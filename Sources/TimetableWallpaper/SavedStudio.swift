import Foundation

struct SavedStudio: Codable {
    var version = 3
    var entries: [ScheduleEntry]
    var configuration: WallpaperConfiguration
    var automation: AutomationSettings? = nil
    var connection: CalendarConnection? = nil
    var receipt: AutomationReceipt? = nil
    // Optional for older v1–v3 files. Exclusions belong to the user's studio,
    // not one connection snapshot, so changing calendars does not erase them.
    var calendarVisibility: CalendarVisibility? = nil

    private enum CodingKeys: String, CodingKey {
        case version, entries, configuration, automation, connection, receipt, calendarVisibility
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var preferences = configuration
        // Keep derived values in render fingerprints, but recompute them from
        // the connected week for every preview/export instead of saving a cache.
        preferences.weekdayDateLabels = nil
        preferences.highlightedDay = nil
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(preferences, forKey: .configuration)
        try container.encodeIfPresent(automation, forKey: .automation)
        try container.encodeIfPresent(connection, forKey: .connection)
        try container.encodeIfPresent(receipt, forKey: .receipt)
        try container.encodeIfPresent(calendarVisibility, forKey: .calendarVisibility)
    }

    var isValid: Bool {
        (1...3).contains(version) && entries.allSatisfy { $0.validationError == nil }
            && Set(entries.map(\.id)).count == entries.count
            && (0...23).contains(configuration.startHour)
            && (1...24).contains(configuration.endHour)
            && configuration.startHour < configuration.endHour
            && (calendarVisibility == nil || (
                Set(calendarVisibility!.exclusions.map(\.id)).count == calendarVisibility!.exclusions.count
                && calendarVisibility!.exclusions.allSatisfy {
                    $0.entry.validationError == nil && !($0.entry.calendarSourceKey ?? "").isEmpty
                }))
            && (connection == nil || (!connection!.calendarIDs.isEmpty && TimeZone(identifier: connection!.timeZoneID) != nil))
    }

    /// Older projects applied to one screen's visible desktop. The requested new
    /// default covers every Space and display without changing automation opt-ins.
    /// Keep the old receipt so its narrower scope cannot count as an all-Space apply.
    @discardableResult
    mutating func migrateWallpaperScope() -> Bool {
        guard (1...2).contains(version) else { return false }
        var settings = automation ?? AutomationSettings()
        settings.targetDisplayID = WallpaperDisplay.allSpacesID
        settings.targetDisplayName = WallpaperDisplay.allSpaces.name
        automation = settings
        version = 3
        return true
    }
}
