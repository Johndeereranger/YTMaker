//
//  ResearchTopic 2.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//


import Foundation
import FirebaseFirestore
//
//// MARK: - Firebase Manager
//@MainActor
//class ResearchTopicManager: ObservableObject {
//    @Published var topics: [ResearchTopic] = []
//    @Published var isLoading = false
//    @Published var errorMessage: String?
//    
//    private let db = Firestore.firestore()
//    private let collectionName = "researchTopics"
//    
//    // MARK: - CREATE
//    func createTopic(_ topic: ResearchTopic) async throws {
//        let docRef = db.collection(collectionName).document(topic.id)
//        try docRef.setData(from: topic)
//        print("✅ Created topic: \(topic.title)")
//        
//        // Add to local array
//        topics.append(topic)
//    }
//    
//    // MARK: - READ (All)
//    func fetchAllTopics() async throws {
//        isLoading = true
//        defer { isLoading = false }
//        
//        let snapshot = try await db.collection(collectionName)
//            .order(by: "createdAt", descending: true)
//            .getDocuments()
//        
//        topics = snapshot.documents.compactMap { doc in
//            try? doc.data(as: ResearchTopic.self)
//        }
//        
//        print("✅ Fetched \(topics.count) research topics")
//    }
//    
//    // MARK: - READ (Single)
//    func fetchTopic(id: String) async throws -> ResearchTopic? {
//        let docRef = db.collection(collectionName).document(id)
//        let document = try await docRef.getDocument()
//        return try? document.data(as: ResearchTopic.self)
//    }
//    
//    // MARK: - UPDATE
//    func updateTopic(_ topic: ResearchTopic) async throws {
//        let docRef = db.collection(collectionName).document(topic.id)
//        try docRef.setData(from: topic, merge: true)
//        print("✅ Updated topic: \(topic.title)")
//        
//        // Update local array
//        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
//            topics[index] = topic
//        }
//    }
//    
//    // MARK: - DELETE
//    func deleteTopic(id: String) async throws {
//        try await db.collection(collectionName).document(id).delete()
//        print("✅ Deleted topic: \(id)")
//        
//        // Remove from local array
//        topics.removeAll { $0.id == id }
//    }
//    
//    // MARK: - Helper: Add Video to Topic
//    func addVideoToTopic(topicId: String, videoId: String) async throws {
//        guard var topic = topics.first(where: { $0.id == topicId }) else {
//            throw NSError(domain: "TopicNotFound", code: 404)
//        }
//        
//        // Avoid duplicates
//        if !topic.videoIds.contains(videoId) {
//            topic.videoIds.append(videoId)
//            try await updateTopic(topic)
//        }
//    }
//    
//    // MARK: - Helper: Remove Video from Topic
//    func removeVideoFromTopic(topicId: String, videoId: String) async throws {
//        guard var topic = topics.first(where: { $0.id == topicId }) else {
//            throw NSError(domain: "TopicNotFound", code: 404)
//        }
//        
//        topic.videoIds.removeAll { $0 == videoId }
//        try await updateTopic(topic)
//    }
//    
//    // MARK: - Refresh (Manual reload)
//    func refresh() async {
//        do {
//            try await fetchAllTopics()
//        } catch {
//            errorMessage = error.localizedDescription
//            print("❌ Error refreshing topics: \(error)")
//        }
//    }
//}

// MARK: - Usage Example
/*
 // In your app initialization or view:
 
 let topicManager = ResearchTopicManager()
 
 // Create new topic
 Task {
     let newTopic = ResearchTopic(
         title: "5 Biggest Mistakes",
         description: "Research on mistake-based videos",
         topicNotes: "These videos get high engagement"
     )
     try await topicManager.createTopic(newTopic)
 }
 
 // Fetch all topics
 Task {
     try await topicManager.fetchAllTopics()
 }
 
 // Refresh topics (for pull-to-refresh or refresh button)
 Task {
     await topicManager.refresh()
 }
 
 // Add video to topic
 Task {
     try await topicManager.addVideoToTopic(
         topicId: "topic-uuid",
         videoId: "dQw4w9WgXcQ"
     )
 }
 
 // Update topic
 Task {
     var topic = topicManager.topics[0]
     topic.topicNotes = "Updated findings: Question hooks work best"
     try await topicManager.updateTopic(topic)
 }
 
 // Delete topic
 Task {
     try await topicManager.deleteTopic(id: "topic-uuid")
 }
 */


