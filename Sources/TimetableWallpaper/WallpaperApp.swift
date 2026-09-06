import AppKit
import SwiftUI

@main
struct WallpaperApp: App {
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
                Button("PNG 저장…", action: store.exportPNG).keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
