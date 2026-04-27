//
//  CreatorNarrativeProfilePromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

struct CreatorNarrativeProfilePromptEngine {

    // MARK: - Layer 1: Structural Signature Clustering

    static func layer1Prompt(
        signatures: [(name: String, description: String)],
        spineCount: Int
    ) -> (system: String, user: String) {
        let system = "You are a narrative pattern analyst. Analyze structural signatures extracted from YouTube video narrative spines and return valid JSON only. Do not include any text outside the JSON object."

        var sigList = ""
        for (i, sig) in signatures.enumerated() {
            sigList += "\(i + 1). \"\(sig.name)\" — \(sig.description)\n"
        }

        let user = """
        You have \(signatures.count) structural signature observations from \(spineCount) narrative spines of a single YouTube creator.

        Many are duplicates or near-duplicates with different wording. Your job:

        1. **Cluster** signatures that describe the same underlying technique into a single entry
        2. **Rank** by frequency (how many spines exhibit this pattern)
        3. **Write a canonical name** for each cluster — short, reusable
        4. **Write a consolidated description** that captures the essence from all variants

        Rules:
        - Two signatures with the same core concept but different wording = same cluster
        - Preserve the specificity of the creator's technique — don't generalize to "uses good storytelling"
        - Output max 25 clusters, dropping any that appear fewer than 2 times
        - The frequency field should be your best estimate of how many of the \(spineCount) spines exhibit this pattern

        Raw signatures:
        \(sigList)

        Return JSON:
        {
          "clusteredSignatures": [
            {
              "canonicalName": "Spectacle-then-deflect",
              "description": "Creator opens with visual spectacle then immediately deflects to a mundane detail, creating tonal whiplash.",
              "frequency": 45,
              "variants": ["Spectacle-deflect", "Visual-hook-then-pivot", "Spectacle-then-undercut"]
            }
          ]
        }

        IMPORTANT: Return ONLY the JSON object. No markdown fences, no preamble, no commentary.
        """

        return (system: system, user: user)
    }

    static func parseLayer1Response(
        _ text: String,
        totalInput: Int,
        spineCount: Int
    ) throws -> SignatureAggregationLayer {
        let cleaned = cleanJSON(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw NarrativeSpineError.parseFailed("Layer 1: Could not convert to UTF-8")
        }

        let raw = try JSONDecoder().decode(Layer1RawResponse.self, from: data)

        let clustered = raw.clusteredSignatures.map { sig in
            ClusteredSignature(
                canonicalName: sig.canonicalName,
                description: sig.description,
                frequency: sig.frequency,
                frequencyPercent: Double(sig.frequency) / Double(max(spineCount, 1)) * 100.0,
                variants: sig.variants
            )
        }.sorted { $0.frequency > $1.frequency }

        return SignatureAggregationLayer(
            totalSignaturesInput: totalInput,
            clusteredSignatures: clustered
        )
    }

    // MARK: - Layer 2: Phase Pattern Analysis

    static func layer2Prompt(
        phases: [[NarrativeSpinePhase]],
        spineCount: Int,
        phaseCountStats: (min: Int, max: Int, mode: Int, median: Double)
    ) -> (system: String, user: String) {
        let system = "You are a narrative structure analyst. Analyze phase architectures from YouTube video narrative spines and return valid JSON only. Do not include any text outside the JSON object."

        var phaseList = ""
        for (i, phaseArray) in phases.enumerated() {
            let phaseDesc = phaseArray.map { p in
                let range = p.beatRange.count >= 2
                    ? "Beats \(p.beatRange[0])-\(p.beatRange[1])"
                    : "Beat \(p.beatRange.first ?? 0)"
                return "P\(p.phaseNumber)(\(range)): \(p.name) — \(p.definingTechnique)"
            }.joined(separator: " | ")
            phaseList += "Spine \(i + 1): \(phaseDesc)\n"
        }

        let user = """
        You have \(spineCount) phase architectures from the same YouTube creator.

        Phase count stats: min=\(phaseCountStats.min), max=\(phaseCountStats.max), mode=\(phaseCountStats.mode), median=\(String(format: "%.1f", phaseCountStats.median))

        Analyze these to find:
        1. The **typical phase architecture** — what phases appear at each position and what defines them
        2. How consistent the architecture is across videos
        3. Where variance occurs (beginning rigid but ending varies? vice versa?)

        Phase data:
        \(phaseList)

        Return JSON:
        {
          "typicalArchitecture": [
            {
              "phasePosition": 1,
              "commonNames": ["Experiential immersion", "Sensory grounding"],
              "definingTechniques": ["First-person physical experience", "Scale demonstration"],
              "typicalBeatSpan": "Beats 1-4",
              "frequency": 140
            }
          ],
          "architectureNarrative": "This creator typically uses a 4-phase structure..."
        }

        IMPORTANT: Return ONLY the JSON object. No markdown fences, no preamble, no commentary.
        """

        return (system: system, user: user)
    }

