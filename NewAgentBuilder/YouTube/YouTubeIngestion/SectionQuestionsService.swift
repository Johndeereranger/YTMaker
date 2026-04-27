//
//  SectionQuestionsService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/29/26.
//

import Foundation

/// Orchestrates AI calls for "What questions does this section answer?" analysis.
/// Supports single and batch generation with concurrency throttling.
@MainActor
class SectionQuestionsService: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var results: [SectionQuestionResult] = []
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var totalCount = 0
    @Published var currentLabel = ""

    // MARK: - Configuration

    var maxConcurrent: Int = 3

    // MARK: - Cancel Support

    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    // MARK: - Data Collection

    /// Collects individual sections from videos, optionally filtered by move label and/or position.
    ///
    /// - Parameters:
    ///   - videos: All videos to scan
    ///   - filterMoveLabel: If set, only include sections with this move type
    ///   - filterPosition: If set, only include sections at this position
    /// - Returns: Array of section inputs ready for AI analysis
    static func collectSections(
        from videos: [YouTubeVideo],
        filterMoveLabel: RhetoricalMoveType? = nil,
        filterPosition: FingerprintPosition? = nil
    ) -> [SectionQuestionInput] {
        var inputs: [SectionQuestionInput] = []

        let videosWithSequences = videos.filter {
            $0.rhetoricalSequence != nil && $0.transcript != nil
        }

        for video in videosWithSequences {
            guard let sequence = video.rhetoricalSequence,
                  let transcript = video.transcript else { continue }
            let seqLength = sequence.moves.count
            guard seqLength >= 1 else { continue }

            let sentences = SentenceParser.parse(transcript)

            for move in sequence.moves {
                // Extract raw transcript text using sentence ranges
                guard let start = move.startSentence,
                      let end = move.endSentence,
                      start >= 0,
                      end < sentences.count,
                      start <= end else { continue }

                let chunkSentences = Array(sentences[start...end])
                let text = chunkSentences.joined(separator: " ")
                guard !text.isEmpty else { continue }

                let position = FingerprintSlotKey.positionBucket(
                    chunkIndex: move.chunkIndex,
                    sequenceLength: seqLength
                )

                // Apply filters
                if let filterMove = filterMoveLabel, move.moveType != filterMove {
                    continue
                }
                if let filterPos = filterPosition, position != filterPos {
                    continue
                }

                inputs.append(SectionQuestionInput(
                    videoId: video.videoId,
                    videoTitle: video.title,
                    chunkIndex: move.chunkIndex,
                    moveType: move.moveType,
                    position: position,
                    sectionText: text,
                    briefDescription: move.briefDescription
                ))
            }
        }

        return inputs
    }

    // MARK: - Generate Single

    func generateSingle(
        input: SectionQuestionInput,
        creatorName: String,
        creatorId: String,
        saveToFirebase: Bool = true
    ) async -> SectionQuestionResult {
        let systemPrompt = SectionQuestionsPromptEngine.buildSystemPrompt()
        let userPrompt = SectionQuestionsPromptEngine.buildUserPrompt(
            input: input,
            creatorName: creatorName
        )
        let params = SectionQuestionsPromptEngine.defaultParams()

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: params
        )

        guard let bundle = bundle else {
            return SectionQuestionResult(
                input: input,
                status: .failed("No response from LLM"),
                questionsAnswered: nil,
                promptSent: userPrompt,
                systemPromptSent: systemPrompt,
                rawResponse: nil,
                tokensUsed: nil,
                error: "No response from LLM"
            )
        }

        let questionsText = bundle.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build Firestore document
        let doc = SectionQuestionsDocument(
            creatorId: creatorId,
            videoId: input.videoId,
            videoTitle: input.videoTitle,
            chunkIndex: input.chunkIndex,
            moveLabel: input.moveType.rawValue,
            position: input.position.rawValue,
            sectionText: input.sectionText,
            briefDescription: input.briefDescription,
            questionsAnswered: questionsText,
            generatedAt: Date(),
            promptSent: userPrompt,
            systemPromptSent: systemPrompt,
            tokensUsed: bundle.totalTokens
        )

        if saveToFirebase {
            do {
                try await SectionQuestionsFirebaseService.shared.save(doc)
            } catch {
                return SectionQuestionResult(
                    input: input,
                    status: .failed("LLM succeeded but Firebase save failed: \(error.localizedDescription)"),
                    questionsAnswered: questionsText,
                    promptSent: userPrompt,
                    systemPromptSent: systemPrompt,
                    rawResponse: bundle.content,
                    tokensUsed: bundle.totalTokens,
                    error: error.localizedDescription
                )
            }
        }

        return SectionQuestionResult(
            input: input,
            status: .success,
            questionsAnswered: questionsText,
            promptSent: userPrompt,
            systemPromptSent: systemPrompt,
            rawResponse: bundle.content,
            tokensUsed: bundle.totalTokens,
            error: nil
        )
    }

    // MARK: - Generate Batch

    /// Generates section question analysis for all provided inputs.
    /// Uses TaskGroup with maxConcurrent throttling.
    func generateBatch(
        inputs: [SectionQuestionInput],
        creatorName: String,
        creatorId: String,
        saveToFirebase: Bool = true
    ) async {
        cancelled = false
        isRunning = true
        completedCount = 0
        failedCount = 0
        totalCount = inputs.count
        results = []

        guard totalCount > 0 else {
            isRunning = false
            return
        }

        // Initialize pending results
        results = inputs.map { input in
            SectionQuestionResult(
                input: input,
                status: .pending,
                questionsAnswered: nil,
                promptSent: nil,
                systemPromptSent: nil,
                rawResponse: nil,
                tokensUsed: nil,
                error: nil
            )
        }

        // Process with TaskGroup and concurrency throttle
        await withTaskGroup(of: SectionQuestionResult.self) { group in
            var itemIndex = 0
            var activeCount = 0

            while itemIndex < inputs.count || activeCount > 0 {
                if cancelled { break }

                // Add tasks up to maxConcurrent
                while activeCount < maxConcurrent && itemIndex < inputs.count {
                    let input = inputs[itemIndex]
                    itemIndex += 1
                    activeCount += 1

                    currentLabel = "\(input.moveType.displayName) — \(input.videoTitle)"

                    group.addTask { [self] in
                        await self.generateSingle(
                            input: input,
                            creatorName: creatorName,
                            creatorId: creatorId,
                            saveToFirebase: saveToFirebase
                        )
                    }
                }

                // Wait for one to complete
                if let result = await group.next() {
                    activeCount -= 1

                    // Update results array
                    if let idx = results.firstIndex(where: {
                        $0.input.id == result.input.id
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

        currentLabel = ""
        isRunning = false
    }
}
