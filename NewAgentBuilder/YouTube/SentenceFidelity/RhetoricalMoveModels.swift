//
//  RhetoricalMoveModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/28/26.
//

import Foundation

// MARK: - 25-Move Codebook (Closed-Set Classification)

enum RhetoricalMoveType: String, Codable, CaseIterable {
    // HOOK MOVES
    case personalStake = "personal-stake"           // "I spent 3 years on this"
    case shockingFact = "shocking-fact"             // "X kills more people than Y"
    case questionHook = "question-hook"             // "What if everything you knew was wrong?"
    case sceneSet = "scene-set"                     // "It's 1943, and a man walks into..."

    // SETUP MOVES
    case commonBelief = "common-belief"             // "Most people think..."
    case historicalContext = "historical-context"   // "To understand this, we go back to..."
    case defineFrame = "define-frame"               // "What do we even mean by X?"
    case stakesEstablishment = "stakes-establishment" // "Here's why this matters..."

    // TENSION MOVES
    case complication = "complication"              // "But here's the problem..."
    case counterargument = "counterargument"        // "Critics argue..."
    case contradiction = "contradiction"            // "But wait — that doesn't add up"
    case mysteryRaise = "mystery-raise"             // "So why did X happen?"

    // REVELATION MOVES
    case hiddenTruth = "hidden-truth"               // "What they don't tell you..."
    case reframe = "reframe"                        // "It's not about X, it's actually about Y"
    case rootCause = "root-cause"                   // "The real reason is..."
    case connectionReveal = "connection-reveal"     // "These two things are linked"

    // EVIDENCE MOVES
    case evidenceStack = "evidence-stack"           // "First... Second... Third..."
    case authorityCite = "authority-cite"           // "According to experts..."
    case dataPresent = "data-present"               // "The numbers show..."
    case caseStudy = "case-study"                   // "Take the example of..."
    case analogy = "analogy"                        // "It's like when..."

    // CLOSING MOVES
    case synthesis = "synthesis"                    // "So what does this mean?"
    case implication = "implication"                // "This explains why..."
    case futureProject = "future-project"           // "If this continues..."
    case viewerAddress = "viewer-address"           // "What do you think?"

    // Display name for UI
    var displayName: String {
        switch self {
        case .personalStake: return "Personal Stake"
        case .shockingFact: return "Shocking Fact"
        case .questionHook: return "Question Hook"
        case .sceneSet: return "Scene Set"
        case .commonBelief: return "Common Belief"
        case .historicalContext: return "Historical Context"
        case .defineFrame: return "Define Frame"
        case .stakesEstablishment: return "Stakes Establishment"
        case .complication: return "Complication"
        case .counterargument: return "Counterargument"
        case .contradiction: return "Contradiction"
        case .mysteryRaise: return "Mystery Raise"
        case .hiddenTruth: return "Hidden Truth"
        case .reframe: return "Reframe"
        case .rootCause: return "Root Cause"
        case .connectionReveal: return "Connection Reveal"
        case .evidenceStack: return "Evidence Stack"
        case .authorityCite: return "Authority Cite"
        case .dataPresent: return "Data Present"
        case .caseStudy: return "Case Study"
        case .analogy: return "Analogy"
        case .synthesis: return "Synthesis"
        case .implication: return "Implication"
        case .futureProject: return "Future Project"
        case .viewerAddress: return "Viewer Address"
        }
    }

    // Category for grouping in UI
    var category: RhetoricalCategory {
        switch self {
        case .personalStake, .shockingFact, .questionHook, .sceneSet:
            return .hook
        case .commonBelief, .historicalContext, .defineFrame, .stakesEstablishment:
            return .setup
        case .complication, .counterargument, .contradiction, .mysteryRaise:
            return .tension
        case .hiddenTruth, .reframe, .rootCause, .connectionReveal:
            return .revelation
        case .evidenceStack, .authorityCite, .dataPresent, .caseStudy, .analogy:
            return .evidence
        case .synthesis, .implication, .futureProject, .viewerAddress:
            return .closing
        }
    }

    // Example phrase for prompt clarity
    var examplePhrase: String {
        switch self {
        case .personalStake: return "I spent 3 years on this"
        case .shockingFact: return "X kills more people than Y"
        case .questionHook: return "What if everything you knew was wrong?"
        case .sceneSet: return "It's 1943, and a man walks into..."
        case .commonBelief: return "Most people think..."
        case .historicalContext: return "To understand this, we go back to..."
        case .defineFrame: return "What do we even mean by X?"
        case .stakesEstablishment: return "Here's why this matters..."
        case .complication: return "But here's the problem..."
        case .counterargument: return "Critics argue..."
        case .contradiction: return "But wait — that doesn't add up"
        case .mysteryRaise: return "So why did X happen?"
        case .hiddenTruth: return "What they don't tell you..."
        case .reframe: return "It's not about X, it's actually about Y"
        case .rootCause: return "The real reason is..."
        case .connectionReveal: return "These two things are linked"
        case .evidenceStack: return "First... Second... Third..."
        case .authorityCite: return "According to experts..."
        case .dataPresent: return "The numbers show..."
        case .caseStudy: return "Take the example of..."
        case .analogy: return "It's like when..."
        case .synthesis: return "So what does this mean?"
        case .implication: return "This explains why..."
        case .futureProject: return "If this continues..."
        case .viewerAddress: return "What do you think?"
        }
    }

