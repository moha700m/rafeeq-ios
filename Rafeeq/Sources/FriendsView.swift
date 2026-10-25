import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var s: Store
    @State private var mode = 0
    @State private var visiting: Friend?
    @State private var reporting: Friend?
    @State private var code = ""
    var body: some View {
        ZStack {
            SceneBG(image: "adv_empty_quarter")
            ScrollView {
                VStack(spacing: 14) {
                    SectionTitle(text: L("الربع", "Friends"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(s.visibleFriends) { f in
                                Button { visiting = f } label: {
                                    VStack {
                                        Image(f.pet.babyImage).resizable().scaledToFit().frame(width: 56, height: 56).padding(4)
                                            .background(Circle().fill(.white.opacity(0.85))).overlay(Circle().stroke(AngularGradient(colors: [.yellow, .pink, .cyan, .yellow], center: .center), lineWidth: 3))
                                        Text(f.name).font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Picker("", selection: $mode) { Text(L("الحين", "Now")).tag(0); Text(L("الدوري", "League")).tag(1); Text(L("أضف", "Add")).tag(2) }.pickerStyle(.segmented)
                    if mode == 0 {
                        HStack { VStack(alignment: .leading) { Text(L("سلسلة الربع", "Group streak")).bold(); Text(L("كلكم أنجزتوا عادة اليوم؟ لا تكسرونها", "Everyone did a habit today? Keep it alive")).font(.caption) }; Spacer(); Text("\(s.d.groupStreak)").font(.system(size: 34, weight: .heavy, design: .rounded)) }.padding(16).glass()
                        ForEach(s.visibleFriends) { f in FriendCard(f: f, visit: { visiting = f }, report: { reporting = f }) }
                        if s.visibleFriends.isEmpty { Text(L("ما عندك ربع للحين، شارك كودك", "No friends yet, share your code")).padding(20).glass() }
                    } else if mode == 1 { LeagueView() }
                    else { addFriend }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .sheet(item: $visiting) { f in RoomVisitView(f: f) }
        .confirmationDialog(L("بلاغ أو حظر", "Report or block"), isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), presenting: reporting) { f in
            Button(L("محتوى غير لائق", "Inappropriate content"), role: .destructive) { s.report(f, reason: "inappropriate") }
            Button(L("إزعاج أو تنمر", "Harassment or bullying"), role: .destructive) { s.report(f, reason: "harassment") }
            Button(L("حظر فقط", "Block only"), role: .destructive) { s.block(f) }
            Button(L("إلغاء", "Cancel"), role: .cancel) {}
        }
    }
    var addFriend: some View {
        VStack(spacing: 12) {
            Text(L("كودك", "Your code")).font(.caption)
            Text(s.d.inviteCode).font(.system(size: 38, weight: .heavy, design: .monospaced)).environment(\.layoutDirection, .leftToRight)
            ShareLink(item: URL(string: "rafeeq://invite/\(s.d.inviteCode)")!, message: Text(L("تعال كبّر رفيقك معي في رفيق، كودي \(s.d.inviteCode)", "Join me on Rafeeq, my code is \(s.d.inviteCode)"))) { Label(L("شارك الدعوة", "Share invite"), systemImage: "square.and.arrow.up").bold().padding(12).glass(16, interactive: true) }
            TextField(L("كود صاحبك", "Friend's code"), text: $code).textInputAutocapitalization(.characters).multilineTextAlignment(.center).padding(14).glass(16)
            Button(L("أضف", "Add")) { if s.addFriend(code: code) { code = "" } else { s.show(L("الكود غلط", "Invalid code")) } }.bold().padding(12).frame(maxWidth: .infinity).background(.white, in: Capsule()).foregroundStyle(.black)
            Text(L("الصداقة بالكود فقط، وما فيه دردشة مفتوحة", "Friends by code only, no open chat")).font(.caption2).opacity(0.8)
        }.padding(18).glass().foregroundStyle(.white)
    }
}

struct FriendCard: View {
    @EnvironmentObject var s: Store
    var f: Friend; var visit: () -> Void; var report: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(f.name).bold()
                if f.sample { Text(L("تجريبي", "Sample")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.25), in: Capsule()) }
                Spacer()
                Label("\(f.streak)", systemImage: "flame.fill").font(.caption.bold())
                Menu { Button(L("بلاغ", "Report"), systemImage: "flag", action: report); Button(L("حظر", "Block"), systemImage: "hand.raised", role: .destructive) { s.block(f) } } label: { Image(systemName: "ellipsis").padding(8) }.accessibilityLabel(L("خيارات", "Options"))
            }
            HStack(spacing: 12) {
                Image(f.pet.babyImage).resizable().scaledToFit().frame(width: 70, height: 70)
                VStack(alignment: .leading) { Text("\(f.petName) · \(L("مستوى", "Lv")) \(f.level)").font(.subheadline.bold()); Text(Safety.clean(f.status)).font(.callout) }
            }
            HStack(spacing: 8) {
                Button { _ = s.cheer(f) } label: { Label(L("شجّع", "Cheer"), systemImage: "bolt.fill").font(.caption.bold()).padding(8).glass(14, interactive: true) }
                Button(action: visit) { Label(L("زُر غرفته", "Visit room"), systemImage: "house.fill").font(.caption.bold()).padding(8).glass(14, interactive: true) }
            }.buttonStyle(.plain)
        }.padding(14).glass().foregroundStyle(.white)
    }
}

struct LeagueView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        let rows = (s.visibleFriends.map { ($0.name, $0.weekScore, false) } + [(L("أنت", "You"), s.weekScore, true)]).sorted { $0.1 > $1.1 }
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label(L("دوري الأسبوع", "Weekly league"), systemImage: "trophy.fill").bold(); Spacer(); Text(L("ترتيبك \(s.leagueRank)", "Rank \(s.leagueRank)")).font(.caption.bold()) }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack { Text("\(i + 1)").bold().foregroundStyle(.yellow).frame(width: 24); Text(r.0).fontWeight(r.2 ? .heavy : .regular); Spacer(); Text("\(r.1)").bold() }.padding(.vertical, 4)
            }
            Text(L("يتجدد الدوري كل أحد", "League resets every Sunday")).font(.caption2).opacity(0.8)
        }.padding(16).glass().foregroundStyle(.white)
    }
}

