//
//  NarrativeSpineModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

// MARK: - Narrative Spine Beat

struct NarrativeSpineBeat: Codable, Identifiable, Hashable {
    var id: Int { beatNumber }

    let beatNumber: Int
    let beatSentence: String    // Full description with → separator: "Creator does X → this sets up Y"
    let function: String        // From 19-label taxonomy (raw string for flexibility)
    let contentTag: String      // Video-specific content anchor
    let dependsOn: [Int]        // Beat numbers this beat depends on
    let creatorPatternNote: String?

    // MARK: - Known Function Labels (must stay in sync with prompt taxonomy)

    static let functionLabels: [String] = [
        "opening-anchor", "frame-set", "setup-plant", "problem-statement",
        "stakes-raise", "context", "expected-path", "dead-end",
        "complication", "method-shift", "discovery", "evidence",
        "reframe", "mechanism", "implication", "escalation",
        "pivot", "callback", "resolution"
    ]

    /// Check if a function label is in the known taxonomy
    static func isKnownFunction(_ label: String) -> Bool {
        functionLabels.contains(label)
    }
}

// MARK: - Narrative Spine Phase

struct NarrativeSpinePhase: Codable, Hashable {
    let phaseNumber: Int
    let beatRange: [Int]            // [start, end] beat numbers
    let name: String                // Short name (e.g., "Experiential immersion")
    let definingTechnique: String   // The technique that defines this phase
}

// MARK: - Structural Signature

struct NarrativeSpineSignature: Codable, Hashable {
    let name: String            // Short reusable label (e.g., "Spectacle-then-deflect")
    let description: String     // 1-2 sentence technique description + beat reference evidence
}

// MARK: - Narrative Spine (Firebase Document)

struct NarrativeSpine: Codable, Identifiable, Hashable {
    var id: String { videoId }

    let videoId: String
    let channelId: String
    let duration: Double            // minutes
    let extractedAt: Date
    let beats: [NarrativeSpineBeat]
    let throughline: String
    let phases: [NarrativeSpinePhase]
    let structuralSignatures: [NarrativeSpineSignature]
    var renderedText: String        // Programmatically reconstructed from structured fields

    // MARK: - Render Text

    /// Deterministically reconstructs the formatted text from structured fields.
    /// Called once after parsing and stored in renderedText.
    mutating func buildRenderedText() {
        renderedText = NarrativeSpine.renderText(
            beats: beats,
            throughline: throughline,
            phases: phases,
            structuralSignatures: structuralSignatures
        )
    }

    /// Static renderer for use before the struct is fully constructed
    static func renderText(
        beats: [NarrativeSpineBeat],
        throughline: String,
        phases: [NarrativeSpinePhase],
        structuralSignatures: [NarrativeSpineSignature]
    ) -> String {
        var lines: [String] = []

        // Beats
        for beat in beats {
            lines.append("Beat \(beat.beatNumber): \(beat.beatSentence)")
            lines.append("Function: \(beat.function)")
            lines.append("Content tag: \(beat.contentTag)")

            if beat.dependsOn.isEmpty || (beat.dependsOn == [0]) {
                lines.append("Depends on: none")
            } else {
                let deps = beat.dependsOn.map { String($0) }.joined(separator: ", ")
                lines.append("Depends on: \(deps)")
            }

            if let note = beat.creatorPatternNote {
                lines.append("Creator pattern note: \(note)")
            }

            lines.append("")
        }

        // Throughline
        lines.append("---")
        lines.append("")
        lines.append("THROUGHLINE")
        lines.append("")
        lines.append(throughline)
        lines.append("")

        // Phase Structure
        lines.append("---")
        lines.append("")
        lines.append("PHASE STRUCTURE")
        lines.append("")
        for phase in phases {
            let range = phase.beatRange.count >= 2
                ? "Beats \(phase.beatRange[0])-\(phase.beatRange[1])"
                : "Beats \(phase.beatRange.first ?? 0)"
            lines.append("- Phase \(phase.phaseNumber) (\(range)): \(phase.name) — \(phase.definingTechnique)")
        }
        lines.append("")

        // Structural Signatures
        lines.append("---")
        lines.append("")
        lines.append("STRUCTURAL SIGNATURES")
        lines.append("")
        for sig in structuralSignatures {
            lines.append("- \(sig.name). \(sig.description)")
        }

        return lines.joined(separator: "\n")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
    }

    static func == (lhs: NarrativeSpine, rhs: NarrativeSpine) -> Bool {
        lhs.videoId == rhs.videoId && lhs.extractedAt == rhs.extractedAt
    }
}

// MARK: - Narrative Spine Status (lightweight flag on video doc)

struct NarrativeSpineStatus: Codable, Hashable {
    var complete: Bool = false
    var beatCount: Int = 0
    var lastUpdated: Date?
}

// MARK: - Fidelity Support Types

struct NarrativeSpineFidelityRun: Identifiable {
    let id = UUID()
    let runNumber: Int
    let spine: NarrativeSpine
}

struct SpineFidelityMetrics {
    let beatCountSpread: (min: Int, max: Int, mode: Int)
    let functionAgreementRate: Double       // 0.0–1.0
    let contentScopeAgreementRate: Double   // 0.0–1.0
    let phaseBoundaryAgreementRate: Double  // 0.0–1.0
    let dependsOnAgreementRate: Double      // 0.0–1.0
    let confusablePairs: [(labelA: String, labelB: String, swapCount: Int, beatPositions: [Int])]

