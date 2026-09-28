import AppKit
import Combine
import SwiftUI

/// Observe only the studio window, not menu-bar popovers or transient panels.
/// Keep SwiftUI's window delegate intact so reopening still uses its scene.
struct StudioWindowLifecycle: NSViewRepresentable {
    var onVisibility: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onVisibility = onVisibility
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onVisibility = onVisibility
    }

    final class ObserverView: NSView {
        var onVisibility: ((Bool) -> Void)?
        private var observers = Set<AnyCancellable>()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.removeAll()
            guard let window else { return }
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
                .sink { [weak self] _ in
                    self?.onVisibility?(false)
                    NSApp.setActivationPolicy(.accessory)
                }.store(in: &observers)
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
                .sink { [weak self] _ in
                    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
                    self?.onVisibility?(true)
                }.store(in: &observers)
        }
    }
}
