import Combine
import Foundation

/// Refreshes the permission status without touching saved calendar selections or
/// imported entries. Only an explicit reconnect action may request access.
@MainActor
final class CalendarAccessRecovery: ObservableObject {
    @Published private(set) var access: CalendarAccess
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?

    private let provider: any CalendarProviding

    init(provider: any CalendarProviding) {
        self.provider = provider
        access = provider.access
    }

    /// Safe for activation, status displays and background calendar checks.
    func refreshStatus() {
        updateAccess()
        if access == .authorized, errorMessage != nil { errorMessage = nil }
    }

    private func updateAccess() {
        let current = provider.access
        if access != current { access = current }
    }

    /// Call only from the user's reconnect button. A successful result allows
    /// the owner to check its existing connection under the usual opt-in rules.
    func reconnect() async -> Bool {
        guard !isConnecting, !Task.isCancelled else { return false }
        isConnecting = true
        if errorMessage != nil { errorMessage = nil }
        defer {
            updateAccess()
            isConnecting = false
        }
        do {
            let granted = try await provider.requestAccess()
            guard !Task.isCancelled else { return false }
            updateAccess()
            guard granted, access == .authorized else { throw CalendarImportError.permissionDenied }
            return true
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                if errorMessage != error.localizedDescription { errorMessage = error.localizedDescription }
            }
            return false
        }
    }
}
