import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        while true {
            do { try store?.flushPendingSave(); return .terminateNow }
            catch {
                let alert = NSAlert()
                alert.messageText = "작업을 저장하지 못했습니다."
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "다시 시도")
                alert.addButton(withTitle: "종료 취소")
                if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            }
        }
    }

    func saveBeforeClosingWindow() {
        do { try store?.flushPendingSave() }
        catch {
            let alert = NSAlert()
            alert.messageText = "아직 저장하지 못한 변경이 있습니다."
            alert.informativeText = "변경 내용은 실행 중인 앱에 남아 있습니다. 창을 다시 열어 저장을 재시도해주세요.\n" + error.localizedDescription
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct WallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-demo"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for theme in WallpaperTheme.allCases {
                    var config = WallpaperConfiguration()
                    config.theme = theme
                    try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: config)
                        .write(to: directory.appendingPathComponent("serein-\(theme.rawValue).png"))
                }
                print("Rendered three deterministic wallpapers at \(directory.path)")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Render failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Serein — Timetable Wallpaper", id: "studio") {
            StudioView().environmentObject(store)
                .frame(minWidth: 1080, minHeight: 740)
                .preferredColorScheme(.light)
                .background(StudioWindowLifecycle(onVisibility: store.setStudioVisible, onClose: delegate.saveBeforeClosingWindow))
                .onAppear { delegate.store = store; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1320, height: 870)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("시간표 이미지 가져오기…", action: store.chooseImage).keyboardShortcut("o")
                Button("캘린더에서 가져오기…") { store.showCalendarImport = true }.keyboardShortcut("k")
                Button("자동화 설정…") { store.showAutomation = true }.keyboardShortcut(",")
                Button("PNG 저장…", action: store.exportPNG).keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra("Serein", systemImage: "calendar.badge.clock") {
            AutomationMenu(store: store)
        }
    }
}

private struct AutomationMenu: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Serein · 나의 주간 배경화면")
        Text(store.automation.status)
        Divider()
        Button("Serein 열기") { showStudio() }
        Button("자동화 설정…") { showStudio(); store.showAutomation = true }
        Button("지금 일정 확인", action: store.checkNow)
            .disabled(!store.automationSettings.hasAutomation || store.automation.isChecking)
        Divider()
        Toggle("일정 변경 시 교체", isOn: $store.automationSettings.refreshOnCalendarChange)
            .disabled(store.calendarConnection == nil)
        Toggle("매주 자동 교체", isOn: $store.automationSettings.refreshWeekly)
            .disabled(store.calendarConnection == nil)
        Toggle("오늘 표시", isOn: $store.automationSettings.showToday)
        Divider()
        Button("Serein 종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func showStudio() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }
}
