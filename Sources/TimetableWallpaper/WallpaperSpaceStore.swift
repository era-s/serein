import Foundation

/// A pure, fail-closed adapter for known macOS 14, 15 and 26 wallpaper store
/// formats. Reading, backing up and replacing the actual store belong to the
/// desktop service; this type never touches the file system or running processes.
enum WallpaperSpaceStore {
    enum StoreError: LocalizedError {
        case unsupportedVersion(Int)
        case invalidImageURL
        case incompatibleStore(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "macOS \(version)의 모든 데스크톱 배경화면 형식은 아직 지원하지 않습니다."
            case .invalidImageURL:
                return "배경화면은 로컬 이미지 파일이어야 합니다."
            case .incompatibleStore(let detail):
                return "macOS 배경화면 설정 형식을 확인할 수 없어 기존 설정을 유지했습니다. (\(detail))"
            }
        }
    }

    static func replacingDesktop(
        in data: Data, imageURL: URL, now: Date, osMajorVersion: Int
    ) throws -> Data {
        try validateVersion(osMajorVersion)
        try validateImageURL(imageURL)
        var root = try validatedRoot(data)
        let originalRoot = root
        let makeSlot: ([String: Any]) throws -> [String: Any] = { original in
            var slot = original
            if slot["Type"] as? String == "linked" {
                // Linked is the effective screen saver, even if a stale Idle
                // selection remains from an earlier individual configuration.
                slot["Idle"] = slot["Linked"]
            }
            slot.removeValue(forKey: "Linked")
            slot["Desktop"] = try desktop(
                replacing: slot["Desktop"] as? [String: Any],
                imageURL: imageURL, now: now, osMajorVersion: osMajorVersion
            )
            slot["Type"] = slot["Idle"] == nil ? "desktop" : "individual"
            return slot
        }

        root["AllSpacesAndDisplays"] = try makeSlot(root["AllSpacesAndDisplays"] as! [String: Any])
        root["SystemDefault"] = try makeSlot(root["SystemDefault"] as! [String: Any])
        var displays = root["Displays"] as! [String: Any]
        for key in displays.keys.sorted() {
            displays[key] = try makeSlot(displays[key] as! [String: Any])
        }
        root["Displays"] = displays
        var spaces = root["Spaces"] as! [String: Any]
        for key in spaces.keys.sorted() {
            var space = spaces[key] as! [String: Any]
            space["Default"] = try makeSlot(space["Default"] as! [String: Any])
            var spaceDisplays = space["Displays"] as! [String: Any]
            for displayKey in spaceDisplays.keys.sorted() {
                spaceDisplays[displayKey] = try makeSlot(spaceDisplays[displayKey] as! [String: Any])
            }
            space["Displays"] = spaceDisplays
            spaces[key] = space
        }
        root["Spaces"] = spaces
        // Binary plist key ordering is an implementation detail of Foundation.
        // Keep already-correct bytes when an identical operation changes no
        // values, rather than rewriting merely because dictionaries reordered.
        if data.starts(with: Data("bplist00".utf8)), NSDictionary(dictionary: root).isEqual(to: originalRoot) {
            return data
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    /// True only when every stored desktop and both future-desktop fallbacks use
    /// the supplied image. A valid different wallpaper returns false; an unknown
    /// structure throws so a writer cannot mistake an unsupported format for a
    /// successfully applied wallpaper.
    static func hasDesktop(_ imageURL: URL, in data: Data, osMajorVersion: Int) throws -> Bool {
        try validateVersion(osMajorVersion)
        try validateImageURL(imageURL)
        let root = try validatedRoot(data)
        var slots = [root["AllSpacesAndDisplays"] as! [String: Any], root["SystemDefault"] as! [String: Any]]
        slots += (root["Displays"] as! [String: Any]).values.map { $0 as! [String: Any] }
        for value in (root["Spaces"] as! [String: Any]).values {
            let space = value as! [String: Any]
            slots.append(space["Default"] as! [String: Any])
            slots += (space["Displays"] as! [String: Any]).values.map { $0 as! [String: Any] }
        }
        return slots.allSatisfy { slot in
            guard let type = slot["Type"] as? String, type == "individual" || type == "desktop",
                  let desktop = slot["Desktop"] as? [String: Any],
                  let content = desktop["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]], choices.count == 1,
                  choices[0]["Provider"] as? String == "com.apple.wallpaper.choice.image"
            else { return false }
            if let shuffle = content["Shuffle"], (shuffle as? String) != "$null" { return false }
            let storedURL: String?
            if osMajorVersion == 26 {
                guard let configuration = choices[0]["Configuration"] as? Data,
                      let value = try? PropertyListSerialization.propertyList(from: configuration, options: [], format: nil),
                      let dictionary = value as? [String: Any], dictionary["type"] as? String == "imageFile",
                      let url = dictionary["url"] as? [String: Any]
                else { return false }
                storedURL = url["relative"] as? String
            } else {
                let files = choices[0]["Files"] as? [[String: Any]]
                storedURL = files?.count == 1 ? files?.first?["relative"] as? String : nil
            }
            guard let storedURL, let parsed = URL(string: storedURL), parsed.isFileURL else { return false }
            return parsed.standardizedFileURL == imageURL.standardizedFileURL
        }
    }

    private static func validateVersion(_ version: Int) throws {
        guard [14, 15, 26].contains(version) else { throw StoreError.unsupportedVersion(version) }
    }

    private static func validateImageURL(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path != "/",
              url.query == nil, url.fragment == nil,
              url.host == nil || url.host == "" || url.host == "localhost"
        else { throw StoreError.invalidImageURL }
    }

    private static func validatedRoot(_ data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw StoreError.incompatibleStore("property list")
        }
        guard let root = value as? [String: Any] else { throw StoreError.incompatibleStore("root") }
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Spaces", "Displays"] {
            guard root[key] is [String: Any] else { throw StoreError.incompatibleStore(key) }
        }
        try validateSlot(root["AllSpacesAndDisplays"] as! [String: Any], at: "AllSpacesAndDisplays", allowEmpty: true)
        try validateSlot(root["SystemDefault"] as! [String: Any], at: "SystemDefault")
        for (key, value) in root["Displays"] as! [String: Any] {
            guard let slot = value as? [String: Any] else { throw StoreError.incompatibleStore("Displays.\(key)") }
            try validateSlot(slot, at: "Displays.\(key)")
        }
        for (key, value) in root["Spaces"] as! [String: Any] {
            guard let space = value as? [String: Any],
                  let defaultSlot = space["Default"] as? [String: Any],
                  let displays = space["Displays"] as? [String: Any]
            else { throw StoreError.incompatibleStore("Spaces.\(key)") }
            try validateSlot(defaultSlot, at: "Spaces.\(key).Default")
            for (displayKey, displayValue) in displays {
                guard let slot = displayValue as? [String: Any]
                else { throw StoreError.incompatibleStore("Spaces.\(key).Displays.\(displayKey)") }
                try validateSlot(slot, at: "Spaces.\(key).Displays.\(displayKey)")
            }
        }
        return root
    }

    private static func validateSlot(_ slot: [String: Any], at path: String, allowEmpty: Bool = false) throws {
        if allowEmpty && slot.isEmpty { return }
        guard let type = slot["Type"] as? String, ["individual", "desktop", "idle", "linked"].contains(type)
        else { throw StoreError.incompatibleStore("\(path).Type") }
        let required = type == "idle" ? "Idle" : type == "linked" ? "Linked" : "Desktop"
        guard slot[required] is [String: Any] else { throw StoreError.incompatibleStore("\(path).\(required)") }
        for key in ["Desktop", "Idle", "Linked"] where slot[key] != nil {
            guard let content = slot[key] as? [String: Any] else { throw StoreError.incompatibleStore("\(path).\(key)") }
            try validateContent(content, at: "\(path).\(key)")
        }
    }

    private static func validateContent(_ block: [String: Any], at path: String) throws {
        guard let content = block["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]]
        else { throw StoreError.incompatibleStore("\(path).Content") }
        for choice in choices {
            guard let provider = choice["Provider"] as? String, !provider.isEmpty,
                  choice["Configuration"] is Data, choice["Files"] is [[String: Any]]
            else { throw StoreError.incompatibleStore("\(path).Content.Choices") }
        }
        for key in ["LastSet", "LastUse"] where block[key] != nil {
            guard block[key] is Date else { throw StoreError.incompatibleStore("\(path).\(key)") }
        }
        if let options = content["EncodedOptionValues"], !(options is Data), (options as? String) != "$null" {
            throw StoreError.incompatibleStore("\(path).Content.EncodedOptionValues")
        }
        if let shuffle = content["Shuffle"], !(shuffle is [String: Any]), (shuffle as? String) != "$null" {
            throw StoreError.incompatibleStore("\(path).Content.Shuffle")
        }
    }

    private static func desktop(
        replacing original: [String: Any]?, imageURL: URL, now: Date, osMajorVersion: Int
    ) throws -> [String: Any] {
        var desktop = original ?? [:]
        var content = desktop["Content"] as? [String: Any] ?? [:]
        let configuration: [String: Any]
        let files: [[String: Any]]
        if osMajorVersion == 26 {
            configuration = ["type": "imageFile", "url": ["relative": imageURL.absoluteString]]
            files = []
            let options: [String: Any] = ["values": ["placement": ["picker": ["_0": ["id": "Crop"]]]]]
            content["EncodedOptionValues"] = try encodedPropertyList(options, reusing: content["EncodedOptionValues"])
        } else {
            // Sonoma/Sequoia image-provider format, documented in the 2024
            // MacScreensaverWallpaper.sh implementation:
            // https://gist.github.com/zaxbux/2ede5e3bc73156df63224bf8cd35f075
            // The color
            // space itself is a binary-plist string nested inside Configuration.
            let colorSpace = try PropertyListSerialization.data(fromPropertyList: "kCGColorSpaceGenericRGB", format: .binary, options: 0)
            configuration = ["placement": 1, "backgroundColor": ["colorSpace": colorSpace, "components": [0.0, 0.0, 0.0, 1.0]]]
            files = [["relative": imageURL.absoluteString]]
            content.removeValue(forKey: "EncodedOptionValues")
        }
        let previousChoices = content["Choices"] as? [[String: Any]]
        let encoded = try encodedPropertyList(configuration, reusing: previousChoices?.first?["Configuration"])
        content["Choices"] = [["Provider": "com.apple.wallpaper.choice.image", "Configuration": encoded, "Files": files]]
        content["Shuffle"] = "$null"
        desktop["Content"] = content
        desktop["LastSet"] = now
        desktop["LastUse"] = now
        return desktop
    }

    private static func encodedPropertyList(_ dictionary: [String: Any], reusing original: Any?) throws -> Data {
        if let data = original as? Data,
           let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let existing = value as? [String: Any],
           NSDictionary(dictionary: existing).isEqual(to: dictionary) {
            return data
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    }
}
