import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject var state: AppState
    @State private var path: [UUID] = []
    @State private var search = ""

    var filtered: [Conversation] {
        guard !search.isEmpty else { return state.conversations }
        let q = ArabicText.normalize(search)
        return state.conversations.filter {
            ArabicText.normalize($0.title).contains(q) || $0.messages.contains { ArabicText.normalize($0.content).contains(q) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if state.conversations.isEmpty {
                    EmptyStateView(icon: "sparkles", title: "أهلاً بك في سَنَد",
                                   message: "ذكاء اصطناعي يعمل على جهازك بالكامل، بدون إنترنت وبدون حساب. ابدأ محادثة جديدة.",
                                   action: ("محادثة جديدة", newChat))
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { c in
                    NavigationLink(value: c.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if c.agentID != nil { Image(systemName: "wand.and.stars").foregroundStyle(.tint).font(.caption) }
                                Text(c.title).font(.headline).lineLimit(1)
                            }
                            Text(c.messages.last?.content ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text(c.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in idx.map { filtered[$0].id }.forEach(state.deleteConversation) }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "ابحث في المحادثات")
            .safeAreaInset(edge: .top) { ModelStatusBanner() }
            .navigationTitle("سَنَد AI")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: newChat) { Image(systemName: "square.and.pencil") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversation: state.conversations.first { $0.id == id } ?? Conversation(id: id))
            }
            .onAppear {
                if UserDefaults.standard.bool(forKey: "demo"), state.tab == .chat, path.isEmpty,
                   let first = state.conversations.first(where: { $0.agentID == nil }) {
                    path = [first.id]
                }
            }
        }
    }

    func newChat() {
        let c = Conversation(personaID: state.settings.personaID)
        state.conversations.insert(c, at: 0)
        path = [c.id]
    }
}

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm: ChatViewModel
    @StateObject private var speech = SpeechService.shared
    @FocusState private var focused: Bool

    init(conversation: Conversation) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation, state: AppStateHolder.shared!))
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelStatusBanner()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(vm.conversation.messages) { m in
                            MessageBubble(message: m).id(m.id)
                        }
                        if vm.isGenerating {
                            if !vm.liveSteps.isEmpty { AgentTraceView(steps: vm.liveSteps, live: true) }
                            MessageBubble(message: ChatMessage(role: .assistant, content: vm.streaming.isEmpty ? "…" : vm.streaming))
                                .id("streaming")
                        }
                        if let e = vm.error {
                            Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.streaming) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: vm.conversation.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composer
        }
        .navigationTitle(vm.agent?.name ?? vm.persona.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("وضع الوكيل") {
                        Button { vm.setAgent(nil) } label: { Label("محادثة عادية", systemImage: vm.agent == nil ? "checkmark" : "bubble.left") }
                        ForEach(state.agents) { a in
                            Button { vm.setAgent(a.id) } label: { Label(a.name, systemImage: vm.agent?.id == a.id ? "checkmark" : a.icon) }
                        }
                    }
                    Section("الشخصية") {
                        ForEach(Persona.all) { p in
                            Button { vm.setPersona(p) } label: { Label(p.name, systemImage: vm.persona.id == p.id ? "checkmark" : p.icon) }
                        }
                    }
                    Section {
                        ShareLink(item: vm.exportText) { Label("مشاركة المحادثة", systemImage: "square.and.arrow.up") }
                        Button { vm.regenerate() } label: { Label("إعادة توليد آخر رد", systemImage: "arrow.clockwise") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { speech.onFinal = { text in vm.send(text) } }
    }

    @ViewBuilder var header: some View {
        if vm.conversation.messages.isEmpty && !vm.isGenerating {
            VStack(spacing: 14) {
                Image(systemName: vm.agent?.icon ?? vm.persona.icon).font(.system(size: 40)).foregroundStyle(.tint)
                Text(vm.agent?.name ?? vm.persona.name).font(.title2.bold())
                Text(vm.agent?.summary ?? "اسألني أي شيء — كل شيء يبقى على جهازك.").foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { vm.send(s) } label: {
                            Text(s).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
    }

    var suggestions: [String] {
        if let a = vm.agent {
            switch a.id {
            case "finance": return ["كم زكاة 120,000 ريال إذا سعر جرام الذهب 410 ريال؟", "سعر جوال 4,599 شامل الضريبة، كم الضريبة؟"]
            case "organizer": return ["ذكرني أتصل على أبوي بكرة بعد صلاة العصر", "وش مواقيت الصلاة في جدة اليوم؟"]
            case "researcher": return ["لخص لي أهم النقاط في مستنداتي", "ابحث في المستندات عن مدة العقد"]
            default: return ["كم باقي على رمضان بالهجري؟", "احسب مكافأة نهاية الخدمة لراتب 9000 و7 سنوات"]
            }
        }
        return ["اكتب لي رسالة تهنئة بالعيد لزملائي", "اشرح لي الذكاء الاصطناعي ببساطة", "ترجم: Thank you for your patience"]
    }

    var composer: some View {
        VStack(spacing: 6) {
            if speech.isListening {
                Text(speech.transcript.isEmpty ? "أستمع…" : speech.transcript).font(.footnote).foregroundStyle(.secondary)
            }
            if let e = speech.error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 8) {
                Button { speech.toggleListening() } label: {
                    Image(systemName: speech.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 30))
                        .symbolEffect(.pulse, isActive: speech.isListening)
                }
                TextField(vm.agent != nil ? "اطلب مهمة من الوكيل…" : "اكتب رسالتك…", text: $vm.input, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 20))
                    .onSubmit { vm.send() }
                if vm.isGenerating {
                    Button { vm.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 30)) }
                } else {
                    Button { vm.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                        .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }
}

struct MessageBubble: View {
    @EnvironmentObject var settings: AppSettings
    let message: ChatMessage
    @State private var showSteps = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let steps = message.agentSteps, !steps.isEmpty {
                DisclosureGroup(isExpanded: $showSteps) {
                    AgentTraceView(steps: steps, live: false)
                } label: {
                    Label("مسار الوكيل (\(steps.filter { $0.kind == .toolCall }.count) أدوات)", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption.weight(.semibold))
                }
                .padding(10)
                .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                if isUser { Spacer(minLength: 40) }
                Group {
                    if isUser { Text(message.content).textSelection(.enabled) } else { MarkdownText(text: message.content) }
                }
                .padding(12)
                .background(isUser ? settings.accentColor.opacity(0.9) : Color("CardBackground"),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(isUser ? .white : .primary)
                if !isUser { Spacer(minLength: 24) }
            }
            if let tps = message.tokensPerSecond, tps > 0 {
                Text(String(format: "%.1f رمز/ث · %d رمز", tps, message.tokenCount ?? 0))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .contextMenu {
            Button { UIPasteboard.general.string = message.content } label: { Label("نسخ", systemImage: "doc.on.doc") }
            Button { SpeechService.shared.speak(message.content) } label: { Label("قراءة بصوت", systemImage: "speaker.wave.2") }
            ShareLink(item: message.content)
        }
    }
}

/// Holds a reference so views can build view models without threading the environment through init.
@MainActor
enum AppStateHolder {
    static weak var shared: AppState?
}
