import Foundation

struct AutomationSettings: Codable, Equatable {
    var refreshOnCalendarChange = false
    var refreshWeekly = false
    var showToday = false
    var targetDisplayID: String? = WallpaperDisplay.allSpacesID
    var targetDisplayName: String? = WallpaperDisplay.allSpaces.name
    var hasCalendarAutomation: Bool { refreshOnCalendarChange || refreshWeekly }
    var hasAutomation: Bool { hasCalendarAutomation || showToday }
}

struct CalendarConnection: Codable, Equatable {
    var calendarIDs: Set<String>
    var calendarNames: [String]
    var weekStart: Date
    var timeZoneID: String
    var managedEntryKeys: Set<String>
    var includeWeekTitle: Bool
}

struct AutomationReceipt: Codable, Equatable {
    var wallpaperFingerprint: String
    var calendarFingerprint: String?
    var appliedAt: Date
    var weekStart: Date?
    var dayKey: String
    var targetDisplayID: String
}

struct AutomationContext {
    var entries: [ScheduleEntry]
    var configuration: WallpaperConfiguration
    var settings: AutomationSettings
    var connection: CalendarConnection?
    var receipt: AutomationReceipt?
    var timeZone: TimeZone = .current
}

enum AutomationTrigger {
    case enabled, settingsChanged, calendarChanged, clock, wake, launch, manual
}

struct AutomationUpdate {
    var entries: [ScheduleEntry]
    var configuration: WallpaperConfiguration
    var connection: CalendarConnection?
    var receipt: AutomationReceipt
    var reason: String
}

struct WallpaperDisplay: Identifiable, Equatable {
    static let allSpacesID = "serein.all-spaces-and-displays"
    static let allSpaces = WallpaperDisplay(id: allSpacesID, name: "모든 데스크탑과 디스플레이")

    var id: String
    var name: String
}
