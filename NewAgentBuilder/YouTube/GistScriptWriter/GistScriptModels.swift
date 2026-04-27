//
//  GistScriptModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import Foundation

// MARK: - Rambling Gist (extracted from user's raw text)

struct RamblingGist: Codable, Identifiable, Hashable {
    let id: UUID
    let chunkIndex: Int
    let sourceText: String              // Original rambling text for this chunk

    // Gist variants (matching Johnny's format)
    let gistA: ChunkGistA               // Deterministic for hard matching
    let gistB: ChunkGistB               // Flexible for semantic matching
    let briefDescription: String        // 30-40 word rhetorical function description

    // Optional rhetorical classification
    let moveLabel: String?
    let confidence: Double?

    // Telemetry
    let telemetry: ChunkTelemetry?

    // Provenance (non-nil if extracted from gap response rambling)
    let gapResponseId: UUID?

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        sourceText: String,
        gistA: ChunkGistA,
        gistB: ChunkGistB,
        briefDescription: String,
        moveLabel: String? = nil,
        confidence: Double? = nil,
        telemetry: ChunkTelemetry? = nil,
        gapResponseId: UUID? = nil
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.sourceText = sourceText
        self.gistA = gistA
        self.gistB = gistB
        self.briefDescription = briefDescription
        self.moveLabel = moveLabel
        self.confidence = confidence
        self.telemetry = telemetry
        self.gapResponseId = gapResponseId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        gistA = try container.decode(ChunkGistA.self, forKey: .gistA)
        gistB = try container.decode(ChunkGistB.self, forKey: .gistB)
        briefDescription = try container.decode(String.self, forKey: .briefDescription)
        moveLabel = try container.decodeIfPresent(String.self, forKey: .moveLabel)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        telemetry = try container.decodeIfPresent(ChunkTelemetry.self, forKey: .telemetry)
        gapResponseId = try container.decodeIfPresent(UUID.self, forKey: .gapResponseId)
    }
}

// MARK: - Johnny Gist (from analyzed YouTube videos)

struct JohnnyGist: Codable, Identifiable, Hashable {
    let id: UUID
    let videoId: String
    let videoTitle: String
    let channelId: String
    let channelName: String
    let chunkIndex: Int

    // Full chunk text from Johnny's video
    let fullChunkText: String

    // Gist variants
    let gistA: ChunkGistA
    let gistB: ChunkGistB
    let briefDescription: String
    let expandedDescription: String?

    // Rhetorical classification
    let moveLabel: String
    let moveCategory: String
    let confidence: Double

    // Telemetry
    let telemetry: ChunkTelemetry?

    // Position in video
    let positionPercent: Double         // 0.0 - 1.0
    let positionLabel: String           // "Opening", "Middle (45%)", etc.

    init(
        id: UUID = UUID(),
        videoId: String,
        videoTitle: String,
        channelId: String,
        channelName: String,
        chunkIndex: Int,
        fullChunkText: String,
        gistA: ChunkGistA,
        gistB: ChunkGistB,
        briefDescription: String,
        expandedDescription: String? = nil,
        moveLabel: String,
        moveCategory: String,
        confidence: Double,
        telemetry: ChunkTelemetry? = nil,
        positionPercent: Double,
        positionLabel: String
    ) {
        self.id = id
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.channelId = channelId
        self.channelName = channelName
        self.chunkIndex = chunkIndex
        self.fullChunkText = fullChunkText
        self.gistA = gistA
        self.gistB = gistB
        self.briefDescription = briefDescription
        self.expandedDescription = expandedDescription
        self.moveLabel = moveLabel
        self.moveCategory = moveCategory
        self.confidence = confidence
        self.telemetry = telemetry
        self.positionPercent = positionPercent
        self.positionLabel = positionLabel
    }
}

// MARK: - Gist Match Result

struct GistMatch: Identifiable, Hashable {
    let id: UUID
    let ramblingGist: RamblingGist
    let johnnyGist: JohnnyGist
    let similarityScore: Double         // 0.0 - 1.0 from embedding comparison
    let matchType: GistMatchType

