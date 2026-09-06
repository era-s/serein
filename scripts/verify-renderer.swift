import AppKit
import Foundation
import ImageIO

/// Executable checks for Command Line Tools installations without XCTest.
@main
enum RendererVerification {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }

    private static func changedPixelBounds(_ first: Data, _ second: Data) -> CGRect? {
        guard let lhs = NSBitmapImageRep(data: first), let rhs = NSBitmapImageRep(data: second),
              lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
              lhs.bitsPerPixel == rhs.bitsPerPixel, lhs.bitsPerSample == 8,
              let left = lhs.bitmapData, let right = rhs.bitmapData else {
            fatalError("Unable to compare rendered pixel data")
        }
        let bytesPerPixel = lhs.bitsPerPixel / 8
        var minX = lhs.pixelsWide, minY = lhs.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                let leftOffset = y * lhs.bytesPerRow + x * bytesPerPixel
                let rightOffset = y * rhs.bytesPerRow + x * bytesPerPixel
                if (0..<bytesPerPixel).contains(where: { left[leftOffset + $0] != right[rightOffset + $0] }) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func main() throws {
        let size = CGSize(width: 756, height: 491)
        let original = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: .init(), size: size)
        let repeated = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: .init(), size: size)
        let reordered = ScheduleEntry.sample.reversed().map { entry in
            var copy = entry
            copy.id = UUID()
            return copy
        }
        let equivalent = try WallpaperRenderer.pngData(entries: reordered, configuration: .init(), size: size)
        expect(original == repeated, "Identical inputs produce identical PNG bytes")
        expect(original == equivalent, "Entry order and UUID changes do not affect the wallpaper")
        let tiedEvents = [
            ScheduleEntry(name: "Design lab", day: 0, startMinutes: 600, endMinutes: 780, location: "Room B", calendarSourceKey: "calendar-a"),
            ScheduleEntry(name: "Design lab", day: 0, startMinutes: 600, endMinutes: 780, location: "Room A", calendarSourceKey: "calendar-b"),
            ScheduleEntry(name: "Design lab", day: 0, startMinutes: 600, endMinutes: 780, location: "Room A", calendarSourceKey: "calendar-c")
        ]
        let permutedTies = tiedEvents.reversed().map { entry in
            var copy = entry
            copy.id = UUID()
            copy.calendarSourceKey = "changed-source-\(entry.id)"
            return copy
        }
        let tiedPNG = try WallpaperRenderer.pngData(entries: tiedEvents, configuration: .init(), size: size)
        let permutedPNG = try WallpaperRenderer.pngData(entries: permutedTies, configuration: .init(), size: size)
        expect(tiedPNG == permutedPNG, "Same-time, same-title overlaps and exact duplicates ignore order, UUIDs, and calendar source keys")

        var todayConfiguration = WallpaperConfiguration()
        todayConfiguration.highlightedDay = 2 // Wednesday is an explicit, stable render input.
        let wednesday = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
        let repeatedWednesday = try WallpaperRenderer.pngData(entries: reordered, configuration: todayConfiguration, size: size)
        expect(wednesday == repeatedWednesday, "Today's indicator is deterministic and independent of UUID or entry order")
        expect(wednesday != original, "Enabling today's indicator changes the wallpaper")
        guard let changed = changedPixelBounds(original, wednesday) else { fatalError("Today's indicator changed no pixels") }
        // At the 756px preview size, Wednesday occupies x=324.5...450.
        // The difference must stay inside that column, beneath the editorial header.
        expect(changed.minX >= 324 && changed.maxX <= 451 && changed.minY >= 175,
               "Wednesday's indicator affects only the Wednesday timetable column")
        expect(changed.height > 200, "Today's border spans the timetable rather than only changing a label")
        todayConfiguration.highlightedDay = 3
        let thursday = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
        expect(thursday != wednesday && thursday != original, "A different highlighted day produces a different wallpaper")
        todayConfiguration.highlightedDay = nil
        let disabled = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
        expect(disabled == original, "Disabling today's indicator restores the original wallpaper exactly")
        for invalidDay in [-1, 7, Int.max] {
            todayConfiguration.highlightedDay = invalidDay
            let invalidHighlight = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
            expect(invalidHighlight == original, "Out-of-range highlighted day \(invalidDay) is safely ignored")
        }
        for weekendDay in [5, 6] {
            todayConfiguration.highlightedDay = weekendDay
            todayConfiguration.showWeekends = false
            let automaticWeekend = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
            todayConfiguration.showWeekends = true
            let explicitWeekend = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
            expect(automaticWeekend == explicitWeekend, "Highlighting \(ScheduleEntry.dayLabels[weekendDay]) includes the weekend without weekend events")
            todayConfiguration.highlightedDay = nil
            let unmarkedWeekend = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: todayConfiguration, size: size)
            expect(automaticWeekend != unmarkedWeekend, "\(ScheduleEntry.dayLabels[weekendDay]) receives a visible today indicator")
        }

        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let bitmap = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("Renderer did not produce a decodable PNG")
        }
        expect(bitmap.width == 756 && bitmap.height == 491, "PNG has exactly the requested pixel dimensions")
        var exportConfiguration = WallpaperConfiguration()
        exportConfiguration.resolution = .air13
        let exported = try WallpaperRenderer.render(entries: [], configuration: exportConfiguration)
        var proposedRect = CGRect(origin: .zero, size: exported.size)
        let exportBitmap = exported.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        expect(exportBitmap?.width == 2560 && exportBitmap?.height == 1664, "Export defaults to the selected MacBook resolution")

        let night = [ScheduleEntry(name: "밤의 타이포그래피", day: 6, startMinutes: 1410, endMinutes: 1440)]
        var nightConfiguration = WallpaperConfiguration()
        nightConfiguration.showWeekends = true
        nightConfiguration.endHour = 24
        let automaticNight = try WallpaperRenderer.pngData(entries: night, configuration: .init(), size: size)
        let explicitNight = try WallpaperRenderer.pngData(entries: night, configuration: nightConfiguration, size: size)
        expect(automaticNight == explicitNight, "Sunday and 24:00 automatically expand the grid")

        let morning = [ScheduleEntry(name: "First light", day: 0, startMinutes: 0, endMinutes: 30)]
        var morningConfiguration = WallpaperConfiguration()
        morningConfiguration.startHour = 0
        let automaticMorning = try WallpaperRenderer.pngData(entries: morning, configuration: .init(), size: size)
        let explicitMorning = try WallpaperRenderer.pngData(entries: morning, configuration: morningConfiguration, size: size)
        expect(automaticMorning == explicitMorning, "00:00 automatically expands the grid")

        let overlapping = [
            ScheduleEntry(name: "A", day: 0, startMinutes: 600, endMinutes: 720),
            ScheduleEntry(name: "B", day: 0, startMinutes: 630, endMinutes: 660),
            ScheduleEntry(name: "C", day: 0, startMinutes: 660, endMinutes: 750),
            ScheduleEntry(name: "D", day: 0, startMinutes: 780, endMinutes: 810)
        ]
        let positions = WallpaperRenderer.positioned(overlapping)
        expect(positions.count == overlapping.count, "Overlap layout retains every class")
        let concurrentClassesHaveSeparateLanes = positions.allSatisfy { first in
            positions.allSatisfy { second in !first.entry.overlaps(second.entry) || first.lane != second.lane }
        }
        expect(concurrentClassesHaveSeparateLanes, "Concurrent classes never share a lane")
        expect(positions.filter { $0.entry.name != "D" }.allSatisfy { $0.laneCount == 2 }, "Connected overlap cluster has consistent column widths")
        expect(positions.first(where: { $0.entry.name == "D" })?.laneCount == 1, "Isolated classes recover their full column width")

        var themes: [Data] = []
        for theme in WallpaperTheme.allCases {
            var configuration = WallpaperConfiguration()
            configuration.theme = theme
            themes.append(try WallpaperRenderer.pngData(entries: [], configuration: configuration, size: size))
        }
        expect(Set(themes).count == 3 && themes.allSatisfy { $0.count > 1000 }, "All three themes render distinct, nonempty wallpapers")

        for invalidSize in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 600), CGSize(width: 1_000_000, height: 1_000_000)] {
            do {
                _ = try WallpaperRenderer.pngData(entries: [], configuration: .init(), size: invalidSize)
                fatalError("Invalid dimensions were accepted")
            } catch WallpaperRenderer.RenderError.invalidSize {
                expect(true, "Invalid dimensions are rejected before bitmap allocation")
            }
        }

        // Optional review images: ./scripts/verify-renderer.sh /absolute/output/directory
        if CommandLine.arguments.count > 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for theme in WallpaperTheme.allCases {
                var configuration = WallpaperConfiguration()
                configuration.theme = theme
                let png = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: configuration, size: CGSize(width: 1512, height: 982))
                try png.write(to: directory.appendingPathComponent("\(theme.rawValue).png"))
            }
            let stressEntries = [
                ScheduleEntry(name: "시각 디자인의 역사와 현대 타이포그래피", day: 0, startMinutes: 570, endMinutes: 690, location: "디자인관 302호"),
                ScheduleEntry(name: "Creative Computing and Critical Design", day: 0, startMinutes: 600, endMinutes: 720, location: "Design Lab 301"),
                ScheduleEntry(name: "30분 수업", day: 2, startMinutes: 810, endMinutes: 840),
                ScheduleEntry(name: "주말 디자인 스튜디오", day: 6, startMinutes: 660, endMinutes: 780, location: "공학관 701호")
            ]
            let stress = try WallpaperRenderer.pngData(entries: stressEntries, configuration: .init(), size: CGSize(width: 1512, height: 982))
            try stress.write(to: directory.appendingPathComponent("overlap-and-short-classes.png"))
            var today = WallpaperConfiguration()
            today.highlightedDay = 2
            let todayPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: today)
            try todayPNG.write(to: directory.appendingPathComponent("today-indicator-demo.png"))
            print("Review images saved to \(directory.path)")
        }
        print("Renderer verification completed: \(checks) checks passed.")
    }
}
