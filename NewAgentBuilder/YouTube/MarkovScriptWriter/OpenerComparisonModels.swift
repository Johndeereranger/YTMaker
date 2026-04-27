//
//  OpenerComparisonModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  Data models for the Opener Comparison Runner.
//  Supports running 8 distinct script-generation methods side-by-side,
//  persisting results, and comparing outputs across model choices.
//

import Foundation

// MARK: - Method Identifiers

enum OpenerMethod: String, Codable, CaseIterable, Identifiable {
    case m1_baselineDraft       = "M1"
    case m2_voiceRewrite        = "M2"
    case m3_cognitiveScaffolding = "M3"
    case m4_analysisRewrite     = "M4"
    case m5_spoonFedRules       = "M5"
    case m6_twoCallAnalysis     = "M6"
    case m7_sentenceFunction    = "M7"
    case m8_mechanical3Phase    = "M8"
    case m9_analyzeThenFixM3   = "M9"
    case m10_analyzeThenFixM1  = "M10"
    case m11_iterativeRefinement = "M11"

    // Structured methods (S-prefix) — use structured inputs from Donor Library + Fingerprints.
    // Each S-method runs once per available fingerprint type (up to 6 variants).
    case s1_singlePassStructured    = "S1"
    case s2_sentenceBySentence      = "S2"
    case s3_draftThenFix            = "S3"
    case s4_specFirstGeneration     = "S4"
    case s5_skeletonDriven          = "S5"
    case s6_adaptiveSkeleton        = "S6"
    case s7_phraseLibrary           = "S7"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m1_baselineDraft:       return "Baseline Draft"
        case .m2_voiceRewrite:        return "Voice-Matched Rewrite"
        case .m3_cognitiveScaffolding: return "Cognitive Scaffolding"
        case .m4_analysisRewrite:     return "Analysis-First Rewrite"
        case .m5_spoonFedRules:       return "Spoon-Fed Rules"
        case .m6_twoCallAnalysis:     return "2-Call Analysis→Rewrite"
        case .m7_sentenceFunction:    return "Sentence-Function Spec"
        case .m8_mechanical3Phase:    return "Mechanical 3-Phase"
        case .m9_analyzeThenFixM3:   return "Analyze-Then-Fix (M3 Start)"
        case .m10_analyzeThenFixM1:  return "Analyze-Then-Fix (M1 Start)"
        case .m11_iterativeRefinement: return "Iterative Refinement (3-Round)"
        case .s1_singlePassStructured:  return "Single-Pass Structured"
        case .s2_sentenceBySentence:    return "Sentence-by-Sentence"
        case .s3_draftThenFix:          return "Draft-Then-Fix (Mechanical)"
        case .s4_specFirstGeneration:   return "Spec-First Generation"
        case .s5_skeletonDriven:        return "Skeleton-Driven (Lookup Table)"
        case .s6_adaptiveSkeleton:      return "Adaptive Skeleton (Revisable)"
        case .s7_phraseLibrary:         return "Phrase-Library Generation"
        }
    }

    var shortDescription: String {
        switch self {
        case .m1_baselineDraft:       return "Single-pass draft with filtered gists"
        case .m2_voiceRewrite:        return "10-question voice analysis (skeleton + texture) → rewrite M1"
        case .m3_cognitiveScaffolding: return "Voice checklist + 3-bucket classification + self-audit"
        case .m4_analysisRewrite:     return "Mechanical analysis (counts, patterns) → rewrite M1"
        case .m5_spoonFedRules:       return "5 distinctive voice rules → constrained rewrite of M1"
        case .m6_twoCallAnalysis:     return "Separate voice analysis → constrained rewrite of M1"
        case .m7_sentenceFunction:    return "Extract sentence jobs → execute with gist content"
        case .m8_mechanical3Phase:    return "Mechanical spec → content map → draft"
        case .m9_analyzeThenFixM3:   return "M3 draft → sentence-level analysis → targeted fix"
        case .m10_analyzeThenFixM1:  return "M1 draft → sentence-level analysis → targeted fix"
        case .m11_iterativeRefinement: return "3 rounds of sentence-level diagnosis → surgical fix on M1"
        case .s1_singlePassStructured:  return "Structural spec + one fingerprint + donors in one call"
        case .s2_sentenceBySentence:    return "Per-sentence call with target signature + donors + fingerprint"
        case .s3_draftThenFix:          return "Draft → evaluate against spec → fix divergences"
        case .s4_specFirstGeneration:   return "Sentence-by-sentence plan → execute plan"
        case .s5_skeletonDriven:        return "Per-sentence call with token requirements from lookup table + donor voice reference"
        case .s6_adaptiveSkeleton:      return "S5 with mid-generation drift detection and skeleton re-walking"
        case .s7_phraseLibrary:         return "Per-sentence call with n-gram phrase library from corpus + token requirements"
        }
    }

    /// Number of LLM calls this method makes per variant (not counting dependency calls).
    /// For S-methods, this is per fingerprint variant — multiply by available fingerprint count for total.
    var ownCallCount: Int {
        switch self {
        case .m1_baselineDraft:       return 1
        case .m2_voiceRewrite:        return 1
        case .m3_cognitiveScaffolding: return 1
        case .m4_analysisRewrite:     return 1
        case .m5_spoonFedRules:       return 2
        case .m6_twoCallAnalysis:     return 2
        case .m7_sentenceFunction:    return 2
        case .m8_mechanical3Phase:    return 3
        case .m9_analyzeThenFixM3:   return 3
        case .m10_analyzeThenFixM1:  return 3
        case .m11_iterativeRefinement: return 6
        case .s1_singlePassStructured:  return 1
        case .s2_sentenceBySentence:    return 8   // estimate — actual depends on target sentence count
        case .s3_draftThenFix:          return 3
        case .s4_specFirstGeneration:   return 2
        case .s5_skeletonDriven:        return 8   // estimate — actual depends on target sentence count
        case .s6_adaptiveSkeleton:      return 10  // estimate — S5's 8 + potential replans
        case .s7_phraseLibrary:         return 8   // estimate — depends on sentence count
        }
    }

    /// Methods that must complete before this one can run.
    var dependencies: [OpenerMethod] {
        switch self {
        case .m1_baselineDraft:       return []
        case .m2_voiceRewrite:        return [.m1_baselineDraft]
        case .m3_cognitiveScaffolding: return []
        case .m4_analysisRewrite:     return [.m1_baselineDraft]
        case .m5_spoonFedRules:       return [.m1_baselineDraft]
        case .m6_twoCallAnalysis:     return [.m1_baselineDraft]
        case .m7_sentenceFunction:    return []
        case .m8_mechanical3Phase:    return []
        case .m9_analyzeThenFixM3:   return []
        case .m10_analyzeThenFixM1:  return []
        case .m11_iterativeRefinement: return [.m1_baselineDraft]
        case .s1_singlePassStructured:  return []
        case .s2_sentenceBySentence:    return []
        case .s3_draftThenFix:          return []
        case .s4_specFirstGeneration:   return []
        case .s5_skeletonDriven:        return []
        case .s6_adaptiveSkeleton:      return []
        case .s7_phraseLibrary:         return []
        }
    }

    /// Whether this is a structured method (S-prefix) that uses Donor Library inputs.
    var isStructured: Bool {
        switch self {
        case .s1_singlePassStructured, .s2_sentenceBySentence,
             .s3_draftThenFix, .s4_specFirstGeneration,
             .s5_skeletonDriven, .s6_adaptiveSkeleton,
             .s7_phraseLibrary:
            return true
        default:
            return false
        }
    }
}