    /// One-sentence description of the move's rhetorical function (for LLM prompts)
    var rhetoricalDefinition: String {
        switch self {
        case .personalStake: return "Establishes the creator's personal investment, experience, or authority on the topic"
        case .shockingFact: return "Opens with a surprising statistic or counterintuitive claim that disrupts expectations"
        case .questionHook: return "Poses a provocative question that creates immediate curiosity or challenges assumptions"
        case .sceneSet: return "Drops the audience into a specific moment, place, or scenario to ground the narrative"
        case .commonBelief: return "States a widely held assumption or conventional wisdom that will later be complicated"
        case .historicalContext: return "Provides background timeline or origin story that the audience needs to follow the argument"
        case .defineFrame: return "Establishes what the topic actually means or redefines the terms of discussion"
        case .stakesEstablishment: return "Makes explicit why this topic matters and what's at risk if we get it wrong"
        case .complication: return "Introduces a problem, obstacle, or wrinkle that complicates the narrative so far"
        case .counterargument: return "Presents the opposing view or strongest objection to the argument being built"
        case .contradiction: return "Points out an inconsistency or conflict between two things that should agree"
        case .mysteryRaise: return "Poses an unanswered question that creates narrative tension and forward momentum"
        case .hiddenTruth: return "Reveals something that was hidden, suppressed, or overlooked by conventional understanding"
        case .reframe: return "Shifts the audience's perspective by redefining what the topic is actually about"
        case .rootCause: return "Identifies the underlying mechanism or true origin that explains why something happens"
        case .connectionReveal: return "Shows a non-obvious link between two things the audience thought were unrelated"
        case .evidenceStack: return "Layers multiple pieces of supporting evidence in sequence to build cumulative weight"
        case .authorityCite: return "Invokes expert opinion, research, or credible sources to back a claim"
        case .dataPresent: return "Presents specific numbers, statistics, or measurements as concrete proof"
        case .caseStudy: return "Walks through a specific real-world example that illustrates the broader pattern"
        case .analogy: return "Maps the concept onto something familiar to make it intuitive and memorable"
        case .synthesis: return "Pulls together the preceding threads into a unified conclusion or takeaway"
        case .implication: return "Extends the argument to show what it means for the audience's life or the broader world"
        case .futureProject: return "Projects forward to what happens next, leaving the audience with forward momentum"
        case .viewerAddress: return "Directly engages the audience by asking them to reflect, consider, or take action"
        }
    }

    /// Parse from string with fallback mapping for common invalid values
    /// Maps non-standard labels to closest valid move
    static func parse(_ value: String) -> RhetoricalMoveType? {
        // Try exact match first
        if let direct = RhetoricalMoveType(rawValue: value) {
            return direct
        }

        // Normalize: lowercase, replace underscores with hyphens
        let normalized = value.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        if let fromNormalized = RhetoricalMoveType(rawValue: normalized) {
            return fromNormalized
        }

        // Map common invalid labels to valid moves
        let lower = value.lowercased()
        switch lower {
        // ⚠️ FRAME VALUES incorrectly used as move labels (most common AI mistake)
        case "application":
            return .implication  // "application" frame → implication move
        case "reveal":
            return .hiddenTruth  // "reveal" frame → hidden-truth move
        case "explanation":
            return .evidenceStack  // "explanation" frame → evidence-stack move
        case "confirmation":
            return .evidenceStack  // "confirmation" frame → evidence-stack move
        case "investigation":
            return .mysteryRaise  // "investigation" frame → mystery-raise move
        case "problem_definition", "problem-definition":
            return .complication  // "problem_definition" frame → complication move
        case "expectation_setup", "expectation-setup":
            return .stakesEstablishment  // "expectation_setup" frame → stakes-establishment move
        case "limitation":
            return .counterargument  // "limitation" frame → counterargument move
        case "scene_set":
            return .sceneSet  // "scene_set" frame → scene-set move (same concept)

        // ⚠️ CATEGORY NAMES incorrectly used as move labels
        case "hook":
            return .questionHook
        case "setup":
            return .stakesEstablishment
        case "tension":
            return .complication
        case "revelation":
            return .hiddenTruth
        case "evidence":
            return .evidenceStack
        case "closing":
            return .synthesis

        // Other common AI mistakes
        case "explain", "explaining":
            return .evidenceStack
        case "description", "describe", "describing":
            return .evidenceStack
        case "introduction", "intro", "introducing":
            return .sceneSet
        case "conclusion", "concluding", "wrap-up", "wrapup":
            return .synthesis
        case "transition", "transitioning", "bridge":
            return .synthesis
        case "context", "background", "backstory":
            return .historicalContext
        case "example", "examples", "illustration":
            return .caseStudy
        case "argument", "arguing", "point":
            return .evidenceStack
        case "claim", "claiming", "assertion":
            return .evidenceStack
        case "summary", "summarizing", "recap":
            return .synthesis
        default:
            break
        }

        // Try keyword matching as fallback
        if lower.contains("explain") { return .evidenceStack }
        if lower.contains("intro") { return .sceneSet }
        if lower.contains("conclu") { return .synthesis }
        if lower.contains("context") { return .historicalContext }
        if lower.contains("example") { return .caseStudy }

        return nil
    }
}

