import AppKit

/// Documentation assets use fictional fixtures and the production renderer.
/// No AppStore, EventKit, saved work or system wallpaper APIs are initialized.
@main
enum RenderGallery {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var base = WallpaperConfiguration()
        base.resolution = .desktop4K
        base.subtitle = "2026.09.07 — 2026.09.13"
        base.weekdayNumberStyle = .date
        base.weekdayDateLabels = ["07", "08", "09", "10", "11", "12", "13"]
        base.highlightedDay = 2
        for theme in WallpaperTheme.allCases {
            var config = base
            config.theme = theme
            try save(theme.rawValue, entries: ScheduleEntry.sample, configuration: config, output: output)
        }
        var weekend = base
        weekend.theme = .moss
        weekend.showWeekends = true
        weekend.highlightedDay = 5
        weekend.title = "A little structure.\nA lot of possibility."
        let weekendEntries = ScheduleEntry.sample + [
            ScheduleEntry(name: "Photo walk", day: 5, startMinutes: 600, endMinutes: 720, location: "Take the scenic route."),
            ScheduleEntry(name: "Reset", day: 6, startMinutes: 960, endMinutes: 1020, location: "Make space for next week.")
        ]
        try save("weekend", entries: weekendEntries, configuration: weekend, output: output)
        var quiet = base
        quiet.theme = .midnight
        quiet.title = "Less noise.\nMore space."
        quiet.weekdayNumberStyle = .hidden
        quiet.highlightedDay = nil
        quiet.showLocations = false
        try save("quiet", entries: [
            ScheduleEntry(name: "Deep work", day: 0, startMinutes: 600, endMinutes: 720),
            ScheduleEntry(name: "Make something", day: 2, startMinutes: 780, endMinutes: 900),
            ScheduleEntry(name: "Read & reflect", day: 4, startMinutes: 900, endMinutes: 990)
        ], configuration: quiet, output: output)
        var overlap = base
        overlap.title = "Find your\nown rhythm."
        overlap.weekdayNumberStyle = .ordinal
        overlap.weekdayDateLabels = nil
        overlap.highlightedDay = 1
        try save("overlap", entries: [
            ScheduleEntry(name: "디자인 스튜디오", day: 0, startMinutes: 600, endMinutes: 720, location: "Studio A"),
            ScheduleEntry(name: "Creative Coding", day: 1, startMinutes: 660, endMinutes: 810, location: "Lab 01"),
            ScheduleEntry(name: "Project critique", day: 1, startMinutes: 720, endMinutes: 840, location: "Studio B"),
            ScheduleEntry(name: "타이포그래피", day: 2, startMinutes: 600, endMinutes: 720, location: "Studio A"),
            ScheduleEntry(name: "독서와 기록", day: 3, startMinutes: 840, endMinutes: 930, location: "A quiet afternoon"),
            ScheduleEntry(name: "Open Studio", day: 4, startMinutes: 780, endMinutes: 960, location: "Make something good.")
        ], configuration: overlap, output: output)
    }

    private static func save(_ name: String, entries: [ScheduleEntry], configuration: WallpaperConfiguration, output: URL) throws {
        let png = try WallpaperRenderer.pngData(entries: entries, configuration: configuration)
        guard let bitmap = NSBitmapImageRep(data: png), bitmap.pixelsWide == 3840, bitmap.pixelsHigh == 2160,
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try jpeg.write(to: output.appendingPathComponent("\(name).jpg"), options: .atomic)
        print("\(name).jpg · \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) · \(jpeg.count) bytes")
    }
}
