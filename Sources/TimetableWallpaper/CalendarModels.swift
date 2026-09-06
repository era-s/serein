import Foundation

enum CalendarAccess: Equatable {
    case notDetermined, authorized, denied, restricted
}

struct CalendarDescriptor: Identifiable, Hashable {
    var id: String
    var title: String
    var account: String
    var colorHex: UInt32
}

struct CalendarEventRecord {
    var id: String
    var calendarID: String
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String = ""
    var isAllDay: Bool = false
    var isCancelled: Bool = false
    var isDeclined: Bool = false
    var occurrenceDate: Date? = nil
}

struct CalendarWeek: Equatable {
    let start: Date
    let end: Date
    let timeZone: TimeZone

    init(containing date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        self.start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        self.end = calendar.date(byAdding: .day, value: 7, to: start)!
        self.timeZone = timeZone
    }

    var label: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        return "\(formatter.string(from: start)) — \(formatter.string(from: end.addingTimeInterval(-1)))"
    }
}

struct CalendarImportResult {
    var entries: [ScheduleEntry]
    var allDayCount: Int = 0
    var excludedCount: Int = 0
    var warnings: [String] = []
}

@MainActor
protocol CalendarProviding {
    var access: CalendarAccess { get }
    func requestAccess() async throws -> Bool
    func calendars() throws -> [CalendarDescriptor]
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord]
}

enum CalendarImportError: LocalizedError {
    case permissionDenied, noCalendarsSelected, calendarsChanged
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "캘린더 접근이 허용되지 않았습니다. 시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Serein을 허용해주세요."
        case .noCalendarsSelected: "가져올 캘린더를 하나 이상 선택해주세요."
        case .calendarsChanged: "선택한 캘린더가 변경되었거나 삭제되었습니다. 목록을 새로고침하고 다시 선택해주세요."
        }
    }
}
