//
//  GapAnalysisModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Data models for the Gap Analysis layer.
//  Runs 5 gap detection approaches on a selected narrative spine,
//  identifies structural weaknesses, and produces actionable questions.
//

import Foundation

// MARK: - Gap Type

enum GapType: String, Codable, CaseIterable, Identifiable {
    case structural       = "structural"
    case causal           = "causal"
    case contentDensity   = "content-density"
    case viewerState      = "viewer-state"
    case payoff           = "payoff"
    case creatorSignature = "creator-signature"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .structural:       return "Structural"
        case .causal:           return "Causal"
        case .contentDensity:   return "Content Density"
        case .viewerState:      return "Viewer State"
        case .payoff:           return "Payoff"
        case .creatorSignature: return "Creator Signature"
        }
    }
}

// MARK: - Gap Action

enum GapAction: String, Codable, CaseIterable, Identifiable {
    case reshape    = "RESHAPE"
    case surface    = "SURFACE"
    case contentGap = "CONTENT_GAP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reshape:    return "Reshape"
        case .surface:    return "Surface"
        case .contentGap: return "Content Gap"
        }
    }

    var shortDescription: String {
        switch self {
        case .reshape:    return "Existing content needs restructuring"
        case .surface:    return "Implicit content needs to be made explicit"
        case .contentGap: return "New content needed"
        }
    }
}

// MARK: - Gap Priority

