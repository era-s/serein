import Foundation

/// Synthetic calendar provider and in-memory wallpaper sink. This executable never
/// requests Calendar permission, reads user calendars, or changes a desktop image.
@main
@MainActor
enum AutomationVerification {
    private static var checks = 0
    private static let seoul = TimeZone(identifier: "Asia/Seoul")!
    private static let wednesday = date("2026-09-09T13:00:00+09:00")
    private static let monday = date("2026-09-14T00:00:00+09:00")

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }

    private static func date(_ value: String) -> Date {
        guard let result = ISO8601DateFormatter().date(from: value) else { fatalError("Invalid fixture date: \(value)") }
        return result
    }

    private static func event(_ id: String = "class", title: String = "디자인 수업 🌿", start: String = "2026-09-09T10:00:00+09:00", end: String = "2026-09-09T11:00:00+09:00") -> CalendarEventRecord {
        .init(id: id, calendarID: "school", title: title, startDate: date(start), endDate: date(end), location: "공학관 302")
    }

    private static func context(changes: Bool = true, weekly: Bool = false, today: Bool = false, now: Date? = nil) -> AutomationContext {
        let week = CalendarWeek(containing: now ?? wednesday, timeZone: seoul)
        return .init(entries: [], configuration: WallpaperConfiguration(),
                     settings: .init(refreshOnCalendarChange: changes, refreshWeekly: weekly, showToday: today,
                                     targetDisplayID: "synthetic-display", targetDisplayName: "Synthetic display"),
                     connection: .init(calendarIDs: ["school"], calendarNames: ["Classes"], weekStart: week.start,
                                       timeZoneID: seoul.identifier, managedEntryKeys: [], includeWeekTitle: true),
                     receipt: nil, timeZone: seoul)
    }

    private static func waitForRequests(_ count: Int, provider: AutomationFakeCalendar) async {
        for _ in 0..<10_000 {
            if provider.eventRequests.count >= count { return }
            await Task.yield()
        }
        fatalError("No synthetic request \(count) arrived")
    }

    private static func checkFingerprintAndDates() throws {
        let configuration = WallpaperConfiguration()
        let first = ScheduleEntry(name: "한글 🌿\nA|B", day: 2, startMinutes: 600, endMinutes: 660, location: "302")
        let second = ScheduleEntry(name: "Typography", day: 0, startMinutes: 720, endMinutes: 780)
        let base = WallpaperAutomation.fingerprint(entries: [first, second], configuration: configuration, targetDisplayID: "display-A")
        var recreated = first; recreated.id = UUID()
        expect(base == WallpaperAutomation.fingerprint(entries: [second, recreated], configuration: configuration, targetDisplayID: "display-A"),
               "Fingerprint ignores fresh UUIDs and incoming event order")
        expect(base == WallpaperAutomation.fingerprint(entries: [first, second], configuration: configuration, targetDisplayID: "display-A"),
               "Fingerprint is deterministic with Korean, emoji, newline and separator characters")
        var renamed = first; renamed.name += " revised"
        expect(base != WallpaperAutomation.fingerprint(entries: [renamed, second], configuration: configuration, targetDisplayID: "display-A"),
               "A visible event title change changes the fingerprint")
        var moved = first; moved.startMinutes += 10
        expect(base != WallpaperAutomation.fingerprint(entries: [moved, second], configuration: configuration, targetDisplayID: "display-A"),
               "A visible event time change changes the fingerprint")
        var colored = configuration; colored.theme = .moss
        expect(base != WallpaperAutomation.fingerprint(entries: [first, second], configuration: colored, targetDisplayID: "display-A"),
               "A wallpaper design change changes the fingerprint")
        expect(base != WallpaperAutomation.fingerprint(entries: [first, second], configuration: configuration, targetDisplayID: "display-B"),
               "Changing the destination display changes the fingerprint")
        var left = first; left.name = "A|B"; left.location = "C"
        var right = first; right.name = "A"; right.location = "B|C"
        expect(WallpaperAutomation.fingerprint(entries: [left], configuration: configuration, targetDisplayID: "display-A") != WallpaperAutomation.fingerprint(entries: [right], configuration: configuration, targetDisplayID: "display-A"),
               "Text separators cannot make distinct title/location fields collide")
        var hiddenLocations = configuration; hiddenLocations.showLocations = false
        var relocated = first; relocated.location = "Another room"
        expect(WallpaperAutomation.fingerprint(entries: [first], configuration: hiddenLocations, targetDisplayID: "display-A") == WallpaperAutomation.fingerprint(entries: [relocated], configuration: hiddenLocations, targetDisplayID: "display-A"),
               "A hidden location change does not cause an identical image to be rewritten")

        var ctx = context(today: true)
        let today = WallpaperAutomation.effectiveConfiguration(ctx.configuration, settings: ctx.settings, connection: ctx.connection,
                                                               now: wednesday, timeZone: seoul)
        expect(today.highlightedDay == 2, "A Wednesday in the displayed week receives Wednesday's border")
        let outside = WallpaperAutomation.effectiveConfiguration(ctx.configuration, settings: ctx.settings, connection: ctx.connection,
                                                                 now: monday, timeZone: seoul)
        expect(outside.highlightedDay == nil, "An old calendar week never labels a day as today")
        ctx.connection = nil
        let manual = WallpaperAutomation.effectiveConfiguration(ctx.configuration, settings: ctx.settings, connection: nil,
                                                                now: wednesday, timeZone: seoul)
        expect(manual.highlightedDay == 2, "A recurring manual timetable can highlight today's weekday")
        ctx.settings.showToday = false
        var previouslyHighlighted = ctx.configuration; previouslyHighlighted.highlightedDay = 2
        let disabled = WallpaperAutomation.effectiveConfiguration(previouslyHighlighted, settings: ctx.settings, connection: nil,
                                                                  now: wednesday, timeZone: seoul)
        expect(disabled.highlightedDay == nil, "Disabling today's marker clears the explicit render input")
        let beforeMidnight = date("2026-09-09T23:59:59+09:00")
        let afterMidnight = date("2026-09-10T00:00:00+09:00")
        expect(WallpaperAutomation.dayKey(now: beforeMidnight, timeZone: seoul) != WallpaperAutomation.dayKey(now: afterMidnight, timeZone: seoul),
               "The day identity changes at local midnight")
        let newYork = TimeZone(identifier: "America/New_York")!
        let fallFirst = date("2026-11-01T01:30:00-04:00")
        let fallSecond = date("2026-11-01T01:30:00-05:00")
        expect(WallpaperAutomation.dayKey(now: fallFirst, timeZone: newYork) == WallpaperAutomation.dayKey(now: fallSecond, timeZone: newYork),
               "The repeated DST hour has the same local day identity")
        let spring = CalendarWeek(containing: date("2026-03-08T12:00:00-04:00"), timeZone: newYork)
        let fall = CalendarWeek(containing: fallFirst, timeZone: newYork)
        expect(spring.end.timeIntervalSince(spring.start) == 167 * 3600 && fall.end.timeIntervalSince(fall.start) == 169 * 3600,
               "Week boundaries remain local Mondays through short and long DST weeks")
        let legacy = Data("""
        {"theme":"ember","resolution":"macbook14","title":"Legacy","subtitle":"Fall","showLocations":true,"showWeekends":false,"showTexture":true,"startHour":9,"endHour":18}
        """.utf8)
        let decoded = try JSONDecoder().decode(WallpaperConfiguration.self, from: legacy)
        expect(decoded.highlightedDay == nil && decoded.title == "Legacy", "Existing saved wallpaper settings decode without the new optional today field")
        var settings = AutomationSettings(); settings.refreshOnCalendarChange = true; settings.showToday = true
        let restored = try JSONDecoder().decode(AutomationSettings.self, from: JSONEncoder().encode(settings))
        expect(restored == settings && !restored.refreshWeekly, "Independent automation switches survive a JSON round trip")
    }

    private static func checkCurrentWeekRefresh() async {
        let off = AutomationHarness(context(changes: false))
        for trigger: AutomationTrigger in [.enabled, .calendarChanged, .clock, .wake, .launch] {
            await off.engine.check(trigger: trigger, now: wednesday)
        }
        expect(off.provider.calendarReads == 0 && off.provider.eventRequests.isEmpty && off.sink.updates.isEmpty && off.provider.permissionRequests == 0,
               "All switches off performs no calendar reads, permission prompts or wallpaper writes")

        let harness = AutomationHarness(context())
        harness.provider.records = [event()]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        expect(harness.provider.eventRequests.count == 1 && harness.provider.eventRequests[0].ids == ["school"] && harness.provider.eventRequests[0].week.start == CalendarWeek(containing: wednesday, timeZone: seoul).start,
               "Enabling calendar refresh reads only selected calendars in the current week")
        expect(harness.sink.updates.count == 1 && harness.sink.updates[0].entries.count == 1 && harness.sink.updates[0].entries[0].name == "디자인 수업 🌿",
               "Enabling refresh produces the current week's initial wallpaper")
        expect(harness.engine.lastAppliedAt == wednesday && !harness.engine.isChecking, "Successful application records its date and finishes checking")
        harness.acceptLatest()
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        expect(harness.sink.updates.count == 1, "Repeated notifications with the same current-week content do not rewrite wallpaper")
        harness.provider.records.append(event("next-week", title: "Future class", start: "2026-09-16T10:00:00+09:00", end: "2026-09-16T11:00:00+09:00"))
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(120))
        expect(harness.sink.updates.count == 1, "An event added outside the current week does not rewrite wallpaper")
        harness.provider.records[0].title = "Changed current class"
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(180))
        expect(harness.sink.updates.count == 2 && harness.sink.updates.last?.entries.first?.name == "Changed current class",
               "Changing a current-week event automatically updates wallpaper")
        harness.acceptLatest()
        harness.provider.records.append(event("additional", title: "Added class", start: "2026-09-10T12:00:00+09:00", end: "2026-09-10T13:00:00+09:00"))
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(240))
        expect(harness.sink.updates.count == 3 && harness.sink.updates.last?.entries.count == 2, "Adding a current-week event automatically updates wallpaper")
        harness.acceptLatest()
        let manual = ScheduleEntry(name: "Manual class", day: 0, startMinutes: 600, endMinutes: 660)
        harness.context.entries.append(manual)
        harness.engine.configure(harness.context)
        harness.provider.records = []
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(300))
        expect(harness.sink.updates.count == 4 && harness.sink.updates.last?.entries == [manual],
               "Deleting all managed calendar events removes them while preserving manual classes")
        expect(harness.sink.updates.last?.connection?.managedEntryKeys.isEmpty == true,
               "An empty current week clears the managed calendar identity set")
        expect(harness.provider.permissionRequests == 0, "Automatic checks never request permission implicitly")
    }

    private static func checkSavedStudio() throws {
        let legacy = Data("""
        {"version":1,"entries":[{"id":"D080A4EE-8287-4940-A9AD-A4A12655338A","name":"Legacy class","day":0,"startMinutes":600,"endMinutes":660,"location":"A101"}],"configuration":{"theme":"ember","resolution":"macbook14","title":"Legacy","subtitle":"Fall","showLocations":true,"showWeekends":false,"showTexture":true,"startHour":9,"endHour":18}}
        """.utf8)
        let old = try JSONDecoder().decode(SavedStudio.self, from: legacy)
        expect(old.version == 1 && old.isValid && old.entries.first?.name == "Legacy class" && old.configuration.title == "Legacy",
               "The actual saved-studio model still loads and validates a version 1 project")
        expect(old.automation == nil && old.connection == nil && old.receipt == nil && old.configuration.highlightedDay == nil,
               "A version 1 project has no implicit automation opt-in, calendar connection or application receipt")
        var migratedLegacy = old
        expect(migratedLegacy.migrateWallpaperScope() && migratedLegacy.version == 3 && migratedLegacy.isValid,
               "Version 1 projects migrate to the current saved-studio version")
        expect(migratedLegacy.automation?.targetDisplayID == WallpaperDisplay.allSpacesID
               && migratedLegacy.automation?.hasAutomation == false && migratedLegacy.entries == old.entries,
               "Legacy projects default to every Space and display without enabling automation or changing entries")
        expect(AutomationSettings().targetDisplayID == WallpaperDisplay.allSpacesID,
               "New projects use all Spaces and displays as the default application scope")

        var ctx = context(changes: true, weekly: true, today: true)
        let week = CalendarWeek(containing: wednesday, timeZone: seoul)
        ctx.entries = CalendarEventConverter.convert([event()], week: week).entries
        ctx.connection?.managedEntryKeys = Set(ctx.entries.compactMap(\.calendarSourceKey))
        ctx.configuration.highlightedDay = 2
        let receipt = AutomationReceipt(wallpaperFingerprint: "synthetic-wallpaper-hash", calendarFingerprint: "synthetic-calendar-hash",
                                        appliedAt: wednesday, weekStart: week.start,
                                        dayKey: WallpaperAutomation.dayKey(now: wednesday, timeZone: seoul), targetDisplayID: "synthetic-display")
        let saved = SavedStudio(entries: ctx.entries, configuration: ctx.configuration,
                                automation: ctx.settings, connection: ctx.connection, receipt: receipt)
        let restored = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(saved))
        var preferences = ctx.configuration
        preferences.highlightedDay = nil
        preferences.weekdayDateLabels = nil
        expect(restored.version == 3 && restored.isValid && restored.entries == ctx.entries && restored.configuration == preferences,
               "A version 3 saved studio preserves entries and render preferences without stale derived labels")
        expect(restored.automation == ctx.settings && restored.connection == ctx.connection && restored.receipt == receipt,
               "A version 3 saved studio preserves every automation switch, selected source, managed identity and receipt")
        var migrated = saved
        migrated.version = 2
        expect(migrated.isValid && migrated.migrateWallpaperScope() && migrated.version == 3,
               "A valid version 2 saved studio migrates to version 3")
        expect(migrated.automation?.targetDisplayID == WallpaperDisplay.allSpacesID
               && migrated.automation?.targetDisplayName == WallpaperDisplay.allSpaces.name
               && migrated.automation?.refreshOnCalendarChange == ctx.settings.refreshOnCalendarChange
               && migrated.automation?.refreshWeekly == ctx.settings.refreshWeekly
               && migrated.automation?.showToday == ctx.settings.showToday
               && migrated.connection == saved.connection && migrated.receipt == receipt,
               "Scope migration changes only the target and preserves opt-ins, calendar ownership and the last actual receipt")
        var unchanged = saved
        expect(!unchanged.migrateWallpaperScope() && unchanged.automation?.targetDisplayID == "synthetic-display",
               "Explicit individual-display selections saved in version 3 are not migrated again")
        for version in [0, 4, 99] {
            var unsupported = saved; unsupported.version = version
            let decoded = try JSONDecoder().decode(SavedStudio.self, from: JSONEncoder().encode(unsupported))
            expect(!decoded.isValid, "Saved-studio validation rejects unsupported version \(version)")
        }
        var invalidSource = saved; invalidSource.connection?.calendarIDs = []
        expect(!invalidSource.isValid, "A saved automation connection cannot have an empty calendar selection")
        invalidSource = saved; invalidSource.connection?.timeZoneID = "Invalid/SyntheticZone"
        expect(!invalidSource.isValid, "A saved automation connection cannot have an unknown time zone")
    }

    private static func checkMigratedScopeRefresh() async {
        var ctx = context(changes: false, weekly: true)
        ctx.entries = CalendarEventConverter.convert([event()], week: CalendarWeek(containing: wednesday, timeZone: seoul)).entries
        ctx.receipt = AutomationReceipt(
            wallpaperFingerprint: WallpaperAutomation.fingerprint(entries: ctx.entries, configuration: ctx.configuration,
                targetDisplayID: "synthetic-display"), calendarFingerprint: nil, appliedAt: wednesday,
            weekStart: ctx.connection?.weekStart, dayKey: WallpaperAutomation.dayKey(now: wednesday, timeZone: seoul),
            targetDisplayID: "synthetic-display")
        var legacy = SavedStudio(version: 2, entries: ctx.entries, configuration: ctx.configuration,
            automation: ctx.settings, connection: ctx.connection, receipt: ctx.receipt)
        legacy.migrateWallpaperScope()
        ctx.settings = legacy.automation!
        let harness = AutomationHarness(ctx)
        await harness.engine.check(trigger: .settingsChanged, now: wednesday)
        expect(harness.sink.updates.count == 1
               && harness.sink.updates.last?.receipt.targetDisplayID == WallpaperDisplay.allSpacesID
               && harness.sink.updates.last?.entries == ctx.entries && harness.provider.eventRequests.isEmpty,
               "A migrated weekly-only project reapplies its existing week to every Space without waiting for Monday")
    }

    private static func checkWeeklySwitch() async {
        let weekly = AutomationHarness(context(changes: false, weekly: true))
        weekly.provider.records = [event()]
        await weekly.engine.check(trigger: .enabled, now: wednesday)
        expect(weekly.sink.updates.count == 1, "Weekly refresh alone establishes its initial current-week wallpaper")
        weekly.acceptLatest()
        let reads = weekly.provider.eventRequests.count
        weekly.provider.records[0].title = "Changed but weekly only"
        await weekly.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        await weekly.engine.check(trigger: .clock, now: wednesday.addingTimeInterval(120))
        expect(weekly.sink.updates.count == 1 && weekly.provider.eventRequests.count == reads,
               "Weekly-only mode ignores same-week calendar notifications and clock checks")
        weekly.provider.records = []
        await weekly.engine.check(trigger: .clock, now: monday)
        expect(weekly.sink.updates.count == 2 && weekly.sink.updates.last?.entries.isEmpty == true && weekly.sink.updates.last?.connection?.weekStart == monday,
               "Monday's weekly transition applies the new week even when it contains no events")
        weekly.acceptLatest()
        await weekly.engine.check(trigger: .wake, now: monday.addingTimeInterval(60))
        expect(weekly.sink.updates.count == 2, "Waking again in the already-applied week does not duplicate a weekly update")

        let changesOnly = AutomationHarness(context(changes: true, weekly: false))
        changesOnly.provider.records = [event()]
        await changesOnly.engine.check(trigger: .enabled, now: wednesday)
        changesOnly.acceptLatest()
        let beforeReads = changesOnly.provider.eventRequests.count
        changesOnly.provider.records = [event("next", start: "2026-09-14T10:00:00+09:00", end: "2026-09-14T11:00:00+09:00")]
        await changesOnly.engine.check(trigger: .calendarChanged, now: monday)
        expect(changesOnly.sink.updates.count == 1 && changesOnly.provider.eventRequests.count == beforeReads,
               "With weekly refresh disabled, a new week does not advance the displayed calendar automatically")

        for trigger: AutomationTrigger in [.wake, .launch] {
            let catchup = AutomationHarness(context(changes: false, weekly: true))
            catchup.provider.records = [event()]
            await catchup.engine.check(trigger: .enabled, now: wednesday)
            catchup.acceptLatest()
            let later = date("2026-09-28T09:00:00+09:00")
            catchup.provider.records = []
            await catchup.engine.check(trigger: trigger, now: later)
            expect(catchup.sink.updates.count == 2 && catchup.sink.updates.last?.connection?.weekStart == date("2026-09-28T00:00:00+09:00"),
                   "\(trigger) catches up directly to the current week after multiple missed Mondays")
        }
    }

    private static func checkMetadataAndLaunchRecovery() async {
        let recovered = AutomationHarness(context(changes: false, weekly: true))
        recovered.provider.records = [event()]
        await recovered.engine.check(trigger: .launch, now: wednesday)
        expect(recovered.sink.updates.count == 1 && recovered.engine.lastAppliedAt == wednesday,
               "Persisted calendar opt-in retries initialization on launch if its first application never succeeded")

        let harness = AutomationHarness(context())
        harness.provider.records = [event("original-id")]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let originalKeys = harness.context.connection?.managedEntryKeys
        harness.provider.records = [event("replacement-id")]
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        expect(harness.sink.updates.count == 1 && harness.sink.stateChanges.count == 1,
               "Identical-looking replacement events update managed identities without rewriting wallpaper")
        expect(harness.sink.stateChanges.last?.connection?.managedEntryKeys != originalKeys && harness.sink.stateChanges.last?.receipt.appliedAt == wednesday && harness.engine.lastAppliedAt == wednesday,
               "Metadata-only updates preserve the timestamp of the last successful wallpaper application")
        harness.acceptStateChange()
        harness.provider.records = []
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(120))
        expect(harness.sink.updates.count == 2 && harness.sink.updates.last?.entries.isEmpty == true,
               "Deleting an identical-looking replacement removes its newly persisted managed identity")

        var hiddenContext = context(); hiddenContext.configuration.showLocations = false
        let hidden = AutomationHarness(hiddenContext)
        hidden.provider.records = [event()]
        await hidden.engine.check(trigger: .enabled, now: wednesday)
        hidden.acceptLatest()
        let calendarFingerprint = hidden.context.receipt?.calendarFingerprint
        hidden.provider.records[0].location = "Changed hidden room"
        await hidden.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        expect(hidden.sink.updates.count == 1 && hidden.sink.stateChanges.last?.entries.first?.location == "Changed hidden room" && hidden.sink.stateChanges.last?.receipt.calendarFingerprint != calendarFingerprint,
               "A hidden location change persists its new calendar content without rewriting wallpaper")

        var identicalContext = context(changes: false, weekly: true)
        identicalContext.connection?.includeWeekTitle = false
        identicalContext.configuration.weekdayNumberStyle = .ordinal
        let identical = AutomationHarness(identicalContext)
        await identical.engine.check(trigger: .enabled, now: wednesday)
        identical.acceptLatest()
        await identical.engine.check(trigger: .clock, now: monday)
        expect(identical.sink.updates.count == 1 && identical.sink.stateChanges.count == 1 && identical.sink.stateChanges.last?.connection?.weekStart == monday && identical.sink.stateChanges.last?.receipt.weekStart == monday,
               "An identical empty week with hidden week dates advances saved week metadata without a redundant image write")
        expect(identical.engine.lastAppliedAt == wednesday && identical.sink.stateChanges.last?.receipt.appliedAt == wednesday,
               "An identical new week's metadata refresh preserves the last actual wallpaper application time")
        identical.acceptStateChange()
        let reads = identical.provider.eventRequests.count
        await identical.engine.check(trigger: .clock, now: monday.addingTimeInterval(60))
        expect(identical.provider.eventRequests.count == reads, "Persisting an identical new week prevents it from being fetched on every timer tick")

        let newYork = TimeZone(identifier: "America/New_York")!
        let springSunday = date("2026-03-08T12:00:00-04:00")
        let springMonday = date("2026-03-09T00:00:00-04:00")
        var dstContext = context(changes: false, weekly: true, today: true)
        dstContext.timeZone = newYork
        dstContext.connection?.timeZoneID = newYork.identifier
        dstContext.connection?.weekStart = CalendarWeek(containing: springSunday, timeZone: newYork).start
        let dst = AutomationHarness(dstContext)
        await dst.engine.check(trigger: .enabled, now: springSunday)
        dst.acceptLatest()
        await dst.engine.check(trigger: .clock, now: springMonday)
        expect(dst.sink.updates.count == 2 && dst.sink.updates.last?.connection?.weekStart == springMonday && dst.sink.updates.last?.configuration.highlightedDay == 0,
               "The automation advances week and today marker at local Monday after the spring DST change")
    }

    private static func checkTodaySwitch() async {
        var manualContext = context(changes: false, today: true)
        manualContext.connection = nil
        manualContext.entries = [ScheduleEntry(name: "Manual", day: 2, startMinutes: 600, endMinutes: 660)]
        let manual = AutomationHarness(manualContext)
        await manual.engine.check(trigger: .launch, now: wednesday)
        await manual.engine.check(trigger: .clock, now: wednesday.addingTimeInterval(60))
        await manual.engine.check(trigger: .enabled, now: wednesday.addingTimeInterval(120))
        expect(manual.sink.updates.isEmpty && manual.provider.eventRequests.isEmpty,
               "Today's marker alone does not change an unarmed manual wallpaper on launch, enable or clock ticks")
        manual.context.configuration.highlightedDay = 2
        manual.context.receipt = .init(
            wallpaperFingerprint: WallpaperAutomation.fingerprint(entries: manual.context.entries, configuration: manual.context.configuration, targetDisplayID: "synthetic-display"),
            calendarFingerprint: nil, appliedAt: wednesday, weekStart: nil,
            dayKey: WallpaperAutomation.dayKey(now: wednesday, timeZone: seoul), targetDisplayID: "synthetic-display")
        manual.engine.configure(manual.context)
        await manual.engine.check(trigger: .clock, now: date("2026-09-10T00:00:00+09:00"))
        expect(manual.sink.updates.count == 1 && manual.sink.updates.last?.configuration.highlightedDay == 3 && manual.provider.eventRequests.isEmpty,
               "After a manual wallpaper is applied, today's marker advances without any calendar connection")

        let harness = AutomationHarness(context(changes: false, weekly: true, today: true))
        harness.provider.records = [event()]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        expect(harness.sink.updates.last?.configuration.highlightedDay == 2, "An applied calendar wallpaper includes today's selected border")
        harness.context.settings.refreshWeekly = false
        harness.engine.configure(harness.context)
        let reads = harness.provider.eventRequests.count
        await harness.engine.check(trigger: .clock, now: date("2026-09-10T00:00:00+09:00"))
        expect(harness.sink.updates.count == 2 && harness.sink.updates.last?.configuration.highlightedDay == 3 && harness.provider.eventRequests.count == reads,
               "With calendar switches off, midnight moves today's border without reading calendars")
        harness.acceptLatest()
        await harness.engine.check(trigger: .clock, now: date("2026-09-10T12:00:00+09:00"))
        expect(harness.sink.updates.count == 2, "Today's border rewrites no more than once for an unchanged local day")
        await harness.engine.check(trigger: .wake, now: monday)
        expect(harness.sink.updates.count == 3 && harness.sink.updates.last?.configuration.highlightedDay == nil && harness.sink.updates.last?.connection?.weekStart != monday,
               "Today's border clears when a retained calendar week is past, without enabling weekly refresh")
        harness.acceptLatest()
        harness.context.settings.showToday = false
        harness.engine.configure(harness.context)
        let count = harness.sink.updates.count
        await harness.engine.check(trigger: .clock, now: monday.addingTimeInterval(86_400))
        expect(harness.sink.updates.count == count, "Disabling all switches stops later automatic applications")
    }

    private static func checkFailuresPreserveWallpaper() async {
        let harness = AutomationHarness(context())
        harness.provider.records = [event()]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let lastApplied = harness.engine.lastAppliedAt
        harness.provider.records[0].title = "Cannot apply yet"
        harness.sink.failure = SyntheticFailure.unavailableDisplay
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60))
        expect(harness.sink.updates.count == 1 && harness.engine.lastAppliedAt == lastApplied && !harness.engine.isChecking,
               "A missing destination display preserves the prior receipt and ends checking")
        expect(!harness.engine.status.isEmpty, "Application failure exposes a status message")
        harness.sink.failure = nil
        await harness.engine.check(trigger: .wake, now: wednesday.addingTimeInterval(120))
        expect(harness.sink.updates.count == 2, "A failed application remains eligible for retry when its display returns")
        harness.acceptLatest()
        harness.provider.failure = SyntheticFailure.providerRead
        harness.provider.records = []
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(180))
        expect(harness.sink.updates.count == 2 && harness.engine.lastAppliedAt == wednesday.addingTimeInterval(120),
               "An event read failure preserves the displayed schedule and prior receipt")
        harness.provider.failure = nil
        harness.provider.access = .denied
        let requests = harness.provider.eventRequests.count
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(240))
        expect(harness.sink.updates.count == 2 && harness.provider.eventRequests.count == requests && harness.provider.permissionRequests == 0,
               "Revoked access neither blanks wallpaper nor requests permission automatically")
        harness.provider.access = .authorized
        harness.provider.availableCalendars = []
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(300))
        expect(harness.sink.updates.count == 2 && harness.provider.eventRequests.count == requests,
               "A deleted selected calendar is an error, not an empty-week replacement")
        harness.context.connection?.calendarIDs = []
        harness.engine.configure(harness.context)
        await harness.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(360))
        expect(harness.sink.updates.count == 2 && harness.provider.eventRequests.count == requests,
               "An empty calendar selection never expands to all calendars or blanks wallpaper")
        expect(harness.sink.stateChanges.isEmpty,
               "Calendar permission, source and fetch errors never persist replacement entries or receipt metadata")

        var missingTarget = context(); missingTarget.settings.targetDisplayID = nil
        let noTarget = AutomationHarness(missingTarget)
        await noTarget.engine.check(trigger: .enabled, now: wednesday)
        expect(noTarget.sink.updates.isEmpty && noTarget.engine.lastAppliedAt == nil && noTarget.provider.eventRequests.isEmpty && noTarget.provider.calendarReads == 0,
               "No selected display prevents both calendar reads and background wallpaper application")
        var disconnected = context(); disconnected.connection = nil
        let noConnection = AutomationHarness(disconnected)
        await noConnection.engine.check(trigger: .enabled, now: wednesday)
        expect(noConnection.sink.updates.isEmpty && noConnection.provider.eventRequests.isEmpty && noConnection.provider.permissionRequests == 0,
               "Calendar automation without a connection waits for explicit setup without reading calendars")
    }

    private static func checkManualPermissionRecovery() async {
        let harness = AutomationHarness(context(changes: false, weekly: true))
        harness.provider.records = [event(title: "Before reconnect")]
        await harness.engine.check(trigger: .enabled, now: wednesday)
        harness.acceptLatest()
        let originalReceipt = harness.context.receipt
        let originalEntries = harness.context.entries
        let initialReads = harness.provider.eventRequests.count

        harness.provider.access = .denied
        await harness.engine.check(trigger: .enabled, now: wednesday.addingTimeInterval(60))
        expect(harness.engine.needsCalendarReconnect && harness.sink.updates.count == 1
               && harness.sink.stateChanges.isEmpty && harness.context.receipt == originalReceipt
               && harness.context.entries == originalEntries && harness.engine.lastAppliedAt == originalReceipt?.appliedAt,
               "A denied re-enable preserves the existing schedule and receipt and exposes a reconnect action")
        for trigger: AutomationTrigger in [.clock, .calendarChanged, .wake] {
            await harness.engine.check(trigger: trigger, now: wednesday.addingTimeInterval(120))
        }
        expect(harness.provider.permissionRequests == 0 && harness.provider.eventRequests.count == initialReads,
               "Background checks after a permission failure neither prompt nor turn weekly-only mode into continuous reads")

        harness.provider.access = .authorized
        harness.provider.records = [event(title: "After reconnect")]
        await harness.engine.check(trigger: .manual, now: wednesday.addingTimeInterval(180))
        expect(harness.provider.eventRequests.count == initialReads + 1 && harness.sink.updates.count == 2
               && harness.sink.updates.last?.entries.first?.name == "After reconnect" && !harness.engine.needsCalendarReconnect,
               "Explicit rechecking after permission recovery refreshes a weekly-only wallpaper within the same week")
        expect(harness.provider.permissionRequests == 0,
               "The automation engine never requests permission even for an explicit manual recheck")
        harness.acceptLatest()
        harness.provider.records = [event(title: "Wait for the next Monday")]
        await harness.engine.check(trigger: .clock, now: wednesday.addingTimeInterval(240))
        expect(harness.provider.eventRequests.count == initialReads + 1 && harness.sink.updates.count == 2,
               "Recovering permission does not change the weekly-only background polling policy")

        for hasReceipt in [false, true] {
            var past = context(changes: true, weekly: false)
            past.entries = originalEntries
            past.receipt = hasReceipt ? originalReceipt : nil
            let retained = AutomationHarness(past)
            retained.provider.records = []
            await retained.engine.check(trigger: .manual, now: monday)
            expect(retained.provider.eventRequests.isEmpty && retained.sink.updates.isEmpty
                   && retained.sink.stateChanges.isEmpty,
                   "Manual rechecking preserves an older displayed week when weekly refresh is off (receipt: \(hasReceipt))")
        }

        let queued = AutomationHarness(harness.context)
        queued.provider.suspendEvents = true
        let manual = Task { await queued.engine.check(trigger: .manual, now: wednesday.addingTimeInterval(300)) }
        await waitForRequests(1, provider: queued.provider)
        let notification = Task { await queued.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(301)) }
        await Task.yield()
        queued.provider.completeRequest(0, records: [event(title: "Superseded manual read")])
        await waitForRequests(2, provider: queued.provider)
        queued.provider.completeRequest(1, records: [event(title: "Latest manual read")])
        await manual.value
        await notification.value
        expect(queued.sink.updates.count == 1 && queued.sink.updates.last?.entries.first?.name == "Latest manual read",
               "A same-week calendar notification cannot discard an in-flight explicit weekly-only recheck")
    }

    private static func checkStaleRequests() async {
        let disabled = AutomationHarness(context())
        disabled.provider.suspendEvents = true
        let original = Task { await disabled.engine.check(trigger: .enabled, now: wednesday) }
        await waitForRequests(1, provider: disabled.provider)
        expect(disabled.engine.isChecking, "An in-flight automatic read exposes its checking state")
        disabled.context.settings.refreshOnCalendarChange = false
        disabled.engine.configure(disabled.context)
        disabled.provider.completeRequest(0, records: [event()])
        await original.value
        expect(disabled.sink.updates.isEmpty && !disabled.engine.isChecking,
               "Turning automation off while reading rejects the late response")

        let newer = AutomationHarness(context())
        newer.provider.suspendEvents = true
        let first = Task { await newer.engine.check(trigger: .enabled, now: wednesday) }
        await waitForRequests(1, provider: newer.provider)
        var changed = newer.context; changed.configuration.theme = .moss
        newer.engine.configure(changed)
        let second = Task { await newer.engine.check(trigger: .settingsChanged, now: wednesday.addingTimeInterval(60)) }
        await Task.yield()
        newer.provider.completeRequest(0, records: [event(title: "Old response")])
        await waitForRequests(2, provider: newer.provider)
        expect(newer.sink.updates.isEmpty && newer.engine.isChecking,
               "A superseded result cannot apply while the newer request is being read")
        newer.provider.completeRequest(1, records: [event(title: "New response")])
        await second.value
        await first.value
        expect(newer.sink.updates.count == 1 && newer.sink.updates.last?.entries.first?.name == "New response" && newer.sink.updates.last?.configuration.theme == .moss,
               "A queued newer request is the only one allowed to apply after settings change")
        expect(!newer.engine.isChecking, "Completion of stale reads does not leave checking stuck")

        let revoked = AutomationHarness(context())
        revoked.provider.suspendEvents = true
        let pending = Task { await revoked.engine.check(trigger: .enabled, now: wednesday) }
        await waitForRequests(1, provider: revoked.provider)
        revoked.provider.access = .denied
        revoked.provider.completeRequest(0, records: [event()])
        await pending.value
        expect(revoked.sink.updates.isEmpty && revoked.engine.lastAppliedAt == nil,
               "Permission revoked during an asynchronous read prevents its response from being applied")

        let deleted = AutomationHarness(context())
        deleted.provider.suspendEvents = true
        let deleting = Task { await deleted.engine.check(trigger: .enabled, now: wednesday) }
        await waitForRequests(1, provider: deleted.provider)
        deleted.provider.availableCalendars = []
        deleted.provider.completeRequest(0, records: [event()])
        await deleting.value
        expect(deleted.sink.updates.isEmpty && deleted.engine.lastAppliedAt == nil,
               "Deleting the selected calendar during a read rejects the stale response")

        let notified = AutomationHarness(context())
        notified.provider.suspendEvents = true
        let firstNotification = Task { await notified.engine.check(trigger: .enabled, now: wednesday) }
        await waitForRequests(1, provider: notified.provider)
        let latestNotification = Task { await notified.engine.check(trigger: .calendarChanged, now: wednesday.addingTimeInterval(60)) }
        await Task.yield()
        notified.provider.completeRequest(0, records: [event(title: "Before later notification")])
        await waitForRequests(2, provider: notified.provider)
        expect(notified.sink.updates.isEmpty, "A calendar change arriving during a query invalidates that query's earlier snapshot")
        notified.provider.completeRequest(1, records: [event(title: "After later notification")])
        await latestNotification.value
        await firstNotification.value
        expect(notified.sink.updates.count == 1 && notified.sink.updates.last?.entries.first?.name == "After later notification",
               "A notification received during a query is retained and rerun with the latest calendar content")
    }

    static func main() async throws {
        try checkFingerprintAndDates()
        try checkSavedStudio()
        await checkMigratedScopeRefresh()
        await checkCurrentWeekRefresh()
        await checkWeeklySwitch()
        await checkMetadataAndLaunchRecovery()
        await checkTodaySwitch()
        await checkFailuresPreserveWallpaper()
        await checkManualPermissionRecovery()
        await checkStaleRequests()
        print("Automation verification completed: \(checks) checks passed using synthetic fixtures only.")
    }
}

