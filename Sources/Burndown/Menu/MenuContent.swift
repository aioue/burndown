import BurndownCore
import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private static let presets: [(String, Lifetime)] = [
        ("1 hour", .hours(1)), ("12 hours", .hours(12)), ("1 day", .days(1)), ("3 days", .days(3)),
        ("7 days", .days(7)), ("14 days", .days(14)), ("31 days", .days(31)), ("Never", .never),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Pause tracking", isOn: $model.settings.paused)

            Divider()
            scopeRow("Downloads", $model.settings.downloads)
            scopeRow("Screenshots", $model.settings.screenshots)

            Divider()
            HStack {
                trackedList
                Spacer()
                Menu("Activity") {
                    if model.state.log.isEmpty { Text("Nothing expired yet") }
                    ForEach(model.state.log.prefix(15)) { e in
                        activityRow(e)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()
            HStack {
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func scopeRow(_ title: String, _ d: Binding<ScopeDefaults>) -> some View {
        HStack {
            Toggle(title, isOn: d.enabled)
            Spacer()
            Menu(d.wrappedValue.lifetime.phrase) {
                ForEach(Self.presets, id: \.0) { name, life in
                    Button(name) { d.wrappedValue.lifetime = life }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Picker("", selection: d.action) {
                Text("Trash").tag(Action.trash)
                Text("Wipe").tag(Action.wipe)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// Tracked files live in a submenu so the popover stays short; each file has its own actions submenu.
    private var trackedList: some View {
        let items = model.state.items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let shown = items.prefix(25)
        return Menu("Tracked files (\(items.count))") {
            if items.isEmpty { Text("No files tracked") }
            ForEach(shown) { item in
                Menu {
                    Button("Keep") { model.keep(item.id) }
                    Button("Expire now") { model.expireNow(item.id) }
                    Button("Reveal in Finder") { model.reveal(item.id) }
                } label: {
                    Label { Text("\(item.name)  \(Self.when(item))") } icon: {
                        Image(nsImage: FileIcon.small(path: item.path))
                    }
                }
            }
            if items.count > shown.count { Text("+ \(items.count - shown.count) more") }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder private func activityRow(_ e: LogEntry) -> some View {
        let label = Label {
            Text("\(e.name) - \(e.restored == true ? "put back" : e.action.pastTense) "
                + e.date.formatted(.relative(presentation: .named)))
        } icon: {
            Image(nsImage: FileIcon.small(path: e.originalPath ?? e.name))
        }
        if e.canRestore {
            Menu { Button("Put back") { model.putBack(e.id) } } label: { label }
        } else {
            label
        }
    }

    private static func when(_ item: TrackedItem) -> String {
        guard let due = item.due else { return "(no expiry)" }
        let verb = item.action == .wipe ? "wipe" : "trash"
        return "(\(verb) \(due.formatted(.relative(presentation: .named))))"
    }
}
