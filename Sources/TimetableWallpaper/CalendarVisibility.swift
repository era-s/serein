import Foundation

enum CalendarExclusionScope: String, Codable {
    case occurrence, event
}

struct ExcludedCalendarEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// A displayable snapshot, also retaining legacy source keys until hydrated.
    var entry: ScheduleEntry
    var scope: CalendarExclusionScope
}

/// Local presentation preferences only; these records never delete or edit an
/// event in its calendar. Matching uses provider identities, never titles.
struct CalendarVisibility: Codable, Equatable {
    var exclusions: [ExcludedCalendarEntry] = []

    init(exclusions: [ExcludedCalendarEntry] = []) { self.exclusions = exclusions }

    private enum CodingKeys: String, CodingKey { case exclusions }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exclusions = try container.decodeIfPresent([ExcludedCalendarEntry].self, forKey: .exclusions) ?? []
    }

    mutating func hide(_ entry: ScheduleEntry, scope: CalendarExclusionScope = .event) {
        guard Self.hasCalendarIdentity(entry) else { return }
        if exclusions.contains(where: { exclusion in
            exclusion.scope == .event && Self.sameEvent(exclusion.entry, entry)
                || scope == .occurrence && exclusion.scope == .occurrence && Self.sameOccurrence(exclusion.entry, entry)
        }) { return }
        exclusions.append(ExcludedCalendarEntry(entry: entry, scope: scope))
        consolidate()
    }

    func isHidden(_ entry: ScheduleEntry) -> Bool {
        exclusions.contains { Self.matches($0, entry) }
    }

    /// Hydrate an old source-key-only exclusion before filtering a fresh import.
    /// Keep absent exclusions: a recurring event may simply skip this week.
    mutating func reconcile(with incoming: [ScheduleEntry]) {
        let ordered = incoming.sorted(by: Self.snapshotOrder)
        for index in exclusions.indices {
            let previous = exclusions[index].entry
            // Prefer the existing segment when it is still present, then a
            // stable occurrence/series match. Never use visible text as identity.
            let match = ordered.first(where: { Self.sameSource(previous, $0) })
                ?? ordered.first(where: { Self.matches(exclusions[index], $0) })
            guard var match else { continue }
            // Fresh converter UUIDs must not cause a saved preference rewrite.
            match.id = previous.id
            match.calendarEventKey = match.calendarEventKey ?? previous.calendarEventKey
            match.calendarOccurrenceKey = match.calendarOccurrenceKey ?? previous.calendarOccurrenceKey
            match.calendarSourceKey = match.calendarSourceKey ?? previous.calendarSourceKey
            if match != previous { exclusions[index].entry = match }
        }
        consolidate()
    }

    @discardableResult
    mutating func restore(_ id: UUID) -> ExcludedCalendarEntry? {
        guard let index = exclusions.firstIndex(where: { $0.id == id }) else { return nil }
        return exclusions.remove(at: index)
    }

    private mutating func consolidate() {
        var result: [ExcludedCalendarEntry] = []
        for var candidate in exclusions {
            if result.contains(where: { $0.scope == .event && Self.sameEvent($0.entry, candidate.entry) }) { continue }
            if candidate.scope == .event {
                // Widen an occurrence exclusion in place instead of requiring
                // the user to restore several overlapping rules later.
                if let first = result.first(where: { Self.sameEvent($0.entry, candidate.entry) }) {
                    candidate.id = first.id
                }
                result.removeAll { Self.sameEvent($0.entry, candidate.entry) }
            } else if result.contains(where: { $0.scope == .occurrence && Self.sameOccurrence($0.entry, candidate.entry) }) {
                continue
            }
            result.append(candidate)
        }
        exclusions = result
    }

    private static func matches(_ exclusion: ExcludedCalendarEntry, _ entry: ScheduleEntry) -> Bool {
        switch exclusion.scope {
        case .event: sameEvent(exclusion.entry, entry)
        case .occurrence: sameOccurrence(exclusion.entry, entry)
        }
    }

    private static func sameEvent(_ lhs: ScheduleEntry, _ rhs: ScheduleEntry) -> Bool {
        if let left = nonempty(lhs.calendarEventKey), let right = nonempty(rhs.calendarEventKey) { return left == right }
        return sameSource(lhs, rhs)
    }

    private static func sameOccurrence(_ lhs: ScheduleEntry, _ rhs: ScheduleEntry) -> Bool {
        if let left = nonempty(lhs.calendarOccurrenceKey), let right = nonempty(rhs.calendarOccurrenceKey) { return left == right }
        return sameSource(lhs, rhs)
    }

    private static func sameSource(_ lhs: ScheduleEntry, _ rhs: ScheduleEntry) -> Bool {
        guard let left = nonempty(lhs.calendarSourceKey), let right = nonempty(rhs.calendarSourceKey) else { return false }
        return left == right
    }

    private static func hasCalendarIdentity(_ entry: ScheduleEntry) -> Bool {
        nonempty(entry.calendarSourceKey) != nil || nonempty(entry.calendarEventKey) != nil || nonempty(entry.calendarOccurrenceKey) != nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func snapshotOrder(_ lhs: ScheduleEntry, _ rhs: ScheduleEntry) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.startMinutes != rhs.startMinutes { return lhs.startMinutes < rhs.startMinutes }
        if lhs.endMinutes != rhs.endMinutes { return lhs.endMinutes < rhs.endMinutes }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.location != rhs.location { return lhs.location < rhs.location }
        return (lhs.calendarSourceKey ?? "") < (rhs.calendarSourceKey ?? "")
    }
}
