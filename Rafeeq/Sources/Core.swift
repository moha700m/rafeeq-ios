import Foundation

// MARK: - Localization (Arabic first)
enum Lang: String, Codable { case ar, en }
struct L10n {
    static var lang: Lang = .ar
    static func t(_ ar: String, _ en: String) -> String { lang == .ar ? ar : en }
}
func L(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

// MARK: - Pets
enum PetKind: String, Codable, CaseIterable, Identifiable {
    case falcon, camel, cat
    var id: String { rawValue }
    var defaultName: String { switch self { case .falcon: return L("صقّور", "Saqqour"); case .camel: return L("زعبول", "Zaboul"); case .cat: return L("بسبوسة", "Basbousa") } }
    var title: String { switch self { case .falcon: return L("صقر", "Falcon"); case .camel: return L("قعود", "Camel"); case .cat: return L("قطوة", "Cat") } }
    var babyImage: String { switch self { case .falcon: return "falcon_chick"; case .camel: return "camel_baby"; case .cat: return "cat_kitten" } }
    var grownImage: String { self == .falcon ? "falcon_grown" : babyImage }
}

enum PetStage: Int, Codable, Comparable {
    case egg = 0, baby, young, grown
    static func < (a: PetStage, b: PetStage) -> Bool { a.rawValue < b.rawValue }
    var title: String { switch self { case .egg: return L("بيضة", "Egg"); case .baby: return L("صغير", "Baby"); case .young: return L("يكبر", "Young"); case .grown: return L("كبير", "Grown") } }
}

struct Pet: Codable, Equatable {
    var kind: PetKind
    var name: String
    var xp: Int = 0
    var equipped: [String] = []
    var stage: PetStage { Engine.stage(forXP: xp) }
    var level: Int { Engine.level(forXP: xp) }
    var imageName: String { stage >= .grown ? kind.grownImage : kind.babyImage }
}

// MARK: - Habits & days
struct Habit: Codable, Identifiable, Equatable {
    var id: String
    var ar: String
    var en: String
    var symbol: String
    var energy: Int
    var title: String { L(ar, en) }
}

struct DayLog: Codable, Equatable {
    var done: Set<String> = []
    var mood: Int? = nil
    var journal: String = ""
    var energy: Int = 0
}

struct Friend: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var pet: PetKind
    var petName: String
    var level: Int
    var weekScore: Int
    var streak: Int
    var status: String
    var sample: Bool = true
}

struct Report: Codable, Equatable { var friendId: String; var reason: String; var date: Date }

struct Adventure: Codable, Equatable { var placeId: String; var start: Date; var end: Date }

// MARK: - Engine (pure logic, unit tested)
enum Engine {
    static func stage(forXP xp: Int) -> PetStage {
        switch xp { case ..<20: return .egg; case ..<300: return .baby; case ..<900: return .young; default: return .grown }
    }
    static func level(forXP xp: Int) -> Int { 1 + Int((Double(max(0, xp)) / 60).squareRoot() * 2) }
    static func progressInStage(xp: Int) -> Double {
        let bounds: [(Int, Int)] = [(0, 20), (20, 300), (300, 900), (900, 2400)]
        let b = bounds[min(stage(forXP: xp).rawValue, 3)]
        return min(1, Double(xp - b.0) / Double(b.1 - b.0))
    }
    static func dayKey(_ d: Date, cal: Calendar = .init(identifier: .gregorian)) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func daysBetween(_ a: String, _ b: String) -> Int {
        let f = DateFormatter(); f.calendar = .init(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let x = f.date(from: a), let y = f.date(from: b) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: x, to: y).day ?? 0
    }
    /// Streak update when the user is active on `today`. Returns (streak, freezesLeft).
    static func updateStreak(streak: Int, lastActive: String?, today: String, freezes: Int) -> (Int, Int) {
        guard let last = lastActive else { return (1, freezes) }
        let gap = daysBetween(last, today)
        if gap <= 0 { return (max(streak, 1), freezes) }
        if gap == 1 { return (streak + 1, freezes) }
        let missed = gap - 1
        if missed <= freezes { return (streak + 1, freezes - missed) }
        return (1, freezes)
    }
    /// Deterministic daily mystery egg reward.
    static func mysteryReward(day: String, seed: String) -> (coins: Int, itemId: String?) {
        var h: UInt64 = 1469598103934665603
        for b in (day + seed).utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let roll = Int(h % 100)
        if roll < 10 { return (0, "rare_\(h % 3)") }
        return (20 + Int(h % 60), nil)
    }
    static func leagueRank(myScore: Int, others: [Int]) -> Int { 1 + others.filter { $0 > myScore }.count }
    static func isLive(_ e: SeasonEvent, now: Date) -> Bool { now >= e.start && now <= e.end }
}

// MARK: - Safety (Apple guideline 1.2)
enum Safety {
    static let blocked: [String] = ["كلب", "حمار", "غبي", "حقير", "تافه", "زق", "fuck", "shit", "bitch", "idiot", "stupid"]
    static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا").replacingOccurrences(of: "ة", with: "ه").replacingOccurrences(of: "ـ", with: "")
    }
    static func isClean(_ s: String) -> Bool { let n = normalize(s); return !blocked.contains { n.contains(normalize($0)) } }
    static func clean(_ s: String) -> String {
        var out = s
        for w in blocked where out.lowercased().contains(w.lowercased()) { out = out.replacingOccurrences(of: w, with: String(repeating: "•", count: w.count), options: .caseInsensitive) }
        return out
    }
}
