//
//  DonorLibraryA4Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation
import FirebaseFirestore

// MARK: - A4: Bigram + Profile Computation Service

/// Computes slot bigram transition tables and section profiles from annotated sentences.
/// Pure computation — no LLM calls.
@MainActor
class DonorLibraryA4Service: ObservableObject {
    static let shared = DonorLibraryA4Service()

    private let db = Firestore.firestore()
    private let bigramCollection = "slot_bigrams"
    private let profileCollection = "section_profiles"

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    // MARK: - Run Bigram + Profile Computation

    func runBigramComputation(videos: [YouTubeVideo], limit: Int? = nil) async {
        let eligible = videos.filter { video in
            video.donorLibraryStatus?.a3Complete == true &&
            video.donorLibraryStatus?.a4Complete != true
        }

        let toProcess = limit.map { Array(eligible.prefix($0)) } ?? eligible
        guard !toProcess.isEmpty else {
            progress = "No eligible videos"
            return
        }

        isRunning = true
        completedVideos = 0
        totalVideos = toProcess.count
        progress = "Computing 0/\(totalVideos) videos"
        perVideoProgress = [:]

        for video in toProcess {
            perVideoProgress[video.videoId] = "Loading sentences..."

            do {
                let sentences = try await DonorLibraryA2Service.shared.loadSentences(forVideoId: video.videoId)

                // Compute bigrams
                perVideoProgress[video.videoId] = "Computing bigrams..."
                let bigrams = computeBigrams(sentences: sentences, videoId: video.videoId, channelId: video.channelId)

                // Compute section profiles
                perVideoProgress[video.videoId] = "Computing profiles..."
                let profiles = computeSectionProfiles(sentences: sentences, videoId: video.videoId, channelId: video.channelId)

                // Save to Firebase
                perVideoProgress[video.videoId] = "Saving..."
                try await saveBigrams(bigrams)
                try await saveProfiles(profiles)
                try await markA4Complete(videoId: video.videoId)

                completedVideos += 1
                progress = "Computing \(completedVideos)/\(totalVideos) videos"
                perVideoProgress[video.videoId] = "\(bigrams.count) bigrams, \(profiles.count) profiles"
            } catch {
                perVideoProgress[video.videoId] = "Error: \(error.localizedDescription)"
            }
        }

        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - Bigram Computation

    private func computeBigrams(sentences: [CreatorSentence], videoId: String, channelId: String) -> [SlotBigram] {
        // Group sentences by section, then sort by sentence index
        let bySection = Dictionary(grouping: sentences) { $0.sectionIndex }

        // Count transitions: (fromSig, toSig, fromMove, toMove) → count
        var transitionCounts: [String: (from: String, to: String, fromMove: String, toMove: String, count: Int)] = [:]

        for (_, sectionSentences) in bySection {
            let sorted = sectionSentences.sorted { $0.sentenceIndex < $1.sentenceIndex }

            for i in 0..<(sorted.count - 1) {
                let current = sorted[i]
                let next = sorted[i + 1]
                let key = "\(current.slotSignature)→\(next.slotSignature)|\(current.moveType)→\(next.moveType)"

                if var existing = transitionCounts[key] {
                    existing.count += 1
                    transitionCounts[key] = (existing.from, existing.to, existing.fromMove, existing.toMove, existing.count)
                } else {
                    transitionCounts[key] = (current.slotSignature, next.slotSignature, current.moveType, next.moveType, 1)
                }
            }
        }

        // Also count cross-section transitions (last sentence of one section → first of next)
        let sectionIndices = bySection.keys.sorted()
        for i in 0..<(sectionIndices.count - 1) {
            guard let currentSection = bySection[sectionIndices[i]],
                  let nextSection = bySection[sectionIndices[i + 1]] else { continue }

            let lastOfCurrent = currentSection.sorted { $0.sentenceIndex < $1.sentenceIndex }.last
            let firstOfNext = nextSection.sorted { $0.sentenceIndex < $1.sentenceIndex }.first

            if let last = lastOfCurrent, let first = firstOfNext {
                let key = "\(last.slotSignature)→\(first.slotSignature)|\(last.moveType)→\(first.moveType)"
                if var existing = transitionCounts[key] {
                    existing.count += 1
                    transitionCounts[key] = (existing.from, existing.to, existing.fromMove, existing.toMove, existing.count)
                } else {
                    transitionCounts[key] = (last.slotSignature, first.slotSignature, last.moveType, first.moveType, 1)
                }
            }
        }

        // Compute probabilities: for each fromSig, total all outgoing transitions
        let fromSigTotals = transitionCounts.values.reduce(into: [String: Int]()) { result, entry in
            result[entry.from, default: 0] += entry.count
        }

        return transitionCounts.map { (_, entry) in
            let total = fromSigTotals[entry.from] ?? 1
            let probability = Double(entry.count) / Double(total)

            return SlotBigram(
                id: UUID().uuidString,
                videoId: videoId,
                channelId: channelId,
                fromSignature: entry.from,
                toSignature: entry.to,
                fromMove: entry.fromMove,
                toMove: entry.toMove,
                count: entry.count,
                probability: probability,
                crossSection: entry.fromMove != entry.toMove,
                createdAt: Date()
            )
        }
    }

    // MARK: - Section Profile Computation

    private func computeSectionProfiles(sentences: [CreatorSentence], videoId: String, channelId: String) -> [SectionProfile] {
        // Group by move type
        let byMove = Dictionary(grouping: sentences) { $0.moveType }
        var profiles: [SectionProfile] = []

        for (moveType, moveSentences) in byMove {
            // Group by section index to get sentence counts per section of this move type
            let bySectionIdx = Dictionary(grouping: moveSentences) { $0.sectionIndex }
            let sectionCounts = bySectionIdx.map { $0.value.count }

            guard !sectionCounts.isEmpty else { continue }

            let sorted = sectionCounts.sorted()
            let median: Double
            if sorted.count % 2 == 0 {
                median = Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
            } else {
                median = Double(sorted[sorted.count / 2])
            }

            // Common opening signatures (from first sentence in each section)
            let openingSigs = bySectionIdx.compactMap { (_, sents) -> String? in
                sents.sorted { $0.sentenceIndex < $1.sentenceIndex }.first?.slotSignature
            }
            let topOpening = topN(openingSigs, n: 3)

            // Common closing signatures (from last sentence in each section)
            let closingSigs = bySectionIdx.compactMap { (_, sents) -> String? in
                sents.sorted { $0.sentenceIndex < $1.sentenceIndex }.last?.slotSignature
            }
            let topClosing = topN(closingSigs, n: 3)

            profiles.append(SectionProfile(
                id: UUID().uuidString,
                videoId: videoId,
                channelId: channelId,
                moveType: moveType,
                minSentences: sorted.first ?? 0,
                maxSentences: sorted.last ?? 0,
                medianSentences: median,
                commonOpeningSignatures: topOpening,
                commonClosingSignatures: topClosing,
                totalSections: bySectionIdx.count,
                createdAt: Date()
            ))
        }

        return profiles
    }

    /// Return top N most frequent strings
    private func topN(_ items: [String], n: Int) -> [String] {
        let counts = items.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(n).map { $0.key }
    }

    // MARK: - Firebase Save

    private func saveBigrams(_ bigrams: [SlotBigram]) async throws {
        let batchSize = 400
        for startIdx in stride(from: 0, to: bigrams.count, by: batchSize) {
            let endIdx = min(startIdx + batchSize, bigrams.count)
            let batch = db.batch()

            for bigram in bigrams[startIdx..<endIdx] {
                let docRef = db.collection(bigramCollection).document(bigram.id)
                try batch.setData(from: bigram, forDocument: docRef)
            }

            try await batch.commit()
        }
    }

    private func saveProfiles(_ profiles: [SectionProfile]) async throws {
        let batch = db.batch()
        for profile in profiles {
            let docRef = db.collection(profileCollection).document(profile.id)
            try batch.setData(from: profile, forDocument: docRef)
        }
        try await batch.commit()
    }

    private func markA4Complete(videoId: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)
        try await docRef.setData([
            "donorLibraryStatus": [
                "a4Complete": true,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Query

    func loadBigrams(forVideoId videoId: String) async throws -> [SlotBigram] {
        let snapshot = try await db.collection(bigramCollection)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SlotBigram.self) }
    }

    func loadBigrams(forChannelId channelId: String) async throws -> [SlotBigram] {
        let snapshot = try await db.collection(bigramCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SlotBigram.self) }
    }

    func loadProfiles(forVideoId videoId: String) async throws -> [SectionProfile] {
        let snapshot = try await db.collection(profileCollection)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SectionProfile.self) }
    }

    func loadProfiles(forChannelId channelId: String) async throws -> [SectionProfile] {
        let snapshot = try await db.collection(profileCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SectionProfile.self) }
    }
}
