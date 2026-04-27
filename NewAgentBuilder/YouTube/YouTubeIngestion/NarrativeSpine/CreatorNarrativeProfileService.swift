//
//  CreatorNarrativeProfileService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

@MainActor
class CreatorNarrativeProfileService: ObservableObject {
    static let shared = CreatorNarrativeProfileService()

    @Published var buildPhase: ProfileBuildPhase = .idle
    @Published var error: String?
    @Published var currentProfile: CreatorNarrativeProfile?

    private let firebase = CreatorNarrativeProfileFirebaseService.shared
    private let spineFirebase = NarrativeSpineFirebaseService.shared

    private init() {}

    // MARK: - Load Existing Profile

    func loadProfile(channelId: String) async {
        do {
            currentProfile = try await firebase.loadProfile(channelId: channelId)
        } catch {
            print("⚠️ Failed to load creator narrative profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Staleness Detection

    func stalenessInfo(currentSpineVideoIds: [String]) -> (isStale: Bool, newCount: Int, removedCount: Int)? {
        guard let profile = currentProfile else { return nil }
        let profileSet = Set(profile.includedVideoIds)
        let currentSet = Set(currentSpineVideoIds)
        let newIds = currentSet.subtracting(profileSet)
        let removedIds = profileSet.subtracting(currentSet)
        return (isStale: !newIds.isEmpty || !removedIds.isEmpty, newCount: newIds.count, removedCount: removedIds.count)
    }

    // MARK: - Build Profile (Orchestrator)

    func buildProfile(channel: YouTubeChannel, videos: [YouTubeVideo]) async {
        buildPhase = .loadingSpines
        error = nil

        do {
            // 1. Load all spines for this creator
            let spines = try await spineFirebase.loadSpines(channelId: channel.channelId)
            guard spines.count >= 3 else {
                error = "Need at least 3 spines to build a profile (have \(spines.count))"
                buildPhase = .failed
                return
            }

            print("📊 Building Creator Narrative Profile from \(spines.count) spines for \(channel.name)")

            // 2. Build video title lookup for representative selection
            let videoTitleLookup = Dictionary(uniqueKeysWithValues: videos.map { ($0.videoId, $0.title) })

            // 3. Run all 4 layers in parallel
            buildPhase = .buildingLayers

            let results = try await withThrowingTaskGroup(
                of: ProfileLayerResult.self
            ) { group in

                // Layer 1: Structural Signature Aggregation (LLM)
                group.addTask {
                    let layer = try await Self.buildLayer1(spines: spines)
                    return .layer1(layer)
                }

                // Layer 2: Phase Pattern Analysis (LLM)
                group.addTask {
                    let layer = try await Self.buildLayer2(spines: spines)
                    return .layer2(layer)
                }

                // Layer 3: Throughline Pattern Analysis (LLM)
                group.addTask {
                    let layer = try await Self.buildLayer3(spines: spines)
                    return .layer3(layer)
                }

                // Layer 4: Beat Function Distribution (programmatic)
                group.addTask {
                    let layer = Self.buildLayer4(spines: spines)
                    return .layer4(layer)
                }

                // Collect results
                var layer1: SignatureAggregationLayer?
                var layer2: PhasePatternLayer?
                var layer3: ThroughlinePatternLayer?
                var layer4: BeatDistributionLayer?

                for try await result in group {
                    switch result {
                    case .layer1(let l): layer1 = l
                    case .layer2(let l): layer2 = l
                    case .layer3(let l): layer3 = l
                    case .layer4(let l): layer4 = l
                    }
                }

                guard let l1 = layer1, let l2 = layer2, let l3 = layer3, let l4 = layer4 else {
                    throw NarrativeSpineError.parseFailed("One or more layers returned nil")
                }

                return (l1, l2, l3, l4)
            }

            // 4. Select representative spines
            buildPhase = .selectingRepresentatives
            let representatives = Self.selectRepresentatives(
                spines: spines,
                layer1: results.0,
                layer4: results.3,
                videoTitleLookup: videoTitleLookup
            )

            // 5. Build rendered text
            let renderedText = Self.renderProfileText(
                channelName: channel.name,
                spineCount: spines.count,
                layer1: results.0,
                layer2: results.1,
                layer3: results.2,
                layer4: results.3,
                representatives: representatives
            )

            // 6. Construct profile
            let profile = CreatorNarrativeProfile(
                channelId: channel.channelId,
                channelName: channel.name,
                spineCount: spines.count,
                includedVideoIds: spines.map { $0.videoId },
                generatedAt: Date(),
                signatureAggregation: results.0,
                phasePatterns: results.1,
                throughlinePatterns: results.2,
                beatDistribution: results.3,
                representativeSpines: representatives,
                renderedText: renderedText
            )

            // 7. Save to Firebase
            buildPhase = .saving
            try await firebase.saveProfile(profile)

            currentProfile = profile
            buildPhase = .complete
            print("✅ Creator Narrative Profile built: \(spines.count) spines → \(results.0.clusteredSignatures.count) signatures, \(results.1.typicalArchitecture.count) phases, \(representatives.count) representatives")

        } catch {
            self.error = error.localizedDescription
            buildPhase = .failed
            print("❌ Profile build failed: \(error)")
        }
    }
}

// MARK: - Layer Builders (nonisolated static — per CLAUDE.md parallel LLM pattern)

extension CreatorNarrativeProfileService {

    private enum ProfileLayerResult: Sendable {
        case layer1(SignatureAggregationLayer)
        case layer2(PhasePatternLayer)
        case layer3(ThroughlinePatternLayer)
        case layer4(BeatDistributionLayer)
    }

    // MARK: - Layer 1: Structural Signatures (LLM)

    nonisolated static func buildLayer1(spines: [NarrativeSpine]) async throws -> SignatureAggregationLayer {
        var allSignatures: [(name: String, description: String)] = []
        for spine in spines {
            for sig in spine.structuralSignatures {
                allSignatures.append((name: sig.name, description: sig.description))
            }
        }

        print("📋 Layer 1: Clustering \(allSignatures.count) raw signatures from \(spines.count) spines")

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let (system, user) = CreatorNarrativeProfilePromptEngine.layer1Prompt(
            signatures: allSignatures,
            spineCount: spines.count
        )

        let response = await adapter.generate_response(
            prompt: user,
            promptBackgroundInfo: system,
            params: ["temperature": 0.2, "max_tokens": 8000]
        )

        guard !response.isEmpty else {
            throw NarrativeSpineError.apiError("Layer 1: Empty response from LLM")
        }

        let result = try CreatorNarrativeProfilePromptEngine.parseLayer1Response(
            response,
            totalInput: allSignatures.count,
            spineCount: spines.count
        )
        print("✅ Layer 1 complete: \(result.clusteredSignatures.count) clustered signatures")
        return result
    }

    // MARK: - Layer 2: Phase Patterns (LLM)

    nonisolated static func buildLayer2(spines: [NarrativeSpine]) async throws -> PhasePatternLayer {
        let allPhases: [[NarrativeSpinePhase]] = spines.map { $0.phases }

        let phaseCounts = allPhases.map { $0.count }
        let minPhases = phaseCounts.min() ?? 0
        let maxPhases = phaseCounts.max() ?? 0
        let sortedCounts = phaseCounts.sorted()
        let medianPhases: Double
        if sortedCounts.isEmpty {
            medianPhases = 0
        } else if sortedCounts.count % 2 == 0 {
            medianPhases = Double(sortedCounts[sortedCounts.count / 2 - 1] + sortedCounts[sortedCounts.count / 2]) / 2.0
        } else {
            medianPhases = Double(sortedCounts[sortedCounts.count / 2])
        }
        let modePhases = mode(of: phaseCounts)

        print("📋 Layer 2: Analyzing phase patterns from \(spines.count) spines (mode=\(modePhases) phases)")

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let (system, user) = CreatorNarrativeProfilePromptEngine.layer2Prompt(
            phases: allPhases,
            spineCount: spines.count,
            phaseCountStats: (min: minPhases, max: maxPhases, mode: modePhases, median: medianPhases)
        )

        let response = await adapter.generate_response(
            prompt: user,
            promptBackgroundInfo: system,
            params: ["temperature": 0.2, "max_tokens": 8000]
        )

        guard !response.isEmpty else {
            throw NarrativeSpineError.apiError("Layer 2: Empty response from LLM")
        }

        let result = try CreatorNarrativeProfilePromptEngine.parseLayer2Response(
            response,
            phaseCountRange: PhaseCountRange(min: minPhases, max: maxPhases, mode: modePhases, median: medianPhases)
        )
        print("✅ Layer 2 complete: \(result.typicalArchitecture.count) typical phases")
        return result
    }

    // MARK: - Layer 3: Throughline Patterns (LLM)

    nonisolated static func buildLayer3(spines: [NarrativeSpine]) async throws -> ThroughlinePatternLayer {
        let throughlines = spines.map { $0.throughline }

        print("📋 Layer 3: Analyzing \(throughlines.count) throughlines")

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let (system, user) = CreatorNarrativeProfilePromptEngine.layer3Prompt(
            throughlines: throughlines
        )

        let response = await adapter.generate_response(
            prompt: user,
            promptBackgroundInfo: system,
            params: ["temperature": 0.2, "max_tokens": 6000]
        )

        guard !response.isEmpty else {
            throw NarrativeSpineError.apiError("Layer 3: Empty response from LLM")
        }

        let result = try CreatorNarrativeProfilePromptEngine.parseLayer3Response(response)
        print("✅ Layer 3 complete: \(result.commonOpeningMoves.count) opening moves, \(result.commonClosingMoves.count) closing moves")
        return result
    }

    // MARK: - Layer 4: Beat Function Distribution (Programmatic)

    nonisolated static func buildLayer4(spines: [NarrativeSpine]) -> BeatDistributionLayer {
        var totalBeats = 0
        var globalCounts: [String: Int] = [:]
        var positionalCounts: [Int: [String: Int]] = [:]
        var positionCoverage: [Int: Int] = [:]

        for spine in spines {
            for beat in spine.beats {
                totalBeats += 1
                globalCounts[beat.function, default: 0] += 1
                positionalCounts[beat.beatNumber, default: [:]][beat.function, default: 0] += 1
                positionCoverage[beat.beatNumber, default: 0] += 1
            }
        }

        // Build global distribution sorted by count descending
        let globalDist = globalCounts.map { (label, count) in
            FunctionFrequency(
                functionLabel: label,
                count: count,
                percent: totalBeats > 0 ? Double(count) / Double(totalBeats) * 100.0 : 0
            )
        }.sorted { $0.count > $1.count }

        // Build positional distribution
        let maxPosition = positionalCounts.keys.max() ?? 0
        var positionalDist: [PositionalBeat] = []

        if maxPosition > 0 {
            for pos in 1...maxPosition {
                guard let funcCounts = positionalCounts[pos] else { continue }
                let coverage = positionCoverage[pos] ?? 0

                let topFuncs = funcCounts.sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { (label, count) in
                        FunctionAtPosition(
                            functionLabel: label,
                            count: count,
                            percent: coverage > 0 ? Double(count) / Double(coverage) * 100.0 : 0
                        )
                    }

                positionalDist.append(PositionalBeat(
                    beatPosition: pos,
                    topFunctions: Array(topFuncs),
                    spinesCoveringThisPosition: coverage
                ))
            }
        }

        print("✅ Layer 4 complete: \(totalBeats) beats, \(globalDist.count) function labels, positions 1-\(maxPosition)")

        return BeatDistributionLayer(
            totalBeatsAnalyzed: totalBeats,
            globalDistribution: globalDist,
            positionalDistribution: positionalDist
        )
    }

    // MARK: - Representative Spine Selection (Programmatic)

    nonisolated static func selectRepresentatives(
        spines: [NarrativeSpine],
        layer1: SignatureAggregationLayer,
        layer4: BeatDistributionLayer,
        videoTitleLookup: [String: String]
    ) -> [RepresentativeSpine] {
        guard !spines.isEmpty else { return [] }

        let topSignatureNames = Set(layer1.clusteredSignatures.prefix(10).map { $0.canonicalName.lowercased() })

        // Build global function distribution as lookup
        var globalFuncPercent: [String: Double] = [:]
        for freq in layer4.globalDistribution {
            globalFuncPercent[freq.functionLabel] = freq.percent
        }

        let avgBeats = spines.isEmpty ? 0.0 : Double(layer4.totalBeatsAnalyzed) / Double(spines.count)

        var scored: [(spine: NarrativeSpine, score: Double, reason: String)] = []

        for spine in spines {
            var score = 0.0
            var reasons: [String] = []

            // Signature overlap (40% weight)
            let spineSignatures = Set(spine.structuralSignatures.map { $0.name.lowercased() })
            let overlap = spineSignatures.intersection(topSignatureNames).count
            let sigScore = min(Double(overlap) / max(Double(topSignatureNames.count), 1.0), 1.0) * 0.4
            score += sigScore
            if overlap > 0 {
                reasons.append("\(overlap) top signatures")
            }

            // Beat function distribution cosine similarity (40% weight)
            var spineFuncCounts: [String: Int] = [:]
            for beat in spine.beats {
                spineFuncCounts[beat.function, default: 0] += 1
            }
            let spineTotal = Double(spine.beats.count)
            let allLabels = Set(spineFuncCounts.keys).union(Set(globalFuncPercent.keys))
            var dotProduct = 0.0
            var magA = 0.0
            var magB = 0.0
            for label in allLabels {
                let a = spineTotal > 0 ? Double(spineFuncCounts[label] ?? 0) / spineTotal * 100.0 : 0
                let b = globalFuncPercent[label] ?? 0
                dotProduct += a * b
                magA += a * a
                magB += b * b
            }
            let cosineSim = (magA > 0 && magB > 0) ? dotProduct / (sqrt(magA) * sqrt(magB)) : 0
            score += cosineSim * 0.4
            reasons.append("function similarity \(String(format: "%.0f%%", cosineSim * 100))")

            // Beat count proximity to average (20% weight)
            let beatDiff = abs(Double(spine.beats.count) - avgBeats) / max(avgBeats, 1.0)
            let beatScore = max(1.0 - beatDiff, 0.0) * 0.2
            score += beatScore
            reasons.append("\(spine.beats.count) beats")

            scored.append((spine, score, reasons.joined(separator: ", ")))
        }

        // Sort by score descending, pick top 5
        let top = scored.sorted { $0.score > $1.score }.prefix(5)

        return top.map { item in
            RepresentativeSpine(
                videoId: item.spine.videoId,
                videoTitle: videoTitleLookup[item.spine.videoId] ?? item.spine.videoId,
                matchScore: item.score,
                matchReason: item.reason
            )
        }
    }

    // MARK: - Render Profile Text

    nonisolated static func renderProfileText(
        channelName: String,
        spineCount: Int,
        layer1: SignatureAggregationLayer,
        layer2: PhasePatternLayer,
        layer3: ThroughlinePatternLayer,
        layer4: BeatDistributionLayer,
        representatives: [RepresentativeSpine]
    ) -> String {
        var lines: [String] = []

        lines.append("CREATOR NARRATIVE PROFILE: \(channelName)")
        lines.append("Generated from \(spineCount) narrative spines")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        // Layer 1
        lines.append("STRUCTURAL SIGNATURES (\(layer1.clusteredSignatures.count) unique patterns from \(layer1.totalSignaturesInput) raw)")
        lines.append("")
        for sig in layer1.clusteredSignatures {
            lines.append("- \(sig.canonicalName) (\(sig.frequency)/\(spineCount) spines, \(String(format: "%.0f%%", sig.frequencyPercent)))")
            lines.append("  \(sig.description)")
            if sig.variants.count > 1 {
                lines.append("  Variants: \(sig.variants.joined(separator: ", "))")
            }
            lines.append("")
        }

        // Layer 2
        lines.append(String(repeating: "-", count: 60))
        lines.append("PHASE ARCHITECTURE")
        lines.append("Typical phase count: \(layer2.typicalPhaseCount.mode) (range: \(layer2.typicalPhaseCount.min)-\(layer2.typicalPhaseCount.max))")
        lines.append("")
        for phase in layer2.typicalArchitecture {
            lines.append("Phase \(phase.phasePosition): \(phase.commonNames.first ?? "?") (\(phase.typicalBeatSpan))")
            if !phase.definingTechniques.isEmpty {
                lines.append("  Techniques: \(phase.definingTechniques.prefix(3).joined(separator: "; "))")
            }
        }
        lines.append("")
        lines.append(layer2.architectureNarrative)
        lines.append("")

        // Layer 3
        lines.append(String(repeating: "-", count: 60))
        lines.append("THROUGHLINE PATTERNS")
        lines.append("")
        lines.append("Recurring movement: \(layer3.recurringMovementPattern)")
        lines.append("")
        if !layer3.commonOpeningMoves.isEmpty {
            lines.append("Opening moves:")
            for move in layer3.commonOpeningMoves {
                lines.append("  - \(move)")
            }
            lines.append("")
        }
        if !layer3.commonClosingMoves.isEmpty {
            lines.append("Closing moves:")
            for move in layer3.commonClosingMoves {
                lines.append("  - \(move)")
            }
            lines.append("")
        }
        lines.append(layer3.throughlineNarrative)
        lines.append("")

        // Layer 4
        lines.append(String(repeating: "-", count: 60))
        lines.append("BEAT FUNCTION DISTRIBUTION (\(layer4.totalBeatsAnalyzed) beats)")
        lines.append("")
        for freq in layer4.globalDistribution {
            lines.append("  \(freq.functionLabel): \(freq.count) (\(String(format: "%.1f%%", freq.percent)))")
        }
        lines.append("")
        if !layer4.positionalDistribution.isEmpty {
            lines.append("POSITIONAL PATTERNS (top functions at each beat position):")
            for pos in layer4.positionalDistribution.prefix(20) {
                let funcs = pos.topFunctions.map { "\(String(format: "%.0f%%", $0.percent)) \($0.functionLabel)" }.joined(separator: ", ")
                lines.append("  Beat \(pos.beatPosition) (\(pos.spinesCoveringThisPosition) spines): \(funcs)")
            }
        }

        // Representatives
        lines.append("")
        lines.append(String(repeating: "-", count: 60))
        lines.append("REPRESENTATIVE SPINES")
        for rep in representatives {
            lines.append("- \(rep.videoTitle) (score: \(String(format: "%.2f", rep.matchScore))): \(rep.matchReason)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    nonisolated private static func mode(of values: [Int]) -> Int {
        var freq: [Int: Int] = [:]
        for v in values { freq[v, default: 0] += 1 }
        return freq.max(by: { $0.value < $1.value })?.key ?? 0
    }
}
