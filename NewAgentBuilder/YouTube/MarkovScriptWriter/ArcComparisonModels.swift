//
//  ArcComparisonModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Data models for the Narrative Arc Comparison tab.
//  Supports running 5 distinct spine-generation paths side-by-side,
//  persisting results, and comparing outputs.
//

import Foundation

// MARK: - Path Identifiers

enum ArcPath: String, Codable, CaseIterable, Identifiable {
    // Pass 1 & 2: Original approach
    case p1_singlePass           = "P1"
    case p2_contentFirst         = "P2"
    case p3_fourStepPipeline     = "P3"
    case p4_dynamicSelection     = "P4"
    case p5_dynamicContentFirst  = "P5"

    // Pass 2 only: Enriched-rambling approach (anchored to Phase 1 spine)
    case v6_enrichedSinglePass       = "V6"
    case v7_enrichedContentFirst     = "V7"
    case v8_enrichedFourStep         = "V8"
    case v9_enrichedDynamic          = "V9"
    case v10_enrichedDynamicContent  = "V10"

    // Pass 2 only: Fresh-build approach (no spine anchoring)
    case v11_freshFourStep           = "V11"
    case v12_freshDynamicContent     = "V12"

    var id: String { rawValue }

    /// True for V-paths that are only available in Pass 2.
    var isPass2Only: Bool {
        switch self {
        case .v6_enrichedSinglePass, .v7_enrichedContentFirst,
             .v8_enrichedFourStep, .v9_enrichedDynamic, .v10_enrichedDynamicContent,
             .v11_freshFourStep, .v12_freshDynamicContent:
            return true
        default:
            return false
        }
    }

    /// True for V6–V10 enriched paths that anchor to the Phase 1 spine via expansion guide.
    var isEnrichedPath: Bool {
        isPass2Only && !isFreshBuildPath
    }

    /// True for V11–V12 fresh-build paths that treat all material as virgin input.
    var isFreshBuildPath: Bool {
        switch self {
        case .v11_freshFourStep, .v12_freshDynamicContent: return true
        default: return false
        }
    }

    /// P1–P5 only (for Pass 1 UI).
    static var pass1Cases: [ArcPath] { allCases.filter { !$0.isPass2Only } }

    /// All paths (for Pass 2 UI).
    static var pass2Cases: [ArcPath] { Array(allCases) }

    /// The P-path that this V-path mirrors (nil for P-paths).
    var mirroredPPath: ArcPath? {
        switch self {
        case .v6_enrichedSinglePass:      return .p1_singlePass
        case .v7_enrichedContentFirst:    return .p2_contentFirst
        case .v8_enrichedFourStep:        return .p3_fourStepPipeline
        case .v9_enrichedDynamic:         return .p4_dynamicSelection
        case .v10_enrichedDynamicContent: return .p5_dynamicContentFirst
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .p1_singlePass:              return "Single Pass"
        case .p2_contentFirst:            return "Content-First"
        case .p3_fourStepPipeline:        return "Four-Step Pipeline"
        case .p4_dynamicSelection:        return "Dynamic Example Selection"
        case .p5_dynamicContentFirst:     return "Dynamic + Content-First"
        case .v6_enrichedSinglePass:      return "Enriched Single Pass"
        case .v7_enrichedContentFirst:    return "Enriched Content-First"
        case .v8_enrichedFourStep:        return "Enriched Four-Step"
        case .v9_enrichedDynamic:         return "Enriched Dynamic Selection"
        case .v10_enrichedDynamicContent: return "Enriched Dynamic + Content"
        case .v11_freshFourStep:          return "Fresh Four-Step"
        case .v12_freshDynamicContent:    return "Fresh Dynamic + Content"
        }
    }

