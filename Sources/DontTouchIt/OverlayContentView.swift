import AppKit

@MainActor
final class OverlayContentView: NSView {
    private let imageView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "Don't touch it")
    private var isTouchActive = false
    private var warningImage: NSImage?

    var onTouchBegan: (() -> Void)?
    var onTouchEnded: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 52, weight: .bold)
        messageLabel.textColor = .white
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        installTouchRecognizer()
        setWarningVisible(false, image: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWarning(image: NSImage?) {
        warningImage = image
        setWarningVisible(isTouchActive, image: image)
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
            isTouchActive = true
            setWarningVisible(true, image: warningImage)
            onTouchBegan?()
        case .ended, .cancelled, .failed:
            isTouchActive = false
            setWarningVisible(false, image: nil)
            onTouchEnded?()
        default:
            break
        }
    }

    private func setWarningVisible(_ visible: Bool, image: NSImage?) {

        if visible {
            if let image {
                imageView.image = image
                imageView.isHidden = false
                messageLabel.isHidden = true
                layer?.backgroundColor = NSColor.black.cgColor
            } else {
                imageView.image = nil
                imageView.isHidden = true
                messageLabel.stringValue = "Don't touch it"
                messageLabel.textColor = .white
                messageLabel.font = .systemFont(ofSize: 52, weight: .bold)
                messageLabel.isHidden = false
                layer?.backgroundColor = NSColor.systemRed.cgColor
            }
        } else {
            imageView.image = nil
            imageView.isHidden = true
            messageLabel.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