enum RhetoricalCategory: String, Codable, CaseIterable {
    case hook = "Hook"
    case setup = "Setup"
    case tension = "Tension"
    case revelation = "Revelation"
    case evidence = "Evidence"
    case closing = "Closing"

    var color: String {
        switch self {
        case .hook: return "blue"
        case .setup: return "green"
        case .tension: return "orange"
        case .revelation: return "purple"
        case .evidence: return "gray"
        case .closing: return "red"
        }
    }

    /// Structural transition note for cross-category moves.
    /// Returns nil for same-category transitions (continuation, no reset needed).
    static func transitionNote(from: RhetoricalCategory, to: RhetoricalCategory) -> String? {
        guard from != to else { return nil }

        switch (from, to) {
        // Tension →
        case (.tension, .hook):
            return "After building tension, the next Hook move should HARD-CUT to a new scene or moment — reset the narrative, don't continue the previous topic."
        case (.tension, .setup):
            return "After tension, Setup should re-contextualize — provide new background that the complication makes necessary."
        case (.tension, .revelation):
            return "After tension, a Revelation should resolve or reframe the tension — deliver the insight the audience is now primed for."
        case (.tension, .evidence):
            return "After raising tension, Evidence should provide concrete proof or data that addresses the tension — pivot from question to answer."
        case (.tension, .closing):
            return "After tension, Closing should acknowledge the unresolved tension and frame it as the takeaway itself."

        // Evidence →
        case (.evidence, .tension):
            return "After laying evidence, Tension should challenge or complicate what was just proven — don't repeat the evidence."
        case (.evidence, .revelation):
            return "After stacking evidence, Revelation should synthesize into an insight the evidence alone didn't make obvious."
        case (.evidence, .hook):
            return "After evidence, a new Hook should start a fresh narrative thread — use the evidence as a springboard to a new scene or question."
        case (.evidence, .setup):
            return "After specific evidence, Setup should zoom out and provide broader context that connects the evidence to a larger framework."
        case (.evidence, .closing):
            return "After evidence, Closing should consolidate what the evidence proves into a bottom-line conclusion or action item."

        // Hook →
        case (.hook, .setup):
            return "After the hook, Setup should contextualize and frame what was introduced — provide background, not more hooks."
        case (.hook, .tension):
            return "After hooking the audience, Tension should immediately complicate the hook — show why it matters or why it's not what it seems."
        case (.hook, .evidence):
            return "After a hook, Evidence should immediately ground it in concrete proof — validate the hook's promise."
        case (.hook, .revelation):
            return "After a hook, Revelation delivers the immediate payoff — the surprising truth the hook set up."
        case (.hook, .closing):
            return "After a hook, Closing should deliver the immediate takeaway — this is a very compressed arc."

        // Setup →
        case (.setup, .tension):
            return "After setup/context, Tension should introduce the complication or question that the context makes meaningful."
        case (.setup, .hook):
            return "After context, a Hook should re-engage — drop into a scene or pose a question that the context now makes vivid."
        case (.setup, .evidence):
            return "After establishing a framework, Evidence should populate it with concrete data or examples."
        case (.setup, .revelation):
            return "After context, Revelation should deliver an insight that the setup makes surprising or meaningful."
        case (.setup, .closing):
            return "After setup, Closing should deliver the bottom-line conclusion the context was building toward."

        // Revelation →
        case (.revelation, .evidence):
            return "After a reveal, Evidence should substantiate the new understanding with concrete proof."
        case (.revelation, .hook):
            return "After a reveal, a new Hook should start a fresh narrative thread — the reveal closes the old thread."
        case (.revelation, .tension):
            return "After a reveal, Tension should complicate or challenge the new understanding — show it's not the whole story."
        case (.revelation, .setup):
            return "After a reveal, Setup should re-contextualize with the new understanding — reframe the background in light of what was just revealed."
        case (.revelation, .closing):
            return "After a reveal, Closing should crystallize what the reveal means for the audience — deliver the 'so what.'"

        // Closing →
        case (.closing, .hook):
            return "After closing one arc, a Hook should open an entirely new thread — this is a multi-arc restart."
        case (.closing, .setup):
            return "After closing, Setup should introduce context for the next section — a fresh framing separate from the closed arc."
        case (.closing, .tension):
            return "After closing, Tension should reopen by introducing a new complication — the previous conclusion isn't the whole story."
        case (.closing, .evidence):
            return "After closing, additional Evidence should bolster the conclusion just delivered — reinforcement, not continuation."
        case (.closing, .revelation):
            return "After closing, a Revelation should deliver a twist or additional insight that reframes the conclusion."

        // Same-category (already handled by guard, but needed for exhaustiveness)
        default:
            return nil
        }
    }
}

// MARK: - Gist Frame (10 Rambling Frames for structural classification)

enum GistFrame: String, Codable, CaseIterable {
    case personalNarrative = "personal_narrative"
    case factualClaim = "factual_claim"
    case wondering = "wondering"
    case problemStatement = "problem_statement"
    case explanation = "explanation"
    case comparison = "comparison"
    case stakesDeclaration = "stakes_declaration"
    case patternNotice = "pattern_notice"
    case correction = "correction"
    case takeaway = "takeaway"

