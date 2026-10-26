import BurndownCore
import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var page: Page

    enum Page { case main, tracked, activity }

    init(model: AppModel, page: Page = .main) {
        self.model = model
        _page = State(initialValue: page)
    }

    private static let presets: [(String, Lifetime)] = [
        ("1 hour", .hours(1)), ("12 hours", .hours(12)), ("1 day", .days(1)), ("3 days", .days(3)),
        ("7 days", .days(7)), ("14 days", .days(14)), ("31 days", .days(31)), ("Never", .never),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch page {
            case .main: mainPage
            case .tracked: listPage("Tracked files", count: model.state.items.count, trackedRows)
            case .activity: listPage("Activity", count: min(model.state.log.count, 50), activityRows)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onDisappear { page = .main }
    }

    // MARK: Main page

    private var mainPage: some View {
        Group {
            Toggle("Pause tracking", isOn: $model.settings.paused)

            Divider()
            scopeRow("Downloads", $model.settings.downloads)
            scopeRow("Screenshots", $model.settings.screenshots)

            Divider()
            HStack {
                pageLink("Tracked files (\(model.state.items.count))", .tracked)
                Spacer()
                pageLink("Activity", .activity)
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
    }

    private func pageLink(_ title: String, _ target: Page) -> some View {
        Button { page = target } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
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

    // MARK: List pages

    private func listPage(_ title: String, count: Int, _ rows: some View) -> some View {
        Group {
            HStack {
                Button { page = .main } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Text("Back").hidden() // keeps the title centred
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) { rows }
            }
            // A ScrollView has no natural height, so size it to its rows up to a cap.
            .frame(height: min(max(CGFloat(count), 1) * 36, 320))
        }
    }

    @ViewBuilder private var trackedRows: some View {
        let items = model.state.items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        if items.isEmpty { Text("No files tracked").foregroundStyle(.secondary) }
        ForEach(items) { item in
            HStack(spacing: 8) {
                FileThumb(previewPath: item.path, iconPath: item.path)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Text(Self.when(item)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                iconButton("checkmark.circle", "Keep") { model.keep(item.id) }
                iconButton("flame", "Expire now") { model.expireNow(item.id) }
                iconButton("magnifyingglass", "Reveal in Finder") { model.reveal(item.id) }
            }
        }
    }

    @ViewBuilder private var activityRows: some View {
        if model.state.log.isEmpty { Text("Nothing has expired yet").foregroundStyle(.secondary) }
        ForEach(model.state.log.prefix(50)) { e in
            HStack(spacing: 8) {
                FileThumb(previewPath: e.restored == true ? e.originalPath : e.trashedPath,
                          iconPath: e.originalPath ?? e.name)
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                    Text("\(e.restored == true ? "put back" : e.action.pastTense) "
                        + e.date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if e.canRestore {
                    iconButton("arrow.uturn.backward.circle", "Restore from Trash") { model.putBack(e.id) }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func when(_ item: TrackedItem) -> String {
        guard let due = item.due else { return "No expiry" }
        let verb = item.action == .wipe ? "Wipe" : "Trash"
        return "\(verb) \(due.formatted(.relative(presentation: .named)))"
    }
}