//
//// MARK: - Firebase Manager (Enhanced)
//@MainActor
//class ResearchTopicManager: ObservableObject {
//    @Published var topics: [ResearchTopic] = []
//    @Published var isLoading = false
//    @Published var errorMessage: String?
//    
//    private let db = Firestore.firestore()
//    private let collectionName = "researchTopics"
//    
//    // MARK: - CREATE
//    func createTopic(_ topic: ResearchTopic) async throws {
//        let docRef = db.collection(collectionName).document(topic.id)
//        try docRef.setData(from: topic)
//        print("✅ Created topic: \(topic.title)")
//        
//        // Add to local array
//        topics.append(topic)
//    }
//    
//    // MARK: - READ (All) - Enhanced with error logging
//    func fetchAllTopics() async throws {
//        isLoading = true
//        defer { isLoading = false }
//        
//        let snapshot = try await db.collection(collectionName)
//            .order(by: "createdAt", descending: true)
//            .getDocuments()
//        
//        print("📦 Fetched \(snapshot.documents.count) documents from Firebase")
//        
//        var successCount = 0
//        var failureCount = 0
//        
//        topics = snapshot.documents.compactMap { doc in
//            do {
//                let topic = try doc.data(as: ResearchTopic.self)
//                successCount += 1
//                return topic
//            } catch {
//                failureCount += 1
//                print("❌ Failed to decode document \(doc.documentID): \(error)")
//                return nil
//            }
//        }
//        
//        print("✅ Successfully decoded \(successCount) topics")
//        if failureCount > 0 {
//            print("⚠️ Failed to decode \(failureCount) topics")
//        }
//    }
//    
//    // MARK: - READ (Single)
//    func fetchTopic(id: String) async throws -> ResearchTopic? {
//        let docRef = db.collection(collectionName).document(id)
//        let document = try await docRef.getDocument()
//        return try? document.data(as: ResearchTopic.self)
//    }
//    
//    // MARK: - UPDATE
//    func updateTopic(_ topic: ResearchTopic) async throws {
//        let docRef = db.collection(collectionName).document(topic.id)
//        try docRef.setData(from: topic, merge: true)
//        print("✅ Updated topic: \(topic.title)")
//        
//        // Update local array
//        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
//            topics[index] = topic
//        }
//    }
//    
//    // MARK: - DELETE
//    func deleteTopic(id: String) async throws {
//        try await db.collection(collectionName).document(id).delete()
//        print("✅ Deleted topic: \(id)")
//        
//        // Remove from local array
//        topics.removeAll { $0.id == id }
//    }
//    
//    // MARK: - Helper: Add Video to Topic
//    func addVideoToTopic(topicId: String, videoId: String) async throws {
//        guard var topic = topics.first(where: { $0.id == topicId }) else {
//            throw NSError(domain: "TopicNotFound", code: 404)
//        }
//        
//        // Avoid duplicates
//        if !topic.videoIds.contains(videoId) {
//            topic.videoIds.append(videoId)
//            try await updateTopic(topic)
//        }
//    }
//    
//    // MARK: - Helper: Remove Video from Topic
//    func removeVideoFromTopic(topicId: String, videoId: String) async throws {
//        guard var topic = topics.first(where: { $0.id == topicId }) else {
//            throw NSError(domain: "TopicNotFound", code: 404)
//        }
//        
//        topic.videoIds.removeAll { $0 == videoId }
//        try await updateTopic(topic)
//    }
//    
//    // MARK: - Refresh (Manual reload)
//    func refresh() async {
//        do {
//            try await fetchAllTopics()
//        } catch {
//            errorMessage = error.localizedDescription
//            print("❌ Error refreshing topics: \(error)")
//        }
//    }
//}