    init(
        id: UUID = UUID(),
        ramblingGist: RamblingGist,
        johnnyGist: JohnnyGist,
        similarityScore: Double,
        matchType: GistMatchType
    ) {
        self.id = id
        self.ramblingGist = ramblingGist
        self.johnnyGist = johnnyGist
        self.similarityScore = similarityScore
        self.matchType = matchType
    }

    var isStrongMatch: Bool { similarityScore >= 0.8 }
    var isModerateMatch: Bool { similarityScore >= 0.6 && similarityScore < 0.8 }
    var isWeakMatch: Bool { similarityScore < 0.6 }
}

enum GistMatchType: String, Codable, CaseIterable {
    case gistAToGistA = "A→A"           // Deterministic matching
    case gistBToGistB = "B→B"           // Semantic matching
    case combined = "Combined"           // Weighted combination

    var description: String {
        switch self {
        case .gistAToGistA: return "Strict structural match"
        case .gistBToGistB: return "Semantic meaning match"
        case .combined: return "Combined structural + semantic"
        }
    }
}

// MARK: - Session State (persisted for continuity)

struct GistScriptSession: Codable, Identifiable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Raw input
    var rawRamblingText: String

    // Extracted gists from rambling
    var ramblingGists: [RamblingGist]

    // Matching results
    var matchResults: [GistMatchResult]

    // Selected matches (user-approved)
    var selectedMatches: [UUID]         // GistMatch IDs

    // Session metadata
    var sessionName: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        rawRamblingText: String = "",
        ramblingGists: [RamblingGist] = [],
        matchResults: [GistMatchResult] = [],
        selectedMatches: [UUID] = [],
        sessionName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rawRamblingText = rawRamblingText
        self.ramblingGists = ramblingGists
        self.matchResults = matchResults
        self.selectedMatches = selectedMatches
        self.sessionName = sessionName
        self.notes = notes
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Match Result (for a single rambling gist)

struct GistMatchResult: Codable, Identifiable, Hashable {
    let id: UUID
    let ramblingGistId: UUID
    let topMatches: [GistMatchSummary]   // Top N matches for this gist
    let matchedAt: Date

    init(
        id: UUID = UUID(),
        ramblingGistId: UUID,
        topMatches: [GistMatchSummary],
        matchedAt: Date = Date()
    ) {
        self.id = id
        self.ramblingGistId = ramblingGistId
        self.topMatches = topMatches
        self.matchedAt = matchedAt
    }
}

// Summary for serialization (full JohnnyGist stored separately)
struct GistMatchSummary: Codable, Identifiable, Hashable {
    let id: UUID
    let johnnyGistId: UUID
    let videoId: String
    let videoTitle: String
    let channelName: String
    let chunkIndex: Int
    let similarityScore: Double
    let matchType: GistMatchType

    init(
        id: UUID = UUID(),
        johnnyGistId: UUID,
        videoId: String,
        videoTitle: String,
        channelName: String,
        chunkIndex: Int,
        similarityScore: Double,
        matchType: GistMatchType
    ) {
        self.id = id
        self.johnnyGistId = johnnyGistId
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.channelName = channelName
        self.chunkIndex = chunkIndex
        self.similarityScore = similarityScore
        self.matchType = matchType
    }
}

// MARK: - View State

enum GistScriptPhase: Equatable {
    case inputRambling                   // Paste raw text
    case extractingGists                 // AI processing rambling → gists
    case reviewingGists                  // User reviews extracted gists
    case matchingGists                   // Finding Johnny matches
    case reviewingMatches                // User reviews matches
    case expandingChunks                 // Viewing full Johnny chunks for selected matches
}

// MARK: - Matching Fidelity Test Result (original)

