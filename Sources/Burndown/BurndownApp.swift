import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var termSource: DispatchSourceSignal?

    override init() {
        super.init()
        // Turn SIGTERM into a normal quit so the screenshot log helper process is stopped with us.
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { NSApp.terminate(nil) }
        src.resume()
        termSource = src
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        setStatusItemTooltip(attempt: 0)
        // Register as a login item once, for installed copies only; turning it off in the menu sticks.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didOfferLoginItem"), Bundle.main.bundlePath.hasPrefix("/Applications/") {
            defaults.set(true, forKey: "didOfferLoginItem")
            try? SMAppService.mainApp.register()
        }
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

    /// Runs before the delegate (and its model) is created, so `--render-docs` never loads real state.
    init() {
        DocsRender.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            Image(nsImage: delegate.model.settings.paused ? MenuBarIcon.paused : MenuBarIcon.normal)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
