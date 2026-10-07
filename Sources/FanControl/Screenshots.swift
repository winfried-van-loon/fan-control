import AppKit
import SwiftUI
import FanKit

/// Renders the README images: `FanControl --screenshots <dir>`.
///
/// Uses a read-only store with its own preferences domain, so it never touches the fans or the
/// user's settings. It collects live readings first (SCREENSHOT_WAIT seconds, default 150) so the
/// history chart has data.
@MainActor
enum Screenshots {
    private static let suite = "com.fancontrol.screenshots"

    static func run(to dir: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1.0, forKey: "refreshInterval")
        let store = FanStore(defaults: defaults, readOnly: true)
        store.start()

        let wait = Double(ProcessInfo.processInfo.environment["SCREENSHOT_WAIT"] ?? "") ?? 150
        print("Collecting \(Int(wait))s of readings…")
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var darkPopover: NSBitmapImageRep?

            for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let appearance = NSAppearance(named: appearanceName)!

                let hero = render(MenuBarHero(store: store, dark: name == "dark").environment(store), appearance: appearance)
                write(withShadow(hero), to: "\(dir)/popover-\(name).png")
                if name == "dark" { darkPopover = render(PopoverCard(store: store).environment(store), appearance: appearance) }

                let window = render(
                    WindowChrome(title: "Fan Control") { DashboardView().environment(store) }
                        .frame(width: 1080, height: 1130),
                    appearance: appearance
                )
                write(withShadow(window), to: "\(dir)/window-\(name).png")

                let settings = render(
                    WindowChrome(title: "Settings", showsGear: false) { SettingsView().environment(store).padding(.vertical, 6) },
                    appearance: appearance
                )
                write(withShadow(settings), to: "\(dir)/settings-\(name).png")
            }

            if let darkPopover {
                let banner = render(Banner(popover: NSImage(cgImage: darkPopover.cgImage!, size: darkPopover.size)), appearance: NSAppearance(named: .darkAqua)!)
                write(banner.cgImage!, to: "\(dir)/banner.png")
            }

            UserDefaults.standard.removePersistentDomain(forName: suite)
            print("Wrote screenshots to \(dir)")
            exit(0)
        }
    }

    // MARK: Rendering

    private static func render<V: View>(_ view: V, appearance: NSAppearance) -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.setFrameSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        appearance.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
        }
        return rep
    }

    /// Pads the image and draws it with a soft drop shadow on a transparent background.
    private static func withShadow(_ rep: NSBitmapImageRep) -> CGImage {
        let image = rep.cgImage!
        let pad = 90
        let width = image.width + pad * 2, height = image.height + pad * 2
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: CGColor(gray: 0, alpha: 0.35))
        ctx.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("  \(path) (\(image.width)×\(image.height))")
    }
}

// MARK: - Scenes

private extension HorizontalAlignment {
    enum StatusItem: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[HorizontalAlignment.center] }
    }
    static let statusItem = HorizontalAlignment(StatusItem.self)
}

/// The popover in a rounded card, as macOS draws it.
private struct PopoverCard: View {
    let store: FanStore

    var body: some View {
        PopoverView(openWindow: {}, quit: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// A slice of desktop: wallpaper, menu bar with the status item highlighted, and the open popover.
private struct MenuBarHero: View {
    let store: FanStore
    let dark: Bool

    private var clock: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM  HH:mm"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .statusItem, spacing: 4) {
            menuBar
            VStack(spacing: 0) {
                Arrow()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 26, height: 11)
                PopoverCard(store: store)
            }
            .alignmentGuide(.statusItem) { d in d[HorizontalAlignment.center] }
            .padding(.bottom, 34)
        }
        .frame(width: 720)
        .background(wallpaper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var menuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text("Finder").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: store.menuBarSymbol)
                Text(store.menuBarText).monospacedDigit()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.16)))
            .alignmentGuide(.statusItem) { d in d[HorizontalAlignment.center] }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(clock)
        }
        .font(.system(size: 13))
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 16)
        .frame(width: 720, height: 28)
        .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.55))
    }

    private var wallpaper: some View {
        LinearGradient(
            colors: dark
                ? [Color(red: 0.07, green: 0.10, blue: 0.24), Color(red: 0.20, green: 0.10, blue: 0.33), Color(red: 0.05, green: 0.24, blue: 0.40)]
                : [Color(red: 0.62, green: 0.78, blue: 0.98), Color(red: 0.82, green: 0.74, blue: 0.96), Color(red: 0.98, green: 0.84, blue: 0.78)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

private struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// A plain macOS-style window frame (title bar with traffic lights) around content.
private struct WindowChrome<Content: View>: View {
    var title: String
    var showsGear = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                    Spacer()
                    if showsGear {
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 12)
                .padding(.horizontal, 18)
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
    }
}

/// README banner: icon, name, tagline and the popover.
private struct Banner: View {
    let popover: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.16, blue: 0.42), Color(red: 0.07, green: 0.42, blue: 0.86)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            // Soft glow behind the popover
            RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 320)
                .frame(width: 640, height: 640)
                .offset(x: 640, y: -140)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 84, height: 84)
                        Text("Fan Control")
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                    }
                    Text("Live temperatures and full fan control,\nright in your Mac's menu bar.")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(3)
                    HStack(spacing: 8) {
                        ForEach(["Presets", "Per-fan control", "Target temperature", "Every sensor"], id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 64)
                Spacer(minLength: 0)
            }
            .frame(height: 400)

            Image(nsImage: popover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 330)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .offset(x: 800, y: 46)
        }
        .frame(width: 1200, height: 400, alignment: .topLeading)
        .clipped()
    }
}
