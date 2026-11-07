// Input probe: a stand-in for "the app underneath" Touch Guard.
//
// Run it twice, once with Touch Guard stopped (baseline) and once with Touch
// Guard started, then perform each action over the window. A row turns green
// once the window has received that kind of input, so any row that works in
// the baseline but stays empty under Touch Guard is an input that the guard
// breaks.
//
//     swift Scripts/input-probe.swift
//
// Press R to reset the counters, Q to quit. It only reads the events its own
// window receives; it does not record or send anything.
import AppKit

struct Check {
    let key: String
    let title: String
    let hint: String
}

let checks: [Check] = [
    Check(key: "move", title: "Mouse/trackpad move", hint: "move the pointer over the window"),
    Check(key: "enter", title: "Hover enter/exit", hint: "move in and out of the window"),
    Check(key: "left", title: "Left click", hint: "click"),
    Check(key: "double", title: "Double click", hint: "double click"),
    Check(key: "right", title: "Right click / two-finger click", hint: "secondary click"),
    Check(key: "other", title: "Middle / extra button", hint: "mouse only"),
    Check(key: "drag", title: "Drag", hint: "press, move, release"),
    Check(key: "scroll", title: "Scroll", hint: "two-finger scroll or wheel"),
    Check(key: "hscroll", title: "Horizontal scroll", hint: "two-finger sideways scroll"),
    Check(key: "momentum", title: "Scroll momentum", hint: "flick, then let go"),
    Check(key: "magnify", title: "Pinch zoom", hint: "two-finger pinch"),
    Check(key: "rotate", title: "Rotate", hint: "two-finger rotate"),
    Check(key: "smart", title: "Smart zoom", hint: "two-finger double tap"),
    Check(key: "swipe", title: "Swipe", hint: "two or three-finger swipe (if enabled)"),
    Check(key: "pressure", title: "Force click / pressure", hint: "press firmly"),
]

@MainActor
final class ProbeView: NSView {
    private var counts: [String: Int] = [:]
    private var details: [String: String] = [:]
    private var magnifyPhases: [String] = []
    private let report = NSTextField(labelWithString: "")
    private var lastInfo = "Waiting for input…"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        report.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        report.maximumNumberOfLines = 0
        report.translatesAutoresizingMaskIntoConstraints = false
        addSubview(report)
        NSLayoutConstraint.activate([
            report.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            report.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            report.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // The cursor over this window should be a crosshair. If it stays an arrow
    // while the pointer is over the window, cursor updates are not reaching it.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func hit(_ key: String, _ detail: String? = nil) {
        counts[key, default: 0] += 1
        if let detail { details[key] = detail }
        lastInfo = "last: \(key)\(detail.map { " (\($0))" } ?? "")"
        refresh()
    }

    func reset() {
        counts.removeAll()
        details.removeAll()
        magnifyPhases.removeAll()
        lastInfo = "Counters reset."
        refresh()
    }

    private func refresh() {
        var lines = ["INPUT PROBE — green = received, empty = never received", ""]
        for check in checks {
            let n = counts[check.key, default: 0]
            let mark = n > 0 ? "✅" : "⬜️"
            var line = "\(mark) \(check.title.padding(toLength: 32, withPad: " ", startingAt: 0)) \(String(format: "%5d", n))"
            if let d = details[check.key] { line += "  \(d)" }
            else if n == 0 { line += "  (\(check.hint))" }
            lines.append(line)
        }
        lines.append("")
        if !magnifyPhases.isEmpty {
            lines.append("pinch phases: \(magnifyPhases.suffix(12).joined(separator: " "))")
        }
        lines.append(lastInfo)
        lines.append("")
        lines.append("Cursor over this window should be a crosshair.   R = reset   Q = quit")
        report.stringValue = lines.joined(separator: "\n")
    }

    private func phaseName(_ phase: NSEvent.Phase) -> String {
        if phase.contains(.began) { return "began" }
        if phase.contains(.changed) { return "changed" }
        if phase.contains(.ended) { return "ended" }
        if phase.contains(.cancelled) { return "cancelled" }
        if phase.contains(.mayBegin) { return "mayBegin" }
        if phase.contains(.stationary) { return "stationary" }
        return "none"
    }

    override func mouseMoved(with event: NSEvent) { hit("move") }
    override func mouseEntered(with event: NSEvent) { hit("enter", "entered") }
    override func mouseExited(with event: NSEvent) { hit("enter", "exited") }
    override func mouseDown(with event: NSEvent) {
        hit("left")
        if event.clickCount >= 2 { hit("double") }
    }
    override func mouseDragged(with event: NSEvent) { hit("drag") }
    override func rightMouseDown(with event: NSEvent) { hit("right") }
    override func otherMouseDown(with event: NSEvent) { hit("other", "button \(event.buttonNumber)") }
    override func scrollWheel(with event: NSEvent) {
        hit("scroll", "phase \(phaseName(event.phase)) / momentum \(phaseName(event.momentumPhase))")
        if event.scrollingDeltaX != 0 { hit("hscroll") }
        if event.momentumPhase != [] { hit("momentum") }
    }
    override func magnify(with event: NSEvent) {
        let name = phaseName(event.phase)
        if magnifyPhases.last != name { magnifyPhases.append(name) }
        hit("magnify", "magnification \(String(format: "%+.3f", event.magnification))")
    }
    override func rotate(with event: NSEvent) { hit("rotate", "rotation \(String(format: "%+.1f", event.rotation))") }
    override func smartMagnify(with event: NSEvent) { hit("smart") }
    override func swipe(with event: NSEvent) { hit("swipe", "dx \(event.deltaX) dy \(event.deltaY)") }
    override func pressureChange(with event: NSEvent) { hit("pressure", "stage \(event.stage)") }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r": reset()
        case "q": NSApp.terminate(nil)
        default: break
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Input Probe"
    let view = ProbeView(frame: window.contentLayoutRect)
    window.contentView = view
    window.acceptsMouseMovedEvents = true
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    app.activate()
    app.run()
}