    var shortDescription: String {
        switch self {
        case .p1_singlePass:
            return "Rambling + Profile + 5 representative spines in one call"
        case .p2_contentFirst:
            return "Extract content atoms (no creator context) → build spine"
        case .p3_fourStepPipeline:
            return "Content → Causal Thread → Structural Plan → Full Spine"
        case .p4_dynamicSelection:
            return "Select 8-12 relevant corpus spines → build with those"
        case .p5_dynamicContentFirst:
            return "Content inventory → Select relevant spines → Build spine"
        case .v6_enrichedSinglePass:
            return "Enriched inventory → spine + positional metadata + validation"
        case .v7_enrichedContentFirst:
            return "Enriched inventory → spine + positional metadata + validation"
        case .v8_enrichedFourStep:
            return "Enriched inventory → causal → plan (+ positional) → spine + validation"
        case .v9_enrichedDynamic:
            return "Enriched inventory → dynamic selection → spine (+ positional) + validation"
        case .v10_enrichedDynamicContent:
            return "Enriched inventory → dynamic selection → spine (+ positional) + validation"
        case .v11_freshFourStep:
            return "Enriched inventory → causal → plan → spine + validation (no positional)"
        case .v12_freshDynamicContent:
            return "Enriched inventory → dynamic selection → spine + validation (no positional)"
        }
    }

    /// Number of LLM calls this path makes (excluding the shared preprocessing calls).
    var callCount: Int {
        switch self {
        case .p1_singlePass:              return 1
        case .p2_contentFirst:            return 2
        case .p3_fourStepPipeline:        return 4
        case .p4_dynamicSelection:        return 2
        case .p5_dynamicContentFirst:     return 3
        case .v6_enrichedSinglePass:      return 2  // spine + validation
        case .v7_enrichedContentFirst:    return 2  // spine + validation (shared inventory)
        case .v8_enrichedFourStep:        return 4  // causal + plan + spine + validation (shared inventory)
        case .v9_enrichedDynamic:         return 3  // selection + spine + validation
        case .v10_enrichedDynamicContent: return 3  // selection + spine + validation (shared inventory)
        case .v11_freshFourStep:          return 4  // causal + plan + spine + validation (shared inventory)
        case .v12_freshDynamicContent:    return 3  // selection + spine + validation (shared inventory)
        }
    }

    /// Call labels for each step in this path.
    var callLabels: [String] {
        switch self {
        case .p1_singlePass:
            return ["Spine Generation"]
        case .p2_contentFirst:
            return ["Content Inventory", "Spine Construction"]
        case .p3_fourStepPipeline:
            return ["Content Inventory", "Causal Thread", "Structural Plan", "Full Spine"]
        case .p4_dynamicSelection:
            return ["Example Selection", "Spine Construction"]
        case .p5_dynamicContentFirst:
            return ["Content Inventory", "Example Selection", "Spine Construction"]
        case .v6_enrichedSinglePass:
            return ["Spine Construction", "Gap Validation"]
        case .v7_enrichedContentFirst:
            return ["Spine Construction", "Gap Validation"]
        case .v8_enrichedFourStep:
            return ["Causal Thread", "Structural Plan", "Full Spine", "Gap Validation"]
        case .v9_enrichedDynamic:
            return ["Example Selection", "Spine Construction", "Gap Validation"]
        case .v10_enrichedDynamicContent:
            return ["Example Selection", "Spine Construction", "Gap Validation"]
        case .v11_freshFourStep:
            return ["Causal Thread", "Structural Plan", "Full Spine", "Gap Validation"]
        case .v12_freshDynamicContent:
            return ["Example Selection", "Spine Construction", "Gap Validation"]
        }
    }
}

// MARK: - Run Status

enum ArcPathRunStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Single LLM Call Record

struct ArcPathCall: Codable, Identifiable {
    let id: UUID
    let callIndex: Int
    let callLabel: String
    let systemPrompt: String
    let userPrompt: String
    let rawResponse: String
    let outputText: String
    let telemetry: SectionTelemetry?
    let durationMs: Int

    init(
        callIndex: Int,
        callLabel: String,
        systemPrompt: String,
        userPrompt: String,
        rawResponse: String,
        outputText: String,
        telemetry: SectionTelemetry?,
        durationMs: Int
    ) {
        self.id = UUID()
        self.callIndex = callIndex
        self.callLabel = callLabel
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.rawResponse = rawResponse
        self.outputText = outputText
        self.telemetry = telemetry
        self.durationMs = durationMs
    }
}

