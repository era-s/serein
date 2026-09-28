import AppKit
import Combine
import SwiftUI

/// Visibility only gates previews; closing/reopening alone controls the Dock.
/// Preserve SwiftUI's delegate so its scene can reopen the same window.
struct StudioWindowLifecycle: NSViewRepresentable {
    var onVisibility: (Bool) -> Void
    var onClose: () -> Void = {}

    static func permitsPreview(visible: Bool, miniaturized: Bool, occluded: Bool, appHidden: Bool) -> Bool {
        visible && !miniaturized && !occluded && !appHidden
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onVisibility = onVisibility
        view.onClose = onClose
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onVisibility = onVisibility
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onVisibility: ((Bool) -> Void)?
        var onClose: (() -> Void)?
        private var observers = Set<AnyCancellable>()
        private var closing = false
        private var lastVisibility: Bool?

        private func refreshVisibility() {
            let allowed = window.map {
                !closing && StudioWindowLifecycle.permitsPreview(visible: $0.isVisible,
                    miniaturized: $0.isMiniaturized, occluded: !$0.occlusionState.contains(.visible),
                    appHidden: NSApp.isHidden)
            } ?? false
            guard lastVisibility != allowed else { return }
            lastVisibility = allowed
            onVisibility?(allowed)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.removeAll()
            guard let window else { return }
            closing = false
            lastVisibility = nil
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
                .sink { [weak self] _ in
                    self?.onClose?()
                    self?.closing = true
                    self?.refreshVisibility()
                    NSApp.setActivationPolicy(.accessory)
                }.store(in: &observers)
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
                .sink { [weak self] _ in
                    self?.closing = false
                    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
                    self?.refreshVisibility()
                }.store(in: &observers)
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.publisher(for: name, object: window)
                    .sink { [weak self] _ in self?.refreshVisibility() }.store(in: &observers)
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                NotificationCenter.default.publisher(for: name)
                    .sink { [weak self] _ in self?.refreshVisibility() }.store(in: &observers)
            }
            // Do not publish during SwiftUI's view update pass.
            DispatchQueue.main.async { [weak self] in self?.refreshVisibility() }
        }
    }
}
