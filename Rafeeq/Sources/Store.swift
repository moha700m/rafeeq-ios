import SwiftUI
import WidgetKit

struct SaveData: Codable {
    var onboarded = false
    var lang: Lang = .ar
    var pet = Pet(kind: .cat, name: "")
    var habitIds: [String] = ["water", "sleep", "walk", "read", "gym"]
    var logs: [String: DayLog] = [:]
    var streak = 0
    var lastActive: String? = nil
    var freezes = 1
    var coins = 150
    var owned: Set<String> = []
    var friends: [Friend] = []
    var blocked: Set<String> = []
    var reports: [Report] = []
    var adventure: Adventure? = nil
    var souvenirs: [String] = []
    var lastEggDay: String? = nil
    var groupStreak = 6
    var inviteCode = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
    var cheersSent: [String: String] = [:]
}

@MainActor
final class Store: ObservableObject {
    @Published var d: SaveData { didSet { save() } }
    @Published var catalog: Catalog
    @Published var toast: String? = nil
    var now: () -> Date = Date.init
    private let key: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, key: String = "rafeeq.save.v1", demo: Bool = false) {
        self.defaults = defaults; self.key = key
        if let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(SaveData.self, from: data) { d = s } else { d = SaveData() }
        catalog = CatalogService.cached() ?? .bundled
        if demo { d = Store.demoData() }
        L10n.lang = d.lang
        if d.friends.isEmpty && d.onboarded { d.friends = Store.sampleFriends }
    }

    static var sampleFriends: [Friend] { [
        Friend(id: "f1", name: L("سعود", "Saud"), pet: .camel, petName: L("زعبول", "Zaboul"), level: 7, weekScore: 420, streak: 42, status: L("رجع من العُلا ومعه سرج نادر", "Back from AlUla with a rare saddle")),
        Friend(id: "f2", name: L("ريان", "Rayan"), pet: .cat, petName: L("لولو", "Lulu"), level: 5, weekScore: 310, streak: 31, status: L("نام بدري ٥ أيام ورا بعض", "Slept early 5 days in a row")),
        Friend(id: "f3", name: L("نواف", "Nawaf"), pet: .falcon, petName: L("شاهين", "Shaheen"), level: 9, weekScore: 280, streak: 28, status: L("خلّص ١٠٬٠٠٠ خطوة", "Hit 10,000 steps"))] }

    static func demoData() -> SaveData {
        var s = SaveData(); s.onboarded = true; s.pet = Pet(kind: .cat, name: L("بسبوسة", "Basbousa"), xp: 420)
        s.streak = 12; s.coins = 850; s.friends = sampleFriends; s.groupStreak = 9
        s.logs[Engine.dayKey(Date())] = DayLog(done: ["water", "sleep"], mood: 1, journal: "", energy: 25)
        return s
    }

    func save() { if let data = try? JSONEncoder().encode(d) { defaults.set(data, forKey: key) }; syncWidget() }
    func syncWidget() {
        let g = UserDefaults(suiteName: "group.com.moha700m.rafeeq") ?? .standard
        g.set(d.pet.kind.rawValue, forKey: "petKind"); g.set(d.pet.name, forKey: "petName"); g.set(d.streak, forKey: "streak")
        g.set(todayLog.done.count, forKey: "done"); g.set(habits.count, forKey: "total")
        WidgetCenter.shared.reloadAllTimelines()
    }

    var today: String { Engine.dayKey(now()) }
    var todayLog: DayLog { d.logs[today] ?? DayLog() }
    var habits: [Habit] { d.habitIds.compactMap { id in catalog.habits.first { $0.id == id } } }
    var todayEnergy: Int { todayLog.energy }
    var todayProgress: Double { habits.isEmpty ? 0 : Double(todayLog.done.count) / Double(habits.count) }
    var visibleFriends: [Friend] { d.friends.filter { !d.blocked.contains($0.id) } }
    var weekScore: Int {
        (0..<7).compactMap { i in d.logs[Engine.dayKey(now().addingTimeInterval(Double(-i) * 86400))]?.energy }.reduce(0, +)
    }
    var leagueRank: Int { Engine.leagueRank(myScore: weekScore, others: visibleFriends.map(\.weekScore)) }
    var dayIndex: Int { Calendar.current.ordinality(of: .day, in: .year, for: now()) ?? 0 }
    var petLine: String { let l = catalog.petLines; guard !l.isEmpty else { return "" }; let x = l[(dayIndex + todayLog.done.count) % l.count]; return L(x.ar, x.en) }
    var prompt: Prompt { let p = catalog.prompts; let i = dayIndex % max(1, p.count); return p.isEmpty ? Prompt(ar: "", en: "") : p[i] }
    var liveEvent: SeasonEvent? { catalog.events.first { Engine.isLive($0, now: now()) } }

    func refreshCatalog() async { if let c = await CatalogService.fetchRemote() { catalog = c } }

    func setLang(_ l: Lang) { L10n.lang = l; d.lang = l }

    func onboard(kind: PetKind, name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        d.pet = Pet(kind: kind, name: n.isEmpty || !Safety.isClean(n) ? kind.defaultName : n, xp: 20)
        d.onboarded = true
        if d.friends.isEmpty { d.friends = Store.sampleFriends }
    }

    private func markActive() {
        let r = Engine.updateStreak(streak: d.streak, lastActive: d.lastActive, today: today, freezes: d.freezes)
        if d.lastActive != today { d.streak = r.0; d.freezes = r.1; d.lastActive = today }
    }

    func toggle(_ h: Habit) {
        var log = todayLog
        if log.done.contains(h.id) { log.done.remove(h.id); log.energy -= h.energy; d.pet.xp -= h.energy; d.coins -= h.energy / 2 }
        else { log.done.insert(h.id); log.energy += h.energy; d.pet.xp += h.energy; d.coins += h.energy / 2; markActive(); haptic() }
        d.logs[today] = log
    }
    func setMood(_ m: Int) { var log = todayLog; log.mood = m; d.logs[today] = log; markActive() }
    func setJournal(_ t: String) { var log = todayLog; log.journal = t; d.logs[today] = log }

    // Social
    func cheer(_ f: Friend) -> Bool {
        guard d.cheersSent[f.id] != today else { return false }
        d.cheersSent[f.id] = today; d.coins += 5; show(L("وصلت تشجيعتك لـ\(f.name)", "Cheer sent to \(f.name)")); return true
    }
    func gift(_ f: Friend, itemId: String) -> Bool {
        guard d.owned.contains(itemId) else { return false }
        d.owned.remove(itemId); show(L("أرسلت هدية لـ\(f.name)", "Gift sent to \(f.name)")); return true
    }
    func block(_ f: Friend) { d.blocked.insert(f.id); show(L("تم الحظر", "Blocked")) }
    func report(_ f: Friend, reason: String) { d.reports.append(Report(friendId: f.id, reason: reason, date: now())); d.blocked.insert(f.id); show(L("وصلنا بلاغك وبنراجعه خلال ٢٤ ساعة", "Report received, we review within 24h")) }
    func addFriend(code: String) -> Bool {
        let c = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard c.count == 6, c != d.inviteCode else { return false }
        show(L("انرسل الطلب، يظهر صاحبك أول ما يقبل", "Request sent, your friend appears once they accept")); return true
    }

    // Adventures
    func startAdventure(_ p: Place) -> Bool {
        guard d.adventure == nil, todayEnergy >= p.cost || d.pet.xp >= p.cost else { return false }
        d.adventure = Adventure(placeId: p.id, start: now(), end: now().addingTimeInterval(p.hours * 3600)); return true
    }
    func adventureRemaining() -> TimeInterval? { d.adventure.map { max(0, $0.end.timeIntervalSince(now())) } }
    func collectAdventure() {
        guard let a = d.adventure, now() >= a.end, let p = catalog.places.first(where: { $0.id == a.placeId }) else { return }
        d.coins += p.reward; d.pet.xp += p.reward / 4; d.souvenirs.append(p.id); d.adventure = nil
        show(L("\(d.pet.name) رجع من \(p.title) ومعه \(p.reward) عملة", "\(d.pet.name) is back from \(p.title) with \(p.reward) coins"))
    }

    // Shop & egg
    func buy(_ i: ShopItem) -> Bool {
        guard d.coins >= i.price, d.pet.level >= i.minLevel else { return false }
        d.coins -= i.price
        if i.kind == "freeze" { d.freezes += 1 } else { d.owned.insert(i.id) }
        haptic(); return true
    }
    func toggleEquip(_ id: String) { if let i = d.pet.equipped.firstIndex(of: id) { d.pet.equipped.remove(at: i) } else if d.owned.contains(id) { d.pet.equipped.append(id) } }
    var eggAvailable: Bool { d.lastEggDay != today }
    func openEgg() -> (Int, String?)? {
        guard eggAvailable else { return nil }
        let r = Engine.mysteryReward(day: today, seed: d.inviteCode)
        d.lastEggDay = today; d.coins += r.coins
        if let it = r.itemId { d.owned.insert(it) }
        return r
    }

    func deleteAccount() { d = SaveData(); try? FileManager.default.removeItem(at: Snapshot.url) }
    func show(_ s: String) { toast = s; Task { try? await Task.sleep(nanoseconds: 2_200_000_000); if toast == s { toast = nil } } }
    func haptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

enum Snapshot {
    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshot.jpg") }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
}