    var displayName: String {
        switch self {
        case .personalNarrative: return "Personal Narrative"
        case .factualClaim: return "Factual Claim"
        case .wondering: return "Wondering"
        case .problemStatement: return "Problem Statement"
        case .explanation: return "Explanation"
        case .comparison: return "Comparison"
        case .stakesDeclaration: return "Stakes Declaration"
        case .patternNotice: return "Pattern Notice"
        case .correction: return "Correction"
        case .takeaway: return "Takeaway"
        }
    }

    var description: String {
        switch self {
        case .personalNarrative: return "Speaker recounts something that happened to them or describes a physical scene they were in or witnessed"
        case .factualClaim: return "Speaker states something they believe to be true — a fact, stat, finding, data point, or sourced reference"
        case .wondering: return "Speaker asks a question out loud — genuine or rhetorical — about something unresolved or worth considering"
        case .problemStatement: return "Speaker identifies that something is broken, wrong, contradicted, or not working"
        case .explanation: return "Speaker describes how something works — a mechanism, process, or cause-effect chain"
        case .comparison: return "Speaker maps the subject onto something else — an analogy, parallel, or similar case from a different domain"
        case .stakesDeclaration: return "Speaker declares why something matters, what's at risk, or speaks directly to the listener's situation"
        case .patternNotice: return "Speaker observes that two or more things share a structure, cause, or behavior — a connection being made in real time"
        case .correction: return "Speaker explicitly replaces a prior belief with a better one, including hedges and acknowledged limits"
        case .takeaway: return "Speaker collapses what they've been saying into a single bottom-line conclusion or forward-looking statement"
        }
    }

    // MARK: - Migration map for old frame values

    /// Maps old 9-frame raw values and other legacy strings to new frames
    private static let migrationMap: [String: GistFrame] = [
        // Old 9-frame values
        "scene_set": .personalNarrative,
        "investigation": .wondering,
        "problem_definition": .problemStatement,
        "expectation_setup": .stakesDeclaration,
        "reveal": .patternNotice,
        "confirmation": .factualClaim,
        "limitation": .correction,
        "application": .takeaway,
        // "explanation" matches new .explanation directly (rawValue unchanged)

        // Additional legacy values
        "backstory": .personalNarrative,
        "data_point": .factualClaim,
        "source_reference": .factualClaim,
    ]

    // MARK: - Codable (backward-compatible decoder)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        // Try new values first
        if let direct = GistFrame(rawValue: raw) {
            self = direct
            return
        }

        // Migration map for old frame values
        if let migrated = GistFrame.migrationMap[raw] {
            self = migrated
            return
        }

        // Try parse() as final fallback
        if let parsed = GistFrame.parse(raw) {
            self = parsed
            return
        }

        // Default to factualClaim rather than crashing
        self = .factualClaim
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Parse frame from various string formats (snake_case, kebab-case, camelCase, etc.)
    /// Also maps rhetorical move labels to appropriate frames when AI confuses them
    static func parse(_ value: String) -> GistFrame? {
        // Try exact match first
        if let direct = GistFrame(rawValue: value) {
            return direct
        }

        // Normalize: lowercase, replace hyphens/spaces with underscores
        let normalized = value.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if let fromNormalized = GistFrame(rawValue: normalized) {
            return fromNormalized
        }

        // Handle camelCase by converting to snake_case
        let snakeCase = value.unicodeScalars.reduce("") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + "_" + String(scalar).lowercased()
            }
            return result + String(scalar)
        }.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if let fromSnake = GistFrame(rawValue: snakeCase) {
            return fromSnake
        }

        // Check migration map for old frame values
        let lower = value.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        if let migrated = migrationMap[lower] {
            return migrated
        }

        // Map rhetorical move labels to appropriate frames (AI sometimes confuses these)
        switch lower {
        // HOOK moves → personalNarrative
        case "personal_stake", "shocking_fact", "question_hook", "scene_set":
            return .personalNarrative
        // SETUP moves → stakesDeclaration
        case "common_belief", "historical_context", "define_frame", "stakes_establishment":
            return .stakesDeclaration
        // TENSION moves → problemStatement
        case "complication", "counterargument", "contradiction", "mystery_raise":
            return .problemStatement
        // REVELATION moves → patternNotice
        case "hidden_truth", "reframe", "root_cause", "connection_reveal":
            return .patternNotice
        // EVIDENCE moves → factualClaim
        case "evidence_stack", "authority_cite", "data_present", "case_study", "analogy":
            return .factualClaim
        // CLOSING moves → takeaway
        case "synthesis", "implication", "future_project", "viewer_address":
            return .takeaway
        default:
            break
        }

        // Try keyword matching as final fallback
        if lower.contains("narrat") || lower.contains("story") || lower.contains("scene") { return .personalNarrative }
        if lower.contains("fact") || lower.contains("claim") || lower.contains("data") { return .factualClaim }
        if lower.contains("wonder") || lower.contains("question") { return .wondering }
        if lower.contains("problem") { return .problemStatement }
        if lower.contains("explain") { return .explanation }
        if lower.contains("compar") || lower.contains("analog") { return .comparison }
        if lower.contains("stake") || lower.contains("matter") { return .stakesDeclaration }
        if lower.contains("pattern") || lower.contains("connect") { return .patternNotice }
        if lower.contains("correct") || lower.contains("replac") { return .correction }
        if lower.contains("takeaway") || lower.contains("bottom") || lower.contains("conclu") { return .takeaway }
        if lower.contains("complic") { return .problemStatement }
        if lower.contains("future") { return .takeaway }

        return nil
    }
}


