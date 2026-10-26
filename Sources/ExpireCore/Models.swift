import Foundation

public enum Scope: String, Codable, Sendable, CaseIterable {
    case download, screenshot
}

public enum Action: String, Codable, Sendable, CaseIterable {
    case trash, wipe

    public var pastTense: String { self == .trash ? "trashed" : "wiped" }
}

/// How long a file lives. `seconds == nil` means it never expires.
public struct Lifetime: Codable, Sendable, Equatable {
    public var seconds: TimeInterval?

    public init(seconds: TimeInterval?) { self.seconds = seconds }

    public static let never = Lifetime(seconds: nil)
    public static func days(_ n: Double) -> Lifetime { Lifetime(seconds: n * 86_400) }
    public static func hours(_ n: Double) -> Lifetime { Lifetime(seconds: n * 3_600) }

    /// "14 days", "1 day", "6 hours", "90 minutes", "never".
    public var phrase: String {
        guard let s = seconds else { return "never" }
        func unit(_ n: Double, _ name: String) -> String {
            let v = n.rounded() == n ? String(Int(n)) : String(format: "%.1f", n)
            return "\(v) \(name)\(n == 1 ? "" : "s")"
        }
        if s >= 86_400 { return unit(s / 86_400, "day") }
        if s >= 3_600 { return unit(s / 3_600, "hour") }
        return unit(max(1, (s / 60).rounded()), "minute")
    }
}

public struct TrackedItem: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public var scope: Scope
    public var arrived: Date
    /// nil = never expires (tracked but no countdown).
    public var due: Date?
    public var action: Action
    public var sourceHost: String?

    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, scope: Scope,
                arrived: Date = Date(), due: Date?, action: Action, sourceHost: String? = nil) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.scope = scope
        self.arrived = arrived
        self.due = due
        self.action = action
        self.sourceHost = sourceHost
    }

    public var name: String { (path as NSString).lastPathComponent }
}

public struct LogEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var name: String
    public var action: Action
    public var reason: String

    public init(id: UUID = UUID(), date: Date = Date(), name: String, action: Action, reason: String) {
        self.id = id
        self.date = date
        self.name = name
        self.action = action
        self.reason = reason
    }
}

public struct ScopeDefaults: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var lifetime: Lifetime
    public var action: Action
    public var showToast: Bool

    public init(enabled: Bool, lifetime: Lifetime, action: Action, showToast: Bool = true) {
        self.enabled = enabled
        self.lifetime = lifetime
        self.action = action
        self.showToast = showToast
    }
}

public enum SecondButton: String, Codable, Sendable, CaseIterable {
    case expireNow, snooze, reveal

    public var defaultLabel: String {
        switch self {
        case .expireNow: "Expire now"
        case .snooze: "Snooze"
        case .reveal: "Reveal"
        }
    }
}

public struct ExpireSettings: Codable, Sendable, Equatable {
    public var downloads = ScopeDefaults(enabled: true, lifetime: .days(14), action: .trash)
    public var screenshots = ScopeDefaults(enabled: false, lifetime: .days(14), action: .trash)
    public var rules: [Rule] = Rule.examples
    public var paused = false
    /// 0 = never auto-dismiss.
    public var toastSeconds: Double = 8
    public var keepLabel = "Keep"
    public var secondButton = SecondButton.expireNow
    public var secondLabel: String?
    public var snoozeDays: Double = 7

    public init() {}

    public func defaults(for scope: Scope) -> ScopeDefaults {
        scope == .download ? downloads : screenshots
    }
}
