import Foundation

/// Fictional snapshots and real temporary files only. No calendar or desktop access.
@main
@MainActor
enum PersistenceVerification {
    private static var checks = 0
    private static let fixtureID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
        print("PASS: \(message)")
    }

    private static func snapshot(_ title: String) -> SavedStudio {
        var configuration = WallpaperConfiguration()
        configuration.title = title
        return SavedStudio(entries: [.init(id: fixtureID, name: "Fictional class", day: 0,
                                          startMinutes: 600, endMinutes: 660)],
                           configuration: configuration,
                           automation: AutomationSettings(),
                           connection: .init(calendarIDs: ["fictional-study", "fictional-personal"],
                                             calendarNames: ["Study", "Personal"],
                                             weekStart: Date(timeIntervalSince1970: 1_788_739_200),
                                             timeZoneID: "Asia/Seoul", managedEntryKeys: ["entry-a", "entry-b"],
                                             includeWeekTitle: true),
                           calendarVisibility: CalendarVisibility())
    }

    private final class DiskSink {
        var writes: [Data] = []
        var times: [ContinuousClock.Instant] = []
        func write(_ data: Data, to url: URL) throws {
            try data.write(to: url, options: .atomic)
            writes.append(data)
            times.append(ContinuousClock.now)
        }
    }

    private static func read(_ url: URL) throws -> SavedStudio {
        try JSONDecoder().decode(SavedStudio.self, from: Data(contentsOf: url))
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(450))
    }

    private static func rapidTyping(_ root: URL) async throws {
        let url = root.appendingPathComponent("typing/studio.json")
        let sink = DiskSink()
        var errors = 0
        let store = StudioPersistence(url: url, onError: { _ in errors += 1 }, write: sink.write)
        for index in 1...20 {
            store.schedule(snapshot("Draft \(index)"))
            try await Task.sleep(for: .milliseconds(50))
        }
        try await settle()
        try expect(sink.writes.count == 1, "Twenty edits at 50 ms intervals produce one disk write")
        let saved = try read(url)
        try expect(saved.configuration.title == "Draft 20" && saved.isValid,
                   "A fresh disk read restores the final typed title and valid studio")
        try expect(errors == 0, "Successful deferred saving reports no errors")
        try await settle()
        try expect(sink.writes.count == 1, "Idle persistence does not repeat a completed write")
    }

    private static func immediateFlush(_ root: URL) async throws {
        let url = root.appendingPathComponent("flush/studio.json")
        let sink = DiskSink()
        let store = StudioPersistence(url: url, onError: { _ in }, write: sink.write)
        store.schedule(snapshot("Earlier text"))
        store.schedule(snapshot("Latest text before close"))
        try store.flush()
        let saved = try read(url)
        try expect(saved.configuration.title == "Latest text before close", "Close/quit flush writes the latest pending text immediately")
        try await settle()
        try expect(sink.writes.count == 1, "Flushing cancels the older delayed write")
        try store.flush()
        try expect(sink.writes.count == 1, "A second flush with no pending changes does not write")
    }

    private static func immediateChangesSupersedeText(_ root: URL) async throws {
        let url = root.appendingPathComponent("immediate/studio.json")
        let sink = DiskSink()
        let store = StudioPersistence(url: url, onError: { _ in }, write: sink.write)
        store.schedule(snapshot("Older scheduled text"))
        var latest = snapshot("Current text with event edit")
        latest.entries[0].name = "Edited fictional class"
        latest.receipt = .init(wallpaperFingerprint: "fictional-fingerprint", calendarFingerprint: "fictional-calendar",
                               appliedAt: Date(timeIntervalSince1970: 1_788_739_200), weekStart: latest.connection?.weekStart,
                               dayKey: "2026-09-07", targetDisplayID: "fictional-display")
        try store.saveImmediately(latest)
        try await settle()
        let saved = try read(url)
        try expect(saved.configuration.title == "Current text with event edit" && saved.entries[0].name == "Edited fictional class"
                   && saved.receipt?.wallpaperFingerprint == "fictional-fingerprint",
                   "An immediate event/automation snapshot retains current text, event, and receipt")
        try expect(sink.writes.count == 1, "An older scheduled snapshot cannot overwrite the immediate event/automation save")

        var newest = latest
        newest.configuration.title = "Text edited after automation"
        store.schedule(newest)
        try await settle()
        let final = try read(url)
        try expect(sink.writes.count == 2 && final.configuration.title == "Text edited after automation"
                   && final.receipt?.wallpaperFingerprint == "fictional-fingerprint",
                   "Newer text after an immediate save is retained with automation metadata")
    }

    private static func skipEquivalentSnapshots(_ root: URL) async throws {
        let url = root.appendingPathComponent("equivalent/studio.json")
        let sink = DiskSink()
        let store = StudioPersistence(url: url, onError: { _ in }, write: sink.write)
        var original = snapshot("Saved title")
        let ids = (0..<100).map { "fictional-calendar-\($0)" }
        original.connection?.calendarIDs = Set(ids)
        original.connection?.managedEntryKeys = Set(ids.map { "entry-\($0)" })
        try store.saveImmediately(original)
        for _ in 0..<10 {
            var equivalent = original
            equivalent.connection?.calendarIDs = Set(ids.reversed())
            equivalent.connection?.managedEntryKeys = Set(ids.reversed().map { "entry-\($0)" })
            equivalent.configuration.highlightedDay = 2
            equivalent.configuration.weekdayDateLabels = ["07", "08", "09", "10", "11", "12", "13"]
            try store.saveImmediately(equivalent)
        }
        try expect(sink.writes.count == 1, "Equal sets and unsaved derived date fields do not produce duplicate writes")
        store.schedule(snapshot("Temporary unsaved edit"))
        store.schedule(original)
        try await settle()
        try expect(sink.writes.count == 1, "Returning to the saved snapshot cancels an obsolete pending edit")

        let reopenedSink = DiskSink()
        let reopened = StudioPersistence(url: url, onError: { _ in }, write: reopenedSink.write)
        try reopened.saveImmediately(original)
        try expect(reopenedSink.writes.isEmpty, "Reopening an identical saved studio establishes a no-write baseline")
    }

    private static func failedWriteRetainsPending(_ root: URL) async throws {
        let blocker = root.appendingPathComponent("blocked")
        try Data("fictional blocking file".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("studio.json")
        var errors = 0
        let store = StudioPersistence(url: url, onError: { _ in errors += 1 })
        store.schedule(snapshot("Retained after failure"))
        try await settle()
        try expect(errors == 1 && !FileManager.default.fileExists(atPath: url.path), "A deferred filesystem failure is surfaced once")
        var flushFailed = false
        do { try store.flush() } catch { flushFailed = true }
        try expect(flushFailed, "A failed close/quit flush throws so its caller can retry or cancel")
        try await settle()
        try expect(errors == 1, "A failed write does not start a periodic retry timer")
        try FileManager.default.removeItem(at: blocker)
        try store.flush()
        let saved = try read(url)
        try expect(saved.configuration.title == "Retained after failure", "A successful retry saves the snapshot retained across write failures")
    }

    private static func newerSnapshotReplacesFailure(_ root: URL) async throws {
        let blocker = root.appendingPathComponent("replacement-blocked")
        try Data("fictional blocking file".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("studio.json")
        let store = StudioPersistence(url: url, onError: { _ in })
        var immediateFailed = false
        do { try store.saveImmediately(snapshot("Failed older immediate save")) }
        catch { immediateFailed = true }
        try expect(immediateFailed, "An immediate filesystem failure throws to its caller")
        store.schedule(snapshot("Newer replacement after failure"))
        try FileManager.default.removeItem(at: blocker)
        try store.flush()
        try await settle()
        let saved = try read(url)
        try expect(saved.configuration.title == "Newer replacement after failure", "A newer snapshot replaces a failed pending snapshot without stale overwrite")
    }

    private static func continuousTypingIsBounded(_ root: URL) async throws {
        let url = root.appendingPathComponent("continuous/studio.json")
        let sink = DiskSink()
        let store = StudioPersistence(url: url, onError: { _ in }, write: sink.write)
        let start = ContinuousClock.now
        store.schedule(snapshot("Continuous 0"))
        for index in 1...24 {
            try await Task.sleep(for: .milliseconds(100))
            store.schedule(snapshot("Continuous \(index)"))
        }
        try expect(!sink.writes.isEmpty, "Continuous typing is saved before the editing burst ends")
        let firstDelay = start.duration(to: sink.times[0])
        try expect(firstDelay >= .milliseconds(1_800) && firstDelay < .milliseconds(2_400),
                   "The first unsaved edit bounds continuous typing to about two seconds")
        try await settle()
        let saved = try read(url)
        try expect(sink.writes.count == 2 && saved.configuration.title == "Continuous 24",
                   "Continuous typing saves at its deadline and once more with the final text")
    }

    static func main() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("serein-persistence-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try await rapidTyping(root)
            try await immediateFlush(root)
            try await immediateChangesSupersedeText(root)
            try await skipEquivalentSnapshots(root)
            try await failedWriteRetainsPending(root)
            try await newerSnapshotReplacesFailure(root)
            try await continuousTypingIsBounded(root)
            print("Persistence verification passed: \(checks) checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