private enum SyntheticFailure: LocalizedError {
    case unavailableDisplay, providerRead
    var errorDescription: String? {
        switch self {
        case .unavailableDisplay: "Synthetic display disconnected"
        case .providerRead: "Synthetic calendar read failed"
        }
    }
}

@MainActor
private final class AutomationSink {
    var updates: [AutomationUpdate] = []
    var stateChanges: [AutomationUpdate] = []
    var failure: SyntheticFailure?
    func apply(_ update: AutomationUpdate) throws {
        if let failure { throw failure }
        updates.append(update)
    }
}

@MainActor
private final class AutomationHarness {
    let provider = AutomationFakeCalendar()
    let sink = AutomationSink()
    var context: AutomationContext
    let engine: WallpaperAutomation
    init(_ context: AutomationContext) {
        self.context = context
        let sink = self.sink
        engine = WallpaperAutomation(provider: provider, apply: { try sink.apply($0) }, onStateChange: { sink.stateChanges.append($0) })
        engine.configure(context)
    }
    func acceptLatest() {
        guard let latest = sink.updates.last else { fatalError("No synthetic update to accept") }
        accept(latest)
    }
    func acceptStateChange() {
        guard let latest = sink.stateChanges.last else { fatalError("No synthetic metadata update to accept") }
        accept(latest)
    }
    private func accept(_ latest: AutomationUpdate) {
        context.entries = latest.entries
        context.configuration = latest.configuration
        context.connection = latest.connection
        context.receipt = latest.receipt
        context.calendarVisibility = latest.calendarVisibility
        engine.configure(context)
    }
}

