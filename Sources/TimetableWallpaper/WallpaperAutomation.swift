import Combine
import CryptoKit
import Foundation

/// Coordinates opt-in calendar snapshots and date-dependent decoration. The
/// injected apply closure is the only place allowed to change the desktop.
@MainActor
final class WallpaperAutomation: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var status = "자동 배경화면 교체가 꺼져 있습니다."
    @Published private(set) var lastAppliedAt: Date?
    @Published private(set) var needsCalendarReconnect = false

    private let provider: any CalendarProviding
    private let apply: (AutomationUpdate) throws -> Void
    private let onStateChange: ((AutomationUpdate) -> Void)?
    private var context: AutomationContext?
    private var generation: UInt64 = 0
    private var configurationVersion: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var pending: Request?
    private var active: Request?

    private struct Request {
        var trigger: AutomationTrigger
        var now: Date
        var configurationVersion: UInt64
    }

    init(provider: any CalendarProviding,
         apply: @escaping (AutomationUpdate) throws -> Void,
         onStateChange: ((AutomationUpdate) -> Void)? = nil) {
        self.provider = provider
        self.apply = apply
        self.onStateChange = onStateChange
    }

    /// User edits invalidate any awaited query, including its pending rerun.
    /// The owner can explicitly schedule a fresh check with the new context.
    func configure(_ context: AutomationContext) {
        generation &+= 1
        configurationVersion &+= 1
        pending = nil
        self.context = context
        lastAppliedAt = context.receipt?.appliedAt
        status = idleStatus(context)
    }

    /// A single worker drains the latest request. New notifications invalidate
    /// in-flight results and retain one rerun, so changes during a fetch cannot
    /// be lost or allow an older response to overwrite a newer one.
    func check(trigger: AutomationTrigger, now: Date = Date()) async {
        guard let context, context.settings.hasAutomation else {
            status = "자동 배경화면 교체가 꺼져 있습니다."
            return
        }
        generation &+= 1
        let previous = pending ?? active
        let mergedTrigger: AutomationTrigger
        if previous?.configurationVersion == configurationVersion,
           previous?.trigger == .enabled {
            mergedTrigger = .enabled
        } else if trigger == .enabled {
            mergedTrigger = .enabled
        } else if trigger == .manual || (previous?.configurationVersion == configurationVersion && previous?.trigger == .manual) {
            mergedTrigger = .manual
        } else if previous?.configurationVersion == configurationVersion,
                  previous?.trigger == .settingsChanged {
            mergedTrigger = .settingsChanged
        } else {
            mergedTrigger = trigger
        }
        pending = Request(trigger: mergedTrigger, now: now, configurationVersion: configurationVersion)
        if worker == nil {
            isChecking = true
            // This unstructured task owns the drain. Cancellation of one caller
            // cannot discard a later caller's queued calendar notification.
            worker = Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
        await worker?.value
    }

    private func drain() async {
        defer {
            active = nil
            worker = nil
            isChecking = false
        }
        while let request = pending {
            pending = nil
            active = request
            let revision = generation
            await process(request, revision: revision)
            active = nil
        }
    }

    private func process(_ request: Request, revision: UInt64) async {
        guard var candidate = context, candidate.settings.hasAutomation,
              revision == generation else { return }
        let settings = candidate.settings
        guard let target = settings.targetDisplayID, !target.isEmpty else {
            status = "자동 적용할 디스플레이를 선택해주세요."
            return
        }
        if settings.hasCalendarAutomation, candidate.connection == nil {
            status = "캘린더에서 가져오기를 열고 자동 교체할 캘린더를 연결해주세요."
            return
        }
        if !settings.hasCalendarAutomation, candidate.receipt == nil {
            status = "배경화면을 한 번 적용하면 오늘 표시가 매일 자동으로 갱신됩니다."
            return
        }

        let week = CalendarWeek(containing: request.now, timeZone: candidate.timeZone)
        let differentWeek = candidate.connection.map {
            $0.weekStart != week.start || $0.timeZoneID != candidate.timeZone.identifier
        } ?? false
        let initialize = request.trigger == .enabled || candidate.receipt == nil
        // Explicit rechecking can recover a failed enable within this week.
        // It must not advance an older snapshot when weekly refresh is disabled.
        let mayRefreshWeek = request.trigger != .manual || !differentWeek || settings.refreshWeekly
        let manualRefresh = request.trigger == .manual && mayRefreshWeek
        let shouldFetch = settings.hasCalendarAutomation && mayRefreshWeek &&
            (initialize || manualRefresh || (settings.refreshWeekly && differentWeek) ||
             (settings.refreshOnCalendarChange && !differentWeek))
        let shouldCheckAppearance = candidate.receipt != nil &&
            (settings.showToday || request.trigger == .settingsChanged || request.trigger == .enabled || request.trigger == .launch || request.trigger == .wake)

        guard shouldFetch || shouldCheckAppearance else {
            status = waitingStatus(candidate, differentWeek: differentWeek)
            return
        }

        var calendarFingerprint = candidate.receipt?.calendarFingerprint
        do {
            if shouldFetch, var connection = candidate.connection {
                status = "이번 주 캘린더 일정을 확인하고 있습니다…"
                _ = try validateConnection(connection)
                let events = try await provider.events(calendarIDs: connection.calendarIDs, week: week)
                // Both user edits and newer notifications supersede this query.
                guard revision == generation else { return }
                let calendars = try validateConnection(connection)
                needsCalendarReconnect = false
                let converted = CalendarEventConverter.convert(events, week: week).entries
                // Reconcile every source record before filtering, so a hidden
                // event can keep its latest identity/details without resurfacing.
                candidate.calendarVisibility.reconcile(with: converted)
                let oldEntries = candidate.entries
                let existingByKey = Dictionary(oldEntries.compactMap { entry in
                    entry.calendarSourceKey.map { ($0, entry.id) }
                }, uniquingKeysWith: { first, _ in first })
                let incoming = converted.filter { !candidate.calendarVisibility.isHidden($0) }.map { entry in
                    var entry = entry
                    if let key = entry.calendarSourceKey, let id = existingByKey[key] { entry.id = id }
                    return entry
                }
                // Track precisely the entries owned by this connection. Other
                // imports and manually entered recurring classes are preserved.
                let incomingKeys = Set(incoming.compactMap(\.calendarSourceKey))
                candidate.entries = oldEntries.filter { entry in
                    guard !candidate.calendarVisibility.isHidden(entry) else { return false }
                    guard let key = entry.calendarSourceKey else { return true }
                    // Restoring a hidden entry can put its last saved row back
                    // before it is managed again. Replace that same source once.
                    return !connection.managedEntryKeys.contains(key) && !incomingKeys.contains(key)
                } + incoming
                connection.managedEntryKeys = incomingKeys
                connection.weekStart = week.start
                connection.timeZoneID = candidate.timeZone.identifier
                connection.calendarNames = calendars
                    .filter { connection.calendarIDs.contains($0.id) }
                    .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
                    .map(\.title)
                if connection.includeWeekTitle { candidate.configuration.subtitle = week.label }
                candidate.connection = connection
                calendarFingerprint = Self.digest(Self.canonicalEntries(incoming, showLocations: true))
            }

            guard revision == generation else { return }
            let visibility = candidate.calendarVisibility
            candidate.entries.removeAll { visibility.isHidden($0) }
            candidate.configuration = Self.effectiveConfiguration(candidate.configuration, settings: settings,
                connection: candidate.connection, now: request.now, timeZone: candidate.timeZone)
            let fingerprint = Self.fingerprint(entries: candidate.entries,
                configuration: candidate.configuration, targetDisplayID: target)
            let reason: String
            if shouldFetch && differentWeek {
                reason = "이번 주 일정으로 배경화면을 교체했습니다."
            } else if shouldFetch {
                reason = "변경된 이번 주 일정을 배경화면에 반영했습니다."
            } else {
                reason = "배경화면의 표시 설정을 갱신했습니다."
            }

            if var receipt = candidate.receipt, receipt.wallpaperFingerprint == fingerprint,
               receipt.targetDisplayID == target {
                // New source keys or an identical-looking new week still need
                // persistence, but must not rewrite the desktop image or the
                // timestamp of the last successful native desktop application.
                receipt.calendarFingerprint = calendarFingerprint
                receipt.weekStart = candidate.connection?.weekStart
                candidate.receipt = receipt
                let metadataChanged = candidate.connection != context?.connection ||
                    candidate.entries != context?.entries || candidate.configuration != context?.configuration ||
                    candidate.receipt != context?.receipt || candidate.calendarVisibility != context?.calendarVisibility
                context = candidate
                if metadataChanged {
                    onStateChange?(AutomationUpdate(entries: candidate.entries,
                        configuration: candidate.configuration, connection: candidate.connection,
                        receipt: receipt, reason: "배경화면은 같아 캘린더 연결 정보만 갱신했습니다.",
                        calendarVisibility: candidate.calendarVisibility))
                }
                status = waitingStatus(candidate, differentWeek: differentWeek && !shouldFetch)
                return
            }

            let receipt = AutomationReceipt(wallpaperFingerprint: fingerprint,
                calendarFingerprint: calendarFingerprint, appliedAt: request.now,
                weekStart: candidate.connection?.weekStart,
                dayKey: Self.dayKey(now: request.now, timeZone: candidate.timeZone), targetDisplayID: target)
            let update = AutomationUpdate(entries: candidate.entries, configuration: candidate.configuration,
                connection: candidate.connection, receipt: receipt, reason: reason,
                calendarVisibility: candidate.calendarVisibility)
            // No state or receipt is advanced before the native apply succeeds.
            try apply(update)
            candidate.receipt = receipt
            if revision == generation { context = candidate }
            lastAppliedAt = request.now
            status = reason
            if differentWeek && !shouldFetch && !settings.refreshWeekly {
                status += " 이전 주 일정은 유지했습니다."
            }
        } catch {
            guard revision == generation else { return }
            if let calendarError = error as? CalendarImportError, case .permissionDenied = calendarError {
                needsCalendarReconnect = true
            }
            status = "자동 교체를 완료하지 못했습니다. \(error.localizedDescription) 기존 배경화면을 유지합니다."
        }
    }

    private func validateConnection(_ connection: CalendarConnection) throws -> [CalendarDescriptor] {
        guard provider.access == .authorized else { throw CalendarImportError.permissionDenied }
        guard !connection.calendarIDs.isEmpty else { throw CalendarImportError.noCalendarsSelected }
        let calendars = try provider.calendars()
        guard Set(calendars.map(\.id)).isSuperset(of: connection.calendarIDs) else {
            throw CalendarImportError.calendarsChanged
        }
        return calendars
    }

    private func idleStatus(_ context: AutomationContext) -> String {
        guard context.settings.hasAutomation else { return "자동 배경화면 교체가 꺼져 있습니다." }
        guard let target = context.settings.targetDisplayID, !target.isEmpty else {
            return "자동 적용할 디스플레이를 선택해주세요."
        }
        if context.settings.hasCalendarAutomation && context.connection == nil {
            return "캘린더에서 가져오기를 열고 자동 교체할 캘린더를 연결해주세요."
        }
        if !context.settings.hasCalendarAutomation && context.receipt == nil {
            return "배경화면을 한 번 적용하면 오늘 표시가 매일 자동으로 갱신됩니다."
        }
        return "자동 배경화면 교체를 준비했습니다. 앱을 실행한 동안 변경을 확인합니다."
    }

    private func waitingStatus(_ context: AutomationContext, differentWeek: Bool) -> String {
        if differentWeek && !context.settings.refreshWeekly {
            return "이전 주 일정은 유지합니다. 이번 주로 이동하려면 매주 자동 교체를 켜거나 캘린더를 다시 가져오세요."
        }
        if context.settings.refreshOnCalendarChange {
            return "이번 주 일정에 변경이 없습니다. 캘린더 변경을 기다립니다."
        }
        if context.settings.refreshWeekly {
            return "이번 주 배경화면을 유지합니다. 다음 월요일에 새 주를 가져옵니다."
        }
        return "오늘 표시가 최신입니다. 날짜가 바뀌면 자동으로 갱신합니다."
    }

    /// The renderer receives an explicit weekday and never consults the clock.
    /// A dated calendar snapshot from another week must not masquerade as today.
    static func effectiveConfiguration(_ configuration: WallpaperConfiguration,
        settings: AutomationSettings, connection: CalendarConnection?, now: Date,
        timeZone: TimeZone) -> WallpaperConfiguration {
        var result = configuration
        result.highlightedDay = nil
        result.weekdayDateLabels = nil
        let numberStyle = configuration.weekdayNumberStyle ?? (connection == nil ? .ordinal : .date)
        if numberStyle == .date, let connection {
            result.weekdayDateLabels = WeekdayHeaderDates.labels(weekStart: connection.weekStart, timeZoneID: connection.timeZoneID) ?? []
        }
        guard settings.showToday else { return result }
        let week = CalendarWeek(containing: now, timeZone: timeZone)
        if let connection,
           connection.weekStart != week.start || connection.timeZoneID != timeZone.identifier {
            return result
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        result.highlightedDay = (calendar.component(.weekday, from: now) + 5) % 7
        return result
    }

    static func dayKey(now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// Semantic render inputs, excluding transient IDs, source identity, order,
    /// and locations that are hidden by the chosen design settings.
    static func fingerprint(entries: [ScheduleEntry], configuration: WallpaperConfiguration,
                            targetDisplayID: String) -> String {
        struct Payload: Encodable {
            var version = 1
            var entries: [[String]]
            var configuration: WallpaperConfiguration
            var targetDisplayID: String
        }
        return digest(Payload(entries: canonicalEntries(entries, showLocations: configuration.showLocations),
            configuration: configuration, targetDisplayID: targetDisplayID))
    }

    private static func canonicalEntries(_ entries: [ScheduleEntry], showLocations: Bool) -> [[String]] {
        entries.filter { $0.validationError == nil }.map { entry in
            [String(entry.day), String(entry.startMinutes), String(entry.endMinutes),
             entry.name, showLocations ? entry.location : ""]
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // The payload contains only finite integers, booleans, strings and enum
        // raw values, so encoding cannot fail for a supported render input.
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
