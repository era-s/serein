import Foundation

/// Explicit UI preview fixture. Never calls EventKit or reads an account.
@MainActor
final class DemoCalendarProvider: CalendarProviding {
    let access: CalendarAccess = .authorized
    static let anchor = ISO8601DateFormatter().date(from: "2026-09-07T00:00:00+09:00")!
    func requestAccess() async throws -> Bool { true }
    func calendars() throws -> [CalendarDescriptor] {
        [
            .init(id: "demo-study", title: "2026 가을학기", account: "Google · 예시 계정", colorHex: 0xC45C36),
            .init(id: "demo-personal", title: "나의 프로젝트", account: "iCloud · 예시 계정", colorHex: 0x7B8F64),
            .init(id: "demo-other", title: "기념일", account: "iCloud · 예시 계정", colorHex: 0x5779B3)
        ]
    }
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = week.timeZone
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: week.start)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        }
        let records: [CalendarEventRecord] = [
            .init(id: "design", calendarID: "demo-study", title: "시각디자인 스튜디오", startDate: date(0, 10), endDate: date(0, 12), location: "디자인관 302"),
            .init(id: "coding", calendarID: "demo-study", title: "Creative Coding", startDate: date(1, 13), endDate: date(1, 15), location: "디지털랩 104"),
            .init(id: "type", calendarID: "demo-study", title: "타이포그래피", startDate: date(3, 11), endDate: date(3, 12, 30), location: "디자인관 201"),
            .init(id: "reading", calendarID: "demo-personal", title: "책과 커피", startDate: date(2, 14), endDate: date(2, 15), location: "동네 책방"),
            .init(id: "project", calendarID: "demo-personal", title: "사이드 프로젝트", startDate: date(4, 14), endDate: date(4, 16), location: "Make something good."),
            .init(id: "all-day", calendarID: "demo-study", title: "학기 시작", startDate: date(0, 0), endDate: date(1, 0), isAllDay: true)
        ]
        return records.filter { calendarIDs.contains($0.calendarID) }
    }
}
