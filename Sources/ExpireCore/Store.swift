import Foundation

public struct PersistedState: Codable, Sendable, Equatable {
    public var settings = ExpireSettings()
    public var items: [TrackedItem] = []
    public var log: [LogEntry] = []
    /// Screenshots are only picked up if created after this moment.
    public var screenshotsSince: Date?

    public init() {}

    public mutating func appendLog(_ entry: LogEntry, limit: Int = 200) {
        log.insert(entry, at: 0)
        if log.count > limit { log.removeLast(log.count - limit) }
    }
}

public enum Store {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Expire/state.json")
    }

    public static func load(from url: URL = defaultURL) -> PersistedState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return PersistedState() }
        return state
    }

    public static func save(_ state: PersistedState, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(state).write(to: url, options: .atomic)
    }
}
