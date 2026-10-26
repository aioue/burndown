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
    /// Where the file lived, and (for Trash) where it is now, so it can be put back.
    public var originalPath: String?
    public var trashedPath: String?
    public var restored: Bool?

    public init(id: UUID = UUID(), date: Date = Date(), name: String, action: Action, reason: String,
                originalPath: String? = nil, trashedPath: String? = nil) {
        self.id = id
        self.date = date
        self.name = name
        self.action = action
        self.reason = reason
        self.originalPath = originalPath
        self.trashedPath = trashedPath
    }

    public var canRestore: Bool {
        action == .trash && restored != true && originalPath != nil && trashedPath != nil
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

public struct BurndownSettings: Codable, Sendable, Equatable {
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
    /// Show the screenshot toast when the thumbnail appears rather than when the file is written.
    public var screenshotEarlyToast = true

    public init() {}

    // Every key is optional so state saved by an older version still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BurndownSettings()
        downloads = try c.decodeIfPresent(ScopeDefaults.self, forKey: .downloads) ?? d.downloads
        screenshots = try c.decodeIfPresent(ScopeDefaults.self, forKey: .screenshots) ?? d.screenshots
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        toastSeconds = try c.decodeIfPresent(Double.self, forKey: .toastSeconds) ?? d.toastSeconds
        keepLabel = try c.decodeIfPresent(String.self, forKey: .keepLabel) ?? d.keepLabel
        secondButton = try c.decodeIfPresent(SecondButton.self, forKey: .secondButton) ?? d.secondButton
        secondLabel = try c.decodeIfPresent(String.self, forKey: .secondLabel)
        snoozeDays = try c.decodeIfPresent(Double.self, forKey: .snoozeDays) ?? d.snoozeDays
        screenshotEarlyToast = try c.decodeIfPresent(Bool.self, forKey: .screenshotEarlyToast) ?? d.screenshotEarlyToast
    }

    public func defaults(for scope: Scope) -> ScopeDefaults {
        scope == .download ? downloads : screenshots
    }
}
