import Foundation
import CoreGraphics

struct ScheduleEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var day: Int
    var startMinutes: Int
    var endMinutes: Int
    var location: String = ""
    var calendarSourceKey: String? = nil
    /// Calendar-scoped identity shared by the event's recurring occurrences.
    var calendarEventKey: String? = nil
    /// Calendar-scoped original occurrence identity, shared by overnight segments.
    var calendarOccurrenceKey: String? = nil

    var timeLabel: String { "\(Self.time(startMinutes)) – \(Self.time(endMinutes))" }
    static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "과목 이름을 입력해주세요." }
        if !(0...6).contains(day) { return "요일을 선택해주세요." }
        if startMinutes < 0 || endMinutes > 1440 || startMinutes >= endMinutes { return "종료 시간은 시작 시간보다 늦어야 합니다." }
        return nil
    }
    func overlaps(_ other: ScheduleEntry) -> Bool {
        id != other.id && day == other.day && startMinutes < other.endMinutes && endMinutes > other.startMinutes
    }
    static let dayNames = ["월", "화", "수", "목", "금", "토", "일"]
    static let dayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    static let sample: [ScheduleEntry] = [
        .init(name: "Visual Thinking", day: 0, startMinutes: 600, endMinutes: 720, location: "Design studio · 302"),
        .init(name: "Typography", day: 0, startMinutes: 840, endMinutes: 930, location: "Arts building · 201"),
        .init(name: "Creative Coding", day: 1, startMinutes: 660, endMinutes: 780, location: "Digital lab · 104"),
        .init(name: "Art & Culture", day: 2, startMinutes: 600, endMinutes: 690, location: "Humanities · 210"),
        .init(name: "Design Research", day: 2, startMinutes: 840, endMinutes: 960, location: "Design studio · 302"),
        .init(name: "Typography", day: 3, startMinutes: 660, endMinutes: 750, location: "Arts building · 201"),
        .init(name: "Open Studio", day: 4, startMinutes: 780, endMinutes: 960, location: "Make something good.")
    ]
}

enum WallpaperTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case ember, moss, midnight
    var id: String { rawValue }
    var label: String { switch self { case .ember: "Ember"; case .moss: "Moss"; case .midnight: "Midnight" } }
    var subtitle: String { switch self { case .ember: "따뜻한 오렌지"; case .moss: "차분한 올리브"; case .midnight: "깊은 코발트" } }
}

enum WallpaperResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case macbook14, macbook16, air13, air15, desktop4K
    var id: String { rawValue }
    var label: String { switch self { case .macbook14: "MacBook Pro 14″"; case .macbook16: "MacBook Pro 16″"; case .air13: "MacBook Air 13″"; case .air15: "MacBook Air 15″"; case .desktop4K: "4K Desktop" } }
    var size: CGSize { switch self { case .macbook14: CGSize(width: 3024, height: 1964); case .macbook16: CGSize(width: 3456, height: 2234); case .air13: CGSize(width: 2560, height: 1664); case .air15: CGSize(width: 2880, height: 1864); case .desktop4K: CGSize(width: 3840, height: 2160) } }
    var dimensions: String { "\(Int(size.width)) × \(Int(size.height))" }
}

enum WeekdayNumberStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case ordinal, date, hidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ordinal: "순서 번호"
        case .date: "실제 날짜"
        case .hidden: "표시 안 함"
        }
    }
}

struct WallpaperConfiguration: Codable, Equatable, Sendable {
    var theme: WallpaperTheme = .ember
    var resolution: WallpaperResolution = .macbook14
    var title: String = "Make room\nfor what matters."
    var subtitle: String = "2026 — FALL SEMESTER"
    var showLocations: Bool = true
    var showWeekends: Bool = false
    var showTexture: Bool = true
    var startHour: Int = 9
    var endHour: Int = 18
    /// Explicit render input, 0=Monday ... 6=Sunday. Never read the clock in the renderer.
    var highlightedDay: Int? = nil
    /// Nil preserves an automatic default: supplied dates select date labels;
    /// an unconnected repeating timetable retains its original ordinal labels.
    var weekdayNumberStyle: WeekdayNumberStyle? = nil
    /// Explicit Monday-through-Sunday dd render inputs. The renderer never
    /// derives these values from the clock, a title, or calendar permissions.
    var weekdayDateLabels: [String]? = nil

    var resolvedWeekdayNumberStyle: WeekdayNumberStyle {
        weekdayNumberStyle ?? (weekdayDateLabels == nil ? .ordinal : .date)
    }
}