// MARK: - Firebase Manager (Singleton)
@MainActor
class ResearchTopicManager: ObservableObject {
    static let shared = ResearchTopicManager()  // ✅ Singleton instance
    
    @Published var topics: [ResearchTopic] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let collectionName = "researchTopics"
    private var hasLoadedInitialData = false
    
    private init() {}  // ✅ Private init to enforce singleton
    
    // MARK: - Load Data (Call once on app launch or first use)
    func loadDataIfNeeded() async {
        guard !hasLoadedInitialData else { return }
        await loadData()
    }
    
    func loadData() async {
        do {
            try await fetchAllTopics()
            hasLoadedInitialData = true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading topics: \(error)")
        }
    }
    
    // MARK: - CREATE
    func createTopic(_ topic: ResearchTopic) async throws {
        let docRef = db.collection(collectionName).document(topic.id)
        try docRef.setData(from: topic)
        print("✅ Created topic: \(topic.title)")
        
        // Add to local array and sort
        topics.append(topic)
        topics.sort { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - READ (All) - Enhanced with error logging
    func fetchAllTopics() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(collectionName)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        print("📦 Fetched \(snapshot.documents.count) documents from Firebase")
        
        var successCount = 0
        var failureCount = 0
        
        topics = snapshot.documents.compactMap { doc in
            do {
                let topic = try doc.data(as: ResearchTopic.self)
                successCount += 1
                return topic
            } catch {
                failureCount += 1
                print("❌ Failed to decode document \(doc.documentID): \(error)")
                return nil
            }
        }
        
        print("✅ Successfully decoded \(successCount) topics")
        if failureCount > 0 {
            print("⚠️ Failed to decode \(failureCount) topics")
        }
    }
    
    // MARK: - READ (Single)
    func fetchTopic(id: String) async throws -> ResearchTopic? {
        let docRef = db.collection(collectionName).document(id)
        let document = try await docRef.getDocument()
        return try? document.data(as: ResearchTopic.self)
    }
    
    // MARK: - UPDATE
    func updateTopic(_ topic: ResearchTopic) async throws {
        let docRef = db.collection(collectionName).document(topic.id)
        try docRef.setData(from: topic, merge: true)
        print("✅ Updated topic: \(topic.title)")
        
        // Update local array
        if let index = topics.firstIndex(where: { $0.id == topic.id }) {
            topics[index] = topic
        }
    }
    
    // MARK: - DELETE
    func deleteTopic(id: String) async throws {
        try await db.collection(collectionName).document(id).delete()
        print("✅ Deleted topic: \(id)")
        
        // Remove from local array
        topics.removeAll { $0.id == id }
    }
    
    // MARK: - Helper: Add Video to Topic
    func addVideoToTopic(topicId: String, videoId: String) async throws {
        guard var topic = topics.first(where: { $0.id == topicId }) else {
            throw NSError(domain: "TopicNotFound", code: 404)
        }
        
        // Avoid duplicates
        if !topic.videoIds.contains(videoId) {
            topic.videoIds.append(videoId)
            try await updateTopic(topic)
        }
    }
    
    // MARK: - Helper: Remove Video from Topic
    func removeVideoFromTopic(topicId: String, videoId: String) async throws {
        guard var topic = topics.first(where: { $0.id == topicId }) else {
            throw NSError(domain: "TopicNotFound", code: 404)
        }
        
        topic.videoIds.removeAll { $0 == videoId }
        try await updateTopic(topic)
    }
    
    // MARK: - Refresh (Manual reload)
    func refresh() async {
        await loadData()
    }
}
