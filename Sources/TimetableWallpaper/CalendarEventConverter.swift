import CryptoKit
import Foundation

/// Converts absolute occurrences into the selected timezone's weekly wall clock.
/// Week and day ends are exclusive; no fixed 24-hour arithmetic is used.
enum CalendarEventConverter {
    static func convert(_ events: [CalendarEventRecord], week: CalendarWeek) -> CalendarImportResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = week.timeZone
        var result = CalendarImportResult(entries: [])
        var cancelledOrDeclined = 0
        var invalid = 0
        var unsupportedWallTime = 0
        var roundedSubminute = 0
        var entriesBySource: [String: ScheduleEntry] = [:]

        // Sorting also makes duplicate/conflicting records resolve consistently,
        // independent of EventKit's order or freshly generated ScheduleEntry UUIDs.
        let ordered = events.sorted { sortKey($0) < sortKey($1) }
        for event in ordered {
            guard event.startDate.timeIntervalSince1970.isFinite,
                  event.endDate.timeIntervalSince1970.isFinite,
                  event.endDate > event.startDate else {
                invalid += 1
                continue
            }
            guard event.startDate < week.end, event.endDate > week.start else { continue }
            if event.isCancelled || event.isDeclined {
                cancelledOrDeclined += 1
                continue
            }
            if event.isAllDay {
                result.allDayCount += 1
                continue
            }

            var cursor = max(event.startDate, week.start)
            let clippedEnd = min(event.endDate, week.end)
            var skippedWallTime = false
            var roundedEvent = false
            while cursor < clippedEnd {
                guard let day = calendar.dateInterval(of: .day, for: cursor), day.end > cursor else {
                    skippedWallTime = true
                    break
                }
                let segmentEnd = min(day.end, clippedEnd)
                let start = wallMinutes(cursor, calendar: calendar)
                let finish = segmentEnd == day.end ? 1440 : wallMinutes(segmentEnd, calendar: calendar)
                // A fall-back clock can move backward within one absolute event.
                // The weekly grid cannot represent that interval faithfully.
                guard finish > start else {
                    skippedWallTime = true
                    cursor = segmentEnd
                    continue
                }
                let startMinute = max(0, min(1439, Int(floor(start))))
                let endMinute = max(startMinute + 1, min(1440, Int(ceil(finish))))
                if finish - start < 1 { roundedEvent = true }
                let key = sourceKey(event, day: day.start, calendar: calendar)
                let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                entriesBySource[key] = ScheduleEntry(
                    name: trimmedTitle.isEmpty ? "제목 없는 일정" : trimmedTitle,
                    day: (calendar.component(.weekday, from: day.start) + 5) % 7,
                    startMinutes: startMinute,
                    endMinutes: endMinute,
                    location: event.location.trimmingCharacters(in: .whitespacesAndNewlines),
                    calendarSourceKey: key,
                    calendarEventKey: eventKey(event),
                    calendarOccurrenceKey: occurrenceKey(event)
                )
                cursor = segmentEnd
            }
            if skippedWallTime { unsupportedWallTime += 1 }
            if roundedEvent { roundedSubminute += 1 }
        }

        result.entries = entriesBySource.values.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
            if $0.endMinutes != $1.endMinutes { return $0.endMinutes < $1.endMinutes }
            return ($0.calendarSourceKey ?? "") < ($1.calendarSourceKey ?? "")
        }
        // allDayCount is separate. excludedCount counts source events with at
        // least one excluded timed segment, even when other days are displayable.
        result.excludedCount = cancelledOrDeclined + invalid + unsupportedWallTime
        if result.allDayCount > 0 {
            result.warnings.append("종일 일정 \(result.allDayCount)개는 시간이 정해져 있지 않아 제외했습니다.")
        }
        if cancelledOrDeclined > 0 {
            result.warnings.append("취소되거나 참석을 거절한 일정 \(cancelledOrDeclined)개를 제외했습니다.")
        }
        if invalid > 0 {
            result.warnings.append("시간이 없거나 종료가 시작보다 늦지 않은 일정 \(invalid)개를 제외했습니다.")
        }
        if unsupportedWallTime > 0 {
            result.warnings.append("서머타임 전환 등으로 시계 시간이 역전되거나 같은 일정 \(unsupportedWallTime)개의 해당 구간을 제외했습니다.")
        }
        if roundedSubminute > 0 {
            result.warnings.append("1분 미만 구간이 있는 일정 \(roundedSubminute)개는 분 단위로 넓혀 표시했습니다.")
        }
        return result
    }

    private static func wallMinutes(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
            + Double(components.nanosecond ?? 0) / 60_000_000_000
    }

    private static func sourceKey(_ event: CalendarEventRecord, day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let localDay = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        let occurrence = event.occurrenceDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "single"
        let parts = ["serein-calendar-v1", event.calendarID, event.id, occurrence, localDay]
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func eventKey(_ event: CalendarEventRecord) -> String {
        identityDigest(["serein-calendar-event-v1", event.calendarID, stableIdentity(event)])
    }

    private static func occurrenceKey(_ event: CalendarEventRecord) -> String {
        // EventKit retains the original occurrenceDate when an occurrence is
        // moved. Single events use their stable identity without their start time.
        let occurrence = event.occurrenceDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "single"
        return identityDigest(["serein-calendar-occurrence-v1", event.calendarID, stableIdentity(event), occurrence])
    }

    private static func stableIdentity(_ event: CalendarEventRecord) -> String {
        if let seriesID = event.seriesID, !seriesID.isEmpty { return seriesID }
        return event.id
    }

    private static func identityDigest(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sortKey(_ event: CalendarEventRecord) -> String {
        let parts = [event.calendarID, event.id,
                     event.occurrenceDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "",
                     String(event.startDate.timeIntervalSince1970.bitPattern),
                     String(event.endDate.timeIntervalSince1970.bitPattern),
                     event.title, event.location, String(event.isAllDay),
                     String(event.isCancelled), String(event.isDeclined), event.seriesID ?? ""]
        return String(data: (try? JSONEncoder().encode(parts)) ?? Data(), encoding: .utf8) ?? ""
    }
}
