import SwiftUI

@main
struct RafeeqApp: App {
    @StateObject private var store: Store
    init() {
        let args = ProcessInfo.processInfo.arguments
        let demo = args.contains("-demo")
        let s = Store(defaults: demo ? UserDefaults(suiteName: "demo")! : .standard, demo: demo)
        if let i = args.firstIndex(of: "-lang"), i + 1 < args.count, let l = Lang(rawValue: args[i + 1]) { s.setLang(l) }
        _store = StateObject(wrappedValue: s)
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .environment(\.layoutDirection, store.d.lang == .ar ? .rightToLeft : .leftToRight)
                .environment(\.locale, Locale(identifier: store.d.lang.rawValue))
                .preferredColorScheme(.dark)
                .task { await store.refreshCatalog() }
                .onOpenURL { url in if url.host == "invite", let c = url.pathComponents.last { _ = store.addFriend(code: c) } }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var s: Store
    @State private var tab = 0
    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = Int(args[i + 1]) { _tab = State(initialValue: t) }
    }
    var body: some View {
        Group {
            if !s.d.onboarded { OnboardingView() }
            else {
                TabView(selection: $tab) {
                    HomeView().tag(0).tabItem { Label(L("رفيقي", "Pet"), systemImage: "house.fill") }
                    FriendsView().tag(1).tabItem { Label(L("الربع", "Friends"), systemImage: "person.2.fill") }
                    DayView().tag(2).tabItem { Label(L("يومي", "Today"), systemImage: "checkmark.circle.fill") }
                    TripsView().tag(3).tabItem { Label(L("رحلات", "Trips"), systemImage: "map.fill") }
                    ShopView().tag(4).tabItem { Label(L("المتجر", "Shop"), systemImage: "bag.fill") }
                }.tint(.white)
            }
        }
        .overlay(alignment: .top) { if let t = s.toast { Toast(text: t) } }
        .animation(.spring(duration: 0.35), value: s.toast)
        .id(s.d.lang)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var s: Store
    @State private var kind: PetKind = .cat
    @State private var name = ""
    var body: some View {
        ZStack {
            SceneBG(image: "adv_taif")
            VStack(spacing: 18) {
                HStack { Spacer(); Button(s.d.lang == .ar ? "English" : "العربية") { s.setLang(s.d.lang == .ar ? .en : .ar) }.font(.subheadline.bold()).padding(10).glass(16) }
                Text(L("اختر رفيقك", "Choose your companion")).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white).shadowText()
                Text(L("يكبر معك كل ما أنجزت عاداتك", "It grows as you build your habits")).foregroundStyle(.white.opacity(0.9))
                Image(kind.babyImage).resizable().scaledToFit().frame(height: 240).shadow(radius: 20).id(kind).transition(.scale.combined(with: .opacity))
                HStack(spacing: 12) {
                    ForEach(PetKind.allCases) { k in
                        Button { withAnimation(.spring) { kind = k } } label: {
                            VStack { Image(k.babyImage).resizable().scaledToFit().frame(height: 60); Text(k.title).font(.footnote.bold()) }
                                .padding(10).frame(maxWidth: .infinity).glass(20, interactive: true)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: kind == k ? 2.5 : 0))
                        }.buttonStyle(.plain)
                    }
                }
                TextField(kind.defaultName, text: $name).padding(14).glass(18).multilineTextAlignment(.center)
                Button { s.onboard(kind: kind, name: name) } label: {
                    Text(L("يلا نبدأ", "Let's start")).font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(16).background(.white, in: Capsule())
                }
            }.padding(22).frame(maxWidth: 520)
        }
    }
}
