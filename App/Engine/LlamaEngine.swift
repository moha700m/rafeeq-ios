import Foundation
import llama

/// On-device inference with llama.cpp (GGUF, Metal on device / CPU in the simulator).
final class LlamaEngine: LLMBackend, @unchecked Sendable {
    private static let backendInit: Void = { llama_backend_init() }()

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var template: String?
    private(set) var modelPath: String?
    private(set) var contextLength: Int = 4096
    private let lock = NSLock()

    var isReady: Bool { ctx != nil }

    deinit { unload() }

    func load(path: String, contextLength: Int) throws {
        _ = Self.backendInit
        unload()
        var mp = llama_model_default_params()
        #if targetEnvironment(simulator)
        mp.n_gpu_layers = 0
        #else
        mp.n_gpu_layers = 999
        #endif
        guard let m = llama_model_load_from_file(path, mp) else {
            throw LLMError.loadFailed("الملف تالف أو غير مدعوم")
        }
        let trainCtx = Int(llama_model_n_ctx_train(m))
        let nCtx = max(512, min(contextLength, trainCtx > 0 ? trainCtx : contextLength))
        var cp = llama_context_default_params()
        cp.n_ctx = UInt32(nCtx)
        cp.n_batch = 512
        cp.n_ubatch = 512
        let threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        cp.n_threads = threads
        cp.n_threads_batch = threads
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            throw LLMError.loadFailed("تعذّر إنشاء السياق (الذاكرة غير كافية؟)")
        }
        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)
        if let t = llama_model_chat_template(m, nil) { template = String(cString: t) }
        modelPath = path
        self.contextLength = nCtx
    }

    func unload() {
        if let c = ctx { llama_free(c) }
        if let m = model { llama_model_free(m) }
        ctx = nil; model = nil; vocab = nil; template = nil; modelPath = nil
    }

    // MARK: - Prompt

    func formatPrompt(_ messages: [ChatMessage]) -> String {
        guard let tmpl = template else { return ChatMLFormatter.format(messages) }
        let roles = messages.map { strdup($0.role == .tool ? "user" : $0.role.rawValue) }
        let contents = messages.map { strdup($0.content) }
        defer { (roles + contents).forEach { free($0) } }
        var chat = zip(roles, contents).map { llama_chat_message(role: $0, content: $1) }
        var cap = max(4096, messages.reduce(0) { $0 + $1.content.utf8.count } * 2 + 1024)
        for _ in 0..<2 {
            var buf = [CChar](repeating: 0, count: cap)
            let n = llama_chat_apply_template(tmpl, &chat, chat.count, true, &buf, Int32(cap))
            if n < 0 { return ChatMLFormatter.format(messages) }
            if Int(n) <= cap {
                return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            cap = Int(n) + 1
        }
        return ChatMLFormatter.format(messages)
    }

    private func tokenize(_ text: String) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 16)
        var n = llama_tokenize(vocab, text, Int32(utf8Count), &tokens, Int32(tokens.count), true, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, Int32(utf8Count), &tokens, Int32(tokens.count), true, true)
        }
        return Array(tokens.prefix(Int(max(0, n))))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        var buf = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        }
        return buf.prefix(Int(max(0, n))).map { UInt8(bitPattern: $0) }
    }

    // MARK: - Generation

    func generate(messages: [ChatMessage], settings: GenerationSettings, stop: [String],
                  onToken: @escaping (String) -> Bool) async throws -> (text: String, stats: GenerationStats) {
        try await Task.detached(priority: .userInitiated) { [self] in
            lock.lock(); defer { lock.unlock() }
            return try generateSync(messages: messages, settings: settings, stop: stop, onToken: onToken)
        }.value
    }

    private func generateSync(messages input: [ChatMessage], settings: GenerationSettings, stop: [String],
                              onToken: (String) -> Bool) throws -> (text: String, stats: GenerationStats) {
        guard let ctx, let vocab else { throw LLMError.noModelLoaded }
        var messages = input
        if let p = modelPath?.lowercased(), p.contains("qwen3"), !settings.enableThinking,
           let i = messages.lastIndex(where: { $0.role == .user }) {
            messages[i].content += " /no_think"
        }

        // Fit prompt into context: drop oldest non-system turns.
        let budget = contextLength - min(settings.maxTokens, contextLength / 2) - 8
        var tokens = tokenize(formatPrompt(messages))
        while tokens.count > budget {
            guard let drop = messages.firstIndex(where: { $0.role != .system }), messages.count > 2 else {
                throw LLMError.contextOverflow
            }
            messages.remove(at: drop)
            tokens = tokenize(formatPrompt(messages))
        }

        llama_memory_clear(llama_get_memory(ctx), true)

        let start = Date()
        // Prompt processing in batches.
        var offset = 0
        while offset < tokens.count {
            let n = min(512, tokens.count - offset)
            let rc: Int32 = tokens.withUnsafeMutableBufferPointer { buf in
                llama_decode(ctx, llama_batch_get_one(buf.baseAddress! + offset, Int32(n)))
            }
            if rc != 0 { throw LLMError.decodeFailed(rc) }
            offset += n
        }

        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(smpl) }
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(Int32(settings.topK)))
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(Float(settings.topP), 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, Float(settings.repeatPenalty), 0, 0))
        if settings.temperature <= 0.01 {
            llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(Float(settings.temperature)))
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(settings.seed))
        }

        var bytes: [UInt8] = []
        var emitted = 0 // number of characters already sent
        var text = ""
        var generated = 0
        let genStart = Date()
        var token: llama_token = 0
        var stopped = false

        while generated < settings.maxTokens && !stopped {
            if Task.isCancelled { break }
            token = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token)
            generated += 1

            // Only decode complete UTF-8 sequences (Arabic is multi-byte).
            if let s = String(bytes: bytes, encoding: .utf8) {
                text = s
                if let hit = stop.compactMap({ text.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                    text = String(text[..<hit.lowerBound])
                    stopped = true
                }
                // Hold back a tail that could be the start of a stop string.
                let hold = stopped ? 0 : (stop.map(\.count).max() ?? 0)
                let safeEnd = max(emitted, text.count - hold)
                if safeEnd > emitted {
                    let startIdx = text.index(text.startIndex, offsetBy: emitted)
                    let endIdx = text.index(text.startIndex, offsetBy: safeEnd)
                    if !onToken(String(text[startIdx..<endIdx])) { break }
                    emitted = safeEnd
                }
            }
            if stopped { break }

            var t = token
            let rc = llama_decode(ctx, llama_batch_get_one(&t, 1))
            if rc != 0 { throw LLMError.decodeFailed(rc) }
            if tokens.count + generated >= contextLength - 2 { break }
        }
        if !stopped, emitted < text.count {
            _ = onToken(String(text[text.index(text.startIndex, offsetBy: emitted)...]))
        }
        let genSeconds = Date().timeIntervalSince(genStart)
        _ = start
        return (text, GenerationStats(promptTokens: tokens.count, generatedTokens: generated, seconds: genSeconds))
    }
}
