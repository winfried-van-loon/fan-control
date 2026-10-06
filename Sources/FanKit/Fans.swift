import Foundation

public struct FanInfo: Identifiable, Hashable, Sendable {
    public let index: Int
    public var actual: Double
    public var minimum: Double
    public var maximum: Double
    public var target: Double
    public var forced: Bool
    public var id: Int { index }

    public var name: String { "Fan \(index + 1)" }

    /// Current speed as a fraction of the min…max range.
    public var fraction: Double {
        guard maximum > minimum else { return 0 }
        return max(0, min(1, (actual - minimum) / (maximum - minimum)))
    }

    public func rpm(forFraction f: Double) -> Double {
        (minimum + (maximum - minimum) * max(0, min(1, f))).rounded()
    }

    public func fraction(forRPM rpm: Double) -> Double {
        guard maximum > minimum else { return 0 }
        return max(0, min(1, (rpm - minimum) / (maximum - minimum)))
    }
}

public enum Fans {
    public static func count() -> Int {
        Int(SMC.double("FNum") ?? 0)
    }

    public static func read() -> [FanInfo] {
        (0..<count()).compactMap { i in
            guard let actual = SMC.double("F\(i)Ac"),
                  let minimum = SMC.double("F\(i)Mn"),
                  let maximum = SMC.double("F\(i)Mx") else { return nil }
            return FanInfo(
                index: i,
                actual: max(0, actual),
                minimum: minimum,
                maximum: maximum,
                target: SMC.double("F\(i)Tg") ?? minimum,
                forced: (SMC.double("F\(i)Md") ?? 0) == 1
            )
        }
    }

    // MARK: Privileged operations (helper only — need root)

    /// Forces fan `index` to `rpm`, clamped to the fan's safe range. Returns the applied RPM.
    @discardableResult
    public static func setSpeed(_ index: Int, rpm: Double) throws -> Double {
        guard let minimum = SMC.double("F\(index)Mn"), let maximum = SMC.double("F\(index)Mx") else {
            throw SMCError.readFailed("F\(index)Mn", -1)
        }
        let clamped = max(minimum, min(maximum, rpm.rounded()))
        try SMC.write("F\(index)Md", 1)
        try SMC.write("F\(index)Tg", clamped)
        return clamped
    }

    /// Returns fan `index` to automatic (system) control.
    public static func setAuto(_ index: Int) throws {
        try SMC.write("F\(index)Md", 0)
    }
}

public enum HelperInfo {
    public static let installPath = "/Library/PrivilegedHelperTools/com.fancontrol.helper"
    /// Bump when the helper's command interface changes; the app offers to reinstall on mismatch.
    public static let version = "1"
}
