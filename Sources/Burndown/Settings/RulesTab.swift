import BurndownCore
import SwiftUI

/// Flat, editable view over a rule's condition list.
extension Rule {
    private func first<T>(_ pick: (Condition) -> T?) -> T? { conditions.lazy.compactMap(pick).first }

    private mutating func replace(_ keep: (Condition) -> Bool, with new: Condition?) {
        conditions.removeAll { !keep($0) }
        if let new { conditions.append(new) }
    }

    var scopeFilter: Scope? {
        get { first { if case .scope(let s) = $0 { s } else { nil } } }
        set { replace({ if case .scope = $0 { false } else { true } }, with: newValue.map { .scope($0) }) }
    }

    var extensionsText: String {
        get { first { if case .extensions(let e) = $0 { e.joined(separator: ", ") } else { nil } } ?? "" }
        set {
            let list = newValue.split(whereSeparator: { ", ".contains($0) }).map(String.init)
            replace({ if case .extensions = $0 { false } else { true } }, with: list.isEmpty ? nil : .extensions(list))
        }
    }

    var globText: String {
        get { first { if case .nameGlob(let g) = $0 { g } else { nil } } ?? "" }
        set { replace({ if case .nameGlob = $0 { false } else { true } }, with: newValue.isEmpty ? nil : .nameGlob(newValue)) }
    }

    var domainText: String {
        get { first { if case .sourceDomain(let d) = $0 { d } else { nil } } ?? "" }
        set { replace({ if case .sourceDomain = $0 { false } else { true } }, with: newValue.isEmpty ? nil : .sourceDomain(newValue)) }
    }

    /// Kilobytes; 0 = no limit.
    var minSizeKB: Int {
        get { first { if case .sizeGreaterThan(let n) = $0 { Int(n / 1024) } else { nil } } ?? 0 }
        set { replace({ if case .sizeGreaterThan = $0 { false } else { true } }, with: newValue > 0 ? .sizeGreaterThan(Int64(newValue) * 1024) : nil) }
    }

    var maxSizeKB: Int {
        get { first { if case .sizeLessThan(let n) = $0 { Int(n / 1024) } else { nil } } ?? 0 }
        set { replace({ if case .sizeLessThan = $0 { false } else { true } }, with: newValue > 0 ? .sizeLessThan(Int64(newValue) * 1024) : nil) }
    }

    var isIgnore: Bool {
        get { outcome == .ignore }
        set { outcome = newValue ? .ignore : .expire(.days(14), .trash) }
    }

    var lifetime: Lifetime {
        get { if case .expire(let l, _) = outcome { l } else { .days(14) } }
        set { if case .expire(_, let a) = outcome { outcome = .expire(newValue, a) } }
    }

    var action: Action {
        get { if case .expire(_, let a) = outcome { a } else { .trash } }
        set { if case .expire(let l, _) = outcome { outcome = .expire(l, newValue) } }
    }
}

struct RulesTab: View {
    @Bindable var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach($model.settings.rules) { $rule in
                        HStack {
                            Toggle("", isOn: $rule.enabled).labelsHidden()
                            Text(rule.name).lineLimit(1)
                        }
                        .tag(rule.id)
                    }
                    .onMove { model.settings.rules.move(fromOffsets: $0, toOffset: $1) }
                }
                HStack {
                    Button { addRule() } label: { Image(systemName: "plus") }
                    Button {
                        if let s = selection { model.settings.rules.removeAll { $0.id == s }; selection = nil }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 180, maxWidth: 220)

            Group {
                if let i = model.settings.rules.firstIndex(where: { $0.id == selection }) {
                    RuleForm(rule: $model.settings.rules[i], preview: { model.previewMatches(for: model.settings.rules[i].id) })
                } else {
                    VStack(spacing: 6) {
                        Text("Rules run top to bottom; the first match wins.")
                        Text("Drag to reorder. Files matching no rule use the Downloads or Screenshots default.")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
    }

    private func addRule() {
        let r = Rule(name: "New rule", conditions: [.scope(.download)], outcome: .expire(.days(7), .trash))
        model.settings.rules.append(r)
        selection = r.id
    }
}

private struct RuleForm: View {
    @Binding var rule: Rule
    let preview: () -> (names: [String], total: Int)
    @State private var showPreview = false
    @State private var result: (names: [String], total: Int) = ([], 0)

    var body: some View {
        Form {
            HStack {
                TextField("Name", text: $rule.name)
                Button("Preview matches") {
                    result = preview()
                    showPreview = true
                }
                .popover(isPresented: $showPreview, arrowEdge: .bottom) { previewList }
            }
            Section("When all of these match") {
                Picker("Kind", selection: $rule.scopeFilter) {
                    Text("Any").tag(Scope?.none)
                    Text("Download").tag(Scope?.some(.download))
                    Text("Screenshot").tag(Scope?.some(.screenshot))
                }
                TextField("Extensions", text: $rule.extensionsText, prompt: Text("dmg, pkg"))
                TextField("Name pattern", text: $rule.globText, prompt: Text("invoice-*.pdf"))
                TextField("Source domain", text: $rule.domainText, prompt: Text("slack.com"))
                TextField("Larger than (KB)", value: $rule.minSizeKB, format: .number)
                TextField("Smaller than (KB)", value: $rule.maxSizeKB, format: .number)
            }
            Section("Then") {
                Picker("", selection: $rule.isIgnore) {
                    Text("Expire").tag(false)
                    Text("Ignore (never track)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !rule.isIgnore {
                    LabeledContent("After") { LifetimeEditor(lifetime: $rule.lifetime) }
                    Picker("Action", selection: $rule.action) {
                        Text("Move to Trash").tag(Action.trash)
                        Text("Wipe").tag(Action.wipe)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(result.names.count) of \(result.total) files in Downloads")
                .font(.headline)
            Text("This rule would apply to these (first match wins). Nothing has been changed.")
                .font(.caption).foregroundStyle(.secondary)
            if result.names.isEmpty {
                Text("No matches").foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                List(result.names.prefix(60), id: \.self) { Text($0).lineLimit(1).truncationMode(.middle) }
                    .frame(width: 320, height: min(CGFloat(result.names.count) * 24 + 8, 260))
            }
        }
        .padding(12)
    }
}
