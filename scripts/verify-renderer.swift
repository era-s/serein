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

    private static func changedPixelBounds(_ first: Data, _ second: Data, within region: CGRect? = nil) -> CGRect? {
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
                if let region, !region.contains(CGPoint(x: x, y: y)) { continue }
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

    private static let dateLabels = ["07", "08", "09", "10", "11", "12", "13"]

    private static func verifyWeekdayNumbers(original: Data, size: CGSize) throws {
        var ordinal = WallpaperConfiguration()
        ordinal.weekdayNumberStyle = .ordinal
        let ordinalPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: ordinal, size: size)
        expect(ordinalPNG == original, "Explicit ordinal labels retain the old default wallpaper exactly")
        ordinal.weekdayDateLabels = dateLabels
        let ordinalWithDates = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: ordinal, size: size)
        expect(ordinalPNG == ordinalWithDates, "An explicit ordinal preference ignores supplied calendar dates")

        var dates = WallpaperConfiguration()
        dates.weekdayNumberStyle = .date
        dates.weekdayDateLabels = dateLabels
        let datesPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: dates, size: size)
        let repeated = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: dates, size: size)
        expect(datesPNG == repeated, "Explicit weekday dates produce identical PNG bytes on repeat rendering")
        var automatic = dates
        automatic.weekdayNumberStyle = nil
        let automaticPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: automatic, size: size)
        expect(automaticPNG == datesPNG, "Supplied dates select actual dates when no preference was saved")
        var hidden = dates
        hidden.weekdayNumberStyle = .hidden
        let hiddenPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: hidden, size: size)
        expect(Set([original, datesPNG, hiddenPNG]).count == 3, "Ordinal, actual dates and hidden numbers produce three distinct wallpapers")
        for (name, image) in [("Date", datesPNG), ("Hidden", hiddenPNG)] {
            guard let difference = changedPixelBounds(original, image) else { fatalError("\(name) labels changed no pixels") }
            expect(difference.minY >= 180 && difference.maxY <= 200,
                   "\(name) preference changes only the weekday header strip")
        }

        for day in 0...6 {
            expect(WallpaperRenderer.weekdayNumber(for: day, configuration: dates) == dateLabels[day],
                   "\(ScheduleEntry.dayLabels[day]) displays its explicit \(dateLabels[day]) date")
        }
        expect((0...6).allSatisfy { WallpaperRenderer.weekdayNumber(for: $0, configuration: hidden) == nil },
               "Hidden mode suppresses all seven numeric labels")
        expect(WallpaperRenderer.weekdayNumber(for: -1, configuration: dates) == nil && WallpaperRenderer.weekdayNumber(for: 7, configuration: dates) == nil,
               "Out-of-range weekday lookups are ignored safely")

        dates.highlightedDay = 2
        hidden.highlightedDay = 2
        let datedToday = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: dates, size: size)
        let hiddenToday = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: hidden, size: size)
        expect(WallpaperRenderer.weekdayNumber(for: 2, configuration: dates) == "09", "The highlighted day retains its actual date")
        expect(changedPixelBounds(datedToday, hiddenToday, within: CGRect(x: 414, y: 191, width: 33, height: 7)) != nil,
               "Date mode draws a separate small TODAY line below Wednesday's date")
        expect(hiddenToday != hiddenPNG, "Hidden number mode retains the visible today indicator")
        guard let todayDifference = changedPixelBounds(hiddenToday, datedToday) else { fatalError("Today's date changed no pixels") }
        expect(todayDifference.minY >= 180 && todayDifference.maxY <= 200,
               "Date and hidden modes share the same today border and differ only inside weekday headers")

        let malformed: [[String]?] = [nil, [], Array(dateLabels.prefix(6)), dateLabels + ["14"],
                                     ["7"] + Array(dateLabels.dropFirst()),
                                     ["09.07"] + Array(dateLabels.dropFirst()),
                                     ["00"] + Array(dateLabels.dropFirst()),
                                     ["32"] + Array(dateLabels.dropFirst()),
                                     ["０７"] + Array(dateLabels.dropFirst())]
        for (index, labels) in malformed.enumerated() {
            var invalid = dates
            invalid.weekdayDateLabels = labels
            expect((0...6).allSatisfy { WallpaperRenderer.weekdayNumber(for: $0, configuration: invalid) == nil },
                   "Malformed date payload \(index + 1) never substitutes an invented ordinal or date")
            let invalidPNG = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: invalid, size: size)
            expect(invalidPNG == hiddenToday, "Malformed date payload \(index + 1) renders safely and retains TODAY")
        }

        var weekendDates = dates
        weekendDates.highlightedDay = nil
        weekendDates.showWeekends = true
        var weekendHidden = weekendDates
        weekendHidden.weekdayNumberStyle = .hidden
        let sevenDates = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: weekendDates, size: size)
        let sevenHidden = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: weekendHidden, size: size)
        // Sunday is the rightmost header at 756px, within the unchanged grid.
        expect(changedPixelBounds(sevenDates, sevenHidden, within: CGRect(x: 630, y: 180, width: 70, height: 20)) != nil,
               "A seven-day timetable paints Sunday's actual date")
        let saved = try JSONEncoder().encode(dates)
        let restored = try JSONDecoder().decode(WallpaperConfiguration.self, from: saved)
        expect(restored == dates, "Weekday number preference and explicit render labels round-trip through Codable")
        let legacy = try JSONDecoder().decode(WallpaperConfiguration.self, from: JSONEncoder().encode(WallpaperConfiguration()))
        expect(legacy.weekdayNumberStyle == nil && legacy.weekdayDateLabels == nil && legacy.resolvedWeekdayNumberStyle == .ordinal,
               "Existing configurations without weekday fields keep their original ordinal default")
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
        try verifyWeekdayNumbers(original: original, size: size)
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
            for style in WeekdayNumberStyle.allCases {
                var configuration = WallpaperConfiguration()
                configuration.weekdayNumberStyle = style
                configuration.weekdayDateLabels = dateLabels
                configuration.subtitle = "2026.09.07 — 2026.09.13"
                configuration.highlightedDay = 1
                configuration.showWeekends = true
                let png = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: configuration)
                try png.write(to: directory.appendingPathComponent("weekday-\(style.rawValue)-demo.png"))
            }
            print("Review images saved to \(directory.path)")
        }
        print("Renderer verification completed: \(checks) checks passed.")
    }
}
