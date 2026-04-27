//
//  StructuralClusteringService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Structural Clustering Service

/// Service for analyzing video structures and clustering them into templates
class StructuralClusteringService {
    static let shared = StructuralClusteringService()

    private let binCount = 10 // Normalize all videos to 10 position bins

    // Spike thresholds - what constitutes a "spike" in tag density
    private let spikeThreshold = 0.3 // 30% density = spike
    private let pivotThreshold = 0.5 // Similarity score below this = pivot

    // Clustering parameters
    private let minClusterSize = 2 // Minimum videos to form a template
    private let similarityThreshold = 0.65 // Minimum similarity to be in same cluster

    private init() {}

    // MARK: - Main Entry Point

    /// Analyze videos and generate structural templates
    func clusterVideos(
        channel: YouTubeChannel,
        boundaryResults: [BoundaryDetectionResult]
    ) -> ClusteringResult {
        // Step 1: Extract structure from each video
        let structures = boundaryResults.map { extractStructure(from: $0) }

        // Step 2: Cluster by structural similarity
        let clusters = clusterByFingerprint(structures)

        // Step 3: Generate templates from clusters
        let templates = clusters.map { generateTemplate(from: $0, channelId: channel.channelId) }

        // Step 4: Find outliers
        let clusteredIds = Set(templates.flatMap { $0.videoIds })
        let outlierIds = structures.map { $0.videoId }.filter { !clusteredIds.contains($0) }

        // Calculate quality metrics
        let avgTightness = templates.isEmpty ? 0 : templates.map { $0.clusterTightness }.reduce(0, +) / Double(templates.count)
        let coverage = structures.isEmpty ? 0 : Double(clusteredIds.count) / Double(structures.count)

        return ClusteringResult(
            channelId: channel.channelId,
            channelName: channel.name,
            createdAt: Date(),
            videoStructures: structures,
            templates: templates,
            outlierVideoIds: outlierIds,
            averageClusterTightness: avgTightness,
            coveragePercent: coverage
        )
    }

    // MARK: - Structure Extraction

    /// Extract the structural sequence from a boundary detection result
    func extractStructure(from result: BoundaryDetectionResult) -> VideoStructure {
        var snapshots: [PositionSnapshot] = []
        var pivotPositions: [Double] = []

        // Calculate average tag densities across all chunks for spike detection
        let avgDensities = calculateAverageDensities(chunks: result.chunks)

        var previousSnapshot: PositionSnapshot?

        for chunk in result.chunks {
            let snapshot = createSnapshot(
                chunk: chunk,
                avgDensities: avgDensities,
                previousSnapshot: previousSnapshot
            )

            snapshots.append(snapshot)

            if snapshot.isPivot {
                pivotPositions.append(chunk.positionInVideo)
            }

            previousSnapshot = snapshot
        }

        // Create fingerprint
        let fingerprint = createFingerprint(
            chunks: result.chunks,
            snapshots: snapshots,
            pivotPositions: pivotPositions
        )

        return VideoStructure(
            videoId: result.videoId,
            videoTitle: result.videoTitle,
            channelId: result.channelId,
            chunkCount: result.chunkCount,
            totalSentences: result.totalSentences,
            sequence: snapshots,
            pivotPositions: pivotPositions,
            fingerprint: fingerprint
        )
    }

    private func calculateAverageDensities(chunks: [Chunk]) -> TagDensity {
        guard !chunks.isEmpty else {
            return TagDensity(
                hasNumber: 0, hasStatistic: 0, hasNamedEntity: 0, hasQuote: 0,
                hasContrastMarker: 0, hasRevealLanguage: 0, hasChallengeLanguage: 0,
                hasFirstPerson: 0, hasSecondPerson: 0, isTransition: 0,
                isSponsorContent: 0, isCallToAction: 0
            )
        }

        let count = Double(chunks.count)
        return TagDensity(
            hasNumber: chunks.map { $0.profile.tagDensity.hasNumber }.reduce(0, +) / count,
            hasStatistic: chunks.map { $0.profile.tagDensity.hasStatistic }.reduce(0, +) / count,
            hasNamedEntity: chunks.map { $0.profile.tagDensity.hasNamedEntity }.reduce(0, +) / count,
            hasQuote: chunks.map { $0.profile.tagDensity.hasQuote }.reduce(0, +) / count,
            hasContrastMarker: chunks.map { $0.profile.tagDensity.hasContrastMarker }.reduce(0, +) / count,
            hasRevealLanguage: chunks.map { $0.profile.tagDensity.hasRevealLanguage }.reduce(0, +) / count,
            hasChallengeLanguage: chunks.map { $0.profile.tagDensity.hasChallengeLanguage }.reduce(0, +) / count,
            hasFirstPerson: chunks.map { $0.profile.tagDensity.hasFirstPerson }.reduce(0, +) / count,
            hasSecondPerson: chunks.map { $0.profile.tagDensity.hasSecondPerson }.reduce(0, +) / count,
            isTransition: chunks.map { $0.profile.tagDensity.isTransition }.reduce(0, +) / count,
            isSponsorContent: chunks.map { $0.profile.tagDensity.isSponsorContent }.reduce(0, +) / count,
            isCallToAction: chunks.map { $0.profile.tagDensity.isCallToAction }.reduce(0, +) / count
        )
    }

