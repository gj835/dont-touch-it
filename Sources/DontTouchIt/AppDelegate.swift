import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let overlayController = OverlayController()
    private var statusItem: NSStatusItem!
    private var guardMenuItem: NSMenuItem!
    private var pointerStatusMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let imagePath = defaults.string(forKey: PreferenceKey.warningImagePath) {
            overlayController.warningImage = NSImage(contentsOfFile: imagePath)
        }

        overlayController.onStateChange = { [weak self] in
            self?.updateMenuState()
        }
        overlayController.onError = { [weak self] failure in
            self?.presentPermissionGuide(for: failure)
        }

        configureStatusItem()
        if !CGPreflightListenEventAccess() {
            presentInputMonitoringGuide()
        } else if !CGPreflightPostEventAccess() {
            presentPermissionGuide(for: .postEventAccess)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.stopAll()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Don't Touch It")
            button.toolTip = "Don't Touch It"
        }

        let menu = NSMenu()

        guardMenuItem = NSMenuItem(title: "Start Touch Guard", action: #selector(toggleTouchGuard), keyEquivalent: "g")
        guardMenuItem.target = self
        menu.addItem(guardMenuItem)

        menu.addItem(NSMenuItem(title: "Choose Warning Image…", action: #selector(chooseWarningImage), keyEquivalent: "i").configured(target: self))
        menu.addItem(.separator())

        pointerStatusMenuItem = NSMenuItem(title: "Pointer events: idle", action: nil, keyEquivalent: "")
        pointerStatusMenuItem.isEnabled = false
        menu.addItem(pointerStatusMenuItem)
        menu.addItem(NSMenuItem(title: "Reveal Touch Guard Log…", action: #selector(revealTouchGuardLog), keyEquivalent: "").configured(target: self))
        menu.addItem(NSMenuItem(title: "Clear Touch Guard Log…", action: #selector(clearTouchGuardLog), keyEquivalent: "").configured(target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Don't Touch It", action: #selector(quit), keyEquivalent: "q").configured(target: self))

        statusItem.menu = menu
        updateMenuState()
    }

    @objc private func toggleTouchGuard() {
        if overlayController.isTouchGuardRunning {
            overlayController.stopTouchGuard()
        } else {
            overlayController.startTouchGuard()
        }
        updateMenuState()
    }

    @objc private func chooseWarningImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Image"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: PreferenceKey.warningImagePath)
        overlayController.warningImage = NSImage(contentsOf: url)
    }

    @objc private func revealTouchGuardLog() {
        TouchGuardLogger.shared.revealLogInFinder()
    }

    @objc private func clearTouchGuardLog() {
        let alert = NSAlert()
        alert.messageText = "Clear Touch Guard Log?"
        alert.informativeText = "This permanently deletes the local diagnostic log."
        alert.addButton(withTitle: "Clear Log")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try TouchGuardLogger.shared.clear()
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Couldn’t Clear the Log"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.runModal()
        }
    }

    @objc private func quit() {
        overlayController.stopAll()
        NSApp.terminate(nil)
    }

    private func updateMenuState() {
        guardMenuItem?.title = overlayController.isTouchGuardRunning ? "Stop Touch Guard" : "Start Touch Guard"
        if overlayController.isTouchGuardRunning {
            pointerStatusMenuItem?.title = "Pointer events: \(overlayController.pointerEventCount) (last: \(overlayController.lastPointerEvent))"
        } else {
            pointerStatusMenuItem?.title = "Pointer events: idle"
        }
    }

    private func presentInputMonitoringGuide() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Needed"
        alert.informativeText = "Touch Guard needs Input Monitoring to briefly make its overlay transparent while a mouse or trackpad button is pressed. Allow Don't Touch It in System Settings > Privacy & Security > Input Monitoring, then quit and reopen the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Input Monitoring Settings")
        alert.addButton(withTitle: "Quit App")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!
            openSettingsAndQuit(settingsURL)
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func presentPermissionGuide(for failure: MouseEventMonitor.StartFailure) {
        let alert = NSAlert()
        let settingsURL: URL
        switch failure {
        case .inputMonitoring:
            alert.messageText = "Input Monitoring Permission Needed"
            alert.informativeText = "Allow Don't Touch It in System Settings > Privacy & Security > Input Monitoring, then quit and reopen the app."
            settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!
        case .postEventAccess:
            alert.messageText = "Accessibility Permission Needed"
            alert.informativeText = "Touch Guard needs permission to replay mouse events through macOS so the window underneath receives them. Allow Don't Touch It in System Settings > Privacy & Security > Accessibility, then quit and reopen the app."
            settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        case .eventTapUnavailable:
            alert.messageText = "Mouse Event Monitor Unavailable"
            alert.informativeText = "macOS could not start the mouse event monitor. Check Input Monitoring and Accessibility, then relaunch the app."
            settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings & Quit")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openSettingsAndQuit(settingsURL)
        }
    }

    private func openSettingsAndQuit(_ settingsURL: URL) {
        if !NSWorkspace.shared.open(settingsURL) {
            let settingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            NSWorkspace.shared.open(settingsAppURL)
        }
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    func configured(target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}

private enum PreferenceKey {
    static let warningImagePath = "warningImagePath"
}
