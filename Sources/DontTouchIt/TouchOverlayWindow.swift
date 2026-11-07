import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
final class TouchOverlayWindow: NSPanel {
    let content: OverlayContentView
    private let displayID: CGDirectDisplayID?

    init(screen: NSScreen, ignoresMouseEvents: Bool) {
        self.content = OverlayContentView(frame: screen.frame)
        self.displayID = screen.displayID

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.ignoresMouseEvents = ignoresMouseEvents
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resizes the window to exactly cover its display. The system can change a
    /// borderless window's frame after creation (for example on a Sidecar
    /// display), which would move the centered warning off the visible screen.
    /// Returns true when the frame had to be corrected.
    @discardableResult
    func fitToScreen() -> Bool {
        guard let displayID,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              frame != screen.frame else { return false }
        setFrame(screen.frame, display: true)
        return true
    }
}
