import Foundation

/// Uses synthetic permissions, calendar events and an in-memory wallpaper sink.
/// No real account, EventKit store, desktop, settings or permission prompt is used.
@main
@MainActor
enum CalendarRecoveryVerification {
    private static var checks = 0
    private static let seoul = TimeZone(identifier: "Asia/Seoul")!
    private static let now = ISO8601DateFormatter().date(from: "2026-09-09T13:00:00+09:00")!

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }

    private static func context() -> AutomationContext {
        let week = CalendarWeek(containing: now, timeZone: seoul)
        return AutomationContext(
            entries: [ScheduleEntry(name: "수동 일정", day: 1, startMinutes: 540, endMinutes: 600),
                      ScheduleEntry(name: "기존 캘린더 일정", day: 2, startMinutes: 600, endMinutes: 660, calendarSourceKey: "old-managed")],
            configuration: WallpaperConfiguration(),
            settings: AutomationSettings(refreshOnCalendarChange: true, refreshWeekly: true,
                                         targetDisplayID: "synthetic-display", targetDisplayName: "Synthetic display"),
            connection: CalendarConnection(calendarIDs: ["classes"], calendarNames: ["원래 선택한 캘린더"],
                                           weekStart: week.start, timeZoneID: seoul.identifier,
                                           managedEntryKeys: ["old-managed"], includeWeekTitle: true),
            receipt: nil, timeZone: seoul)
    }

    private static func event() -> CalendarEventRecord {
        CalendarEventRecord(id: "recovered-event", calendarID: "classes", title: "권한 복구 후 일정",
                            startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(-1800))
    }

    private static func verifyStatusOnly() async {
        let provider = RecoveryProvider()
        let recovery = CalendarAccessRecovery(provider: provider)
        expect(provider.requests == 0, "Creating the recovery model never requests permission")
        for access in [CalendarAccess.notDetermined, .denied, .restricted, .authorized] {
            provider.access = access
            recovery.refreshStatus()
            expect(recovery.access == access, "Status refresh reflects \(access) access")
        }
        expect(provider.requests == 0 && provider.calendarReads == 0 && provider.eventReads == 0,
               "Status refresh never requests permission or reads calendar data")

        for access in [CalendarAccess.notDetermined, .denied, .restricted] {
            provider.access = access
            let harness = RecoveryHarness(provider: provider, context: context())
            let before = harness.snapshot.context
            await harness.engine.check(trigger: .launch, now: now)
            await harness.engine.check(trigger: .calendarChanged, now: now)
            expect(provider.requests == 0, "Background \(access) checks never invoke the explicit permission path")
            expect(harness.snapshot.context.entries == before.entries && harness.snapshot.context.connection == before.connection,
                   "Background \(access) checks preserve saved entries and calendar selection")
            expect(harness.snapshot.updates == 0 && harness.snapshot.context.receipt == before.receipt,
                   "Background \(access) checks preserve wallpaper and successful receipt")
        }
    }

    private static func verifyGrantAndDenial() async {
        let provider = RecoveryProvider()
        provider.access = .denied
        let recovery = CalendarAccessRecovery(provider: provider)
        var initial = context()
        initial.receipt = AutomationReceipt(wallpaperFingerprint: "previous-wallpaper", calendarFingerprint: "previous-calendar",
                                            appliedAt: now.addingTimeInterval(-86400), weekStart: initial.connection?.weekStart,
                                            dayKey: "previous-day", targetDisplayID: "synthetic-display")
        let harness = RecoveryHarness(provider: provider, context: initial)
        let before = harness.snapshot.context
        provider.requestResult = false
        provider.accessAfterRequest = .denied
        expect(!(await recovery.reconnect()), "Explicit denial returns failure")
        expect(provider.requests == 1 && recovery.access == .denied && recovery.errorMessage != nil && !recovery.isConnecting,
               "Explicit denial is visible and ends its loading state")
        expect(harness.snapshot.context.entries == before.entries && harness.snapshot.context.connection == before.connection && harness.snapshot.context.settings == before.settings,
               "Denied reconnection leaves entries, selected calendars and automation options intact")
        expect(provider.calendarReads == 0 && provider.eventReads == 0 && harness.snapshot.updates == 0,
               "Denied reconnection does not read or apply a calendar snapshot")
        expect(harness.snapshot.context.receipt == before.receipt && harness.engine.lastAppliedAt == before.receipt?.appliedAt,
               "Denied reconnection preserves the last successful wallpaper receipt and timestamp")

        provider.requestFailure = RecoveryFailure()
        expect(!(await recovery.reconnect()) && recovery.errorMessage == RecoveryFailure().localizedDescription,
               "A permission request error remains visible without changing the saved connection")
        expect(harness.snapshot.context.entries == before.entries && harness.snapshot.context.connection == before.connection && harness.snapshot.context.receipt == before.receipt,
               "A request error preserves prior entries, connection and receipt")

        provider.requestFailure = nil
        provider.requestResult = true
        provider.accessAfterRequest = .denied
        expect(!(await recovery.reconnect()), "A claimed grant is rejected when actual authorization is still denied")
        expect(recovery.access == .denied && recovery.errorMessage != nil, "The actual authorization state controls recovery success")

        provider.accessAfterRequest = .authorized
        provider.records = [event()]
        let recovered = await recovery.reconnect()
        expect(recovered && recovery.access == .authorized && recovery.errorMessage == nil && !recovery.isConnecting,
               "An explicit successful request recovers authorization and clears the old error")
        expect(provider.eventReads == 0 && harness.snapshot.updates == 0,
               "Permission recovery itself does not apply an unsolicited wallpaper")
        if recovered { await harness.engine.check(trigger: .manual, now: now) }
        expect(provider.eventReads == 1 && harness.snapshot.updates == 1, "The existing opt-in automation can fetch and apply after explicit recovery")
        expect(harness.snapshot.context.connection?.calendarIDs == before.connection?.calendarIDs,
               "Recovery checks the existing calendar selection")
        expect(harness.snapshot.context.entries.contains(where: { $0.id == before.entries[0].id }) && harness.snapshot.context.entries.contains(where: { $0.name == event().title }),
               "Recovered calendar data replaces managed entries while keeping manual entries")
        expect(!harness.snapshot.context.entries.contains(where: { $0.calendarSourceKey == "old-managed" }),
               "Recovered synchronization removes the old managed snapshot")

        let offProvider = RecoveryProvider()
        offProvider.accessAfterRequest = .authorized
        let offRecovery = CalendarAccessRecovery(provider: offProvider)
        var offContext = context()
        offContext.settings = AutomationSettings()
        let off = RecoveryHarness(provider: offProvider, context: offContext)
        if await offRecovery.reconnect() { await off.engine.check(trigger: .manual, now: now) }
        expect(offProvider.requests == 1 && offProvider.eventReads == 0 && off.snapshot.updates == 0,
               "Explicit access recovery respects disabled automation options")
    }

    private static func waitForRequest(_ provider: RecoveryProvider) async {
        for _ in 0..<10_000 {
            if provider.pending != nil { return }
            await Task.yield()
        }
        fatalError("Synthetic permission request did not suspend")
    }

    private static func verifyConcurrentAndCancelled() async {
        let provider = RecoveryProvider()
        provider.suspendRequest = true
        provider.accessAfterRequest = .authorized
        let recovery = CalendarAccessRecovery(provider: provider)
        let first = Task { await recovery.reconnect() }
        await waitForRequest(provider)
        expect(recovery.isConnecting, "An in-flight explicit request publishes its loading state")
        expect(!(await recovery.reconnect()) && provider.requests == 1, "A second click cannot create a duplicate permission request")
        recovery.refreshStatus()
        expect(provider.requests == 1 && recovery.isConnecting, "A status refresh during a prompt does not start or discard the request")
        provider.completeRequest()
        expect(await first.value, "The first explicit request can still complete successfully")
        expect(!recovery.isConnecting, "Completion clears the loading state")

        provider.access = .notDetermined
        let cancelled = Task { await recovery.reconnect() }
        await waitForRequest(provider)
        cancelled.cancel()
        provider.completeRequest()
        expect(!(await cancelled.value), "A cancelled reconnect does not authorize its caller to fetch or apply")
        expect(!recovery.isConnecting && recovery.errorMessage == nil, "Cancellation ends loading without a misleading permission error")
        expect(provider.calendarReads == 0 && provider.eventReads == 0, "Cancelled recovery never reads calendar data")

        provider.suspendRequest = false
        provider.requestFailure = CancellationError()
        expect(!(await recovery.reconnect()) && recovery.errorMessage == nil && !recovery.isConnecting,
               "Provider cancellation is handled quietly and restores controls")

        provider.requestFailure = nil
        let countBeforeCancellation = provider.requests
        let neverStarted = Task { await recovery.reconnect() }
        neverStarted.cancel()
        expect(!(await neverStarted.value) && provider.requests == countBeforeCancellation,
               "A task cancelled before reconnect starts never requests permission")

        provider.requestResult = false
        provider.accessAfterRequest = .denied
        _ = await recovery.reconnect()
        expect(recovery.errorMessage != nil, "A later denial has a visible error")
        let requests = provider.requests
        provider.access = .authorized
        recovery.refreshStatus()
        expect(recovery.errorMessage == nil && recovery.access == .authorized && provider.requests == requests,
               "Access restored in system settings clears the old error without a new prompt")
    }

    static func main() async {
        await verifyStatusOnly()
        await verifyGrantAndDenial()
        await verifyConcurrentAndCancelled()
        print("Verified \(checks) explicit calendar recovery assertions using synthetic data only.")
    }
}

