import Foundation

/// Calendar arithmetic, render inputs and automation are exercised using fixed
/// dates, synthetic calendars and an in-memory sink. No real permissions or
/// desktop image APIs are invoked.
@main @MainActor
enum WeekdayLabelVerification {
    private static var checks = 0
    private static let zone = TimeZone(identifier: "Asia/Seoul")!
    private static let wednesday = date("2026-09-09T12:00:00+09:00")
    private static let nextMonday = date("2026-09-14T00:00:00+09:00")
    private static let septemberWeek = ["09.07", "09.08", "09.09", "09.10", "09.11", "09.12", "09.13"]
    private static let nextWeek = ["09.14", "09.15", "09.16", "09.17", "09.18", "09.19", "09.20"]

    private static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }
    private static func connection(start: Date? = nil, timeZoneID: String = "Asia/Seoul") -> CalendarConnection {
        .init(calendarIDs: ["fixture-calendar"], calendarNames: ["Fixture"],
              weekStart: start ?? date("2026-09-07T00:00:00+09:00"), timeZoneID: timeZoneID,
              managedEntryKeys: [], includeWeekTitle: false)
    }
    private static func effective(_ configuration: WallpaperConfiguration, connection selected: CalendarConnection?,
                                  now: Date? = nil, timeZone: TimeZone? = nil, showToday: Bool = false) -> WallpaperConfiguration {
        WallpaperAutomation.effectiveConfiguration(configuration, settings: .init(showToday: showToday),
            connection: selected, now: now ?? wednesday, timeZone: timeZone ?? zone)
    }

    private static func checkCalendarBoundaries() {
        let cases: [(String, String, [String], String)] = [
            ("2026-08-31T00:00:00+09:00", "Asia/Seoul", ["08.31", "09.01", "09.02", "09.03", "09.04", "09.05", "09.06"], "month boundary"),
            ("2026-12-28T00:00:00+09:00", "Asia/Seoul", ["12.28", "12.29", "12.30", "12.31", "01.01", "01.02", "01.03"], "year boundary"),
            ("2028-02-28T00:00:00+09:00", "Asia/Seoul", ["02.28", "02.29", "03.01", "03.02", "03.03", "03.04", "03.05"], "leap day"),
            ("2026-02-23T00:00:00+09:00", "Asia/Seoul", ["02.23", "02.24", "02.25", "02.26", "02.27", "02.28", "03.01"], "non-leap February"),
            ("2026-03-02T00:00:00-05:00", "America/New_York", ["03.02", "03.03", "03.04", "03.05", "03.06", "03.07", "03.08"], "spring DST week"),
            ("2026-10-26T00:00:00-04:00", "America/New_York", ["10.26", "10.27", "10.28", "10.29", "10.30", "10.31", "11.01"], "autumn DST week"),
            ("2026-10-26T00:00:00+03:00", "Africa/Cairo", ["10.26", "10.27", "10.28", "10.29", "10.30", "10.31", "11.01"], "midweek backward DST transition")
        ]
        for (start, timeZone, expected, label) in cases {
            expect(WeekdayHeaderDates.labels(weekStart: date(start), timeZoneID: timeZone) == expected,
                   "Seven MM.dd labels remain correct through the \(label)")
        }
        let cairo = TimeZone(identifier: "Africa/Cairo")!
        expect(cairo.secondsFromGMT(for: date("2026-10-26T00:00:00+03:00")) != cairo.secondsFromGMT(for: date("2026-11-01T00:00:00+02:00")),
               "The midweek DST fixture actually crosses an offset change that fixed 24-hour stepping would mishandle")
        expect(WeekdayHeaderDates.labels(weekStart: date("2026-09-07T14:30:00+09:00"), timeZoneID: "Asia/Seoul") == septemberWeek,
               "A valid Monday snapshot normalizes its time of day before generating labels")
        expect(WeekdayHeaderDates.labels(weekStart: date("2026-09-07T00:00:00+09:00"), timeZoneID: "Invalid/Zone") == nil,
               "An unknown saved time zone does not invent dates")
        expect(WeekdayHeaderDates.labels(weekStart: date("2026-09-06T00:00:00+09:00"), timeZoneID: "Asia/Seoul") == nil,
               "A non-Monday snapshot is rejected instead of shifting the displayed week")
        expect(WeekdayHeaderDates.labels(weekStart: Date(timeIntervalSince1970: .nan), timeZoneID: "Asia/Seoul") == nil
               && WeekdayHeaderDates.labels(weekStart: Date(timeIntervalSince1970: .infinity), timeZoneID: "Asia/Seoul") == nil,
               "Non-finite dates are rejected before calendar conversion")
    }

    private static func checkDefaultsAndSelections() throws {
        let automatic = effective(.init(), connection: connection())
        expect(automatic.weekdayNumberStyle == nil && automatic.weekdayDateLabels == septemberWeek
               && WallpaperRenderer.weekdayNumber(for: 0, configuration: automatic) == "09.07",
               "The automatic style shows the selected week's actual dates when a calendar is connected")
        expect(automatic.highlightedDay == nil && automatic.weekdayDateLabels != nil,
               "Date headers remain available when today's indicator is turned off")
        let manual = effective(.init(), connection: nil)
        expect(manual.weekdayNumberStyle == nil && manual.weekdayDateLabels == nil
               && WallpaperRenderer.weekdayNumber(for: 0, configuration: manual) == "01",
               "The automatic style preserves ordinal numbers for an unconnected manual timetable")

        for style in WeekdayNumberStyle.allCases {
            var base = WallpaperConfiguration()
            base.weekdayNumberStyle = style
            base.weekdayDateLabels = nextWeek // A stale derived field must not survive a style change.
            let configured = effective(base, connection: connection())
            expect(configured.weekdayNumberStyle == style,
                   "Effective configuration retains the explicit \(style.rawValue) choice")
            switch style {
            case .date:
                expect(configured.weekdayDateLabels == septemberWeek
                       && WallpaperRenderer.weekdayNumber(for: 6, configuration: configured) == "09.13",
                       "Explicit date style replaces stale labels with dates from the saved connection")
            case .ordinal:
                expect(configured.weekdayDateLabels == nil
                       && WallpaperRenderer.weekdayNumber(for: 6, configuration: configured) == "07",
                       "Explicit ordinal style clears derived date labels and preserves its original numbering")
            case .hidden:
                expect(configured.weekdayDateLabels == nil
                       && (0..<7).allSatisfy { WallpaperRenderer.weekdayNumber(for: $0, configuration: configured) == nil },
                       "Hidden style clears stale dates and removes every secondary weekday label")
            }
        }
        var dateOnly = WallpaperConfiguration()
        dateOnly.weekdayNumberStyle = .date
        dateOnly.weekdayDateLabels = septemberWeek
        let disconnected = effective(dateOnly, connection: nil)
        expect(disconnected.weekdayDateLabels == nil && disconnected.weekdayNumberStyle == .date
               && WallpaperRenderer.weekdayNumber(for: 0, configuration: disconnected) == nil,
               "Explicit date style without a calendar shows no invented date or ordinal fallback")
        let invalidConnection = effective(.init(), connection: connection(timeZoneID: "Invalid/Zone"))
        expect(WallpaperRenderer.weekdayNumber(for: 0, configuration: invalidConnection) == nil,
               "An invalid connected date source stays blank rather than falling back to a misleading ordinal")

        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let oldWeek = effective(dateOnly, connection: connection(), now: date("2026-09-21T12:00:00+09:00"),
                                timeZone: losAngeles, showToday: true)
        expect(oldWeek.weekdayDateLabels == septemberWeek && oldWeek.highlightedDay == nil,
               "An old selected week retains its saved time zone and dates even when now and the Mac's zone differ")

        let oldJSON = Data("""
        {"theme":"ember","resolution":"macbook14","title":"Legacy","subtitle":"Fall","showLocations":true,"showWeekends":false,"showTexture":true,"startHour":9,"endHour":18}
        """.utf8)
        let decoded = try JSONDecoder().decode(WallpaperConfiguration.self, from: oldJSON)
        expect(decoded.weekdayNumberStyle == nil && decoded.weekdayDateLabels == nil
               && decoded.title == "Legacy", "Older saved configuration JSON loads without either new weekday-label field")
        for style in WeekdayNumberStyle.allCases {
            var base = decoded; base.weekdayNumberStyle = style
            let saved = SavedStudio(entries: [], configuration: base)
            let restored = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(saved))
            expect(restored.isValid && restored.configuration.weekdayNumberStyle == style
                   && restored.configuration.weekdayDateLabels == nil,
                   "The explicit \(style.rawValue) preference survives a saved-studio round trip without derived dates")
        }
        var rendered = automatic
        rendered.weekdayNumberStyle = .date
        rendered.highlightedDay = 2
        let savedRendered = SavedStudio(entries: [], configuration: rendered, connection: connection())
        let clean = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(savedRendered))
        expect(clean.configuration.weekdayDateLabels == nil && clean.configuration.highlightedDay == nil
               && clean.configuration.weekdayNumberStyle == .date,
               "Saving a rendered configuration removes both derived date and today labels while retaining its explicit mode")
        expect(effective(clean.configuration, connection: clean.connection).weekdayDateLabels == septemberWeek,
               "Reloading recomputes date headers from the saved calendar week rather than requiring a cached render array")
    }

    private static func checkFingerprints() {
        let later = connection(start: nextMonday)
        for style: WeekdayNumberStyle? in [nil, .date, .ordinal, .hidden] {
            var base = WallpaperConfiguration(); base.weekdayNumberStyle = style
            let current = effective(base, connection: connection())
            let next = effective(base, connection: later, now: nextMonday)
            let firstHash = WallpaperAutomation.fingerprint(entries: [], configuration: current, targetDisplayID: "fixture-display")
            let nextHash = WallpaperAutomation.fingerprint(entries: [], configuration: next, targetDisplayID: "fixture-display")
            if style == nil || style == .date {
                expect(firstHash != nextHash,
                       "A visible date header advances the fingerprint with the week (style: \(style?.rawValue ?? "automatic"))")
            } else {
                expect(firstHash == nextHash,
                       "Changing the week does not change an unchanged \(style!.rawValue) wallpaper when week title and dates are absent")
            }
        }
    }

    private static func context(style: WeekdayNumberStyle? = nil, changes: Bool = false, weekly: Bool = true) -> AutomationContext {
        var base = WallpaperConfiguration(); base.weekdayNumberStyle = style
        return .init(entries: [], configuration: base,
            settings: .init(refreshOnCalendarChange: changes, refreshWeekly: weekly, targetDisplayID: "fixture-display"),
            connection: connection(), receipt: nil, timeZone: zone)
    }
    private static func checkWeeklyAutomation() async {
        for style: WeekdayNumberStyle? in [nil, .date] {
            let harness = WeekdayHarness(context(style: style))
            await harness.engine.check(trigger: .enabled, now: wednesday)
            harness.acceptLatest()
            expect(harness.context.configuration.weekdayDateLabels == septemberWeek,
                   "Initial calendar application includes selected-week dates with today's marker disabled")
            await harness.engine.check(trigger: .clock, now: nextMonday)
            harness.acceptLatest()
            expect(harness.sink.writes == 2 && harness.context.configuration.weekdayDateLabels == nextWeek
                   && harness.context.configuration.weekdayNumberStyle == style,
                   "Weekly refresh advances visible date labels and retains \(style?.rawValue ?? "automatic") mode even with identical empty events")
            let reads = harness.provider.reads
            await harness.engine.check(trigger: .clock, now: nextMonday.addingTimeInterval(60))
            expect(harness.sink.writes == 2 && harness.provider.reads == reads,
                   "An unchanged date header is not fetched or applied again during the same week")
        }

        for style in [WeekdayNumberStyle.ordinal, .hidden] {
            let harness = WeekdayHarness(context(style: style))
            await harness.engine.check(trigger: .enabled, now: wednesday)
            harness.acceptLatest()
            await harness.engine.check(trigger: .clock, now: nextMonday)
            harness.acceptLatest()
            expect(harness.sink.writes == 1 && harness.sink.states.count == 2
                   && harness.context.connection?.weekStart == nextMonday && harness.context.receipt?.appliedAt == wednesday
                   && harness.context.configuration.weekdayNumberStyle == style && harness.context.configuration.weekdayDateLabels == nil,
                   "An unchanged \(style.rawValue) wallpaper advances only saved week metadata and preserves its application time")
        }

        let retained = WeekdayHarness(context(style: .date, changes: true, weekly: false))
        await retained.engine.check(trigger: .enabled, now: wednesday)
        retained.acceptLatest()
        let reads = retained.provider.reads
        await retained.engine.check(trigger: .clock, now: nextMonday)
        await retained.engine.check(trigger: .manual, now: nextMonday)
        expect(retained.sink.writes == 1 && retained.provider.reads == reads
               && retained.context.configuration.weekdayDateLabels == septemberWeek
               && retained.context.connection?.weekStart != nextMonday,
               "Disabling weekly refresh preserves the selected week's dates on clock ticks and manual checks")

        let metadata = WeekdayHarness(context(style: .date, changes: true))
        metadata.provider.records = [record(id: "original-source")]
        await metadata.engine.check(trigger: .enabled, now: wednesday)
        metadata.acceptLatest()
        let oldKeys = metadata.context.connection?.managedEntryKeys
        metadata.provider.records = [record(id: "replacement-source")]
        await metadata.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        metadata.acceptLatest()
        expect(metadata.sink.writes == 1 && metadata.sink.states.count == 2
               && metadata.context.connection?.managedEntryKeys != oldKeys
               && metadata.context.configuration.weekdayDateLabels == septemberWeek && metadata.context.receipt?.appliedAt == wednesday,
               "Identical-looking source identity changes persist metadata without rewriting an unchanged date-labeled wallpaper")
        expect(metadata.provider.permissionRequests == 0, "Date-label automation never requests calendar permission implicitly")
    }

    private static func checkExistingWallpaperRefresh() async {
        for trigger in [AutomationTrigger.launch, .wake] {
            var existing = context()
            existing.receipt = .init(
                wallpaperFingerprint: WallpaperAutomation.fingerprint(entries: existing.entries,
                    configuration: existing.configuration, targetDisplayID: "fixture-display"),
                calendarFingerprint: nil, appliedAt: wednesday, weekStart: existing.connection?.weekStart,
                dayKey: "2026-09-09", targetDisplayID: "fixture-display")
            let harness = WeekdayHarness(existing)
            await harness.engine.check(trigger: trigger, now: wednesday)
            harness.acceptLatest()
            expect(harness.sink.writes == 1 && harness.provider.reads == 0
                   && harness.context.configuration.weekdayDateLabels == septemberWeek,
                   "\(trigger) upgrades an existing same-week weekly-only wallpaper to date headers without reading calendars")
            await harness.engine.check(trigger: .wake, now: wednesday.addingTimeInterval(60))
            await harness.engine.check(trigger: .launch, now: wednesday.addingTimeInterval(120))
            expect(harness.sink.writes == 1 && harness.provider.reads == 0,
                   "Repeated launch/wake checks do not rewrite an already upgraded date header")
            existing.settings = AutomationSettings()
            let off = WeekdayHarness(existing)
            await off.engine.check(trigger: trigger, now: wednesday)
            expect(off.sink.writes == 0 && off.sink.states.isEmpty && off.provider.reads == 0,
                   "\(trigger) leaves an opted-out existing wallpaper unchanged even when new date headers are available")
        }
    }

    private static func record(id: String) -> CalendarEventRecord {
        .init(id: id, calendarID: "fixture-calendar", title: "Fixture class",
              startDate: date("2026-09-09T10:00:00+09:00"), endDate: date("2026-09-09T11:00:00+09:00"))
    }
    static func main() async throws {
        checkCalendarBoundaries()
        try checkDefaultsAndSelections()
        checkFingerprints()
        await checkWeeklyAutomation()
        await checkExistingWallpaperRefresh()
        print("Weekday label verification completed: \(checks) checks passed using synthetic fixtures only.")
    }
}

