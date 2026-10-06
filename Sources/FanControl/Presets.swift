import Foundation

/// A named fan setting. Each level is a fraction of a fan's min…max range, or nil for automatic.
/// A single level applies to every fan.
struct Preset: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var levels: [Double?]
    var isBuiltIn: Bool = false

    func level(forFan index: Int) -> Double? {
        guard !levels.isEmpty else { return nil }
        return levels.count == 1 ? levels[0] : (index < levels.count ? levels[index] : levels.last!)
    }

    static let auto = Preset(id: "auto", name: "Auto", symbol: "a.circle", levels: [nil], isBuiltIn: true)
    static let silent = Preset(id: "silent", name: "Silent", symbol: "leaf", levels: [0], isBuiltIn: true)
    static let balanced = Preset(id: "balanced", name: "Balanced", symbol: "dial.medium", levels: [0.45], isBuiltIn: true)
    static let performance = Preset(id: "performance", name: "Boost", symbol: "hare", levels: [0.75], isBuiltIn: true)
    static let full = Preset(id: "full", name: "Full", symbol: "tornado", levels: [1], isBuiltIn: true)

    static let builtIns: [Preset] = [.auto, .silent, .balanced, .performance, .full]
}