// MARK: - Run Status

enum MethodRunStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Single LLM Call Record

struct OpenerMethodCall: Codable, Identifiable {
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

// MARK: - Per-Method Result

struct OpenerMethodResult: Codable, Identifiable {
    let id: UUID
    let method: OpenerMethod
    let strategyId: String

    /// For S-methods: which fingerprint type was used as the voice constraint.
    /// nil for M-methods.
    var fingerprintVariant: FingerprintPromptType?

    /// For methods that run multiple times without fingerprint variants (e.g. S5).
    var runVariantIndex: Int?

    /// The final script text produced by this method.
    var outputText: String

    /// Intermediate outputs keyed by label (e.g. "voiceAnalysis", "mechanicalSpec", "contentMap").
    var intermediateOutputs: [String: String]

    /// Individual LLM call records (1-3 per method).
    var calls: [OpenerMethodCall]

    /// Aggregated telemetry.
    var totalPromptTokens: Int
    var totalCompletionTokens: Int
    var totalCost: Double
    var durationMs: Int

    var status: MethodRunStatus

    /// Fidelity evaluation score (populated after running evaluator).
    var fidelityScore: FidelityScore?

    /// Display label including variant if present: "S1 (CMP)", "S5 #1", or just "M1".
    var displayLabel: String {
        if let variant = fingerprintVariant {
            return "\(method.rawValue) (\(variant.shortLabel))"
        }
        if let idx = runVariantIndex {
            return "\(method.rawValue) #\(idx)"
        }
        return method.rawValue
    }

    init(
        method: OpenerMethod,
        strategyId: String,
        fingerprintVariant: FingerprintPromptType? = nil,
        runVariantIndex: Int? = nil,
        outputText: String = "",
        intermediateOutputs: [String: String] = [:],
        calls: [OpenerMethodCall] = [],
        status: MethodRunStatus = .pending
    ) {
        self.id = UUID()
        self.method = method
        self.strategyId = strategyId
        self.fingerprintVariant = fingerprintVariant
        self.runVariantIndex = runVariantIndex
        self.outputText = outputText
        self.intermediateOutputs = intermediateOutputs
        self.calls = calls
        self.totalPromptTokens = calls.compactMap { $0.telemetry?.promptTokens }.reduce(0, +)
        self.totalCompletionTokens = calls.compactMap { $0.telemetry?.completionTokens }.reduce(0, +)
        self.totalCost = 0
        self.durationMs = calls.map(\.durationMs).reduce(0, +)
        self.status = status
    }

    mutating func finalize(cost: Double) {
        self.totalPromptTokens = calls.compactMap { $0.telemetry?.promptTokens }.reduce(0, +)
        self.totalCompletionTokens = calls.compactMap { $0.telemetry?.completionTokens }.reduce(0, +)
        self.durationMs = calls.map(\.durationMs).reduce(0, +)
        self.totalCost = cost
    }
}

// MARK: - Per-Strategy Container

struct OpenerStrategyComparisonRun: Codable, Identifiable {
    let id: UUID
    let strategyId: String
    let strategyName: String

    var methodResults: [OpenerMethodResult]

    init(strategyId: String, strategyName: String) {
        self.id = UUID()
        self.strategyId = strategyId
        self.strategyName = strategyName
        self.methodResults = []
    }