struct RoomVisitView: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) var dismiss
    var f: Friend
    @State private var liked = false
    var body: some View {
        ZStack {
            SceneBG(image: "adv_alula")
            VStack(spacing: 16) {
                HStack { Text(L("غرفة \(f.petName)", "\(f.petName)'s room")).font(.title.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").padding(10).glass(14) } }
                ZStack(alignment: .bottom) {
                    Image("room_majlis").resizable().scaledToFit()
                    Image(f.pet.babyImage).resizable().scaledToFit().frame(height: 170).offset(y: -20)
                }.padding(10).glass(28)
                Text(Safety.clean(f.status)).padding(12).glass(16)
                HStack(spacing: 10) {
                    Button { _ = s.cheer(f) } label: { Label(L("شجّع +١٠", "Cheer +10"), systemImage: "bolt.fill").frame(maxWidth: .infinity).padding(12).glass(18, interactive: true) }
                    Button { if let item = s.d.owned.first { _ = s.gift(f, itemId: item) } else { s.show(L("ما عندك أغراض تهديها، اشتر من المتجر", "No items to gift, visit the shop")) } } label: { Label(L("هدية", "Gift"), systemImage: "gift.fill").frame(maxWidth: .infinity).padding(12).glass(18, interactive: true) }
                    Button { liked.toggle() } label: { Label(L("عجبني", "Like"), systemImage: liked ? "heart.fill" : "heart").frame(maxWidth: .infinity).padding(12).glass(18, interactive: true) }
                }.buttonStyle(.plain).font(.subheadline.bold())
                Spacer()
            }.padding(18).foregroundStyle(.white)
        }
    }
}