// MARK: - Spine Validation Result

struct SpineValidationResult: Codable {
    /// Product of all consecutive transition probabilities (log scale).
    let sequenceLogProbability: Double

    /// Transitions with probability below threshold.
    let lowProbabilityTransitions: [FlaggedTransition]

    /// Common corpus transitions that are absent from this spine.
    let missingCommonTransitions: [MissingTransition]

    /// Function labels not in the 19-label taxonomy.
    let unknownFunctions: [String]

    let beatCount: Int
    let phaseCount: Int

    /// True if no beat depends on a later beat (no forward references).
    let hasValidDependencyChain: Bool

    /// Content atoms from inventory that don't appear in any beat's contentTag (P2/P3/P5 only).
    let unmappedContentAtoms: [String]?

    struct FlaggedTransition: Codable {
        let fromFunction: String
        let toFunction: String
        let probability: Double
        let beatIndex: Int
    }

    struct MissingTransition: Codable {
        let fromFunction: String
        let toFunction: String
        let expectedProbability: Double
    }
}

// MARK: - Per-Path Result

struct ArcPathResult: Codable, Identifiable {
    let id: UUID
    let path: ArcPath

    /// The parsed spine (nil if parse failed).
    var outputSpine: NarrativeSpine?

    /// Raw JSON/text response from the final LLM call.
    var rawSpineText: String

    /// Intermediate outputs keyed by label (e.g. "contentInventory", "causalThread", "structuralPlan", "selectedExampleIds").
    var intermediateOutputs: [String: String]

    /// Individual LLM call records.
    var calls: [ArcPathCall]

    /// Aggregated telemetry.
    var totalPromptTokens: Int
    var totalCompletionTokens: Int
    var totalCost: Double
    var durationMs: Int

    var status: ArcPathRunStatus

    /// Validation result (populated after run).
    var validationResult: SpineValidationResult?

    /// Gap coverage validation result (V-paths only: V6–V12).
    var gapValidationResult: GapCoverageResult?

    /// Error message if the path failed.
    var errorMessage: String?

    var displayLabel: String { path.rawValue }

    /// Formats this path's prompts + output for clipboard copy.
    func copyPromptAndOutput() -> String {
        var parts: [String] = []
        let tokens = totalPromptTokens + totalCompletionTokens
        let duration = String(format: "%.1f", Double(durationMs) / 1000.0)
        let cost = String(format: "$%.4f", totalCost)

        parts.append("═══ \(path.rawValue): \(path.displayName) ═══")
        parts.append("Status: \(status.rawValue) | Calls: \(calls.count) | Tokens: \(tokens) | Cost: \(cost) | Duration: \(duration)s")
        parts.append("")

        // Intermediate outputs
        if !intermediateOutputs.isEmpty {
            parts.append("--- Intermediate Outputs ---")
            for (key, value) in intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                parts.append("[\(key)]")
                parts.append(value)
                parts.append("")
            }
        }

        // Per-call prompts and responses
        for call in calls {
            parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
            if let t = call.telemetry {
                parts.append("Tokens: in=\(t.promptTokens) out=\(t.completionTokens) | Model: \(t.modelUsed)")
            }
            parts.append("")
            parts.append("[SYSTEM PROMPT]")
            parts.append(call.systemPrompt)
            parts.append("")
            parts.append("[USER PROMPT]")
            parts.append(call.userPrompt)
            parts.append("")
            parts.append("[RESPONSE]")
            parts.append(call.rawResponse)
            parts.append("")
        }

        // Final spine output
        if let spine = outputSpine {
            parts.append("--- Parsed Spine ---")
            parts.append(spine.renderedText)
        } else if status == .completed || status == .failed {
            parts.append("--- Raw Spine Text (parse failed) ---")
            parts.append(rawSpineText)
        }