    private func createSnapshot(
        chunk: Chunk,
        avgDensities: TagDensity,
        previousSnapshot: PositionSnapshot?
    ) -> PositionSnapshot {
        let density = chunk.profile.tagDensity

        // Detect spikes (significantly above average)
        let contrastSpike = density.hasContrastMarker > max(spikeThreshold, avgDensities.hasContrastMarker * 1.5)
        let revealSpike = density.hasRevealLanguage > max(spikeThreshold, avgDensities.hasRevealLanguage * 1.5)
        let challengeSpike = density.hasChallengeLanguage > max(spikeThreshold, avgDensities.hasChallengeLanguage * 1.5)
        let statSpike = density.hasStatistic > max(spikeThreshold, avgDensities.hasStatistic * 1.5)
        let quoteSpike = density.hasQuote > max(spikeThreshold, avgDensities.hasQuote * 1.5)

        // Build top tags list
        var topTags: [String] = []
        if density.hasFirstPerson > 0.3 { topTags.append("1P") }
        if density.hasSecondPerson > 0.3 { topTags.append("2P") }
        if density.hasStatistic > 0.2 { topTags.append("STAT") }
        if density.hasNamedEntity > 0.3 { topTags.append("ENT") }
        if density.hasQuote > 0.2 { topTags.append("QUOTE") }
        if density.hasContrastMarker > 0.2 { topTags.append("CONTRAST") }
        if density.hasRevealLanguage > 0.2 { topTags.append("REVEAL") }
        if density.hasChallengeLanguage > 0.2 { topTags.append("CHALLENGE") }

        // Detect pivot (significant shift from previous chunk)
        var isPivot = false
        var pivotReason: String?

        if let prev = previousSnapshot {
            // Perspective shift
            if prev.dominantPerspective != chunk.profile.dominantPerspective {
                if (prev.dominantPerspective == .third && chunk.profile.dominantPerspective == .first) ||
                   (prev.dominantPerspective == .first && chunk.profile.dominantPerspective == .second) {
                    isPivot = true
                    pivotReason = "Perspective shift to \(chunk.profile.dominantPerspective.rawValue)"
                }
            }

            // Stance shift
            if prev.dominantStance != chunk.profile.dominantStance {
                if chunk.profile.dominantStance == .questioning || chunk.profile.dominantStance == .challenging {
                    isPivot = true
                    pivotReason = "Stance shift to \(chunk.profile.dominantStance.rawValue)"
                }
            }

            // Spike-based pivots
            if contrastSpike && !prev.hasContrastSpike {
                isPivot = true
                pivotReason = "CONTRAST spike"
            }
            if revealSpike && !prev.hasRevealSpike {
                isPivot = true
                pivotReason = "REVEAL spike"
            }
        }

        return PositionSnapshot(
            position: chunk.positionInVideo,
            chunkIndex: chunk.chunkIndex,
            dominantPerspective: chunk.profile.dominantPerspective,
            dominantStance: chunk.profile.dominantStance,
            topTags: topTags,
            hasContrastSpike: contrastSpike,
            hasRevealSpike: revealSpike,
            hasChallengeSpike: challengeSpike,
            hasStatSpike: statSpike,
            hasQuoteSpike: quoteSpike,
            isPivot: isPivot,
            pivotReason: pivotReason
        )
    }

    // MARK: - Fingerprint Creation