    static func parseLayer2Response(
        _ text: String,
        phaseCountRange: PhaseCountRange
    ) throws -> PhasePatternLayer {
        let cleaned = cleanJSON(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw NarrativeSpineError.parseFailed("Layer 2: Could not convert to UTF-8")
        }

        let raw = try JSONDecoder().decode(Layer2RawResponse.self, from: data)

        let typical = raw.typicalArchitecture.map { phase in
            TypicalPhase(
                phasePosition: phase.phasePosition,
                commonNames: phase.commonNames,
                definingTechniques: phase.definingTechniques,
                typicalBeatSpan: phase.typicalBeatSpan,
                frequency: phase.frequency
            )
        }.sorted { $0.phasePosition < $1.phasePosition }

        return PhasePatternLayer(
            typicalPhaseCount: phaseCountRange,
            typicalArchitecture: typical,
            architectureNarrative: raw.architectureNarrative
        )
    }

    // MARK: - Layer 3: Throughline Pattern Analysis

    static func layer3Prompt(
        throughlines: [String]
    ) -> (system: String, user: String) {
        let system = "You are a narrative pattern analyst. Extract recurring argument movement patterns from YouTube video throughlines and return valid JSON only. Do not include any text outside the JSON object."

        let throughlineList = throughlines.enumerated().map { (i, t) in
            "\(i + 1). \(t)"
        }.joined(separator: "\n\n")

        let user = """
        You have \(throughlines.count) throughlines from narrative spines of the same YouTube creator. Each throughline is a 3-5 sentence summary of the structural logic of one video.

        Analyze ALL \(throughlines.count) throughlines to extract:
        1. The **recurring argument movement pattern** — how does this creator typically move from opening to resolution?
        2. **Common opening moves** — how do the throughlines typically start the argument?
        3. **Common closing moves** — how do they typically resolve?
        4. A narrative explaining the overall pattern

        Focus on the STRUCTURAL movement (e.g., "grounds in experience -> raises a question -> tests obvious answers -> reveals hidden mechanism -> zooms out to implications"), not the content topics.

        Throughlines:
        \(throughlineList)

        Return JSON:
        {
          "recurringMovementPattern": "This creator consistently opens with experiential grounding, then...",
          "commonOpeningMoves": ["Experiential grounding before abstract claims", "Scale demonstration to earn credibility"],
          "commonClosingMoves": ["Zooming out from specific to systemic", "Callback to opening experience with new understanding"],
          "throughlineNarrative": "Across \(throughlines.count) videos, this creator's argument consistently follows a pattern of..."
        }

        IMPORTANT: Return ONLY the JSON object. No markdown fences, no preamble, no commentary.
        """

        return (system: system, user: user)
    }

    static func parseLayer3Response(_ text: String) throws -> ThroughlinePatternLayer {
        let cleaned = cleanJSON(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw NarrativeSpineError.parseFailed("Layer 3: Could not convert to UTF-8")
        }

        let raw = try JSONDecoder().decode(Layer3RawResponse.self, from: data)

        return ThroughlinePatternLayer(
            recurringMovementPattern: raw.recurringMovementPattern,
            commonOpeningMoves: raw.commonOpeningMoves,
            commonClosingMoves: raw.commonClosingMoves,
            throughlineNarrative: raw.throughlineNarrative
        )
    }

    // MARK: - JSON Cleaning Helper

    private static func cleanJSON(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        return cleaned
    }
}

// MARK: - Raw Response Types (private, for JSON decoding only)

private struct Layer1RawResponse: Codable {
    let clusteredSignatures: [RawClusteredSignature]
}

private struct RawClusteredSignature: Codable {
    let canonicalName: String
    let description: String
    let frequency: Int
    let variants: [String]
}

private struct Layer2RawResponse: Codable {
    let typicalArchitecture: [RawTypicalPhase]
    let architectureNarrative: String
}

private struct RawTypicalPhase: Codable {
    let phasePosition: Int
    let commonNames: [String]
    let definingTechniques: [String]
    let typicalBeatSpan: String
    let frequency: Int
}

private struct Layer3RawResponse: Codable {
    let recurringMovementPattern: String
    let commonOpeningMoves: [String]
    let commonClosingMoves: [String]
    let throughlineNarrative: String
}
