//
//  DonorLibraryA5Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation
import FirebaseFirestore

// MARK: - A5: Rhythm Template Extraction Service

/// Extracts structural skeletons (rhythm templates) from annotated sentences.
/// Pure computation — no LLM calls. Used for Tier 3 fallback during writing.
@MainActor
class DonorLibraryA5Service: ObservableObject {
    static let shared = DonorLibraryA5Service()

    private let db = Firestore.firestore()
    private let collectionName = "rhythm_templates"

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    // MARK: - Run Rhythm Template Extraction

    func runRhythmExtraction(videos: [YouTubeVideo], limit: Int? = nil) async {
        let eligible = videos.filter { video in
            video.donorLibraryStatus?.a4Complete == true &&
            video.donorLibraryStatus?.a5Complete != true
        }

        let toProcess = limit.map { Array(eligible.prefix($0)) } ?? eligible
        guard !toProcess.isEmpty else {
            progress = "No eligible videos"
            return
        }

        isRunning = true
        completedVideos = 0
        totalVideos = toProcess.count
        progress = "Extracting 0/\(totalVideos) videos"
        perVideoProgress = [:]

        for video in toProcess {
            perVideoProgress[video.videoId] = "Loading sentences..."

            do {
                let sentences = try await DonorLibraryA2Service.shared.loadSentences(forVideoId: video.videoId)

                perVideoProgress[video.videoId] = "Extracting templates..."
                let templates = extractRhythmTemplates(sentences: sentences, videoId: video.videoId, channelId: video.channelId)

                perVideoProgress[video.videoId] = "Saving \(templates.count) templates..."
                try await saveTemplates(templates)
                try await markA5Complete(videoId: video.videoId)

                completedVideos += 1
                progress = "Extracting \(completedVideos)/\(totalVideos) videos"
                perVideoProgress[video.videoId] = "\(templates.count) templates"
            } catch {
                perVideoProgress[video.videoId] = "Error: \(error.localizedDescription)"
            }
        }

        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - Rhythm Template Extraction

    private func extractRhythmTemplates(sentences: [CreatorSentence], videoId: String, channelId: String) -> [RhythmTemplate] {
        // Group by move type
        let byMove = Dictionary(grouping: sentences) { $0.moveType }
        var templates: [RhythmTemplate] = []

        for (moveType, moveSentences) in byMove {
            // Group by section to determine position within section
            let bySection = Dictionary(grouping: moveSentences) { $0.sectionIndex }

            for position in ["opening", "mid", "closing"] {
                let positionSentences = collectPositionSentences(bySection: bySection, position: position)
                guard !positionSentences.isEmpty else { continue }

                // Word count range
                let wordCounts = positionSentences.map { $0.wordCount }
                let wordMin = wordCounts.min() ?? 5
                let wordMax = wordCounts.max() ?? 30

                // Clause count range
                let clauseCounts = positionSentences.map { $0.clauseCount }
                let clauseMin = clauseCounts.min() ?? 1
                let clauseMax = clauseCounts.max() ?? 3

                // Sentence type (most common)
                let sentenceType: String
                let questionCount = positionSentences.filter { $0.isQuestion }.count
                let fragmentCount = positionSentences.filter { $0.isFragment }.count
                let statementCount = positionSentences.count - questionCount - fragmentCount

                if questionCount > statementCount && questionCount > fragmentCount {
                    sentenceType = "question"
                } else if fragmentCount > statementCount {
                    sentenceType = "fragment"
                } else {
                    sentenceType = "statement"
                }

                // Common openers (top 3)
                let openers = positionSentences.map { $0.openingPattern }.filter { !$0.isEmpty }
                let topOpeners = topN(openers, n: 3)

                // Most common slot signature
                let sigs = positionSentences.map { $0.slotSignature }
                let typicalSig = topN(sigs, n: 1).first ?? ""

                templates.append(RhythmTemplate(
                    id: UUID().uuidString,
                    videoId: videoId,
                    channelId: channelId,
                    moveType: moveType,
                    positionInSection: position,
                    wordCountMin: wordMin,
                    wordCountMax: wordMax,
                    clauseCountMin: clauseMin,
                    clauseCountMax: clauseMax,
                    sentenceType: sentenceType,
                    commonOpeners: topOpeners,
                    typicalSlotSignature: typicalSig,
                    createdAt: Date()
                ))
            }
        }

        return templates
    }

    /// Collect sentences at a given position (opening/mid/closing) across all sections.
    private func collectPositionSentences(
        bySection: [Int: [CreatorSentence]],
        position: String
    ) -> [CreatorSentence] {
        var result: [CreatorSentence] = []

        for (_, sectionSentences) in bySection {
            let sorted = sectionSentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard !sorted.isEmpty else { continue }

            switch position {
            case "opening":
                // First sentence (or first 2 if section has 5+)
                let count = sorted.count >= 5 ? 2 : 1
                result.append(contentsOf: sorted.prefix(count))
            case "closing":
                // Last sentence (or last 2 if section has 5+)
                let count = sorted.count >= 5 ? 2 : 1
                result.append(contentsOf: sorted.suffix(count))
            case "mid":
                // Everything in between
                if sorted.count > 2 {
                    let startIdx = sorted.count >= 5 ? 2 : 1
                    let endIdx = sorted.count >= 5 ? sorted.count - 2 : sorted.count - 1
                    if startIdx < endIdx {
                        result.append(contentsOf: sorted[startIdx..<endIdx])
                    }
                }
            default:
                break
            }
        }

        return result
    }

    private func topN(_ items: [String], n: Int) -> [String] {
        let counts = items.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(n).map { $0.key }
    }

    // MARK: - Firebase Save

    private func saveTemplates(_ templates: [RhythmTemplate]) async throws {
        let batch = db.batch()
        for template in templates {
            let docRef = db.collection(collectionName).document(template.id)
            try batch.setData(from: template, forDocument: docRef)
        }
        try await batch.commit()
    }

    private func markA5Complete(videoId: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)
        try await docRef.setData([
            "donorLibraryStatus": [
                "a5Complete": true,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Query

    func loadTemplates(forVideoId videoId: String) async throws -> [RhythmTemplate] {
        let snapshot = try await db.collection(collectionName)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RhythmTemplate.self) }
    }

    func loadTemplates(forChannelId channelId: String) async throws -> [RhythmTemplate] {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RhythmTemplate.self) }
    }
}
