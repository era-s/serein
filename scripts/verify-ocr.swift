// Standalone verification for machines with Command Line Tools but no XCTest SDK.
// Run scripts/verify-ocr.sh. This compiles the production OCR and model sources.
import Foundation
import CoreGraphics

enum VerificationState {
    static var failures: [String] = []
    static var assertions = 0
}
func check(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    VerificationState.assertions += 1
    if !condition() { VerificationState.failures.append("FAIL \(file):\(line)") }
}
func checkEqual<T: Equatable>(_ actual: @autoclosure () -> T, _ expected: @autoclosure () -> T, file: StaticString = #file, line: UInt = #line) {
    VerificationState.assertions += 1
    let actual = actual()
    let expected = expected()
    if actual != expected { VerificationState.failures.append("FAIL \(file):\(line) — got \(actual), expected \(expected)") }
}
func recordFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
    VerificationState.failures.append("FAIL \(file):\(line) — \(message)")
}


final class OCRParserChecks {
    private func span(_ text: String, x: CGFloat = 0.1, y: CGFloat = 0.8, width: CGFloat = 0.7, height: CGFloat = 0.02) -> RecognizedScheduleSpan {
        .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: height))
    }

    func testExplicitKoreanAndEnglishSchedules() {
        let result = TimetableOCR.parse(spans: [
            span("월 09:00-10:30 자료구조 공학관 301", y: 0.8),
            span("Wednesday 13:00–14:15 Creative Coding Room 204", y: 0.7),
            span("금요일 15시 30분~17시 타이포그래피 디자인관 202호", y: 0.6)
        ])
        checkEqual(result.entries.count, 3)
        checkEqual(result.entries.map(\.day), [0, 2, 4])
        checkEqual(result.entries.map(\.startMinutes), [540, 780, 930])
        checkEqual(result.entries.map(\.endMinutes), [630, 855, 1020])
        checkEqual(result.entries.map(\.name), ["자료구조", "Creative Coding", "타이포그래피"])
        checkEqual(result.entries.map(\.location), ["공학관 301", "Room 204", "디자인관 202호"])
        check(result.recognizedText.contains("자료구조"))
    }

    func testJoinsSeparateObservationsIntoAnExplicitRow() {
        let result = TimetableOCR.parse(spans: [
            span("공학관 301", x: 0.72, y: 0.802, width: 0.2),
            span("자료구조", x: 0.46, y: 0.798, width: 0.2),
            span("09:00–10:30", x: 0.2, y: 0.801, width: 0.22),
            span("월", x: 0.1, y: 0.8, width: 0.05)
        ])
        checkEqual(result.entries.count, 1)
        checkEqual(result.entries.first?.name, "자료구조")
        checkEqual(result.entries.first?.location, "공학관 301")
    }

    func testHandlesMultipleCompleteEntriesInOneImageRow() {
        let result = TimetableOCR.parse(spans: [
            span("월 09:00-10:00 History", x: 0.1, y: 0.8, width: 0.35),
            span("화 11:00-12:00 Design", x: 0.55, y: 0.8, width: 0.35),
            span("금 13:00-14:00 Coding", y: 0.7)
        ])
        checkEqual(result.entries.map(\.name), ["History", "Design", "Coding"])
    }

    func testWeekdayCharactersInsideCourseNamesDoNotBecomeDays() {
        let result = TimetableOCR.parse(spans: [
            span("월간디자인 09:00-10:00", y: 0.8),
            span("일반물리학 10:00-11:00", y: 0.7),
            span("목공예 11:00-12:00", y: 0.6),
            span("Monday 14:00-15:00 월간디자인", y: 0.5)
        ])
        checkEqual(result.entries.count, 1)
        checkEqual(result.entries.first?.name, "월간디자인")
        checkEqual(result.entries.first?.day, 0)
    }

    func testRejectsInvalidTimeRangesAndAcceptsMidnightBoundary() {
        let result = TimetableOCR.parse(spans: [
            span("월 25:00-26:00 Invalid", y: 0.9),
            span("화 09:60-10:00 Invalid", y: 0.8),
            span("수 13:00-12:00 Reversed", y: 0.7),
            span("목 09:00-09:00 Empty", y: 0.6),
            span("금 23:00-24:30 Invalid", y: 0.5),
            span("토 23:00-24:00 Astronomy", y: 0.4),
            span("일 00:00-01:00 Observing", y: 0.3)
        ])
        checkEqual(result.entries.count, 2)
        checkEqual(result.entries.map(\.startMinutes), [1380, 0])
        checkEqual(result.entries.map(\.endMinutes), [1440, 60])
        check(result.entries.allSatisfy { $0.validationError == nil })
    }

    private var grid: [RecognizedScheduleSpan] {
        [
            span("월요일", x: 0.26, y: 0.93, width: 0.08),
            span("화요일", x: 0.56, y: 0.93, width: 0.08),
            span("09:00", x: 0.03, y: 0.79, width: 0.09),
            span("10:00", x: 0.03, y: 0.69, width: 0.09),
            span("11:00", x: 0.03, y: 0.59, width: 0.09),
            span("12:00", x: 0.03, y: 0.49, width: 0.09),
            span("13:00", x: 0.03, y: 0.39, width: 0.09)
        ]
    }

    func testGridUsesHeaderColumnsAndConsistentClockAxis() {
        let result = TimetableOCR.parse(spans: grid + [
            span("Visual", x: 0.2, y: 0.78, width: 0.2),
            span("Thinking", x: 0.2, y: 0.75, width: 0.2),
            span("디자인관 302", x: 0.2, y: 0.72, width: 0.2),
            span("자료구조", x: 0.5, y: 0.58, width: 0.2),
            span("공학관 201", x: 0.5, y: 0.55, width: 0.2)
        ])
        checkEqual(result.entries.count, 2)
        checkEqual(result.entries.map(\.day), [0, 1])
        checkEqual(result.entries.map(\.name), ["Visual Thinking", "자료구조"])
        checkEqual(result.entries.map(\.location), ["디자인관 302", "공학관 201"])
        checkEqual(result.entries.map(\.startMinutes), [540, 660])
        checkEqual(result.entries.map(\.endMinutes), [600, 720])
        check(result.warnings.joined().contains("추정"))
    }

    func testGridPreservesWrittenStartAndEndTimesWithinAClassBlock() {
        let result = TimetableOCR.parse(spans: grid + [
            span("Creative Coding", x: 0.2, y: 0.78, width: 0.2),
            span("09:00–10:30", x: 0.2, y: 0.75, width: 0.2),
            span("Room 204", x: 0.2, y: 0.72, width: 0.2)
        ])
        checkEqual(result.entries.count, 1)
        checkEqual(result.entries.first?.name, "Creative Coding")
        checkEqual(result.entries.first?.endMinutes, 630)
        checkEqual(result.entries.first?.location, "Room 204")
    }

    func testDoesNotGuessClockTimesFromPeriodNumbers() {
        let periods = grid.filter { !$0.text.contains(":") } + [
            span("1", x: 0.03, y: 0.79, width: 0.09),
            span("2", x: 0.03, y: 0.69, width: 0.09),
            span("3", x: 0.03, y: 0.59, width: 0.09),
            span("자료구조", x: 0.2, y: 0.78, width: 0.2)
        ]
        check(TimetableOCR.parse(spans: periods).entries.isEmpty)
    }

    func testRejectsInconsistentTimeAxisAndMissingGeometry() {
        var inconsistent = grid
        inconsistent[3].text = "12:00"
        inconsistent.append(span("자료구조", x: 0.2, y: 0.78, width: 0.2))
        check(TimetableOCR.parse(spans: inconsistent).entries.isEmpty)
        let textOnly = TimetableOCR.parse(spans: [span("자료구조 공학관 301")])
        check(textOnly.entries.isEmpty)
        check(textOnly.recognizedText.contains("자료구조"))
        check(textOnly.warnings.joined().contains("직접 입력"))
    }

    func testUnreadableAndLowConfidenceTextReturnUsefulWarnings() {
        let empty = TimetableOCR.parse(spans: [])
        check(empty.entries.isEmpty)
        checkEqual(empty.recognizedText, "")
        check(empty.warnings.joined().contains("읽을 수 있는 글자"))
        var lowConfidence = span("월 09:00-10:00 자료구조")
        lowConfidence.confidence = 0.25
        let result = TimetableOCR.parse(spans: [lowConfidence])
        checkEqual(result.entries.count, 1)
        check(result.warnings.joined().contains("신뢰도"))
    }

    func testRejectsUnreadableImage() async {
        do {
            _ = try await TimetableOCR.recognize(url: URL(fileURLWithPath: "/a-file-that-does-not-exist.png"))
            recordFailure("Expected image loading error")
        } catch {
            check(error is TimetableOCRError)
        }
    }
}

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct OCRVerification {
    @MainActor
    static func main() async throws {
        let checks = OCRParserChecks()
        checks.testExplicitKoreanAndEnglishSchedules()
        checks.testJoinsSeparateObservationsIntoAnExplicitRow()
        checks.testHandlesMultipleCompleteEntriesInOneImageRow()
        checks.testWeekdayCharactersInsideCourseNamesDoNotBecomeDays()
        checks.testRejectsInvalidTimeRangesAndAcceptsMidnightBoundary()
        checks.testGridUsesHeaderColumnsAndConsistentClockAxis()
        checks.testGridPreservesWrittenStartAndEndTimesWithinAClassBlock()
        checks.testDoesNotGuessClockTimesFromPeriodNumbers()
        checks.testRejectsInconsistentTimeAxisAndMissingGeometry()
        checks.testUnreadableAndLowConfidenceTextReturnUsefulWarnings()
        await checks.testRejectsUnreadableImage()
        print("Parser checks: \(VerificationState.assertions) assertions, \(VerificationState.failures.count) failures across 11 scenarios")
        let width = 1600
        let height = 1100
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        func text(_ value: String, _ x: Double, _ y: Double, _ w: Double, size: Double = 25, bold: Bool = false) {
            let font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
            (value as NSString).draw(in: CGRect(x: x, y: y, width: w, height: 40), withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        text("2026 가을학기 시간표", 160, 1020, 900, size: 36, bold: true)
        let left = 160.0
        let top = 940.0
        let column = 272.0
        let hour = 90.0
        context.setLineWidth(1)
        context.setStrokeColor(NSColor(white: 0.78, alpha: 1).cgColor)
        for day in 0...5 {
            let x = left + Double(day) * column
            context.move(to: CGPoint(x: x, y: 130))
            context.addLine(to: CGPoint(x: x, y: top))
        }
        for row in 0...9 {
            let y = top - Double(row) * hour
            context.move(to: CGPoint(x: left, y: y))
            context.addLine(to: CGPoint(x: left + 5 * column, y: y))
            text(String(format: "%02d:00", 9 + row), 50, y - 20, 100, size: 23)
        }
        context.strokePath()
        for (index, day) in ["월요일", "화요일", "수요일", "목요일", "금요일"].enumerated() {
            text(day, left + Double(index) * column + 92, top + 12, 140, size: 28, bold: true)
        }
        func course(_ name: String, day: Int, start: Double, duration: Double, location: String, writtenTime: String? = nil) {
            let x = left + Double(day) * column + 1
            let y = top - (start - 9) * hour - duration * hour + 1
            context.setFillColor(NSColor(calibratedRed: 0.88, green: 0.94, blue: 0.94, alpha: 1).cgColor)
            context.fill(CGRect(x: x, y: y, width: column - 2, height: duration * hour - 2))
            let titleY = top - (start - 9) * hour - 38
            text(name, x + 15, titleY, column - 25, size: 25, bold: true)
            text(writtenTime ?? location, x + 15, titleY - 30, column - 25, size: 20)
            if writtenTime != nil { text(location, x + 15, titleY - 60, column - 25, size: 20) }
        }
        course("자료구조", day: 0, start: 9, duration: 1.5, location: "공학관 301", writtenTime: "09:00–10:30")
        course("타이포그래피", day: 1, start: 11, duration: 1, location: "디자인관 202")
        course("선형대수학", day: 2, start: 13, duration: 1.5, location: "과학관 401", writtenTime: "13:00–14:30")
        course("Creative Coding", day: 4, start: 15, duration: 1, location: "Room 204")
        NSGraphicsContext.restoreGraphicsState()
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "artifacts/ocr-fixture.png"
        let url = URL(fileURLWithPath: path)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
        let result = try await TimetableOCR.recognize(url: url)
        print("Recognized text:\n\(result.recognizedText)\n")
        for entry in result.entries {
            print("\(ScheduleEntry.dayNames[entry.day]) \(entry.timeLabel) \(entry.name) | \(entry.location)")
        }
        for warning in result.warnings { print("Warning: \(warning)") }
        checkEqual(result.entries.count, 4)
        check(result.entries.contains(where: { $0.name.contains("자료구조") && $0.day == 0 && $0.startMinutes == 540 && $0.endMinutes == 630 }))
        check(result.entries.contains(where: { $0.name.contains("타이포그래피") && $0.day == 1 && $0.startMinutes == 660 && $0.endMinutes == 720 }))
        check(result.entries.contains(where: { $0.name.contains("선형대수학") && $0.day == 2 && $0.startMinutes == 780 && $0.endMinutes == 870 }))
        check(result.entries.contains(where: { $0.name.contains("Creative Coding") && $0.day == 4 && $0.startMinutes == 900 && $0.endMinutes == 960 }))
        check(result.entries.map(\.location) == ["공학관 301", "디자인관 202", "과학관 401", "Room 204"])
        check(result.warnings.joined().contains("추정"))
        let diagnostic = "Apple Vision OCR smoke check\n\n" + result.recognizedText + "\n\nCandidates\n" + result.entries.map { "\(ScheduleEntry.dayNames[$0.day]) \($0.timeLabel) \($0.name) | \($0.location)" }.joined(separator: "\n") + "\n\nWarnings\n" + result.warnings.joined(separator: "\n") + "\n"
        try diagnostic.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        print("Total: \(VerificationState.assertions) assertions, \(VerificationState.failures.count) failures (including actual Apple Vision OCR)")
        if !VerificationState.failures.isEmpty {
            VerificationState.failures.forEach { print($0) }
            exit(1)
        }
    }
}
