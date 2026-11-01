import Foundation

public struct AgentStep: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case thought, toolCall, toolResult, denied, error, final }
    public var id: UUID = UUID()
    public var kind: Kind
    public var title: String
    public var detail: String
    public var toolName: String?
    public var date: Date = Date()

    public init(kind: Kind, title: String, detail: String, toolName: String? = nil) {
        self.kind = kind; self.title = title; self.detail = detail; self.toolName = toolName
    }
}

public struct AgentProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var summary: String
    public var instructions: String
    public var toolNames: [String]
    public var maxSteps: Int
    public var builtIn: Bool

    public init(id: String = UUID().uuidString, name: String, icon: String, summary: String,
                instructions: String, toolNames: [String], maxSteps: Int = 6, builtIn: Bool = false) {
        self.id = id; self.name = name; self.icon = icon; self.summary = summary
        self.instructions = instructions; self.toolNames = toolNames; self.maxSteps = maxSteps; self.builtIn = builtIn
    }

    public static let allCoreTools = [
        "calculator", "current_datetime", "hijri_date", "prayer_times", "qibla", "zakat", "vat",
        "end_of_service", "knowledge_search", "read_document", "notes_add", "notes_search",
        "create_reminder", "create_event", "image_text", "web_search",
    ]

    public static let builtIns: [AgentProfile] = [
        AgentProfile(id: "sanad", name: "وكيل سَنَد الشامل", icon: "wand.and.stars",
                     summary: "يخطط وينفّذ بكل الأدوات المتاحة",
                     instructions: "أنت وكيل عام ذكي. قسّم المهمة لخطوات واستخدم الأدوات عند الحاجة للحصول على معلومات دقيقة بدلاً من التخمين.",
                     toolNames: allCoreTools, maxSteps: 8, builtIn: true),
        AgentProfile(id: "researcher", name: "باحث المستندات", icon: "doc.text.magnifyingglass",
                     summary: "يبحث في قاعدة معرفتك ويجيب مع المصادر",
                     instructions: "ابحث دائماً في قاعدة المعرفة أولاً، وأجب فقط بما تجده مع ذكر اسم المستند بين قوسين [ ]. إذا لم تجد الإجابة فقل ذلك.",
                     toolNames: ["knowledge_search", "read_document", "calculator", "notes_add"], maxSteps: 6, builtIn: true),
        AgentProfile(id: "finance", name: "المستشار المالي", icon: "banknote",
                     summary: "زكاة، ضريبة القيمة المضافة، مكافأة نهاية الخدمة",
                     instructions: "أنت مساعد مالي سعودي. استخدم أدوات الحساب دائماً ولا تحسب ذهنياً. اعرض النتيجة بالريال السعودي مع شرح مختصر للخطوات، ونبّه أن المرجع الرسمي هو هيئة الزكاة والضريبة والجمارك.",
                     toolNames: ["zakat", "vat", "end_of_service", "calculator", "hijri_date"], maxSteps: 6, builtIn: true),
        AgentProfile(id: "organizer", name: "منظّم المهام", icon: "checklist",
                     summary: "تذكيرات، مواعيد، ملاحظات، مواقيت الصلاة",
                     instructions: "أنت منظّم شخصي. حوّل طلبات المستخدم إلى تذكيرات أو مواعيد أو ملاحظات باستخدام الأدوات. راعِ أوقات الصلاة عند اقتراح المواعيد. استخدم current_datetime لمعرفة الوقت الحالي قبل تحديد أي تاريخ.",
                     toolNames: ["current_datetime", "hijri_date", "prayer_times", "create_reminder", "create_event", "notes_add", "notes_search"], maxSteps: 6, builtIn: true),
        AgentProfile(id: "coder", name: "المبرمج", icon: "terminal",
                     summary: "يكتب ويراجع الكود ويحفظ المقتطفات",
                     instructions: "You are a senior engineer. Write correct code in fenced blocks. Use notes_add to save useful snippets when the user asks. Explain briefly in Arabic.",
                     toolNames: ["calculator", "notes_add", "notes_search", "image_text"], maxSteps: 4, builtIn: true),
    ]
}

public enum AgentEvent {
    case step(AgentStep)
    case partial(String)
    case finished(String)
}

/// ReAct-style loop: the model reasons, optionally emits one tool call, sees the result, repeats.
public final class AgentLoop {
    public let backend: LLMBackend
    public let registry: ToolRegistry
    public var allowNetwork: Bool
    /// Asked before running a tool that requires confirmation. Return `true` to allow.
    public var confirm: (ToolSpec, ToolArguments) async -> Bool
    public var now: () -> Date

    public init(backend: LLMBackend, registry: ToolRegistry, allowNetwork: Bool = false,
                confirm: @escaping (ToolSpec, ToolArguments) async -> Bool = { _, _ in false },
                now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.registry = registry
        self.allowNetwork = allowNetwork
        self.confirm = confirm
        self.now = now
    }

