import Foundation

@Observable
class ShortcutGenerator {
    private let ollama: OllamaService
    private let compiler: CherriCompiler
    private let scheduler: ScheduleService
    private let systemPrompt: String

    var isGenerating = false
    var currentStatus = ""

    init(
        ollama: OllamaService = OllamaService(),
        compiler: CherriCompiler = CherriCompiler(),
        scheduler: ScheduleService = ScheduleService()
    ) {
        self.ollama = ollama
        self.compiler = compiler
        self.scheduler = scheduler
        self.systemPrompt = Self.loadSystemPrompt()
    }

    // MARK: - Public API

    func generate(description: String, model: String = "qwen2.5-coder:7b") async throws -> GenerationResult {
        isGenerating = true
        defer {
            isGenerating = false
            currentStatus = ""
        }

        currentStatus = "Analyzing schedule..."
        let extraction = try await extractSchedule(from: description, model: model)

        let codeDescription: String = {
            if let ext = extraction, ext.hasSchedule, let actionOnly = ext.actionOnly, !actionOnly.isEmpty {
                return actionOnly
            }
            return description
        }()

        let schedule = buildSchedule(from: extraction, fallbackName: shortcutName(from: codeDescription))

        // Infer a human-friendly name in parallel with code generation
        currentStatus = "Generating Cherri code..."
        async let nameTask = inferName(from: codeDescription, model: model)
        async let codeTask = callModel(description: codeDescription, model: model, previousAttempt: nil, previousError: nil)

        let (inferredName, firstResponse) = try await (nameTask, codeTask)
        var cherriCode = extractCodeFromResponse(firstResponse)

        if cherriCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return GenerationResult(
                success: false, cherriCode: firstResponse,
                shortcutURL: nil, schedule: schedule,
                error: "LLM returned no parseable code.", inferredName: inferredName
            )
        }