// MARK: - Gist Protocol (for generic handling)

protocol GistProtocol {
    var subject: [String] { get }
    var premise: String { get }
    var frame: GistFrame { get }
    var embeddingText: String { get }
}

// MARK: - Chunk Gist A (Deterministic - strict, minimal, routing-safe)

struct ChunkGistA: Codable, Hashable, GistProtocol {
    let subject: [String]       // Concrete nouns only, no verbs/adjectives/tone
    let premise: String         // One neutral declarative sentence - observable action only
    let frame: GistFrame        // Structural frame classification

    /// Combined text for embedding
    var embeddingText: String {
        let subjectText = subject.joined(separator: ", ")
        return "\(subjectText). \(premise)"
    }
}

// MARK: - Chunk Gist B (Flexible - natural language, still non-interpretive)

struct ChunkGistB: Codable, Hashable, GistProtocol {
    let subject: [String]       // Noun phrases, may include light modifiers from text
    let premise: String         // One sentence describing what chunk accomplishes - plain language
    let frame: GistFrame        // Structural frame classification

    /// Combined text for embedding
    var embeddingText: String {
        let subjectText = subject.joined(separator: ", ")
        return "\(subjectText). \(premise)"
    }
}

// MARK: - Chunk Telemetry (Countable signals only)

enum DominantStance: String, Codable, CaseIterable {
    case asserting = "ASSERTING"
    case questioning = "QUESTIONING"
    case mixed = "MIXED"

    /// Parse from various string formats - returns .asserting as default fallback
    static func parse(_ value: String) -> DominantStance {
        // Try exact match first
        if let direct = DominantStance(rawValue: value) {
            return direct
        }

        // Try uppercase
        if let upper = DominantStance(rawValue: value.uppercased()) {
            return upper
        }

        // Keyword match and map common AI-invented values
        let lower = value.lowercased()

        // Questioning variants
        if lower.contains("question") { return .questioning }
        if lower.contains("ask") { return .questioning }
        if lower.contains("inquir") { return .questioning }

        // Mixed variants
        if lower.contains("mix") { return .mixed }
        if lower.contains("neutral") { return .mixed }
        if lower.contains("balanced") { return .mixed }
        if lower.contains("both") { return .mixed }

        // Everything else maps to asserting (most common)
        // Includes: DEMONSTRATING, EXPLAINING, NARRATING, STATING, DOCUMENTING, etc.
        if lower.contains("assert") { return .asserting }
        if lower.contains("demonstrat") { return .asserting }
        if lower.contains("explain") { return .asserting }
        if lower.contains("describ") { return .asserting }
        if lower.contains("narrat") { return .asserting }
        if lower.contains("stat") { return .asserting }
        if lower.contains("document") { return .asserting }
        if lower.contains("present") { return .asserting }
        if lower.contains("declar") { return .asserting }
        if lower.contains("synthe") { return .asserting }

        // Default fallback - asserting is most common
        print("⚠️ [DominantStance] Unknown value '\(value)', defaulting to ASSERTING")
        return .asserting
    }
}

struct ChunkTelemetry: Codable, Hashable {
    let dominantStance: DominantStance

    // Perspective counts
    let firstPersonCount: Int
    let secondPersonCount: Int
    let thirdPersonCount: Int

    // Sentence flag counts
    let numberCount: Int
    let temporalCount: Int
    let contrastCount: Int
    let questionCount: Int
    let quoteCount: Int
    let spatialCount: Int
    let technicalCount: Int

    /// Total sentence count (approximated from perspective totals)
    var approximateSentenceCount: Int {
        max(firstPersonCount + secondPersonCount + thirdPersonCount, 1)
    }

    /// Dominant perspective
    var dominantPerspective: String {
        let counts = [
            ("first", firstPersonCount),
            ("second", secondPersonCount),
            ("third", thirdPersonCount)
        ]
        return counts.max(by: { $0.1 < $1.1 })?.0 ?? "third"
    }
}

// MARK: - Rhetorical Move (Single Classification)

struct RhetoricalMove: Codable, Identifiable, Hashable {
    let id: UUID
    let chunkIndex: Int
    let moveType: RhetoricalMoveType
    let confidence: Double                      // 0-1 how confident the AI is
    let alternateType: RhetoricalMoveType?      // Second-best guess
    let alternateConfidence: Double?            // Confidence for alternate
    let briefDescription: String                // 1-sentence summary of chunk content

    // New fields for enhanced gist analysis (optional for backwards compatibility)
    let gistA: ChunkGistA?                      // Deterministic gist for hard matching
    let gistB: ChunkGistB?                      // Flexible gist for semantic matching
    let expandedDescription: String?            // 3-5 sentence structural analysis
    let telemetry: ChunkTelemetry?              // Countable signals

