import Foundation

/// Derives seven display labels from the saved calendar week, never today's
/// clock or the machine's current locale/time zone. Calendar day arithmetic
/// keeps dates correct across month, year and daylight-saving boundaries.
enum WeekdayHeaderDates {
    static func labels(weekStart: Date, timeZoneID: String) -> [String]? {
        guard weekStart.timeIntervalSince1970.isFinite,
              let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let day = calendar.dateInterval(of: .day, for: weekStart),
              calendar.component(.weekday, from: day.start) == 2,
              (1...9999).contains(calendar.component(.year, from: day.start)) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = "dd"
        var result: [String] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: day.start) else { return nil }
            result.append(formatter.string(from: date))
        }
        return result
    }
}
