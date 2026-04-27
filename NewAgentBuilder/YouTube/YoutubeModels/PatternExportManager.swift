//
//  PatternExportManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//


import Foundation
import FirebaseFirestore

class PatternExportManager: ObservableObject {
    private let db = Firestore.firestore()
    private let collection = "exported_patterns"
    
    @Published var exportedPatterns: [ExportedPattern] = []
    @Published var isLoading = false
    
    // MARK: - Fetch All Exported Patterns
    
    func fetchAllPatterns() async throws {
        isLoading = true
        
        let snapshot = try await db.collection(collection)
            .order(by: "exportedDate", descending: true)
            .getDocuments()
        
        exportedPatterns = try snapshot.documents.compactMap { doc in
            try doc.data(as: ExportedPattern.self)
        }
        
        isLoading = false
    }
    
    // MARK: - Check if Pattern Already Exported
    
    func isPatternExported(originalPatternId: UUID) async throws -> Bool {
        let snapshot = try await db.collection(collection)
            .whereField("originalPatternId", isEqualTo: originalPatternId.uuidString)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    // MARK: - Get Exported Status for Multiple Patterns
    
    func getExportedStatus(for patternIds: [UUID]) async throws -> Set<UUID> {
        guard !patternIds.isEmpty else { return Set() }
        
        let idStrings = patternIds.map { $0.uuidString }
        
        let snapshot = try await db.collection(collection)
            .whereField("originalPatternId", in: idStrings)
            .getDocuments()
        
        let exportedIds = snapshot.documents.compactMap { doc -> UUID? in
            guard let idString = doc.data()["originalPatternId"] as? String else { return nil }
            return UUID(uuidString: idString)
        }
        
        return Set(exportedIds)
    }
    
    // MARK: - Export Pattern
    
    func exportPattern(_ pattern: ExportedPattern) async throws {
        let docRef = db.collection(collection).document(pattern.id.uuidString)
        try docRef.setData(from: pattern)
        print("✅ Exported pattern: \(pattern.patternType.rawValue)")
    }
    
    // MARK: - Export Multiple Patterns
    
    func exportPatterns(_ patterns: [ExportedPattern]) async throws {
        let batch = db.batch()
        
        for pattern in patterns {
            let docRef = db.collection(collection).document(pattern.id.uuidString)
            try batch.setData(from: pattern, forDocument: docRef)
        }
        
        try await batch.commit()
        print("✅ Exported \(patterns.count) patterns")
    }
    
    // MARK: - Delete Exported Pattern
    
    func deletePattern(id: UUID) async throws {
        try await db.collection(collection).document(id.uuidString).delete()
        print("✅ Deleted exported pattern")
    }
    
    // MARK: - Filter Patterns by Creator
    
    func fetchPatternsByCreator(creatorId: String) async throws -> [ExportedPattern] {
        let snapshot = try await db.collection(collection)
            .whereField("creatorId", isEqualTo: creatorId)
            .order(by: "exportedDate", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: ExportedPattern.self)
        }
    }
    
    // MARK: - Filter Patterns by Pattern Type
    
    func fetchPatternsByType(type: PatternType) async throws -> [ExportedPattern] {
        let snapshot = try await db.collection(collection)
            .whereField("patternType", isEqualTo: type.rawValue)
            .order(by: "exportedDate", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: ExportedPattern.self)
        }
    }
}