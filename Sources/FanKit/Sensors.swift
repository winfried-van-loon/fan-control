import Foundation

public enum SensorGroup: String, CaseIterable, Codable, Sendable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case storage = "Storage"
    case battery = "Battery"
    case board = "Mainboard"
    case airflow = "Airflow & Heatsink"
    case enclosure = "Enclosure"
    case other = "Other"

    public var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.75percent"
        case .board: return "rectangle.connected.to.line.below"
        case .airflow: return "wind"
        case .enclosure: return "laptopcomputer"
        case .other: return "thermometer.medium"
        }
    }
}

public struct Sensor: Identifiable, Hashable, Sendable {
    public let key: String
    public let name: String
    public let group: SensorGroup
    public var value: Double
    public var id: String { key }
}

public enum SensorCatalog {
    /// Friendly names for well-known Intel Mac SMC temperature keys.
    static let known: [String: (String, SensorGroup)] = [
        "TCXC": ("CPU Package", .cpu),
        "TCMX": ("CPU Hottest Core", .cpu),
        "TC0P": ("CPU Proximity", .cpu),
        "TC0D": ("CPU Die", .cpu),
        "TC0E": ("CPU Die (Virtual 1)", .cpu),
        "TC0F": ("CPU Die (Virtual 2)", .cpu),
        "TC0H": ("CPU Heatsink", .cpu),
        "TCSA": ("CPU System Agent", .cpu),
        "TCGC": ("Integrated GPU", .gpu),
        "TG0P": ("GPU Proximity", .gpu),
        "TG1P": ("GPU Proximity 2", .gpu),
        "TGDD": ("GPU Die", .gpu),
        "TGDE": ("GPU Die (Virtual 1)", .gpu),
        "TGDF": ("GPU Die (Virtual 2)", .gpu),
        "TGVP": ("GPU VRAM Proximity", .gpu),
        "TGVF": ("GPU VRAM (Virtual)", .gpu),
        "TG0D": ("GPU Die", .gpu),
        "TM0P": ("Memory Proximity", .memory),
        "TM0S": ("Memory Slot", .memory),
        "TH0a": ("SSD A", .storage),
        "TH0b": ("SSD B", .storage),
        "TH0F": ("SSD (Filtered)", .storage),
        "TH0X": ("SSD (Max)", .storage),
        "TH1a": ("SSD 2 A", .storage),
        "TH1b": ("SSD 2 B", .storage),
        "TB0T": ("Battery", .battery),
        "TB1T": ("Battery Cell 1", .battery),
        "TB2T": ("Battery Cell 2", .battery),
        "TB3T": ("Battery Cell 3", .battery),
        "TPCD": ("Platform Controller Hub", .board),
        "Tm0P": ("Mainboard Proximity", .board),
        "TW0P": ("Wi-Fi Module", .board),
        "TTLD": ("Thunderbolt Left", .board),
        "TTRD": ("Thunderbolt Right", .board),
        "TaLC": ("Airflow Left", .airflow),
        "TaRC": ("Airflow Right", .airflow),
        "Th1H": ("Heatpipe 1", .airflow),
        "Th2H": ("Heatpipe 2", .airflow),
        "TA0V": ("Ambient", .enclosure),
        "TA0P": ("Ambient", .enclosure),
        "Ts0P": ("Palm Rest Left", .enclosure),
        "Ts1P": ("Palm Rest Right", .enclosure),
        "Ts0S": ("Bottom Case 1", .enclosure),
        "Ts1S": ("Bottom Case 2", .enclosure),
        "Ts2S": ("Bottom Case 3", .enclosure),
    ]

    /// Preferred sensors for the menu bar, in order.
    public static let defaultMenuBarKeys = ["TCXC", "TC0D", "TC0P", "TCMX", "Tp09", "Tp01"]

    public static func describe(_ key: String) -> (String, SensorGroup) {
        if let k = known[key] { return k }
        let chars = Array(key)
        if chars.count == 4, chars[0] == "T", chars[1] == "C", chars[3] == "C", let n = chars[2].wholeNumberValue {
            return ("CPU Core \(n)", .cpu)
        }
        switch chars.count > 1 ? chars[1] : " " {
        case "C": return ("CPU \(key)", .cpu)
        case "G": return ("GPU \(key)", .gpu)
        case "B": return ("Battery \(key)", .battery)
        case "H": return ("Storage \(key)", .storage)
        case "M": return ("Memory \(key)", .memory)
        case "s", "A": return ("Enclosure \(key)", .enclosure)
        default: return ("Sensor \(key)", .other)
        }
    }

    /// A plausible reading from a live sensor (filters out disconnected / placeholder keys).
    static func plausible(_ v: Double) -> Bool { v >= 10 && v < 130 }
}

/// Discovers temperature keys once, then reads them cheaply on each refresh.
public final class SensorReader: @unchecked Sendable {
    private var keys: [String] = []

    public init() {}

    public func discover() {
        keys = SMC.allKeys().filter { key in
            guard key.hasPrefix("T"), let v = try? SMC.read(key),
                  v.type == "sp78" || v.type == "flt ", let d = v.double else { return false }
            return SensorCatalog.plausible(d)
        }
    }

    public func read() -> [Sensor] {
        if keys.isEmpty { discover() }
        return keys.compactMap { key in
            guard let v = SMC.double(key), SensorCatalog.plausible(v) else { return nil }
            let (name, group) = SensorCatalog.describe(key)
            return Sensor(key: key, name: name, group: group, value: v)
        }
    }
}
