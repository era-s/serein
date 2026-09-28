import Foundation

/// Owns the newest unsaved studio on the main actor, so delayed text saves cannot
/// overtake immediate event edits or automation receipts.
@MainActor
final class StudioPersistence {
    private let url: URL
    private let onError: (Error) -> Void
    private let write: (Data, URL) throws -> Void
    private var lastSaved: SavedStudio?
    private var pending: SavedStudio?
    private var firstPendingAt: ContinuousClock.Instant?
    private var saveTask: Task<Void, Never>?

    init(url: URL, onError: @escaping (Error) -> Void,
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.url = url
        self.onError = onError
        self.write = write
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(SavedStudio.self, from: data), saved.isValid {
            lastSaved = saved
        }
    }

    deinit { saveTask?.cancel() }

    func schedule(_ snapshot: SavedStudio) {
        if let lastSaved, Self.equivalent(snapshot, lastSaved) {
            clearPending()
            return
        }
        pending = snapshot
        let now = ContinuousClock.now
        let first = firstPendingAt ?? now
        firstPendingAt = first
        let deadline = min(now.advanced(by: .milliseconds(300)), first.advanced(by: .seconds(2)))
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            guard !Task.isCancelled else { return }
            do { try self?.flush() }
            catch { self?.onError(error) }
        }
    }

    /// Errors from explicit saves/flushes are handled by the caller, allowing
    /// close or termination to offer retry/cancel. Deferred errors use onError.
    func saveImmediately(_ snapshot: SavedStudio) throws {
        pending = snapshot
        firstPendingAt = firstPendingAt ?? ContinuousClock.now
        try flush()
    }

    func flush() throws {
        saveTask?.cancel()
        saveTask = nil
        guard let snapshot = pending else { return }
        if let lastSaved, Self.equivalent(snapshot, lastSaved) {
            clearPending()
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(data, url)
        // Keep pending intact until the atomic write succeeds. No suspension
        // occurs between taking the snapshot and marking it saved.
        lastSaved = snapshot
        clearPending()
    }

    private func clearPending() {
        saveTask?.cancel()
        saveTask = nil
        pending = nil
        firstPendingAt = nil
    }

    private static func equivalent(_ lhs: SavedStudio, _ rhs: SavedStudio) -> Bool {
        var leftConfiguration = lhs.configuration
        var rightConfiguration = rhs.configuration
        // Match SavedStudio.encode's omission of transient render inputs.
        leftConfiguration.highlightedDay = nil
        rightConfiguration.highlightedDay = nil
        leftConfiguration.weekdayDateLabels = nil
        rightConfiguration.weekdayDateLabels = nil
        return lhs.version == rhs.version && lhs.entries == rhs.entries
            && leftConfiguration == rightConfiguration && lhs.automation == rhs.automation
            && lhs.connection == rhs.connection && lhs.receipt == rhs.receipt
            && lhs.calendarVisibility == rhs.calendarVisibility
    }
}
