import SwiftUI

struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var interactive = false
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.foregroundStyle(.white)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        } else {
            content.foregroundStyle(.white)
                .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.45), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }
}
extension View {
    func glass(_ r: CGFloat = 24, interactive: Bool = false) -> some View { modifier(GlassCard(radius: r, interactive: interactive)) }
    func shadowText() -> some View { shadow(color: .black.opacity(0.35), radius: 6, y: 2) }
}

struct SceneBG: View {
    var image: String
    var blur: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            Image(image).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped().blur(radius: blur)
                .overlay(LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea()
    }
}

struct EggView: View {
    var size: CGFloat = 120
    var body: some View {
        Ellipse().fill(RadialGradient(colors: [.white, Color(red: 0.96, green: 0.88, blue: 0.75), Color(red: 0.85, green: 0.64, blue: 0.36)], center: .init(x: 0.4, y: 0.3), startRadius: 2, endRadius: size * 0.7))
            .frame(width: size * 0.8, height: size)
            .overlay(Circle().fill(Color.brown.opacity(0.5)).frame(width: size * 0.1).offset(x: -size * 0.12, y: -size * 0.1))
            .overlay(Circle().fill(Color.brown.opacity(0.5)).frame(width: size * 0.08).offset(x: size * 0.15, y: size * 0.2))
            .shadow(color: .yellow.opacity(0.5), radius: 20)
    }
}

struct PetView: View {
    var pet: Pet
    var size: CGFloat = 240
    @State private var bounce = false
    var body: some View {
        ZStack(alignment: .top) {
            if pet.stage == .egg { EggView(size: size * 0.6) }
            else {
                Image(pet.imageName).resizable().scaledToFit()
                    .frame(width: size * (pet.stage == .baby ? 0.85 : 1), height: size * (pet.stage == .baby ? 0.85 : 1))
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 14)
            }
            HStack(spacing: 4) { ForEach(pet.equipped, id: \.self) { id in Text(Accessory.symbol(id)).font(.system(size: size * 0.12)) } }.offset(y: -6)
        }
        .scaleEffect(bounce ? 1.03 : 0.98, anchor: .bottom)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bounce)
        .onAppear { bounce = true }
        .accessibilityLabel(pet.name)
    }
}
enum Accessory { static func symbol(_ id: String) -> String { ["crown": "👑", "glasses": "🕶️", "scarf": "🧣"][id] ?? "" } }

struct Pill: View {
    var symbol: String; var text: String
    var body: some View { Label(text, systemImage: symbol).font(.system(.subheadline, design: .rounded).weight(.bold)).padding(.horizontal, 12).padding(.vertical, 7).glass(18) }
}

struct ProgressBar: View {
    var value: Double; var tint: Color = .white
    var body: some View {
        GeometryReader { g in ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25))
            Capsule().fill(tint).frame(width: max(8, g.size.width * value))
        }.environment(\.layoutDirection, L10n.lang == .ar ? .rightToLeft : .leftToRight) }.frame(height: 8)
    }
}

struct Toast: View {
    var text: String
    var body: some View { Text(text).font(.callout.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 12).glass(20).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)) }
}

struct SectionTitle: View {
    var text: String
    var body: some View { Text(text).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(.white).shadowText().frame(maxWidth: .infinity, alignment: .leading) }
}
