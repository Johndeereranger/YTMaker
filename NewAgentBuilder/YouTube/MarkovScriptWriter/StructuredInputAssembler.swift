//
//  StructuredInputAssembler.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//
//  Loads all structured data from Firebase (fingerprints, donor sentences,
//  section profiles, rhythm templates, confusable pairs) and packages them
//  into a StructuredInputBundle for S1-S4 methods.
//

import Foundation

class StructuredInputAssembler {

    enum AssemblyError: Error, LocalizedError {
        case noCreatorId
        case noTargetMoveType
        case noSectionProfile
        case firebaseError(String)

        var errorDescription: String? {
            switch self {
            case .noCreatorId: return "No creator (channel) ID available"
            case .noTargetMoveType: return "Could not determine target move type from matched videos"
            case .noSectionProfile: return "No section profile found for target move type"
            case .firebaseError(let msg): return "Firebase error: \(msg)"
            }
        }
    }

    /// Assemble all structured inputs for the given creator and target move.
    ///
    /// - Parameters:
    ///   - creatorId: The YouTube channelId to load data for
    ///   - targetMoveType: The rhetorical move type to target (e.g. .sceneSet)
    ///   - targetPosition: The position bucket (e.g. .first)
    /// - Returns: A fully populated StructuredInputBundle
    static func assemble(
        creatorId: String,
        targetMoveType: RhetoricalMoveType,
        targetPosition: FingerprintPosition,
        approvedSpec: ApprovedStructuralSpec? = nil
    ) async throws -> StructuredInputBundle {

        // Run independent Firebase queries in parallel
        async let fingerprintsFetch = loadFingerprints(
            creatorId: creatorId,
            moveType: targetMoveType,
            position: targetPosition
        )
        async let profilesFetch = DonorLibraryA4Service.shared.loadProfiles(forChannelId: creatorId)
        async let templatesFetch = DonorLibraryA5Service.shared.loadTemplates(forChannelId: creatorId)
        async let confusableFetch = ConfusablePairService.shared.loadPairs(creatorId: creatorId)
        async let sentencesFetch = DonorLibraryA2Service.shared.loadSentences(forChannelId: creatorId)

        let fingerprints = try await fingerprintsFetch
        let allProfiles = try await profilesFetch
        let allTemplates = try await templatesFetch
        let confusablePairs = try await confusableFetch
        let allSentences = try await sentencesFetch

        print("[Assembler] ═══ ASSEMBLY SUMMARY ═══")
        print("[Assembler] WHAT: creatorId=\(creatorId) targetMove=\(targetMoveType.rawValue) targetPos=\(targetPosition.rawValue)")
        print("[Assembler] WHAT: approvedSpec=\(approvedSpec != nil ? "YES (moveType=\(approvedSpec!.moveType))" : "nil")")
        print("[Assembler] WHAT: \(fingerprints.count) fingerprints, \(allProfiles.count) profiles, \(allTemplates.count) templates, \(confusablePairs.count) confusable pairs, \(allSentences.count) sentences")

        // Filter profiles and templates to target move type
        let moveTypeRaw = targetMoveType.rawValue
        let sectionProfile = allProfiles.first { $0.moveType == moveTypeRaw }
        print("[Assembler] WHAT: sectionProfile for \"\(moveTypeRaw)\": \(sectionProfile != nil ? "found (median=\(sectionProfile!.medianSentences) sentences)" : "NOT FOUND")")
        if sectionProfile == nil {
            let availableMoves = Set(allProfiles.map(\.moveType)).sorted()
            print("[Assembler] WHY: Available profile moveTypes: \(availableMoves.joined(separator: ", "))")
        }

        // Build confusable lookup
        let confusableLookup = ConfusablePairService.shared.buildLookup(from: confusablePairs)

        // Use approved spec if available and move type matches; otherwise auto-derive
        let targetSignatureSequence: [String]
        let rhythmTemplates: [RhythmTemplate]

        if let spec = approvedSpec, spec.moveType == moveTypeRaw {
            // Approved spec from Structure Workbench — use its sequence and convert overrides to templates
            targetSignatureSequence = spec.signatureSequence
            rhythmTemplates = spec.rhythmOverrides.map { override in
                let posLabel: String
                if override.positionIndex == 0 { posLabel = "opening" }
                else if override.positionIndex == spec.signatureSequence.count - 1 { posLabel = "closing" }
                else { posLabel = "mid" }

                return RhythmTemplate(
                    id: "approved_\(override.positionIndex)",
                    videoId: "approved_spec",
                    channelId: creatorId,
                    moveType: moveTypeRaw,
                    positionInSection: posLabel,
                    wordCountMin: override.wordCountMin,
                    wordCountMax: override.wordCountMax,
                    clauseCountMin: override.clauseCountMin,
                    clauseCountMax: override.clauseCountMax,
                    sentenceType: "statement",
                    commonOpeners: override.commonOpeners,
                    typicalSlotSignature: spec.signatureSequence[override.positionIndex],
                    createdAt: spec.approvedAt
                )
            }
        } else {
            // Fallback: auto-derive from rhythm templates (original behavior)
            let loadedTemplates = allTemplates.filter { $0.moveType == moveTypeRaw }
            rhythmTemplates = loadedTemplates
            targetSignatureSequence = deriveTargetSignatures(
                sectionProfile: sectionProfile,
                rhythmTemplates: loadedTemplates
            )
        }

        let targetSentenceCount = targetSignatureSequence.count

        print("[Assembler] WHAT: targetSignatureSequence (\(targetSentenceCount) sentences): \(targetSignatureSequence)")
        print("[Assembler] WHAT: rhythmTemplates count: \(rhythmTemplates.count)")

        // Filter sentences to this move type for donor matching
        let moveSentences = allSentences.filter { $0.moveType == moveTypeRaw }

        print("[Assembler] WHAT: \(allSentences.count) total sentences → \(moveSentences.count) match moveType \"\(moveTypeRaw)\"")
        if moveSentences.isEmpty {
            let availableMoves = Set(allSentences.map(\.moveType)).sorted()
            print("[Assembler] WHY: Available sentence moveTypes: \(availableMoves.joined(separator: ", "))")
        }

        // Build donor matches per position
        let donorsByPosition = buildDonorMatches(
            targetSignatures: targetSignatureSequence,
            moveSentences: moveSentences,
            confusableLookup: confusableLookup,
            moveType: moveTypeRaw
        )

        let totalDonors = donorsByPosition.reduce(0) { $0 + $1.matchingSentences.count }
        print("[Assembler] RESULT: \(totalDonors) total donor matches across \(donorsByPosition.count) positions")
        for donor in donorsByPosition {
            print("[Assembler]   pos[\(donor.positionIndex)] sig=\"\(donor.targetSignature)\" → \(donor.matchingSentences.count) donors (expanded: \(donor.expandedSignatures.count) variants)")
        }
        print("[Assembler] ═══ ASSEMBLY COMPLETE ═══")

        return StructuredInputBundle(
            creatorId: creatorId,
            fingerprints: fingerprints,
            donorsByPosition: donorsByPosition,
            sectionProfile: sectionProfile,
            rhythmTemplates: rhythmTemplates,
            confusableLookup: confusableLookup,
            targetMoveType: moveTypeRaw,
            targetPosition: targetPosition,
            targetSignatureSequence: targetSignatureSequence,
            targetSentenceCount: targetSentenceCount
        )
    }