    public func systemPrompt(for profile: AgentProfile) -> String {
        let specs = registry.specs(for: profile.toolNames, allowNetwork: allowNetwork)
        let tools = specs.map(\.promptDescription).joined(separator: "\n")
        return """
        \(profile.instructions)

        التاريخ الحالي: \(Hijri.describe(now())).

        # الأدوات
        لديك الأدوات التالية:
        <tools>
        \(tools)
        </tools>

        # طريقة العمل
        - فكّر بإيجاز فيما تحتاجه.
        - لاستخدام أداة، اكتب سطراً واحداً بالضبط بهذا الشكل ثم توقف:
        <tool_call>
        {"name": "اسم_الأداة", "arguments": {"المعامل": "القيمة"}}
        </tool_call>
        - ستصلك النتيجة داخل <tool_response>. يمكنك استدعاء أداة أخرى إذا احتجت.
        - عندما تكتمل المعلومات اكتب الإجابة النهائية للمستخدم مباشرة بدون أي <tool_call>.
        - لا تخترع نتائج الأدوات أبداً.
        """
    }

    public func run(goal: String, history: [ChatMessage] = [], profile: AgentProfile,
                    settings: GenerationSettings = .agent,
                    onEvent: @escaping (AgentEvent) -> Void) async throws -> (answer: String, steps: [AgentStep]) {
        var steps: [AgentStep] = []
        func emit(_ s: AgentStep) { steps.append(s); onEvent(.step(s)) }

        var messages: [ChatMessage] = [ChatMessage(role: .system, content: systemPrompt(for: profile))]
        messages += history.filter { $0.role == .user || $0.role == .assistant }.suffix(6)
        messages.append(ChatMessage(role: .user, content: goal))

        let known = Set(registry.specs(for: profile.toolNames, allowNetwork: allowNetwork).map(\.name))
        var lastCallSignature: String?

        for _ in 0..<max(1, profile.maxSteps) {
            try Task.checkCancellation()
            var streamed = ""
            let (raw, _) = try await backend.generate(messages: messages, settings: settings,
                                                       stop: ["</tool_call>", "<tool_response>"]) { piece in
                streamed += piece
                if !streamed.contains("<tool_call>") && !streamed.contains("{\"name\"") {
                    onEvent(.partial(ThinkingFilter.strip(streamed)))
                }
                return !Task.isCancelled
            }
            let completed = raw.contains("<tool_call>") && !raw.contains("</tool_call>") ? raw + "</tool_call>" : raw
            let parsed = ToolCallParser.parse(completed, knownTools: known)

            if let t = parsed.thinking, !t.isEmpty { emit(AgentStep(kind: .thought, title: "تفكير", detail: t)) }

            guard let call = parsed.call else {
                let answer = parsed.text.isEmpty ? ThinkingFilter.strip(raw) : parsed.text
                emit(AgentStep(kind: .final, title: "الإجابة", detail: answer))
                onEvent(.finished(answer))
                return (answer, steps)
            }

            if !parsed.text.isEmpty { emit(AgentStep(kind: .thought, title: "خطة", detail: parsed.text)) }
            let argsJSON = JSONValue.object(call.arguments).compactJSON
            guard let tool = registry.tool(named: call.name), known.contains(call.name) else {
                emit(AgentStep(kind: .error, title: "أداة غير معروفة", detail: call.name))
                messages.append(ChatMessage(role: .assistant, content: completed))
                messages.append(ChatMessage(role: .user, content: "<tool_response>\nخطأ: الأداة \(call.name) غير متاحة. الأدوات المتاحة: \(known.sorted().joined(separator: ", "))\n</tool_response>"))
                continue
            }
            emit(AgentStep(kind: .toolCall, title: tool.spec.title, detail: argsJSON, toolName: call.name))

            let signature = call.name + argsJSON
            var result: String
            if signature == lastCallSignature {
                result = "تم تنفيذ نفس الاستدعاء للتو. استخدم النتيجة السابقة واكتب الإجابة النهائية."
            } else if tool.spec.requiresConfirmation, !(await confirm(tool.spec, call.arguments)) {
                result = "رفض المستخدم تنفيذ هذه الأداة. لا تحاول مرة أخرى، وأخبره بما كنت ستفعله."
                emit(AgentStep(kind: .denied, title: "رفض المستخدم", detail: tool.spec.title, toolName: call.name))
            } else {
                do {
                    result = try await tool.run(call.arguments)
                    emit(AgentStep(kind: .toolResult, title: "نتيجة \(tool.spec.title)", detail: result, toolName: call.name))
                } catch {
                    result = "خطأ: \(error.localizedDescription)"
                    emit(AgentStep(kind: .error, title: "فشل \(tool.spec.title)", detail: error.localizedDescription, toolName: call.name))
                }
            }
            lastCallSignature = signature
            if result.count > 4000 { result = String(result.prefix(4000)) + "\n…(مقتطع)" }

            messages.append(ChatMessage(role: .assistant,
                                        content: "<tool_call>\n{\"name\": \"\(call.name)\", \"arguments\": \(argsJSON)}\n</tool_call>"))
            messages.append(ChatMessage(role: .user, content: "<tool_response>\n\(result)\n</tool_response>"))
        }

        // Out of steps: ask for a final answer without tools.
        messages.append(ChatMessage(role: .user, content: "انتهى عدد الخطوات المسموح. اكتب الآن أفضل إجابة نهائية ممكنة بناءً على ما سبق، بدون أدوات."))
        var acc = ""
        let (raw, _) = try await backend.generate(messages: messages, settings: settings, stop: ["<tool_call>"]) { piece in
            acc += piece
            onEvent(.partial(ThinkingFilter.strip(acc))); return !Task.isCancelled
        }
        let answer = ThinkingFilter.strip(raw)
        emit(AgentStep(kind: .final, title: "الإجابة", detail: answer))
        onEvent(.finished(answer))
        return (answer, steps)
    }
}
