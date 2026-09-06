import Foundation
import CoreGraphics
import ImageIO
import Vision

struct OCRImportResult: Sendable {
    var entries: [ScheduleEntry]
    var recognizedText: String
    var warnings: [String]
}

/// Coordinates use Vision's normalized image space (origin at the bottom left).
struct RecognizedScheduleSpan: Sendable {
    var text: String
    var bounds: CGRect
    var confidence: Float = 1
}

enum TimetableOCRError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        "이미지를 열 수 없어요. PNG, JPEG 또는 HEIC 이미지로 다시 시도해주세요."
    }
}

enum TimetableOCR {
    static func recognize(url: URL) async throws -> OCRImportResult {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096
                  ] as CFDictionary) else {
                throw TimetableOCRError.unreadableImage
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.005
            // ImageIO applies EXIF orientation above; bounding boxes now match the upright image.
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            try Task.checkCancellation()
            let spans = (request.results ?? []).compactMap { observation -> RecognizedScheduleSpan? in
                guard let text = observation.topCandidates(1).first else { return nil }
                return .init(text: text.string, bounds: observation.boundingBox, confidence: text.confidence)
            }
            return parse(spans: spans)
        }.value
    }

    /// Pure parsing entry point, also used by tests. Grid-derived times are always provisional.
    static func parse(spans: [RecognizedScheduleSpan]) -> OCRImportResult {
        let spans = spans.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let rows = alignedRows(spans)
        let recognizedText = rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        var warnings: [String] = []
        var entries: [ScheduleEntry] = []

        // First prefer self-contained rows with explicitly written days and start/end times.
        for row in rows {
            if let entry = explicitEntry(row.map(\.text).joined(separator: " ")) {
                entries.append(entry)
            } else {
                // Separate table columns can each contain a complete textual record.
                entries.append(contentsOf: row.compactMap { explicitEntry($0.text) })
            }
        }
        if entries.isEmpty, let gridEntries = gridEntries(spans), !gridEntries.isEmpty {
            entries = gridEntries
            warnings.append("표의 요일 열과 시간 눈금으로 과목을 배치했어요. 시간이 적히지 않은 수업은 글자 위치를 기준으로 시작 시간을 30분 단위, 종료 시간을 기본 1시간으로 추정했어요. 적용 전에 모든 요일과 시작·종료 시간을 확인해주세요.")
        } else if !entries.isEmpty {
            warnings.append("이미지에서 읽은 과목 이름, 요일, 시간과 장소를 확인한 뒤 가져와주세요. 인식되지 않은 행은 원문과 비교해 직접 추가할 수 있어요.")
        }
        if spans.contains(where: { $0.confidence < 0.5 }) {
            warnings.append("일부 글자가 흐릿해서 인식 신뢰도가 낮아요. 인식한 원문과 실제 시간표를 비교해주세요.")
        }
        if entries.isEmpty {
            warnings.append(spans.isEmpty
                ? "읽을 수 있는 글자를 찾지 못했어요. 더 선명한 시간표 이미지를 사용하거나 직접 입력해주세요."
                : "요일과 시간을 확실히 연결하지 못했어요. 인식한 원문을 참고해 직접 입력해주세요. ‘월 09:00–10:30 자료구조’처럼 요일과 시간이 적힌 이미지도 사용할 수 있어요.")
        }
        // Avoid duplicating the same row if Vision happened to return overlapping observations.
        var seen = Set<String>()
        entries = entries.filter {
            seen.insert("\($0.day)|\($0.startMinutes)|\($0.endMinutes)|\($0.name)|\($0.location)").inserted
        }.sorted {
            $0.day == $1.day ? $0.startMinutes < $1.startMinutes : $0.day < $1.day
        }
        return .init(entries: entries, recognizedText: recognizedText, warnings: warnings)
    }

    private static func alignedRows(_ spans: [RecognizedScheduleSpan]) -> [[RecognizedScheduleSpan]] {
        var rows: [[RecognizedScheduleSpan]] = []
        for span in spans.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let index = rows.indices.last,
               let first = rows[index].first,
               abs(span.bounds.midY - first.bounds.midY) <= max(span.bounds.height, first.bounds.height) * 0.55 {
                rows[index].append(span)
            } else {
                rows.append([span])
            }
        }
        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    private static let dayPattern = #"(?<![\p{L}\p{N}])(?:월요일|화요일|수요일|목요일|금요일|토요일|일요일|월|화|수|목|금|토|일|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?![\p{L}\p{N}])"#
    private static let timePattern = #"(?<![\d:])(?:[01]?\d|2[0-4])\s*(?::\s*[0-5]\d|시(?:\s*[0-5]?\d\s*분)?)"#
    private static let rangePattern = timePattern + #"\s*(?:[-–—~〜]|to)\s*"# + timePattern + #"(?![\d:])"#

    private static func matches(_ pattern: String, _ string: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
    }

    private static func substring(_ string: String, _ range: NSRange) -> String {
        guard let range = Range(range, in: string) else { return "" }
        return String(string[range])
    }

    private static func dayNumber(_ string: String) -> Int? {
        let token = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = [["월", "월요일", "mon", "monday"], ["화", "화요일", "tue", "tuesday"],
                      ["수", "수요일", "wed", "wednesday"], ["목", "목요일", "thu", "thursday"],
                      ["금", "금요일", "fri", "friday"], ["토", "토요일", "sat", "saturday"],
                      ["일", "일요일", "sun", "sunday"]]
        return tokens.firstIndex { $0.contains(token) }
    }

    private static func minutes(_ string: String) -> Int? {
        let numbers = matches(#"\d+"#, string).compactMap { Int(substring(string, $0.range)) }
        guard let hour = numbers.first, hour <= 24 else { return nil }
        let minute = numbers.count > 1 ? numbers[1] : 0
        guard minute < 60, hour < 24 || minute == 0 else { return nil }
        return hour * 60 + minute
    }

    private static func timeRange(_ string: String) -> (start: Int, end: Int, range: NSRange)? {
        guard let match = matches(rangePattern, string).first else { return nil }
        let rangeText = substring(string, match.range)
        let times = matches(timePattern, rangeText)
        guard times.count == 2,
              let start = minutes(substring(rangeText, times[0].range)),
              let end = minutes(substring(rangeText, times[1].range)), start < end else { return nil }
        return (start, end, match.range)
    }

    private static func explicitEntry(_ string: String) -> ScheduleEntry? {
        guard let range = timeRange(string) else { return nil }
        let days = matches(dayPattern, string)
        // Several days or time ranges in one joined row are ambiguous; inspect its spans separately.
        guard days.count == 1, matches(rangePattern, string).count == 1,
              let day = dayNumber(substring(string, days[0].range)) else { return nil }
        let mutable = NSMutableString(string: string)
        for match in [range.range, days[0].range].sorted(by: { $0.location > $1.location }) {
            mutable.replaceCharacters(in: match, with: " ")
        }
        let details = courseDetails(mutable as String)
        guard !details.name.isEmpty else { return nil }
        return .init(name: details.name, day: day, startMinutes: range.start, endMinutes: range.end, location: details.location)
    }

    private static func courseDetails(_ text: String) -> (name: String, location: String) {
        let clean = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|,;·()[]")))
        guard !matches(#"[\p{L}]{2}"#, clean).isEmpty else { return ("", "") }
        // Location is only separated with recognizable room/building notation. Other text stays intact.
        let locationPattern = #"(?:[\p{L}\d-]*(?:관|동|강의실|실험실|스튜디오)\s*[-\dA-Za-z]+(?:호)?|(?:Room|Rm\.?|Building|Studio|Lab)\s+[\p{L}\d-]+|\d{2,4}호)\s*$"#
        if let match = matches(locationPattern, clean).first, match.range.location > 0 {
            let name = substring(clean, NSRange(location: 0, length: match.range.location))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|,;·")))
            if !name.isEmpty { return (name, substring(clean, match.range)) }
        }
        return (clean, "")
    }

    private struct Header {
        var day: Int
        var span: RecognizedScheduleSpan
    }

    private static func headerDay(_ text: String) -> Int? {
        // Entire header must be a weekday, optionally followed by a date. Never match '월' in a title.
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dayMatch = matches("^\\s*[\\[(]?" + dayPattern + #"[\])]?(?:\s+\d{1,2}(?:[/.]\d{1,2})?)?\s*$"#, clean).first else { return nil }
        let matched = substring(clean, dayMatch.range)
        guard let token = matches(dayPattern, matched).first else { return nil }
        return dayNumber(substring(matched, token.range))
    }

    private static func tickMinutes(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !matches(#"^(?:[01]?\d|2[0-4])(?:\s*:\s*[0-5]\d|\s*시)?$"#, clean).isEmpty else { return nil }
        return minutes(clean)
    }

    private static func gridEntries(_ spans: [RecognizedScheduleSpan]) -> [ScheduleEntry]? {
        let candidates = spans.compactMap { span -> Header? in
            headerDay(span.text).map { .init(day: $0, span: span) }
        }
        // Find an aligned header row with at least two different days and well-separated columns.
        var headerGroups: [[Header]] = []
        for candidate in candidates.sorted(by: { $0.span.bounds.midY > $1.span.bounds.midY }) {
            if let index = headerGroups.firstIndex(where: {
                abs(($0.first?.span.bounds.midY ?? 0) - candidate.span.bounds.midY) < max(candidate.span.bounds.height * 1.5, 0.025)
            }) { headerGroups[index].append(candidate) }
            else { headerGroups.append([candidate]) }
        }
        guard let headers = headerGroups.filter({ Set($0.map(\.day)).count == $0.count && $0.count >= 2 })
            .max(by: { $0.count < $1.count })?.sorted(by: { $0.span.bounds.midX < $1.span.bounds.midX }) else { return nil }
        let gaps = zip(headers, headers.dropFirst()).map { $1.span.bounds.midX - $0.span.bounds.midX }
        guard let smallestGap = gaps.min(), smallestGap > 0.06 else { return nil }
        let columnWidth = gaps.sorted()[gaps.count / 2]
        let headerBottom = headers.map { $0.span.bounds.minY }.min() ?? 1
        let axisLimit = headers[0].span.bounds.midX - columnWidth * 0.4
        let ticks = spans.compactMap { span -> (y: CGFloat, minutes: Int, explicit: Bool)? in
            guard span.bounds.midX < axisLimit, span.bounds.midY < headerBottom,
                  let minute = tickMinutes(span.text) else { return nil }
            return (span.bounds.midY, minute, span.text.contains(":") || span.text.contains("시"))
        }.sorted { $0.y > $1.y }
        guard ticks.count >= 2, let firstTick = ticks.first, let lastTick = ticks.last,
              firstTick.y - lastTick.y > 0.06,
              lastTick.minutes > firstTick.minutes else { return nil }
        // Bare 1, 2, 3 often mean class periods, which cannot safely be converted to clock times.
        guard ticks.contains(where: \.explicit) || (ticks.count >= 3 && firstTick.minutes >= 360) else { return nil }
        // Reject period numbers and inconsistent axes. We only accept plausible clock-hour increments.
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            guard b.minutes > a.minutes, (15...180).contains(b.minutes - a.minutes) else { return nil }
        }
        let scale = CGFloat(lastTick.minutes - firstTick.minutes) / (firstTick.y - lastTick.y)
        func minuteAt(_ y: CGFloat) -> CGFloat { CGFloat(firstTick.minutes) + (firstTick.y - y) * scale }
        guard ticks.allSatisfy({ abs(minuteAt($0.y) - CGFloat($0.minutes)) <= 12 }) else { return nil }

        var result: [ScheduleEntry] = []
        for (index, header) in headers.enumerated() {
            let left = index == 0 ? header.span.bounds.midX - columnWidth / 2 : (headers[index - 1].span.bounds.midX + header.span.bounds.midX) / 2
            let right = index == headers.count - 1 ? header.span.bounds.midX + columnWidth / 2 : (headers[index + 1].span.bounds.midX + header.span.bounds.midX) / 2
            let content = spans.filter { span in
                span.bounds.midX >= left && span.bounds.midX < right && span.bounds.maxY < headerBottom
                    && minuteAt(span.bounds.midY) >= CGFloat(firstTick.minutes - 15)
                    && minuteAt(span.bounds.midY) <= CGFloat(min(lastTick.minutes + 60, 1440))
                    && headerDay(span.text) == nil && tickMinutes(span.text) == nil
                    && matches(#"^(?:시간표|시간|교시|요일|Timetable|Schedule|Time|\d+\s*교시)$"#, span.text).isEmpty
            }.sorted { $0.bounds.midY > $1.bounds.midY }
            var groups: [[RecognizedScheduleSpan]] = []
            for span in content {
                if let index = groups.indices.last, let last = groups[index].last,
                   (last.bounds.minY - span.bounds.maxY) * scale <= 12,
                   (last.bounds.midY - span.bounds.midY) * scale <= 25,
                   timeRange(span.text) == nil || !groups[index].contains(where: { timeRange($0.text) != nil }) {
                    groups[index].append(span)
                } else { groups.append([span]) }
            }
            for group in groups {
                guard let top = group.first else { continue }
                var text = alignedRows(group).map { $0.map(\.text).joined(separator: " ") }.joined(separator: " ")
                let writtenTime = timeRange(text)
                if let writtenTime, let range = Range(writtenTime.range, in: text) { text.removeSubrange(range) }
                let details = courseDetails(text)
                guard !details.name.isEmpty else { continue }
                let start = writtenTime?.start ?? Int((minuteAt(top.bounds.maxY) / 30).rounded()) * 30
                let end = writtenTime?.end ?? min(start + 60, 1440)
                guard start >= 0, start < end, end <= 1440 else { continue }
                result.append(.init(name: details.name, day: header.day, startMinutes: start, endMinutes: end, location: details.location))
            }
        }
        return result
    }
}
