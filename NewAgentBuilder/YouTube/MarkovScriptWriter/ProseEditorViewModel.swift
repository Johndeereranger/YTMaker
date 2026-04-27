//
//  ProseEditorViewModel.swift
//  NewAgentBuilder
//
//  ViewModel for the Prose Editor tab.
//  Manages brief input, LLM generation, sentence-level markup,
//  reconstruction with locked anchors, and session persistence.
//

import Foundation

@MainActor
class ProseEditorViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Session State

    @Published var session = ProseEditorSession()

    // Brief form fields
    @Published var briefInput = ""
    @Published var styleProfileRef = ""

    // Working sentence array (current draft)
    @Published var sentences: [SentenceUnit] = []

    // UI phase
    @Published var phase: ProseEditorPhase = .brief
    @Published var isGenerating = false
    @Published var generatingMessage = ""
    @Published var errorMessage: String?

    // Inline editing
    @Published var editingId: UUID?
    @Published var editBuffer = ""

    // MARK: - Storage Key

    private let storageKey = "ProseEditor.CurrentSession"

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
        loadPersistedSession()
    }

    // MARK: - Brief Submission

    func submitBrief() {
        let trimmed = briefInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Brief cannot be empty."
            return
        }

        let brief = ProseBrief(
            rawInput: trimmed,
            styleProfileRef: styleProfileRef.isEmpty ? nil : styleProfileRef
        )
        session.brief = brief
        session.currentRound = 0
        session.drafts = []
        sentences = []

        Task { await reconstruct() }
    }

    // MARK: - Reconstruct (single code path for generate + iterate)

    func reconstruct() async {
        guard let brief = session.brief else {
            errorMessage = "No brief set."
            return
        }

        isGenerating = true
        phase = .generating
        generatingMessage = sentences.isEmpty
            ? "Generating prose..."
            : "Reconstructing (round \(session.currentRound + 1))..."

        let (systemPrompt, userPrompt) = buildReconstructPrompt(brief: brief, sentences: sentences)

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let llmBundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.6, "max_tokens": 4000]
        )

        guard let response = llmBundle else {
            errorMessage = "No response from AI."
            isGenerating = false
            phase = sentences.isEmpty ? .brief : .editing
            return
        }

        let rawResponse = response.content

        let newSentences = spliceResponse(
            rawResponse: rawResponse,
            currentSentences: sentences
        )

        let draft = ProseDraft(
            briefId: brief.id,
            round: session.currentRound,
            sentences: newSentences,
            rawAIResponse: rawResponse,
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens
        )
        session.drafts.append(draft)
        session.currentRound += 1

        sentences = newSentences
        isGenerating = false
        phase = .editing

        persistSession()
    }

    // MARK: - Prompt Construction

    func buildReconstructPrompt(brief: ProseBrief, sentences: [SentenceUnit]) -> (system: String, user: String) {

        let system = """
        You are a prose ghostwriter. You write prose based on a brief and optionally \
        revise a marked-up draft.

        RULES:
        1. Output one sentence per line. Raw prose only — no numbering, labels, or markers.
        2. When a marked-up draft is provided:
           - [KEEP] sentences are positional anchors handled by the system. Do NOT \
        reproduce them. Write ONLY the new content for non-KEEP positions.
           - [FLAGGED]: rewrite this sentence following the user's annotation.
           - [STRUCK]: write new content matching the annotation description.
           - [PENDING]: rewrite freely to improve flow and quality.
        3. The sentence count may change — you can merge or adjust as needed.
        4. Match the style reference if one is provided.
        """

        var userParts: [String] = []

        // Brief
        userParts.append("BRIEF:\n\(brief.rawInput)")

        // Style
        let style = brief.styleProfileRef ?? "Natural conversational tone"
        userParts.append("STYLE: \(style)")

        // Context from rambling gists (if available)
        let gists = coordinator.session.ramblingGists
        if !gists.isEmpty {
            let context = gists.prefix(5).map(\.sourceText).joined(separator: "\n\n")
            userParts.append("CONTEXT (background notes):\n\(context)")
        }

        // If this is initial generation (no sentences), just ask for prose
        if sentences.isEmpty {
            userParts.append("Write prose addressing this brief. One sentence per line, raw text only.")
        } else {
            // Build the marked-up draft
            var draftLines: [String] = []
            for s in sentences {
                switch s.status {
                case .keep, .edited:
                    draftLines.append("Position \(s.position) [KEEP]: \"\(s.text)\"")
                case .flagged:
                    let note = s.annotation ?? ""
                    draftLines.append("Position \(s.position) [FLAGGED]: \"\(s.text)\" NOTE: \"\(note)\"")
                case .struck:
                    let note = s.annotation ?? ""
                    draftLines.append("Position \(s.position) [STRUCK] NOTE: \"\(note)\"")
                case .pending:
                    draftLines.append("Position \(s.position) [PENDING]: \"\(s.text)\"")
                }
            }
            userParts.append("CURRENT DRAFT:\n\(draftLines.joined(separator: "\n"))")

            // Build gap descriptions
            let gaps = identifyGaps(in: sentences)
            if !gaps.isEmpty {
                var gapDesc: [String] = []
                for gap in gaps {
                    let posRange = gap.positions.map(String.init).joined(separator: ", ")
                    var desc = "Gap (positions \(posRange)"
                    if let before = gap.anchorBefore {
                        desc += ", after anchor at \(before)"
                    }
                    if let after = gap.anchorAfter {
                        desc += ", before anchor at \(after)"
                    }
                    desc += "): rewrite per annotations."
                    gapDesc.append(desc)
                }
                userParts.append("Write replacement prose for the non-KEEP positions only. Output one sentence per line for each gap, in order.\n\(gapDesc.joined(separator: "\n"))")
            } else {
                userParts.append("All sentences are locked. No output needed.")
            }
        }

        let user = userParts.joined(separator: "\n\n")
        return (system, user)
    }

    // MARK: - Gap Identification

    struct Gap {
        let positions: [Int]
        let anchorBefore: Int?
        let anchorAfter: Int?
    }

    private func identifyGaps(in sentences: [SentenceUnit]) -> [Gap] {
        var gaps: [Gap] = []
        var currentGapPositions: [Int] = []
        var lastAnchorPosition: Int? = nil

        for s in sentences {
            if s.isLocked {
                if !currentGapPositions.isEmpty {
                    gaps.append(Gap(
                        positions: currentGapPositions,
                        anchorBefore: lastAnchorPosition,
                        anchorAfter: s.position
                    ))
                    currentGapPositions = []
                }
                lastAnchorPosition = s.position
            } else {
                currentGapPositions.append(s.position)
            }
        }

        // Trailing gap (no anchor after)
        if !currentGapPositions.isEmpty {
            gaps.append(Gap(
                positions: currentGapPositions,
                anchorBefore: lastAnchorPosition,
                anchorAfter: nil
            ))
        }

        return gaps
    }

    // MARK: - Response Splicing

    func spliceResponse(rawResponse: String, currentSentences: [SentenceUnit]) -> [SentenceUnit] {
        // Parse AI output into clean sentence lines
        var aiSentences = rawResponse
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Strip common accidental formatting: "1. ", "- ", etc.
        aiSentences = aiSentences.map { line in
            var cleaned = line
            // Strip leading numbering: "1. ", "2) ", etc.
            if let range = cleaned.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                cleaned.removeSubrange(range)
            }
            // Strip leading dash
            if cleaned.hasPrefix("- ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        // Initial generation — no locked sentences, just map all AI output
        if currentSentences.isEmpty || currentSentences.allSatisfy({ !$0.isLocked }) {
            // Use SentenceParser if the AI didn't respect one-per-line
            let finalSentences: [String]
            if aiSentences.count <= 1, let single = aiSentences.first, single.count > 100 {
                finalSentences = SentenceParser.parse(single)
            } else {
                finalSentences = aiSentences
            }

            return finalSentences.enumerated().map { i, text in
                SentenceUnit(position: i, text: text, status: .pending)
            }
        }

        // Reconstruction: interleave locked anchors with AI gap-fill sentences
        var result: [SentenceUnit] = []
        var aiIndex = 0

        for s in currentSentences {
            if s.isLocked {
                // Insert locked sentence verbatim
                result.append(s)
            } else {
                // Fill from AI output
                if aiIndex < aiSentences.count {
                    result.append(SentenceUnit(
                        position: s.position,
                        text: aiSentences[aiIndex],
                        status: .pending
                    ))
                    aiIndex += 1
                }
                // If AI ran out, this position is dropped (count decreases)
            }
        }

        // If AI produced extra sentences, append them
        while aiIndex < aiSentences.count {
            result.append(SentenceUnit(
                position: result.count,
                text: aiSentences[aiIndex],
                status: .pending
            ))
            aiIndex += 1
        }

        // Re-index positions
        for i in 0..<result.count {
            result[i].position = i
        }

        return result
    }

    // MARK: - Sentence Mutations

    func markKeep(at index: Int) {
        guard index < sentences.count else { return }
        sentences[index].status = .keep
        sentences[index].annotation = nil
    }

    func markFlagged(at index: Int, annotation: String) {
        guard index < sentences.count else { return }
        sentences[index].status = .flagged
        sentences[index].annotation = annotation.isEmpty ? nil : annotation
    }

    func markStruck(at index: Int, annotation: String) {
        guard index < sentences.count else { return }
        sentences[index].status = .struck
        sentences[index].annotation = annotation.isEmpty ? nil : annotation
    }

    func editText(at index: Int, newText: String) {
        guard index < sentences.count else { return }
        if sentences[index].originalText == nil {
            sentences[index].originalText = sentences[index].text
        }
        sentences[index].text = newText
        sentences[index].status = .edited
    }

    func resetToPending(at index: Int) {
        guard index < sentences.count else { return }
        if let original = sentences[index].originalText {
            sentences[index].text = original
        }
        sentences[index].status = .pending
        sentences[index].annotation = nil
        sentences[index].originalText = nil
    }

    func markAllKeep() {
        for i in 0..<sentences.count {
            if sentences[i].status == .pending {
                sentences[i].status = .keep
            }
        }
    }

    // MARK: - Utilities

    var fullProseText: String {
        sentences
            .filter { $0.status != .struck }
            .map(\.text)
            .joined(separator: " ")
    }

    var sentenceStats: (total: Int, kept: Int, edited: Int, flagged: Int, struck: Int, pending: Int) {
        let s = sentences
        return (
            total: s.count,
            kept: s.filter({ $0.status == .keep }).count,
            edited: s.filter({ $0.status == .edited }).count,
            flagged: s.filter({ $0.status == .flagged }).count,
            struck: s.filter({ $0.status == .struck }).count,
            pending: s.filter({ $0.status == .pending }).count
        )
    }

    var hasWorkToDo: Bool {
        sentences.contains { $0.status == .flagged || $0.status == .struck || $0.status == .pending }
    }

    func goBackToBrief() {
        phase = .brief
    }

    // MARK: - Persistence

    func persistSession() {
        session.touch()
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func loadPersistedSession() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(ProseEditorSession.self, from: data) else { return }
        session = saved
        if let draft = session.currentDraft {
            sentences = draft.sentences
            briefInput = session.brief?.rawInput ?? ""
            styleProfileRef = session.brief?.styleProfileRef ?? ""
            phase = .editing
        }
    }

    func clearSession() {
        session = ProseEditorSession()
        sentences = []
        briefInput = ""
        styleProfileRef = ""
        editingId = nil
        editBuffer = ""
        phase = .brief
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Copy Formatters

    func copyFullReport() -> String {
        guard let brief = session.brief else { return fullProseText }

        var lines: [String] = []
        lines.append("=== PROSE EDITOR OUTPUT ===")
        lines.append("Brief: \(brief.rawInput.prefix(200))")
        if let style = brief.styleProfileRef {
            lines.append("Style: \(style)")
        }
        lines.append("Round: \(session.currentRound)")
        lines.append("Sentences: \(sentences.count)")
        lines.append("")
        lines.append("--- Text ---")
        lines.append(fullProseText)
        lines.append("")
        lines.append("--- Per-Sentence ---")
        for s in sentences {
            let statusTag = "[\(s.status.rawValue.uppercased())]"
            lines.append("S\(s.position + 1) \(statusTag) (\(s.wordCount)w): \(s.text)")
            if let ann = s.annotation, !ann.isEmpty {
                lines.append("  Note: \(ann)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