    private func createFingerprint(
        chunks: [Chunk],
        snapshots: [PositionSnapshot],
        pivotPositions: [Double]
    ) -> StructuralFingerprint {
        // Create 10 bins covering 0-100% of video
        var bins: [StructuralFingerprint.BinProfile] = []

        for binIndex in 0..<binCount {
            let binStart = Double(binIndex) / Double(binCount)
            let binEnd = Double(binIndex + 1) / Double(binCount)

            // Find chunks that fall in this bin
            let binChunks = chunks.filter { $0.positionInVideo >= binStart && $0.positionInVideo < binEnd }
            let binSnapshots = snapshots.filter { $0.position >= binStart && $0.position < binEnd }

            // Determine dominant characteristics for this bin
            let perspective = dominantPerspective(from: binChunks)
            let stance = dominantStance(from: binChunks)
            let (hasSpike, spikeType) = detectSpike(from: binSnapshots)

            bins.append(StructuralFingerprint.BinProfile(
                binIndex: binIndex,
                perspective: perspective,
                stance: stance,
                hasSpike: hasSpike,
                spikeType: spikeType
            ))
        }

        // Determine dominant pattern
        let dominantPattern = determineDominantPattern(chunks: chunks, snapshots: snapshots)

        return StructuralFingerprint(
            bins: bins,
            pivotCount: pivotPositions.count,
            firstPivotPosition: pivotPositions.first,
            lastPivotPosition: pivotPositions.last,
            dominantPattern: dominantPattern
        )
    }

    private func dominantPerspective(from chunks: [Chunk]) -> ChunkProfile.DominantValue {
        guard !chunks.isEmpty else { return .mixed }

        let counts = Dictionary(grouping: chunks, by: { $0.profile.dominantPerspective })
        let sorted = counts.sorted {
            if $0.value.count != $1.value.count {
                return $0.value.count > $1.value.count
            }
            return $0.key.rawValue < $1.key.rawValue  // Tie-breaker by enum raw value
        }
        return sorted.first?.key ?? .mixed
    }

    private func dominantStance(from chunks: [Chunk]) -> ChunkProfile.DominantValue {
        guard !chunks.isEmpty else { return .neutral }

        let counts = Dictionary(grouping: chunks, by: { $0.profile.dominantStance })
        let sorted = counts.sorted {
            if $0.value.count != $1.value.count {
                return $0.value.count > $1.value.count
            }
            return $0.key.rawValue < $1.key.rawValue  // Tie-breaker by enum raw value
        }
        return sorted.first?.key ?? .neutral
    }

    private func detectSpike(from snapshots: [PositionSnapshot]) -> (Bool, String?) {
        for snapshot in snapshots {
            if snapshot.hasContrastSpike { return (true, "CONTRAST") }
            if snapshot.hasRevealSpike { return (true, "REVEAL") }
            if snapshot.hasChallengeSpike { return (true, "CHALLENGE") }
            if snapshot.hasStatSpike { return (true, "STAT") }
            if snapshot.hasQuoteSpike { return (true, "QUOTE") }
        }
        return (false, nil)
    }

    private func determineDominantPattern(chunks: [Chunk], snapshots: [PositionSnapshot]) -> String {
        var patterns: [String] = []

        // Check for 1P-heavy
        let firstPersonCount = chunks.filter { $0.profile.dominantPerspective == .first }.count
        if Double(firstPersonCount) / Double(max(1, chunks.count)) > 0.5 {
            patterns.append("1P-heavy")
        }

        // Check for stat-rich
        let statCount = snapshots.filter { $0.hasStatSpike || $0.topTags.contains("STAT") }.count
        if Double(statCount) / Double(max(1, snapshots.count)) > 0.3 {
            patterns.append("stat-rich")
        }

        // Check for question-driven
        let questionCount = chunks.filter { $0.profile.dominantStance == .questioning }.count
        if Double(questionCount) / Double(max(1, chunks.count)) > 0.3 {
            patterns.append("question-driven")
        }

        // Check for late-contrast
        let lateContrastCount = snapshots.filter { $0.position > 0.6 && $0.hasContrastSpike }.count
        if lateContrastCount > 0 {
            patterns.append("late-contrast")
        }

        return patterns.isEmpty ? "standard" : patterns.joined(separator: ", ")
    }

    // MARK: - Clustering

    private func clusterByFingerprint(_ structures: [VideoStructure]) -> [[VideoStructure]] {
        guard !structures.isEmpty else { return [] }

        // Sort by videoId for deterministic clustering order
        let sortedStructures = structures.sorted { $0.videoId < $1.videoId }

        var assigned = Set<String>()
        var clusters: [[VideoStructure]] = []

        for structure in sortedStructures {
            if assigned.contains(structure.videoId) { continue }

            // Find all similar unassigned structures
            var cluster = [structure]
            assigned.insert(structure.videoId)

            for other in sortedStructures where !assigned.contains(other.videoId) {
                let similarity = structure.fingerprint.similarity(to: other.fingerprint)
                if similarity >= similarityThreshold {
                    cluster.append(other)
                    assigned.insert(other.videoId)
                }
            }

            if cluster.count >= minClusterSize {
                clusters.append(cluster)
            }
        }

        return clusters
    }

