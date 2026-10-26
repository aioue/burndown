import BurndownCore
import SwiftUI

/// Value + unit (hours / days / never) editor for a `Lifetime`.
struct LifetimeEditor: View {
    @Binding var lifetime: Lifetime

    private enum Unit: String, CaseIterable { case hours = "Hours", days = "Days", never = "Never" }

    private var unit: Unit {
        guard let s = lifetime.seconds else { return .never }
        return s >= 86_400 && s.truncatingRemainder(dividingBy: 86_400) == 0 ? .days : .hours
    }

    private var value: Double {
        guard let s = lifetime.seconds else { return 0 }
        return unit == .days ? s / 86_400 : s / 3_600
    }

    var body: some View {
        HStack {
            if unit != .never {
                TextField("", value: Binding(get: { value }, set: { set($0, unit) }), format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
            Picker("", selection: Binding(get: { unit }, set: { set(unit == .never ? 7 : value, $0) })) {
                ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
        }
    }

    private func set(_ v: Double, _ u: Unit) {
        let n = max(1, v)
        switch u {
        case .hours: lifetime = .hours(n)
        case .days: lifetime = .days(n)
        case .never: lifetime = .never
        }
    }
}
