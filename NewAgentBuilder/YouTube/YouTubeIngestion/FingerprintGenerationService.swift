//
//  FingerprintGenerationService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import Foundation

/// Orchestrates single and batch LLM calls for fingerprint generation.
/// Supports multiple prompt types per slot.
@MainActor
class FingerprintGenerationService: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var results: [FingerprintGenerationResult] = []
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var totalCount = 0
    @Published var currentSlotLabel = ""

    // MARK: - Configuration

    var maxConcurrent: Int = 5

    // MARK: - Cancel Support

    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    // MARK: - Generate Single (one slot + one prompt type)

    /// Generates a fingerprint for a single slot and prompt type.
    /// Set saveToFirebase=false for preview-only testing.
    func generateSingle(
        slotKey: FingerprintSlotKey,
        promptType: FingerprintPromptType,
        availability: FingerprintSlotAvailability,
        creatorName: String,
        creatorId: String,
        saveToFirebase: Bool = true
    ) async -> FingerprintGenerationResult {
        let systemPrompt = FingerprintPromptEngine.buildSystemPrompt(for: promptType)
        let userPrompt = FingerprintPromptEngine.buildUserPrompt(
            slotKey: slotKey,
            promptType: promptType,
            creatorName: creatorName,
            sampleTexts: availability.sampleTexts,
            videoTitles: availability.sourceVideoTitles
        )
        let params = FingerprintPromptEngine.defaultParams(for: promptType)

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: params
        )

        guard let bundle = bundle else {
            return FingerprintGenerationResult(
                slotKey: slotKey,
                promptType: promptType,
                status: .failed("No response from LLM"),
                fingerprintText: nil,
                promptSent: userPrompt,
                systemPromptSent: systemPrompt,
                rawResponse: nil,
                tokensUsed: nil,
                error: "No response from LLM"
            )
        }

        let fingerprintText = bundle.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build document
        let doc = FingerprintDocument(
            creatorId: creatorId,
            moveLabel: slotKey.moveLabel.rawValue,
            position: slotKey.position.rawValue,
            promptType: promptType.rawValue,
            fingerprintText: fingerprintText,
            sourceVideoCount: availability.sourceVideoIds.count,
            sourceSequenceIds: availability.sourceVideoIds,
            generatedAt: Date(),
            promptSent: userPrompt,
            tokensUsed: bundle.totalTokens
        )

        if saveToFirebase {
            do {
                try await FingerprintFirebaseService.shared.saveFingerprint(doc)
            } catch {
                return FingerprintGenerationResult(
                    slotKey: slotKey,
                    promptType: promptType,
                    status: .failed("LLM succeeded but Firebase save failed: \(error.localizedDescription)"),
                    fingerprintText: fingerprintText,
                    promptSent: userPrompt,
                    systemPromptSent: systemPrompt,
                    rawResponse: bundle.content,
                    tokensUsed: bundle.totalTokens,
                    error: error.localizedDescription
                )
            }
        }

        return FingerprintGenerationResult(
            slotKey: slotKey,
            promptType: promptType,
            status: .success,
            fingerprintText: fingerprintText,
            promptSent: userPrompt,
            systemPromptSent: systemPrompt,
            rawResponse: bundle.content,
            tokensUsed: bundle.totalTokens,
            error: nil
        )
    }

    // MARK: - Generate All Types (all prompt types for one slot)

    /// Generates fingerprints for ALL prompt types for a single slot.
    func generateAllTypes(
        slotKey: FingerprintSlotKey,
        availability: FingerprintSlotAvailability,
        creatorName: String,
        creatorId: String,
        saveToFirebase: Bool = true
    ) async -> [FingerprintGenerationResult] {
        var allResults: [FingerprintGenerationResult] = []

        for promptType in FingerprintPromptType.allCases {
            if cancelled { break }
            currentSlotLabel = "\(slotKey.moveLabel.displayName) (\(slotKey.position.displayName)) - \(promptType.displayName)"

            let result = await generateSingle(
                slotKey: slotKey,
                promptType: promptType,
                availability: availability,
                creatorName: creatorName,
                creatorId: creatorId,
                saveToFirebase: saveToFirebase
            )
            allResults.append(result)
        }

        return allResults
    }

    // MARK: - Generate All (Batch: all slots x all types)

    /// Generates fingerprints for all eligible slots across all prompt types.
    /// Uses TaskGroup with maxConcurrent throttling.
    func generateAll(
        availabilities: [FingerprintSlotKey: FingerprintSlotAvailability],
        minimumSamples: Int,
        creatorName: String,
        creatorId: String
    ) async {
        cancelled = false
        isRunning = true
        completedCount = 0
        failedCount = 0
        results = []

        // Filter to slots with enough data
        let eligibleSlots = availabilities.filter { $0.value.hasSufficientData(minimum: minimumSamples) }
        let promptTypes = FingerprintPromptType.allCases
        totalCount = eligibleSlots.count * promptTypes.count

        guard totalCount > 0 else {
            isRunning = false
            return
        }

        // Build work items: cartesian product of (slot, promptType)
        var workItems: [(FingerprintSlotKey, FingerprintPromptType, FingerprintSlotAvailability)] = []
        let sortedSlots = eligibleSlots.sorted { $0.key.moveLabel.rawValue < $1.key.moveLabel.rawValue }
        for (slotKey, availability) in sortedSlots {
            for promptType in promptTypes {
                workItems.append((slotKey, promptType, availability))
            }
        }

        // Initialize pending results
        results = workItems.map { slotKey, promptType, _ in
            FingerprintGenerationResult(
                slotKey: slotKey,
                promptType: promptType,
                status: .pending,
                fingerprintText: nil,
                promptSent: nil,
                systemPromptSent: nil,
                rawResponse: nil,
                tokensUsed: nil,
                error: nil
            )
        }

        // Process with TaskGroup and concurrency throttle
        await withTaskGroup(of: FingerprintGenerationResult.self) { group in
            var itemIndex = 0
            var activeCount = 0

            while itemIndex < workItems.count || activeCount > 0 {
                if cancelled { break }

                // Add tasks up to maxConcurrent
                while activeCount < maxConcurrent && itemIndex < workItems.count {
                    let (slotKey, promptType, availability) = workItems[itemIndex]
                    itemIndex += 1
                    activeCount += 1

                    currentSlotLabel = "\(slotKey.moveLabel.displayName) (\(slotKey.position.displayName)) - \(promptType.displayName)"

                    group.addTask { [self] in
                        await self.generateSingle(
                            slotKey: slotKey,
                            promptType: promptType,
                            availability: availability,
                            creatorName: creatorName,
                            creatorId: creatorId
                        )
                    }
                }

                // Wait for one to complete
                if let result = await group.next() {
                    activeCount -= 1

                    // Update results array
                    if let idx = results.firstIndex(where: {
                        $0.slotKey == result.slotKey && $0.promptType == result.promptType
                    }) {
                        results[idx] = result
                    } else {
                        results.append(result)
                    }

                    switch result.status {
                    case .success:
                        completedCount += 1
                    case .failed:
                        failedCount += 1
                    default:
                        break
                    }
                }
            }
        }

        currentSlotLabel = ""
        isRunning = false
    }
}
