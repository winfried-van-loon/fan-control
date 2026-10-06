import AppKit
import FanKit
import Observation

enum FanMode: Codable, Equatable {
    case auto
    case manual(rpm: Double)

    var isManual: Bool { if case .manual = self { return true } else { return false } }
}

struct HistorySample: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let rpms: [Double]
}

@Observable
@MainActor
final class FanStore {
    static let hottestSensorKey = "__hottest"

    // Live readings
    private(set) var sensors: [Sensor] = []
    private(set) var fans: [FanInfo] = []
    private(set) var history: [HistorySample] = []

    // Desired control state (what the user asked for)
    private(set) var modes: [Int: FanMode] = [:]
    private(set) var activePresetID: String? = Preset.auto.id

    private(set) var helperStatus: HelperStatus = .notInstalled
    var notice: String?

    // Settings
    var menuBarSensorKey: String { didSet { defaults.set(menuBarSensorKey, forKey: "menuBarSensorKey"); onChange?() } }
    var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: "useFahrenheit"); onChange?() } }
    var menuBarShowsRPM: Bool { didSet { defaults.set(menuBarShowsRPM, forKey: "menuBarShowsRPM"); onChange?() } }
    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval"); startTimer() } }
    var restoreAutoOnQuit: Bool { didSet { defaults.set(restoreAutoOnQuit, forKey: "restoreAutoOnQuit") } }
    var reapplyOnLaunch: Bool { didSet { defaults.set(reapplyOnLaunch, forKey: "reapplyOnLaunch") } }
    var thermalSafety: Bool { didSet { defaults.set(thermalSafety, forKey: "thermalSafety") } }
    var thermalSafetyLimit: Double { didSet { defaults.set(thermalSafetyLimit, forKey: "thermalSafetyLimit") } }
    private(set) var customPresets: [Preset] { didSet { savePresets() } }

    /// Called after each refresh and on display-relevant setting changes (used to update the status item).
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let reader = SensorReader()
    private let readQueue = DispatchQueue(label: "fancontrol.read")
    private var timer: Timer?
    private var pendingApply: Task<Void, Never>?
    private var lastApply = Date.distantPast
    private var applying = false
    private var didInitialSync = false

    init() {
        defaults.register(defaults: [
            "menuBarSensorKey": "TCXC",
            "refreshInterval": 2.0,
            "restoreAutoOnQuit": true,
            "reapplyOnLaunch": false,
            "thermalSafety": true,
            "thermalSafetyLimit": 95.0,
        ])
        menuBarSensorKey = defaults.string(forKey: "menuBarSensorKey") ?? "TCXC"
        useFahrenheit = defaults.bool(forKey: "useFahrenheit")
        menuBarShowsRPM = defaults.bool(forKey: "menuBarShowsRPM")
        refreshInterval = defaults.double(forKey: "refreshInterval")
        restoreAutoOnQuit = defaults.bool(forKey: "restoreAutoOnQuit")
        reapplyOnLaunch = defaults.bool(forKey: "reapplyOnLaunch")
        thermalSafety = defaults.bool(forKey: "thermalSafety")
        thermalSafetyLimit = defaults.double(forKey: "thermalSafetyLimit")
        if let data = defaults.data(forKey: "customPresets"), let presets = try? JSONDecoder().decode([Preset].self, from: data) {
            customPresets = presets
        } else {
            customPresets = []
        }
    }

    func start() {
        do { try SMC.open() } catch { notice = "\(error)" }
        refreshHelperStatus()
        refresh()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.5, refreshInterval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.2
    }

    func refreshHelperStatus() {
        helperStatus = HelperClient.status()
    }

    // MARK: Reading

    func refresh() {
        readQueue.async { [reader] in
            let sensors = reader.read()
            let fans = Fans.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(sensors: sensors, fans: fans) }
            }
        }
    }

    private func apply(sensors: [Sensor], fans: [FanInfo]) {
        self.sensors = sensors
        self.fans = fans

        if !didInitialSync, !fans.isEmpty {
            didInitialSync = true
            syncModesFromHardware()
            if reapplyOnLaunch, let saved = savedModes(), helperStatus == .ready {
                modes = saved
                activePresetID = defaults.string(forKey: "lastPresetID")
                scheduleApply(delay: 0)
            }
        }

        if let temp = menuBarTemperature {
            history.append(HistorySample(date: Date(), temperature: temp, rpms: fans.map(\.actual)))
            let cutoff = Date().addingTimeInterval(-600)
            if let first = history.firstIndex(where: { $0.date >= cutoff }), first > 0 { history.removeFirst(first) }
        }

        enforceThermalSafety()
        correctDrift()
        onChange?()
    }

    /// Adopt whatever the hardware is doing (e.g. fans left forced by a previous session).
    private func syncModesFromHardware() {
        for fan in fans {
            modes[fan.index] = fan.forced ? .manual(rpm: fan.target) : .auto
        }
        activePresetID = fans.allSatisfy({ !$0.forced }) ? Preset.auto.id : nil
    }

    /// Re-apply manual settings if the system took control back.
    private func correctDrift() {
        guard helperStatus == .ready, !applying, pendingApply == nil, Date().timeIntervalSince(lastApply) > 5 else { return }
        let drifted = fans.contains { fan in
            switch mode(for: fan.index) {
            case .manual(let rpm): return !fan.forced || abs(fan.target - rpm) > 30
            case .auto: return fan.forced
            }
        }
        if drifted { scheduleApply(delay: 0) }
    }

    private func enforceThermalSafety() {
        guard thermalSafety, modes.values.contains(where: \.isManual) else { return }
        let critical = sensors.filter { $0.group == .cpu || $0.group == .gpu }.map(\.value).max() ?? 0
        guard critical >= thermalSafetyLimit else { return }
        let allAtMax = fans.allSatisfy { fan in
            if case .manual(let rpm) = mode(for: fan.index) { return rpm >= fan.maximum - 1 }
            return true
        }
        guard !allAtMax else { return }
        notice = "Thermal safety: \(formatTemperature(critical)) reached — switched back to automatic."
        applyPreset(.auto)
    }

    // MARK: Derived values

    func mode(for index: Int) -> FanMode { modes[index] ?? .auto }

    var hottestSensor: Sensor? { sensors.max { $0.value < $1.value } }

    var menuBarSensor: Sensor? {
        if menuBarSensorKey != FanStore.hottestSensorKey, let s = sensors.first(where: { $0.key == menuBarSensorKey }) {
            return s
        }
        if menuBarSensorKey == FanStore.hottestSensorKey {
            return sensors.filter { $0.group == .cpu }.max { $0.value < $1.value } ?? hottestSensor
        }
        for key in SensorCatalog.defaultMenuBarKeys {
            if let s = sensors.first(where: { $0.key == key }) { return s }
        }
        return hottestSensor
    }

    var menuBarSensorLabel: String {
        menuBarSensorKey == FanStore.hottestSensorKey ? "Hottest CPU sensor" : (menuBarSensor?.name ?? "—")
    }

    var menuBarTemperature: Double? { menuBarSensor?.value }

    var sensorsByGroup: [(SensorGroup, [Sensor])] {
        SensorGroup.allCases.compactMap { group in
            let items = sensors.filter { $0.group == group }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var allPresets: [Preset] { Preset.builtIns + customPresets }

    var canControl: Bool { helperStatus == .ready }

    var isAllAuto: Bool { fans.allSatisfy { !mode(for: $0.index).isManual } }

    /// Average requested level across fans, as a fraction of their range.
    var overallFraction: Double {
        guard !fans.isEmpty else { return 0 }
        let fractions = fans.map { fan -> Double in
            if case .manual(let rpm) = mode(for: fan.index) { return fan.fraction(forRPM: rpm) }
            return fan.fraction
        }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    func displayRPM(for fan: FanInfo) -> Double {
        if case .manual(let rpm) = mode(for: fan.index) { return rpm }
        return fan.actual
    }

    func formatTemperature(_ celsius: Double, unit: Bool = true) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.0f", value) + (unit ? (useFahrenheit ? "°F" : "°C") : "°")
    }

    // MARK: Control

    func applyPreset(_ preset: Preset) {
        for fan in fans {
            if let level = preset.level(forFan: fan.index) {
                modes[fan.index] = .manual(rpm: fan.rpm(forFraction: level))
            } else {
                modes[fan.index] = .auto
            }
        }
        activePresetID = preset.id
        scheduleApply(delay: 0)
    }

    func setRPM(_ rpm: Double, forFan index: Int) {
        guard let fan = fans.first(where: { $0.index == index }) else { return }
        modes[index] = .manual(rpm: max(fan.minimum, min(fan.maximum, rpm.rounded())))
        activePresetID = nil
        scheduleApply()
    }

    func setFraction(_ fraction: Double, forFan index: Int) {
        guard let fan = fans.first(where: { $0.index == index }) else { return }
        setRPM(fan.rpm(forFraction: fraction), forFan: index)
    }

    func setAllFraction(_ fraction: Double) {
        for fan in fans { modes[fan.index] = .manual(rpm: fan.rpm(forFraction: fraction)) }
        activePresetID = nil
        scheduleApply()
    }

    func setAuto(forFan index: Int) {
        modes[index] = .auto
        activePresetID = isAllAuto ? Preset.auto.id : nil
        scheduleApply(delay: 0)
    }

    func setFull(forFan index: Int) {
        guard let fan = fans.first(where: { $0.index == index }) else { return }
        setRPM(fan.maximum, forFan: index)
    }

    private func scheduleApply(delay: Double = 0.35) {
        pendingApply?.cancel()
        pendingApply = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.pendingApply = nil
            await self.applyModes()
        }
    }

    private func applyModes() async {
        guard helperStatus == .ready else {
            notice = "Install the helper to change fan speeds."
            return
        }
        let commands = fans.map { fan -> [String] in
            switch mode(for: fan.index) {
            case .auto: return ["auto", "\(fan.index)"]
            case .manual(let rpm): return ["set", "\(fan.index)", "\(Int(rpm))"]
            }
        }
        applying = true
        defer { applying = false; lastApply = Date() }
        do {
            try await HelperClient.run(commands)
            if notice == "Install the helper to change fan speeds." { notice = nil }
            saveModes()
        } catch {
            notice = error.localizedDescription
        }
        refresh()
    }

    /// Synchronously hand the fans back to the system (used at quit).
    func restoreAutoIfNeeded() {
        guard restoreAutoOnQuit, helperStatus == .ready else { return }
        pendingApply?.cancel()
        _ = try? HelperClient.runSync(["auto", "all"])
    }

    // MARK: Helper

    func installHelper() {
        do {
            try HelperClient.install()
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
        refreshHelperStatus()
        if helperStatus == .ready { syncModesFromHardware() }
    }

    func uninstallHelper() {
        do { try HelperClient.uninstall() } catch { notice = error.localizedDescription }
        refreshHelperStatus()
    }

    // MARK: Presets

    func saveCurrentAsPreset(named name: String) {
        let levels: [Double?] = fans.map { fan in
            if case .manual(let rpm) = mode(for: fan.index) { return fan.fraction(forRPM: rpm) }
            return nil
        }
        let preset = Preset(id: UUID().uuidString, name: name, symbol: "star", levels: levels)
        customPresets.append(preset)
        activePresetID = preset.id
    }

    func deletePreset(_ preset: Preset) {
        customPresets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id { activePresetID = nil }
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(customPresets) { defaults.set(data, forKey: "customPresets") }
    }

    private func saveModes() {
        let dict = Dictionary(uniqueKeysWithValues: modes.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(dict) { defaults.set(data, forKey: "lastModes") }
        defaults.set(activePresetID, forKey: "lastPresetID")
    }

    private func savedModes() -> [Int: FanMode]? {
        guard let data = defaults.data(forKey: "lastModes"),
              let dict = try? JSONDecoder().decode([String: FanMode].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in Int(k).map { ($0, v) } })
    }
}
