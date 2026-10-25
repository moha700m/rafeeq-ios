import SwiftUI

struct ShopView: View {
    @EnvironmentObject var s: Store
    @State private var eggResult: String?
    @State private var shake = false
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.97, green: 0.71, blue: 0.54), Color(red: 0.78, green: 0.48, blue: 0.66), Color(red: 0.43, green: 0.36, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack { SectionTitle(text: L("المتجر", "Shop")); Pill(symbol: "circle.hexagongrid.fill", text: "\(s.d.coins)") }
                    HStack(spacing: 14) {
                        EggView(size: 90).rotationEffect(.degrees(shake ? 8 : -8)).animation(s.eggAvailable ? .easeInOut(duration: 0.15).repeatCount(6, autoreverses: true) : .default, value: shake)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("بيضة اليوم الغامضة", "Daily mystery egg")).font(.headline)
                            Text(eggResult ?? L("افتحها مرة كل يوم", "Open once a day")).font(.caption)
                            Button(s.eggAvailable ? L("افتح", "Open") : L("ارجع بكرة", "Come back tomorrow")) {
                                shake.toggle()
                                if let r = s.openEgg() { eggResult = r.1 != nil ? L("طلع لك غرض نادر!", "You got a rare item!") : L("طلع لك \(r.0) عملة", "You got \(r.0) coins") }
                            }.disabled(!s.eggAvailable).bold().padding(.horizontal, 16).padding(.vertical, 8).background(.white, in: Capsule()).foregroundStyle(.black)
                        }
                        Spacer()
                    }.padding(16).glass().foregroundStyle(.white)
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(s.catalog.items) { i in
                            let owned = s.d.owned.contains(i.id), equipped = s.d.pet.equipped.contains(i.id), locked = s.d.pet.level < i.minLevel
                            VStack(spacing: 8) {
                                Image(systemName: i.symbol).font(.system(size: 38)).frame(height: 60)
                                Text(i.title).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.8)
                                Button {
                                    if owned && i.kind == "wear" { s.toggleEquip(i.id) }
                                    else if !owned { if !s.buy(i) { s.show(locked ? L("يحتاج مستوى \(i.minLevel)", "Needs level \(i.minLevel)") : L("عملاتك ما تكفي", "Not enough coins")) } }
                                } label: {
                                    Text(owned ? (i.kind == "wear" ? (equipped ? L("شيله", "Remove") : L("لبّسه", "Wear")) : L("عندك", "Owned")) : (locked ? L("مستوى \(i.minLevel)", "Lv \(i.minLevel)") : "\(i.price)"))
                                        .font(.caption.bold()).frame(maxWidth: .infinity).padding(8).background(.white.opacity(owned ? 0.3 : 0.95), in: Capsule()).foregroundStyle(owned ? .white : .black)
                                }
                            }.padding(12).glass(22).foregroundStyle(.white).opacity(locked ? 0.7 : 1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("مجموعتك", "Your collection")).font(.headline)
                        HStack { ForEach(PetKind.allCases) { k in Image(k.babyImage).resizable().scaledToFit().frame(height: 70).saturation(k == s.d.pet.kind ? 1 : 0).opacity(k == s.d.pet.kind ? 1 : 0.5) } }
                        Text(L("تذكارات الرحلات: \(s.d.souvenirs.count)", "Trip souvenirs: \(s.d.souvenirs.count)")).font(.caption)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glass().foregroundStyle(.white)
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) var dismiss
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section(L("اللغة", "Language")) {
                    Picker(L("اللغة", "Language"), selection: Binding(get: { s.d.lang }, set: { s.setLang($0) })) { Text("العربية").tag(Lang.ar); Text("English").tag(Lang.en) }.pickerStyle(.segmented)
                }
                Section(L("الأمان", "Safety")) {
                    Text(L("المحظورين: \(s.d.blocked.count)", "Blocked: \(s.d.blocked.count)"))
                    if !s.d.blocked.isEmpty { Button(L("إلغاء كل الحظر", "Unblock all")) { s.d.blocked = [] } }
                    Link(L("سياسة الخصوصية", "Privacy policy"), destination: URL(string: "https://moha700m.github.io/rafeeq-ios/privacy.html")!)
                    Link(L("الدعم", "Support"), destination: URL(string: "https://moha700m.github.io/rafeeq-ios/")!)
                }
                Section { Button(L("حذف الحساب وكل البيانات", "Delete account and all data"), role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle(L("الإعدادات", "Settings"))
            .toolbar { Button(L("تم", "Done")) { dismiss() } }
            .alert(L("متأكد؟ ما تقدر ترجعها", "Are you sure? This can't be undone"), isPresented: $confirmDelete) {
                Button(L("احذف", "Delete"), role: .destructive) { s.deleteAccount(); dismiss() }
                Button(L("إلغاء", "Cancel"), role: .cancel) {}
            }
        }
    }
}