enum GapPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case high   = "HIGH"
    case medium = "MEDIUM"
    case low    = "LOW"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }

    static func < (lhs: GapPriority, rhs: GapPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Refinement Status

enum RefinementStatus: String, Codable, CaseIterable {
    case resolved   // Rambling already covers this — spine builder missed it
    case refined    // Partially covered — question sharpened
    case confirmed  // Genuinely missing — question unchanged
}

// MARK: - Gap Finding

struct GapFinding: Codable, Identifiable {
    let id: UUID
    let type: GapType
    let action: GapAction
    let location: String
    let whatsMissing: String
    let whyItMatters: String
    let questionToRambler: String
    let priority: GapPriority

    // Refinement pass fields (nil until refinement runs)
    var refinementStatus: RefinementStatus?
    var ramblingExcerpt: String?     // Relevant quote from the raw rambling
    var refinedQuestion: String?     // Sharpened question (for .refined status)
    var refinementNote: String?      // Why the LLM made this classification

    /// The best question to use — refined version if available, otherwise original.
    var effectiveQuestion: String {
        if refinementStatus == .refined, let refined = refinedQuestion, !refined.isEmpty {
            return refined
        }
        return questionToRambler
    }

    init(
        type: GapType,
        action: GapAction,
        location: String,
        whatsMissing: String,
        whyItMatters: String,
        questionToRambler: String,
        priority: GapPriority
    ) {
        self.id = UUID()
        self.type = type
        self.action = action
        self.location = location
        self.whatsMissing = whatsMissing
        self.whyItMatters = whyItMatters
        self.questionToRambler = questionToRambler
        self.priority = priority
    }
}

// MARK: - Gap Path

enum GapPath: String, Codable, CaseIterable, Identifiable {
    case g1_singleLLM               = "G1"
    case g2_programmaticPlusLLM     = "G2"
    case g3_representativeComparison = "G3"
    case g4_viewerSimulation        = "G4"
    case g5_combined                = "G5"
    case g6_synthesis               = "G6"

    var id: String { rawValue }

    /// G1-G5 are primary paths (user-toggled). G6 is a synthesis path that auto-runs post-hoc.
    var isPrimary: Bool { self != .g6_synthesis }

    static var primaryCases: [GapPath] {
        allCases.filter(\.isPrimary)
    }

    var displayName: String {
        switch self {
        case .g1_singleLLM:               return "Single LLM"
        case .g2_programmaticPlusLLM:     return "Programmatic + LLM"
        case .g3_representativeComparison: return "Representative Comparison"
        case .g4_viewerSimulation:        return "Viewer Simulation"
        case .g5_combined:                return "Combined (G1+G4)"
        case .g6_synthesis:               return "Synthesis"
        }
    }

    var shortDescription: String {
        switch self {
        case .g1_singleLLM:
            return "Spine + Profile + Inventory → evaluate all 6 gap types in one call"
        case .g2_programmaticPlusLLM:
            return "Programmatic structural/payoff/signature/density flags → LLM refines + adds causal/viewer-state"
        case .g3_representativeComparison:
            return "Compare spine against representative spines beat-by-beat"
        case .g4_viewerSimulation:
            return "Spine only (no profile) — LLM reads as viewer, reports confusion/logic jumps"
        case .g5_combined:
            return "Viewer sim + profile comparison → merge/dedup"
        case .g6_synthesis:
            return "Merges findings from all completed paths into one deduplicated set"
        }
    }

    var callCount: Int {
        switch self {
        case .g1_singleLLM:               return 1
        case .g2_programmaticPlusLLM:     return 1
        case .g3_representativeComparison: return 1
        case .g4_viewerSimulation:        return 1
        case .g5_combined:                return 3
        case .g6_synthesis:               return 1
        }
    }

    var callLabels: [String] {
        switch self {
        case .g1_singleLLM:               return ["Gap Detection"]
        case .g2_programmaticPlusLLM:     return ["LLM Refinement"]
        case .g3_representativeComparison: return ["Comparative Analysis"]
        case .g4_viewerSimulation:        return ["Viewer Simulation"]
        case .g5_combined:                return ["Viewer Simulation", "Profile Gap Detection", "Merge & Dedup"]
        case .g6_synthesis:               return ["Synthesis"]
        }
    }
}

// MARK: - Gap Path Result

struct GapPathResult: Codable, Identifiable {
    let id: UUID
    let path: GapPath

    var findings: [GapFinding]
    var calls: [ArcPathCall]
    var intermediateOutputs: [String: String]
    var telemetry: GapPathTelemetry
    var status: ArcPathRunStatus
    var errorMessage: String?

    init(path: GapPath) {
        self.id = UUID()
        self.path = path
        self.findings = []
        self.calls = []
        self.intermediateOutputs = [:]
        self.telemetry = GapPathTelemetry()
        self.status = .pending
    }

    mutating func finalize() {
        telemetry.totalCalls = calls.count
        telemetry.totalPromptTokens = calls.compactMap { $0.telemetry?.promptTokens }.reduce(0, +)
        telemetry.totalCompletionTokens = calls.compactMap { $0.telemetry?.completionTokens }.reduce(0, +)
        telemetry.durationMs = calls.map(\.durationMs).reduce(0, +)
    }
}

struct GapPathTelemetry: Codable {
    var totalCalls: Int = 0
    var totalPromptTokens: Int = 0
    var totalCompletionTokens: Int = 0
    var durationMs: Int = 0
    var totalCost: Double = 0

    var totalTokens: Int { totalPromptTokens + totalCompletionTokens }
}

// MARK: - Gap Analysis Run

struct GapAnalysisRun: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let sourceArcRunId: UUID
    let sourceArcPath: ArcPath
    let enabledGapPaths: [GapPath]

    var pathResults: [GapPathResult]
    var refinementApplied: Bool

    // Aggregate telemetry
    var totalCalls: Int
    var totalTokens: Int
    var totalCost: Double
    var totalDurationMs: Int

    init(modelUsed: String, sourceArcRunId: UUID, sourceArcPath: ArcPath, enabledGapPaths: Set<GapPath>) {
        self.id = UUID()
        self.createdAt = Date()
        self.modelUsed = modelUsed
        self.sourceArcRunId = sourceArcRunId
        self.sourceArcPath = sourceArcPath
        self.enabledGapPaths = Array(enabledGapPaths).sorted { $0.rawValue < $1.rawValue }
        self.pathResults = []
        self.refinementApplied = false
        self.totalCalls = 0
        self.totalTokens = 0
        self.totalCost = 0
        self.totalDurationMs = 0
    }

    // Custom decoder for backwards compatibility — older saved runs may lack `refinementApplied`
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modelUsed = try container.decode(String.self, forKey: .modelUsed)
        sourceArcRunId = try container.decode(UUID.self, forKey: .sourceArcRunId)
        sourceArcPath = try container.decode(ArcPath.self, forKey: .sourceArcPath)
        enabledGapPaths = try container.decode([GapPath].self, forKey: .enabledGapPaths)
        pathResults = try container.decode([GapPathResult].self, forKey: .pathResults)
        refinementApplied = try container.decodeIfPresent(Bool.self, forKey: .refinementApplied) ?? false
        totalCalls = try container.decode(Int.self, forKey: .totalCalls)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        totalCost = try container.decode(Double.self, forKey: .totalCost)
        totalDurationMs = try container.decode(Int.self, forKey: .totalDurationMs)
    }

    mutating func finalize() {
        totalCalls = pathResults.flatMap(\.calls).count
        totalTokens = pathResults.flatMap(\.calls)
            .compactMap { $0.telemetry?.totalTokens }
            .reduce(0, +)
        totalCost = pathResults.map(\.telemetry.totalCost).reduce(0, +)
        totalDurationMs = pathResults.map(\.telemetry.durationMs).reduce(0, +)
    }

    // MARK: - Copy Methods

    func copyAllOutput() -> String {
        var parts: [String] = []
        parts.append("=== GAP ANALYSIS ===")
        parts.append("Model: \(modelUsed) | Source: \(sourceArcPath.rawValue) | Paths: \(enabledGapPaths.count) | \(formattedDate)")
        parts.append("")

        for result in pathResults where result.status == .completed {
            parts.append("=== \(result.path.rawValue): \(result.path.displayName) ===")
            parts.append("Findings: \(result.findings.count)")
            parts.append("")
            for (i, finding) in result.findings.enumerated() {
                parts.append("\(i + 1). [\(finding.priority.rawValue)] [\(finding.type.rawValue)] [\(finding.action.rawValue)]")
                parts.append("   Location: \(finding.location)")
                parts.append("   Missing: \(finding.whatsMissing)")
                parts.append("   Why: \(finding.whyItMatters)")
                parts.append("   Question: \(finding.questionToRambler)")
                parts.append("")
            }
        }
        return parts.joined(separator: "\n")
    }

    func copyAllWithPrompts() -> String {
        var parts: [String] = []
        parts.append("=== GAP ANALYSIS (FULL DEBUG) ===")
        parts.append("Model: \(modelUsed) | Source: \(sourceArcPath.rawValue) | \(formattedDate)")
        parts.append("")

        for result in pathResults {
            let tokens = result.telemetry.totalTokens
            let duration = String(format: "%.1f", Double(result.telemetry.durationMs) / 1000.0)

            parts.append("=== \(result.path.rawValue): \(result.path.displayName) ===")
            parts.append("Status: \(result.status.rawValue) | Calls: \(result.calls.count) | Tokens: \(tokens) | Duration: \(duration)s")
            parts.append("")

            if !result.intermediateOutputs.isEmpty {
                parts.append("--- Intermediate Outputs ---")
                for (key, value) in result.intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                    parts.append("[\(key)]")
                    parts.append(value)
                    parts.append("")
                }
            }

            for call in result.calls {
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

            parts.append("--- Findings ---")
            for (i, finding) in result.findings.enumerated() {
                parts.append("\(i + 1). [\(finding.priority.rawValue)] [\(finding.type.rawValue)] [\(finding.action.rawValue)]")
                parts.append("   Location: \(finding.location)")
                parts.append("   Missing: \(finding.whatsMissing)")
                parts.append("   Why: \(finding.whyItMatters)")
                parts.append("   Question: \(finding.questionToRambler)")
                parts.append("")
            }
            parts.append("\n")
        }
        return parts.joined(separator: "\n")
    }

    func copyPromptsOnly() -> String {
        var parts: [String] = []
        parts.append("=== GAP ANALYSIS PROMPTS ===")
        parts.append("Model: \(modelUsed) | \(formattedDate)")
        parts.append("")

        for result in pathResults {
            parts.append("=== \(result.path.rawValue): \(result.path.displayName) ===")
            for call in result.calls {
                parts.append("--- Call \(call.callIndex + 1): \(call.callLabel) ---")
                parts.append("[SYSTEM]")
                parts.append(call.systemPrompt)
                parts.append("")
                parts.append("[USER]")
                parts.append(call.userPrompt)
                parts.append("")
            }
        }
        return parts.joined(separator: "\n")
    }

    func copyGapQuestionsOnly() -> String {
        var parts: [String] = []
        parts.append("=== GAP QUESTIONS FOR RAMBLER ===")
        parts.append("Source: \(sourceArcPath.rawValue) | \(formattedDate)")
        parts.append("")

        // Prefer G6 synthesis findings when available (the merged best-of set)
        let g6Result = pathResults.first { $0.path == .g6_synthesis && $0.status == .completed }
        let allFindings: [GapFinding]
        if let g6 = g6Result, !g6.findings.isEmpty {
            parts.append("(From G6 Synthesis)")
            parts.append("")
            allFindings = g6.findings.sorted { $0.priority < $1.priority }
        } else {
            allFindings = pathResults
                .filter { $0.status == .completed }
                .flatMap(\.findings)
                .sorted { $0.priority < $1.priority }
        }

        // Skip resolved findings — the rambling already covers them
        let actionable = allFindings.filter { $0.refinementStatus != .resolved }

        for (i, finding) in actionable.enumerated() {
            parts.append("\(i + 1). [\(finding.priority.rawValue)] \(finding.effectiveQuestion)")
            parts.append("   (Gap: \(finding.whatsMissing))")
            parts.append("")
        }
        return parts.joined(separator: "\n")
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: createdAt)
    }
}

