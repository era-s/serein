import AppKit
import Foundation

/// Runs the real AppStore and automation engine using their explicit demo path.
/// No app scene is launched, and no system Calendar or wallpaper service is used.
@main
struct CalendarVisibilityAppVerification {
    @MainActor private static var assertions = 0

    @MainActor
    private static func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else { throw Failure(description: description) }
        assertions += 1
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor
    private static func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try check(condition(), description)
    }

    @MainActor
    static func main() async {
        do {
            guard CommandLine.arguments.contains("--automation-demo") else {
                throw Failure(description: "This verification must use --automation-demo")
            }
            guard let temporaryRoot = ProcessInfo.processInfo.environment["SEREIN_VERIFICATION_TEMP_DIR"],
                  URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL
                    == URL(fileURLWithPath: temporaryRoot).resolvingSymlinksInPath().standardizedFileURL else {
                throw Failure(description: "The shell wrapper must protect the actual system temporary demo output")
            }

            let store = AppStore()
            try check(store.isDemo, "AppStore must stay on the safe demo path")
            try check(store.entries.isEmpty, "Demo automation starts with an empty timetable")
            try check(store.calendarConnection != nil, "Demo calendar connection is available")
            try check(store.calendarVisibility.exclusions.isEmpty, "Demo starts without hidden events")

            let provider = DemoCalendarProvider()
            let zone = TimeZone(identifier: "Asia/Seoul")!
            let week = CalendarWeek(containing: store.now, timeZone: zone)
            let calendars: Set<String> = ["demo-study", "demo-personal"]
            let originalRecords = try await provider.events(calendarIDs: calendars, week: week)
            let originalEntries = CalendarEventConverter.convert(originalRecords, week: week).entries
            let originalSourceKeys = Set(originalEntries.compactMap(\.calendarSourceKey))
            try check(originalEntries.count == 5, "Immutable demo source contains five timed events")

            store.automationSettings.refreshOnCalendarChange = true
            try await waitFor("Enabling real AppStore automation imports five demo events") {
                store.entries.count == 5 && store.automationReceipt != nil && !store.automation.isChecking
            }
            try check(store.entries.allSatisfy { $0.calendarEventKey != nil && $0.calendarOccurrenceKey != nil },
                      "Imported rows include persistent event and occurrence identities")
            let originalSettings = store.automationSettings
            let victim = store.sortedEntries[0]
            let visibleAfterHide = originalSourceKeys.subtracting([victim.calendarSourceKey!])

            store.remove(victim.id)
            try check(store.entries.count == 4, "Removing an imported event immediately removes its row")
            try check(store.calendarVisibility.exclusions.count == 1, "Removing an imported event creates one persistent exclusion")
            try check(store.calendarVisibility.exclusions[0].scope == .event, "Default removal hides the event and future repetitions")
            try check(store.calendarVisibility.isHidden(victim), "Removed event matches the saved hide preference")
            try check(store.automationSettings == originalSettings, "Hiding an event keeps automation options unchanged")

            let saved = SavedStudio(entries: store.entries, configuration: store.configuration,
                                    automation: store.automationSettings, connection: store.calendarConnection,
                                    receipt: store.automationReceipt, calendarVisibility: store.calendarVisibility)
            let decoded = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(saved))
            try check(decoded.isValid, "The real SavedStudio model accepts the hidden-event state")
            try check(decoded.entries.count == 4 && decoded.calendarVisibility?.isHidden(victim) == true,
                      "SavedStudio serialization retains both visible rows and the hide preference")

            await store.automation.check(trigger: .calendarChanged, now: store.now)
            try check(store.entries.count == 4, "A calendar change does not restore the removed event")
            await store.automation.check(trigger: .manual, now: store.now)
            try check(Set(store.entries.compactMap(\.calendarSourceKey)) == visibleAfterHide,
                      "Manual refresh keeps exactly the four unhidden source events")
            // Let the AppStore's own debounced edit check run as it does in the
            // app, in addition to the direct engine checks above.
            try await Task.sleep(for: .milliseconds(800))
            try check(store.entries.count == 4, "The AppStore's scheduled refresh also preserves the hide")

            let exclusionID = store.calendarVisibility.exclusions[0].id
            store.restoreHiddenCalendarEntry(exclusionID)
            try await waitFor("Restoring through AppStore retrieves the fifth event") {
                store.entries.count == 5 && store.calendarVisibility.exclusions.isEmpty && !store.automation.isChecking
            }
            try check(Set(store.entries.compactMap(\.calendarSourceKey)) == originalSourceKeys,
                      "Restore returns the complete original source set without duplicates")
            try check(store.automationSettings == originalSettings, "Restore also keeps automation options unchanged")

            let manual = ScheduleEntry(name: "Manual verification class", day: 0,
                                       startMinutes: 9 * 60, endMinutes: 9 * 60 + 30)
            store.save(manual)
            try check(store.entries.count == 6, "A manual class can coexist with imported calendar rows")
            store.remove(manual.id)
            try check(store.entries.count == 5 && store.calendarVisibility.exclusions.isEmpty,
                      "Deleting a manual class does not create a calendar exclusion")

            store.clearEntries()
            try check(store.entries.isEmpty, "Clearing the timetable immediately removes every displayed row")
            try check(store.calendarVisibility.exclusions.count == 5, "Clearing preserves hide preferences for all five calendar events")
            await store.automation.check(trigger: .manual, now: store.now)
            await store.automation.check(trigger: .calendarChanged, now: store.now)
            try check(store.entries.isEmpty, "Manual and calendar refresh keep a cleared timetable empty")
            try await Task.sleep(for: .milliseconds(800))
            try check(store.entries.isEmpty && store.calendarVisibility.exclusions.count == 5,
                      "The scheduled AppStore update retains an empty timetable and all exclusions")

            let reviewStore = AppStore()
            let deselected = originalEntries[0]
            let selected = Array(originalEntries.dropFirst())
            let reviewConnection = CalendarConnection(calendarIDs: calendars,
                calendarNames: ["Study", "Personal"], weekStart: week.start, timeZoneID: zone.identifier,
                managedEntryKeys: Set(selected.compactMap(\.calendarSourceKey)), includeWeekTitle: true)
            reviewStore.importCalendarEntries(selected, replace: true, subtitle: week.label,
                                              connection: reviewConnection, excluded: [deselected])
            try check(reviewStore.entries.count == 4, "Calendar review imports only its four selected rows")
            try check(reviewStore.calendarVisibility.exclusions.count == 1,
                      "An explicitly deselected review row creates a persistent exclusion")
            try check(reviewStore.calendarVisibility.isHidden(deselected)
                        && reviewStore.calendarVisibility.exclusions[0].scope == .event,
                      "Review deselection hides the source event and its future repetitions")
            reviewStore.automationSettings.refreshOnCalendarChange = true
            try await waitFor("Enabling automation respects the calendar review exclusion") {
                reviewStore.entries.count == 4 && reviewStore.automationReceipt != nil && !reviewStore.automation.isChecking
            }
            await reviewStore.automation.check(trigger: .manual, now: reviewStore.now)
            try check(reviewStore.entries.count == 4 && !reviewStore.entries.contains { $0.calendarSourceKey == deselected.calendarSourceKey },
                      "Manual synchronization does not resurrect a deselected review row")
            reviewStore.importCalendarEntries(originalEntries, replace: true, subtitle: nil, connection: reviewConnection)
            try check(reviewStore.entries.count == 4 && reviewStore.calendarVisibility.isHidden(deselected),
                      "Reimporting all source rows cannot silently undo a saved exclusion")
            reviewStore.restoreHiddenCalendarEntry(reviewStore.calendarVisibility.exclusions[0].id)
            try await waitFor("Explicitly restoring a review exclusion recovers the fifth source event") {
                reviewStore.entries.count == 5 && reviewStore.calendarVisibility.exclusions.isEmpty
            }
            try check(reviewStore.error == nil, "Review exclusion and restore finish without an application error")

            let unchangedRecords = try await provider.events(calendarIDs: calendars, week: week)
            let unchangedEntries = CalendarEventConverter.convert(unchangedRecords, week: week).entries
            try check(unchangedRecords.count == originalRecords.count,
                      "Hiding and clearing never remove records from the demo calendar source")
            try check(Set(unchangedEntries.compactMap(\.calendarSourceKey)) == originalSourceKeys,
                      "All five original source events remain available after local exclusions")
            try check(store.error == nil, "Real AppStore operations finish without an application error")
            print("Verified \(assertions) real AppStore calendar-visibility assertions using demo providers only.")
            print("No app window was opened; Calendar permissions, login items and system wallpapers were not changed.")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Calendar visibility AppStore verification failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
