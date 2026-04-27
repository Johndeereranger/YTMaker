//
//  ScriptManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import Foundation
import Firebase

// MARK: - ScriptManager
class ScriptManager {
    static let instance = ScriptManager()
    private let db = Firestore.firestore().collection("scripts")

    private init() {}

    func fetchScripts() async throws -> [Script] {
        let snapshot = try await db.getDocuments()
        return snapshot.documents.compactMap { Script(document: $0) }
    }

    func fetchScript(with id: UUID) async throws -> Script? {
        let doc = try await db.document(id.uuidString).getDocument()
        return Script(document: doc)
    }

    func saveScript(_ script: Script) async throws {
        try await db.document(script.id.uuidString).setData(script.toFirestoreData())
    }

    func deleteScript(with id: UUID) async throws {
        try await db.document(id.uuidString).delete()
    }
}

// MARK: - SoundBeatManager
class SoundBeatManager {
    static let instance = SoundBeatManager()
    private let db = Firestore.firestore().collection("soundBeats")

    private init() {}

    func fetchSoundBeats(for scriptId: UUID) async throws -> [SoundBeat] {
        let snapshot = try await db.whereField("scriptId", isEqualTo: scriptId.uuidString).getDocuments()
        return snapshot.documents.compactMap { SoundBeat(document: $0) }
    }

    func fetchSoundBeat(with id: UUID) async throws -> SoundBeat? {
        let doc = try await db.document(id.uuidString).getDocument()
        return SoundBeat(document: doc)
    }

    func saveSoundBeat(_ beat: SoundBeat) async throws {
        try await db.document(beat.id.uuidString).setData(beat.toFirestoreData())
    }

    func deleteSoundBeat(with id: UUID) async throws {
        try await db.document(id.uuidString).delete()
    }
    
    func saveSoundBeats(_ beats: [SoundBeat], forScript script: Script) async throws {
        let batch = Firestore.firestore().batch()
        for beat in beats {
            let ref = db.document(beat.id.uuidString)
            batch.setData(beat.toFirestoreData(), forDocument: ref)
        }
        try await batch.commit()
    }
    
    func updateSelectedPrompt(for beat: SoundBeat) async throws {
        try await db.document(beat.id.uuidString).setData(beat.toFirestoreData(), merge: true)
    }
    
//    func updateSystemMatches(for beatMatches: [UUID: [SystemMatch]]) async throws {
//        let batch = Firestore.firestore().batch()
//        
//        for (beatId, matches) in beatMatches {
//            let ref = db.document(beatId.uuidString)
//            let updateData: [String: Any] = [
//                "systemMatches": matches.map { match in
//                    [
//                        "promptId": match.promptId,
//                        "strength": match.strength.rawValue,
//                        "rank": match.rank
//                    ]
//                }
//            ]
//            // Change this line:
//            batch.setData(updateData, forDocument: ref, merge: true)  // Instead of updateData
//        }
//        
//        try await batch.commit()
//    }
    // Add this method to SoundBeatManager
    func updateSystemMatches(for beatId: UUID, matches: [SystemMatch]) async throws {
        let updateData: [String: Any] = [
            "systemMatches": matches.map { match in
                [
                    "promptId": match.promptId,
                    "strength": match.strength.rawValue,
                    "rank": match.rank
                ]
            }
        ]
        try await db.document(beatId.uuidString).setData(updateData, merge: true)
    }
}
