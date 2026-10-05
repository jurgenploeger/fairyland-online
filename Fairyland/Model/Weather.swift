import Foundation

/// The weather on a map: picked from the map's `ambience.weather` weights in content/maps.json,
/// and changing every `spell` in-game hours (an in-game hour is a real minute). The same save on
/// the same map at the same hour always gets the same weather, so walking off and back doesn't
/// reroll it. `Sky` draws it, with the light of the time of day.
enum Weather: String, CaseIterable {
    case clear, cloudy, rain, storm, fog, snow

    /// In-game hours each spell of weather lasts.
    static let spell = 6
    /// Where a map doesn't say: mostly clear, sometimes cloudy, rainy or foggy.
    static let usual: [String: Double] = ["clear": 6, "cloudy": 2, "rain": 2, "fog": 1]

    /// Debug launches (`weather=rain`) set this to have it everywhere there's a sky.
    static var forced: Weather?

    /// The weather on `map` at `date`, or nil on a map with no sky (a cave, or `weather: {}`).
    static func on(_ map: MapDef, at date: Date = Date(), since start: Date?) -> Weather? {
        guard map.ambience?.darkness == nil, map.ambience?.weather?.isEmpty != true else { return nil }
        if let forced { return forced }
        let weights = (map.ambience?.weather ?? usual)
            .compactMap { entry in Weather(rawValue: entry.key).map { ($0, entry.value) } }
            .filter { $0.1 > 0 }
            .sorted { $0.0.rawValue < $1.0.rawValue }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        let slot = Int(GameClock.hours(at: date, since: start)) / spell
        var rng = SeededRandom(text: "\(map.id)/weather/\(slot)")
        var roll = Double.random(in: 0..<total, using: &rng)
        for (weather, weight) in weights {
            roll -= weight
            if roll < 0 { return weather }
        }
        return weights.last?.0
    }

    /// How much the clouds dim the light (multiplied into the time of day's colour).
    var shade: (r: Double, g: Double, b: Double) {
        switch self {
        case .clear: (1, 1, 1)
        case .cloudy: (0.88, 0.89, 0.92)
        case .rain: (0.76, 0.79, 0.86)
        case .storm: (0.6, 0.63, 0.72)
        case .fog: (0.93, 0.94, 0.96)
        case .snow: (0.9, 0.92, 0.97)
        }
    }

    /// Whether the sun's flare and sunbeams still shine through.
    var sunny: Bool { self == .clear }
}
