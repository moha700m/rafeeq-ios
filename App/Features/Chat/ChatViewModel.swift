import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversation: Conversation
    @Published var input = ""
    @Published var streaming = ""
    @Published var liveSteps: [AgentStep] = []
    @Published var isGenerating = false
    @Published var error: String?

    private weak var state: AppState?
    private var task: Task<Void, Never>?

    init(conversation: Conversation, state: AppState) {
        self.conversation = conversation
        self.state = state
    }

    var agent: AgentProfile? {
        guard let id = conversation.agentID else { return nil }
        return state?.agents.first { $0.id == id }
    }

    var persona: Persona { Persona.by(id: conversation.personaID) }

    func send(_ text: String? = nil) {
        let content = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isGenerating, let state else { return }
        input = ""
        error = nil
        guard state.engineReady else {
            error = LLMError.noModelLoaded.localizedDescription
            input = content
            return
        }
        let history = conversation.messages
        conversation.messages.append(ChatMessage(role: .user, content: content))
        if conversation.messages.count == 1 {
            conversation.title = String(content.prefix(40))
        }
        conversation.modelID = state.models.activeModelID
        persist()
        isGenerating = true
        streaming = ""
        liveSteps = []

        task = Task { [weak self] in
            guard let self else { return }
            if let agent = self.agent {
                await self.runAgent(agent, goal: content, history: history, state: state)
            } else {
                await self.runChat(state: state)
            }
            self.isGenerating = false
            self.streaming = ""
            self.persist()
        }
    }

    private func runChat(state: AppState) async {
        var settings = state.settings.generation
        settings.maxTokens = max(64, settings.maxTokens)
        var msgs = [ChatMessage(role: .system, content: persona.systemPrompt + "\nالتاريخ: \(Hijri.describe(Date())).")]
        msgs += conversation.messages.filter { $0.role != .system }
        var acc = ""
        do {
            let (text, stats) = try await state.engine.generate(messages: msgs, settings: settings, stop: []) { [weak self] piece in
                acc += piece
                let shown = settings.hideThinking ? ThinkingFilter.strip(acc) : acc
                Task { @MainActor in self?.streaming = shown }
                return !Task.isCancelled
            }
            let final = settings.hideThinking ? ThinkingFilter.strip(text) : text
            conversation.messages.append(ChatMessage(role: .assistant, content: final.isEmpty ? "…" : final,
                                                     tokensPerSecond: stats.tokensPerSecond, tokenCount: stats.generatedTokens))
            if state.settings.speakReplies { SpeechService.shared.speak(final) }
        } catch {
            if !acc.isEmpty { conversation.messages.append(ChatMessage(role: .assistant, content: ThinkingFilter.strip(acc))) }
            self.error = error.localizedDescription
        }
    }

    private func runAgent(_ agent: AgentProfile, goal: String, history: [ChatMessage], state: AppState) async {
        let loop = state.makeAgentLoop()
        var profile = agent
        profile.maxSteps = min(agent.maxSteps, max(2, state.settings.agentMaxSteps))
        do {
            let (answer, steps) = try await loop.run(goal: goal, history: history, profile: profile) { [weak self] ev in
                Task { @MainActor in
                    switch ev {
                    case .step(let s): self?.liveSteps.append(s); self?.streaming = ""
                    case .partial(let p): self?.streaming = p
                    case .finished: break
                    }
                }
            }
            conversation.messages.append(ChatMessage(role: .assistant, content: answer, agentSteps: steps))
            if state.settings.speakReplies { SpeechService.shared.speak(answer) }
        } catch {
            if !liveSteps.isEmpty {
                conversation.messages.append(ChatMessage(role: .assistant, content: "توقف الوكيل.", agentSteps: liveSteps))
            }
            self.error = error is CancellationError ? nil : error.localizedDescription
        }
        liveSteps = []
    }

    func stop() {
        task?.cancel()
        SpeechService.shared.stopSpeaking()
    }

    func regenerate() {
        guard !isGenerating, let lastUser = conversation.messages.lastIndex(where: { $0.role == .user }) else { return }
        let text = conversation.messages[lastUser].content
        conversation.messages.removeSubrange(lastUser...)
        send(text)
    }

    func setPersona(_ p: Persona) { conversation.personaID = p.id; persist() }
    func setAgent(_ id: String?) { conversation.agentID = id; persist() }

    func persist() {
        conversation.updatedAt = Date()
        if !conversation.messages.isEmpty { state?.upsert(conversation) }
    }

    var exportText: String {
        conversation.messages.map { m in
            let who = m.role == .user ? "أنت" : "سَنَد"
            return "**\(who):**\n\(m.content)"
        }.joined(separator: "\n\n")
    }
}