struct GistFidelityTest: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let createdAt: Date

    // Test parameters
    let matchType: GistMatchType
    let topK: Int                        // How many matches per gist

    // Results
    let totalGists: Int
    let strongMatches: Int               // >= 0.8
    let moderateMatches: Int             // 0.6 - 0.8
    let weakMatches: Int                 // < 0.6
    let noMatches: Int                   // No suitable match found

    var successRate: Double {
        guard totalGists > 0 else { return 0 }
        return Double(strongMatches + moderateMatches) / Double(totalGists)
    }

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        matchType: GistMatchType,
        topK: Int,
        totalGists: Int,
        strongMatches: Int,
        moderateMatches: Int,
        weakMatches: Int,
        noMatches: Int
    ) {
        self.id = id
        self.sessionId = sessionId
        self.createdAt = Date()
        self.matchType = matchType
        self.topK = topK
        self.totalGists = totalGists
        self.strongMatches = strongMatches
        self.moderateMatches = moderateMatches
        self.weakMatches = weakMatches
        self.noMatches = noMatches
    }
}

// MARK: - Extraction Fidelity Test (for prompt stability)

/// A single run of the extraction with its results
struct ExtractionFidelityRun: Codable, Identifiable {
    let id: UUID
    let runNumber: Int
    let timestamp: Date
    let temperature: Double
    let gists: [RamblingGist]
    let rawResponse: String              // Full API response for debugging
    let durationSeconds: Double

    init(
        id: UUID = UUID(),
        runNumber: Int,
        temperature: Double,
        gists: [RamblingGist],
        rawResponse: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.runNumber = runNumber
        self.timestamp = Date()
        self.temperature = temperature
        self.gists = gists
        self.rawResponse = rawResponse
        self.durationSeconds = durationSeconds
    }

    var chunkCount: Int { gists.count }
}

/// Result of comparing extraction runs for stability
struct ExtractionFidelityResult: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let inputWordCount: Int
    let temperature: Double
    let totalRuns: Int
    let successfulRuns: Int

    // Chunk-level stability
    let chunkCountVariance: ChunkCountVariance
    let chunkBoundaryDivergences: [ChunkBoundaryDivergence]

    // Gist-level stability
    let moveVariances: [MoveVariance]
    let frameVariances: [FrameVariance]

    // Overall score
    var stabilityScore: Double {
        guard totalRuns > 0 else { return 0 }

        let chunkStability = chunkCountVariance.isStable ? 1.0 : 0.5
        let boundaryStability = chunkBoundaryDivergences.isEmpty ? 1.0 :
            Double(chunkBoundaryDivergences.filter { $0.variance <= 1 }.count) / Double(max(1, chunkBoundaryDivergences.count))
        let moveStability = moveVariances.isEmpty ? 1.0 :
            Double(moveVariances.filter { $0.isStable }.count) / Double(max(1, moveVariances.count))

        return (chunkStability + boundaryStability + moveStability) / 3.0
    }

    init(
        id: UUID = UUID(),
        inputWordCount: Int,
        temperature: Double,
        totalRuns: Int,
        successfulRuns: Int,
        chunkCountVariance: ChunkCountVariance,
        chunkBoundaryDivergences: [ChunkBoundaryDivergence],
        moveVariances: [MoveVariance],
        frameVariances: [FrameVariance]
    ) {
        self.id = id
        self.createdAt = Date()
        self.inputWordCount = inputWordCount
        self.temperature = temperature
        self.totalRuns = totalRuns
        self.successfulRuns = successfulRuns
        self.chunkCountVariance = chunkCountVariance
        self.chunkBoundaryDivergences = chunkBoundaryDivergences
        self.moveVariances = moveVariances
        self.frameVariances = frameVariances
    }
}

/// Variance in how many chunks were produced across runs
struct ChunkCountVariance: Codable {
    let distribution: [Int: Int]         // chunkCount -> runCount
    let minChunks: Int
    let maxChunks: Int
    let dominantCount: Int               // Most common chunk count

    var isStable: Bool { distribution.count == 1 }
    var variance: Int { maxChunks - minChunks }

    var summaryText: String {
        if isStable {
            return "Stable: \(dominantCount) chunks across all runs"
        } else {
            let dist = distribution.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)x" }
                .joined(separator: ", ")
            return "Variance: \(dist)"
        }
    }
}

