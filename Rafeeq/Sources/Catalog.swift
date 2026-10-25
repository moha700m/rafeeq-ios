import Foundation

struct Place: Codable, Identifiable, Equatable { var id: String; var ar: String; var en: String; var image: String; var hours: Double; var cost: Int; var reward: Int; var descAr: String; var descEn: String
    var title: String { L(ar, en) }; var desc: String { L(descAr, descEn) } }
struct ShopItem: Codable, Identifiable, Equatable { var id: String; var ar: String; var en: String; var symbol: String; var price: Int; var kind: String; var minLevel: Int = 0
    var title: String { L(ar, en) } }
struct SeasonEvent: Codable, Identifiable, Equatable { var id: String; var ar: String; var en: String; var image: String; var start: Date; var end: Date; var goal: Int; var progress: Int; var descAr: String; var descEn: String
    var title: String { L(ar, en) }; var desc: String { L(descAr, descEn) } }
struct Prompt: Codable, Equatable { var ar: String; var en: String }

/// Remote-updatable content. Fetched from `Catalog.remoteURL` (or Firestore `catalog/current` once Firebase is connected),
/// cached on disk, and falls back to the bundled default so the app works fully offline.
struct Catalog: Codable, Equatable {
    var version: Int
    var habits: [Habit]
    var places: [Place]
    var items: [ShopItem]
    var events: [SeasonEvent]
    var prompts: [Prompt]
    var petLines: [Prompt]
    var freezePrice: Int

    static let remoteURL = URL(string: "https://moha700m.github.io/rafeeq-ios/catalog.json")!

    static var bundled: Catalog {
        let now = Date()
        return Catalog(version: 1,
            habits: [
                Habit(id: "water", ar: "موية", en: "Water", symbol: "drop.fill", energy: 10),
                Habit(id: "sleep", ar: "نوم بدري", en: "Sleep early", symbol: "moon.fill", energy: 15),
                Habit(id: "walk", ar: "مشي", en: "Walk", symbol: "figure.walk", energy: 15),
                Habit(id: "read", ar: "قراية", en: "Reading", symbol: "book.fill", energy: 10),
                Habit(id: "study", ar: "مذاكرة", en: "Study", symbol: "graduationcap.fill", energy: 15),
                Habit(id: "gym", ar: "رياضة", en: "Exercise", symbol: "dumbbell.fill", energy: 20)],
            places: [
                Place(id: "alula", ar: "العُلا", en: "AlUla", image: "adv_alula", hours: 2, cost: 30, reward: 60, descAr: "صخور ذهبية وقصص قديمة", descEn: "Golden rocks and old stories"),
                Place(id: "taif", ar: "الطايف", en: "Taif", image: "adv_taif", hours: 3, cost: 40, reward: 80, descAr: "ورد وجبال وهوا بارد", descEn: "Roses, mountains, cool air"),
                Place(id: "rub", ar: "الربع الخالي", en: "Empty Quarter", image: "adv_empty_quarter", hours: 6, cost: 70, reward: 160, descAr: "كثبان ونجوم وجوائز نادرة", descEn: "Dunes, stars and rare loot")],
            items: [
                ShopItem(id: "scarf", ar: "شال ملوّن", en: "Colorful scarf", symbol: "scribble.variable", price: 120, kind: "wear"),
                ShopItem(id: "crown", ar: "تاج صغير", en: "Little crown", symbol: "crown.fill", price: 400, kind: "wear", minLevel: 5),
                ShopItem(id: "glasses", ar: "نظارة شمس", en: "Sunglasses", symbol: "eyeglasses", price: 200, kind: "wear"),
                ShopItem(id: "lantern", ar: "فنر", en: "Lantern", symbol: "lamp.table.fill", price: 150, kind: "room"),
                ShopItem(id: "tent", ar: "خيمة شتوية", en: "Winter tent", symbol: "tent.fill", price: 350, kind: "room"),
                ShopItem(id: "palm", ar: "نخلة", en: "Palm tree", symbol: "tree.fill", price: 180, kind: "room"),
                ShopItem(id: "freeze", ar: "تجميد السلسلة", en: "Streak freeze", symbol: "snowflake", price: 100, kind: "freeze")],
            events: [
                SeasonEvent(id: "alula-season", ar: "موسم العُلا", en: "AlUla Season", image: "adv_alula", start: now.addingTimeInterval(-86400 * 3), end: now.addingTimeInterval(86400 * 4), goal: 1_000_000, progress: 742_000, descAr: "كل الرفقاء يجمعون طاقة سوا، والجائزة سرج نادر", descEn: "Everyone pools energy for a rare saddle"),
                SeasonEvent(id: "stars-night", ar: "ليلة النجوم", en: "Night of Stars", image: "adv_empty_quarter", start: now.addingTimeInterval(86400 * 6), end: now.addingTimeInterval(86400 * 9), goal: 500_000, progress: 0, descAr: "حدث جاي بالربع الخالي", descEn: "Upcoming event in the Empty Quarter")],
            prompts: [
                Prompt(ar: "وش أكثر شي ضحكك اليوم؟", en: "What made you laugh today?"),
                Prompt(ar: "وش الشي اللي تفتخر فيه اليوم؟", en: "What are you proud of today?"),
                Prompt(ar: "لو تقدر تسافر بكرة، وين تروح؟", en: "If you could travel tomorrow, where to?"),
                Prompt(ar: "مين أكثر واحد فرّحك اليوم؟", en: "Who made your day better?"),
                Prompt(ar: "وش شي صغير تبي تسويه بكرة؟", en: "One small thing for tomorrow?")],
            petLines: [
                Prompt(ar: "يا هلا! شربت مويتك اليوم؟", en: "Hey! Had your water today?"),
                Prompt(ar: "كفو عليك، كمّل كذا", en: "Nice one, keep going"),
                Prompt(ar: "تعبت اليوم؟ خلنا ننام بدري", en: "Tired? Let's sleep early tonight"),
                Prompt(ar: "يلا نمشي شوي ونطلع مغامرة", en: "Let's walk a bit and go on an adventure")],
            freezePrice: 100)
    }
}

enum CatalogService {
    static var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("catalog.json") }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    static func cached() -> Catalog? { (try? Data(contentsOf: cacheURL)).flatMap { try? decoder.decode(Catalog.self, from: $0) } }
    static func fetchRemote() async -> Catalog? {
        var r = URLRequest(url: Catalog.remoteURL); r.timeoutInterval = 8; r.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let c = try? decoder.decode(Catalog.self, from: data) else { return nil }
        try? data.write(to: cacheURL)
        return c
    }
}
