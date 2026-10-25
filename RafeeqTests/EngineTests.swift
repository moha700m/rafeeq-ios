import XCTest
@testable import Rafeeq

final class EngineTests: XCTestCase {
    func testStages() {
        XCTAssertEqual(Engine.stage(forXP: 0), .egg)
        XCTAssertEqual(Engine.stage(forXP: 25), .baby)
        XCTAssertEqual(Engine.stage(forXP: 500), .young)
        XCTAssertEqual(Engine.stage(forXP: 1000), .grown)
        XCTAssertGreaterThan(Engine.level(forXP: 1000), Engine.level(forXP: 10))
    }
    func testStreakContinues() { XCTAssertEqual(Engine.updateStreak(streak: 4, lastActive: "2026-10-24", today: "2026-10-25", freezes: 0).0, 5) }
    func testStreakSameDay() { XCTAssertEqual(Engine.updateStreak(streak: 4, lastActive: "2026-10-25", today: "2026-10-25", freezes: 0).0, 4) }
    func testStreakFreezeUsed() {
        let r = Engine.updateStreak(streak: 4, lastActive: "2026-10-23", today: "2026-10-25", freezes: 1)
        XCTAssertEqual(r.0, 5); XCTAssertEqual(r.1, 0)
    }
    func testStreakResets() { XCTAssertEqual(Engine.updateStreak(streak: 9, lastActive: "2026-10-20", today: "2026-10-25", freezes: 1).0, 1) }
    func testFirstDay() { XCTAssertEqual(Engine.updateStreak(streak: 0, lastActive: nil, today: "2026-10-25", freezes: 0).0, 1) }
    func testMysteryDeterministic() {
        let a = Engine.mysteryReward(day: "2026-10-25", seed: "ABC123"), b = Engine.mysteryReward(day: "2026-10-25", seed: "ABC123")
        XCTAssertEqual(a.coins, b.coins); XCTAssertEqual(a.itemId, b.itemId)
    }
    func testLeague() { XCTAssertEqual(Engine.leagueRank(myScore: 300, others: [420, 310, 100]), 3) }
    func testSafetyFilter() {
        XCTAssertFalse(Safety.isClean("انت غبي"))
        XCTAssertTrue(Safety.isClean("صقّور البطل"))
        XCTAssertFalse(Safety.clean("you idiot").contains("idiot"))
    }
    func testCatalogBundledValid() {
        let c = Catalog.bundled
        XCTAssertEqual(c.places.map(\.id), ["alula", "taif", "rub"])
        XCTAssertFalse(c.habits.isEmpty)
        let json = try! { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return try e.encode(c) }()
        XCTAssertNotNil(try? CatalogService.decoder.decode(Catalog.self, from: json))
    }
    @MainActor func testStoreFlow() {
        let ud = UserDefaults(suiteName: "test-\(UUID())")!
        let s = Store(defaults: ud, key: "k")
        s.onboard(kind: .falcon, name: "غبي")
        XCTAssertEqual(s.d.pet.name, PetKind.falcon.defaultName)
        let h = s.habits[0]; let coins = s.d.coins
        s.toggle(h)
        XCTAssertTrue(s.todayLog.done.contains(h.id)); XCTAssertEqual(s.d.streak, 1); XCTAssertGreaterThan(s.d.coins, coins)
        s.toggle(h); XCTAssertFalse(s.todayLog.done.contains(h.id))
        let f = s.visibleFriends[0]
        XCTAssertTrue(s.cheer(f)); XCTAssertFalse(s.cheer(f))
        s.report(f, reason: "x"); XCTAssertFalse(s.visibleFriends.contains(f))
        XCTAssertNotNil(s.openEgg()); XCTAssertNil(s.openEgg())
        s.deleteAccount(); XCTAssertFalse(s.d.onboarded)
    }
}