    // MARK: - Private Helpers

    /// Load fingerprints for a specific slot by loading all for the creator (cached) and filtering in memory.
    private static func loadFingerprints(
        creatorId: String,
        moveType: RhetoricalMoveType,
        position: FingerprintPosition
    ) async throws -> [FingerprintPromptType: FingerprintDocument] {
        let allDocs = try await FingerprintFirebaseService.shared.loadFingerprints(
            creatorId: creatorId
        )

        let moveLabelRaw = moveType.rawValue
        let positionRaw = position.rawValue

        print("[Assembler] WHAT: Loading fingerprints for creator=\(creatorId)")
        print("[Assembler] WHAT: Total fingerprints loaded from Firebase: \(allDocs.count)")
        print("[Assembler] WHAT: Filtering for moveLabel=\"\(moveLabelRaw)\" position=\"\(positionRaw)\"")

        // Show all unique moveLabel+position combos so we can see what actually exists
        let combos = Set(allDocs.map { "\($0.moveLabel) @ \($0.position)" })
        print("[Assembler] WHY: Available moveLabel+position combos in Firebase (\(combos.count)):")
        for combo in combos.sorted() {
            let count = allDocs.filter { "\($0.moveLabel) @ \($0.position)" == combo }.count
            print("[Assembler]   \(combo) → \(count) docs")
        }

        var result: [FingerprintPromptType: FingerprintDocument] = [:]
        for doc in allDocs where doc.moveLabel == moveLabelRaw && doc.position == positionRaw {
            if let promptType = doc.promptTypeEnum {
                result[promptType] = doc
            }
        }

        print("[Assembler] RESULT: \(result.count) fingerprints matched filter")
        if result.isEmpty {
            print("[Assembler] WHY: Zero matches — either moveLabel \"\(moveLabelRaw)\" or position \"\(positionRaw)\" has no docs. Check combos above.")
        } else {
            print("[Assembler] RESULT: Matched types: \(result.keys.map(\.rawValue).sorted().joined(separator: ", "))")
        }

        return result
    }