    // MARK: - Template Generation

    private func generateTemplate(from cluster: [VideoStructure], channelId: String) -> StructuralTemplate {
        let templateId = UUID().uuidString
        let name = generateTemplateName(from: cluster)

        // Get video IDs and ALL video titles
        let videoIds = cluster.map { $0.videoId }
        let exampleTitles = cluster.map { $0.videoTitle }

        // Calculate typical sequence by averaging across cluster
        let typicalSequence = calculateTypicalSequence(from: cluster)

        // Find key pivots (appearing in majority of videos)
        let keyPivots = findKeyPivots(from: cluster)

        // Calculate average chunk count
        let avgChunks = Double(cluster.map { $0.chunkCount }.reduce(0, +)) / Double(cluster.count)

        // Determine dominant characteristics
        var characteristics: [String] = []
        if let firstPattern = cluster.first?.fingerprint.dominantPattern {
            characteristics = firstPattern.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        // Calculate cluster tightness
        let tightness = calculateClusterTightness(cluster)

        return StructuralTemplate(
            id: templateId,
            templateName: name,
            channelId: channelId,
            videoCount: cluster.count,
            videoIds: videoIds,
            exampleVideoTitles: exampleTitles,
            typicalSequence: typicalSequence,
            keyPivots: keyPivots,
            averageChunkCount: avgChunks,
            dominantCharacteristics: characteristics,
            clusterTightness: tightness
        )
    }

    private func generateTemplateName(from cluster: [VideoStructure]) -> String {
        // Analyze cluster characteristics to generate a meaningful name
        guard let first = cluster.first else { return "Unknown" }

        let pivotCount = first.pivotPositions.count
        let pattern = first.fingerprint.dominantPattern

        // Generate name based on characteristics
        if pattern.contains("question-driven") {
            return pivotCount > 2 ? "Inquiry Journey" : "Question Focus"
        } else if pattern.contains("stat-rich") {
            return "Evidence Stack"
        } else if pattern.contains("late-contrast") {
            return "Build & Reveal"
        } else if pattern.contains("1P-heavy") {
            return pivotCount > 2 ? "Personal Journey" : "Direct Address"
        } else if pivotCount == 0 {
            return "Linear Flow"
        } else if pivotCount == 1 {
            return "Single Pivot"
        } else if pivotCount <= 3 {
            return "Classic Arc"
        } else {
            return "Multi-Act"
        }
    }

    private func calculateTypicalSequence(from cluster: [VideoStructure]) -> [TemplateChunk] {
        // Determine typical chunk count
        let avgChunkCount = cluster.map { $0.chunkCount }.reduce(0, +) / max(1, cluster.count)
        let targetChunks = max(3, min(12, avgChunkCount))

        var templateChunks: [TemplateChunk] = []

        for i in 0..<targetChunks {
            let posStart = Double(i) / Double(targetChunks)
            let posEnd = Double(i + 1) / Double(targetChunks)

            // Find snapshots from all videos that fall in this position range
            var positionSnapshots: [PositionSnapshot] = []
            for structure in cluster {
                let matching = structure.sequence.filter {
                    $0.position >= posStart && $0.position < posEnd
                }
                positionSnapshots.append(contentsOf: matching)
            }

            // Determine typical characteristics
            let perspective = mostCommon(positionSnapshots.map { $0.dominantPerspective }) ?? .mixed
            let stance = mostCommon(positionSnapshots.map { $0.dominantStance }) ?? .neutral

            // Find high tags
            var tagCounts: [String: Int] = [:]
            for snapshot in positionSnapshots {
                for tag in snapshot.topTags {
                    tagCounts[tag, default: 0] += 1
                }
            }
            let sortedTags = tagCounts.sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key < $1.key  // Alphabetical tie-breaker
            }
            let highTags = Array(sortedTags.prefix(3).map { $0.key })

            // Check for pivot
            let pivotCount = positionSnapshots.filter { $0.isPivot }.count
            let isPivot = Double(pivotCount) / Double(max(1, positionSnapshots.count)) > 0.4
            let pivotReason = positionSnapshots.first(where: { $0.isPivot })?.pivotReason

            // Determine role
            let role = determineChunkRole(
                position: posStart,
                perspective: perspective,
                stance: stance,
                highTags: highTags,
                isPivot: isPivot
            )

            templateChunks.append(TemplateChunk(
                chunkIndex: i,
                positionStart: posStart,
                positionEnd: posEnd,
                typicalRole: role,
                dominantPerspective: perspective,
                dominantStance: stance,
                highTags: highTags,
                isPivotPoint: isPivot,
                pivotDescription: isPivot ? pivotReason : nil
            ))
        }

        return templateChunks
    }