    /// Compute metrics from a set of fidelity runs
    static func compute(from runs: [NarrativeSpineFidelityRun]) -> SpineFidelityMetrics {
        guard !runs.isEmpty else {
            return SpineFidelityMetrics(
                beatCountSpread: (0, 0, 0),
                functionAgreementRate: 0,
                contentScopeAgreementRate: 0,
                phaseBoundaryAgreementRate: 0,
                dependsOnAgreementRate: 0,
                confusablePairs: []
            )
        }

        // Beat count spread
        let beatCounts = runs.map { $0.spine.beats.count }
        let minCount = beatCounts.min() ?? 0
        let maxCount = beatCounts.max() ?? 0
        let modeCount = Self.mode(of: beatCounts)

        // Use the minimum beat count for positional comparison
        let positionCount = minCount

        // Function label agreement
        var functionMatches = 0
        var functionTotal = 0
        var pairCounts: [String: (count: Int, positions: [Int])] = [:]

        for pos in 0..<positionCount {
            let labels = runs.compactMap { run -> String? in
                guard pos < run.spine.beats.count else { return nil }
                return run.spine.beats[pos].function
            }
            guard labels.count == runs.count else { continue }
            functionTotal += 1

            let uniqueLabels = Set(labels)
            if uniqueLabels.count == 1 {
                functionMatches += 1
            } else {
                // Extract confusable pairs
                let sorted = Array(uniqueLabels).sorted()
                for i in 0..<sorted.count {
                    for j in (i+1)..<sorted.count {
                        let key = "\(sorted[i])|\(sorted[j])"
                        var existing = pairCounts[key] ?? (count: 0, positions: [])
                        existing.count += 1
                        existing.positions.append(pos + 1) // 1-indexed beat number
                        pairCounts[key] = existing
                    }
                }
            }
        }

        let functionRate = functionTotal > 0 ? Double(functionMatches) / Double(functionTotal) : 0

        // Content scope agreement (Jaccard similarity on keywords)
        var scopeMatches = 0
        var scopeTotal = 0

        for pos in 0..<positionCount {
            let tags = runs.compactMap { run -> String? in
                guard pos < run.spine.beats.count else { return nil }
                return run.spine.beats[pos].contentTag
            }
            guard tags.count == runs.count else { continue }
            scopeTotal += 1

            let keywordSets = tags.map { Self.extractKeywords(from: $0) }
            let allPairsAboveThreshold = Self.allPairsJaccardAboveThreshold(keywordSets, threshold: 0.3)
            if allPairsAboveThreshold {
                scopeMatches += 1
            }
        }

        let scopeRate = scopeTotal > 0 ? Double(scopeMatches) / Double(scopeTotal) : 0

        // Phase boundary agreement
        let phaseArrays = runs.map { run in
            run.spine.phases.map { $0.beatRange }
        }
        let phaseReference = phaseArrays.first ?? []
        var phaseMatches = 0
        for arr in phaseArrays {
            if arr == phaseReference { phaseMatches += 1 }
        }
        let phaseRate = runs.count > 0 ? Double(phaseMatches) / Double(runs.count) : 0

        // DependsOn chain consistency
        var depsMatches = 0
        var depsTotal = 0

        for pos in 0..<positionCount {
            let depsArrays = runs.compactMap { run -> [Int]? in
                guard pos < run.spine.beats.count else { return nil }
                return run.spine.beats[pos].dependsOn.sorted()
            }
            guard depsArrays.count == runs.count else { continue }
            depsTotal += 1

            let reference = depsArrays[0]
            if depsArrays.allSatisfy({ $0 == reference }) {
                depsMatches += 1
            }
        }

        let depsRate = depsTotal > 0 ? Double(depsMatches) / Double(depsTotal) : 0

        // Build confusable pairs
        let confusable = pairCounts.map { (key, value) -> (String, String, Int, [Int]) in
            let parts = key.split(separator: "|").map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : "", value.count, value.positions)
        }.sorted { $0.2 > $1.2 }

        return SpineFidelityMetrics(
            beatCountSpread: (minCount, maxCount, modeCount),
            functionAgreementRate: functionRate,
            contentScopeAgreementRate: scopeRate,
            phaseBoundaryAgreementRate: phaseRate,
            dependsOnAgreementRate: depsRate,
            confusablePairs: confusable
        )
    }

    // MARK: - Helpers

    private static func mode(of values: [Int]) -> Int {
        var freq: [Int: Int] = [:]
        for v in values { freq[v, default: 0] += 1 }
        return freq.max(by: { $0.value < $1.value })?.key ?? 0
    }

    private static func extractKeywords(from text: String) -> Set<String> {
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
                                       "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
                                       "has", "have", "had", "do", "does", "did", "will", "would", "could",
                                       "should", "may", "might", "that", "this", "these", "those", "it", "its"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(words)
    }

    private static func allPairsJaccardAboveThreshold(_ sets: [Set<String>], threshold: Double) -> Bool {
        guard sets.count >= 2 else { return true }
        for i in 0..<sets.count {
            for j in (i+1)..<sets.count {
                let intersection = sets[i].intersection(sets[j])
                let union = sets[i].union(sets[j])
                let jaccard = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
                if jaccard < threshold { return false }
            }
        }
        return true
    }
}

// MARK: - Stored Fidelity Test (UserDefaults)

struct StoredSpineFidelityTest: Codable {
    let date: Date
    let runCount: Int
    let temperature: Double
    let beatCountMin: Int
    let beatCountMax: Int
    let beatCountMode: Int
    let functionAgreementRate: Double
    let contentScopeAgreementRate: Double
    let phaseBoundaryAgreementRate: Double
}