        // Smell test — if the model wrote JavaScript/Python, retry before compiling
        if let jsError = detectWrongLanguage(cherriCode) {
            currentStatus = "Wrong language detected — correcting..."
            let fixedResponse = try await callModel(
                description: codeDescription, model: model,
                previousAttempt: cherriCode, previousError: jsError
            )
            let fixedCode = extractCodeFromResponse(fixedResponse)
            if !fixedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cherriCode = fixedCode
            }
        }

        // Use the inferred name as the file name for compilation
        let fileName = shortcutName(from: inferredName.isEmpty ? codeDescription : inferredName)
        currentStatus = "Compiling shortcut..."

        do {
            let result = try await compiler.compile(source: cherriCode, name: fileName, skipSign: true)
            return GenerationResult(success: true, cherriCode: cherriCode, shortcutURL: result.shortcutURL, schedule: schedule, error: nil, inferredName: inferredName)
        } catch {
            let firstError = error.localizedDescription

            currentStatus = "Repairing with compiler feedback..."
            let retryResponse = try await callModel(
                description: codeDescription, model: model,
                previousAttempt: cherriCode, previousError: firstError
            )
            let retryCode = extractCodeFromResponse(retryResponse)

            if !retryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cherriCode = retryCode
                do {
                    let result = try await compiler.compile(source: retryCode, name: fileName, skipSign: true)
                    return GenerationResult(success: true, cherriCode: retryCode, shortcutURL: result.shortcutURL, schedule: schedule, error: nil, inferredName: inferredName)
                } catch {
                    return GenerationResult(success: false, cherriCode: retryCode, shortcutURL: nil, schedule: schedule, error: error.localizedDescription, inferredName: inferredName)
                }
            }

            return GenerationResult(success: false, cherriCode: cherriCode, shortcutURL: nil, schedule: schedule, error: firstError, inferredName: inferredName)
        }
    }

    func rewritePrompt(from description: String, model: String) async throws -> String {
        isGenerating = true
        currentStatus = "Rewriting prompt..."
        defer {
            isGenerating = false
            currentStatus = ""
        }

        let prompt = """
        Rewrite the user request below so a Cherri code generator can implement it.
        Stay as close to the original intent as possible — do NOT add new complexity.
        Replace foreign-language words with English descriptions of what they mean.
        Keep URLs and quoted markers exactly as written.
        Return ONLY the rewritten description.

        Original request:
        \(description)
        """
        let rewritten = try await ollama.generate(
            prompt: prompt,
            systemPrompt: "You translate user Shortcuts requests into clearer English. Output ONLY the rewritten request.",
            model: model
        )
        return rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recompile(code: String, name: String) async throws -> GenerationResult {
        isGenerating = true
        currentStatus = "Compiling shortcut..."
        defer {
            isGenerating = false
            currentStatus = ""
        }

        let resolvedName = shortcutName(from: name)
        do {
            let result = try await compiler.compile(source: code, name: resolvedName, skipSign: true)
            return GenerationResult(success: true, cherriCode: code, shortcutURL: result.shortcutURL, schedule: nil, error: nil, inferredName: name)
        } catch {
            return GenerationResult(success: false, cherriCode: code, shortcutURL: nil, schedule: nil, error: error.localizedDescription, inferredName: name)
        }
    }

    /// Ask the LLM for a short, human-friendly title for this shortcut (2–4 words, Title Case).
    /// Falls back to the heuristic name if the LLM returns empty or fails.
    func inferName(from description: String, model: String) async -> String {
        let prompt = """
        Give a SHORT name (2–4 words, Title Case) for an Apple Shortcut that does the following:

        \(description)

        Rules:
        - 2 to 4 words maximum
        - Title Case (e.g. "Show Battery Level", "Fetch Menu Items")
        - No punctuation, no quotes, no explanations
        - Output ONLY the name, nothing else
        """
        do {
            let response = try await ollama.generate(
                prompt: prompt,
                systemPrompt: "You generate short, descriptive names for Apple Shortcuts. Output only the name.",
                model: model
            )
            let cleaned = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
            if !cleaned.isEmpty && cleaned.count < 60 {
                return cleaned
            }
        } catch {}
        return shortcutName(from: description)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func signAndExport(code: String, name: String) async throws -> URL {
        let resolvedName = shortcutName(from: name)
        let result = try await compiler.compile(source: code, name: resolvedName, skipSign: false)
        return result.shortcutURL
    }

    func installSchedule(_ schedule: Schedule, shortcutName: String) async throws {
        try await scheduler.install(schedule: schedule, shortcutName: shortcutName)
    }

    func uninstallSchedule(_ schedule: Schedule) async throws {
        try await scheduler.uninstall(schedule: schedule)
    }

    // MARK: - Language smell test

    /// Returns a human-readable error if the code looks like JavaScript, Python, or another
    /// language rather than Cherri — before we waste a compile call on it.
    private func detectWrongLanguage(_ code: String) -> String? {
        struct Signal {
            let pattern: String
            let description: String
        }
        let signals: [Signal] = [
            Signal(pattern: #"(?m)^\s*(let|var)\s+\w+\s*="#,       description: "uses `let`/`var` declarations (JavaScript)"),
            Signal(pattern: #"(?m)===|!=="#,                         description: "uses `===`/`!==` equality (JavaScript)"),
            Signal(pattern: #"(?m)console\.(log|error|warn)"#,       description: "uses `console.log` (JavaScript)"),
            Signal(pattern: #"(?m)function\s*\w*\s*\("#,             description: "uses `function()` syntax (JavaScript)"),
            Signal(pattern: #"(?m)^\s*def\s+\w+\s*\("#,             description: "uses `def` function definitions (Python)"),
            Signal(pattern: #"(?m)^\s*import\s+\w"#,                description: "uses `import` statements (Python/JS)"),
            Signal(pattern: #"(?m)\bprint\s*\("#,                    description: "uses `print()` (Python)"),
            Signal(pattern: #"(?m);\s*$"#,                           description: "has semicolons at end of lines (JavaScript/Java)"),
        ]

        var found: [String] = []
        for signal in signals {
            if let regex = try? NSRegularExpression(pattern: signal.pattern),
               regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                found.append(signal.description)
            }
        }

        guard !found.isEmpty else { return nil }

        return """
        WRONG LANGUAGE: The code you wrote is NOT Cherri. Detected: \(found.joined(separator: "; ")).
        Cherri variables use `@name = "value"` — NOT `let name`, `var name`, or `const name`.
        Cherri has no semicolons, no `===`, no `function()`, no `print()`, no `import`.
        Rewrite the entire program from scratch using only the Cherri syntax shown in the examples.
        """
    }

    // MARK: - Code generation (with RAG)

    private func callModel(
        description: String,
        model: String,
        previousAttempt: String?,
        previousError: String?
    ) async throws -> String {
        let examples = CherriExamples.relevant(for: description, topK: 3)
        let exampleBlock: String
        if examples.isEmpty {
            exampleBlock = ""
        } else {
            let rendered = examples.map { $0.asPromptBlock }.joined(separator: "\n\n")
            exampleBlock = """

            Below are working Cherri snippets for similar tasks. Adapt them; do not copy URLs or text verbatim — substitute the real values from the user request.

            \(rendered)

            """
        }

        let repairBlock: String
        if let attempt = previousAttempt, let err = previousError {
            let hint = repairHint(forError: err, code: attempt)
            repairBlock = """

            Your previous attempt FAILED to compile. Here is the failed code and the compiler error.
            Re-emit the FULL corrected program. Do not explain — just code.

            Failed code:
            ```
            \(attempt)
            ```

            Compiler error:
            ```
            \(err)
            ```
            \(hint)
            """
        } else {
            repairBlock = ""
        }

        let prompt = """
        Create a Cherri shortcut that does the following:

        \(description)
        \(exampleBlock)\(repairBlock)
        Hard rules — every program must satisfy these:
        - EVERY variable name MUST start with `@`. Both when defining (`@url = "..."`) and when using (`getWebpageContents(@url)`). Bare identifiers like `url = "..."` are a SYNTAX ERROR and will not compile. Constants use `const name = ...` (no `@`); everything else uses `@`.
        - Use the EXACT URLs, words, file paths, and other literals from the user's request as string literals in the code.
        - Do NOT call prompt() to ask the user for values that are already given in the request. Only use prompt() if the user explicitly says "ask me", "prompt me", or "let me enter".
        - Cherri has NO string concatenation operator. NEVER write `"a" + @b + "c"`. Use interpolation: `"a{b}c"`.
        - When building a regex from two literal markers, write the markers DIRECTLY into the pattern: `matchText("MARKER1([\\\\s\\\\S]*?)MARKER2", @page, false)`. Do not interpolate variables into the pattern.
        - Every action result must be assigned to a `@variable` before being referenced (e.g. `@matches = matchText(...)`, then `getMatchGroup(@matches, 1)`).
        - When fetching a webpage to read its content, use `getWebpageContents(url)`. Do NOT use `openURL` for fetching.

        Output ONLY raw Cherri source code. No markdown fences, no commentary. The code must compile as-is.
        """

        return try await ollama.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            model: model
        )
    }

    /// Cherri's compiler errors are often cryptic ("Illegal character 'u'", "Unexpected token").
    /// Translate them into concrete fix instructions so the retry has something to act on.
    private func repairHint(forError error: String, code: String) -> String {
        var hints: [String] = []
        let lower = error.lowercased()

        // The classic case: bare identifier on the left of `=`. Cherri sees it as illegal.
        if lower.contains("illegal character") || lower.contains("unexpected") {
            if let bareAssignment = firstBareAssignmentName(in: code) {
                hints.append("Likely cause: line `\(bareAssignment) = ...` is missing the `@` prefix. Rewrite as `@\(bareAssignment) = ...` and update every reference to `@\(bareAssignment)`.")
            } else {
                hints.append("Likely cause: a bare identifier is being used where Cherri expects `@name` for a variable or `const name` for a constant.")
            }
        }

        if lower.contains("undefined") || lower.contains("not defined") {
            hints.append("Likely cause: a `@variable` is referenced before it is assigned. Make sure every action result is captured: `@result = action(...)` before any later use of `@result`.")
        }

        if lower.contains("invalid value") && lower.contains("inputtype") {
            hints.append("Likely cause: prompt() was used with the wrong argument order. Either remove the prompt() call (use a string literal instead) or use the correct signature: prompt(text question, ?inputType, ?defaultValue, ?multiline).")
        }

        if hints.isEmpty { return "" }

        return """

            Hints:
            - \(hints.joined(separator: "\n            - "))
            """
    }

    /// Find the first occurrence of `name = ...` (no `@`) at the start of a line
    /// outside of strings. Returns the bare identifier so we can name it in the hint.
    private func firstBareAssignmentName(in code: String) -> String? {
        for raw in code.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("#include") { continue }
            if line.hasPrefix("@") || line.hasPrefix("const ") { continue }
            // Match: identifier at start, then `=` (not `==`), with no `(` between (not a call).
            guard let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z_]\w*)\s*=\s*[^=]"#) else { return nil }
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                if !["if", "else", "for", "repeat", "menu", "item", "action"].contains(name) {
                    return name
                }
            }
        }
        return nil
    }

    // MARK: - Schedule extraction (unchanged)

    private func extractSchedule(from description: String, model: String) async throws -> ScheduleExtraction? {
        let prompt = """
        Analyze this request and extract scheduling information. Return ONLY a JSON object, nothing else.

        Request: "\(description)"

        If there is NO scheduling (no time, no "every day", no "daily", no "for N days"), return:
        {"has_schedule": false}

        If there IS scheduling, return:
        {
          "has_schedule": true,
          "hour": 7,
          "minute": 0,
          "recurrence": "daily",
          "weekday": null,
          "duration_days": 10,
          "action_only": "open the podcast app"
        }

        Rules:
        - hour: 0-23 (24h format)
        - minute: 0-59
        - recurrence: "once", "daily", or "weekly"
        - weekday: 1=Monday...7=Sunday (only for weekly, null otherwise)
        - duration_days: number of days to run, null if indefinite
        - action_only: the request with scheduling words removed

        Return ONLY valid JSON.
        """

        let response = try await ollama.generate(
            prompt: prompt,
            systemPrompt: "You are a JSON extraction tool. Output ONLY valid JSON objects.",
            model: model
        )

        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ScheduleExtraction.self, from: data)
    }

    private func buildSchedule(from extraction: ScheduleExtraction?, fallbackName: String) -> Schedule? {
        guard let ext = extraction, ext.hasSchedule, let hour = ext.hour, let minute = ext.minute else {
            return nil
        }
        let recurrence: Schedule.Recurrence
        switch ext.recurrence?.lowercased() {
        case "weekly": recurrence = .weekly
        case "once":   recurrence = .once
        default:       recurrence = .daily
        }
        return Schedule(
            hour: hour,
            minute: minute,
            recurrence: recurrence,
            weekday: ext.weekday,
            durationDays: ext.durationDays,
            startDate: Date(),
            label: fallbackName
        )
    }

    // MARK: - Response parsing

    /// Strip markdown fences and stray prose so we hand the compiler raw Cherri.
    private func extractCodeFromResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // ```cherri ... ```
        if let fenced = extractFenced(trimmed, language: "cherri") { return fenced }
        // ``` ... ```
        if let fenced = extractFenced(trimmed, language: nil) { return fenced }

        return trimmed
    }

    private func extractFenced(_ text: String, language: String?) -> String? {
        let opener = language.map { "```\($0)" } ?? "```"
        guard let openRange = text.range(of: opener) else { return nil }

        let afterOpen = text[openRange.upperBound...]
        let bodyStart: String.Index
        if let nl = afterOpen.firstIndex(of: "\n") {
            bodyStart = text.index(after: nl)
        } else {
            bodyStart = openRange.upperBound
        }

        let body = text[bodyStart...]
        if let closeRange = body.range(of: "```") {
            return String(body[body.startIndex..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSON(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start <= end {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    // MARK: - Naming

    private func shortcutName(from description: String) -> String {
        let fillerWords: Set<String> = [
            "create", "make", "build", "generate", "a", "an", "the", "that", "which",
            "to", "for", "with", "from", "automation", "shortcut", "please", "can",
            "you", "i", "want", "need", "would", "like", "should", "it", "do", "my"
        ]
        let words = description
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !fillerWords.contains($0) && !$0.hasPrefix("http") }
            .prefix(4)
        let name = words.joined(separator: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") })
            .replacingOccurrences(of: "__", with: "_")
        return cleaned.isEmpty ? "shortcut" : String(cleaned.prefix(50))
    }

    // MARK: - System prompt

    private static func loadSystemPrompt() -> String {
        if let url = Bundle.main.url(forResource: "CherriLLMGuide", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return """
        You are a Cherri code generator. Cherri is a programming language that compiles to Apple Shortcuts.
        Use only documented Cherri actions. Always assign action results to @variables before referencing them.
        Output ONLY raw Cherri code, no markdown fences.
        """
    }
}
