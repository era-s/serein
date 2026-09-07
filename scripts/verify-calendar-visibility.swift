import Foundation

/// Synthetic calendar records, memory-only application sink, and in-memory JSON
/// round trips. Never requests permission or changes a real calendar/desktop.
@main @MainActor
enum CalendarVisibilityVerification {
    private static var checks = 0
    private static let zone = TimeZone(identifier: "Asia/Seoul")!
    private static let wednesday = date("2026-09-09T12:00:00+09:00")
    private static let nextMonday = date("2026-09-14T00:00:00+09:00")

    private static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        guard value() else { fatalError("FAIL: \(description)") }
        checks += 1
        print("PASS: \(description)")
    }
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func event(_ id: String = "occurrence-one", series: String = "series-a", title: String = "Design class",
        start: String = "2026-09-09T10:00:00+09:00", end: String = "2026-09-09T11:00:00+09:00",
        calendar: String = "school") -> CalendarEventRecord {
        .init(id: id, calendarID: calendar, title: title, startDate: date(start), endDate: date(end),
              location: "Room 301", occurrenceDate: date(start), seriesID: series)
    }
    private static func converted(_ events: [CalendarEventRecord], now: Date? = nil) -> [ScheduleEntry] {
        CalendarEventConverter.convert(events, week: CalendarWeek(containing: now ?? wednesday, timeZone: zone)).entries
    }
    private static func context(changes: Bool = true, weekly: Bool = true) -> AutomationContext {
        .init(entries: [], configuration: .init(),
              settings: .init(refreshOnCalendarChange: changes, refreshWeekly: weekly, targetDisplayID: "fixture-display"),
              connection: .init(calendarIDs: ["school"], calendarNames: ["Fixture calendar"],
                  weekStart: CalendarWeek(containing: wednesday, timeZone: zone).start, timeZoneID: zone.identifier,
                  managedEntryKeys: [], includeWeekTitle: true), receipt: nil, timeZone: zone)
    }

    private static func checkIdentityAndModel() throws {
        let first = converted([event()])[0]
        let unrelated = converted([event("unrelated", series: "other-series")])[0]
        let otherCalendar = converted([event(calendar: "other-calendar")])[0]
        var edited = event("detached-occurrence")
        edited.title = "Renamed class"
        edited.location = "A different room"
        edited.startDate = date("2026-09-10T14:00:00+09:00")
        edited.endDate = date("2026-09-10T15:00:00+09:00")
        let moved = converted([edited])[0]
        expect(first.calendarEventKey == moved.calendarEventKey && first.calendarOccurrenceKey == moved.calendarOccurrenceKey,
               "Renaming, moving, relocating and detaching an occurrence preserve its event/occurrence identities")
        expect(first.calendarEventKey != unrelated.calendarEventKey && first.calendarEventKey != otherCalendar.calendarEventKey,
               "Equal titles in another event or calendar retain separate identities")

        var visibility = CalendarVisibility()
        visibility.hide(first)
        expect(visibility.exclusions.count == 1 && visibility.exclusions[0].scope == .event,
               "The default exclusion applies to the entire calendar event or recurring series")
        expect(visibility.isHidden(first) && visibility.isHidden(moved) && !visibility.isHidden(unrelated) && !visibility.isHidden(otherCalendar),
               "Hidden events follow identity rather than title, time or calendar label")
        let manual = ScheduleEntry(name: first.name, day: first.day, startMinutes: first.startMinutes, endMinutes: first.endMinutes)
        visibility.hide(manual)
        expect(visibility.exclusions.count == 1 && !visibility.isHidden(manual), "Manual entries are never hidden by matching text or empty calendar identities")
        visibility.hide(moved)
        expect(visibility.exclusions.count == 1, "Hiding the same event repeatedly creates only one preference")
        let originalID = visibility.exclusions[0].id
        visibility.reconcile(with: [moved, unrelated])
        expect(visibility.exclusions[0].id == originalID && visibility.exclusions[0].entry.name == moved.name,
               "Reconciliation refreshes the hidden preview while preserving the preference identity")
        let reconciled = visibility
        var freshUUID = moved; freshUUID.id = UUID()
        visibility.reconcile(with: [unrelated, freshUUID])
        expect(visibility == reconciled, "Fresh query UUIDs and ordering do not churn saved exclusions")
        visibility.reconcile(with: [])
        expect(visibility == reconciled, "A missing week or deleted source does not silently erase a hidden preference")
        let restored = try JSONDecoder().decode(CalendarVisibility.self, from: JSONEncoder().encode(visibility))
        expect(restored == visibility && restored.isHidden(moved), "Exclusions and stable identities survive serialization")

        var legacy = first; legacy.calendarEventKey = nil; legacy.calendarOccurrenceKey = nil
        var legacyVisibility = CalendarVisibility()
        legacyVisibility.hide(legacy)
        legacyVisibility.reconcile(with: [first])
        expect(legacyVisibility.isHidden(moved) && legacyVisibility.exclusions[0].entry.calendarEventKey == first.calendarEventKey,
               "Legacy source-only exclusions hydrate to stable event identities before filtering")
        var scope = CalendarVisibility()
        scope.hide(first, scope: .occurrence)
        let occurrencePreferenceID = scope.exclusions[0].id
        scope.hide(first, scope: .event)
        expect(scope.exclusions.count == 1 && scope.exclusions[0].scope == .event && scope.exclusions[0].id == occurrencePreferenceID,
               "Widening one occurrence to its event consolidates the preference without changing its identity")
        expect(scope.restore(occurrencePreferenceID) != nil && !scope.isHidden(first), "Restoring an exclusion makes that event eligible again")
    }

    private static func checkSynchronizationAndRestart() async throws {
        let record = event()
        let unrelated = event("other-occurrence", series: "other-series")
        let hiddenKey = converted([record])[0].calendarEventKey
        let manual = ScheduleEntry(name: record.title, day: 2, startMinutes: 900, endMinutes: 960)
        var initial = context(); initial.entries = [manual]
        let harness = VisibilityHarness(initial)
        harness.provider.records = [record, unrelated]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let hidden = harness.context.entries.first { $0.calendarEventKey == hiddenKey }!
        harness.hide(hidden)
        await harness.engine.check(trigger: .settingsChanged, now: wednesday.addingTimeInterval(60))
        harness.acceptLatest()
        expect(harness.sink.writes == 2 && harness.context.entries.count == 2
               && harness.context.entries.contains(manual) && !harness.context.entries.contains { $0.calendarEventKey == hiddenKey },
               "Deleting an imported event stays hidden on the next sync while equal-title manual and unrelated events remain")
        expect(harness.context.calendarVisibility.exclusions.count == 1, "Applied updates retain the user's hidden preferences")
        let appliedAt = harness.context.receipt?.appliedAt
        var renamed = record
        renamed.title = "Hidden source changed"
        renamed.startDate = date("2026-09-10T14:00:00+09:00")
        renamed.endDate = date("2026-09-10T15:00:00+09:00")
        harness.provider.records = [renamed, unrelated]
        let stateCount = harness.sink.states.count
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(120))
        expect(harness.sink.writes == 2 && harness.sink.states.count == stateCount + 1,
               "Changes only to hidden source details persist metadata without rewriting the wallpaper")
        harness.acceptLatest()
        expect(harness.context.calendarVisibility.exclusions[0].entry.name == renamed.title && harness.context.receipt?.appliedAt == appliedAt,
               "Hidden preview metadata updates without changing the last actual application time")
        let refreshedStateCount = harness.sink.states.count
        await harness.engine.check(trigger: .clock, now: wednesday.addingTimeInterval(121))
        expect(harness.sink.states.count == refreshedStateCount && harness.sink.writes == 2,
               "Repeated queries with unchanged hidden content cause neither wallpaper writes nor preference rewrites")

        let restarted = VisibilityHarness(try harness.roundTripContext())
        restarted.provider.records = [renamed, unrelated]
        await restarted.engine.check(trigger: .launch, now: wednesday.addingTimeInterval(180))
        expect(restarted.sink.writes == 0 && restarted.context.calendarVisibility.isHidden(hidden),
               "Restarting from a saved studio does not revive hidden events or rewrite an unchanged wallpaper")
        restarted.acceptLatestIfPresent()
        let nextHidden = event("next-detached-id", title: "Following week's hidden event", start: "2026-09-16T10:00:00+09:00", end: "2026-09-16T11:00:00+09:00")
        let nextOther = event("next-other-id", series: "other-series", start: "2026-09-16T10:00:00+09:00", end: "2026-09-16T11:00:00+09:00")
        restarted.provider.records = [nextHidden, nextOther]
        await restarted.engine.check(trigger: .clock, now: nextMonday)
        restarted.acceptLatest()
        expect(restarted.context.entries.count == 2 && !restarted.context.entries.contains { $0.calendarEventKey == hiddenKey }
               && restarted.context.calendarVisibility.isHidden(converted([nextHidden], now: nextMonday)[0]),
               "A future recurrence remains hidden after the weekly rollover even when its occurrence ID changes")
        let exclusionID = restarted.context.calendarVisibility.exclusions[0].id
        restarted.context.calendarVisibility.restore(exclusionID)
        restarted.engine.configure(restarted.context)
        await restarted.engine.check(trigger: .manual, now: nextMonday)
        restarted.acceptLatest()
        expect(restarted.context.calendarVisibility.exclusions.isEmpty && restarted.context.entries.count == 3
               && restarted.context.entries.contains { $0.calendarEventKey == hiddenKey },
               "Restoring a preference brings back the current source occurrence through a fresh sync")
        expect(restarted.provider.permissionRequests == 0 && harness.provider.permissionRequests == 0,
               "Hide, restart, rollover and restore never request permission or write calendar data")
    }

    private static func checkOvernightOccurrence() async {
        let first = event("overnight-one", start: "2026-09-09T23:00:00+09:00", end: "2026-09-10T01:00:00+09:00")
        let second = event("overnight-two", start: "2026-09-11T23:00:00+09:00", end: "2026-09-12T01:00:00+09:00")
        let pieces = converted([first, second])
        expect(pieces.count == 4 && pieces[0].calendarOccurrenceKey == pieces[1].calendarOccurrenceKey
               && pieces[0].calendarOccurrenceKey != pieces[2].calendarOccurrenceKey,
               "Midnight segments share an occurrence identity while another recurrence stays distinct")
        let harness = VisibilityHarness(context())
        harness.provider.records = [first, second]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let occurrence = converted([first])[0].calendarOccurrenceKey
        harness.hide(harness.context.entries.first { $0.calendarOccurrenceKey == occurrence }!, scope: .occurrence)
        await harness.engine.check(trigger: .calendarChanged, now: wednesday)
        harness.acceptLatest()
        expect(harness.context.entries.count == 2 && harness.context.entries.allSatisfy { $0.calendarOccurrenceKey != occurrence },
               "Occurrence-only hiding removes both sides of midnight but retains the other recurrence")
    }

    private static func checkFailuresOptOutAndRestoredRows() async throws {
        let harness = VisibilityHarness(context())
        harness.provider.records = [event()]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let hidden = harness.context.entries[0]
        let receipt = harness.context.receipt
        harness.hide(hidden)
        let persistedPreference = try harness.roundTripContext().calendarVisibility
        harness.sink.fails = true
        await harness.engine.check(trigger: .settingsChanged, now: wednesday)
        expect(harness.sink.writes == 1 && harness.context.receipt == receipt
               && harness.context.calendarVisibility == persistedPreference && harness.context.entries.isEmpty,
               "A native apply failure cannot roll back the separately persisted hide preference or advance its receipt")
        harness.sink.fails = false
        await harness.engine.check(trigger: .wake, now: wednesday)
        harness.acceptLatest()
        expect(harness.context.entries.isEmpty && harness.context.calendarVisibility.isHidden(hidden),
               "Retrying after a failed wallpaper application still excludes the hidden source")

        harness.context.settings.refreshOnCalendarChange = false
        harness.context.settings.refreshWeekly = false
        harness.engine.configure(harness.context)
        let reads = harness.provider.reads
        let writes = harness.sink.writes
        await harness.engine.check(trigger: .manual, now: wednesday)
        await harness.engine.check(trigger: .clock, now: nextMonday)
        expect(harness.provider.reads == reads && harness.sink.writes == writes && harness.context.calendarVisibility.isHidden(hidden),
               "Disabling automation stops reads and wallpaper writes without forgetting hidden preferences")

        let remotelyDeleted = VisibilityHarness(try harness.roundTripContext())
        remotelyDeleted.context.calendarVisibility.restore(remotelyDeleted.context.calendarVisibility.exclusions[0].id)
        remotelyDeleted.context.settings.refreshOnCalendarChange = true
        remotelyDeleted.engine.configure(remotelyDeleted.context)
        await remotelyDeleted.engine.check(trigger: .manual, now: wednesday)
        remotelyDeleted.acceptLatestIfPresent()
        expect(remotelyDeleted.provider.reads == 1 && remotelyDeleted.context.entries.isEmpty && remotelyDeleted.context.calendarVisibility.exclusions.isEmpty,
               "Restoring an event that no longer exists in the source does not resurrect a stale saved occurrence")

        harness.context.calendarVisibility.restore(harness.context.calendarVisibility.exclusions[0].id)
        harness.context.entries = [hidden] // A restored row is no longer in managedEntryKeys.
        harness.context.settings.refreshOnCalendarChange = true
        harness.engine.configure(harness.context)
        await harness.engine.check(trigger: .manual, now: wednesday)
        harness.acceptLatest()
        expect(harness.context.entries.count == 1 && Set(harness.context.entries.map(\.id)).count == 1,
               "An existing restored source row is replaced once rather than duplicated with an incoming copy")

        var noManagedOwnership = context()
        noManagedOwnership.entries = [hidden]
        noManagedOwnership.calendarVisibility.hide(hidden)
        let unmanaged = VisibilityHarness(noManagedOwnership)
        unmanaged.provider.records = []
        await unmanaged.engine.check(trigger: .enabled, now: wednesday)
        unmanaged.acceptLatest()
        expect(unmanaged.context.entries.isEmpty && unmanaged.context.calendarVisibility.isHidden(hidden),
               "Hidden stale imported rows are removed even when absent from managedEntryKeys and the current source query")
    }

    private static func checkStaleReadAfterHide() async {
        let harness = VisibilityHarness(context())
        harness.provider.records = [event()]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        harness.provider.suspends = true
        let first = Task { await harness.engine.check(trigger: .calendarChanged, now: wednesday) }
        await waitForReads(2, in: harness.provider)
        let entry = harness.context.entries[0]
        harness.hide(entry)
        let newest = Task { await harness.engine.check(trigger: .settingsChanged, now: wednesday) }
        await Task.yield()
        harness.provider.complete(1, records: [event(title: "An old awaited response")])
        await waitForReads(3, in: harness.provider)
        expect(harness.sink.writes == 1, "Hiding while a calendar query is in flight invalidates the earlier unfiltered response")
        harness.provider.complete(2, records: [event(title: "The latest hidden response")])
        await first.value
        await newest.value
        harness.acceptLatest()
        expect(harness.sink.writes == 2 && harness.context.entries.isEmpty
               && harness.context.calendarVisibility.exclusions[0].entry.name == "The latest hidden response",
               "Only the latest query may apply after hiding, and it persists the hidden state rather than reviving the event")
    }

    private static func waitForReads(_ count: Int, in provider: VisibilityProvider) async {
        for _ in 0..<10_000 {
            if provider.reads >= count { return }
            await Task.yield()
        }
        fatalError("The expected synthetic calendar read did not start")
    }

    static func main() async throws {
        try checkIdentityAndModel()
        try await checkSynchronizationAndRestart()
        await checkOvernightOccurrence()
        try await checkFailuresOptOutAndRestoredRows()
        await checkStaleReadAfterHide()
        print("Calendar visibility verification completed: \(checks) checks passed using synthetic fixtures only.")
    }
}

