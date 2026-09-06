import Foundation
import CryptoKit
import Darwin

protocol WallpaperAgentControlling {
    func suspend() throws
    func resume()
    func reload() throws
}

/// Owns the native store transaction; the transformer itself has no side effects.
/// This adapter is deliberately separate from NSWorkspace, which disables the
/// shared-Spaces setting when setting an image for a specific NSScreen.
struct WallpaperStoreWriter {
    static var systemStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    static func apply(imageURL: URL, storeURL: URL, backupDirectory: URL,
                      osMajorVersion: Int, agent: any WallpaperAgentControlling,
                      now: Date = Date()) throws {
        guard imageURL.isFileURL, FileManager.default.isReadableFile(atPath: imageURL.path) else {
            throw WriteError.imageUnavailable
        }
        // Reject an unknown schema before touching the running wallpaper service.
        let initial = try Data(contentsOf: storeURL)
        _ = try WallpaperSpaceStore.replacingDesktop(in: initial, imageURL: imageURL, now: now, osMajorVersion: osMajorVersion)
        defer { agent.resume() }
        try agent.suspend()
        let original = try Data(contentsOf: storeURL)
        let replacement = try WallpaperSpaceStore.replacingDesktop(in: original, imageURL: imageURL, now: now, osMajorVersion: osMajorVersion)
        let manager = FileManager.default
        try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let backup = backupDirectory.appendingPathComponent("before-all-spaces-\(hash).plist")
        if !manager.fileExists(atPath: backup.path) {
            try original.write(to: backup, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        let permissions = (try manager.attributesOfItem(atPath: storeURL.path))[.posixPermissions]
        guard try Data(contentsOf: storeURL) == original else { throw WriteError.concurrentChange }
        var wroteReplacement = false
        do {
            try replacement.write(to: storeURL, options: .atomic)
            wroteReplacement = true
            if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: storeURL.path) }
            guard try WallpaperSpaceStore.hasDesktop(imageURL, in: Data(contentsOf: storeURL), osMajorVersion: osMajorVersion) else {
                throw WriteError.verificationFailed
            }
            try agent.reload()
            guard try WallpaperSpaceStore.hasDesktop(imageURL, in: Data(contentsOf: storeURL), osMajorVersion: osMajorVersion) else {
                throw WriteError.verificationFailed
            }
        } catch {
            // Never overwrite an intervening edit by another process. Restore
            // only the exact bytes we wrote; retain the original backup either way.
            if wroteReplacement, (try? Data(contentsOf: storeURL)) == replacement {
                try? original.write(to: storeURL, options: .atomic)
                if let permissions { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: storeURL.path) }
                try? agent.reload()
            }
            throw error
        }
    }

    enum WriteError: LocalizedError {
        case imageUnavailable, concurrentChange, verificationFailed, agentUnavailable, agentSignal, agentRestart
        var errorDescription: String? {
            switch self {
            case .imageUnavailable: "적용할 PNG 파일을 읽을 수 없습니다."
            case .concurrentChange: "다른 앱이 배경화면 설정을 변경했습니다. 잠시 후 다시 적용해주세요."
            case .verificationFailed: "모든 데스크탑의 배경화면 설정을 확인하지 못했습니다. 원본 설정은 Serein의 WallpaperBackups 폴더에 보관했습니다."
            case .agentUnavailable: "macOS 배경화면 서비스를 찾을 수 없습니다. 로그인 상태를 확인한 뒤 다시 시도해주세요."
            case .agentSignal: "macOS 배경화면 서비스를 갱신하지 못했습니다. 잠시 후 다시 시도해주세요."
            case .agentRestart: "macOS 배경화면 서비스가 다시 시작되지 않았습니다. 잠시 후 다시 적용해주세요."
            }
        }
    }
}

final class SystemWallpaperAgent: WallpaperAgentControlling {
    private var suspended: [pid_t] = []
    deinit { resume() }

    func suspend() throws {
        let pids = try runningPIDs()
        guard !pids.isEmpty else { throw WallpaperStoreWriter.WriteError.agentUnavailable }
        for pid in pids {
            guard kill(pid, SIGSTOP) == 0 else { resume(); throw WallpaperStoreWriter.WriteError.agentSignal }
            suspended.append(pid)
        }
    }

    func resume() {
        for pid in suspended { _ = kill(pid, SIGCONT) }
        suspended.removeAll()
    }

    func reload() throws {
        let pids = suspended.isEmpty ? try runningPIDs() : suspended
        guard !pids.isEmpty else { throw WallpaperStoreWriter.WriteError.agentUnavailable }
        // Queue termination before resuming so the old in-memory store does not
        // get a chance to process a file-change notification over the new file.
        for pid in pids {
            if kill(pid, SIGTERM) != 0 && errno != ESRCH {
                resume()
                throw WallpaperStoreWriter.WriteError.agentSignal
            }
        }
        resume()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if pids.allSatisfy({ kill($0, 0) != 0 }) {
                let newPIDs = try runningPIDs()
                if !newPIDs.isEmpty {
                    // Let the restarted service load/canonicalize its store.
                    Thread.sleep(forTimeInterval: 0.15)
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw WallpaperStoreWriter.WriteError.agentRestart
    }

    private func runningPIDs() throws -> [pid_t] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // Affect only the logged-in user's wallpaper service, never other users.
        process.arguments = ["-u", String(getuid()), "-x", "WallpaperAgent"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw WallpaperStoreWriter.WriteError.agentUnavailable
        }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }.filter { $0 > 1 }
    }
}
