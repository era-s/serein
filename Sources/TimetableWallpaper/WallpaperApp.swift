import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
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
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }
}
