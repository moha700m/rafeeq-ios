import SwiftUI

struct DayView: View {
    @EnvironmentObject var s: Store
    @State private var journal = ""
    let moods: [(String, String, String)] = [("😄", "رايق", "Great"), ("🙂", "زين", "Good"), ("😐", "عادي", "Okay"), ("😕", "تعبان", "Tired"), ("😣", "مضغوط", "Stressed")]
    var body: some View {
        ZStack {
            SceneBG(image: "adv_taif", blur: 8)
            ScrollView {
                VStack(spacing: 14) {
                    SectionTitle(text: L("كيف يومك؟", "How's your day?"))
                    HStack {
                        ForEach(0..<5, id: \.self) { i in
                            Button { withAnimation(.spring) { s.setMood(i) } } label: {
                                VStack(spacing: 4) { Text(moods[i].0).font(.system(size: 32)); Text(L(moods[i].1, moods[i].2)).font(.caption2.bold()) }
                                    .frame(maxWidth: .infinity).opacity(s.todayLog.mood == nil || s.todayLog.mood == i ? 1 : 0.45).scaleEffect(s.todayLog.mood == i ? 1.12 : 1)
                            }.buttonStyle(.plain)
                        }
                    }.padding(12).glass().foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("سؤال \(s.d.pet.name)", "\(s.d.pet.name) asks")).font(.caption)
                        Text(L(s.prompt.ar, s.prompt.en)).font(.headline)
                        TextField(L("اكتب سطر أو سطرين…", "Write a line or two…"), text: $journal, axis: .vertical).lineLimit(2...4).padding(10).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .onSubmit { s.setJournal(journal) }.onChange(of: journal) { _, v in s.setJournal(v) }
                        Text(L("يومياتك خاصة لك وما تنشارك", "Your journal is private")).font(.caption2).opacity(0.8)
                    }.padding(16).glass().foregroundStyle(.white)
                    VStack(spacing: 0) { ForEach(s.habits) { h in HabitRow(h: h); Divider().overlay(.white.opacity(0.2)) } }.padding(.horizontal, 16).padding(.vertical, 6).glass()
                    HStack { Label(L("تجميد السلسلة: \(s.d.freezes)", "Streak freezes: \(s.d.freezes)"), systemImage: "snowflake"); Spacer(); Label("\(s.d.streak)", systemImage: "flame.fill") }.font(.subheadline.bold()).padding(14).glass().foregroundStyle(.white)
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
        }.onAppear { journal = s.todayLog.journal }
    }
}
