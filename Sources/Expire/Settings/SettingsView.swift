import ExpireCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
            ScopeTab(title: "Downloads", d: $model.settings.downloads)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            ScopeTab(title: "Screenshots", d: $model.settings.screenshots,
                     footnote: "Tracks macOS screenshots wherever they are saved. Only screenshots taken after you turn this on are tracked.")
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            RulesTab(model: model).tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            ActivityTab(model: model).tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Toggle("Pause tracking", isOn: $model.settings.paused)

            Section("Toast") {
                Picker("Auto-dismiss", selection: $model.settings.toastSeconds) {
                    Text("Never").tag(0.0)
                    ForEach([1.0, 3, 5, 8, 15, 30], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                TextField("Keep button", text: $model.settings.keepLabel)
                Picker("Second button", selection: $model.settings.secondButton) {
                    ForEach(SecondButton.allCases, id: \.self) { Text($0.defaultLabel).tag($0) }
                }
                TextField("Second button label", text: Binding(
                    get: { model.settings.secondLabel ?? "" },
                    set: { model.settings.secondLabel = $0.isEmpty ? nil : $0 }),
                    prompt: Text(model.settings.secondButton.defaultLabel))
                if model.settings.secondButton == .snooze {
                    Stepper("Snooze by \(Int(model.settings.snoozeDays)) days",
                            value: $model.settings.snoozeDays, in: 1...90)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScopeTab: View {
    let title: String
    @Binding var d: ScopeDefaults
    var footnote: String?

    var body: some View {
        Form {
            Toggle("Track \(title.lowercased())", isOn: $d.enabled)
            LabeledContent("Expire after") { LifetimeEditor(lifetime: $d.lifetime) }
            Picker("When expired", selection: $d.action) {
                Text("Move to Trash").tag(Action.trash)
                Text("Wipe (permanent delete)").tag(Action.wipe)
            }
            Toggle("Show a toast for each new file", isOn: $d.showToast)
            if let footnote { Text(footnote).font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}

private struct ActivityTab: View {
    var model: AppModel

    var body: some View {
        if model.state.log.isEmpty {
            Text("Nothing has expired yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.state.log) { e in
                HStack {
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(e.action.pastTense) \(e.date.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