@MainActor private final class WeekdayProvider: CalendarProviding {
    var access: CalendarAccess = .authorized
    var permissionRequests = 0
    var reads = 0
    var records: [CalendarEventRecord] = []
    func requestAccess() async throws -> Bool { permissionRequests += 1; return false }
    func calendars() throws -> [CalendarDescriptor] {
        [.init(id: "fixture-calendar", title: "Fixture", account: "Synthetic", colorHex: 0)]
    }
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        reads += 1
        return records.filter { calendarIDs.contains($0.calendarID) }
    }
}

@MainActor private final class WeekdaySink {
    var writes = 0
    var states: [AutomationUpdate] = []
    func apply(_ update: AutomationUpdate) { writes += 1; states.append(update) }
}

@MainActor private final class WeekdayHarness {
    let provider = WeekdayProvider()
    let sink = WeekdaySink()
    let engine: WallpaperAutomation
    var context: AutomationContext
    init(_ context: AutomationContext) {
        self.context = context
        let sink = self.sink
        engine = WallpaperAutomation(provider: provider, apply: { sink.apply($0) }, onStateChange: { sink.states.append($0) })
        engine.configure(context)
    }
    func acceptLatest() {
        guard let latest = sink.states.last else { fatalError("Missing synthetic date-label update") }
        context.entries = latest.entries
        context.configuration = latest.configuration
        context.connection = latest.connection
        context.receipt = latest.receipt
        context.calendarVisibility = latest.calendarVisibility
        engine.configure(context)
    }
}