        // Validation
        if let v = validationResult {
            parts.append("")
            parts.append("--- Validation ---")
            parts.append("Sequence log probability: \(String(format: "%.3f", v.sequenceLogProbability))")
            parts.append("Low-prob transitions: \(v.lowProbabilityTransitions.count)")
            parts.append("Missing common transitions: \(v.missingCommonTransitions.count)")
            parts.append("Unknown functions: \(v.unknownFunctions.joined(separator: ", "))")
            parts.append("Valid dependency chain: \(v.hasValidDependencyChain)")
        }

        return parts.joined(separator: "\n")
    }

    init(path: ArcPath) {
        self.id = UUID()
        self.path = path
        self.rawSpineText = ""
        self.intermediateOutputs = [:]
        self.calls = []
        self.totalPromptTokens = 0
        self.totalCompletionTokens = 0
        self.totalCost = 0
        self.durationMs = 0
        self.status = .pending
    }

    mutating func finalize() {
        self.totalPromptTokens = calls.compactMap { $0.telemetry?.promptTokens }.reduce(0, +)
        self.totalCompletionTokens = calls.compactMap { $0.telemetry?.completionTokens }.reduce(0, +)
        self.durationMs = calls.map(\.durationMs).reduce(0, +)
    }
}

// MARK: - Full Comparison Run

