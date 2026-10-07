import SwiftUI
import FanKit

extension Color {
    static func temperature(_ celsius: Double) -> Color {
        switch celsius {
        case ..<45: return Color(red: 0.20, green: 0.70, blue: 0.95)
        case ..<60: return Color(red: 0.25, green: 0.78, blue: 0.45)
        case ..<75: return Color(red: 0.96, green: 0.75, blue: 0.15)
        case ..<88: return Color(red: 0.98, green: 0.50, blue: 0.15)
        default: return Color(red: 0.93, green: 0.23, blue: 0.20)
        }
    }
}

/// A fan glyph that spins faster the faster the fan turns.
struct SpinningFan: View {
    var rpm: Double
    var size: CGFloat = 18
    var tint: Color = .accentColor

    var body: some View {
        // Speed is bucketed so the animation only restarts on noticeable changes.
        let bucket = rpm > 0 ? Int(max(800, min(6000, rpm)) / 400) : 0
        Spinner(period: bucket == 0 ? 0 : 2.4 - (Double(bucket) * 400 - 800) / 5200 * 2.05, size: size, tint: tint)
            .id(bucket)
            .frame(width: size * 1.3, height: size * 1.3)
    }

    private struct Spinner: View {
        var period: Double
        var size: CGFloat
        var tint: Color
        @State private var spinning = false

        var body: some View {
            Image(systemName: "fan.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .onAppear {
                    guard period > 0 else { return }
                    withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { spinning = true }
                }
        }
    }
}

struct RingGauge<Center: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * max(0.001, min(1, fraction)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: fraction)
            center
        }
    }
}

struct PresetButton: View {
    var preset: Preset
    var isActive: Bool
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: compact ? 14 : 17, weight: .medium))
                    .frame(height: compact ? 16 : 20)
                Text(preset.name)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 7 : 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(preset.isBuiltIn ? presetHelp : "Custom preset")
    }

    private var presetHelp: String {
        switch preset.id {
        case "auto": return "Let macOS control the fans"
        case "full": return "All fans at maximum speed"
        default:
            let pct = Int((preset.levels.first.flatMap { $0 } ?? 0) * 100)
            return "All fans at \(pct)% of their range"
        }
    }
}

struct ModeBadge: View {
    var manual: Bool
    var target: Bool = false

    private var color: Color { target ? .purple : (manual ? .orange : .green) }

    var body: some View {
        Text(target ? "TARGET" : (manual ? "MANUAL" : "AUTO"))
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}

/// Toggle + setpoint for "hold a target temperature" mode.
struct TargetControl: View {
    @Environment(FanStore.self) private var store
    var compact: Bool = false

    var body: some View {
        @Bindable var store = store
        let enabled = store.targetModeEnabled
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(enabled ? Color.purple : .secondary)
                Toggle(isOn: Binding(get: { enabled }, set: { store.setTargetMode($0) })) {
                    Text(compact ? "Hold temperature" : "Hold a target temperature")
                        .font(compact ? .callout.weight(.medium) : .subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                if compact {
                    Stepper(value: $store.targetTemperature, in: 40...90, step: 1) {
                        Text(store.formatTemperature(store.targetTemperature))
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(enabled ? Color.purple : .primary)
                    }
                    .controlSize(.small)
                }
            }
            .disabled(!store.canControl)

            if !compact {
                HStack(spacing: 10) {
                    Text(store.formatTemperature(40)).font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { store.targetTemperature }, set: { store.targetTemperature = $0.rounded() }), in: 40...90)
                        .controlSize(.small)
                    Text(store.formatTemperature(90)).font(.caption2).foregroundStyle(.secondary)
                    Text(store.formatTemperature(store.targetTemperature))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(enabled ? Color.purple : .primary)
                        .frame(width: 58, alignment: .trailing)
                }
                Picker("Sensor", selection: $store.targetSensorKey) {
                    ForEach(store.sensors.sorted { $0.name < $1.name }) { sensor in
                        Text(sensor.name).tag(sensor.key)
                    }
                }
                .controlSize(.small)
            }

            if enabled, let sensor = store.targetSensor {
                let diff = sensor.value - store.targetTemperature
                HStack(spacing: 4) {
                    Text("\(sensor.name) \(store.formatTemperature(sensor.value))")
                    Image(systemName: diff > 1 ? "arrow.down.right" : (diff < -1 ? "checkmark" : "equal"))
                    Text(diff > 1 ? "cooling" : (diff < -1 ? "below target" : "on target"))
                    Spacer()
                    Text("fans \(Int((store.targetOutput * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !compact {
                Text("Fans speed up when the sensor rises above the target and slow back down below it. Thermal safety stays active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HelperBanner: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        if store.helperStatus != .ready {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.helperStatus == .outdated ? "Helper needs an update" : "Fan control needs a helper")
                        .font(.callout.weight(.semibold))
                    Text("Reading temperatures works without it. Changing fan speeds needs a one-time admin approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(store.helperStatus == .outdated ? "Update" : "Install") { store.installHelper() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.25)))
        }
    }
}

struct NoticeBar: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        if let notice = store.notice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { store.notice = nil } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.1)))
        }
    }
}

/// Slider that controls one fan's RPM. Dragging switches the fan to manual.
struct FanSlider: View {
    @Environment(FanStore.self) private var store
    var fan: FanInfo

    var body: some View {
        Slider(
            value: Binding(
                get: { store.displayRPM(for: fan) },
                set: { store.setRPM($0, forFan: fan.index) }
            ),
            in: fan.minimum...max(fan.minimum + 1, fan.maximum)
        )
        .controlSize(.small)
        .disabled(!store.canControl)
    }
}

struct AllFansSlider: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        Slider(
            value: Binding(get: { store.overallFraction }, set: { store.setAllFraction($0) }),
            in: 0...1
        )
        .controlSize(.small)
        .disabled(!store.canControl)
    }
}

/// Non-lazy grid of preset buttons (rows of `columns`), so it sizes correctly inside popovers.
struct PresetGrid: View {
    @Environment(FanStore.self) private var store
    var columns: Int = 5
    var compact: Bool = false
    var spacing: CGFloat = 6

    var body: some View {
        let presets = store.allPresets
        let rows = stride(from: 0, to: presets.count, by: columns).map { Array(presets[$0..<min($0 + columns, presets.count)]) }
        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(rows[r]) { preset in
                        PresetButton(preset: preset, isActive: store.activePresetID == preset.id, compact: compact) {
                            store.applyPreset(preset)
                        }
                        .disabled(!store.canControl)
                        .contextMenu {
                            if !preset.isBuiltIn {
                                Button("Delete \u{201C}\(preset.name)\u{201D}", role: .destructive) { store.deletePreset(preset) }
                            }
                        }
                    }
                    ForEach(0..<(columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }
}

/// "Start at login" switch. Re-reads the real state on appear, since it can also be changed in System Settings.
struct LaunchAtLoginToggle: View {
    var label: String = "Start Fan Control at login"
    var compact: Bool = false
    @State private var enabled = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Matches the surrounding toggles: a checkbox in the popover, the default style in Settings.
            Toggle(label, isOn: Binding(get: { enabled }, set: { set($0) }))
                .font(compact ? .callout : .body)
            if needsApproval {
                HStack(spacing: 4) {
                    Text("Blocked in System Settings.").foregroundStyle(.orange)
                    Button("Open Login Items…") { LoginItem.openSystemSettings() }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: reload)
    }

    private func set(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        enabled = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}
