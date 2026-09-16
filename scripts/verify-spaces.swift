import Foundation

/// Synthetic fixtures only. File transactions use a disposable temporary folder
/// and a fake agent; this executable never reads a real wallpaper store, touches
/// user preferences, launches system services, or changes a desktop.
@main
enum SpaceStoreVerification {
    private static var checks = 0
    private static let moment = Date(timeIntervalSince1970: 1_789_000_000)
    private static let firstImage = URL(fileURLWithPath: "/synthetic/한 주의 시간표 🌿/Serein wallpaper.png")
    private static let secondImage = URL(fileURLWithPath: "/synthetic/next week/second.png")

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }

    private static func expectThrows(_ message: String, _ action: () throws -> Void) {
        do { try action(); fatalError("FAIL: \(message)") }
        catch { checks += 1; print("PASS: \(message)") }
    }

    private static func encode(_ value: Any, format: PropertyListSerialization.PropertyListFormat = .binary) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            fatalError("Fixture was not a dictionary")
        }
        return result
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        guard let result = value as? [String: Any] else { fatalError("Missing fixture dictionary") }
        return result
    }

    private static func content(_ label: String) -> [String: Any] {
        ["Content": ["Choices": [["Provider": "synthetic.\(label)", "Configuration": Data([0, 1, 2]),
                                    "Files": [["relative": "file:///synthetic/old-\(label).png"]],
                                    "ChoiceMetadata": ["keep": label]]],
                     "ContentMetadata": ["opaque": label]],
         "LastSet": Date(timeIntervalSince1970: 100), "LastUse": Date(timeIntervalSince1970: 200),
         "BlockMetadata": "\(label)-metadata"]
    }

    private static func slot(_ label: String, kind: String = "individual", idle: Bool = true) -> [String: Any] {
        var result: [String: Any] = ["Type": kind, "SlotMetadata": label]
        if kind == "linked" { result["Linked"] = content("linked-\(label)") }
        else if kind == "individual" || kind == "desktop" { result["Desktop"] = content(label) }
        if idle { result["Idle"] = content(kind == "linked" ? "linked-\(label)" : "idle-\(label)") }
        return result
    }

    private static func fixture() -> [String: Any] {
        ["AllSpacesAndDisplays": slot("global"),
         "SystemDefault": slot("system"),
         "Displays": ["display-A": slot("display-A"), "display-B": slot("display-B")],
         "Spaces": [
            "space-1": ["Default": slot("space-1-default"),
                        "Displays": ["display-A": slot("space-1-A"), "display-B": slot("space-1-B")],
                        "SpaceMetadata": ["keep": 17]],
            "space-2": ["Default": slot("space-2-default"),
                        "Displays": ["display-A": slot("space-2-A")],
                        "SpaceMetadata": ["keep": 23]],
            "space-empty": ["Default": slot("space-empty-default"), "Displays": [String: Any]()]
         ],
         "Idle": ["opaque": Data([9, 8, 7])],
         "RootMetadata": ["keep": [1, 2, 3]]]
    }

    private static func slots(_ root: [String: Any]) -> [(String, [String: Any])] {
        var result = [("global", dictionary(root["AllSpacesAndDisplays"])), ("system", dictionary(root["SystemDefault"]))]
        for (id, slot) in dictionary(root["Displays"]).sorted(by: { $0.key < $1.key }) {
            result.append(("display/\(id)", dictionary(slot)))
        }
        for (id, value) in dictionary(root["Spaces"]).sorted(by: { $0.key < $1.key }) {
            let space = dictionary(value)
            result.append(("space/\(id)/default", dictionary(space["Default"])))
            for (displayID, slot) in dictionary(space["Displays"]).sorted(by: { $0.key < $1.key }) {
                result.append(("space/\(id)/\(displayID)", dictionary(slot)))
            }
        }
        return result
    }

    private static func imageString(_ slot: [String: Any], os: Int) throws -> String {
        let desktop = dictionary(slot["Desktop"])
        let content = dictionary(desktop["Content"])
        guard let choices = content["Choices"] as? [[String: Any]], choices.count == 1 else { fatalError("Expected a single image choice") }
        if os == 26 || os == 27 {
            let configuration = try decode(choices[0]["Configuration"] as! Data)
            expect(configuration["type"] as? String == "imageFile", "Modern desktop configuration identifies an image file")
            expect((choices[0]["Files"] as? [[String: Any]])?.isEmpty == true, "Modern image provider has no legacy file entries")
            return dictionary(configuration["url"])["relative"] as! String
        }
        return (choices[0]["Files"] as! [[String: Any]])[0]["relative"] as! String
    }

    private static func replacingSlot(_ name: String, with value: [String: Any], in source: [String: Any]) -> [String: Any] {
        var root = source
        if name == "global" { root["AllSpacesAndDisplays"] = value }
        else if name == "system" { root["SystemDefault"] = value }
        else {
            let path = name.split(separator: "/").map(String.init)
            if path[0] == "display" {
                var displays = dictionary(root["Displays"])
                displays[path[1]] = value
                root["Displays"] = displays
            } else {
                var spaces = dictionary(root["Spaces"])
                var space = dictionary(spaces[path[1]])
                if path[2] == "default" { space["Default"] = value }
                else {
                    var displays = dictionary(space["Displays"])
                    displays[path[2]] = value
                    space["Displays"] = displays
                }
                spaces[path[1]] = space
                root["Spaces"] = spaces
            }
        }
        return root
    }

    private static func verifyAllDestinations(os: Int) throws {
        let original = fixture()
        let input = try encode(original, format: .xml)
        let output = try WallpaperSpaceStore.replacingDesktop(in: input, imageURL: firstImage, now: moment, osMajorVersion: os)
        let root = try decode(output)
        expect(output.starts(with: Data("bplist00".utf8)), "macOS \(os): output is a binary property list")
        expect(try WallpaperSpaceStore.hasDesktop(firstImage, in: output, osMajorVersion: os), "macOS \(os): every desktop destination uses the requested image")
        expect(!(try WallpaperSpaceStore.hasDesktop(secondImage, in: output, osMajorVersion: os)), "macOS \(os): another image does not pass verification")
        expect(NSDictionary(dictionary: dictionary(root["RootMetadata"])).isEqual(to: dictionary(original["RootMetadata"])), "macOS \(os): unknown root metadata survives")
        expect(NSDictionary(dictionary: dictionary(root["Idle"])).isEqual(to: dictionary(original["Idle"])), "macOS \(os): root screen saver data survives unchanged")
        let originals = Dictionary(uniqueKeysWithValues: slots(original))
        for (name, slot) in slots(root) {
            let before = originals[name]!
            expect(slot["Type"] as? String == "individual", "macOS \(os): \(name) is an individual desktop")
            expect(try imageString(slot, os: os) == firstImage.absoluteString, "macOS \(os): \(name) uses an encoded Unicode and space file URL")
            expect(slot["SlotMetadata"] as? String == before["SlotMetadata"] as? String, "macOS \(os): \(name) retains unknown slot metadata")
            expect(NSDictionary(dictionary: dictionary(slot["Idle"])).isEqual(to: dictionary(before["Idle"])), "macOS \(os): \(name) leaves the screen saver untouched")
            let desktop = dictionary(slot["Desktop"])
            let oldDesktop = dictionary(before["Desktop"])
            expect(desktop["BlockMetadata"] as? String == oldDesktop["BlockMetadata"] as? String, "macOS \(os): \(name) retains unknown desktop metadata")
            expect(NSDictionary(dictionary: dictionary(dictionary(desktop["Content"])["ContentMetadata"])).isEqual(to: dictionary(dictionary(oldDesktop["Content"])["ContentMetadata"])), "macOS \(os): \(name) retains unknown desktop content metadata")
            let mismatching = replacingSlot(name, with: before, in: root)
            expect(!(try WallpaperSpaceStore.hasDesktop(firstImage, in: encode(mismatching), osMajorVersion: os)), "macOS \(os): verification catches one stale destination at \(name)")
        }
        let spaces = dictionary(root["Spaces"])
        expect(NSDictionary(dictionary: dictionary(dictionary(spaces["space-1"])["SpaceMetadata"])).isEqual(to: ["keep": 17]), "macOS \(os): unknown per-space metadata survives")
        let repeated = try WallpaperSpaceStore.replacingDesktop(in: output, imageURL: firstImage, now: moment, osMajorVersion: os)
        expect(repeated == output, "macOS \(os): applying identical inputs is byte-idempotent")
        let replacement = try WallpaperSpaceStore.replacingDesktop(in: output, imageURL: secondImage, now: moment.addingTimeInterval(60), osMajorVersion: os)
        let replacementRoot = try decode(replacement)
        expect(try WallpaperSpaceStore.hasDesktop(secondImage, in: replacement, osMajorVersion: os), "macOS \(os): a later wallpaper replaces every destination")
        expect(!(try WallpaperSpaceStore.hasDesktop(firstImage, in: replacement, osMajorVersion: os)), "macOS \(os): the earlier desktop image no longer passes verification")
        expect(try slots(replacementRoot).allSatisfy { try imageString($0.1, os: os) == secondImage.absoluteString }, "macOS \(os): no active desktop slot retains the earlier file URL")

        var inherited = root
        inherited["Spaces"] = [String: Any]()
        inherited["Displays"] = [String: Any]()
        let inheritedData = try encode(inherited)
        expect(try WallpaperSpaceStore.hasDesktop(firstImage, in: inheritedData, osMajorVersion: os), "macOS \(os): defaults cover a fresh space without explicit overrides")
    }

    private static func verifyMigration() throws {
        for kind in ["linked", "idle"] {
            var root = fixture()
            let previous = slot("migration", kind: kind, idle: kind == "idle")
            root["AllSpacesAndDisplays"] = previous
            let output = try WallpaperSpaceStore.replacingDesktop(in: encode(root), imageURL: firstImage, now: moment, osMajorVersion: 26)
            let migrated = dictionary(try decode(output)["AllSpacesAndDisplays"])
            expect(migrated["Type"] as? String == "individual", "\(kind) slot becomes an independent desktop slot")
            expect(migrated["Linked"] == nil, "\(kind) migration does not leave a linked desktop override")
            expect(NSDictionary(dictionary: dictionary(migrated["Idle"])).isEqual(to: dictionary(previous[kind == "linked" ? "Linked" : "Idle"])), "\(kind) migration preserves the former screen saver contents")
            expect(try WallpaperSpaceStore.hasDesktop(firstImage, in: output, osMajorVersion: 26), "\(kind) migration still verifies across every space")
        }
        var equivalent = fixture()
        equivalent["SystemDefault"] = slot("matching-linked", kind: "linked", idle: true)
        let result = try WallpaperSpaceStore.replacingDesktop(in: encode(equivalent), imageURL: firstImage, now: moment, osMajorVersion: 26)
        expect(try WallpaperSpaceStore.hasDesktop(firstImage, in: result, osMajorVersion: 26), "Equivalent Linked and Idle blocks can safely migrate")

        var stale = fixture()
        var linked = slot("active-linked", kind: "linked", idle: false)
        linked["Idle"] = content("stale-idle")
        stale["SystemDefault"] = linked
        let staleOutput = try WallpaperSpaceStore.replacingDesktop(in: encode(stale), imageURL: firstImage, now: moment, osMajorVersion: 26)
        let migrated = dictionary(try decode(staleOutput)["SystemDefault"])
        expect(NSDictionary(dictionary: dictionary(migrated["Idle"])).isEqual(to: dictionary(linked["Linked"])), "Active linked content supersedes a stale idle block during migration")
        expect(migrated["Linked"] == nil, "Migrated linked content is not left as a desktop override")

        var desktopOnly = fixture()
        desktopOnly["AllSpacesAndDisplays"] = [String: Any]()
        desktopOnly["SystemDefault"] = slot("desktop-only", kind: "desktop", idle: false)
        let desktopOutput = try WallpaperSpaceStore.replacingDesktop(in: encode(desktopOnly), imageURL: firstImage, now: moment, osMajorVersion: 26)
        let desktopRoot = try decode(desktopOutput)
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            let value = dictionary(desktopRoot[key])
            expect(value["Type"] as? String == "desktop", "\(key) without a screen saver stays desktop-only")
            expect(value["Idle"] == nil, "\(key) does not gain an unsolicited screen saver")
        }
        expect(try WallpaperSpaceStore.hasDesktop(firstImage, in: desktopOutput, osMajorVersion: 26), "An empty global default and desktop-only system default normalize to the requested image")
    }

    private static func verifyFailures() throws {
        let input = try encode(fixture())
        for os in [0, 13, 16, 25, 28, 99] {
            expectThrows("Unsupported macOS \(os) is rejected before changing any data") {
                _ = try WallpaperSpaceStore.replacingDesktop(in: input, imageURL: firstImage, now: moment, osMajorVersion: os)
            }
        }
        expectThrows("An HTTPS image cannot be written as a local wallpaper") {
            _ = try WallpaperSpaceStore.replacingDesktop(in: input, imageURL: URL(string: "https://example.invalid/wallpaper.png")!, now: moment, osMajorVersion: 26)
        }
        expectThrows("Corrupt input is rejected") {
            _ = try WallpaperSpaceStore.replacingDesktop(in: Data([0, 1, 2]), imageURL: firstImage, now: moment, osMajorVersion: 26)
        }
        expectThrows("An array root is rejected") {
            _ = try WallpaperSpaceStore.replacingDesktop(in: encode(["wrong"]), imageURL: firstImage, now: moment, osMajorVersion: 26)
        }

        var invalidCases: [(String, [String: Any])] = []
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Displays", "Spaces"] {
            var missing = fixture(); missing.removeValue(forKey: key)
            invalidCases.append(("Missing required root \(key)", missing))
            var wrongType = fixture(); wrongType[key] = "unsupported"
            invalidCases.append(("Wrong root type for \(key)", wrongType))
        }
        var root = fixture(); root["Displays"] = ["display-A": "unsupported"]
        invalidCases.append(("Malformed display slot", root))
        root = fixture(); root["Spaces"] = ["space-1": ["Default": slot("valid")]]
        invalidCases.append(("Space missing display map", root))
        root = fixture(); root["Spaces"] = ["space-1": ["Displays": [String: Any]()]]
        invalidCases.append(("Space missing default slot", root))
        for (description, malformed) in [
            ("Unknown slot type", ["Type": "future"]),
            ("Individual slot without desktop", ["Type": "individual"]),
            ("Idle slot without screen saver", ["Type": "idle"]),
            ("Linked slot without content", ["Type": "linked"]),
            ("Desktop lacking content", ["Type": "individual", "Desktop": ["anything": "else"]]),
            ("Desktop with malformed choices", ["Type": "individual", "Desktop": ["Content": ["Choices": "wrong"]]]),
            ("Desktop provider missing", ["Type": "individual", "Desktop": ["Content": ["Choices": [["Configuration": Data(), "Files": [Any]()]]]]]),
            ("Desktop configuration wrong type", ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "synthetic", "Configuration": "wrong", "Files": [Any]()]]]]]),
            ("Desktop files wrong type", ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "synthetic", "Configuration": Data(), "Files": "wrong"]]]]]),
            ("Desktop timestamp wrong type", ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "synthetic", "Configuration": Data(), "Files": [Any]()]]], "LastSet": "wrong"]])
        ] as [(String, [String: Any])] {
            root = fixture(); root["AllSpacesAndDisplays"] = malformed
            invalidCases.append((description, root))
        }
        for (description, malformed) in invalidCases {
            expectThrows("\(description) is rejected") {
                _ = try WallpaperSpaceStore.replacingDesktop(in: encode(malformed), imageURL: firstImage, now: moment, osMajorVersion: 26)
            }
        }
    }

    private final class FakeAgent: WallpaperAgentControlling {
        var suspendCount = 0
        var resumeCount = 0
        var reloadCount = 0
        var onSuspend: (() throws -> Void)?
        var onReload: ((Int) throws -> Void)?

        func suspend() throws { suspendCount += 1; try onSuspend?() }
        func resume() { resumeCount += 1 }
        func reload() throws { reloadCount += 1; try onReload?(reloadCount) }
    }

    private enum InjectedError: Error { case suspend, reload }

    private struct TransactionFixture {
        var directory: URL
        var image: URL
        var store: URL
        var backups: URL
        var original: Data
    }

    private static func withTransaction(_ body: (TransactionFixture) throws -> Void) throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("serein-spaces-test-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        let image = directory.appendingPathComponent("합성 시간표 🌿.png")
        let store = directory.appendingPathComponent("Synthetic-Index.plist")
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        let original = try encode(fixture())
        try Data("Synthetic image bytes; renderer is tested separately".utf8).write(to: image)
        try original.write(to: store)
        try manager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: store.path)
        try body(.init(directory: directory, image: image, store: store, backups: backups, original: original))
    }

    private static func write(_ fixture: TransactionFixture, agent: FakeAgent, os: Int) throws {
        try WallpaperStoreWriter.apply(imageURL: fixture.image, storeURL: fixture.store,
                                       backupDirectory: fixture.backups, osMajorVersion: os,
                                       agent: agent, now: moment)
    }

    private static func permissions(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    private static func verifyTransactions(os: Int) throws {
        try withTransaction { fixture in
            let agent = FakeAgent()
            try write(fixture, agent: agent, os: os)
            let output = try Data(contentsOf: fixture.store)
            expect(try WallpaperSpaceStore.hasDesktop(fixture.image, in: output, osMajorVersion: os), "Transaction writes the wallpaper to every stored desktop")
            expect(agent.suspendCount == 1 && agent.reloadCount == 1 && agent.resumeCount == 1, "Successful transaction suspends, reloads and resumes the injected agent")
            expect(try permissions(fixture.store) == 0o640, "Atomic replacement retains original store permissions")
            let backups = try FileManager.default.contentsOfDirectory(at: fixture.backups, includingPropertiesForKeys: nil)
            expect(backups.count == 1, "Transaction creates exactly one original backup")
            expect(try Data(contentsOf: backups[0]) == fixture.original, "Backup retains exact original bytes")
            expect(try permissions(backups[0]) == 0o600, "Original backup is readable only by its owner")
            expect(backups[0].lastPathComponent.hasPrefix("before-all-spaces-") && backups[0].pathExtension == "plist", "Backup is an identifiable version of the original property list")
            let outputRoot = try decode(output)
            let originalRoot = try decode(fixture.original)
            expect(NSDictionary(dictionary: dictionary(outputRoot["Idle"])).isEqual(to: dictionary(originalRoot["Idle"])), "File transaction preserves global screen saver settings")
        }

        try withTransaction { fixture in
            let malformed = Data("not a property list".utf8)
            try malformed.write(to: fixture.store)
            let agent = FakeAgent()
            expectThrows("Malformed store is rejected before suspending the agent") { try write(fixture, agent: agent, os: os) }
            expect(agent.suspendCount == 0 && agent.resumeCount == 0 && agent.reloadCount == 0, "Malformed preflight never interacts with an agent")
            expect(try Data(contentsOf: fixture.store) == malformed, "Malformed preflight leaves original bytes untouched")
            expect(!FileManager.default.fileExists(atPath: fixture.backups.path), "Malformed preflight does not create a misleading backup")
        }

        try withTransaction { fixture in
            try FileManager.default.removeItem(at: fixture.image)
            let agent = FakeAgent()
            expectThrows("Missing image is rejected before suspending the agent") { try write(fixture, agent: agent, os: os) }
            expect(agent.suspendCount == 0 && agent.resumeCount == 0 && agent.reloadCount == 0, "Missing image never interacts with an agent")
            expect(try Data(contentsOf: fixture.store) == fixture.original, "Missing image leaves the store unchanged")
        }

        try withTransaction { fixture in
            let agent = FakeAgent()
            agent.onSuspend = { throw InjectedError.suspend }
            expectThrows("Suspension failure aborts the transaction") { try write(fixture, agent: agent, os: os) }
            expect(agent.suspendCount == 1 && agent.resumeCount == 1 && agent.reloadCount == 0, "Suspension failure still resumes any partially suspended agent")
            expect(try Data(contentsOf: fixture.store) == fixture.original, "Suspension failure leaves the original store unchanged")
            expect(!FileManager.default.fileExists(atPath: fixture.backups.path), "Suspension failure performs no file transaction")
        }

        try withTransaction { fixture in
            let agent = FakeAgent()
            agent.onReload = { invocation in if invocation == 1 { throw InjectedError.reload } }
            expectThrows("Reload failure is reported") { try write(fixture, agent: agent, os: os) }
            expect(try Data(contentsOf: fixture.store) == fixture.original, "Reload failure rolls back the exact bytes written by this transaction")
            expect(try permissions(fixture.store) == 0o640, "Rollback retains original store permissions")
            expect(agent.reloadCount == 2 && agent.resumeCount == 1, "Rollback reloads the restored store and resumes the agent")
            let backups = try FileManager.default.contentsOfDirectory(at: fixture.backups, includingPropertiesForKeys: nil)
            expect(backups.count == 1, "Reload failure retains a single recovery backup")
            expect(try Data(contentsOf: backups[0]) == fixture.original, "Reload failure retains the original recovery backup bytes")
        }

        try withTransaction { fixture in
            let external = try WallpaperSpaceStore.replacingDesktop(in: fixture.original, imageURL: secondImage,
                                                                   now: moment.addingTimeInterval(1), osMajorVersion: os)
            let agent = FakeAgent()
            agent.onReload = { _ in
                try external.write(to: fixture.store, options: .atomic)
                throw InjectedError.reload
            }
            expectThrows("Reload failure after an external edit is reported") { try write(fixture, agent: agent, os: os) }
            expect(try Data(contentsOf: fixture.store) == external, "Rollback never overwrites an intervening external change")
            expect(agent.reloadCount == 1 && agent.resumeCount == 1, "External edit is preserved without a second rollback reload")
        }

        try withTransaction { fixture in
            let external = try WallpaperSpaceStore.replacingDesktop(in: fixture.original, imageURL: secondImage,
                                                                   now: moment.addingTimeInterval(1), osMajorVersion: os)
            let agent = FakeAgent()
            agent.onReload = { _ in try external.write(to: fixture.store, options: .atomic) }
            var verificationFailed = false
            do { try write(fixture, agent: agent, os: os) }
            catch WallpaperStoreWriter.WriteError.verificationFailed { verificationFailed = true }
            expect(verificationFailed, "A successful reload that leaves another wallpaper fails post-reload verification")
            expect(try Data(contentsOf: fixture.store) == external, "Post-reload verification failure preserves the intervening valid store")
            expect(agent.resumeCount == 1, "Verification failure always resumes the agent")
        }

        try withTransaction { fixture in
            // A regular file at the directory path is a deterministic failure,
            // independent of the invoking account's directory permissions.
            try Data("block backup creation".utf8).write(to: fixture.backups)
            let agent = FakeAgent()
            expectThrows("Backup directory failure aborts before replacing the store") { try write(fixture, agent: agent, os: os) }
            expect(try Data(contentsOf: fixture.store) == fixture.original, "Backup failure leaves the original store unchanged")
            expect(agent.suspendCount == 1 && agent.resumeCount == 1 && agent.reloadCount == 0, "Backup failure resumes the agent without reloading")
        }

        try withTransaction { fixture in
            let altered = Data("external unsupported format".utf8)
            let agent = FakeAgent()
            agent.onSuspend = { try altered.write(to: fixture.store) }
            expectThrows("Store is validated again after suspension") { try write(fixture, agent: agent, os: os) }
            expect(try Data(contentsOf: fixture.store) == altered, "A newly unsupported store is not overwritten using stale preflight bytes")
            expect(agent.resumeCount == 1 && agent.reloadCount == 0, "Second validation failure resumes the agent without reloading")
        }
    }

    static func main() throws {
        for os in [27, 14, 15, 26] { try verifyAllDestinations(os: os) }
        try verifyMigration()
        try verifyFailures()
        for os in [26, 27] { try verifyTransactions(os: os) }
        print("Verified \(checks) all-spaces wallpaper assertions using synthetic data and a fake agent only.")
    }
}
