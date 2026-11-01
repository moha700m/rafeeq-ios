import Foundation
import SwiftUI

enum AppTab: String, CaseIterable {
    case chat, agents, models, lens, more
}

/// App-wide settings persisted in UserDefaults.
final class AppSettings: ObservableObject {
    @AppStorage("generation") private var generationData: Data = Data()
    @AppStorage("personaID") var personaID: String = Persona.general.id
    @AppStorage("webAccess2") var webAccess: Bool = true
    @AppStorage("memoryEnabled") var memoryEnabled: Bool = true
    @AppStorage("customInstructions") var customInstructions: String = ""
    /// "local" or a cloud provider id.
    @AppStorage("defaultModelRef") var defaultModelRef: String = "local"
    @AppStorage("speakReplies") var speakReplies: Bool = false
    @AppStorage("oledDark") var oledDark: Bool = false
    @AppStorage("appearance") var appearance: Int = 0 // 0 system, 1 light, 2 dark
    @AppStorage("accent") var accent: Int = 0
    @AppStorage("ignoreMemoryCheck") var ignoreMemoryCheck: Bool = false
    @AppStorage("serverPort") var serverPort: Int = 8080
    @AppStorage("agentMaxSteps") var agentMaxSteps: Int = 6
    @AppStorage("defaultCity") var defaultCity: String = "الرياض"
    @AppStorage("goldPrice") var goldPrice: String = ""

    var generation: GenerationSettings {
        get { (try? JSONDecoder().decode(GenerationSettings.self, from: generationData)) ?? GenerationSettings() }
        set { generationData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }

    static let accents: [(String, Color)] = [
        ("أخضر سعودي", Color("AccentColor")), ("ذهبي", Color("Gold")), ("أزرق", .blue),
        ("بنفسجي", .purple), ("برتقالي", .orange), ("وردي", .pink),
    ]
    var accentColor: Color { Self.accents[min(max(accent, 0), Self.accents.count - 1)].1 }

    var colorScheme: ColorScheme? { appearance == 1 ? .light : appearance == 2 ? .dark : nil }
}

@MainActor
final class AppState: ObservableObject {
    @Published var tab: AppTab = .chat
    @Published var deepLinkScreen: String?
    @Published var conversations: [Conversation] = []
    @Published var agents: [AgentProfile] = []
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var lensHandoff: String?
    /// Query handed in from Siri/Shortcuts; opened as a new chat.
    @Published var pendingQuery: String?
    var pendingAutoSend: String?

    let settings = AppSettings()
    let engine: LlamaEngine
    let models: ModelManager
    let registry = ToolRegistry()
    let knowledge = KnowledgeBase.shared
    let notes = NotesStore.shared
    let memory = MemoryStore.shared
    let server: LocalAPIServer
    let mcp: MCPManager
    @Published var providers: [ProviderConfig] = []

    /// Latest image text from the Lens, available to the `image_text` tool.
    var lastImageText: String?

    struct PendingConfirmation: Identifiable {
        let id = UUID()
        let spec: ToolSpec
        let arguments: ToolArguments
        let continuation: CheckedContinuation<Bool, Never>
    }

    init() {
        let engine = LlamaEngine()
        self.engine = engine
        self.models = ModelManager(engine: engine)
        self.mcp = MCPManager(registry: registry)
        self.server = LocalAPIServer(
            backend: { engine },
            modelName: { UserDefaults.standard.string(forKey: "activeModelID") ?? "none" },
            apiKey: { Keychain.get("apiKey") })
        conversations = Storage.load([Conversation].self, from: "conversations.json") ?? []
        let custom = Storage.load([AgentProfile].self, from: "agents.json") ?? []
        agents = AgentProfile.builtIns + custom
        providers = Storage.load([ProviderConfig].self, from: "providers.json") ?? []
        CoreTools.register(into: registry, knowledge: knowledge, notes: notes, memory: memory)
        AppTools.register(into: registry, state: self)
        AppStateHolder.shared = self
        applyLaunchArguments()
    }

    var engineReady: Bool { isReady(settings.defaultModelRef) }

    // MARK: Model routing (local ↔ cloud)

    func provider(for ref: String?) -> ProviderConfig? {
        let r = ref ?? settings.defaultModelRef
        return providers.first { $0.id == r }
    }