@MainActor private final class VisibilityProvider: CalendarProviding {
    var access: CalendarAccess = .authorized
    var records: [CalendarEventRecord] = []
    var permissionRequests = 0
    var reads = 0
    var suspends = false
    private var pending: [Int: CheckedContinuation<[CalendarEventRecord], Error>] = [:]
    func requestAccess() async throws -> Bool { permissionRequests += 1; return false }
    func calendars() throws -> [CalendarDescriptor] {
        [.init(id: "school", title: "Fixture calendar", account: "Synthetic", colorHex: 0)]
    }
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        let index = reads
        reads += 1
        if suspends { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        return records.filter { calendarIDs.contains($0.calendarID) }
    }
    func complete(_ index: Int, records: [CalendarEventRecord]) {
        guard let continuation = pending.removeValue(forKey: index) else { fatalError("Missing synthetic read") }
        continuation.resume(returning: records)
    }
}

@MainActor private final class VisibilitySink {
    var states: [AutomationUpdate] = []
    var writes = 0
    var fails = false
    func apply(_ update: AutomationUpdate) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        writes += 1
        states.append(update)
    }
}

@MainActor private final class VisibilityHarness {
    let provider = VisibilityProvider()
    let sink = VisibilitySink()
    let engine: WallpaperAutomation
    var context: AutomationContext
    init(_ context: AutomationContext) {
        self.context = context
        let sink = self.sink
        engine = WallpaperAutomation(provider: provider, apply: { try sink.apply($0) }, onStateChange: { sink.states.append($0) })
        engine.configure(context)
    }
    func hide(_ entry: ScheduleEntry, scope: CalendarExclusionScope = .event) {
        context.calendarVisibility.hide(entry, scope: scope)
        let visibility = context.calendarVisibility
        context.entries.removeAll { visibility.isHidden($0) }
        engine.configure(context)
    }
    func acceptLatestIfPresent() { if !sink.states.isEmpty { acceptLatest() } }
    func acceptLatest() {
        guard let latest = sink.states.last else { fatalError("No synthetic state to accept") }
        context.entries = latest.entries
        context.configuration = latest.configuration
        context.connection = latest.connection
        context.receipt = latest.receipt
        context.calendarVisibility = latest.calendarVisibility
        engine.configure(context)
    }
    func roundTripContext() throws -> AutomationContext {
        let saved = SavedStudio(entries: context.entries, configuration: context.configuration, automation: context.settings,
            connection: context.connection, receipt: context.receipt, calendarVisibility: context.calendarVisibility)
        let decoded = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(saved))
        guard decoded.isValid else { fatalError("Saved visibility fixture was invalid") }
        return AutomationContext(entries: decoded.entries, configuration: decoded.configuration,
            settings: decoded.automation!, connection: decoded.connection, receipt: decoded.receipt,
            calendarVisibility: decoded.calendarVisibility ?? CalendarVisibility(), timeZone: context.timeZone)
    }
}
