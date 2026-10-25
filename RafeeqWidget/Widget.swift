import WidgetKit
import SwiftUI

struct Entry: TimelineEntry { let date: Date; let pet: String; let name: String; let streak: Int; let done: Int; let total: Int }
struct Provider: TimelineProvider {
    func read() -> Entry {
        let g = UserDefaults(suiteName: "group.com.moha700m.rafeeq") ?? .standard
        let kind = g.string(forKey: "petKind") ?? "cat"
        let img = ["falcon": "falcon_chick", "camel": "camel_baby"][kind] ?? "cat_kitten"
        return Entry(date: .now, pet: img, name: g.string(forKey: "petName") ?? "رفيق", streak: g.integer(forKey: "streak"), done: g.integer(forKey: "done"), total: max(1, g.integer(forKey: "total")))
    }
    func placeholder(in context: Context) -> Entry { Entry(date: .now, pet: "cat_kitten", name: "رفيق", streak: 3, done: 2, total: 5) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) { completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(3600)))) }
}
struct RafeeqWidgetView: View {
    var e: Entry
    var body: some View {
        VStack(spacing: 4) {
            Image(e.pet).resizable().scaledToFit()
            HStack { Text(e.name).bold(); Spacer(); Text("🔥\(e.streak)") }.font(.caption)
            Gauge(value: Double(e.done), in: 0...Double(e.total)) {}.gaugeStyle(.accessoryLinearCapacity).tint(.white)
        }.foregroundStyle(.white)
        .containerBackground(for: .widget) { Image("adv_taif").resizable().scaledToFill() }
    }
}
@main
struct RafeeqWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RafeeqWidget", provider: Provider()) { RafeeqWidgetView(e: $0) }
            .configurationDisplayName("رفيق").description("رفيقك وسلسلتك على الشاشة").supportedFamilies([.systemSmall])
    }
}
