import Charts
import SwiftUI
import FanKit

struct DashboardView: View {
    @Environment(FanStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HelperBanner()
                    NoticeBar()
                    FansSection()
                    TargetSection()
                    PresetsSection()
                    HistorySection()
                }
                .padding(20)
            }
            .frame(width: 470)

            Divider()

            ScrollView {
                TemperaturesSection()
                    .padding(20)
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings.toggle() } label: { Label("Settings", systemImage: "gearshape") }
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        SettingsView().environment(store)
                    }
            }
        }
    }
}

// MARK: - Sections

private struct SectionHeader: View {
    var title: String
    var symbol: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

private struct FansSection: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Fans", symbol: "fan", trailing: store.targetModeEnabled ? "Holding \(store.formatTemperature(store.targetTemperature))" : (store.isAllAuto ? "System controlled" : "Manual control"))
            HStack(spacing: 12) {
                ForEach(store.fans) { fan in
                    FanCard(fan: fan)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("All fans").font(.subheadline.weight(.medium))
                        Spacer()
                        Text(store.isAllAuto ? "Auto" : "\(Int((store.overallFraction * 100).rounded()))% of range")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        AllFansSlider()
                        Button("Auto") { store.applyPreset(.auto) }
                        Button("Full Speed") { store.applyPreset(.full) }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    .controlSize(.small)
                    .disabled(!store.canControl)
                }
            }
        }
    }
}

private struct FanCard: View {
    @Environment(FanStore.self) private var store
    var fan: FanInfo

    var body: some View {
        let mode = store.mode(for: fan.index)
        let tint: Color = store.targetModeEnabled ? .purple : (mode.isManual ? .orange : .accentColor)
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text(fan.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    ModeBadge(manual: mode.isManual, target: store.targetModeEnabled)
                }
                RingGauge(fraction: fan.fraction, tint: tint) {
                    VStack(spacing: 0) {
                        SpinningFan(rpm: fan.actual, size: 16, tint: tint)
                        Text("\(Int(fan.actual))")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("RPM").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                Picker("", selection: Binding(
                    get: { mode.isManual },
                    set: { manual in
                        if manual { store.setRPM(fan.actual, forFan: fan.index) } else { store.setAuto(forFan: fan.index) }
                    }
                )) {
                    Text("Auto").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!store.canControl)

                VStack(spacing: 2) {
                    FanSlider(fan: fan)
                    HStack {
                        Text("\(Int(fan.minimum))")
                        Spacer()
                        if case .manual(let rpm) = mode {
                            Text("target \(Int(rpm))").foregroundStyle(.orange)
                        }
                        Spacer()
                        Text("\(Int(fan.maximum))")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Min") { store.setFraction(0, forFan: fan.index) }
                    Button("50%") { store.setFraction(0.5, forFan: fan.index) }
                    Button("Max") { store.setFull(forFan: fan.index) }
                }
                .controlSize(.small)
                .disabled(!store.canControl)
            }
        }
    }
}

private struct TargetSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Target Temperature", symbol: "scope")
            Card { TargetControl() }
        }
    }
}

private struct PresetsSection: View {
    @Environment(FanStore.self) private var store
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Presets", symbol: "slider.horizontal.3")
            PresetGrid(spacing: 8)
            HStack {
                Button {
                    newName = "My Preset"
                    naming = true
                } label: {
                    Label("Save Current Setting as Preset…", systemImage: "plus")
                }
                .controlSize(.small)
                Spacer()
                if !store.customPresets.isEmpty {
                    Text("Right-click a custom preset to delete it")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .sheet(isPresented: $naming) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Preset").font(.headline)
                Text("Saves each fan's current setting (manual speed or Auto).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Cancel") { naming = false }.keyboardShortcut(.cancelAction)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.saveCurrentAsPreset(named: name)
        naming = false
    }
}

private struct HistorySection: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Last 10 Minutes", symbol: "chart.xyaxis.line", trailing: store.menuBarSensorLabel)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    let points = smoothedTemperatures
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Temperature", point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.temperature(point.celsius))
                    }
                    .chartYScale(domain: temperatureDomain(points.map(\.value)))
                    .chartXAxis(.hidden)
                    .chartYAxisLabel(store.useFahrenheit ? "°F" : "°C")
                    .frame(height: 90)

                    Chart {
                        ForEach(store.history) { sample in
                            ForEach(Array(sample.rpms.enumerated()), id: \.offset) { index, rpm in
                                LineMark(x: .value("Time", sample.date), y: .value("RPM", rpm))
                                    .foregroundStyle(by: .value("Fan", "Fan \(index + 1)"))
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("RPM")
                    .chartLegend(position: .top, alignment: .trailing)
                    .frame(height: 90)
                }
            }
        }
    }

    private func displayTemp(_ c: Double) -> Double { store.useFahrenheit ? c * 9 / 5 + 32 : c }

    /// Temperatures with a short moving average, so sensor jitter doesn't swamp the trend.
    private var smoothedTemperatures: [(date: Date, celsius: Double, value: Double)] {
        let temps = store.history.map(\.temperature)
        let window = 5
        return store.history.indices.map { i in
            let slice = temps[max(0, i - window + 1)...i]
            let avg = slice.reduce(0, +) / Double(slice.count)
            return (store.history[i].date, avg, displayTemp(avg))
        }
    }

    /// At least 20 degrees tall, so small fluctuations look small.
    private func temperatureDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 30...70 }
        let span = max(20, hi - lo + 6)
        let mid = (lo + hi) / 2
        return (mid - span / 2).rounded(.down)...(mid + span / 2).rounded(.up)
    }
}

private struct TemperaturesSection: View {
    @Environment(FanStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Temperatures", symbol: "thermometer.medium", trailing: "\(store.sensors.count) sensors")
            ForEach(store.sensorsByGroup, id: \.0) { group, sensors in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: group.symbol).foregroundStyle(.secondary).frame(width: 18)
                            Text(group.rawValue).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let max = sensors.map(\.value).max() {
                                Text("max \(store.formatTemperature(max))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(sensors) { sensor in
                            SensorRow(sensor: sensor)
                        }
                    }
                }
            }
        }
    }
}

private struct SensorRow: View {
    @Environment(FanStore.self) private var store
    var sensor: Sensor
    @State private var hovering = false

    var body: some View {
        let pinned = store.menuBarSensorKey == sensor.key
        HStack(spacing: 8) {
            Text(sensor.name)
                .font(.callout)
                .lineLimit(1)
            Text(sensor.key)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Button {
                store.menuBarSensorKey = pinned ? FanStore.hottestSensorKey : sensor.key
            } label: {
                Image(systemName: pinned ? "menubar.arrow.up.rectangle" : "pin")
                    .foregroundStyle(pinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(pinned || hovering ? 1 : 0)
            .help(pinned ? "Shown in the menu bar — click to show the hottest CPU sensor instead" : "Show in menu bar")

            Capsule()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 70, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.temperature(sensor.value))
                        .frame(width: 70 * max(0.04, min(1, (sensor.value - 20) / 80)), height: 5)
                        .animation(.easeOut, value: sensor.value)
                }
            Text(store.formatTemperature(sensor.value))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.temperature(sensor.value))
                .frame(width: 48, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Menu Bar") { store.menuBarSensorKey = sensor.key }
        }
    }
}