    private func mostCommon<T: Hashable>(_ items: [T]) -> T? {
        let counts = Dictionary(grouping: items, by: { $0 })
        let sorted = counts.sorted {
            if $0.value.count != $1.value.count {
                return $0.value.count > $1.value.count
            }
            // Deterministic tie-breaker using string description
            return String(describing: $0.key) < String(describing: $1.key)
        }
        return sorted.first?.key
    }

    private func determineChunkRole(
        position: Double,
        perspective: ChunkProfile.DominantValue,
        stance: ChunkProfile.DominantValue,
        highTags: [String],
        isPivot: Bool
    ) -> String {
        // Opening section
        if position < 0.1 {
            if stance == .questioning {
                return "Opening hook"
            } else if highTags.contains("1P") {
                return "Personal intro"
            } else {
                return "Setup"
            }
        }

        // Closing section
        if position > 0.85 {
            if highTags.contains("2P") {
                return "Viewer address"
            } else if highTags.contains("CONTRAST") {
                return "Final thought"
            } else {
                return "Close"
            }
        }

        // Pivot points
        if isPivot {
            if highTags.contains("CONTRAST") {
                return "Pivot - complication"
            } else if highTags.contains("REVEAL") {
                return "Pivot - reveal"
            } else {
                return "Transition"
            }
        }

        // Middle content based on tags
        if highTags.contains("STAT") || highTags.contains("QUOTE") {
            return "Evidence block"
        } else if highTags.contains("ENT") {
            return "Context/background"
        } else if stance == .questioning {
            return "Exploration"
        } else if perspective == .first {
            return "Personal insight"
        } else if perspective == .second {
            return "Viewer engagement"
        }

        return "Development"
    }

    private func findKeyPivots(from cluster: [VideoStructure]) -> [PivotPoint] {
        // Collect all pivot positions and reasons
        var pivotData: [(position: Double, reason: String)] = []

        for structure in cluster {
            for snapshot in structure.sequence where snapshot.isPivot {
                if let reason = snapshot.pivotReason {
                    pivotData.append((snapshot.position, reason))
                }
            }
        }

        // Group by approximate position (within 10%)
        var groupedPivots: [[Double]: [String]] = [:]
        for pivot in pivotData {
            let binned = (pivot.position * 10).rounded() / 10
            let key = [binned]
            groupedPivots[key, default: []].append(pivot.reason)
        }

        // Find pivots that appear in at least 40% of videos
        let threshold = Double(cluster.count) * 0.4
        var keyPivots: [PivotPoint] = []

        for (posArray, reasons) in groupedPivots.sorted(by: { $0.key.first ?? 0 < $1.key.first ?? 0 }) {
            if Double(reasons.count) >= threshold {
                let position = posArray.first ?? 0
                let mostCommonReason = mostCommon(reasons) ?? "Pivot"

                keyPivots.append(PivotPoint(
                    position: position,
                    chunkIndex: Int(position * 10),
                    pivotType: pivotTypeFrom(reason: mostCommonReason),
                    description: mostCommonReason
                ))
            }
        }

        return keyPivots.sorted { $0.position < $1.position }
    }

    private func pivotTypeFrom(reason: String) -> PivotPoint.PivotType {
        if reason.lowercased().contains("contrast") {
            return .contrastSpike
        } else if reason.lowercased().contains("reveal") {
            return .revealSpike
        } else if reason.lowercased().contains("perspective") {
            return .perspectiveShift
        } else if reason.lowercased().contains("stance") {
            return .stanceShift
        } else {
            return .topicTransition
        }
    }

    private func calculateClusterTightness(_ cluster: [VideoStructure]) -> Double {
        guard cluster.count >= 2 else { return 1.0 }

        var totalSimilarity = 0.0
        var comparisons = 0

        for i in 0..<cluster.count {
            for j in (i + 1)..<cluster.count {
                totalSimilarity += cluster[i].fingerprint.similarity(to: cluster[j].fingerprint)
                comparisons += 1
            }
        }

        return comparisons > 0 ? totalSimilarity / Double(comparisons) : 0
    }

    // MARK: - Export

    /// Export clustering result as formatted text
    func exportAsText(_ result: ClusteringResult) -> String {
        return result.summary
    }

    /// Export individual video structure
    func exportVideoStructure(_ structure: VideoStructure) -> String {
        return structure.structureSummary
    }
}
