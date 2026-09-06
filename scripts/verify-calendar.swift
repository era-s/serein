import Foundation

/// Synthetic executable checks; never requests permission or reads personal calendars.
/// Works with Command Line Tools installations that do not include XCTest.
@main
@MainActor
enum CalendarVerification {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }

    private static func date(_ text: String) -> Date {
        guard let value = ISO8601DateFormatter().date(from: text) else {
            fatalError("Invalid fixture date: \(text)")
        }
        return value
    }

    private static func event(_ id: String, _ start: String, _ end: String, title: String = "Design studio", calendarID: String = "school") -> CalendarEventRecord {
        .init(id: id, calendarID: calendarID, title: title, startDate: date(start), endDate: date(end), location: "Room 302")
    }

    private static func checkWeeksAndConversion() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let week = CalendarWeek(containing: date("2026-09-09T13:00:00+09:00"), timeZone: seoul)
        expect(week.start == date("2026-09-07T00:00:00+09:00"), "A week starts at Monday midnight in the chosen time zone")
        expect(week.end == date("2026-09-14T00:00:00+09:00"), "The next Monday is the exclusive week boundary")
        expect(CalendarWeek(containing: week.start, timeZone: seoul) == week, "An exact Monday belongs to its new week")
        expect(CalendarWeek(containing: week.end.addingTimeInterval(-1), timeZone: seoul) == week, "Sunday's final second belongs to the same week")

        let newYork = TimeZone(identifier: "America/New_York")!
        let spring = CalendarWeek(containing: date("2026-03-08T12:00:00-04:00"), timeZone: newYork)
        let fall = CalendarWeek(containing: date("2026-11-01T12:00:00-05:00"), timeZone: newYork)
        expect(spring.end.timeIntervalSince(spring.start) == 167 * 3600, "A spring DST week includes its real 23-hour day")
        expect(fall.end.timeIntervalSince(fall.start) == 169 * 3600, "An autumn DST week includes its real 25-hour day")
        let springResult = CalendarEventConverter.convert([
            event("spring", "2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00")
        ], week: spring)
        expect(springResult.entries.count == 1 && springResult.entries[0].day == 6 && springResult.entries[0].startMinutes == 90 && springResult.entries[0].endMinutes == 210,
               "A spring transition uses Sunday wall-clock labels rather than elapsed minutes")
        let fallResult = CalendarEventConverter.convert([
            event("fall", "2026-11-01T00:30:00-04:00", "2026-11-01T02:30:00-05:00")
        ], week: fall)
        expect(fallResult.entries.count == 1 && fallResult.entries[0].day == 6 && fallResult.entries[0].startMinutes == 30 && fallResult.entries[0].endMinutes == 150,
               "An autumn transition uses Sunday wall-clock labels rather than elapsed minutes")
        let reversedWallTime = CalendarEventConverter.convert([
            event("fall-repeated-hour", "2026-11-01T01:45:00-04:00", "2026-11-01T01:15:00-05:00")
        ], week: fall)
        expect(reversedWallTime.entries.isEmpty && reversedWallTime.excludedCount == 1 && !reversedWallTime.warnings.isEmpty,
               "A real event whose clock labels reverse across DST is excluded with an explanation")

        let normal = event("normal", "2026-09-07T01:15:00Z", "2026-09-07T02:45:00Z")
        let normalResult = CalendarEventConverter.convert([normal], week: week)
        expect(normalResult.entries.count == 1, "A timed calendar event becomes one schedule entry")
        let entry = normalResult.entries[0]
        expect(entry.day == 0 && entry.startMinutes == 615 && entry.endMinutes == 705, "UTC event dates convert to the selected local weekday and minutes")
        expect(entry.name == "Design studio" && entry.location == "Room 302", "Event title and location are preserved")
        expect(entry.validationError == nil && entry.calendarSourceKey != nil, "Imported entries are valid and carry a calendar source key")

        let overnight = CalendarEventConverter.convert([
            event("overnight", "2026-09-11T23:30:00+09:00", "2026-09-12T01:15:00+09:00")
        ], week: week).entries.sorted { $0.day < $1.day }
        expect(overnight.count == 2, "An overnight event splits into two daily entries")
        expect(overnight[0].day == 4 && overnight[0].startMinutes == 1410 && overnight[0].endMinutes == 1440,
               "The first overnight segment ends at 24:00")
        expect(overnight[1].day == 5 && overnight[1].startMinutes == 0 && overnight[1].endMinutes == 75,
               "The second overnight segment starts at 00:00")
        expect(overnight[0].calendarSourceKey != overnight[1].calendarSourceKey, "Daily segments retain distinct source identities")
        let midnight = CalendarEventConverter.convert([
            event("midnight", "2026-09-07T23:00:00+09:00", "2026-09-08T00:00:00+09:00")
        ], week: week).entries
        expect(midnight.count == 1 && midnight[0].endMinutes == 1440, "An exact-midnight ending creates no phantom next-day entry")

        let clipped = CalendarEventConverter.convert([
            event("left", "2026-09-06T23:00:00+09:00", "2026-09-07T01:00:00+09:00"),
            event("right", "2026-09-13T23:00:00+09:00", "2026-09-14T01:00:00+09:00"),
            event("before", "2026-09-06T23:00:00+09:00", "2026-09-07T00:00:00+09:00"),
            event("after", "2026-09-14T00:00:00+09:00", "2026-09-14T01:00:00+09:00")
        ], week: week).entries.sorted { $0.day < $1.day }
        expect(clipped.count == 2, "Events merely touching a week boundary are excluded")
        expect(clipped[0].day == 0 && clipped[0].startMinutes == 0 && clipped[0].endMinutes == 60,
               "An event crossing into the week is clipped to Monday midnight")
        expect(clipped[1].day == 6 && clipped[1].startMinutes == 1380 && clipped[1].endMinutes == 1440,
               "An event crossing out of the week is clipped to Sunday 24:00")

        var allDay = normal; allDay.id = "all-day"; allDay.isAllDay = true
        var cancelled = normal; cancelled.id = "cancelled"; cancelled.isCancelled = true
        var declined = normal; declined.id = "declined"; declined.isDeclined = true
        var zero = normal; zero.id = "zero"; zero.endDate = zero.startDate
        var backwards = normal; backwards.id = "backwards"; backwards.endDate = backwards.startDate.addingTimeInterval(-60)
        let exclusions = CalendarEventConverter.convert([normal, allDay, cancelled, declined, zero, backwards], week: week)
        expect(exclusions.entries.count == 1 && exclusions.entries[0].calendarSourceKey == entry.calendarSourceKey,
               "All-day, cancelled, declined and invalid intervals do not become classes")
        expect(exclusions.allDayCount == 1, "All-day events are counted for the review explanation")
        expect(exclusions.excludedCount >= 4, "Cancelled, declined and invalid intervals are accounted for as exclusions")
        let emptyTitle = CalendarEventConverter.convert([
            event("untitled", "2026-09-08T10:00:00+09:00", "2026-09-08T11:00:00+09:00", title: " \n ")
        ], week: week).entries
        expect(emptyTitle.count == 1 && !emptyTitle[0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && emptyTitle[0].validationError == nil,
               "A blank event title receives a usable nonempty fallback")
        let subminute = CalendarEventConverter.convert([
            event("seconds", "2026-09-08T10:00:20+09:00", "2026-09-08T10:00:40+09:00")
        ], week: week)
        expect(subminute.entries.count == 1 && subminute.entries[0].startMinutes == 600 && subminute.entries[0].endMinutes == 601 && !subminute.warnings.isEmpty,
               "A positive subminute event remains visible with an explicit rounding explanation")

        var tuesday = normal; tuesday.startDate = date("2026-09-08T10:15:00+09:00"); tuesday.endDate = date("2026-09-08T11:45:00+09:00")
        var otherID = normal; otherID.id = "other-event"
        var otherCalendar = normal; otherCalendar.calendarID = "personal"
        let recurring = CalendarEventConverter.convert([normal, normal, tuesday, otherID, otherCalendar], week: week).entries
        expect(recurring.count == 4, "Duplicate reads collapse while recurring occurrences and separate events survive")
        expect(Set(recurring.compactMap(\.calendarSourceKey)).count == 4, "Event, calendar and occurrence differences have distinct source keys")
        let repeatedRead = CalendarEventConverter.convert([otherCalendar, otherID, tuesday, normal], week: week).entries
        expect(Set(recurring.compactMap(\.calendarSourceKey)) == Set(repeatedRead.compactMap(\.calendarSourceKey)),
               "Source identities remain stable across reloads and input ordering")
        var renamed = normal; renamed.title = "Updated title"; renamed.location = "New room"
        expect(CalendarEventConverter.convert([renamed], week: week).entries[0].calendarSourceKey == entry.calendarSourceKey,
               "Editing an event title or location preserves its source identity")
        var moved = normal; moved.occurrenceDate = normal.startDate
        let beforeMove = CalendarEventConverter.convert([moved], week: week).entries[0].calendarSourceKey
        moved.startDate = moved.startDate.addingTimeInterval(3600); moved.endDate = moved.endDate.addingTimeInterval(3600)
        expect(CalendarEventConverter.convert([moved], week: week).entries[0].calendarSourceKey == beforeMove,
               "A moved recurrence uses its original occurrence date for stable identity")
        var morning = normal; morning.occurrenceDate = normal.startDate
        var afternoon = normal; afternoon.startDate = normal.startDate.addingTimeInterval(4 * 3600); afternoon.endDate = normal.endDate.addingTimeInterval(4 * 3600); afternoon.occurrenceDate = afternoon.startDate
        let sameDayOccurrences = CalendarEventConverter.convert([morning, afternoon, morning], week: week).entries
        expect(sameDayOccurrences.count == 2 && Set(sameDayOccurrences.compactMap(\.calendarSourceKey)).count == 2,
               "Distinct recurring occurrences on the same day survive duplicate reads")
    }

    private static func checkPersistence() throws {
        let legacy = Data("""
        {"id":"D080A4EE-8287-4940-A9AD-A4A12655338A","name":"Legacy class","day":0,"startMinutes":600,"endMinutes":660,"location":"A101"}
        """.utf8)
        let decoded = try JSONDecoder().decode(ScheduleEntry.self, from: legacy)
        expect(decoded.name == "Legacy class" && decoded.calendarSourceKey == nil,
               "Existing saved classes decode without a calendar source key")
        var imported = decoded; imported.calendarSourceKey = "synthetic-calendar-event"
        let roundTrip = try JSONDecoder().decode(ScheduleEntry.self, from: JSONEncoder().encode(imported))
        expect(roundTrip == imported, "A saved imported class preserves its calendar identity")
    }

    private static func checkMerging() {
        let manual = ScheduleEntry(name: "Manual class", day: 0, startMinutes: 600, endMinutes: 660)
        var first = manual; first.id = UUID(); first.name = "Calendar class"; first.calendarSourceKey = "source-1"
        let initial = CalendarEntryMerger.merge(existing: [manual], incoming: [first])
        expect(initial.count == 2 && initial[0] == manual, "Adding a calendar class preserves an existing manual class")
        var updated = first; updated.id = UUID(); updated.name = "Revised class"; updated.startMinutes = 630; updated.endMinutes = 690
        let second = CalendarEntryMerger.merge(existing: initial, incoming: [updated])
        expect(second.count == 2 && second[1].name == "Revised class" && second[1].startMinutes == 630,
               "Reimporting the same source updates its existing class without duplication")
        expect(second[1].id == first.id && second[0] == manual, "An upsert preserves the local class identity and unrelated manual entries")
        var separate = updated; separate.id = UUID(); separate.calendarSourceKey = "source-2"
        let distinct = CalendarEntryMerger.merge(existing: second, incoming: [separate])
        expect(distinct.count == 3, "Different calendar sources survive even when displayed details match")
        var invalid = first; invalid.calendarSourceKey = "invalid"; invalid.endMinutes = invalid.startMinutes
        expect(CalendarEntryMerger.merge(existing: distinct, incoming: [invalid]) == distinct, "Invalid incoming classes are rejected by the merge boundary")
        let duplicateIncoming = CalendarEntryMerger.merge(existing: [manual], incoming: [first, updated])
        expect(duplicateIncoming.count == 2 && duplicateIncoming[1].name == "Revised class", "Repeated source keys within one import merge only once")
    }

    private static func waitForRequests(_ count: Int, provider: FakeCalendarProvider) async {
        for _ in 0..<10_000 {
            if provider.eventRequests.count >= count { return }
            await Task.yield()
        }
        fatalError("The fake provider did not receive \(count) requests")
    }

    private static func checkModel() async {
        let chosenDate = date("2026-09-09T13:00:00+09:00")
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let neverPrompt = FakeCalendarProvider(access: .notDetermined)
        let unopened = CalendarImportModel(provider: neverPrompt, date: chosenDate, timeZone: seoul)
        await unopened.loadIfAuthorized()
        expect(neverPrompt.permissionRequests == 0 && neverPrompt.calendarReads == 0 && neverPrompt.eventRequests.isEmpty,
               "Opening the importer never prompts or reads calendars before permission")
        expect(unopened.access == .notDetermined && !unopened.canImport, "An unconnected importer cannot add classes")

        let deniedProvider = FakeCalendarProvider(access: .denied)
        let denied = CalendarImportModel(provider: deniedProvider, date: chosenDate, timeZone: seoul)
        await denied.loadIfAuthorized()
        await denied.fetchEvents()
        expect(deniedProvider.permissionRequests == 0 && deniedProvider.calendarReads == 0 && deniedProvider.eventRequests.isEmpty,
               "A denied importer performs no provider reads or implicit permission requests")
        expect(denied.error != nil && !denied.canImport, "Denied access produces a useful error and disables import")
        let refusingProvider = FakeCalendarProvider(access: .notDetermined)
        refusingProvider.willGrantAccess = false
        let refusing = CalendarImportModel(provider: refusingProvider, date: chosenDate, timeZone: seoul)
        await refusing.connect()
        expect(refusingProvider.permissionRequests == 1 && refusingProvider.calendarReads == 0 && refusing.access == .denied && refusing.error != nil && !refusing.isLoading,
               "An explicit connection denial ends loading and displays the permission failure")

        let provider = FakeCalendarProvider(access: .notDetermined)
        let model = CalendarImportModel(provider: provider, date: chosenDate, timeZone: seoul)
        await model.connect()
        expect(provider.permissionRequests == 1 && provider.calendarReads == 1 && model.access == .authorized && model.calendars.count == 2,
               "Only explicit Connect requests access and then loads calendar choices")
        expect(model.selectedCalendarIDs.isEmpty && provider.eventRequests.isEmpty, "Connecting selects no calendars and fetches no private events automatically")
        await model.fetchEvents()
        expect(provider.eventRequests.isEmpty && model.error != nil && !model.canImport, "An empty calendar selection never becomes a request for all calendars")
        model.selectedCalendarIDs = ["school"]
        provider.records = [event("model", "2026-09-07T10:00:00+09:00", "2026-09-07T11:00:00+09:00")]
        await model.fetchEvents()
        expect(provider.eventRequests.count == 1 && provider.eventRequests[0].ids == ["school"] && provider.eventRequests[0].week == model.week,
               "Fetching forwards exactly the chosen calendar IDs and week")
        expect(model.reviewEntries.count == 1 && model.selectedEntryIDs.count == 1 && !model.confirmed && !model.canImport,
               "Fetched classes require explicit review confirmation before import")
        model.confirmed = true
        expect(model.canImport, "Valid selected classes become importable after confirmation")
        var edited = model.reviewEntries[0]; edited.name = "Edited in review"
        model.updateEntry(edited)
        expect(model.reviewEntries[0].name == edited.name && !model.confirmed && !model.canImport,
               "Editing a review class clears prior confirmation")
        model.confirmed = true
        model.selectedEntryIDs = []
        expect(!model.confirmed && !model.canImport, "Deselecting every class disables import and clears confirmation")
        model.selectedEntryIDs = Set(model.reviewEntries.map(\.id)); model.confirmed = true
        model.selectedDate = date("2026-09-16T13:00:00+09:00")
        expect(model.result == nil && model.reviewEntries.isEmpty && !model.confirmed && !model.canImport,
               "Changing the selected week discards the previous review immediately")

        let authorized = FakeCalendarProvider(access: .authorized)
        let restored = CalendarImportModel(provider: authorized, date: chosenDate, timeZone: seoul)
        await restored.loadIfAuthorized()
        expect(authorized.permissionRequests == 0 && authorized.calendarReads == 1 && authorized.eventRequests.isEmpty,
               "Existing permission loads choices without prompting or automatically fetching events")
        restored.selectedCalendarIDs = ["school", "personal"]
        authorized.availableCalendars.removeAll { $0.id == "personal" }
        await restored.refreshCalendars()
        expect(restored.selectedCalendarIDs == ["school"] && restored.calendars.count == 1,
               "Refreshing removes selections for calendars that no longer exist")
        authorized.access = .restricted
        await restored.refreshCalendars()
        expect(restored.access == .restricted && restored.calendars.isEmpty && restored.selectedCalendarIDs.isEmpty && !restored.canImport,
               "A revoked or restricted permission clears calendar choices and importability")

        await checkStaleRequests(date: chosenDate, timeZone: seoul)
        await checkImportBoundaryAndExternalChanges(date: chosenDate, timeZone: seoul)
    }

    private static func checkImportBoundaryAndExternalChanges(date chosenDate: Date, timeZone: TimeZone) async {
        let provider = FakeCalendarProvider(access: .authorized)
        let model = CalendarImportModel(provider: provider, date: chosenDate, timeZone: timeZone)
        provider.records = [event("reviewed", "2026-09-07T10:00:00+09:00", "2026-09-07T11:00:00+09:00")]
        await model.loadIfAuthorized()
        model.selectedCalendarIDs = ["school"]
        await model.fetchEvents()
        expect(!model.validateForImport(), "The commit boundary rejects an unconfirmed review")
        model.confirmed = true
        let reviewedEntries = model.reviewEntries
        expect(model.validateForImport() && model.reviewEntries == reviewedEntries && model.confirmed,
               "A confirmed review with current permission and valid sources passes the commit boundary")
        model.refreshAfterExternalChange()
        expect(model.reviewEntries == reviewedEntries && model.confirmed && model.canImport,
               "App activation with unchanged permission and calendars preserves a reviewed selection")

        provider.access = .denied
        expect(!model.validateForImport() && model.access == .denied && model.result == nil && model.reviewEntries.isEmpty && !model.confirmed && model.error != nil,
               "Permission revoked after confirmation rejects the import and clears its stale review")
        provider.access = .authorized
        model.refreshAfterExternalChange()
        expect(model.access == .authorized && model.calendars.count == 2 && model.result == nil && provider.permissionRequests == 0,
               "Restoring access externally refreshes calendar choices without requesting permission")

        model.selectedCalendarIDs = ["school"]
        await model.fetchEvents()
        model.confirmed = true
        provider.availableCalendars.removeAll { $0.id == "school" }
        expect(!model.validateForImport() && model.result == nil && model.reviewEntries.isEmpty && !model.confirmed && model.error != nil,
               "Deleting a selected calendar after confirmation rejects the import and clears its stale review")
        model.refreshAfterExternalChange()
        expect(model.selectedCalendarIDs.isEmpty && model.calendars.map(\.id) == ["personal"],
               "Refreshing after a calendar deletion removes its unavailable selection")

        model.selectedCalendarIDs = ["personal"]
        provider.records = [event("personal-reviewed", "2026-09-07T10:00:00+09:00", "2026-09-07T11:00:00+09:00", calendarID: "personal")]
        await model.fetchEvents()
        model.confirmed = true
        provider.availableCalendars[0].title = "Renamed personal calendar"
        model.refreshAfterExternalChange()
        expect(model.result == nil && model.reviewEntries.isEmpty && !model.confirmed && model.calendars[0].title == "Renamed personal calendar",
               "An external source descriptor change refreshes the list and invalidates prior review")

        await model.fetchEvents()
        model.confirmed = true
        provider.access = .restricted
        model.refreshAfterExternalChange()
        expect(model.access == .restricted && model.calendars.isEmpty && model.selectedCalendarIDs.isEmpty && model.reviewEntries.isEmpty && !model.canImport,
               "An external permission restriction clears choices and confirmed review on activation")
    }

    private static func checkEmptySnapshots() async {
        let chosenDate = date("2026-09-09T13:00:00+09:00")
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let provider = FakeCalendarProvider(access: .authorized)
        let model = CalendarImportModel(provider: provider, date: chosenDate, timeZone: timeZone)
        await model.loadIfAuthorized()
        model.selectedCalendarIDs = ["school"]
        model.confirmed = true
        expect(!model.isEmptySnapshot && !model.canImport && !model.validateForImport(),
               "An unfetched review cannot be mistaken for a confirmed empty calendar week")

        await model.fetchEvents()
        expect(model.isEmptySnapshot && model.result != nil && model.reviewEntries.isEmpty && !model.confirmed && !model.canImport,
               "A successfully fetched empty week is identifiable and still requires confirmation")
        model.confirmed = true
        expect(model.canImport && model.validateForImport(),
               "A confirmed empty week can establish a calendar connection for future automation")

        model.selectedDate = date("2026-09-16T13:00:00+09:00")
        expect(!model.isEmptySnapshot && !model.confirmed && !model.canImport,
               "Changing the week invalidates a previously confirmed empty snapshot")
        model.selectedDate = chosenDate
        provider.records = [event("real", "2026-09-09T10:00:00+09:00", "2026-09-09T11:00:00+09:00")]
        await model.fetchEvents()
        model.selectedEntryIDs = []
        model.confirmed = true
        expect(!model.isEmptySnapshot && !model.canImport && !model.validateForImport(),
               "Deselecting all fetched events cannot masquerade as an empty-week connection")

        provider.records = []
        await model.fetchEvents()
        model.confirmed = true
        provider.access = .denied
        expect(!model.validateForImport() && model.result == nil && !model.isEmptySnapshot && model.error != nil,
               "Revoking permission after an empty review rejects connection and discards the snapshot")
        provider.access = .authorized
        await model.loadIfAuthorized()
        model.selectedCalendarIDs = ["school"]
        await model.fetchEvents()
        model.confirmed = true
        provider.availableCalendars.removeAll { $0.id == "school" }
        expect(!model.validateForImport() && model.result == nil && !model.isEmptySnapshot && model.error != nil,
               "Deleting the selected calendar after an empty review rejects connection instead of clearing entries")

        provider.availableCalendars = [.init(id: "school", title: "Classes", account: "Synthetic Google", colorHex: 0xE86E36)]
        await model.refreshCalendars()
        model.selectedCalendarIDs = ["school"]
        provider.eventError = CalendarImportError.calendarsChanged
        await model.fetchEvents()
        model.confirmed = true
        expect(model.error != nil && model.result == nil && !model.isEmptySnapshot && !model.canImport && !model.validateForImport(),
               "A failed event fetch never becomes an importable empty snapshot")
        provider.eventError = nil
        model.selectedCalendarIDs = []
        await model.fetchEvents()
        model.confirmed = true
        expect(model.error != nil && !model.isEmptySnapshot && !model.canImport,
               "No selected calendar cannot establish an empty connection")

        model.selectedCalendarIDs = ["school"]
        provider.suspendEvents = true
        let pendingIndex = provider.eventRequests.count
        let pending = Task { await model.fetchEvents() }
        await waitForRequests(pendingIndex + 1, provider: provider)
        model.confirmed = true
        expect(model.isLoading && !model.isEmptySnapshot && !model.canImport,
               "A pending empty-looking read is not an importable empty snapshot")
        provider.completeRequest(pendingIndex, with: [])
        await pending.value
        expect(model.isEmptySnapshot && !model.confirmed && !model.canImport,
               "Completion of an empty read requires fresh confirmation after loading")
        model.confirmed = true
        expect(model.canImport && model.validateForImport() && provider.permissionRequests == 0,
               "A completed empty read passes the same permission and source checks without requesting new access")
    }

    private static func checkStaleRequests(date chosenDate: Date, timeZone: TimeZone) async {
        let provider = FakeCalendarProvider(access: .authorized)
        provider.suspendEvents = true
        let model = CalendarImportModel(provider: provider, date: chosenDate, timeZone: timeZone)
        await model.loadIfAuthorized()
        model.selectedCalendarIDs = ["school"]
        let original = Task { await model.fetchEvents() }
        await waitForRequests(1, provider: provider)
        expect(model.isLoading, "A pending calendar request exposes its loading state")
        model.selectedDate = date("2026-09-16T13:00:00+09:00")
        expect(!model.isLoading && model.result == nil && !model.canImport, "A date change invalidates the in-flight request immediately")
        let replacement = Task { await model.fetchEvents() }
        await waitForRequests(2, provider: provider)
        provider.completeRequest(1, with: [event("new", "2026-09-14T09:00:00+09:00", "2026-09-14T10:00:00+09:00", title: "New week")])
        await replacement.value
        provider.completeRequest(0, with: [event("old", "2026-09-07T09:00:00+09:00", "2026-09-07T10:00:00+09:00", title: "Old week")])
        await original.value
        expect(model.reviewEntries.count == 1 && model.reviewEntries[0].name == "New week" && !model.isLoading,
               "An older request finishing last cannot overwrite the new week's result")

        let previousCalendar = Task { await model.fetchEvents() }
        await waitForRequests(3, provider: provider)
        model.selectedCalendarIDs = ["personal"]
        let newCalendar = Task { await model.fetchEvents() }
        await waitForRequests(4, provider: provider)
        provider.completeRequest(2, with: [event("school-old", "2026-09-14T09:00:00+09:00", "2026-09-14T10:00:00+09:00", title: "Old calendar")])
        await previousCalendar.value
        expect(model.isLoading && model.result == nil, "A stale calendar response cannot finish the newer request's loading state")
        provider.completeRequest(3, with: [event("personal-new", "2026-09-14T09:00:00+09:00", "2026-09-14T10:00:00+09:00", title: "Chosen calendar", calendarID: "personal")])
        await newCalendar.value
        expect(model.reviewEntries.count == 1 && model.reviewEntries[0].name == "Chosen calendar" && provider.eventRequests[3].ids == ["personal"],
               "Changing calendar selections retains only the matching new response")

        let deselected = Task { await model.fetchEvents() }
        await waitForRequests(5, provider: provider)
        model.selectedCalendarIDs = []
        provider.completeRequest(4, with: [event("cleared", "2026-09-14T09:00:00+09:00", "2026-09-14T10:00:00+09:00", calendarID: "personal")])
        await deselected.value
        expect(model.reviewEntries.isEmpty && model.result == nil && !model.canImport,
               "Deselecting all calendars rejects a previously requested result")

        model.selectedCalendarIDs = ["school"]
        let revoked = Task { await model.fetchEvents() }
        await waitForRequests(6, provider: provider)
        provider.access = .denied
        provider.completeRequest(5, with: [event("revoked", "2026-09-14T09:00:00+09:00", "2026-09-14T10:00:00+09:00")])
        await revoked.value
        expect(model.access == .denied && model.result == nil && model.reviewEntries.isEmpty && model.error != nil && !model.canImport,
               "Permission revoked during a request prevents its events from entering review")
    }

    static func main() async throws {
        checkWeeksAndConversion()
        try checkPersistence()
        checkMerging()
        await checkModel()
        await checkEmptySnapshots()
        print("Calendar verification completed: \(checks) checks passed using synthetic fixtures only.")
    }
}

