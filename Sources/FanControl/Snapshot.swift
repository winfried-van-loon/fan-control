import AppKit
import SwiftUI

/// Debug aid: `FanControl --snapshot <dir>` renders the popover and dashboard to PNGs, then exits.
@MainActor
enum Snapshot {
    static func run(store: FanStore, to dir: String) {
        store.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            render(PopoverView(openWindow: {}, quit: {}).environment(store), size: nil, to: "\(dir)/popover.png")
            render(DashboardView().environment(store), size: NSSize(width: 980, height: 760), to: "\(dir)/dashboard.png")
            render(SettingsView().environment(store), size: nil, to: "\(dir)/settings.png")
            let original = store.menuBarFanDisplay // the setting persists, so put it back afterwards
            for option in MenuBarFanDisplay.allCases {
                store.menuBarFanDisplay = option
                print("menu bar [\(option.label)]: \(store.menuBarSymbol) \(store.menuBarText)")
            }
            store.menuBarFanDisplay = original
            exit(0)
        }
    }

    private static func render<V: View>(_ view: V, size: NSSize?, to path: String) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
