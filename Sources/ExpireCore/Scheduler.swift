import Foundation

public enum Scheduler {
    /// Items whose countdown has finished.
    public static func due(_ items: [TrackedItem], now: Date = Date()) -> [TrackedItem] {
        items.filter { ($0.due ?? .distantFuture) <= now }
    }

    /// The earliest future due date, used to arm the single timer.
    public static func nextDue(_ items: [TrackedItem], after now: Date = Date()) -> Date? {
        items.compactMap(\.due).filter { $0 > now }.min()
    }

    /// Items expiring within `window` seconds, soonest first (the menu's "Expiring soon").
    public static func expiringSoon(_ items: [TrackedItem], within window: TimeInterval = 86_400,
                                    now: Date = Date()) -> [TrackedItem] {
        items.filter { if let d = $0.due { return d > now && d <= now + window } else { return false } }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
}
