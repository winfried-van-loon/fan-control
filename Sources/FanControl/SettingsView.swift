import ServiceManagement
import SwiftUI
import FanKit

struct SettingsView: View {
    @Environment(FanStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Menu Bar") {
                Picker("Temperature", selection: $store.menuBarSensorKey) {
                    Text("Hottest CPU sensor").tag(FanStore.hottestSensorKey)
                    Divider()
                    ForEach(store.sensors.sorted { $0.name < $1.name }) { sensor in
                        Text(sensor.name).tag(sensor.key)
                    }
                }
                Toggle("Also show fan speed", isOn: $store.menuBarShowsRPM)
                Picker("Units", selection: $store.useFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Behavior") {
                Picker("Refresh every", selection: $store.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Toggle("Return fans to Auto when quitting", isOn: $store.restoreAutoOnQuit)
                Toggle("Reapply last fan setting at launch", isOn: $store.reapplyOnLaunch)
                Toggle("Thermal safety", isOn: $store.thermalSafety)
                if store.thermalSafety {
                    Stepper(value: $store.thermalSafetyLimit, in: 80...100, step: 1) {
                        Text("Switch to Auto at \(store.formatTemperature(store.thermalSafetyLimit))")
                    }
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Helper") {
                LabeledContent("Status") {
                    switch store.helperStatus {
                    case .ready: Label("Installed", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .outdated: Label("Outdated", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .notInstalled: Label("Not installed", systemImage: "xmark.seal").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(store.helperStatus == .ready ? "Reinstall" : "Install") { store.installHelper() }
                    if store.helperStatus != .notInstalled {
                        Button("Uninstall", role: .destructive) { store.uninstallHelper() }
                    }
                }
                Text(HelperInfo.installPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
