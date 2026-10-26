import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        setStatusItemTooltip(attempt: 0)
    }

    /// MenuBarExtra has no tooltip API, so find its status bar button and set one (the window appears
    /// slightly after launch, hence the retries).
    private func setStatusItemTooltip(attempt: Int) {
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let b = view as? NSStatusBarButton { return b }
            for sub in view.subviews { if let b = button(in: sub) { return b } }
            return nil
        }
        let found = NSApp.windows.lazy.compactMap { button(in: $0.contentView) }.first
        if let found {
            found.toolTip = "Burndown"
        } else if attempt < 20 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.setStatusItemTooltip(attempt: attempt + 1)
            }
        }
    }
}

@main
struct BurndownApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
