import Foundation
import FirebaseFirestore

/// Firebase persistence for digression detection results
/// Uses its own collection, isolated from other data
class DigressionFirebaseService {

    static let shared = DigressionFirebaseService()

    private let db = Firestore.firestore()
    private let collectionName = "digressionDetectionResults"

    private init() {}

    // MARK: - Save

    func saveResult(_ result: DigressionDetectionResult) async throws {
        let docRef = db.collection(collectionName).document(result.id.uuidString)
        let data = try Firestore.Encoder().encode(result)
        try await docRef.setData(data)
        print("Saved digression detection result: \(result.id)")
    }

    // MARK: - Load

    func getResults(forVideoId videoId: String) async throws -> [DigressionDetectionResult] {
        let snapshot = try await db.collection(collectionName)
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: DigressionDetectionResult.self)
        }
    }

    func getLatestResult(forVideoId videoId: String) async throws -> DigressionDetectionResult? {
        let results = try await getResults(forVideoId: videoId)
        return results.first
    }

    // MARK: - Delete

    func deleteResult(id: UUID) async throws {
        try await db.collection(collectionName).document(id.uuidString).delete()
        print("Deleted digression detection result: \(id)")
    }

    func deleteAllResults(forVideoId videoId: String) async throws {
        let results = try await getResults(forVideoId: videoId)
        for result in results {
            try await deleteResult(id: result.id)
        }
        print("Deleted \(results.count) digression results for video: \(videoId)")
    }

    /// Delete ALL digression detection results across all videos
    func deleteAllResults() async throws -> Int {
        let snapshot = try await db.collection(collectionName).getDocuments()
        let docs = snapshot.documents
        guard !docs.isEmpty else {
            print("No digression detection results to delete")
            return 0
        }

        for chunk in stride(from: 0, to: docs.count, by: 500) {
            let batch = db.batch()
            let end = min(chunk + 500, docs.count)
            for i in chunk..<end {
                batch.deleteDocument(docs[i].reference)
            }
            try await batch.commit()
        }

        print("Deleted \(docs.count) digression detection results")
        return docs.count
    }
}
