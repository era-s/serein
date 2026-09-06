import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    private var renderTask: Task<Void, Never>?
    private var loading = true
    private var autosaveEnabled = true

    private struct SavedState: Codable {
        var version = 1
        var entries: [ScheduleEntry]
        var configuration: WallpaperConfiguration
    }
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Serein", isDirectory: true)
    }

    init() {
        if CommandLine.arguments.contains("--calendar-demo") {
            // The preview fixture never reads or overwrites the user's saved studio.
            autosaveEnabled = false
            loading = false
            showCalendarImport = true
            refreshPreview()
            return
        }
        let url = Self.supportDirectory.appendingPathComponent("studio.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
                guard saved.version == 1, saved.entries.allSatisfy({ $0.validationError == nil }),
                      Set(saved.entries.map(\.id)).count == saved.entries.count,
                      (0...23).contains(saved.configuration.startHour),
                      (1...24).contains(saved.configuration.endHour),
                      saved.configuration.startHour < saved.configuration.endHour else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                entries = saved.entries
                configuration = saved.configuration
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
        refreshPreview()
    }

    private func changed() {
        guard !loading else { return }
        if autosaveEnabled { do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SavedState(entries: entries, configuration: configuration))
                .write(to: Self.supportDirectory.appendingPathComponent("studio.json"), options: .atomic)
        } catch { self.error = "작업을 저장하지 못했습니다. \(error.localizedDescription)" } }
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
            preview = try WallpaperRenderer.render(entries: entries, configuration: configuration,
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
    func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    func importCalendarEntries(_ incoming: [ScheduleEntry], replace: Bool, subtitle: String?) {
        guard !incoming.isEmpty, incoming.allSatisfy({ $0.validationError == nil }) else {
            error = "가져올 일정의 이름과 시간을 확인해주세요."
            return
        }
        entries = replace ? incoming : CalendarEntryMerger.merge(existing: entries, incoming: incoming)
        if let subtitle { configuration.subtitle = subtitle }
        showCalendarImport = false
        message = "캘린더 일정 \(incoming.count)개를 반영했습니다."
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
                    let data = try WallpaperRenderer.pngData(entries: self.entries, configuration: self.configuration)
                    try data.write(to: url, options: .atomic)
                    self.message = "\(self.configuration.resolution.dimensions) PNG를 저장했습니다."
                } catch { self.error = "PNG 저장에 실패했습니다. \(error.localizedDescription)" }
            }
        }
    }

    func applyWallpaper() {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
            error = "배경화면을 적용할 디스플레이를 찾을 수 없습니다."
            return
        }
        isExporting = true
        defer { isExporting = false }
        do {
            let directory = Self.supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("serein-\(UUID().uuidString).png")
            // Keep prior files: another display or Space may still reference them.
            try WallpaperRenderer.pngData(entries: entries, configuration: configuration).write(to: url, options: .atomic)
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true
            ])
            message = "현재 디스플레이의 배경화면을 설정했습니다."
        } catch { self.error = "배경화면을 설정하지 못했습니다. \(error.localizedDescription)" }
    }
}
