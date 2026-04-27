//
//  ScriptTraceW3Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - W3: Donor Retrieval Service

/// Retrieves the best-matching donor sentence from the creator corpus
/// for a given beat's target slot signature and content payload.
class ScriptTraceW3Service {

    // MARK: - Retrieve Donor

    struct DonorMatch {
        let sentence: CreatorSentence
        let matchReason: String
        let similarityScore: Double
    }

    /// Three-pass donor retrieval:
    /// 1. Exact: same move + exact signature match
    /// 2. Relaxed: same move + >= 50% slot overlap
    /// 3. Move-only: same move, any signature
    /// Ranked by embedding cosine similarity when available.
    func retrieveDonor(
        moveType: String,
        targetSignature: String?,
        payloadText: String,
        payloadEmbedding: [Float]?,
        corpus: [CreatorSentence],
        excludeIds: Set<String> = []
    ) -> DonorMatch? {
        let moveFiltered = corpus.filter { $0.moveType == moveType && !excludeIds.contains($0.id) }
        guard !moveFiltered.isEmpty else { return nil }

        // Pass 1: exact signature match
        if let targetSig = targetSignature {
            let exact = moveFiltered.filter { $0.slotSignature == targetSig }
            if let best = rankByEmbedding(candidates: exact, payloadEmbedding: payloadEmbedding) {
                return DonorMatch(
                    sentence: best.sentence,
                    matchReason: "Exact: move=\(moveType), sig=\(targetSig)",
                    similarityScore: best.similarity
                )
            }

            // Pass 2: relaxed — >= 50% slot overlap
            let relaxed = moveFiltered.filter { sentence in
                slotOverlap(sig1: sentence.slotSignature, sig2: targetSig) >= 0.5
            }
            if let best = rankByEmbedding(candidates: relaxed, payloadEmbedding: payloadEmbedding) {
                return DonorMatch(
                    sentence: best.sentence,
                    matchReason: "Relaxed: move=\(moveType), overlap>=50%",
                    similarityScore: best.similarity
                )
            }
        }

        // Pass 3: move-only
        if let best = rankByEmbedding(candidates: moveFiltered, payloadEmbedding: payloadEmbedding) {
            return DonorMatch(
                sentence: best.sentence,
                matchReason: "Move-only: move=\(moveType)",
                similarityScore: best.similarity
            )
        }

        return nil
    }

    // MARK: - Ranking

    private struct RankedCandidate {
        let sentence: CreatorSentence
        let similarity: Double
    }

    private func rankByEmbedding(
        candidates: [CreatorSentence],
        payloadEmbedding: [Float]?
    ) -> RankedCandidate? {
        guard !candidates.isEmpty else { return nil }

        guard let targetEmb = payloadEmbedding else {
            // No embedding available — return first candidate
            return RankedCandidate(sentence: candidates[0], similarity: 0.0)
        }

        var bestSentence: CreatorSentence? = nil
        var bestScore: Double = -1.0

        for sentence in candidates {
            guard let sentenceEmb = sentence.embedding else { continue }
            let score = cosineSimilarity(a: targetEmb, b: sentenceEmb)
            if score > bestScore {
                bestScore = score
                bestSentence = sentence
            }
        }

        if let best = bestSentence {
            return RankedCandidate(sentence: best, similarity: bestScore)
        }

        // None had embeddings — return first
        return RankedCandidate(sentence: candidates[0], similarity: 0.0)
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(a: [Float], b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }

        return Double(dotProduct / denominator)
    }

    // MARK: - Slot Overlap

    private func slotOverlap(sig1: String, sig2: String) -> Double {
        let slots1 = Set(sig1.split(separator: "|").map(String.init))
        let slots2 = Set(sig2.split(separator: "|").map(String.init))

        guard !slots1.isEmpty || !slots2.isEmpty else { return 1.0 }

        let intersection = slots1.intersection(slots2).count
        let union = slots1.union(slots2).count

        return union > 0 ? Double(intersection) / Double(union) : 0.0
    }
}