@MainActor
private final class FakeCalendarProvider: CalendarProviding {
    struct Request {
        var ids: Set<String>
        var week: CalendarWeek
    }
    var access: CalendarAccess
    var willGrantAccess = true
    var permissionRequests = 0
    var calendarReads = 0
    var eventRequests: [Request] = []
    var records: [CalendarEventRecord] = []
    var suspendEvents = false
    var eventError: Error?
    var availableCalendars: [CalendarDescriptor] = [
        .init(id: "school", title: "Classes", account: "Synthetic Google", colorHex: 0xE86E36),
        .init(id: "personal", title: "Personal", account: "Synthetic iCloud", colorHex: 0x728A53)
    ]
    private var pending: [Int: CheckedContinuation<[CalendarEventRecord], Error>] = [:]

    init(access: CalendarAccess) { self.access = access }

    func requestAccess() async throws -> Bool {
        permissionRequests += 1
        access = willGrantAccess ? .authorized : .denied
        return willGrantAccess
    }

    func calendars() throws -> [CalendarDescriptor] {
        calendarReads += 1
        return availableCalendars
    }

    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        let index = eventRequests.count
        eventRequests.append(.init(ids: calendarIDs, week: week))
        if suspendEvents {
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        if let eventError { throw eventError }
        return records.filter { calendarIDs.contains($0.calendarID) }
    }

    func completeRequest(_ index: Int, with records: [CalendarEventRecord]) {
        guard let continuation = pending.removeValue(forKey: index) else {
            fatalError("No pending synthetic request at index \(index)")
        }
        continuation.resume(returning: records)
    }
}
