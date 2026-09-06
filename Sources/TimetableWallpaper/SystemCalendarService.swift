import AppKit
import CryptoKit
import EventKit
import Foundation

/// EventKit exposes calendars configured in macOS, including Google accounts
/// enabled in the Calendar app. This adapter never modifies calendar data.
@MainActor
final class SystemCalendarService: CalendarProviding {
    // A single store owns all of its EventKit objects. Do not fetch before consent.
    private lazy var store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined, .writeOnly: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// Only the explicit Connect action should call this method.
    func requestAccess() async throws -> Bool {
        if access == .authorized { return true }
        guard access == .notDetermined else { return false }
        let granted = try await store.requestFullAccessToEvents()
        guard granted, access == .authorized else { return false }
        store.reset()
        return true
    }

    func calendars() throws -> [CalendarDescriptor] {
        try requireAccess()
        return store.calendars(for: .event).map { calendar in
            CalendarDescriptor(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                // Source titles are account labels, not evidence of a provider.
                account: calendar.source?.title ?? "Mac 캘린더",
                colorHex: Self.colorHex(calendar.cgColor)
            )
        }.sorted {
            if $0.account != $1.account { return $0.account.localizedStandardCompare($1.account) == .orderedAscending }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        try requireAccess()
        guard !calendarIDs.isEmpty else { throw CalendarImportError.noCalendarsSelected }
        let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        // Never pass nil/an empty array to the predicate: that can mean all calendars.
        guard Set(selected.map(\.calendarIdentifier)) == calendarIDs else {
            throw CalendarImportError.calendarsChanged
        }
        let predicate = store.predicateForEvents(withStart: week.start, end: week.end, calendars: selected)
        // This predicate expands recurring series into their actual occurrences,
        // including detached occurrences. Do not expand recurrence rules ourselves.
        let records = try store.events(matching: predicate).map { event -> CalendarEventRecord in
            guard let calendarID = event.calendar?.calendarIdentifier, calendarIDs.contains(calendarID) else {
                throw CalendarImportError.calendarsChanged
            }
            let hasDates = event.startDate != nil && event.endDate != nil
            return CalendarEventRecord(
                id: Self.eventID(event),
                calendarID: calendarID,
                title: event.title ?? "",
                // An incomplete event is represented as an invalid interval so
                // conversion reports an exclusion instead of inventing a time.
                startDate: hasDates ? event.startDate : .distantPast,
                endDate: hasDates ? event.endDate : .distantPast,
                location: event.location ?? "",
                isAllDay: event.isAllDay,
                isCancelled: event.status == .canceled,
                isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
                occurrenceDate: event.occurrenceDate
            )
        }
        try requireAccess()
        return records
    }

    private func requireAccess() throws {
        guard access == .authorized else { throw CalendarImportError.permissionDenied }
    }

    private static func eventID(_ event: EKEvent) -> String {
        if let identifier = event.eventIdentifier, !identifier.isEmpty { return identifier }
        if !event.calendarItemIdentifier.isEmpty { return event.calendarItemIdentifier }
        if let identifier = event.calendarItemExternalIdentifier, !identifier.isEmpty { return identifier }
        // Unsaved/malformed events can lack an ID. A content-derived fallback
        // remains deterministic and never turns a missing ID into a random UUID.
        let parts = [event.calendar?.calendarIdentifier ?? "", event.title ?? "", event.location ?? "",
                     event.startDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "",
                     event.endDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? ""]
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return "fallback-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func colorHex(_ cgColor: CGColor?) -> UInt32 {
        guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return 0x82927B }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return (byte(color.redComponent) << 16) | (byte(color.greenComponent) << 8) | byte(color.blueComponent)
    }
}
