import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import EventKit
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    @Published var entries: [ScheduleEntry] = ScheduleEntry.sample { didSet { changed() } }
    @Published var configuration = WallpaperConfiguration() { didSet { changed() } }
    @Published var preview: NSImage?
    @Published var isRecognizing = false
    @Published var isExporting = false
    @Published var importResult: OCRImportResult?
    @Published var importImage: NSImage?
    @Published var message: String?
    @Published var error: String?
    @Published var showCalendarImport = false
    @Published var showAutomation = false
    @Published var showHiddenCalendarEntries = false
    @Published var automationSettings = AutomationSettings() { didSet { automationOptionsChanged(oldValue) } }
    @Published private(set) var calendarConnection: CalendarConnection?
    @Published private(set) var displays: [WallpaperDisplay] = []
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var automationReceipt: AutomationReceipt?
    @Published private(set) var calendarVisibility = CalendarVisibility()
    let isDemo = CommandLine.arguments.contains("--calendar-demo") || CommandLine.arguments.contains("--automation-demo")
    var now: Date { isDemo ? DemoCalendarProvider.anchor.addingTimeInterval(2 * 86400 + 12 * 3600) : Date() }
    private var observers = Set<AnyCancellable>()
    private var checkTask: Task<Void, Never>?
    private var scheduledTrigger: AutomationTrigger?
    private var committingAutomation = false
    private lazy var calendarProvider: any CalendarProviding = {
        if isDemo { return DemoCalendarProvider() }
        return SystemCalendarService()
    }()
    lazy var calendarRecovery = CalendarAccessRecovery(provider: calendarProvider)
    lazy var automation: WallpaperAutomation = {
        return WallpaperAutomation(provider: calendarProvider, apply: { [weak self] update in
            guard let self else { return }
            if self.isDemo {
                try WallpaperRenderer.pngData(entries: update.entries, configuration: update.configuration)
                    .write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("serein-automation-demo.png"), options: .atomic)
            } else {
                try WallpaperDesktopService.apply(entries: update.entries, configuration: update.configuration,
                                                  displayID: update.receipt.targetDisplayID)
            }
            self.acceptAutomation(update)
        }, onStateChange: { [weak self] update in self?.acceptAutomation(update) })
    }()
    private var renderTask: Task<Void, Never>?
    private var loading = true
    private var autosaveEnabled = true

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Serein", isDirectory: true)
    }

    init() {
        var migratedWallpaperScope = false
        if isDemo {
            autosaveEnabled = false
            if CommandLine.arguments.contains("--automation-demo") {
                let week = CalendarWeek(containing: now, timeZone: TimeZone(identifier: "Asia/Seoul")!)
                calendarConnection = CalendarConnection(calendarIDs: ["demo-study", "demo-personal"],
                    calendarNames: ["Google · Study", "iCloud · Personal"], weekStart: week.start,
                    timeZoneID: week.timeZone.identifier, managedEntryKeys: [], includeWeekTitle: true)
                entries = []
                showAutomation = true
            } else { showCalendarImport = true }
            loading = false
            startAutomation()
            refreshPreview()
            return
        }
        let url = Self.supportDirectory.appendingPathComponent("studio.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                var saved = try JSONDecoder().decode(SavedStudio.self, from: Data(contentsOf: url))
                guard saved.isValid else { throw CocoaError(.fileReadCorruptFile) }
                migratedWallpaperScope = saved.migrateWallpaperScope()
                entries = saved.entries
                configuration = saved.configuration
                configuration.highlightedDay = nil
                configuration.weekdayDateLabels = nil
                automationSettings = saved.automation ?? AutomationSettings()
                calendarConnection = saved.connection
                automationReceipt = saved.receipt
                calendarVisibility = saved.calendarVisibility ?? CalendarVisibility()
                entries.removeAll { calendarVisibility.isHidden($0) }
            } catch {
                let recovery = Self.supportDirectory.appendingPathComponent("studio-recovery-\(UUID().uuidString).json")
                do {
                    try FileManager.default.copyItem(at: url, to: recovery)
                    self.error = "저장한 작업을 불러오지 못해 예시를 열었습니다. 원본은 \(recovery.lastPathComponent)에 별도로 보관했습니다."
                } catch {
                    autosaveEnabled = false
                    self.error = "저장한 작업을 불러오지 못했습니다. 원본을 보호하기 위해 자동 저장을 중지했습니다. PNG 저장은 사용할 수 있습니다. \(error.localizedDescription)"
                }
            }
        }
        loading = false
        startAutomation(initialTrigger: migratedWallpaperScope && automationSettings.hasAutomation ? .settingsChanged : .launch)
        if migratedWallpaperScope {
            committingAutomation = true
            changed()
            committingAutomation = false
        }
        refreshPreview()
    }

    private func changed() {
        guard !loading else { return }
        if autosaveEnabled { do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SavedStudio(entries: entries, configuration: configuration,
                automation: automationSettings, connection: calendarConnection, receipt: automationReceipt,
                calendarVisibility: calendarVisibility))
                .write(to: Self.supportDirectory.appendingPathComponent("studio.json"), options: .atomic)
        } catch { self.error = "작업을 저장하지 못했습니다. \(error.localizedDescription)" } }
        if !committingAutomation {
            scheduledTrigger = nil
            automation.configure(automationContext)
            scheduleCheck(.settingsChanged, delay: 0.5)
        }
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.refreshPreview()
        }
    }

    func refreshPreview() {
        let size = configuration.resolution.size
        do {
            preview = try WallpaperRenderer.render(entries: entries, configuration: effectiveConfiguration,
                size: CGSize(width: 1600, height: 1600 * size.height / size.width))
        } catch { self.error = "미리보기를 만들지 못했습니다. \(error.localizedDescription)" }
    }

    var sortedEntries: [ScheduleEntry] {
        entries.sorted { ($0.day, $0.startMinutes, $0.name) < ($1.day, $1.startMinutes, $1.name) }
    }
    var weeklyHours: String {
        let hours = Double(entries.reduce(0) { $0 + $1.endMinutes - $1.startMinutes }) / 60
        return hours.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(hours)) : String(format: "%.1f", hours)
    }
    func save(_ entry: ScheduleEntry) {
        guard entry.validationError == nil else { error = entry.validationError; return }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else { entries.append(entry) }
    }
    func remove(_ id: UUID, scope: CalendarExclusionScope = .event) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        guard entry.calendarSourceKey != nil else {
            entries.removeAll { $0.id == id }
            return
        }
        // Persist the exclusion and removed rows as one edit before scheduling
        // another query. configure() also invalidates a fetch already in flight.
        loading = true
        calendarVisibility.hide(entry, scope: scope)
        entries.removeAll { calendarVisibility.isHidden($0) }
        loading = false
        changed()
        refreshAfterVisibilityEdit()
        message = scope == .event
            ? "배경화면에서 숨겼습니다. 이후 반복 일정도 제외하며, 숨긴 일정에서 되돌릴 수 있습니다."
            : "이번 회차를 숨겼습니다. 다음 반복 일정은 계속 표시합니다."
    }

    func clearEntries() {
        loading = true
        for entry in entries where entry.calendarSourceKey != nil { calendarVisibility.hide(entry) }
        entries = []
        loading = false
        changed()
        refreshAfterVisibilityEdit()
        message = "시간표를 비웠습니다. 캘린더 일정의 숨김은 동기화 후에도 유지합니다."
    }

    func restoreHiddenCalendarEntry(_ id: UUID) {
        guard calendarVisibility.restore(id) != nil else { return }
        changed()
        if automationSettings.hasCalendarAutomation {
            scheduleCheck(.manual, delay: 0)
            message = "숨김을 해제했습니다. 현재 연결한 캘린더의 최신 일정을 확인합니다."
        } else {
            message = "숨김을 해제했습니다. 캘린더에서 다시 가져오면 표시됩니다."
        }
    }

    private func refreshAfterVisibilityEdit() {
        // Resolve legacy source-only rows now, including weekly-only setups,
        // so a future recurrence can inherit the same series exclusion.
        guard automationSettings.hasCalendarAutomation, let connection = calendarConnection else { return }
        if automationSettings.refreshWeekly || connection.weekStart == CalendarWeek(containing: now).start {
            scheduleCheck(.manual, delay: 0)
        }
    }

    func importCalendarEntries(_ incoming: [ScheduleEntry], replace: Bool, subtitle: String?, connection: CalendarConnection,
                               excluded: [ScheduleEntry] = []) {
        guard (incoming + excluded).allSatisfy({ $0.validationError == nil }) else {
            error = "가져올 일정의 이름과 시간을 확인해주세요."
            return
        }
        loading = true
        for entry in excluded { calendarVisibility.hide(entry) }
        calendarVisibility.reconcile(with: incoming)
        let visible = incoming.filter { !calendarVisibility.isHidden($0) }
        entries = replace ? visible : CalendarEntryMerger.merge(existing: entries, incoming: visible)
        entries.removeAll { calendarVisibility.isHidden($0) }
        calendarConnection = connection
        if connection.weekStart != CalendarWeek(containing: now).start {
            automationSettings.refreshOnCalendarChange = false
            automationSettings.refreshWeekly = false
        }
        if let subtitle { configuration.subtitle = subtitle }
        loading = false
        changed()
        showCalendarImport = false
        message = incoming.isEmpty ? "일정이 없는 주간 시간표로 캘린더를 연결했습니다. 자동화에서 주간 교체를 켤 수 있습니다."
            : "캘린더 일정 \(visible.count)개를 반영했습니다." + (visible.count < incoming.count ? " 숨긴 일정은 제외했습니다." : "")
    }

    func chooseImage() {
        guard !isRecognizing else { return }
        let panel = NSOpenPanel()
        panel.title = "시간표 이미지 가져오기"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.recognize(url: url) }
        }
    }
    func recognize(url: URL) {
        guard !isRecognizing else { return }
        isRecognizing = true
        importImage = NSImage(contentsOf: url)
        Task {
            defer { isRecognizing = false }
            do { importResult = try await TimetableOCR.recognize(url: url) }
            catch { self.error = "이미지를 인식하지 못했습니다. \(error.localizedDescription)" }
        }
    }

    func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "serein-\(configuration.theme.rawValue)-\(Int(configuration.resolution.size.width)).png"
        panel.title = "배경화면 PNG 저장"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.isExporting = true
                defer { self.isExporting = false }
                do {
                    let data = try WallpaperRenderer.pngData(entries: self.entries, configuration: self.effectiveConfiguration)
                    try data.write(to: url, options: .atomic)
                    self.message = "\(self.configuration.resolution.dimensions) PNG를 저장했습니다."
                } catch { self.error = "PNG 저장에 실패했습니다. \(error.localizedDescription)" }
            }
        }
    }

    func applyWallpaper() {
        let target = automationSettings.targetDisplayID ?? WallpaperDisplay.allSpacesID
        isExporting = true
        defer { isExporting = false }
        do {
            let config = effectiveConfiguration
            if isDemo {
                try WallpaperRenderer.pngData(entries: entries, configuration: config)
                    .write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("serein-automation-demo.png"), options: .atomic)
            } else {
                try WallpaperDesktopService.apply(entries: entries, configuration: config, displayID: target)
            }
            loading = true
            automationSettings.targetDisplayID = target
            automationSettings.targetDisplayName = displays.first { $0.id == target }?.name
            automationReceipt = AutomationReceipt(
                wallpaperFingerprint: WallpaperAutomation.fingerprint(entries: entries, configuration: config, targetDisplayID: target),
                calendarFingerprint: nil, appliedAt: now, weekStart: calendarConnection?.weekStart,
                dayKey: WallpaperAutomation.dayKey(now: now, timeZone: .current), targetDisplayID: target)
            loading = false
            changed()
            message = isDemo ? "예시 PNG를 만들었습니다. 실제 배경화면은 변경하지 않습니다."
                : target == WallpaperDisplay.allSpacesID
                    ? "모든 데스크탑과 디스플레이의 배경화면을 설정했습니다."
                    : "선택한 디스플레이의 현재 데스크탑 배경화면을 설정했습니다."
        } catch { self.error = "배경화면을 설정하지 못했습니다. \(error.localizedDescription)" }
    }

    var effectiveConfiguration: WallpaperConfiguration {
        WallpaperAutomation.effectiveConfiguration(configuration, settings: automationSettings,
            connection: calendarConnection, now: now, timeZone: .current)
    }
    var weekdayNumberStyle: WeekdayNumberStyle {
        configuration.weekdayNumberStyle ?? (calendarConnection == nil ? .ordinal : .date)
    }
    private var automationContext: AutomationContext {
        AutomationContext(entries: entries, configuration: configuration, settings: automationSettings,
                          connection: calendarConnection, receipt: automationReceipt, calendarVisibility: calendarVisibility)
    }
    private func automationOptionsChanged(_ old: AutomationSettings) {
        guard !loading else { return }
        if automationSettings.hasAutomation && automationSettings.targetDisplayID == nil {
            loading = true
            automationSettings.targetDisplayID = WallpaperDisplay.allSpacesID
            automationSettings.targetDisplayName = WallpaperDisplay.allSpaces.name
            loading = false
        }
        changed()
        let enabled = (!old.refreshWeekly && automationSettings.refreshWeekly)
            || (!old.refreshOnCalendarChange && automationSettings.refreshOnCalendarChange)
        scheduleCheck(enabled ? .enabled : .settingsChanged, delay: 0.2)
    }
    private func acceptAutomation(_ update: AutomationUpdate) {
        loading = true
        entries = update.entries
        calendarConnection = update.connection
        configuration = update.configuration
        configuration.highlightedDay = nil
        configuration.weekdayDateLabels = nil
        automationReceipt = update.receipt
        calendarVisibility = update.calendarVisibility
        loading = false
        committingAutomation = true
        changed()
        committingAutomation = false
    }
    func refreshDisplays() {
        let individualDisplays = isDemo ? [WallpaperDisplay(id: "demo-display", name: "예시 MacBook Pro")]
                                        : WallpaperDesktopService.displays
        displays = [.allSpaces] + individualDisplays
    }
    func selectDisplay(_ id: String) {
        var settings = automationSettings
        let target = id.isEmpty ? WallpaperDisplay.allSpacesID : id
        settings.targetDisplayID = target
        settings.targetDisplayName = displays.first { $0.id == target }?.name
        automationSettings = settings
    }
    func checkNow() { scheduleCheck(.manual, delay: 0) }
    func refreshCalendarAccess() { calendarRecovery.refreshStatus() }

    /// Permission is requested only from the user's explicit reconnect action.
    /// Never replace a newly selected source with the connection shown at the
    /// start of a permission dialog, or change the user's automation switches.
    func reconnectCalendar() {
        guard !calendarRecovery.isConnecting else { return }
        let selectedConnection = calendarConnection
        Task { [weak self] in
            guard let self else { return }
            let authorized = await self.calendarRecovery.reconnect()
            guard authorized, !Task.isCancelled else { return }
            guard self.calendarConnection == selectedConnection else {
                self.message = "권한 연결을 확인했습니다. 새로 선택한 캘린더 설정을 유지합니다."
                return
            }
            self.scheduledTrigger = nil
            self.automation.configure(self.automationContext)
            self.scheduleCheck(.manual, delay: 0)
            self.message = "캘린더 권한 연결을 확인했습니다. 기존 자동화 설정으로 다시 확인합니다."
        }
    }
    private func scheduleCheck(_ trigger: AutomationTrigger, delay: Double) {
        checkTask?.cancel()
        // Explicit enable/scope changes must survive timer events during debounce.
        let selectedTrigger: AutomationTrigger
        if scheduledTrigger == .enabled || trigger == .enabled { selectedTrigger = .enabled }
        else if scheduledTrigger == .manual || trigger == .manual { selectedTrigger = .manual }
        else if scheduledTrigger == .settingsChanged { selectedTrigger = .settingsChanged }
        else { selectedTrigger = trigger }
        scheduledTrigger = selectedTrigger
        checkTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.scheduledTrigger = nil
            await self.automation.check(trigger: selectedTrigger, now: self.now)
            self.refreshCalendarAccess()
            self.refreshPreview()
        }
    }
    private func startAutomation(initialTrigger: AutomationTrigger = .launch) {
        refreshDisplays()
        refreshLoginStatus()
        refreshCalendarAccess()
        automation.configure(automationContext)
        automation.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        calendarRecovery.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.scheduleCheck(.clock, delay: 0)
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.scheduleCheck(.calendarChanged, delay: 1)
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.automation.configure(self.automationContext)
                self.scheduleCheck(.wake, delay: 0.3)
            }.store(in: &observers)
        for name in [NSApplication.didBecomeActiveNotification, NSNotification.Name.NSCalendarDayChanged] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshLoginStatus()
                self?.refreshCalendarAccess()
                self?.scheduleCheck(.wake, delay: 0.3)
            }.store(in: &observers)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.scheduleCheck(.wake, delay: 1)
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshDisplays()
            self?.scheduleCheck(.wake, delay: 0.5)
        }.store(in: &observers)
        scheduleCheck(initialTrigger, delay: 0.5)
    }
    func refreshLoginStatus() {
        guard !isDemo else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLoginEnabled(_ enabled: Bool) {
        guard !isDemo else { loginEnabled = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch { self.error = "로그인 시 실행 설정을 변경하지 못했습니다. 앱을 응용 프로그램 폴더에 옮겨 다시 시도해주세요. \(error.localizedDescription)" }
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