    // Sentence range mapping (optional — populated by LLM pipeline, nil for legacy/deterministic)
    let startSentence: Int?                     // 0-indexed into original transcript
    let endSentence: Int?                       // 0-indexed, inclusive

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        moveType: RhetoricalMoveType,
        confidence: Double,
        alternateType: RhetoricalMoveType? = nil,
        alternateConfidence: Double? = nil,
        briefDescription: String,
        gistA: ChunkGistA? = nil,
        gistB: ChunkGistB? = nil,
        expandedDescription: String? = nil,
        telemetry: ChunkTelemetry? = nil,
        startSentence: Int? = nil,
        endSentence: Int? = nil
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.moveType = moveType
        self.confidence = confidence
        self.alternateType = alternateType
        self.alternateConfidence = alternateConfidence
        self.briefDescription = briefDescription
        self.gistA = gistA
        self.gistB = gistB
        self.expandedDescription = expandedDescription
        self.telemetry = telemetry
        self.startSentence = startSentence
        self.endSentence = endSentence
    }

    var isLowConfidence: Bool {
        confidence < 0.7
    }

    var isAmbiguous: Bool {
        guard let altConf = alternateConfidence else { return false }
        return (confidence - altConf) < 0.2 // Top two are close
    }

    /// Whether this move has enhanced gist data
    var hasEnhancedGist: Bool {
        gistA != nil && gistB != nil
    }

    /// Best embedding text (prefers gistB for semantic richness, falls back to briefDescription)
    var embeddingText: String {
        gistB?.embeddingText ?? gistA?.embeddingText ?? briefDescription
    }
}

// MARK: - Rhetorical Sequence (Full Video)

struct RhetoricalSequence: Codable, Identifiable, Hashable {
    let id: UUID
    let videoId: String
    let moves: [RhetoricalMove]
    let extractedAt: Date

    init(
        id: UUID = UUID(),
        videoId: String,
        moves: [RhetoricalMove],
        extractedAt: Date = Date()
    ) {
        self.id = id
        self.videoId = videoId
        self.moves = moves
        self.extractedAt = extractedAt
    }

    // Just the move labels in order (for comparison)
    var moveSequence: [RhetoricalMoveType] {
        moves.map { $0.moveType }
    }

    // Parent-level sequence (6 categories only)
    var parentSequence: [RhetoricalCategory] {
        moves.map { $0.moveType.category }
    }

    // String version for display
    var moveSequenceString: String {
        moves.map { $0.moveType.rawValue }.joined(separator: " → ")
    }

    // Parent-level string for display
    var parentSequenceString: String {
        moves.map { $0.moveType.category.rawValue }.joined(separator: " → ")
    }

    // Average confidence across all moves
    var averageConfidence: Double {
        guard !moves.isEmpty else { return 0 }
        return moves.map { $0.confidence }.reduce(0, +) / Double(moves.count)
    }

    // Count of low-confidence assignments
    var lowConfidenceCount: Int {
        moves.filter { $0.isLowConfidence }.count
    }

    // Category distribution
    var categoryDistribution: [RhetoricalCategory: Int] {
        var dist: [RhetoricalCategory: Int] = [:]
        for move in moves {
            let cat = move.moveType.category
            dist[cat, default: 0] += 1
        }
        return dist
    }
}

// MARK: - Twin Comparison Result

struct RhetoricalTwinResult: Identifiable, Hashable {
    let id: UUID
    let video1Id: String
    let video2Id: String
    let sequence1: RhetoricalSequence
    let sequence2: RhetoricalSequence
    let matchScore: Double                      // 0-1 how similar (1 = identical)
    let editDistance: Int                       // Raw edit distance
    let alignedMoves: [AlignedMovePair]         // For side-by-side view

    init(
        id: UUID = UUID(),
        video1Id: String,
        video2Id: String,
        sequence1: RhetoricalSequence,
        sequence2: RhetoricalSequence,
        matchScore: Double,
        editDistance: Int,
        alignedMoves: [AlignedMovePair]
    ) {
        self.id = id
        self.video1Id = video1Id
        self.video2Id = video2Id
        self.sequence1 = sequence1
        self.sequence2 = sequence2
        self.matchScore = matchScore
        self.editDistance = editDistance
        self.alignedMoves = alignedMoves
    }

