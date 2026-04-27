//
//  ScriptTraceW2Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - W2: Slot Bigram Walk Service

/// Deterministic computation: walks the slot bigram chain to determine
/// the target slot signature for each beat in the script.
class ScriptTraceW2Service {

    // MARK: - Walk Bigram Chain

    /// Given a move type and the previous beat's closing signature,
    /// return the most probable next slot signature.
    func walkBigram(
        moveType: String,
        previousSignature: String?,
        bigrams: [SlotBigram],
        profiles: [SectionProfile]
    ) -> String? {
        // If no previous signature, use the most common opening signature
        // from the section profile for this move type.
        if previousSignature == nil {
            let profile = profiles.first { $0.moveType == moveType }
            return profile?.commonOpeningSignatures.first
        }

        // Filter bigrams to those starting from the previous signature
        // and matching the current move type
        let candidates = bigrams.filter { bigram in
            bigram.fromSignature == previousSignature &&
            (bigram.fromMove == moveType || bigram.toMove == moveType)
        }

        guard !candidates.isEmpty else {
            // Fallback: any bigram for this move type
            let moveOnlyCandidates = bigrams.filter { $0.fromMove == moveType || $0.toMove == moveType }
            return moveOnlyCandidates.max(by: { $0.probability < $1.probability })?.toSignature
        }

        // Weighted random selection based on probability
        let totalProb = candidates.reduce(0.0) { $0 + $1.probability }
        var roll = Double.random(in: 0..<totalProb)

        for candidate in candidates.sorted(by: { $0.probability > $1.probability }) {
            roll -= candidate.probability
            if roll <= 0 {
                return candidate.toSignature
            }
        }

        // Fallback to highest probability
        return candidates.max(by: { $0.probability < $1.probability })?.toSignature
    }

    /// Plan slot signatures for all beats in a section.
    func planSlotSequence(
        moveType: String,
        beatCount: Int,
        bigrams: [SlotBigram],
        profiles: [SectionProfile]
    ) -> [String?] {
        var signatures: [String?] = []
        var previousSig: String? = nil

        for _ in 0..<beatCount {
            let nextSig = walkBigram(
                moveType: moveType,
                previousSignature: previousSig,
                bigrams: bigrams,
                profiles: profiles
            )
            signatures.append(nextSig)
            previousSig = nextSig
        }

        return signatures
    }
}
