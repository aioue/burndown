import Foundation
import Testing
@testable import BurndownCore

@Suite struct RuleTests {
    func file(_ name: String, size: Int64 = 100, from: [String] = [], scope: Scope = .download) -> FileInfo {
        FileInfo(name: name, size: size, sourceURLs: from, scope: scope)
    }

    @Test func defaultAppliesWhenNoRuleMatches() {
        let s = BurndownSettings()
        #expect(RuleEngine.evaluate(file("a.pdf"), settings: s) == .expire(.days(14), .trash))
    }

    @Test func screenshotsDisabledByDefault() {
        #expect(RuleEngine.evaluate(file("Screenshot.png", scope: .screenshot), settings: BurndownSettings()) == nil)
    }

    @Test func firstMatchWins() {
        var s = BurndownSettings()
        s.rules = [
            Rule(name: "dmg", conditions: [.extensions(["DMG"])], outcome: .expire(.days(1), .wipe)),
            Rule(name: "all", conditions: [], outcome: .ignore),
        ]
        #expect(RuleEngine.evaluate(file("x.dmg"), settings: s) == .expire(.days(1), .wipe))
        #expect(RuleEngine.evaluate(file("x.txt"), settings: s) == .ignore)
    }

    @Test func disabledRuleSkipped() {
        var s = BurndownSettings()
        s.rules = [Rule(name: "off", enabled: false, conditions: [], outcome: .ignore)]
        #expect(RuleEngine.evaluate(file("x"), settings: s) == .expire(.days(14), .trash))
    }

    @Test func globSizeAndDomain() {
        #expect(Condition.nameGlob("*.TORRENT").matches(file("a.torrent")))
        #expect(Condition.sizeLessThan(1024).matches(file("a", size: 10)))
        #expect(!Condition.sizeGreaterThan(1024).matches(file("a", size: 10)))
        let f = file("a", from: ["https://files.slack.com/x"])
        #expect(Condition.sourceDomain("slack.com").matches(f))
        #expect(!Condition.sourceDomain("lack.com").matches(f))
    }

    @Test func rulesRoundTripThroughJSON() throws {
        let s = BurndownSettings()
        let back = try JSONDecoder().decode(BurndownSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@Suite struct MiscTests {
    @Test func lifetimePhrases() {
        #expect(Lifetime.days(14).phrase == "14 days")
        #expect(Lifetime.days(1).phrase == "1 day")
        #expect(Lifetime.hours(6).phrase == "6 hours")
        #expect(Lifetime.never.phrase == "never")
    }

    @Test func partialFilter() {
        #expect(PartialFilter.shouldSkip(name: "a.crdownload"))
        #expect(PartialFilter.shouldSkip(name: ".DS_Store"))
        #expect(PartialFilter.shouldSkip(name: "x.Part"))
        #expect(!PartialFilter.shouldSkip(name: "report.pdf"))
    }

    @Test func schedulerPicksEarliestFuture() {
        let now = Date()
        let items = [
            TrackedItem(path: "/a", scope: .download, due: now - 5, action: .trash),
            TrackedItem(path: "/b", scope: .download, due: now + 100, action: .trash),
            TrackedItem(path: "/c", scope: .download, due: now + 50, action: .trash),
            TrackedItem(path: "/d", scope: .download, due: nil, action: .trash),
        ]
        #expect(Scheduler.due(items, now: now).map(\.path) == ["/a"])
        #expect(Scheduler.nextDue(items, after: now) == now + 50)
        #expect(Scheduler.expiringSoon(items, within: 60, now: now).map(\.path) == ["/c"])
    }

    @Test func storeRoundTripAndLogCap() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expire-\(UUID())/state.json")
        var st = PersistedState()
        st.items = [TrackedItem(path: "/x", scope: .download, due: Date(timeIntervalSince1970: 1000), action: .wipe)]
        for i in 0..<250 { st.appendLog(LogEntry(name: "f\(i)", action: .trash, reason: "t")) }
        #expect(st.log.count == 200)
        #expect(st.log.first?.name == "f249")
        try Store.save(st, to: url)
        #expect(Store.load(from: url) == st)
    }
}

@Suite struct ExpirerTests {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("expire-\(UUID())")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func wipesFileInDownloads() throws {
        let dl = try tempDir()
        let f = dl.appendingPathComponent("a.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        let item = TrackedItem(path: f.path, scope: .download, due: nil, action: .wipe)
        #expect(Expirer.expire(item, downloadsDir: dl) == .expired)
        #expect(!FileManager.default.fileExists(atPath: f.path))
    }

    @Test func missingFileIsUntracked() throws {
        let dl = try tempDir()
        let item = TrackedItem(path: dl.appendingPathComponent("gone").path, scope: .download, due: nil, action: .wipe)
        #expect(Expirer.expire(item, downloadsDir: dl) == .untrack(reason: "missing"))
    }

    @Test func movedOutOfDownloadsIsLeftAlone() throws {
        let dl = try tempDir(), other = try tempDir()
        let f = other.appendingPathComponent("a.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        let item = TrackedItem(path: f.path, scope: .download, due: nil, action: .wipe)
        #expect(Expirer.expire(item, downloadsDir: dl) == .untrack(reason: "moved out of Downloads"))
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func keptFileIsLeftAlone() throws {
        let dl = try tempDir()
        let f = dl.appendingPathComponent("a.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        try FileMeta.markKept(f)
        let item = TrackedItem(path: f.path, scope: .download, due: nil, action: .wipe)
        #expect(Expirer.expire(item, downloadsDir: dl) == .untrack(reason: "kept"))
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func screenshotsMayLiveAnywhere() throws {
        let dl = try tempDir(), other = try tempDir()
        let f = other.appendingPathComponent("shot.png")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        let item = TrackedItem(path: f.path, scope: .screenshot, due: nil, action: .wipe)
        #expect(Expirer.expire(item, downloadsDir: dl) == .expired)
    }
}

@Suite struct MigrationTests {
    @Test func settingsFromOlderVersionStillDecode() throws {
        let json = #"{"paused":true,"keepLabel":"Hold"}"#
        let s = try JSONDecoder().decode(BurndownSettings.self, from: Data(json.utf8))
        #expect(s.paused)
        #expect(s.keepLabel == "Hold")
        #expect(s.screenshotEarlyToast)
        #expect(s.downloads.lifetime == .days(14))
    }
}
