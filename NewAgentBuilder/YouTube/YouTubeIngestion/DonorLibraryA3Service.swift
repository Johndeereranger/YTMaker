//
//  DonorLibraryA3Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation
import FirebaseFirestore

// MARK: - A3: Embedding Generation Service

/// Generates embeddings for CreatorSentence records using OpenAI text-embedding-3-small.
@MainActor
class DonorLibraryA3Service: ObservableObject {
    static let shared = DonorLibraryA3Service()

    private let db = Firestore.firestore()
    private let collectionName = "creator_sentences"
    private let embeddingModel = "text-embedding-3-small"
    private let apiKey = GPT4ModelAdapter().apiKey
    private let batchSize = 100  // OpenAI batch limit

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    // MARK: - Run Embedding Generation

    /// Run A3 embedding generation on videos that have A2 complete but not A3.
    func runEmbeddingGeneration(videos: [YouTubeVideo], limit: Int? = nil) async {
        let eligible = videos.filter { video in
            video.donorLibraryStatus?.a2Complete == true &&
            video.donorLibraryStatus?.a3Complete != true
        }

        let toProcess = limit.map { Array(eligible.prefix($0)) } ?? eligible
        guard !toProcess.isEmpty else {
            progress = "No eligible videos"
            return
        }

        isRunning = true
        completedVideos = 0
        totalVideos = toProcess.count
        progress = "Embedding 0/\(totalVideos) videos"
        perVideoProgress = [:]

        for video in toProcess {
            perVideoProgress[video.videoId] = "Loading sentences..."

            do {
                let sentences = try await DonorLibraryA2Service.shared.loadSentences(forVideoId: video.videoId)
                let needsEmbedding = sentences.filter { $0.embedding == nil }

                if needsEmbedding.isEmpty {
                    // All already have embeddings
                    try await markA3Complete(videoId: video.videoId)
                    completedVideos += 1
                    perVideoProgress[video.videoId] = "Already done"
                    continue
                }

                perVideoProgress[video.videoId] = "Embedding \(needsEmbedding.count) sentences..."

                // Batch embed
                let texts = needsEmbedding.map { $0.rawText }
                var allEmbeddings: [[Float]] = []

                for startIdx in stride(from: 0, to: texts.count, by: batchSize) {
                    let endIdx = min(startIdx + batchSize, texts.count)
                    let batchTexts = Array(texts[startIdx..<endIdx])

                    let embeddings = try await callEmbeddingAPI(texts: batchTexts)
                    allEmbeddings.append(contentsOf: embeddings)

                    perVideoProgress[video.videoId] = "Embedded \(allEmbeddings.count)/\(texts.count)"
                }

                // Update Firebase docs with embeddings
                try await updateEmbeddings(sentences: needsEmbedding, embeddings: allEmbeddings)
                try await markA3Complete(videoId: video.videoId)

                completedVideos += 1
                progress = "Embedding \(completedVideos)/\(totalVideos) videos"
                perVideoProgress[video.videoId] = "\(allEmbeddings.count) embedded"
            } catch {
                perVideoProgress[video.videoId] = "Error: \(error.localizedDescription)"
            }
        }

        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - OpenAI Embedding API Call

    private func callEmbeddingAPI(texts: [String]) async throws -> [[Float]] {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input": texts,
            "model": embeddingModel
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw DonorLibraryError.llmError("Embedding API returned \(statusCode): \(bodyStr)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw DonorLibraryError.llmError("Invalid embedding response format")
        }

        // Sort by index to maintain order
        let sorted = dataArray.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }

        return sorted.compactMap { item -> [Float]? in
            guard let embedding = item["embedding"] as? [Double] else { return nil }
            return embedding.map { Float($0) }
        }
    }

    // MARK: - Firebase Update

    private func updateEmbeddings(sentences: [CreatorSentence], embeddings: [[Float]]) async throws {
        guard sentences.count == embeddings.count else {
            throw DonorLibraryError.llmError("Embedding count mismatch: \(sentences.count) sentences vs \(embeddings.count) embeddings")
        }

        // Batch update (max 500 per batch)
        let batchLimit = 400
        for startIdx in stride(from: 0, to: sentences.count, by: batchLimit) {
            let endIdx = min(startIdx + batchLimit, sentences.count)
            let batch = db.batch()

            for i in startIdx..<endIdx {
                let docRef = db.collection(collectionName).document(sentences[i].id)
                // Store embedding as array of doubles (Firestore doesn't have Float)
                let embeddingDoubles = embeddings[i].map { Double($0) }
                batch.updateData(["embedding": embeddingDoubles], forDocument: docRef)
            }

            try await batch.commit()
        }
    }

    private func markA3Complete(videoId: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)
        try await docRef.setData([
            "donorLibraryStatus": [
                "a3Complete": true,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }
}
