import Foundation

/// What the rule engine knows about a newly arrived file.
public struct FileInfo: Sendable, Equatable {
    public var name: String
    public var size: Int64
    public var sourceURLs: [String]
    public var scope: Scope

    public init(name: String, size: Int64, sourceURLs: [String] = [], scope: Scope) {
        self.name = name
        self.size = size
        self.sourceURLs = sourceURLs
        self.scope = scope
    }

    public var ext: String { (name as NSString).pathExtension.lowercased() }

    public var sourceHost: String? {
        sourceURLs.lazy.compactMap { URL(string: $0)?.host?.lowercased() }.first
    }
}

public enum Condition: Codable, Sendable, Equatable {
    case scope(Scope)
    case extensions([String])
    case nameGlob(String)
    case sizeLessThan(Int64)
    case sizeGreaterThan(Int64)
    case sourceDomain(String)

    public func matches(_ f: FileInfo) -> Bool {
        switch self {
        case .scope(let s): return f.scope == s
        case .extensions(let list): return list.contains { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == f.ext }
        case .nameGlob(let g): return fnmatch(g.lowercased(), f.name.lowercased(), 0) == 0
        case .sizeLessThan(let n): return f.size < n
        case .sizeGreaterThan(let n): return f.size > n
        case .sourceDomain(let d):
            let domain = d.lowercased()
            return f.sourceURLs.contains { s in
                guard let host = URL(string: s)?.host?.lowercased() else { return false }
                return host == domain || host.hasSuffix("." + domain)
            }
        }
    }
}

public enum Outcome: Codable, Sendable, Equatable {
    case ignore
    case expire(Lifetime, Action)
}

public struct Rule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var conditions: [Condition]
    public var outcome: Outcome

    public init(id: UUID = UUID(), name: String, enabled: Bool = true,
                conditions: [Condition], outcome: Outcome) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.conditions = conditions
        self.outcome = outcome
    }

    /// Disabled examples shipped so the Rules tab isn't empty.
    public static var examples: [Rule] {
        [
            Rule(name: "Installers go quickly", enabled: false,
                 conditions: [.scope(.download), .extensions(["dmg", "pkg"])],
                 outcome: .expire(.days(1), .trash)),
            Rule(name: "Ignore torrents", enabled: false,
                 conditions: [.scope(.download), .extensions(["torrent"])],
                 outcome: .ignore),
        ]
    }
}

public enum RuleEngine {
    /// First enabled rule whose conditions all match wins; otherwise the scope default applies.
    /// Returns nil when the scope itself is disabled.
    public static func evaluate(_ file: FileInfo, settings: ExpireSettings) -> Outcome? {
        let d = settings.defaults(for: file.scope)
        guard d.enabled else { return nil }
        for rule in settings.rules where rule.enabled {
            if rule.conditions.allSatisfy({ $0.matches(file) }) { return rule.outcome }
        }
        return .expire(d.lifetime, d.action)
    }
}