    static func == (lhs: RhetoricalTwinResult, rhs: RhetoricalTwinResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct AlignedMovePair: Codable, Identifiable, Hashable {
    let id: UUID
    let position: Int
    let move1: RhetoricalMove?
    let move2: RhetoricalMove?

    init(id: UUID = UUID(), position: Int, move1: RhetoricalMove?, move2: RhetoricalMove?) {
        self.id = id
        self.position = position
        self.move1 = move1
        self.move2 = move2
    }

    var isMatch: Bool {
        guard let m1 = move1, let m2 = move2 else { return false }
        return m1.moveType == m2.moveType
    }

    var isGap: Bool {
        move1 == nil || move2 == nil
    }
}

// MARK: - AI Response Model (for parsing)

struct RhetoricalExtractionResponse: Codable {
    let moves: [RhetoricalMoveAIResponse]
}

/// AI response model for gist variants
struct GistAIResponse: Codable {
    let subject: [String]
    let premise: String
    let frame: String

    func toChunkGistA() -> ChunkGistA? {
        guard let frameEnum = GistFrame.parse(frame) else {
            print("⚠️ [GistAIResponse] Invalid frame for GistA: '\(frame)'. Valid frames: \(GistFrame.allCases.map { $0.rawValue })")
            return nil
        }
        return ChunkGistA(subject: subject, premise: premise, frame: frameEnum)
    }

    func toChunkGistB() -> ChunkGistB? {
        guard let frameEnum = GistFrame.parse(frame) else {
            print("⚠️ [GistAIResponse] Invalid frame for GistB: '\(frame)'. Valid frames: \(GistFrame.allCases.map { $0.rawValue })")
            return nil
        }
        return ChunkGistB(subject: subject, premise: premise, frame: frameEnum)
    }
}

/// AI response model for telemetry
struct TelemetryAIResponse: Codable {
    let dominantStance: String
    let perspectiveCounts: PerspectiveCountsAIResponse
    let sentenceFlags: SentenceFlagsAIResponse

    struct PerspectiveCountsAIResponse: Codable {
        let firstPerson: Int
        let secondPerson: Int
        let thirdPerson: Int

        enum CodingKeys: String, CodingKey {
            case firstPerson = "first_person"
            case secondPerson = "second_person"
            case thirdPerson = "third_person"
        }
    }

    struct SentenceFlagsAIResponse: Codable {
        let number: Int
        let temporal: Int
        let contrast: Int
        let question: Int
        let quote: Int
        let spatial: Int
        let technical: Int
    }

    enum CodingKeys: String, CodingKey {
        case dominantStance = "dominant_stance"
        case perspectiveCounts = "perspective_counts"
        case sentenceFlags = "sentence_flags"
    }

    func toChunkTelemetry() -> ChunkTelemetry {
        // DominantStance.parse always returns a valid value (defaults to .asserting)
        let stance = DominantStance.parse(dominantStance)
        return ChunkTelemetry(
            dominantStance: stance,
            firstPersonCount: perspectiveCounts.firstPerson,
            secondPersonCount: perspectiveCounts.secondPerson,
            thirdPersonCount: perspectiveCounts.thirdPerson,
            numberCount: sentenceFlags.number,
            temporalCount: sentenceFlags.temporal,
            contrastCount: sentenceFlags.contrast,
            questionCount: sentenceFlags.question,
            quoteCount: sentenceFlags.quote,
            spatialCount: sentenceFlags.spatial,
            technicalCount: sentenceFlags.technical
        )
    }
}

struct RhetoricalMoveAIResponse: Codable {
    let chunkIndex: Int
    let moveLabel: String
    let confidence: Double
    let alternateLabel: String?
    let alternateConfidence: Double?
    let briefDescription: String

    // New enhanced fields (optional for backwards compatibility with old data)
    let gistA: GistAIResponse?
    let gistB: GistAIResponse?
    let expandedDescription: String?
    let telemetry: TelemetryAIResponse?

    // Use snake_case for ALL keys to match prompt output format
    enum CodingKeys: String, CodingKey {
        case chunkIndex = "chunk_index"
        case moveLabel = "move_label"
        case confidence
        case alternateLabel = "alternate_label"
        case alternateConfidence = "alternate_confidence"
        case briefDescription = "brief_description"
        case gistA = "gist_a"
        case gistB = "gist_b"
        case expandedDescription = "expanded_description"
        case telemetry
    }

    func toRhetoricalMove() -> RhetoricalMove? {
        guard let moveType = RhetoricalMoveType.parse(moveLabel) else {
            print("⚠️ [RhetoricalMoveAIResponse] Could not parse move_label: '\(moveLabel)'")
            return nil
        }

        let altType = alternateLabel.flatMap { RhetoricalMoveType.parse($0) }

        // Parse enhanced fields
        let parsedGistA = gistA?.toChunkGistA()
        let parsedGistB = gistB?.toChunkGistB()
        let parsedTelemetry = telemetry?.toChunkTelemetry()

        // Log if enhanced data was provided but failed to parse
        if gistA != nil && parsedGistA == nil {
            print("⚠️ [Chunk \(chunkIndex)] GistA provided but failed to parse")
        }
        if gistB != nil && parsedGistB == nil {
            print("⚠️ [Chunk \(chunkIndex)] GistB provided but failed to parse")
        }
        if telemetry != nil && parsedTelemetry == nil {
            print("⚠️ [Chunk \(chunkIndex)] Telemetry provided but failed to parse")
        }

        return RhetoricalMove(
            chunkIndex: chunkIndex,
            moveType: moveType,
            confidence: confidence,
            alternateType: altType,
            alternateConfidence: alternateConfidence,
            briefDescription: briefDescription,
            gistA: parsedGistA,
            gistB: parsedGistB,
            expandedDescription: expandedDescription,
            telemetry: parsedTelemetry
        )
    }
}

// MARK: - Multi-Stage Twin Finding Models

/// Stage 1 result: Coarse comparison at parent level
struct CoarseComparisonResult: Identifiable {
    let id = UUID()
    let video1Id: String
    let video2Id: String
    let sequence1: RhetoricalSequence
    let sequence2: RhetoricalSequence
    let parentMatchScore: Double           // 0-1 based on parent-level Levenshtein
    let parentEditDistance: Int            // Raw edit distance at parent level

    // Rank by parent match score
    static func < (lhs: CoarseComparisonResult, rhs: CoarseComparisonResult) -> Bool {
        lhs.parentMatchScore > rhs.parentMatchScore
    }
}

/// Stage 2 result: Fine-grained comparison with same-parent tolerance
struct FineComparisonResult: Identifiable {
    let id = UUID()
    let video1Id: String
    let video2Id: String
    let sequence1: RhetoricalSequence
    let sequence2: RhetoricalSequence
    let parentMatchScore: Double           // From Stage 1
    let fineScore: Double                  // Weighted score with same-parent tolerance
    let chunkComparisons: [ChunkComparison]

    var mismatchedChunks: [ChunkComparison] {
        chunkComparisons.filter { !$0.isExactMatch }
    }

    var sameParentMismatches: [ChunkComparison] {
        chunkComparisons.filter { !$0.isExactMatch && $0.isSameParent }
    }

    var differentParentMismatches: [ChunkComparison] {
        chunkComparisons.filter { !$0.isSameParent }
    }
}

/// Comparison of a single chunk position between two videos
struct ChunkComparison: Identifiable {
    let id: UUID
    let chunkIndex: Int
    let move1: RhetoricalMove?
    let move2: RhetoricalMove?
    let chunkScore: Double                 // 1.0 = exact, 0.7 = same parent, 0.0 = different parent

    // Stage 3 AI resolution (filled in later)
    var aiVerdict: SemanticVerdict?
    var adjustedScore: Double?

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        move1: RhetoricalMove?,
        move2: RhetoricalMove?,
        chunkScore: Double,
        aiVerdict: SemanticVerdict? = nil,
        adjustedScore: Double? = nil
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.move1 = move1
        self.move2 = move2
        self.chunkScore = chunkScore
        self.aiVerdict = aiVerdict
        self.adjustedScore = adjustedScore
    }

    var isExactMatch: Bool {
        guard let m1 = move1, let m2 = move2 else { return false }
        return m1.moveType == m2.moveType
    }

    var isSameParent: Bool {
        guard let m1 = move1, let m2 = move2 else { return false }
        return m1.moveType.category == m2.moveType.category
    }

    var isGap: Bool {
        move1 == nil || move2 == nil
    }

    var finalScore: Double {
        adjustedScore ?? chunkScore
    }

    // Match status for UI display
    var matchStatus: ChunkMatchStatus {
        if isGap { return .gap }
        if isExactMatch { return .exactMatch }
        if let verdict = aiVerdict {
            switch verdict.verdict {
            case .same: return verdict.confidence == .high ? .aiConfirmedSame : .aiMaybeSame
            case .different: return .aiConfirmedDifferent
            }
        }
        if isSameParent { return .sameParent }
        return .differentParent
    }
}

enum ChunkMatchStatus {
    case exactMatch           // Green: Same child label
    case sameParent           // Yellow: Different child, same parent (awaiting AI check)
    case aiConfirmedSame      // Yellow-Green: AI says same function (HIGH confidence)
    case aiMaybeSame          // Yellow: AI says same function (MEDIUM confidence)
    case aiConfirmedDifferent // Red: AI says different function
    case differentParent      // Red: Different parent category
    case gap                  // Gray: One video has a chunk the other doesn't
}

/// Stage 3 AI verdict for semantic comparison
struct SemanticVerdict: Codable {
    let verdict: VerdictType
    let sharedFunction: String?            // If SAME, what function they share
    let confidence: VerdictConfidence
    let reasoning: String

