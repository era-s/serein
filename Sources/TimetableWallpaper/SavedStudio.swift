import Foundation

struct SavedStudio: Codable {
    var version = 2
    var entries: [ScheduleEntry]
    var configuration: WallpaperConfiguration
    var automation: AutomationSettings? = nil
    var connection: CalendarConnection? = nil
    var receipt: AutomationReceipt? = nil

    var isValid: Bool {
        (1...2).contains(version) && entries.allSatisfy { $0.validationError == nil }
            && Set(entries.map(\.id)).count == entries.count
            && (0...23).contains(configuration.startHour)
            && (1...24).contains(configuration.endHour)
            && configuration.startHour < configuration.endHour
            && (connection == nil || (!connection!.calendarIDs.isEmpty && TimeZone(identifier: connection!.timeZoneID) != nil))
    }
}