/// Divergence in where a specific chunk boundary falls
struct ChunkBoundaryDivergence: Codable, Identifiable {
    var id: String { "chunk_\(chunkIndex)" }
    let chunkIndex: Int
    let wordBoundaries: [Int: Int]       // wordOffset -> runCount
    let variance: Int                    // Max difference in word offset

    var isStable: Bool { variance == 0 }

    var summaryText: String {
        let sorted = wordBoundaries.sorted { $0.value > $1.value }
        return sorted.map { "[\($0.key)w]: \($0.value)x" }.joined(separator: ", ")
    }
}

/// Variance in move labels assigned to a chunk position
struct MoveVariance: Codable, Identifiable {
    var id: String { "move_\(chunkIndex)" }
    let chunkIndex: Int
    let moveDistribution: [String: Int]  // moveLabel -> runCount
    let dominantMove: String?
    let dominantPercentage: Double

    var isStable: Bool { moveDistribution.count == 1 }

    var summaryText: String {
        let sorted = moveDistribution.sorted { $0.value > $1.value }
        return sorted.map { "\($0.key): \($0.value)x" }.joined(separator: ", ")
    }
}

/// Variance in frames assigned to a chunk position
struct FrameVariance: Codable, Identifiable {
    var id: String { "frame_\(chunkIndex)" }
    let chunkIndex: Int
    let gistType: String                 // "A" or "B"
    let frameDistribution: [String: Int] // frame -> runCount
    let dominantFrame: String?
    let dominantPercentage: Double

    var isStable: Bool { frameDistribution.count == 1 }
}

/// Full fidelity test session containing all runs and analysis
struct ExtractionFidelitySession: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let inputText: String                // The rambling text being tested
    let runs: [ExtractionFidelityRun]
    let result: ExtractionFidelityResult?

    var inputWordCount: Int {
        inputText.split(separator: " ").count
    }

    init(
        id: UUID = UUID(),
        inputText: String,
        runs: [ExtractionFidelityRun] = [],
        result: ExtractionFidelityResult? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.inputText = inputText
        self.runs = runs
        self.result = result
    }
}

// MARK: - Prompt Version (snapshot of extraction prompt at a point in time)

struct PromptVersion: Codable, Identifiable {
    let id: UUID
    let versionLabel: String               // "v1", "v2", etc.
    let createdAt: Date
    let changeNotes: String                // What changed from previous version

    // Snapshot of the prompt text at save time
    let systemPromptText: String
    let userPromptTemplate: String         // The template (without input text substituted)

    // Fidelity results captured at save time (optional — nil if saved without running test)
    let fidelityResult: ExtractionFidelityResult?
    let fidelityRuns: [ExtractionFidelityRun]?

    // Summary stats for quick comparison
    let chunkCountFromLastRun: Int?        // How many chunks the last extraction produced
    let stabilityScore: Double?            // From fidelity test if run

    init(
        id: UUID = UUID(),
        versionLabel: String,
        changeNotes: String,
        systemPromptText: String,
        userPromptTemplate: String,
        fidelityResult: ExtractionFidelityResult? = nil,
        fidelityRuns: [ExtractionFidelityRun]? = nil,
        chunkCountFromLastRun: Int? = nil,
        stabilityScore: Double? = nil
    ) {
        self.id = id
        self.versionLabel = versionLabel
        self.createdAt = Date()
        self.changeNotes = changeNotes
        self.systemPromptText = systemPromptText
        self.userPromptTemplate = userPromptTemplate
        self.fidelityResult = fidelityResult
        self.fidelityRuns = fidelityRuns
        self.chunkCountFromLastRun = chunkCountFromLastRun
        self.stabilityScore = stabilityScore
    }

    var promptCharCount: Int { systemPromptText.count + userPromptTemplate.count }
}

struct PromptVersionComparison {
    let versionA: PromptVersion
    let versionB: PromptVersion

    var stabilityDelta: Double? {
        guard let a = versionA.stabilityScore, let b = versionB.stabilityScore else { return nil }
        return b - a
    }