    enum VerdictType: String, Codable {
        case same = "SAME"
        case different = "DIFFERENT"
    }

    enum VerdictConfidence: String, Codable {
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
    }
}

/// Final twin result with all stages combined
struct MultiStageTwinResult: Identifiable {
    let id = UUID()
    let video1Id: String
    let video2Id: String
    let sequence1: RhetoricalSequence
    let sequence2: RhetoricalSequence

    // Stage scores
    let stage1ParentScore: Double
    let stage2FineScore: Double
    let stage3AdjustedScore: Double?       // nil if Stage 3 wasn't run

    // Detailed chunk comparisons
    let chunkComparisons: [ChunkComparison]

    // Final verdict
    var finalScore: Double {
        stage3AdjustedScore ?? stage2FineScore
    }

    var confidence: TwinConfidence {
        if finalScore >= 0.9 { return .high }
        if finalScore >= 0.75 { return .medium }
        return .low
    }

    var exactMatchCount: Int {
        chunkComparisons.filter { $0.isExactMatch }.count
    }

    var sameParentCount: Int {
        chunkComparisons.filter { !$0.isExactMatch && $0.isSameParent }.count
    }

    var differentParentCount: Int {
        chunkComparisons.filter { !$0.isSameParent && !$0.isGap }.count
    }

    var aiResolvedCount: Int {
        chunkComparisons.filter { $0.aiVerdict != nil }.count
    }

    enum TwinConfidence: String {
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
    }
}

// MARK: - Stage 3 AI Response Model

struct SemanticComparisonRequest {
    let chunkIndex: Int
    let label1: RhetoricalMoveType
    let label2: RhetoricalMoveType
    let text1: String
    let text2: String
    let video1Id: String
    let video2Id: String
}

struct SemanticComparisonResponse: Codable {
    let chunkIndex: Int
    let verdict: String                    // "SAME" or "DIFFERENT"
    let sharedFunction: String?
    let confidence: String                 // "HIGH", "MEDIUM", "LOW"
    let reasoning: String

    func toVerdict() -> SemanticVerdict? {
        guard let verdictType = SemanticVerdict.VerdictType(rawValue: verdict),
              let conf = SemanticVerdict.VerdictConfidence(rawValue: confidence) else {
            return nil
        }
        return SemanticVerdict(
            verdict: verdictType,
            sharedFunction: sharedFunction,
            confidence: conf,
            reasoning: reasoning
        )
    }
}
