//
//  YouTubeInsightManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/10/26.
//


import Foundation
import FirebaseFirestore

@MainActor
class YouTubeInsightManager: ObservableObject {
    @Published var insights: [YouTubeInsight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let collectionName = "youtubeInsights"
    
    // MARK: - CREATE
    func createInsight(_ insight: YouTubeInsight) async throws {
        let docRef = db.collection(collectionName).document(insight.id)
        try docRef.setData(from: insight)
        print("✅ Created insight: \(insight.videoTitle) @ \(insight.timestamp)")
        
        // Add to local array
        insights.append(insight)
    }
    
    // MARK: - READ (All)
    func fetchAllInsights() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(collectionName)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        insights = snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeInsight.self)
        }
        
        print("✅ Fetched \(insights.count) YouTube insights")
    }
    
    // MARK: - READ (Single)
    func fetchInsight(id: String) async throws -> YouTubeInsight? {
        let docRef = db.collection(collectionName).document(id)
        let document = try await docRef.getDocument()
        return try? document.data(as: YouTubeInsight.self)
    }
    
    // MARK: - READ (By Channel)
    func fetchInsights(forChannel channelName: String) async throws -> [YouTubeInsight] {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelName", isEqualTo: channelName)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeInsight.self)
        }
    }
    
    // MARK: - READ (By Type)
    func fetchInsights(ofType type: YouTubeInsight.InsightType) async throws -> [YouTubeInsight] {
        let snapshot = try await db.collection(collectionName)
            .whereField("insightType", isEqualTo: type.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeInsight.self)
        }
    }
    
    // MARK: - UPDATE
    func updateInsight(_ insight: YouTubeInsight) async throws {
        let docRef = db.collection(collectionName).document(insight.id)
        try docRef.setData(from: insight, merge: true)
        print("✅ Updated insight: \(insight.videoTitle)")
        
        // Update local array
        if let index = insights.firstIndex(where: { $0.id == insight.id }) {
            insights[index] = insight
        }
    }
    
    // MARK: - DELETE
    func deleteInsight(id: String) async throws {
        try await db.collection(collectionName).document(id).delete()
        print("✅ Deleted insight: \(id)")
        
        // Remove from local array
        insights.removeAll { $0.id == id }
    }
    
    // MARK: - Refresh
    func refresh() async {
        do {
            try await fetchAllInsights()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error refreshing insights: \(error)")
        }
    }
}