    /// Derive the target slot signature sequence from section profile and rhythm templates.
    /// Uses rhythm templates' typical signatures at each position (opening, mid, closing).
    /// Falls back to section profile's common signatures if templates are sparse.
    private static func deriveTargetSignatures(
        sectionProfile: SectionProfile?,
        rhythmTemplates: [RhythmTemplate]
    ) -> [String] {
        // Determine sentence count from section profile median, default to 6
        let sentenceCount = Int(sectionProfile?.medianSentences ?? 6.0)
        guard sentenceCount > 0 else { return [] }

        // Group rhythm templates by position
        let openingTemplates = rhythmTemplates.filter { $0.positionInSection == "opening" }
        let midTemplates = rhythmTemplates.filter { $0.positionInSection == "mid" }
        let closingTemplates = rhythmTemplates.filter { $0.positionInSection == "closing" }

        // Build signature sequence
        var signatures: [String] = []

        for i in 0..<sentenceCount {
            let sig: String
            if i == 0 {
                // Opening position — use rhythm template or section profile
                sig = openingTemplates.first?.typicalSlotSignature
                    ?? sectionProfile?.commonOpeningSignatures.first
                    ?? "actor_reference|narrative_action"
            } else if i == sentenceCount - 1 {
                // Closing position
                sig = closingTemplates.first?.typicalSlotSignature
                    ?? sectionProfile?.commonClosingSignatures.first
                    ?? "evaluative_claim|narrative_action"
            } else {
                // Mid positions — cycle through available mid templates
                let midIndex = (i - 1) % max(midTemplates.count, 1)
                sig = midTemplates.indices.contains(midIndex)
                    ? midTemplates[midIndex].typicalSlotSignature
                    : "narrative_action|visual_detail"
            }
            signatures.append(sig)
        }

        return signatures
    }

    /// Build donor sentence matches for each position in the target signature sequence.
    /// Expands each target signature via confusable pairs for fuzzy matching.
    private static func buildDonorMatches(
        targetSignatures: [String],
        moveSentences: [CreatorSentence],
        confusableLookup: ConfusableLookup,
        moveType: String
    ) -> [DonorSentenceMatch] {
        // Build a signature → [sentence] index for fast lookup
        var signatureIndex: [String: [CreatorSentence]] = [:]
        for sentence in moveSentences {
            signatureIndex[sentence.slotSignature, default: []].append(sentence)
        }

        return targetSignatures.enumerated().map { index, targetSig in
            // Expand signature via confusable pairs
            let expanded = ConfusablePairService.shared.expandSignature(
                targetSig,
                using: confusableLookup,
                moveType: moveType
            )

            // Collect all sentences matching any expanded variant
            var matches: [CreatorSentence] = []
            var seenIds = Set<String>()
            for expandedSig in expanded {
                for sentence in signatureIndex[expandedSig] ?? [] {
                    if seenIds.insert(sentence.id).inserted {
                        matches.append(sentence)
                    }
                }
            }

            return DonorSentenceMatch(
                positionIndex: index,
                targetSignature: targetSig,
                expandedSignatures: expanded,
                matchingSentences: matches
            )
        }
    }
}
