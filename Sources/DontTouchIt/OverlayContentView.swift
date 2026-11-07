import AppKit

@MainActor
final class OverlayContentView: NSView {
    private let messageLabel = NSTextField(labelWithString: "Don't Touch It!")

    var onTouchBegan: (() -> Void)?
    var onTouchEnded: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 52, weight: .bold)
        messageLabel.textColor = .white
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        installTouchRecognizer()
        setWarningVisible(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installTouchRecognizer() {
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.allowedTouchTypes = .direct
        press.buttonMask = 0
        press.minimumPressDuration = 0.001
        press.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(press)
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setWarningVisible(true)
            onTouchBegan?()
        case .ended, .cancelled, .failed:
            setWarningVisible(false)
            onTouchEnded?()
        default:
            break
        }
    }

    private func setWarningVisible(_ visible: Bool) {
        messageLabel.isHidden = !visible
        layer?.backgroundColor = visible ? NSColor.systemRed.cgColor : NSColor.clear.cgColor
    }
}
