import AppKit
import CoreGraphics
import CryptoKit

@MainActor
struct WallpaperDesktopService {
    static func identifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var displays: [WallpaperDisplay] {
        NSScreen.screens.compactMap { screen in
            identifier(for: screen).map { WallpaperDisplay(id: $0, name: screen.localizedName) }
        }
    }

    static func apply(entries: [ScheduleEntry], configuration: WallpaperConfiguration, displayID: String) throws {
        let allSpaces = displayID == WallpaperDisplay.allSpacesID
        let screen = NSScreen.screens.first(where: { identifier(for: $0) == displayID })
        guard allSpaces || screen != nil else { throw DesktopError.disconnected }
        let data = try WallpaperRenderer.pngData(entries: entries, configuration: configuration)
        let directory = AppStore.supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent("serein-\(hash).png")
        // Reuse identical output; retain older images because other Spaces may still use them.
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        if allSpaces {
            try WallpaperStoreWriter.apply(imageURL: url, storeURL: WallpaperStoreWriter.systemStoreURL,
                backupDirectory: AppStore.supportDirectory.appendingPathComponent("WallpaperBackups", isDirectory: true),
                osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                agent: SystemWallpaperAgent())
        } else if let screen {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true
            ])
        }
    }

    enum DesktopError: LocalizedError {
        case disconnected
        var errorDescription: String? { "선택한 디스플레이가 연결되어 있지 않습니다. 다시 연결하거나 자동화에서 적용 대상을 선택해주세요." }
    }
}
