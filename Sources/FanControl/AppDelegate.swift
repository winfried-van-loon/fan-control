import AppKit
import SwiftUI
import FanKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = FanStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--login-item") {
            LoginItem.runCommand(i + 1 < args.count ? args[i + 1] : "status")
        }
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            Screenshots.run(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(store: store, to: args[i + 1])
            return
        }
        buildMainMenu()
        handleTerminationSignals()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Fan Control")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView:
            PopoverView(
                openWindow: { [weak self] in self?.showWindow() },
                quit: { NSApp.terminate(nil) }
            )
            .environment(store)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        store.onChange = { [weak self] in self?.updateStatusItem() }
        store.start()
        updateStatusItem()
    }

    private var signalSources: [DispatchSourceSignal] = []

    /// Treat `kill`/`pkill` (SIGTERM) and Ctrl-C like a normal quit, so the fans are handed back to Auto.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.restoreAutoIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Status item

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = NSAttributedString(string: " " + store.menuBarText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .baselineOffset: 0.5,
        ])
        let symbol = store.menuBarSymbol
        if button.image?.accessibilityDescription != symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
            button.image?.isTemplate = true
        }
        let temp = store.menuBarTemperature.map { store.formatTemperature($0) } ?? "—"
        button.toolTip = "\(store.menuBarSensorLabel) \(temp)\n\(store.fanStatusDescription)"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refreshHelperStatus()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        for preset in store.allPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPresetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = store.activePresetID == preset.id ? .on : .off
            item.image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)
            item.isEnabled = store.canControl
            menu.addItem(item)
        }
        let target = NSMenuItem(title: "Hold \(store.formatTemperature(store.targetTemperature))", action: #selector(toggleTargetFromMenu), keyEquivalent: "")
        target.target = self
        target.state = store.targetModeEnabled ? .on : .off
        target.image = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)
        target.isEnabled = store.canControl
        menu.addItem(.separator())
        menu.addItem(target)
        menu.addItem(.separator())
        let display = NSMenuItem(title: "Fan Speed in Menu Bar", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        for option in MenuBarFanDisplay.allCases {
            let item = NSMenuItem(title: option.label, action: #selector(setFanDisplayFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = store.menuBarFanDisplay == option ? .on : .off
            displayMenu.addItem(item)
        }
        displayMenu.addItem(.separator())
        let showMode = NSMenuItem(title: "Show Fan Mode", action: #selector(toggleShowModeFromMenu), keyEquivalent: "")
        showMode.target = self
        showMode.state = store.menuBarShowsMode ? .on : .off
        displayMenu.addItem(showMode)
        display.submenu = displayMenu
        menu.addItem(display)

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: "Open Fan Control…", action: #selector(openWindowFromMenu), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Quit Fan Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func applyPresetFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let preset = store.allPresets.first(where: { $0.id == id }) else { return }
        store.applyPreset(preset)
    }

    @objc private func toggleTargetFromMenu() { store.setTargetMode(!store.targetModeEnabled) }

    @objc private func setFanDisplayFromMenu(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let option = MenuBarFanDisplay(rawValue: raw) {
            store.menuBarFanDisplay = option
        }
    }

    @objc private func toggleShowModeFromMenu() { store.menuBarShowsMode.toggle() }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            store.notice = "Couldn't change Start at Login: \(error.localizedDescription)"
        }
    }

    @objc private func openWindowFromMenu() { showWindow() }

    // MARK: Window

    func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let hosting = NSHostingController(rootView: DashboardView().environment(store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Fan Control"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 980, height: 720))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("FanControlDashboard")
            self.window = window
        }
        store.refreshHelperStatus()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a pure menu bar app once the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Fan Control", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Fan Control", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Fan Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