    var chunkCountDelta: Int? {
        guard let a = versionA.chunkCountFromLastRun, let b = versionB.chunkCountFromLastRun else { return nil }
        return b - a
    }

    var promptLengthDelta: Int {
        versionB.promptCharCount - versionA.promptCharCount
    }

    var isImproved: Bool? {
        stabilityDelta.map { $0 > 0 }
    }

    var summary: String {
        if let delta = stabilityDelta {
            let direction = delta > 0 ? "improved" : (delta < 0 ? "declined" : "unchanged")
            let pct = Int(abs(delta) * 100)
            return "Stability \(direction) by \(pct)%"
        }
        return "No stability data to compare"
    }
}

// MARK: - Export Formats

extension GistScriptSession {

    /// Export all gists as formatted text
    func exportGistsAsText() -> String {
        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        GIST SCRIPT SESSION
        ════════════════════════════════════════════════════════════════════════════════
        Created: \(createdAt.formatted())
        Updated: \(updatedAt.formatted())
        \(sessionName.map { "Name: \($0)" } ?? "")

        ────────────────────────────────────────────────────────────────────────────────
        ORIGINAL RAMBLING (\(rawRamblingText.split(separator: " ").count) words)
        ────────────────────────────────────────────────────────────────────────────────

        \(rawRamblingText)

        ────────────────────────────────────────────────────────────────────────────────
        EXTRACTED GISTS (\(ramblingGists.count) chunks)
        ────────────────────────────────────────────────────────────────────────────────

        """

        for gist in ramblingGists.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
            output += """

            ╔═══════════════════════════════════════════════════════════════════════════════
            ║ CHUNK \(gist.chunkIndex + 1)\(gist.moveLabel.map { " — \($0.uppercased())" } ?? "")
            ╠═══════════════════════════════════════════════════════════════════════════════
            ║ GIST_A (Deterministic):
            ║   Subject: \(gist.gistA.subject.joined(separator: ", "))
            ║   Premise: \(gist.gistA.premise)
            ║   Frame: \(gist.gistA.frame.rawValue)
            ╠───────────────────────────────────────────────────────────────────────────────
            ║ GIST_B (Flexible):
            ║   Subject: \(gist.gistB.subject.joined(separator: ", "))
            ║   Premise: \(gist.gistB.premise)
            ║   Frame: \(gist.gistB.frame.rawValue)
            ╠───────────────────────────────────────────────────────────────────────────────
            ║ Brief: \(gist.briefDescription)
            ╠───────────────────────────────────────────────────────────────────────────────
            ║ Source Text:
            ║ \(gist.sourceText.replacingOccurrences(of: "\n", with: "\n║ "))
            ╚═══════════════════════════════════════════════════════════════════════════════

            """
        }

        return output
    }

    /// Export matches as formatted text
    func exportMatchesAsText(johnnyGists: [UUID: JohnnyGist]) -> String {
        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        GIST MATCHES
        ════════════════════════════════════════════════════════════════════════════════

        """

        for result in matchResults {
            guard let ramblingGist = ramblingGists.first(where: { $0.id == result.ramblingGistId }) else { continue }

            output += """

            ┌───────────────────────────────────────────────────────────────────────────────
            │ YOUR CHUNK \(ramblingGist.chunkIndex + 1): \(ramblingGist.gistB.premise)
            ├───────────────────────────────────────────────────────────────────────────────
            │ TOP MATCHES:
            """

            for (index, match) in result.topMatches.prefix(3).enumerated() {
                let scorePercent = Int(match.similarityScore * 100)
                output += """

                │
                │ [\(index + 1)] \(scorePercent)% — \(match.channelName)
                │     Video: \(match.videoTitle)
                │     Chunk \(match.chunkIndex + 1)
                """

                if let johnnyGist = johnnyGists[match.johnnyGistId] {
                    output += """

                    │     Johnny's Gist: \(johnnyGist.gistB.premise)
                    │     Full Text Preview: \(String(johnnyGist.fullChunkText.prefix(200)))...
                    """
                }
            }

            output += "\n└───────────────────────────────────────────────────────────────────────────────\n"
        }

        return output
    }
}