// MARK: - Gap Analysis Run Summary

struct GapAnalysisRunSummary: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let modelUsed: String
    let sourceArcPath: String
    let totalFindings: Int
    let highCount: Int
    let totalCost: Double
    let topFindings: [String]
    /// The session directory this run was found in (may differ from current session after clear/reset).
    var sourceSessionId: UUID

    init(from run: GapAnalysisRun, sessionId: UUID) {
        self.id = run.id
        self.createdAt = run.createdAt
        self.modelUsed = run.modelUsed
        self.sourceArcPath = run.sourceArcPath.rawValue
        let allFindings = run.pathResults.filter { $0.status == .completed }.flatMap(\.findings)
        self.totalFindings = allFindings.count
        self.highCount = allFindings.filter { $0.priority == .high }.count
        self.totalCost = run.totalCost
        self.topFindings = allFindings
            .sorted { $0.priority < $1.priority }
            .prefix(3)
            .map(\.whatsMissing)
        self.sourceSessionId = sessionId
    }
}

// MARK: - Programmatic Gap Flags (for G2)

struct ProgrammaticGapFlags: Codable {
    var structuralFlags: [ProgrammaticFlag]
    var payoffFlags: [ProgrammaticFlag]
    var signatureFlags: [ProgrammaticFlag]
    var densityFlags: [ProgrammaticFlag]

