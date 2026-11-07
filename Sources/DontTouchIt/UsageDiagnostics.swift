import AppKit
import Foundation
import IOKit.hid

// Opt-in usage diagnostics. When enabled, each Touch Guard session adds a few
// lines to the existing log so people running the app on touch-screen Macs can
// share what happened without sharing anything personal.
//
// Only counts and hardware categories are recorded: no coordinates, window or
// application names, process ids, key presses, or serial numbers. Nothing is
// sent anywhere; the person decides whether to share the log file.

/// Counts touches and how they relate to mouse and trackpad activity.
///
/// Two independent views of touch are kept so they can be compared:
/// - `hidContacts`: fingers reported by the touch-screen hardware itself, whether
///   or not the overlay was able to receive them.
/// - `overlayTouches`: touches the overlay window actually caught.
/// A contact that arrives while the overlay is transparent to the pointer is a
/// touch the app could not catch.
struct UsageSessionStats {
    enum Recency: CaseIterable {
        case under150ms, under500ms, under2s, older, none

        var label: String {
            switch self {
            case .under150ms: "lt150ms"
            case .under500ms: "lt500ms"
            case .under2s: "lt2s"
            case .older: "ge2s"
            case .none: "no_pointer"
            }
        }
    }

    /// Mouse events a touch itself causes (such as the cursor jumping to the
    /// finger) reach the event tap just after the contact. They are not treated as
    /// separate pointer activity, or every later touch would look like it followed
    /// a mouse event.
    private static let touchInducedQuietNanoseconds: UInt64 = 250_000_000

    private(set) var hidContacts = 0
    private(set) var otherDigitizerContacts = 0
    private(set) var contactsWhileTransparent = 0
    private(set) var overlayTouches = 0
    private var contactsByRecency: [Recency: Int] = [:]
    private var lastPointerActivity: UInt64?
    private var lastContact: UInt64?

    mutating func reset() {
        self = UsageSessionStats()
    }

    mutating func pointerActivity(at now: UInt64) {
        if let lastContact, now >= lastContact, now - lastContact < Self.touchInducedQuietNanoseconds {
            return
        }
        lastPointerActivity = now
    }

    mutating func touchScreenContact(at now: UInt64, overlayIsTransparent: Bool) {
        hidContacts += 1
        if overlayIsTransparent {
            contactsWhileTransparent += 1
        }
        contactsByRecency[recency(at: now), default: 0] += 1
        lastContact = now
    }

    mutating func otherDigitizerContact() {
        otherDigitizerContacts += 1
    }

    mutating func overlayTouchBegan() {
        overlayTouches += 1
    }

    private func recency(at now: UInt64) -> Recency {
        guard let lastPointerActivity, now >= lastPointerActivity else { return .none }
        switch now - lastPointerActivity {
        case ..<150_000_000: return .under150ms
        case ..<500_000_000: return .under500ms
        case ..<2_000_000_000: return .under2s
        default: return .older
        }
    }

    /// One line, for example:
    /// `duration_s=84 hid_contacts=12 overlay_touches=11 contacts_while_transparent=1 other_digitizer_contacts=0 contact_after_pointer lt150ms=0 lt500ms=1 lt2s=0 ge2s=4 no_pointer=7`
    func summary(durationSeconds: Int) -> String {
        let recencyParts = Recency.allCases.map { "\($0.label)=\(contactsByRecency[$0, default: 0])" }
        return "duration_s=\(durationSeconds) hid_contacts=\(hidContacts) overlay_touches=\(overlayTouches) "
            + "contacts_while_transparent=\(contactsWhileTransparent) other_digitizer_contacts=\(otherDigitizerContacts) "
            + "contact_after_pointer \(recencyParts.joined(separator: " "))"
    }
}

/// Watches digitizer (touch) hardware through IOHIDManager and reports each new
/// finger contact. This works even while the overlay is transparent, so it shows
/// touches the overlay could not catch.
///
/// Matches the HID Digitizer usage page. Contacts are counted from devices whose
/// primary usage is Touch Screen; contacts from any other digitizer (a pen
/// tablet, say) are reported separately.
@MainActor
final class TouchScreenMonitor {
    private static let digitizerUsagePage = 0x0D
    private static let touchScreenUsage = 0x04
    private static let tipSwitchUsage = 0x42

    private struct ElementKey: Hashable {
        let device: UInt
        let cookie: UInt32
    }

    /// Called for every new finger contact. The flag is true for a touch screen.
    var onContactBegan: ((_ isTouchScreen: Bool) -> Void)?

    private var manager: IOHIDManager?
    private var lastTipSwitch: [ElementKey: Int] = [:]

    /// Digitizer devices present at start, described only by usage and transport.
    private(set) var deviceDescriptions: [String] = []

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: Self.digitizerUsagePage] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, touchScreenValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            deviceDescriptions = ["unavailable"]
            return
        }
        self.manager = manager
        lastTipSwitch.removeAll()

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        deviceDescriptions = devices.map { device in
            let usage = Self.primaryUsage(of: device)
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "unknown"
            return "primary_usage=\(usage) transport=\(transport)"
        }.sorted()
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        lastTipSwitch.removeAll()
    }

    fileprivate func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(Self.digitizerUsagePage),
              IOHIDElementGetUsage(element) == UInt32(Self.tipSwitchUsage) else { return }

        let device = IOHIDElementGetDevice(element)
        let key = ElementKey(
            device: UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()),
            cookie: IOHIDElementGetCookie(element)
        )
        let down = IOHIDValueGetIntegerValue(value) != 0 ? 1 : 0
        let wasDown = lastTipSwitch[key, default: 0]
        lastTipSwitch[key] = down
        guard down == 1, wasDown == 0 else { return }

        onContactBegan?(Self.primaryUsage(of: device) == Self.touchScreenUsage)
    }

    private static func primaryUsage(of device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? -1
    }
}

private func touchScreenValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let monitor = Unmanaged<TouchScreenMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.handle(value) }
}

enum UsageDiagnostics {
    /// Hardware model identifier such as `Mac16,6`. Not a serial number.
    static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    /// One line describing the machine, for example
    /// `model=Mac16,6 os=Version 27.2 displays=1 digitizers=[primary_usage=4 transport=USB]`.
    @MainActor
    static func environmentLine(digitizers: [String]) -> String {
        let list = digitizers.isEmpty ? "none" : digitizers.map { "[\($0)]" }.joined(separator: ",")
        return "model=\(modelIdentifier()) os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
            + "displays=\(NSScreen.screens.count) digitizers=\(list)"
    }
}