private struct RecoveryFailure: LocalizedError {
    var errorDescription: String? { "Synthetic permission request failure" }
}

@MainActor
private final class RecoveryProvider: CalendarProviding {
    var access = CalendarAccess.notDetermined
    var accessAfterRequest = CalendarAccess.authorized
    var requestResult = true
    var requestFailure: Error?
    var suspendRequest = false
    var pending: CheckedContinuation<Bool, Error>?
    var requests = 0
    var calendarReads = 0
    var eventReads = 0
    var records: [CalendarEventRecord] = []
    func requestAccess() async throws -> Bool {
        requests += 1
        if let requestFailure { throw requestFailure }
        if suspendRequest { return try await withCheckedThrowingContinuation { pending = $0 } }
        access = accessAfterRequest
        return requestResult
    }
    func completeRequest() {
        guard let request = pending else { fatalError("No synthetic request is pending") }
        pending = nil
        access = accessAfterRequest
        request.resume(returning: requestResult)
    }
    func calendars() throws -> [CalendarDescriptor] {
        calendarReads += 1
        return [.init(id: "classes", title: "Synthetic calendar", account: "Synthetic account", colorHex: 0)]
    }
    func events(calendarIDs: Set<String>, week: CalendarWeek) async throws -> [CalendarEventRecord] {
        eventReads += 1
        return records
    }
}

@MainActor
private final class RecoverySnapshot {
    var context: AutomationContext
    var updates = 0
    init(_ context: AutomationContext) { self.context = context }
    func accept(_ update: AutomationUpdate) {
        updates += 1
        context.entries = update.entries
        context.configuration = update.configuration
        context.connection = update.connection
        context.receipt = update.receipt
    }
}

@MainActor
private final class RecoveryHarness {
    let engine: WallpaperAutomation
    let snapshot: RecoverySnapshot
    init(provider: RecoveryProvider, context: AutomationContext) {
        let snapshot = RecoverySnapshot(context)
        self.snapshot = snapshot
        engine = WallpaperAutomation(provider: provider, apply: { snapshot.accept($0) }, onStateChange: { snapshot.accept($0) })
        engine.configure(context)
    }
}
