import SwiftUI
import FanKit

struct PopoverView: View {
    @Environment(FanStore.self) private var store
    var openWindow: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HelperBanner()
            NoticeBar()
            presets
            TargetControl(compact: true)
            Divider()
            fans
            Divider()
            LaunchAtLoginToggle(compact: true)
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            let temp = store.menuBarTemperature ?? 0
            ZStack {
                Circle().fill(Color.temperature(temp).opacity(0.15))
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.temperature(temp))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.menuBarSensor?.name ?? "Temperature")
                    .font(.callout.weight(.medium))
                if let hottest = store.hottestSensor {
                    Text("Hottest \(store.formatTemperature(hottest.value)) · \(hottest.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(store.menuBarTemperature.map { store.formatTemperature($0) } ?? "—")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.temperature(temp))
                .contentTransition(.numericText())
                .animation(.default, value: Int(temp))
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            PresetGrid(compact: true)
        }
    }

    private var fans: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ALL FANS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(store.targetModeEnabled ? "Target" : (store.isAllAuto ? "Auto" : "\(Int((store.overallFraction * 100).rounded()))%"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            AllFansSlider()

            ForEach(store.fans) { fan in
                PopoverFanRow(fan: fan)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: openWindow) {
                Label("Open Fan Control", systemImage: "macwindow")
            }
            Spacer()
            Button(action: quit) {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
    }
}

private struct PopoverFanRow: View {
    @Environment(FanStore.self) private var store
    var fan: FanInfo

    var body: some View {
        let manual = store.mode(for: fan.index).isManual
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SpinningFan(rpm: fan.actual, size: 14, tint: store.targetModeEnabled ? .purple : (manual ? .orange : .accentColor))
                Text(fan.name).font(.callout.weight(.medium))
                ModeBadge(manual: manual, target: store.targetModeEnabled)
                Spacer()
                Text("\(Int(fan.actual)) rpm")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                FanSlider(fan: fan)
                Button("Auto") { store.setAuto(forFan: fan.index) }
                    .controlSize(.mini)
                    .disabled(!manual || !store.canControl)
                Button("Max") { store.setFull(forFan: fan.index) }
                    .controlSize(.mini)
                    .disabled(!store.canControl)
            }
        }
    }
}
