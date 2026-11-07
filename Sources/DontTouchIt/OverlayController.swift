import AppKit
import CoreGraphics

/// Gesture events are sparse compared with drags, and fingers can pause
/// mid-gesture, so the overlay stays transparent a little longer after the last one.
private let trackpadGestureLingerNanoseconds: UInt64 = 400_000_000

@MainActor
final class OverlayController {
    private var guardWindows: [TouchOverlayWindow] = []
    private let mouseEventMonitor = MouseEventMonitor()
    private var pressedMouseButtons: Set<Int64> = []
    private var restoreMouseTransparencyTask: Task<Void, Never>?
    private var directTouchCount = 0
    private var lastPointerMenuUpdateTimestamp: UInt64 = 0
    private var screenParametersObserver: NSObjectProtocol?
    private var routingStats = InputRoutingStats()
    private var passThroughToggles = 0

    var warningImage: NSImage? {
        didSet {
            guardWindows.forEach { $0.content.showWarning(image: warningImage) }
        }
    }

    var onStateChange: (() -> Void)?
    var onError: ((MouseEventMonitor.StartFailure) -> Void)?

    private(set) var pointerEventCount = 0
    private(set) var lastPointerEvent = "none"

    var isTouchGuardRunning: Bool { !guardWindows.isEmpty }

