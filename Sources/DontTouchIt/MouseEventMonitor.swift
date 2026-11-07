import AppKit
import CoreGraphics

private let delayedRepostMarker: Int64 = 0x44544952
private let mouseEventRepostDelayMilliseconds: Int = 30

/// Trackpad gesture events (NSEventType raw values: rotate, gesture, magnify,
/// swipe, smartMagnify, pressure). CGEventType does not name them, so they are
/// listed by raw value. Begin/end gesture events are no longer delivered.
let trackpadGestureEventTypes: [UInt32] = [18, 29, 30, 31, 32, 34]

func isTrackpadGesture(_ type: CGEventType) -> Bool {
    trackpadGestureEventTypes.contains(type.rawValue)
}

@MainActor
final class MouseEventMonitor {
    enum StartFailure: Equatable {
        case inputMonitoring
        case postEventAccess
        case eventTapUnavailable
    }

    var onMouseEvent: ((CGEventType, CGEvent) -> Bool)?
    /// Called for every event a listen-only tap sees after the system has decided
    /// where to route it. Those events carry the window that will receive them.
    var onEventObserved: ((CGEventType, CGEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var routingTap: CFMachPort?
    private var routingRunLoopSource: CFRunLoopSource?
    private var isMouseDownReplayPending = false
    private var latestDragWhileMouseDownPending: CGEvent?
    private var isScrollReplayPending = false
    private var pendingScrollEvents: [CGEvent] = []

    var isRunning: Bool { eventTap != nil }

    func start() -> StartFailure? {
        guard eventTap == nil else { return nil }

        guard CGPreflightListenEventAccess() else {
            TouchGuardLogger.shared.record("Input Monitoring preflight=false; requesting access")
            _ = CGRequestListenEventAccess()
            return .inputMonitoring
        }
        guard CGPreflightPostEventAccess() else {
            TouchGuardLogger.shared.record("Post Event preflight=false; requesting access")
            _ = CGRequestPostEventAccess()
            return .postEventAccess
        }

        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        } | trackpadGestureEventTypes.reduce(CGEventMask(0)) { mask, rawType in
            mask | (CGEventMask(1) << rawType)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mouseEventTapCallback,
            userInfo: context
        ) else {
            TouchGuardLogger.shared.record("CGEvent.tapCreate returned nil")
            return .eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // A second, listen-only tap placed after the system annotates events with
        // their target window. It never changes events and is only used for the
        // routing summary, so failing to create it is not an error.
        if let observer = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: routingTapCallback,
            userInfo: context
        ) {
            let observerSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, observer, 0)
            routingTap = observer
            routingRunLoopSource = observerSource
            CFRunLoopAddSource(CFRunLoopGetMain(), observerSource, .commonModes)
            CGEvent.tapEnable(tap: observer, enable: true)
        } else {
            TouchGuardLogger.shared.record("routing observer tap unavailable")
        }

        return nil
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let routingTap {
            CGEvent.tapEnable(tap: routingTap, enable: false)
        }
        if let routingRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), routingRunLoopSource, .commonModes)
        }
        routingTap = nil
        routingRunLoopSource = nil
        self.eventTap = nil
        runLoopSource = nil
        isMouseDownReplayPending = false
        latestDragWhileMouseDownPending = nil
        isScrollReplayPending = false
        pendingScrollEvents.removeAll()
    }

    fileprivate func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            TouchGuardLogger.shared.record("system disabled event tap: \(type == .tapDisabledByTimeout ? "timeout" : "user input"); re-enabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }
        return onMouseEvent?(type, event) ?? false
    }

    fileprivate func observeRouted(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let routingTap {
                CGEvent.tapEnable(tap: routingTap, enable: true)
            }
            return
        }
        onEventObserved?(type, event)
    }

    fileprivate func beginMouseDownReplay() {
        isMouseDownReplayPending = true
        latestDragWhileMouseDownPending = nil
    }

    fileprivate func queueDragWhileMouseDownPending(_ type: CGEventType, event: CGEvent) -> Bool {
        guard isMouseDownReplayPending, isMouseDragged(type) else { return false }
        latestDragWhileMouseDownPending = event.copy()
        return true
    }

    fileprivate func finishMouseDownReplay() {
        isMouseDownReplayPending = false
        guard let dragEvent = latestDragWhileMouseDownPending else { return }
        latestDragWhileMouseDownPending = nil
        dragEvent.setIntegerValueField(.eventSourceUserData, value: delayedRepostMarker)
        dragEvent.post(tap: .cgSessionEventTap)
    }

    fileprivate func beginScrollReplay() {
        isScrollReplayPending = true
        pendingScrollEvents.removeAll(keepingCapacity: true)
    }

    fileprivate func queueScrollWhileReplayPending(_ type: CGEventType, event: CGEvent) -> Bool {
        guard isScrollReplayPending, type == .scrollWheel, let copy = event.copy() else { return false }
        pendingScrollEvents.append(copy)
        return true
    }

    fileprivate func finishScrollReplay() {
        isScrollReplayPending = false
        let events = pendingScrollEvents
        pendingScrollEvents.removeAll(keepingCapacity: true)
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: delayedRepostMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

private func mouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    if event.getIntegerValueField(.eventSourceUserData) == delayedRepostMarker {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    if MainActor.assumeIsolated({ monitor.queueScrollWhileReplayPending(type, event: event) }) {
        return nil
    }
    if MainActor.assumeIsolated({ monitor.queueDragWhileMouseDownPending(type, event: event) }) {
        return nil
    }
    let shouldRepost = MainActor.assumeIsolated {
        monitor.handle(type, event: event)
    }
    guard shouldRepost else { return Unmanaged.passUnretained(event) }

    guard let repostedEvent = event.copy() else {
        TouchGuardLogger.shared.record("input event copy failed; original event passed through")
        return Unmanaged.passUnretained(event)
    }

    if isMouseDown(type) {
        MainActor.assumeIsolated {
            monitor.beginMouseDownReplay()
        }
    }
    if type == .scrollWheel {
        MainActor.assumeIsolated {
            monitor.beginScrollReplay()
        }
    }
    repostedEvent.setIntegerValueField(.eventSourceUserData, value: delayedRepostMarker)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(mouseEventRepostDelayMilliseconds)) {
        repostedEvent.post(tap: .cgSessionEventTap)
        if isMouseDown(type) {
            MainActor.assumeIsolated {
                monitor.finishMouseDownReplay()
            }
        }
        if type == .scrollWheel {
            MainActor.assumeIsolated {
                monitor.finishScrollReplay()
            }
        }
    }
    return nil
}

/// Listen-only callback for the annotated session tap. Events are passed on untouched.
private func routingTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.observeRouted(type, event: event) }
    }
    return Unmanaged.passUnretained(event)
}

private func isMouseDown(_ type: CGEventType) -> Bool {
    type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
}

private func isMouseDragged(_ type: CGEventType) -> Bool {
    type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
}
