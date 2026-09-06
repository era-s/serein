import AppKit
import SwiftUI

@MainActor
final class CalendarImportModel: ObservableObject {
    @Published private(set) var access: CalendarAccess
    @Published private(set) var calendars: [CalendarDescriptor] = []
    @Published var selectedCalendarIDs: Set<String> = [] { didSet { if oldValue != selectedCalendarIDs { invalidateResult() } } }
    @Published var selectedDate: Date { didSet { if oldValue != selectedDate { invalidateResult() } } }
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var result: CalendarImportResult?
    @Published private(set) var reviewEntries: [ScheduleEntry] = []
    @Published var selectedEntryIDs: Set<UUID> = [] { didSet { confirmed = false } }
    @Published var confirmed = false
    let isDemo: Bool
    private let provider: any CalendarProviding
    private let timeZone: TimeZone
    private var operation = UUID()

    init(provider: (any CalendarProviding)? = nil, date: Date = Date(), isDemo: Bool = false, timeZone: TimeZone = .current) {
        let resolvedProvider = provider ?? SystemCalendarService()
        self.provider = resolvedProvider
        self.selectedDate = date
        self.access = resolvedProvider.access
        self.isDemo = isDemo
        self.timeZone = timeZone
    }

    var week: CalendarWeek { CalendarWeek(containing: selectedDate, timeZone: timeZone) }
    /// A successfully read week with no timed entries can still establish a
    /// calendar connection. Deselecting fetched entries is a different action.
    var isEmptySnapshot: Bool { result != nil && reviewEntries.isEmpty }
    var canImport: Bool {
        guard !isLoading, result != nil, confirmed, access == .authorized,
              !selectedCalendarIDs.isEmpty else { return false }
        let selected = reviewEntries.filter { selectedEntryIDs.contains($0.id) }
        return isEmptySnapshot || (!selected.isEmpty && selected.allSatisfy { $0.validationError == nil })
    }

    func invalidateResult() {
        operation = UUID()
        isLoading = false
        result = nil
        reviewEntries = []
        selectedEntryIDs = []
        confirmed = false
        error = nil
    }

    func loadIfAuthorized() async {
        access = provider.access
        if access == .authorized {
            await refreshCalendars()
            if isDemo, !calendars.isEmpty {
                selectedCalendarIDs = Set(calendars.prefix(2).map(\.id))
                await fetchEvents()
            }
        }
    }

    func connect() async {
        guard !isLoading else { return }
        invalidateResult()
        let token = UUID()
        operation = token
        isLoading = true
        defer { if operation == token { isLoading = false } }
        do {
            let allowed = try await provider.requestAccess()
            guard operation == token else { return }
            access = provider.access
            guard allowed, access == .authorized else { throw CalendarImportError.permissionDenied }
            calendars = try provider.calendars()
            selectedCalendarIDs.formIntersection(Set(calendars.map(\.id)))
        } catch {
            guard operation == token else { return }
            access = provider.access
            self.error = error.localizedDescription
        }
    }

    func refreshCalendars() async {
        guard !isLoading else { return }
        invalidateResult()
        access = provider.access
        guard access == .authorized else { calendars = []; selectedCalendarIDs = []; return }
        do {
            calendars = try provider.calendars()
            selectedCalendarIDs.formIntersection(Set(calendars.map(\.id)))
        } catch { self.error = error.localizedDescription }
    }

    func fetchEvents() async {
        guard !isLoading else { return }
        invalidateResult()
        access = provider.access
        guard access == .authorized else { error = CalendarImportError.permissionDenied.localizedDescription; return }
        guard !selectedCalendarIDs.isEmpty else { error = CalendarImportError.noCalendarsSelected.localizedDescription; return }
        let ids = selectedCalendarIDs
        let selectedWeek = week
        let token = UUID()
        operation = token
        isLoading = true
        defer { if operation == token { isLoading = false } }
        do {
            let events = try await provider.events(calendarIDs: ids, week: selectedWeek)
            guard operation == token else { return }
            access = provider.access
            guard access == .authorized else { throw CalendarImportError.permissionDenied }
            let converted = CalendarEventConverter.convert(events, week: selectedWeek)
            result = converted
            reviewEntries = converted.entries
            selectedEntryIDs = Set(converted.entries.map(\.id))
        } catch {
            guard operation == token else { return }
            access = provider.access
            self.error = error.localizedDescription
        }
    }

    func updateEntry(_ entry: ScheduleEntry) {
        guard entry.validationError == nil else { error = entry.validationError; return }
        guard let index = reviewEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        reviewEntries[index] = entry
        confirmed = false
    }

    /// Check consent and source existence again at the moment a snapshot is used.
    func validateForImport() -> Bool {
        guard canImport else { return false }
        do {
            guard provider.access == .authorized else { throw CalendarImportError.permissionDenied }
            let available = Set(try provider.calendars().map(\.id))
            guard selectedCalendarIDs.isSubset(of: available) else { throw CalendarImportError.calendarsChanged }
            return true
        } catch {
            invalidateResult()
            access = provider.access
            self.error = error.localizedDescription
            return false
        }
    }

    func refreshAfterExternalChange() {
        guard !isDemo else { return }
        let currentAccess = provider.access
        if currentAccess != access {
            invalidateResult()
            access = currentAccess
            calendars = []
        }
        guard currentAccess == .authorized else { selectedCalendarIDs = []; return }
        do {
            let updated = try provider.calendars()
            if updated != calendars {
                invalidateResult()
                calendars = updated
                selectedCalendarIDs.formIntersection(Set(updated.map(\.id)))
            }
        } catch { invalidateResult(); self.error = error.localizedDescription }
    }

    func openAccountsSettings() {
        openSettings("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
    }
    func openPrivacySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }
    private func openSettings(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            error = "시스템 설정을 열지 못했습니다. 시스템 설정 앱에서 직접 이동해주세요."
            return
        }
    }
}

enum CalendarEntryMerger {
    static func merge(existing: [ScheduleEntry], incoming: [ScheduleEntry]) -> [ScheduleEntry] {
        var merged = existing
        for var entry in incoming {
            guard entry.validationError == nil else { continue }
            if let key = entry.calendarSourceKey,
               let index = merged.firstIndex(where: { $0.calendarSourceKey == key }) {
                entry.id = merged[index].id
                merged[index] = entry
            } else { merged.append(entry) }
        }
        return merged
    }
}
