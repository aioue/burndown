import BurndownCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
            ScopeTab(title: "Downloads", d: $model.settings.downloads)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            ScopeTab(title: "Screenshots", d: $model.settings.screenshots,
                     early: $model.settings.screenshotEarlyToast,
                     footnote: "Tracks macOS screenshots wherever they are saved. Only screenshots taken after you turn this on are tracked.")
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            RulesTab(model: model).tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            ActivityTab(model: model).tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 560, height: 500)
    }
}

private struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            form
            HStack {
                Spacer()
                testToastChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var form: some View {
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Toggle("Pause tracking", isOn: $model.settings.paused)
            Toggle("Double-tap Shift to keep", isOn: $model.settings.shiftKeeps)
            Text("While a toast is showing, tapping Shift twice keeps the newest file.")
                .font(.caption).foregroundStyle(.secondary)

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
                    prompt: Text(model.settings.secondButtonLabel))
                if model.settings.secondButton == .expireSoon {
                    Stepper("Expire in \(Int(model.settings.expireSoonMinutes)) minutes",
                            value: $model.settings.expireSoonMinutes, in: 1...720, step: 5)
                }
                if model.settings.secondButton == .snooze {
                    Stepper("Snooze by \(Int(model.settings.snoozeDays)) days",
                            value: $model.settings.snoozeDays, in: 1...90)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var testToastChip: some View {
        Button { model.sendTestToast() } label: {
            Image(systemName: "bell.badge")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Show a test toast")
    }
}

private struct ScopeTab: View {
    let title: String
    @Binding var d: ScopeDefaults
    var early: Binding<Bool>?
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
            if let early {
                Toggle("Show it as soon as the thumbnail appears", isOn: early)
                    .disabled(!d.showToast)
                Text("macOS only saves a screenshot about 5 seconds after the thumbnail appears. This watches the system log to show the toast sooner (needs an admin account).")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
