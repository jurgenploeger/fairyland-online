import Foundation

/// Fairyland's calendar ("1001/Fire/12/13hr"): an in-game hour passes every real minute,
/// and each 60-day month belongs to one of the five elements.
enum GameClock {
    static let months: [Element] = [.metal, .wood, .water, .fire, .earth]

    struct Moment {
        let year: Int
        let month: Element
        let day: Int
        let hour: Int

        var isDaytime: Bool { (6..<18).contains(hour) }
        var text: String { "\(year)/\(month.displayName)/\(day)/\(hour)hr" }
    }

    static func moment(at date: Date = Date(), since start: Date?) -> Moment {
        let origin = start ?? Date(timeIntervalSince1970: 1_790_000_000)
        // Start mid-morning on day one, so a new game opens in daylight.
        let hours = max(0, Int(date.timeIntervalSince(origin) / 60)) + 9
        let days = hours / 24
        return Moment(year: 1001 + days / 300, month: months[(days / 60) % months.count], day: days % 60 + 1, hour: hours % 24)
    }
}
