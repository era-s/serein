import XCTest
@testable import TimetableWallpaper

final class OCRTests: XCTestCase {
    private func span(_ text: String, x: CGFloat = 0.1, y: CGFloat = 0.8, width: CGFloat = 0.7, height: CGFloat = 0.02) -> RecognizedScheduleSpan {
        .init(text: text, bounds: CGRect(x: x, y: y, width: width, height: height))
    }

    func testExplicitKoreanAndEnglishSchedules() {
        let result = TimetableOCR.parse(spans: [
            span("월 09:00-10:30 자료구조 공학관 301", y: 0.8),
            span("Wednesday 13:00–14:15 Creative Coding Room 204", y: 0.7),
            span("금요일 15시 30분~17시 타이포그래피 디자인관 202호", y: 0.6)
        ])
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entries.map(\.day), [0, 2, 4])
        XCTAssertEqual(result.entries.map(\.startMinutes), [540, 780, 930])
        XCTAssertEqual(result.entries.map(\.endMinutes), [630, 855, 1020])
        XCTAssertEqual(result.entries.map(\.name), ["자료구조", "Creative Coding", "타이포그래피"])
        XCTAssertEqual(result.entries.map(\.location), ["공학관 301", "Room 204", "디자인관 202호"])
        XCTAssertTrue(result.recognizedText.contains("자료구조"))
    }

    func testJoinsSeparateObservationsIntoAnExplicitRow() {
        let result = TimetableOCR.parse(spans: [
            span("공학관 301", x: 0.72, y: 0.802, width: 0.2),
            span("자료구조", x: 0.46, y: 0.798, width: 0.2),
            span("09:00–10:30", x: 0.2, y: 0.801, width: 0.22),
            span("월", x: 0.1, y: 0.8, width: 0.05)
        ])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "자료구조")
        XCTAssertEqual(result.entries.first?.location, "공학관 301")
    }

    func testHandlesMultipleCompleteEntriesInOneImageRow() {
        let result = TimetableOCR.parse(spans: [
            span("월 09:00-10:00 History", x: 0.1, y: 0.8, width: 0.35),
            span("화 11:00-12:00 Design", x: 0.55, y: 0.8, width: 0.35),
            span("금 13:00-14:00 Coding", y: 0.7)
        ])
        XCTAssertEqual(result.entries.map(\.name), ["History", "Design", "Coding"])
    }

    func testWeekdayCharactersInsideCourseNamesDoNotBecomeDays() {
        let result = TimetableOCR.parse(spans: [
            span("월간디자인 09:00-10:00", y: 0.8),
            span("일반물리학 10:00-11:00", y: 0.7),
            span("목공예 11:00-12:00", y: 0.6),
            span("Monday 14:00-15:00 월간디자인", y: 0.5)
        ])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "월간디자인")
        XCTAssertEqual(result.entries.first?.day, 0)
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
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries.map(\.startMinutes), [1380, 0])
        XCTAssertEqual(result.entries.map(\.endMinutes), [1440, 60])
        XCTAssertTrue(result.entries.allSatisfy { $0.validationError == nil })
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
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries.map(\.day), [0, 1])
        XCTAssertEqual(result.entries.map(\.name), ["Visual Thinking", "자료구조"])
        XCTAssertEqual(result.entries.map(\.location), ["디자인관 302", "공학관 201"])
        XCTAssertEqual(result.entries.map(\.startMinutes), [540, 660])
        XCTAssertEqual(result.entries.map(\.endMinutes), [600, 720])
        XCTAssertTrue(result.warnings.joined().contains("추정"))
    }

    func testGridPreservesWrittenStartAndEndTimesWithinAClassBlock() {
        let result = TimetableOCR.parse(spans: grid + [
            span("Creative Coding", x: 0.2, y: 0.78, width: 0.2),
            span("09:00–10:30", x: 0.2, y: 0.75, width: 0.2),
            span("Room 204", x: 0.2, y: 0.72, width: 0.2)
        ])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Creative Coding")
        XCTAssertEqual(result.entries.first?.endMinutes, 630)
        XCTAssertEqual(result.entries.first?.location, "Room 204")
    }

    func testDoesNotGuessClockTimesFromPeriodNumbers() {
        let periods = grid.filter { !$0.text.contains(":") } + [
            span("1", x: 0.03, y: 0.79, width: 0.09),
            span("2", x: 0.03, y: 0.69, width: 0.09),
            span("3", x: 0.03, y: 0.59, width: 0.09),
            span("자료구조", x: 0.2, y: 0.78, width: 0.2)
        ]
        XCTAssertTrue(TimetableOCR.parse(spans: periods).entries.isEmpty)
    }

    func testRejectsInconsistentTimeAxisAndMissingGeometry() {
        var inconsistent = grid
        inconsistent[3].text = "12:00"
        inconsistent.append(span("자료구조", x: 0.2, y: 0.78, width: 0.2))
        XCTAssertTrue(TimetableOCR.parse(spans: inconsistent).entries.isEmpty)
        let textOnly = TimetableOCR.parse(spans: [span("자료구조 공학관 301")])
        XCTAssertTrue(textOnly.entries.isEmpty)
        XCTAssertTrue(textOnly.recognizedText.contains("자료구조"))
        XCTAssertTrue(textOnly.warnings.joined().contains("직접 입력"))
    }

    func testUnreadableAndLowConfidenceTextReturnUsefulWarnings() {
        let empty = TimetableOCR.parse(spans: [])
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.recognizedText, "")
        XCTAssertTrue(empty.warnings.joined().contains("읽을 수 있는 글자"))
        var lowConfidence = span("월 09:00-10:00 자료구조")
        lowConfidence.confidence = 0.25
        let result = TimetableOCR.parse(spans: [lowConfidence])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertTrue(result.warnings.joined().contains("신뢰도"))
    }

    func testRejectsUnreadableImage() async {
        do {
            _ = try await TimetableOCR.recognize(url: URL(fileURLWithPath: "/a-file-that-does-not-exist.png"))
            XCTFail("Expected image loading error")
        } catch {
            XCTAssertTrue(error is TimetableOCRError)
        }
    }
}
