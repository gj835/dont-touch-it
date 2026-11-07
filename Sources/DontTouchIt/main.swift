import AppKit

@main
@MainActor
enum DontTouchItApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}