    func isReady(_ ref: String?) -> Bool {
        if let p = provider(for: ref) { return p.kind == .custom || Keychain.get(p.keychainKey)?.isEmpty == false }
        return engine.isReady
    }

    func backend(for ref: String?) -> LLMBackend {
        if let p = provider(for: ref) { return CloudBackend(config: p, apiKey: Keychain.get(p.keychainKey) ?? "") }
        return engine
    }

    func modelName(for ref: String?) -> String {
        if let p = provider(for: ref) { return p.displayName }
        return models.activeModel?.name ?? "نموذج محلي"
    }

    func isCloud(_ ref: String?) -> Bool { provider(for: ref) != nil }

    func saveProvider(_ p: ProviderConfig, key: String?) {
        if let i = providers.firstIndex(where: { $0.id == p.id }) { providers[i] = p } else { providers.append(p) }
        if let key { key.isEmpty ? Keychain.delete(p.keychainKey) : Keychain.set(key, for: p.keychainKey) }
        Storage.save(providers, to: "providers.json")
    }

    func deleteProvider(_ p: ProviderConfig) {
        providers.removeAll { $0.id == p.id }
        Keychain.delete(p.keychainKey)
        if settings.defaultModelRef == p.id { settings.defaultModelRef = "local" }
        Storage.save(providers, to: "providers.json")
    }

    /// System-prompt suffix with the user's custom instructions and long-term memory.
    var personalContext: String {
        var s = ""
        let ci = settings.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ci.isEmpty { s += "\n\n# تعليمات المستخدم المخصصة\n" + ci }
        if settings.memoryEnabled { s += memory.promptBlock() }
        return s
    }

    // MARK: Persistence

    func saveConversations() {
        let snapshot = conversations
        Task.detached(priority: .utility) { Storage.save(snapshot, to: "conversations.json") }
    }

    func upsert(_ c: Conversation) {
        if let i = conversations.firstIndex(where: { $0.id == c.id }) { conversations[i] = c } else { conversations.insert(c, at: 0) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversations()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        saveConversations()
    }

    func saveAgent(_ a: AgentProfile) {
        if let i = agents.firstIndex(where: { $0.id == a.id }) { agents[i] = a } else { agents.append(a) }
        Storage.save(agents.filter { !$0.builtIn }, to: "agents.json")
    }

    func deleteAgent(_ id: String) {
        agents.removeAll { $0.id == id && !$0.builtIn }
        Storage.save(agents.filter { !$0.builtIn }, to: "agents.json")
    }

    // MARK: Agent

    func makeAgentLoop(ref: String? = nil) -> AgentLoop {
        let loop = makeAgentLoopBase(backend(for: ref))
        loop.extraContext = personalContext
        return loop
    }

    private func makeAgentLoopBase(_ b: LLMBackend) -> AgentLoop {
        AgentLoop(backend: b, registry: registry, allowNetwork: settings.webAccess,
                  confirm: { [weak self] spec, args in
                      guard let self else { return false }
                      return await withCheckedContinuation { cont in
                          Task { @MainActor in
                              self.pendingConfirmation = PendingConfirmation(spec: spec, arguments: args, continuation: cont)
                          }
                      }
                  })
    }

    func resolveConfirmation(_ allowed: Bool) {
        pendingConfirmation?.continuation.resume(returning: allowed)
        pendingConfirmation = nil
    }

    // MARK: Privacy

    func wipeAllData() {
        server.stop()
        models.unload()
        conversations = []
        knowledge.removeAll()
        notes.removeAll()
        memory.removeAll()
        providers.forEach { Keychain.delete($0.keychainKey) }
        providers = []
        mcp.servers.forEach { Keychain.delete($0.keychainKey) }
        agents = AgentProfile.builtIns
        Keychain.delete("apiKey")
        try? FileManager.default.removeItem(at: Storage.root)
        try? FileManager.default.createDirectory(at: Storage.root, withIntermediateDirectories: true)
        if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
    }

    // MARK: Launch arguments (used by CI screenshots)

    private func applyLaunchArguments() {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetOnboarding") { d.set(false, forKey: "seenOnboarding") }
        if d.bool(forKey: "seenOnboard") { d.set(true, forKey: "seenOnboarding") }
        if let t = d.string(forKey: "tab"), let tab = AppTab(rawValue: t) { self.tab = tab }
        deepLinkScreen = d.string(forKey: "screen")
        if d.bool(forKey: "demo") { DemoContent.install(into: self) }
    }
}
