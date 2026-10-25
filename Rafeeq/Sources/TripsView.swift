import SwiftUI

struct TripsView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        ZStack {
            SceneBG(image: "adv_alula")
            ScrollView {
                VStack(spacing: 14) {
                    SectionTitle(text: L("رحلات وأحداث", "Trips & events"))
                    if let e = s.liveEvent { EventCard(e: e, live: true) }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let a = s.d.adventure, let p = s.catalog.places.first(where: { $0.id == a.placeId }) {
                            let rem = s.adventureRemaining() ?? 0
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("\(s.d.pet.name) في \(p.title)", "\(s.d.pet.name) is in \(p.title)")).bold()
                                ProgressBar(value: 1 - rem / max(1, a.end.timeIntervalSince(a.start)), tint: .yellow)
                                if rem <= 0 { Button(L("استلم الغنايم", "Collect rewards")) { s.collectAdventure() }.bold().padding(10).frame(maxWidth: .infinity).background(.white, in: Capsule()).foregroundStyle(.black) }
                                else { Text(L("يرجع بعد \(Duration.seconds(rem).formatted(.time(pattern: .hourMinuteSecond)))", "Back in \(Duration.seconds(rem).formatted(.time(pattern: .hourMinuteSecond)))")).font(.caption) }
                            }.padding(16).glass().foregroundStyle(.white)
                        }
                    }
                    ForEach(s.catalog.places) { p in
                        HStack(spacing: 12) {
                            Image(p.image).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 4) { Text(p.title).font(.headline); Text(p.desc).font(.caption); Text(L("\(Int(p.hours)) ساعات · \(p.reward) عملة", "\(Int(p.hours))h · \(p.reward) coins")).font(.caption2.bold()).foregroundStyle(.yellow) }
                            Spacer()
                            Button(L("أرسل", "Send")) { if s.startAdventure(p) { s.show(L("\(s.d.pet.name) طلع \(p.title)!", "\(s.d.pet.name) left for \(p.title)!")) } else { s.show(L("في رحلة الحين أو طاقته قليلة", "Already on a trip or not enough energy")) } }
                                .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 8).background(.white, in: Capsule()).foregroundStyle(.black).disabled(s.d.adventure != nil)
                        }.padding(12).glass().foregroundStyle(.white)
                    }
                    ForEach(s.catalog.events.filter { !Engine.isLive($0, now: Date()) }) { e in EventCard(e: e, live: false) }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
    }
}

struct EventCard: View {
    var e: SeasonEvent; var live: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(e.image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading) { Text(live ? L("● حدث مباشر", "● Live event") : L("قريبًا", "Coming soon")).font(.caption.bold()).foregroundStyle(live ? .yellow : .white.opacity(0.8)); Text(e.title).font(.title3.bold()); Text(e.desc).font(.caption) } }
            if live { ProgressBar(value: Double(e.progress) / Double(max(1, e.goal)), tint: .yellow)
                Text(L("ينتهي \(e.end.formatted(.relative(presentation: .named)))", "Ends \(e.end.formatted(.relative(presentation: .named)))")).font(.caption2) }
        }.padding(16).glass().foregroundStyle(.white)
    }
}