    func result(for method: OpenerMethod) -> OpenerMethodResult? {
        methodResults.first { $0.method == method }
    }
}

// MARK: - Full Comparison Run

struct OpenerComparisonRun: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let enabledMethods: [OpenerMethod]

    var strategyRuns: [OpenerStrategyComparisonRun]

    // Aggregate telemetry
    var totalCalls: Int
    var totalTokens: Int
    var totalCost: Double
    var totalDurationMs: Int

    init(modelUsed: String, enabledMethods: Set<OpenerMethod>) {
        self.id = UUID()
        self.createdAt = Date()
        self.modelUsed = modelUsed
        self.enabledMethods = Array(enabledMethods).sorted { $0.rawValue < $1.rawValue }
        self.strategyRuns = []
        self.totalCalls = 0
        self.totalTokens = 0
        self.totalCost = 0
        self.totalDurationMs = 0
    }

    mutating func finalize() {
        totalCalls = strategyRuns.flatMap(\.methodResults).flatMap(\.calls).count
        totalTokens = strategyRuns.flatMap(\.methodResults)
            .flatMap(\.calls)
            .compactMap { $0.telemetry?.totalTokens }
            .reduce(0, +)
        totalCost = strategyRuns.flatMap(\.methodResults).map(\.totalCost).reduce(0, +)
        totalDurationMs = strategyRuns.flatMap(\.methodResults).map(\.durationMs).reduce(0, +)
    }