@MainActor
private final class AutomationFakeCalendar: CalendarProviding {
    struct Request { var ids: Set<String>; var week: CalendarWeek }
    var access: CalendarAccess = .authorized
    var permissionRequests = 0
    var calendarReads = 0
    var eventRequests: [Request] = []
    var records: [CalendarEventRecord] = []
    var suspendEvents = false
    var failure: SyntheticFailure?
    var availableCalendars: [CalendarDescriptor] = [
        .init(id: "school", title: "Classes", account: "Synthetic Google", colorHex: 0xE86E36)
    ]
    private var pending: [Int: CheckedContinuation<[CalendarEventRecord], Error>] = [:]

    func requestAccess() async throws -> Bool {
        permissionRequests += 1
        return false
    }
    func calendars() throws -> [CalendarDescriptor] {
        calendarReads += 1
        return availableCalendars
    }
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        let index = eventRequests.count
        eventRequests.append(.init(ids: calendarIDs, week: week))
        if suspendEvents { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        if let failure { throw failure }
        // Keep out-of-week records to verify that the engine/converter enforces
        // the current-week boundary even with an overbroad provider response.
        return records.filter { calendarIDs.contains($0.calendarID) }
    }
    func completeRequest(_ index: Int, records: [CalendarEventRecord]) {
        guard let continuation = pending.removeValue(forKey: index) else { fatalError("No pending request \(index)") }
        continuation.resume(returning: records)
    }
}
