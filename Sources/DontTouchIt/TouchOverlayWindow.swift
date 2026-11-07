import AppKit

@MainActor
final class TouchOverlayWindow: NSPanel {
    let content: OverlayContentView

    init(screen: NSScreen, ignoresMouseEvents: Bool) {
        self.content = OverlayContentView(frame: screen.frame)

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


}