    /// Format all outputs with guiding template openings at the top for context.
    func copyAllOutput(strategyId: String? = nil) -> String {
        let runs = strategyId.flatMap { sid in strategyRuns.filter { $0.strategyId == sid } } ?? strategyRuns
        let allCalls = runs.flatMap(\.methodResults).flatMap(\.calls)

        var parts: [String] = []

        // Prepend template openings so outputs can be evaluated in context
        let templates = Self.extractTemplateSection(from: allCalls)
        if !templates.isEmpty {
            parts.append("═══ GUIDING TEMPLATES ═══\n")
            parts.append(templates)
            parts.append("\n═══ GENERATED OUTPUTS ═══")
        }

        for stratRun in runs {
            if strategyRuns.count > 1 {
                parts.append("=== Strategy \(stratRun.strategyId): \(stratRun.strategyName) ===\n")
            }
            let sorted = stratRun.methodResults
                .sorted { Self.resultSortKey($0) < Self.resultSortKey($1) }
            var didInsertStructuredHeader = false
            for result in sorted {
                guard result.status == .completed else { continue }
                if result.method.isStructured && !didInsertStructuredHeader {
                    parts.append("\n═══ STRUCTURED METHODS ═══")
                    didInsertStructuredHeader = true
                }
                let cleanOutput = Self.stripAuditFromOutput(result.outputText)
                parts.append("\(result.displayLabel) (\(result.method.displayName)) - \(cleanOutput)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Format all outputs with methodology explanations, prompts, intermediate outputs, and telemetry.
    func copyAllWithMethodology(strategyId: String? = nil) -> String {
        let runs = strategyId.flatMap { sid in strategyRuns.filter { $0.strategyId == sid } } ?? strategyRuns

        var parts: [String] = []
        for stratRun in runs {
            if strategyRuns.count > 1 {
                parts.append("═══════════════════════════════════════════")
                parts.append("Strategy \(stratRun.strategyId): \(stratRun.strategyName)")
                parts.append("═══════════════════════════════════════════\n")
            }
            let sorted = stratRun.methodResults
                .sorted { Self.resultSortKey($0) < Self.resultSortKey($1) }
            var didInsertStructuredHeader = false
            for result in sorted {
                guard result.status == .completed else { continue }
                if result.method.isStructured && !didInsertStructuredHeader {
                    parts.append("\n═══ STRUCTURED METHODS ═══\n")
                    didInsertStructuredHeader = true
                }

                let tokens = result.totalPromptTokens + result.totalCompletionTokens
                let duration = String(format: "%.1f", Double(result.durationMs) / 1000.0)
                let cost = String(format: "$%.4f", result.totalCost)

                parts.append("═══ \(result.displayLabel) (\(result.method.displayName)) ═══")
                parts.append("Methodology: \(result.method.shortDescription)")
                parts.append("Calls: \(result.calls.count) | Tokens: \(tokens) | Cost: \(cost) | Duration: \(duration)s")
                parts.append("")

                for call in result.calls {
                    parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
                    if let t = call.telemetry {
                        parts.append("In: \(t.promptTokens) | Out: \(t.completionTokens) | Model: \(t.modelUsed)")
                    }
                    parts.append("")
                    parts.append("SYSTEM PROMPT:")
                    parts.append(call.systemPrompt)
                    parts.append("")
                    parts.append("USER PROMPT:")
                    parts.append(call.userPrompt)
                    parts.append("")
                }

                if !result.intermediateOutputs.isEmpty {
                    parts.append("--- Intermediate Outputs ---")
                    for (key, value) in result.intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                        parts.append("\(key):")
                        parts.append(value)
                        parts.append("")
                    }
                }

                parts.append("--- Final Output ---")
                parts.append(Self.stripAuditFromOutput(result.outputText))
                parts.append("\n")
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Sort key for results: M-methods first by rawValue, then S-methods by rawValue + variant.
    static func resultSortKey(_ result: OpenerMethodResult) -> String {
        let prefix = result.method.isStructured ? "Z" : "A"
        let variantSuffix = result.fingerprintVariant?.rawValue ?? ""
        return "\(prefix)_\(result.method.rawValue)_\(variantSuffix)"
    }

    /// Deduplicated version of copyAllWithMethodology.
    /// Shows shared content (templates, gists, constraint blocks, fingerprints, structural spec, donors) once at the top,
    /// then abbreviates each method's prompts with [REFERENCE] tags.
    func copyAllWithMethodologyShort(strategyId: String? = nil) -> String {
        let runs = strategyId.flatMap { sid in strategyRuns.filter { $0.strategyId == sid } } ?? strategyRuns
        let allResults = runs.flatMap(\.methodResults).filter { $0.status == .completed }
        let allCalls = allResults.flatMap(\.calls)

        // 1. Extract shared content from first available user prompt
        let sharedTemplates = Self.extractTemplateSection(from: allCalls)
        let allTemplateTexts = Self.extractAllTemplateSections(from: allCalls)
        let sharedGists = Self.extractGistSection(from: allCalls)

        // 2. Known constraint blocks to abbreviate in system prompts
        let constraintBlocks: [(name: String, text: String)] = [
            ("NARRATIVE_MODE", OpenerComparisonPromptEngine.NARRATIVE_MODE),
            ("VERB_CONSTRAINT", OpenerComparisonPromptEngine.VERB_CONSTRAINT),
            ("ACTOR_REQUIREMENT", OpenerComparisonPromptEngine.ACTOR_REQUIREMENT),
            ("EVIDENCE_MINIMUM", OpenerComparisonPromptEngine.EVIDENCE_MINIMUM),
            ("TEXTURE_RULES", OpenerComparisonPromptEngine.TEXTURE_RULES),
        ]

        // 3. Build output index of each method's final output for cross-referencing
        var methodOutputs: [(label: String, text: String)] = []
        for result in allResults {
            if !result.outputText.isEmpty {
                methodOutputs.append(("\(result.method.rawValue) OUTPUT", result.outputText))
            }
        }

        // 4. Extract structured-method shared content
        let fingerprints = Self.extractFingerprints(from: allResults)
        let structuralSpec = Self.extractStructuralSpec(from: allResults)
        let donorExamples = Self.extractDonorExamples(from: allResults)
        let positionDonors = Self.extractPositionDonors(from: allResults)

        var structuredBlocks: [(name: String, text: String)] = []
        for fp in fingerprints {
            structuredBlocks.append(("FINGERPRINT: \(fp.name)", fp.text))
        }
        if !structuralSpec.isEmpty {
            structuredBlocks.append(("STRUCTURAL SPEC", structuralSpec))
        }
        if !donorExamples.isEmpty {
            structuredBlocks.append(("DONOR EXAMPLES", donorExamples))
        }
        for pd in positionDonors {
            structuredBlocks.append(("DONORS Position \(pd.position)", pd.text))
        }

        // ═══ SHARED CONTEXT ═══
        var parts: [String] = []
        parts.append("═══ SHARED CONTEXT ═══\n")

        if !sharedTemplates.isEmpty {
            parts.append("TEMPLATE OPENINGS:\n\(sharedTemplates)\n")
        }
        if !sharedGists.isEmpty {
            parts.append("CONTENT MATERIAL:\n\(sharedGists)\n")
        }

        parts.append("CONSTRAINT BLOCKS:")
        for (name, text) in constraintBlocks {
            parts.append("[\(name)]:\n\(text)\n")
        }

        if !fingerprints.isEmpty {
            parts.append("═══ FINGERPRINTS ═══\n")
            for fp in fingerprints {
                parts.append("[\(fp.name)]:\n\(fp.text)\n")
            }
        }

        if !structuralSpec.isEmpty {
            parts.append("═══ STRUCTURAL SPEC ═══\n")
            parts.append(structuralSpec)
            parts.append("")
        }

        if !donorExamples.isEmpty {
            parts.append("═══ DONOR EXAMPLES ═══\n")
            parts.append(donorExamples)
            parts.append("")
        }
        if !positionDonors.isEmpty && donorExamples.isEmpty {
            parts.append("═══ DONOR EXAMPLES ═══\n")
            for pd in positionDonors {
                parts.append(pd.text)
                parts.append("")
            }
        }

        // ═══ Per-method sections ═══
        for stratRun in runs {
            if strategyRuns.count > 1 {
                parts.append("═══════════════════════════════════════════")
                parts.append("Strategy \(stratRun.strategyId): \(stratRun.strategyName)")
                parts.append("═══════════════════════════════════════════\n")
            }
            for result in stratRun.methodResults.sorted(by: { Self.resultSortKey($0) < Self.resultSortKey($1) }) {
                guard result.status == .completed else { continue }

                let tokens = result.totalPromptTokens + result.totalCompletionTokens
                let duration = String(format: "%.1f", Double(result.durationMs) / 1000.0)
                let cost = String(format: "$%.4f", result.totalCost)

                parts.append("═══ \(result.displayLabel) (\(result.method.displayName)) ═══")
                parts.append("\(result.calls.count) calls | \(tokens) tok | \(cost) | \(duration)s")
                parts.append("")

                // Build call-level output references for this method's own calls
                var ownCallOutputs: [(label: String, text: String)] = []

                for call in result.calls {
                    parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
                    if let t = call.telemetry {
                        parts.append("In: \(t.promptTokens) | Out: \(t.completionTokens) | Model: \(t.modelUsed)")
                    }

                    // Build cross-references: other methods' outputs + this method's earlier calls
                    var crossRefs = methodOutputs.filter { $0.label != "\(result.method.rawValue) OUTPUT" }
                    crossRefs.append(contentsOf: ownCallOutputs)

                    // Abbreviate system prompt
                    let sysShort = Self.abbreviatePrompt(
                        call.systemPrompt,
                        templateTexts: allTemplateTexts,
                        gistText: sharedGists,
                        constraintBlocks: constraintBlocks,
                        crossReferences: crossRefs,
                        structuredBlocks: structuredBlocks
                    )
                    parts.append("\nSYSTEM:\n\(sysShort)")

                    // Abbreviate user prompt
                    let userShort = Self.abbreviatePrompt(
                        call.userPrompt,
                        templateTexts: allTemplateTexts,
                        gistText: sharedGists,
                        constraintBlocks: constraintBlocks,
                        crossReferences: crossRefs,
                        structuredBlocks: structuredBlocks
                    )
                    parts.append("\nUSER:\n\(userShort)")
                    parts.append("")

                    // Track this call's output for later calls in same method
                    if !call.outputText.isEmpty {
                        ownCallOutputs.append(("CALL \(call.callIndex + 1) OUTPUT", call.outputText))
                    }
                }

                // Intermediate outputs — abbreviate if they match known outputs
                if !result.intermediateOutputs.isEmpty {
                    parts.append("Intermediates:")
                    for (key, value) in result.intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                        // Check if this intermediate matches another method's output
                        var abbreviated = false
                        for (label, outputText) in methodOutputs {
                            if value == outputText {
                                parts.append("  \(key): [\(label)]")
                                abbreviated = true
                                break
                            }
                        }
                        if !abbreviated {
                            // Check if it matches one of this method's own call outputs
                            for (label, outputText) in result.calls.map({ ("CALL \($0.callIndex + 1) OUTPUT", $0.outputText) }) {
                                if value == outputText {
                                    parts.append("  \(key): [\(label)]")
                                    abbreviated = true
                                    break
                                }
                            }
                        }
                        if !abbreviated {
                            parts.append("  \(key):\n\(value)")
                        }
                        parts.append("")
                    }
                }

                parts.append("Output:\n\(Self.stripAuditFromOutput(result.outputText))")
                parts.append("\n")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Prompts only — deduplicated like copyAllWithMethodologyShort but with no outputs, intermediates, or telemetry.
    /// Structured methods (S1-S4) show each fingerprint once; structural spec, donors, and raw data use reference tags.
    func copyPromptsOnly(strategyId: String? = nil) -> String {
        let runs = strategyId.flatMap { sid in strategyRuns.filter { $0.strategyId == sid } } ?? strategyRuns
        let allResults = runs.flatMap(\.methodResults).filter { $0.status == .completed }
        let allCalls = allResults.flatMap(\.calls)

        let sharedTemplates = Self.extractTemplateSection(from: allCalls)
        let allTemplateTexts = Self.extractAllTemplateSections(from: allCalls)
        let sharedGists = Self.extractGistSection(from: allCalls)

        let constraintBlocks: [(name: String, text: String)] = [
            ("NARRATIVE_MODE", OpenerComparisonPromptEngine.NARRATIVE_MODE),
            ("VERB_CONSTRAINT", OpenerComparisonPromptEngine.VERB_CONSTRAINT),
            ("ACTOR_REQUIREMENT", OpenerComparisonPromptEngine.ACTOR_REQUIREMENT),
            ("EVIDENCE_MINIMUM", OpenerComparisonPromptEngine.EVIDENCE_MINIMUM),
            ("TEXTURE_RULES", OpenerComparisonPromptEngine.TEXTURE_RULES),
        ]

        var methodOutputs: [(label: String, text: String)] = []
        for result in allResults {
            if !result.outputText.isEmpty {
                methodOutputs.append(("\(result.method.rawValue) OUTPUT", result.outputText))
            }
        }

        // Extract structured-method shared content
        let fingerprints = Self.extractFingerprints(from: allResults)
        let structuralSpec = Self.extractStructuralSpec(from: allResults)
        let donorExamples = Self.extractDonorExamples(from: allResults)
        let positionDonors = Self.extractPositionDonors(from: allResults)

        // Build replaceable blocks for abbreviation
        var structuredBlocks: [(name: String, text: String)] = []
        for fp in fingerprints {
            structuredBlocks.append(("FINGERPRINT: \(fp.name)", fp.text))
        }
        if !structuralSpec.isEmpty {
            structuredBlocks.append(("STRUCTURAL SPEC", structuralSpec))
        }
        if !donorExamples.isEmpty {
            structuredBlocks.append(("DONOR EXAMPLES", donorExamples))
        }
        for pd in positionDonors {
            structuredBlocks.append(("DONORS Position \(pd.position)", pd.text))
        }

        var parts: [String] = []
        parts.append("═══ SHARED CONTEXT ═══\n")

        if !sharedTemplates.isEmpty {
            parts.append("TEMPLATE OPENINGS:\n\(sharedTemplates)\n")
        }
        if !sharedGists.isEmpty {
            parts.append("CONTENT MATERIAL:\n\(sharedGists)\n")
        }

        parts.append("CONSTRAINT BLOCKS:")
        for (name, text) in constraintBlocks {
            parts.append("[\(name)]:\n\(text)\n")
        }

        // Show each fingerprint once
        if !fingerprints.isEmpty {
            parts.append("═══ FINGERPRINTS ═══\n")
            for fp in fingerprints {
                parts.append("[\(fp.name)]:\n\(fp.text)\n")
            }
        }

        // Show structural spec once
        if !structuralSpec.isEmpty {
            parts.append("═══ STRUCTURAL SPEC ═══\n")
            parts.append(structuralSpec)
            parts.append("")
        }

        // Show donor examples once
        if !donorExamples.isEmpty {
            parts.append("═══ DONOR EXAMPLES ═══\n")
            parts.append(donorExamples)
            parts.append("")
        }
        if !positionDonors.isEmpty && donorExamples.isEmpty {
            parts.append("═══ DONOR EXAMPLES ═══\n")
            for pd in positionDonors {
                parts.append(pd.text)
                parts.append("")
            }
        }

        for stratRun in runs {
            if strategyRuns.count > 1 {
                parts.append("═══════════════════════════════════════════")
                parts.append("Strategy \(stratRun.strategyId): \(stratRun.strategyName)")
                parts.append("═══════════════════════════════════════════\n")
            }
            for result in stratRun.methodResults.sorted(by: { Self.resultSortKey($0) < Self.resultSortKey($1) }) {
                guard result.status == .completed else { continue }

                parts.append("═══ \(result.displayLabel) (\(result.method.displayName)) ═══")
                parts.append("")

                var ownCallOutputs: [(label: String, text: String)] = []

                for call in result.calls {
                    parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")

                    var crossRefs = methodOutputs.filter { $0.label != "\(result.method.rawValue) OUTPUT" }
                    crossRefs.append(contentsOf: ownCallOutputs)

                    let sysShort = Self.abbreviatePrompt(
                        call.systemPrompt,
                        templateTexts: allTemplateTexts,
                        gistText: sharedGists,
                        constraintBlocks: constraintBlocks,
                        crossReferences: crossRefs,
                        structuredBlocks: structuredBlocks
                    )
                    parts.append("\nSYSTEM:\n\(sysShort)")

                    let userShort = Self.abbreviatePrompt(
                        call.userPrompt,
                        templateTexts: allTemplateTexts,
                        gistText: sharedGists,
                        constraintBlocks: constraintBlocks,
                        crossReferences: crossRefs,
                        structuredBlocks: structuredBlocks
                    )
                    parts.append("\nUSER:\n\(userShort)")
                    parts.append("")

                    if !call.outputText.isEmpty {
                        ownCallOutputs.append(("CALL \(call.callIndex + 1) OUTPUT", call.outputText))
                    }
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Short Copy Helpers

    /// Extract template openings text from the first call that contains them.
    /// Handles both M-method format ("### Template 1:") and S-method format ("### Template:").
    private static func extractTemplateSection(from calls: [OpenerMethodCall]) -> String {
        let startMarkers = ["### Template 1:", "### Template:"]
        for call in calls {
            let prompt = call.userPrompt
            var startRange: Range<String.Index>? = nil
            for marker in startMarkers {
                if let r = prompt.range(of: marker) {
                    startRange = r
                    break
                }
            }
            guard let startRange else { continue }

            let afterStart = prompt[startRange.lowerBound...]
            let endMarkers = ["---", "## WRITE IT ABOUT THIS:", "## DRAFT TO ANALYZE:", "## THE DRAFT TO REWRITE:",
                              "## DRAFT TO REWRITE:", "## CONTENT MATERIAL:", "## ORIGINAL CONTENT",
                              "## DONOR EXAMPLES", "## WRITE THE OPENING", "## CREATE THE PLAN"]
            var endIndex = afterStart.endIndex

            for marker in endMarkers {
                if let markerRange = afterStart.range(of: marker) {
                    if markerRange.lowerBound < endIndex {
                        endIndex = markerRange.lowerBound
                    }
                }
            }

            let extracted = String(afterStart[startRange.lowerBound..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty { return extracted }
        }
        return ""
    }

    /// Extract ALL distinct template section texts from calls (M-method and S-method formats may differ).
    /// Returns multiple texts so abbreviatePrompt can replace both formats.
    private static func extractAllTemplateSections(from calls: [OpenerMethodCall]) -> [String] {
        let startMarkers = ["### Template 1:", "### Template:"]
        var results: [String] = []
        var seen = Set<Int>() // track by text length to avoid near-duplicates

        for call in calls {
            let prompt = call.userPrompt
            var startRange: Range<String.Index>? = nil
            for marker in startMarkers {
                if let r = prompt.range(of: marker) {
                    startRange = r
                    break
                }
            }
            guard let startRange else { continue }

            let afterStart = prompt[startRange.lowerBound...]
            let endMarkers = ["---", "## WRITE IT ABOUT THIS:", "## DRAFT TO ANALYZE:", "## THE DRAFT TO REWRITE:",
                              "## DRAFT TO REWRITE:", "## CONTENT MATERIAL:", "## ORIGINAL CONTENT",
                              "## DONOR EXAMPLES", "## WRITE THE OPENING", "## CREATE THE PLAN",
                              "## STRUCTURAL EVALUATION", "## ORIGINAL DRAFT", "## TARGET SPECIFICATION",
                              "## REWRITE", "## EXECUTE THE PLAN", "## THE PLAN"]
            var endIndex = afterStart.endIndex

            for marker in endMarkers {
                if let markerRange = afterStart.range(of: marker) {
                    if markerRange.lowerBound < endIndex {
                        endIndex = markerRange.lowerBound
                    }
                }
            }

            let extracted = String(afterStart[startRange.lowerBound..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty && !seen.contains(extracted.count) {
                seen.insert(extracted.count)
                results.append(extracted)
            }
        }
        return results
    }

    /// Extract content gist text from the first call that contains them.
    private static func extractGistSection(from calls: [OpenerMethodCall]) -> String {
        for call in calls {
            let prompt = call.userPrompt
            guard let startRange = prompt.range(of: "### Position 1 Content:") else { continue }

            // Find end: look for section separators after gists
            let afterStart = prompt[startRange.lowerBound...]
            let endMarkers = ["---", "## TEMPLATE OPENINGS", "## SENTENCE JOBS:", "## MECHANICAL SPEC:", "## VOICE ANALYSIS", "## VOICE RULES:"]
            var endIndex = afterStart.endIndex

            for marker in endMarkers {
                if let markerRange = afterStart.range(of: marker) {
                    if markerRange.lowerBound < endIndex {
                        endIndex = markerRange.lowerBound
                    }
                }
            }

            let extracted = String(afterStart[startRange.lowerBound..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty { return extracted }
        }
        return ""
    }

    /// Strip M3 self-audit text that may be baked into saved outputText.
    /// Handles both new runs (parser already strips) and old loaded runs (audit embedded in storage).
    static func stripAuditFromOutput(_ text: String) -> String {
        let auditMarkers = ["### STEP 5", "## STEP 5", "**STEP 5", "STEP 5 —", "SELF-AUDIT"]
        for marker in auditMarkers {
            if let auditRange = text.range(of: marker) {
                return String(text[text.startIndex..<auditRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// Extract unique fingerprint texts from structured method calls, keyed by fingerprint type name.
    private static func extractFingerprints(from results: [OpenerMethodResult]) -> [(name: String, text: String)] {
        var seen = Set<String>()
        var fingerprints: [(name: String, text: String)] = []

        for result in results where result.method.isStructured {
            for call in result.calls {
                for prompt in [call.systemPrompt, call.userPrompt] {
                    guard let startRange = prompt.range(of: "## VOICE CONSTRAINTS (") else { continue }
                    // Extract the fingerprint type name from the header
                    let afterHeader = prompt[startRange.upperBound...]
                    guard let closeParen = afterHeader.range(of: ")") else { continue }
                    let typeName = String(afterHeader[afterHeader.startIndex..<closeParen.lowerBound])
                        .replacingOccurrences(of: " Fingerprint", with: "")
                    guard !seen.contains(typeName) else { continue }

                    // Find end of this section
                    let sectionStart = prompt[startRange.lowerBound...]
                    let endMarkers = ["## STRUCTURAL SPECIFICATION", "## DONOR EXAMPLES", "## TEMPLATE OPENINGS",
                                      "## CONTENT MATERIAL", "## TARGET FOR THIS SENTENCE", "## WRITE THE OPENING"]
                    var endIndex = sectionStart.endIndex
                    for marker in endMarkers {
                        if let r = sectionStart.range(of: marker), r.lowerBound > startRange.lowerBound, r.lowerBound < endIndex {
                            endIndex = r.lowerBound
                        }
                    }

                    let extracted = String(sectionStart[startRange.lowerBound..<endIndex])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty {
                        seen.insert(typeName)
                        fingerprints.append((typeName, extracted))
                    }
                }
            }
        }
        return fingerprints
    }

    /// Extract structural specification from structured method calls (identical across all S-methods).
    private static func extractStructuralSpec(from results: [OpenerMethodResult]) -> String {
        for result in results where result.method.isStructured {
            for call in result.calls {
                for prompt in [call.systemPrompt, call.userPrompt] {
                    guard let startRange = prompt.range(of: "## STRUCTURAL SPECIFICATION") else { continue }
                    let sectionStart = prompt[startRange.lowerBound...]
                    let endMarkers = ["## VOICE CONSTRAINTS", "## DONOR EXAMPLES", "## TEMPLATE OPENINGS",
                                      "## CONTENT MATERIAL", "## TARGET FOR THIS SENTENCE"]
                    var endIndex = sectionStart.endIndex
                    for marker in endMarkers {
                        if let r = sectionStart.range(of: marker), r.lowerBound > startRange.lowerBound, r.lowerBound < endIndex {
                            endIndex = r.lowerBound
                        }
                    }
                    let extracted = String(sectionStart[startRange.lowerBound..<endIndex])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty { return extracted }
                }
            }
        }
        return ""
    }

    /// Extract donor examples from structured method calls (identical across all S-methods).
    private static func extractDonorExamples(from results: [OpenerMethodResult]) -> String {
        for result in results where result.method.isStructured {
            for call in result.calls {
                let prompt = call.userPrompt
                guard let startRange = prompt.range(of: "## DONOR EXAMPLES") else { continue }
                let sectionStart = prompt[startRange.lowerBound...]
                let endMarkers = ["## CONTENT MATERIAL", "## WRITE THE OPENING", "## TEMPLATE OPENINGS",
                                  "## CREATE THE PLAN", "## TARGET FOR THIS SENTENCE"]
                var endIndex = sectionStart.endIndex
                for marker in endMarkers {
                    if let r = sectionStart.range(of: marker), r.lowerBound > startRange.lowerBound, r.lowerBound < endIndex {
                        endIndex = r.lowerBound
                    }
                }
                let extracted = String(sectionStart[startRange.lowerBound..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty { return extracted }
            }
        }
        return ""
    }

    /// Extract per-sentence donor examples from S2 calls (position-specific donors).
    private static func extractPositionDonors(from results: [OpenerMethodResult]) -> [(position: Int, text: String)] {
        var seen = Set<Int>()
        var donors: [(position: Int, text: String)] = []

        for result in results where result.method == .s2_sentenceBySentence {
            for call in result.calls {
                let prompt = call.userPrompt
                guard let startRange = prompt.range(of: "### Donor Examples for Position ") else { continue }
                // Extract position number
                let afterPrefix = prompt[startRange.upperBound...]
                guard let spaceRange = afterPrefix.range(of: " ") else { continue }
                let posStr = String(afterPrefix[afterPrefix.startIndex..<spaceRange.lowerBound])
                guard let pos = Int(posStr), !seen.contains(pos) else { continue }

                let sectionStart = prompt[startRange.lowerBound...]
                let endMarkers = ["## SENTENCES SO FAR", "## CONTENT MATERIAL", "## TARGET FOR THIS SENTENCE",
                                  "Write ONLY sentence"]
                var endIndex = sectionStart.endIndex
                for marker in endMarkers {
                    if let r = sectionStart.range(of: marker), r.lowerBound > startRange.lowerBound, r.lowerBound < endIndex {
                        endIndex = r.lowerBound
                    }
                }
                let extracted = String(sectionStart[startRange.lowerBound..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    seen.insert(pos)
                    donors.append((pos, extracted))
                }
            }
        }
        return donors.sorted { $0.position < $1.position }
    }

    /// Replace shared content in a prompt string with short reference tags.
    private static func abbreviatePrompt(
        _ prompt: String,
        templateTexts: [String],
        gistText: String,
        constraintBlocks: [(name: String, text: String)],
        crossReferences: [(label: String, text: String)],
        structuredBlocks: [(name: String, text: String)] = []
    ) -> String {
        var shortened = prompt

        // Replace structured blocks first (fingerprints, structural spec, donors — longest first)
        for (name, text) in structuredBlocks.sorted(by: { $0.text.count > $1.text.count }) {
            if text.count > 50 && shortened.contains(text) {
                shortened = shortened.replacingOccurrences(of: text, with: "[\(name)]")
            }
        }

        // Replace constraint blocks (longest first to avoid partial matches)
        for (name, text) in constraintBlocks.sorted(by: { $0.text.count > $1.text.count }) {
            if shortened.contains(text) {
                shortened = shortened.replacingOccurrences(of: text, with: "[\(name)]")
            }
        }

        // Replace template texts (multiple formats: M-method and S-method)
        for templateText in templateTexts.sorted(by: { $0.count > $1.count }) {
            if !templateText.isEmpty && shortened.contains(templateText) {
                shortened = shortened.replacingOccurrences(of: templateText, with: "[TEMPLATE OPENINGS]")
            }
        }

        // Replace gist text
        if !gistText.isEmpty && shortened.contains(gistText) {
            shortened = shortened.replacingOccurrences(of: gistText, with: "[CONTENT MATERIAL]")
        }

        // Replace cross-references (other methods' outputs, earlier calls' outputs)
        // Sort longest first to avoid partial matches
        for (label, text) in crossReferences.sorted(by: { $0.text.count > $1.text.count }) {
            if text.count > 50 && shortened.contains(text) {
                shortened = shortened.replacingOccurrences(of: text, with: "[\(label)]")
            }
        }

        return shortened
    }
}

// MARK: - Run Summary (lightweight, stored in session)

struct OpenerComparisonRunSummary: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let strategyIds: [String]
    let methodCount: Int
    let totalCost: Double
    let totalCalls: Int

    /// Display label of the method with the best fidelity score.
    let bestFidelityMethod: String?
    /// Best method's composite score (nil if never evaluated).
    let bestFidelityComposite: Double?
    /// Best method's per-dimension scores keyed by FidelityDimension.rawValue.
    let bestFidelityDimensions: [String: Double]?
    /// Best method's hard-fail count.
    let bestFidelityHardFails: Int?

    init(from run: OpenerComparisonRun) {
        self.id = run.id
        self.createdAt = run.createdAt
        self.modelUsed = run.modelUsed
        self.strategyIds = run.strategyRuns.map(\.strategyId)
        self.methodCount = run.enabledMethods.count
        self.totalCost = run.totalCost
        self.totalCalls = run.totalCalls

        let allResults = run.strategyRuns.flatMap(\.methodResults)
        if let bestResult = allResults
            .filter({ $0.fidelityScore != nil })
            .max(by: { ($0.fidelityScore?.compositeScore ?? 0) < ($1.fidelityScore?.compositeScore ?? 0) }),
           let fs = bestResult.fidelityScore {
            self.bestFidelityMethod = bestResult.displayLabel
            self.bestFidelityComposite = fs.compositeScore
            self.bestFidelityDimensions = fs.dimensionScores.mapValues(\.score)
            self.bestFidelityHardFails = fs.hardFailCount
        } else {
            self.bestFidelityMethod = nil
            self.bestFidelityComposite = nil
            self.bestFidelityDimensions = nil
            self.bestFidelityHardFails = nil
        }
    }
}
