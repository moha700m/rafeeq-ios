import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject var s: Store
    @State private var showSettings = false
    @State private var photo: PhotosPickerItem?
    @State private var snap: UIImage? = Snapshot.load()
    var body: some View {
        ZStack {
            SceneBG(image: "adv_taif")
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("هلا والله", "Hello")).foregroundStyle(.white.opacity(0.9))
                            Text(s.d.pet.name).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white).shadowText()
                            Text("\(s.d.pet.kind.title) · \(s.d.pet.stage.title) · \(L("مستوى", "Lv")) \(s.d.pet.level)").font(.footnote.bold()).foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Pill(symbol: "flame.fill", text: "\(s.d.streak)")
                            Pill(symbol: "circle.hexagongrid.fill", text: "\(s.d.coins)")
                        }
                        Button { showSettings = true } label: { Image(systemName: "gearshape.fill").padding(10).glass(16) }.accessibilityLabel(L("الإعدادات", "Settings"))
                    }
                    Text(s.petLine).font(.callout.weight(.semibold)).padding(12).glass(18).frame(maxWidth: .infinity, alignment: .trailing)
                    PetView(pet: s.d.pet, size: 230).frame(height: 240).onTapGesture { s.haptic(); s.show(s.petLine) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(L("طاقة اليوم", "Today's energy")).bold(); Spacer(); Text("\(Int(s.todayProgress * 100))٪").bold() }
                        ProgressBar(value: s.todayProgress)
                        ForEach(s.habits.prefix(4)) { h in HabitRow(h: h, compact: true) }
                    }.padding(16).glass()
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            VStack(spacing: 4) { Image(systemName: "camera.fill").font(.title2); Text(L("لقطة اليوم", "Daily snap")).font(.footnote.bold()) }.frame(maxWidth: .infinity).padding(14).glass(20, interactive: true)
                        }
                        ShareLink(item: ShareCard.image(store: s), preview: SharePreview(L("رفيقي", "My Rafeeq"), image: ShareCard.image(store: s))) {
                            VStack(spacing: 4) { Image(systemName: "square.and.arrow.up.fill").font(.title2); Text(L("شارك", "Share")).font(.footnote.bold()) }.frame(maxWidth: .infinity).padding(14).glass(20, interactive: true)
                        }
                    }.foregroundStyle(.white)
                    if let snap { Image(uiImage: snap).resizable().scaledToFill().frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 22)) }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: photo) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                try? img.jpegData(compressionQuality: 0.8)?.write(to: Snapshot.url); snap = img; s.d.pet.xp += 5 } }
        }
    }
}

struct HabitRow: View {
    @EnvironmentObject var s: Store
    var h: Habit; var compact = false
    var body: some View {
        let done = s.todayLog.done.contains(h.id)
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { s.toggle(h) } } label: {
            HStack(spacing: 12) {
                Image(systemName: h.symbol).frame(width: 26)
                Text(h.title).bold()
                Spacer()
                Text("+\(h.energy)").font(.caption.bold()).foregroundStyle(.yellow)
                ZStack {
                    Circle().stroke(.white.opacity(0.8), lineWidth: 1.5).frame(width: 30, height: 30)
                    if done { Circle().fill(.white).frame(width: 30, height: 30); Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green) }
                }.scaleEffect(done ? 1.1 : 1)
            }.padding(.vertical, compact ? 4 : 10).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.white)
        .accessibilityLabel("\(h.title) \(done ? L("تم", "done") : "")")
    }
}

enum ShareCard {
    @MainActor static func image(store s: Store) -> Image {
        let v = ZStack {
            Image("adv_taif").resizable().scaledToFill().frame(width: 1080 / 3, height: 1920 / 3).clipped()
            VStack(spacing: 12) {
                Text(L("رفيقي", "My Rafeeq")).font(.system(size: 30, weight: .heavy, design: .rounded))
                Image(s.d.pet.imageName).resizable().scaledToFit().frame(height: 260)
                Text(s.d.pet.name).font(.title.bold())
                Text(L("🔥 \(s.d.streak) يوم سلسلة · مستوى \(s.d.pet.level)", "🔥 \(s.d.streak)-day streak · Lv \(s.d.pet.level)")).font(.headline)
                Text(L("حمّل رفيق وكبّر رفيقك معي · كودي \(s.d.inviteCode)", "Get Rafeeq and grow with me · code \(s.d.inviteCode)")).font(.footnote)
            }.foregroundStyle(.white).shadow(radius: 6)
        }.frame(width: 360, height: 640)
        let r = ImageRenderer(content: v); r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) } ?? Image("adv_taif")
    }
}