struct ArcComparisonRun: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let enabledPaths: [ArcPath]

    var pathResults: [ArcPathResult]

    /// Shared preprocessing calls (base inventory + supplemental inventory).
    var preprocessingCalls: [ArcPathCall]

    // Aggregate telemetry
    var totalCalls: Int
    var totalTokens: Int
    var totalCost: Double
    var totalDurationMs: Int

    init(modelUsed: String, enabledPaths: Set<ArcPath>) {
        self.id = UUID()
        self.createdAt = Date()
        self.modelUsed = modelUsed
        self.enabledPaths = Array(enabledPaths).sorted { $0.rawValue < $1.rawValue }
        self.pathResults = []
        self.preprocessingCalls = []
        self.totalCalls = 0
        self.totalTokens = 0
        self.totalCost = 0
        self.totalDurationMs = 0
    }

    mutating func finalize() {
        var allCalls = pathResults.flatMap(\.calls)
        allCalls += preprocessingCalls
        totalCalls = allCalls.count
        totalTokens = allCalls
            .compactMap { $0.telemetry?.totalTokens }
            .reduce(0, +)
        totalCost = pathResults.map(\.totalCost).reduce(0, +)
        totalDurationMs = pathResults.map(\.durationMs).reduce(0, +)
    }

    // MARK: - Shared Reference Dictionary (for consolidated copy output)

    private struct PromptReference {
        let label: String
        let content: String
    }

    /// Scans all calls in the run and identifies prompt blocks that appear in 2+ calls.
    /// Returns them sorted longest-first (to avoid partial-match issues during replacement).
    private func buildSharedReferences() -> [PromptReference] {
        let allUserPrompts = pathResults.flatMap { $0.calls.map(\.userPrompt) }
        let allSystemPrompts = pathResults.flatMap { $0.calls.map(\.systemPrompt) }
        var refs: [PromptReference] = []

        // 1. Static blocks from prompt engine (exact match)
        let staticCandidates: [(String, String)] = [
            ("Function Taxonomy", ArcComparisonPromptEngine.functionTaxonomy),
            ("Beat Guidance", ArcComparisonPromptEngine.beatGuidance),
            ("Output Format (JSON Schema)", ArcComparisonPromptEngine.spineJsonFormat),
            ("Gap-Aware Rules", ArcComparisonPromptEngine.gapAwareRules),
        ]

        for (label, content) in staticCandidates {
            if allUserPrompts.filter({ $0.contains(content) }).count >= 2 {
                refs.append(PromptReference(label: label, content: content))
            }
        }

        // 2. Spine system prompt (shared across most calls)
        let spineSystem = ArcComparisonPromptEngine.spineSystemPrompt
        if allSystemPrompts.filter({ $0 == spineSystem }).count >= 2 {
            refs.append(PromptReference(label: "Spine System Prompt", content: spineSystem))
        }

        // 3. Dynamic blocks (extracted by header from first prompt containing them)
        let dynamicCandidates: [(header: String, label: String, terminators: [String])] = [
            ("### Creator Narrative Profile:",
             "Creator Profile",
             ["\n\n### Representative", "\n\n### What a beat", "\n\n### Function labels"]),
            ("### Representative Spines",
             "Representative Spines",
             ["\n\n### What a beat", "\n\n### Function labels", "\n\n### Rules"]),
            ("## Gap Analysis Context",
             "Gap Analysis Context",
             ["\n\n---\n", "\n\n### Rules", "\n\n### Structural Expansion"]),
        ]

        for candidate in dynamicCandidates {
            if let content = extractDynamicBlock(from: allUserPrompts,
                                                  header: candidate.header,
                                                  terminators: candidate.terminators),
               allUserPrompts.filter({ $0.contains(content) }).count >= 2 {
                refs.append(PromptReference(label: candidate.label, content: content))
            }
        }

        // Sort longest content first to avoid partial-match issues during replacement
        return refs.sorted { $0.content.count > $1.content.count }
    }

    /// Extracts a section from the first prompt containing `header`, ending at the earliest terminator.
    private func extractDynamicBlock(from prompts: [String], header: String, terminators: [String]) -> String? {
        for prompt in prompts {
            guard let startRange = prompt.range(of: header) else { continue }
            let afterHeader = prompt[startRange.upperBound...]

            var endIdx = prompt.endIndex
            for terminator in terminators {
                if let range = afterHeader.range(of: terminator) {
                    if range.lowerBound < endIdx {
                        endIdx = range.lowerBound
                    }
                }
            }

            let extracted = String(prompt[startRange.lowerBound..<endIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty { return extracted }
        }
        return nil
    }

    /// Replaces shared block content with reference markers in a prompt string.
    private func replaceSharedBlocks(in text: String, refs: [PromptReference]) -> String {
        var result = text
        for ref in refs {
            result = result.replacingOccurrences(of: ref.content, with: "[→ See: \(ref.label)]")
        }
        return result
    }

    /// Formats the shared reference dictionary section for copy output.
    private func formatReferenceDictionary(_ refs: [PromptReference]) -> String {
        guard !refs.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("═══ SHARED REFERENCE ═══")
        parts.append("(Blocks shared across multiple prompts. Referenced inline as [→ See: Label].)")
        parts.append("")

        let labels = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for (i, ref) in refs.enumerated() {
            let tag = i < labels.count ? String(labels[labels.index(labels.startIndex, offsetBy: i)]) : "\(i+1)"
            parts.append("--- [\(tag)] \(ref.label) ---")
            parts.append(ref.content)
            parts.append("")
        }

        parts.append("═══ END REFERENCE ═══")
        parts.append("")
        return parts.joined(separator: "\n")
    }

    // MARK: - Copy Methods

    func copyAllOutput() -> String {
        var parts: [String] = []
        parts.append("═══ NARRATIVE ARC COMPARISON ═══")
        parts.append("Model: \(modelUsed) | Paths: \(enabledPaths.count) | \(formattedDate)")
        parts.append("")

        for result in pathResults where result.status == .completed {
            parts.append("═══ \(result.path.rawValue): \(result.path.displayName) ═══")
            if let spine = result.outputSpine {
                parts.append(spine.renderedText)
            } else {
                parts.append("[Parse failed — raw response below]")
                parts.append(result.rawSpineText)
            }
            parts.append("")
        }
        return parts.joined(separator: "\n")
    }

    func copyAllWithPrompts() -> String {
        let refs = buildSharedReferences()
        var parts: [String] = []
        parts.append("═══ NARRATIVE ARC COMPARISON (FULL DEBUG) ═══")
        parts.append("Model: \(modelUsed) | Paths: \(enabledPaths.count) | \(formattedDate)")
        parts.append("")

        parts.append(formatReferenceDictionary(refs))

        for result in pathResults {
            let tokens = result.totalPromptTokens + result.totalCompletionTokens
            let duration = String(format: "%.1f", Double(result.durationMs) / 1000.0)
            let cost = String(format: "$%.4f", result.totalCost)

            parts.append("═══ \(result.path.rawValue): \(result.path.displayName) ═══")
            parts.append("Status: \(result.status.rawValue) | Calls: \(result.calls.count) | Tokens: \(tokens) | Cost: \(cost) | Duration: \(duration)s")
            parts.append("")

            // Intermediate outputs
            if !result.intermediateOutputs.isEmpty {
                parts.append("--- Intermediate Outputs ---")
                for (key, value) in result.intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                    parts.append("[\(key)]")
                    parts.append(value)
                    parts.append("")
                }
            }

            // Per-call prompts and responses
            for call in result.calls {
                parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
                if let t = call.telemetry {
                    parts.append("Tokens: in=\(t.promptTokens) out=\(t.completionTokens) | Model: \(t.modelUsed)")
                }
                parts.append("")
                parts.append("[SYSTEM PROMPT]")
                parts.append(replaceSharedBlocks(in: call.systemPrompt, refs: refs))
                parts.append("")
                parts.append("[USER PROMPT]")
                parts.append(replaceSharedBlocks(in: call.userPrompt, refs: refs))
                parts.append("")
                parts.append("[RESPONSE]")
                parts.append(call.rawResponse)
                parts.append("")
            }

            // Final spine output
            if let spine = result.outputSpine {
                parts.append("--- Parsed Spine ---")
                parts.append(spine.renderedText)
            } else if result.status == .completed || result.status == .failed {
                parts.append("--- Raw Spine Text (parse failed) ---")
                parts.append(result.rawSpineText)
            }

            // Validation
            if let v = result.validationResult {
                parts.append("")
                parts.append("--- Validation ---")
                parts.append("Sequence log probability: \(String(format: "%.3f", v.sequenceLogProbability))")
                parts.append("Low-prob transitions: \(v.lowProbabilityTransitions.count)")
                parts.append("Missing common transitions: \(v.missingCommonTransitions.count)")
                parts.append("Unknown functions: \(v.unknownFunctions.joined(separator: ", "))")
                parts.append("Valid dependency chain: \(v.hasValidDependencyChain)")
            }

            parts.append("\n")
        }
        return parts.joined(separator: "\n")
    }

    func copyPromptsOnly() -> String {
        let refs = buildSharedReferences()
        var parts: [String] = []
        parts.append("═══ NARRATIVE ARC PROMPTS ═══")
        parts.append("Model: \(modelUsed) | \(formattedDate)")
        parts.append("")

        parts.append(formatReferenceDictionary(refs))

        for result in pathResults {
            parts.append("═══ \(result.path.rawValue): \(result.path.displayName) ═══")
            for call in result.calls {
                parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
                parts.append("[SYSTEM]")
                parts.append(replaceSharedBlocks(in: call.systemPrompt, refs: refs))
                parts.append("")
                parts.append("[USER]")
                parts.append(replaceSharedBlocks(in: call.userPrompt, refs: refs))
                parts.append("")
            }
        }
        return parts.joined(separator: "\n")
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: createdAt)
    }
}

// MARK: - Run Summary (lightweight for history)

struct ArcComparisonRunSummary: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let pathCount: Int
    let totalCalls: Int
    let totalCost: Double
    let completedPaths: [String]
    /// The session directory this run was found in (may differ from current session after clear/reset).
    var sourceSessionId: UUID

    init(from run: ArcComparisonRun, sessionId: UUID) {
        self.id = run.id
        self.createdAt = run.createdAt
        self.modelUsed = run.modelUsed
        self.pathCount = run.enabledPaths.count
        self.totalCalls = run.totalCalls
        self.totalCost = run.totalCost
        self.completedPaths = run.pathResults
            .filter { $0.status == .completed }
            .map { $0.path.rawValue }
        self.sourceSessionId = sessionId
    }
}

// MARK: - Gap Coverage Validation (V-path post-hoc check)

struct GapCoverageResult: Codable {
    /// HIGH-priority gap IDs that the spine produced beats for.
    let coveredGapIds: [UUID]
    /// HIGH-priority gap IDs that the spine did NOT produce beats for.
    let uncoveredGapIds: [UUID]
    /// LLM's narrative summary of coverage.
    let coverageSummary: String
}
