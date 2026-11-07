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
    private var useDefaultWarningMenuItem: NSMenuItem!
    private var usageDiagnosticsMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // On by default while the app is in development; the menu item turns it off.
        overlayController.usageDiagnosticsEnabled =
            defaults.object(forKey: PreferenceKey.usageDiagnosticsEnabled) as? Bool ?? true
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
        presentUsageDiagnosticsNoticeIfNeeded()
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
        menu.autoenablesItems = false

        guardMenuItem = NSMenuItem(title: "Start Touch Guard", action: #selector(toggleTouchGuard), keyEquivalent: "g")
        guardMenuItem.target = self
        menu.addItem(guardMenuItem)

        menu.addItem(NSMenuItem(title: "Choose Warning Image…", action: #selector(chooseWarningImage), keyEquivalent: "i").configured(target: self))
        useDefaultWarningMenuItem = NSMenuItem(title: "Use Default Warning", action: #selector(useDefaultWarning), keyEquivalent: "")
        useDefaultWarningMenuItem.target = self
        menu.addItem(useDefaultWarningMenuItem)
        menu.addItem(.separator())

        pointerStatusMenuItem = NSMenuItem(title: "Pointer events: idle", action: nil, keyEquivalent: "")
        pointerStatusMenuItem.isEnabled = false
        menu.addItem(pointerStatusMenuItem)
        usageDiagnosticsMenuItem = NSMenuItem(title: "Record Usage Diagnostics", action: #selector(toggleUsageDiagnostics), keyEquivalent: "")
        usageDiagnosticsMenuItem.target = self
        menu.addItem(usageDiagnosticsMenuItem)
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
        updateMenuState()
    }

    @objc private func useDefaultWarning() {
        defaults.removeObject(forKey: PreferenceKey.warningImagePath)
        overlayController.warningImage = nil
        updateMenuState()
    }

    @objc private func toggleUsageDiagnostics() {
        if overlayController.usageDiagnosticsEnabled {
            setUsageDiagnostics(enabled: false)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Record Usage Diagnostics?"
        alert.informativeText = Self.usageDiagnosticsDescription + "\n\nTakes effect the next time Touch Guard starts."
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setUsageDiagnostics(enabled: true)
    }

    private static let usageDiagnosticsDescription = """
        While Touch Guard runs, the local log also records: your Mac model \
        identifier, macOS version, number of displays, the type of any touch \
        hardware, counts of touches and of mouse or trackpad activity, and how \
        soon touches arrived after mouse or trackpad use.

        It never records where you touch or click, what you type, or any window, \
        app or file names. Nothing is sent anywhere. If you want to help improve \
        the app, you can share the log yourself (Reveal Touch Guard Log…).
        """

    /// Diagnostics are on by default, so say so once, and offer to turn them off.
    private func presentUsageDiagnosticsNoticeIfNeeded() {
        guard !defaults.bool(forKey: PreferenceKey.usageDiagnosticsNoticeShown) else { return }
        defaults.set(true, forKey: PreferenceKey.usageDiagnosticsNoticeShown)
        guard overlayController.usageDiagnosticsEnabled else { return }

        let alert = NSAlert()
        alert.messageText = "Usage Diagnostics Are On"
        alert.informativeText = Self.usageDiagnosticsDescription
            + "\n\nYou can turn this off any time with Record Usage Diagnostics in the menu bar menu."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Turn Off")
        if alert.runModal() == .alertSecondButtonReturn {
            setUsageDiagnostics(enabled: false)
        }
    }

    private func setUsageDiagnostics(enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKey.usageDiagnosticsEnabled)
        overlayController.usageDiagnosticsEnabled = enabled
        updateMenuState()
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
        useDefaultWarningMenuItem?.isEnabled = overlayController.warningImage != nil
        usageDiagnosticsMenuItem?.state = overlayController.usageDiagnosticsEnabled ? .on : .off
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
    static let usageDiagnosticsEnabled = "usageDiagnosticsEnabled"
    static let usageDiagnosticsNoticeShown = "usageDiagnosticsNoticeShown"
}