    func startTouchGuard() {
        stopTouchGuard()
        pointerEventCount = 0
        directTouchCount = 0
        lastPointerMenuUpdateTimestamp = 0
        lastPointerEvent = "waiting"
        routingStats.reset()
        passThroughToggles = 0

        TouchGuardLogger.shared.beginGuard(context: [
            "os=\(ProcessInfo.processInfo.operatingSystemVersionString)",
            "input_monitoring=\(CGPreflightListenEventAccess())",
            "post_event_access=\(CGPreflightPostEventAccess())"
        ])
        TouchGuardLogger.shared.record("mouse event tap starting")

        mouseEventMonitor.onMouseEvent = { [weak self] type, event in
            self?.handleMouseEvent(type, event: event) ?? false
        }
        mouseEventMonitor.onEventObserved = { [weak self] type, event in
            self?.recordRouting(type, event: event)
        }
        if let failure = mouseEventMonitor.start() {
            TouchGuardLogger.shared.record("mouse event tap start failed: \(failure)")
            TouchGuardLogger.shared.endGuard(summary: "start failed: \(failure)")
            onError?(failure)
            return
        }
        TouchGuardLogger.shared.record("mouse event tap created at session level")

        guardWindows = NSScreen.screens.map { makeGuardWindow(for: $0, ignoresMouseEvents: false) }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildGuardWindows() }
        }
        // The system may adjust a window's frame right after it is shown.
        DispatchQueue.main.async { [weak self] in
            self?.fitGuardWindowsToScreens()
        }
        TouchGuardLogger.shared.record("touch guard active; overlay_count=\(guardWindows.count)")
        onStateChange?()
    }

    private func makeGuardWindow(for screen: NSScreen, ignoresMouseEvents: Bool) -> TouchOverlayWindow {
        let window = TouchOverlayWindow(screen: screen, ignoresMouseEvents: ignoresMouseEvents)
        window.content.showWarning(image: warningImage)
        window.content.onTouchBegan = { [weak self] in
            // Make sure the warning is centered on the visible display before it appears.
            self?.fitGuardWindowsToScreens()
            self?.directTouchCount += 1
            self?.onStateChange?()
        }
        window.content.onTouchEnded = { [weak self] in
            self?.onStateChange?()
        }
        window.orderFrontRegardless()
        return window
    }

    private func fitGuardWindowsToScreens() {
        var corrected = 0
        for window in guardWindows where window.fitToScreen() {
            corrected += 1
        }
        if corrected > 0 {
            TouchGuardLogger.shared.record("overlay frame corrected; windows=\(corrected)")
        }
    }

    private func rebuildGuardWindows() {
        guard !guardWindows.isEmpty else { return }
        let ignoresMouse = guardWindows.first?.ignoresMouseEvents ?? false
        guardWindows.forEach { $0.orderOut(nil) }
        guardWindows = NSScreen.screens.map { makeGuardWindow(for: $0, ignoresMouseEvents: ignoresMouse) }
        TouchGuardLogger.shared.record("display configuration changed; overlay_count=\(guardWindows.count)")
        onStateChange?()
    }

    func stopTouchGuard() {
        let wasActive = !guardWindows.isEmpty || mouseEventMonitor.isRunning
        if wasActive {
            TouchGuardLogger.shared.record(
                "stopping guard; touches=\(directTouchCount), pointer_events=\(pointerEventCount)"
            )
            TouchGuardLogger.shared.record(
                "routing summary: \(routingStats.summary) | pass_through_toggles=\(passThroughToggles)"
            )
        }
        mouseEventMonitor.stop()
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        screenParametersObserver = nil
        restoreMouseTransparencyTask?.cancel()
        restoreMouseTransparencyTask = nil
        pressedMouseButtons.removeAll()
        guardWindows.forEach { $0.orderOut(nil) }
        guardWindows.removeAll()
        if wasActive {
            TouchGuardLogger.shared.endGuard(
                summary: "stopped normally; touches=\(directTouchCount), pointer_events=\(pointerEventCount)"
            )
        }
        onStateChange?()
    }

    func stopAll() {
        stopTouchGuard()
    }

    private func recordRouting(_ type: CGEventType, event: CGEvent) {
        guard !guardWindows.isEmpty else { return }
        let overlayWindowNumbers = Set(guardWindows.map { Int64($0.windowNumber) })
        let overlayIsOpaque = !(guardWindows.first?.ignoresMouseEvents ?? true)
        routingStats.record(
            type,
            event: event,
            overlayWindowNumbers: overlayWindowNumbers,
            overlayIsOpaque: overlayIsOpaque
        )
    }

    private func handleMouseEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        guard !guardWindows.isEmpty else { return false }

        if isTrackpadGesture(type) {
            handleTrackpadGesture(type, event: event)
            return false
        }

        let ignoresMouseBefore = guardWindows.first?.ignoresMouseEvents ?? false

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            pressedMouseButtons.insert(event.getIntegerValueField(.mouseEventButtonNumber))
            setGuardMouseTransparency(true)
            cancelTransparencyRestore()

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            setGuardMouseTransparency(true)
            if pressedMouseButtons.isEmpty {
                scheduleTransparencyRestore()
            } else {
                cancelTransparencyRestore()
                // The initial down event was replayed after the overlay became
                // transparent. Let high-frequency drag events continue through
                // the original event stream instead of delaying and reposting
                // each one, which makes window movement visibly jittery.
                return false
            }

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            pressedMouseButtons.remove(button)
            setGuardMouseTransparency(true)
            if pressedMouseButtons.isEmpty {
                scheduleTransparencyRestore()
            } else {
                cancelTransparencyRestore()
            }

        case .scrollWheel:
            setGuardMouseTransparency(true)
            scheduleTransparencyRestore()
            if ignoresMouseBefore {
                pointerEventCount += 1
                lastPointerEvent = "scroll"
                if lastPointerMenuUpdateTimestamp == 0 ||
                    event.timestamp - lastPointerMenuUpdateTimestamp >= 1_000_000_000 {
                    lastPointerMenuUpdateTimestamp = event.timestamp
                    onStateChange?()
                }
                return false
            }

        case .mouseMoved:
            return false

        default:
            return false
        }

        if isPointerAction(type) {
            pointerEventCount += 1
            lastPointerEvent = eventDescription(type)
            onStateChange?()
        }
        return true
    }

    /// Pinch, rotate, smart zoom, swipe and pressure events are delivered to the
    /// window under the pointer. While the overlay is touch-sensitive it would
    /// swallow them, so keep it transparent for as long as gesture events keep
    /// arriving. The events themselves pass through the original stream.
    private func handleTrackpadGesture(_ type: CGEventType, event: CGEvent) {
        setGuardMouseTransparency(true)
        scheduleTransparencyRestore(after: trackpadGestureLingerNanoseconds)

        guard let description = trackpadGestureDescription(type) else { return }
        pointerEventCount += 1
        lastPointerEvent = description
        if lastPointerMenuUpdateTimestamp == 0 ||
            event.timestamp - lastPointerMenuUpdateTimestamp >= 1_000_000_000 {
            lastPointerMenuUpdateTimestamp = event.timestamp
            onStateChange?()
        }
    }

    private func trackpadGestureDescription(_ type: CGEventType) -> String? {
        switch type.rawValue {
        case 30: "pinch"
        case 18: "rotate"
        case 32: "smart zoom"
        case 31: "swipe"
        default: nil
        }
    }

    private func setGuardMouseTransparency(_ transparent: Bool) {
        let previous = guardWindows.first?.ignoresMouseEvents
        guardWindows.forEach { $0.ignoresMouseEvents = transparent }
        if previous != transparent {
            passThroughToggles += 1
        }
    }

    private func cancelTransparencyRestore() {
        restoreMouseTransparencyTask?.cancel()
        restoreMouseTransparencyTask = nil
    }

    private func scheduleTransparencyRestore(after nanoseconds: UInt64 = 120_000_000) {
        cancelTransparencyRestore()
        restoreMouseTransparencyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, self.pressedMouseButtons.isEmpty else { return }
            self.setGuardMouseTransparency(false)
            self.restoreMouseTransparencyTask = nil
        }
    }

    private func isPointerAction(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
             .otherMouseDragged, .scrollWheel:
            true
        default:
            false
        }
    }

    private func eventDescription(_ type: CGEventType) -> String {
        switch type {
        case .leftMouseDown: "left down"
        case .leftMouseUp: "left up"
        case .rightMouseDown: "right down"
        case .rightMouseUp: "right up"
        case .otherMouseDown: "other down"
        case .otherMouseUp: "other up"
        case .scrollWheel: "scroll"
        default: "pointer event"
        }
    }

}