    var allFlags: [ProgrammaticFlag] {
        structuralFlags + payoffFlags + signatureFlags + densityFlags
    }

    var renderedSummary: String {
        var parts: [String] = []

        if !structuralFlags.isEmpty {
            parts.append("STRUCTURAL FLAGS:")
            for flag in structuralFlags {
                parts.append("- \(flag.description)")
            }
        }

        if !payoffFlags.isEmpty {
            parts.append("\nPAYOFF FLAGS:")
            for flag in payoffFlags {
                parts.append("- \(flag.description)")
            }
        }

        if !signatureFlags.isEmpty {
            parts.append("\nSIGNATURE FLAGS:")
            for flag in signatureFlags {
                parts.append("- \(flag.description)")
            }
        }

        if !densityFlags.isEmpty {
            parts.append("\nDENSITY FLAGS:")
            for flag in densityFlags {
                parts.append("- \(flag.description)")
            }
        }

        if parts.isEmpty {
            return "No programmatic flags detected."
        }
        return parts.joined(separator: "\n")
    }
}

struct ProgrammaticFlag: Codable, Identifiable {
    let id: UUID
    let category: String
    let beatIndex: Int?
    let description: String

    init(category: String, beatIndex: Int? = nil, description: String) {
        self.id = UUID()
        self.category = category
        self.beatIndex = beatIndex
        self.description = description
    }
}
