import AppKit
import ImageIO
import XCTest
@testable import TimetableWallpaper

final class RendererTests: XCTestCase {
    private let previewSize = CGSize(width: 756, height: 491)

    func testPNGHasRequestedPixelDimensions() throws {
        let size = CGSize(width: 1000, height: 650)
        let data = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: .init(), size: size)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1000)
        XCTAssertEqual(image.height, 650)
    }

    func testDefaultExportUsesSelectedResolution() throws {
        var configuration = WallpaperConfiguration()
        configuration.resolution = .air13
        let image = try WallpaperRenderer.render(entries: [], configuration: configuration)
        XCTAssertEqual(image.size, configuration.resolution.size)
        var proposed = CGRect(origin: .zero, size: image.size)
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        XCTAssertEqual(bitmap.width, 2560)
        XCTAssertEqual(bitmap.height, 1664)
    }

    func testRepeatedRenderIsByteIdenticalAndIgnoresUUIDAndInputOrder() throws {
        let entries = ScheduleEntry.sample
        var equivalentEntries = Array(entries.reversed())
        for index in equivalentEntries.indices { equivalentEntries[index].id = UUID() }
        let first = try WallpaperRenderer.pngData(entries: entries, configuration: .init(), size: previewSize)
        let repeated = try WallpaperRenderer.pngData(entries: entries, configuration: .init(), size: previewSize)
        let equivalent = try WallpaperRenderer.pngData(entries: equivalentEntries, configuration: .init(), size: previewSize)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first, equivalent)
    }

    func testWeekendAndMidnightAutomaticallyExpandVisibleGrid() throws {
        let entries = [ScheduleEntry(name: "밤의 타이포그래피", day: 6, startMinutes: 1410, endMinutes: 1440, location: "디자인관 302")]
        let automatic = try WallpaperRenderer.pngData(entries: entries, configuration: .init(), size: previewSize)
        var explicit = WallpaperConfiguration()
        explicit.showWeekends = true
        explicit.endHour = 24
        let configured = try WallpaperRenderer.pngData(entries: entries, configuration: explicit, size: previewSize)
        XCTAssertEqual(automatic, configured)
    }

    func testEarlyMorningAutomaticallyExpandsVisibleGrid() throws {
        let entries = [ScheduleEntry(name: "First light", day: 0, startMinutes: 0, endMinutes: 30)]
        let automatic = try WallpaperRenderer.pngData(entries: entries, configuration: .init(), size: previewSize)
        var explicit = WallpaperConfiguration()
        explicit.startHour = 0
        XCTAssertEqual(automatic, try WallpaperRenderer.pngData(entries: entries, configuration: explicit, size: previewSize))
    }

    func testEmptyStateAndThemesProduceDistinctImages() throws {
        var outputs: [Data] = []
        for theme in WallpaperTheme.allCases {
            var configuration = WallpaperConfiguration()
            configuration.theme = theme
            let data = try WallpaperRenderer.pngData(entries: [], configuration: configuration, size: previewSize)
            XCTAssertGreaterThan(data.count, 1000)
            outputs.append(data)
        }
        XCTAssertEqual(Set(outputs).count, WallpaperTheme.allCases.count)
    }

    func testOverlapLanesNeverPlaceConcurrentClassesTogether() {
        let entries = [
            ScheduleEntry(name: "A", day: 0, startMinutes: 600, endMinutes: 720),
            ScheduleEntry(name: "B", day: 0, startMinutes: 630, endMinutes: 660),
            ScheduleEntry(name: "C", day: 0, startMinutes: 660, endMinutes: 750),
            ScheduleEntry(name: "D", day: 0, startMinutes: 780, endMinutes: 810)
        ]
        let positioned = WallpaperRenderer.positioned(entries)
        XCTAssertEqual(positioned.count, entries.count)
        for first in positioned {
            for second in positioned where first.entry.overlaps(second.entry) {
                XCTAssertNotEqual(first.lane, second.lane)
                XCTAssertEqual(first.laneCount, second.laneCount)
            }
        }
        XCTAssertEqual(positioned.first(where: { $0.entry.name == "D" })?.laneCount, 1)
        XCTAssertEqual(positioned.first(where: { $0.entry.name == "A" })?.laneCount, 2)
    }

    func testInvalidSizeFailsBeforeAllocatingAnImage() {
        for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 600), CGSize(width: 1_000_000, height: 1_000_000)] {
            XCTAssertThrowsError(try WallpaperRenderer.pngData(entries: [], configuration: .init(), size: size))
        }
    }
}
