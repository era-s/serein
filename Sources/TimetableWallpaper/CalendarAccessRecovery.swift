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
        access = provider.access
        if access == .authorized { errorMessage = nil }
    }

    /// Call only from the user's reconnect button. A successful result allows
    /// the owner to check its existing connection under the usual opt-in rules.
    func reconnect() async -> Bool {
        guard !isConnecting, !Task.isCancelled else { return false }
        isConnecting = true
        errorMessage = nil
        defer {
            access = provider.access
            isConnecting = false
        }
        do {
            let granted = try await provider.requestAccess()
            guard !Task.isCancelled else { return false }
            access = provider.access
            guard granted, access == .authorized else { throw CalendarImportError.permissionDenied }
            return true
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }
}
