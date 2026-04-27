//
//  YTSCRIPTManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/5/25.
//


import Foundation
import FirebaseFirestore

class YTSCRIPTManager {
    static let shared = YTSCRIPTManager()
    private let db = Firestore.firestore()
    private let collection = "ytscripts"
    
    private init() {}
    
    // MARK: - Create
    func createScript(_ script: YTSCRIPT) async throws {
        let docRef = db.collection(collection).document(script.id.uuidString)
        let data = scriptToFirebase(script)
        try await docRef.setData(data)
        print("✅ Created script: \(script.title)")
    }
    
    // MARK: - Read
    func fetchAllScripts() async throws -> [YTSCRIPT] {
        let snapshot = try await db.collection(collection)
            .order(by: "lastModified", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> YTSCRIPT? in
            return firebaseToScript(doc.data(), id: doc.documentID)
        }
    }
    
    func fetchScript(id: UUID) async throws -> YTSCRIPT? {
        let docRef = db.collection(collection).document(id.uuidString)
        let snapshot = try await docRef.getDocument()
        
        guard let data = snapshot.data() else { return nil }
        return firebaseToScript(data, id: snapshot.documentID)
    }
    
    // MARK: - Update (Auto-save)
    func updateScript(_ script: YTSCRIPT) async throws {
        let docRef = db.collection(collection).document(script.id.uuidString)
        let data = scriptToFirebase(script)
        try await docRef.setData(data, merge: true)
        print("💾 Auto-saved: \(script.title)")
    }
    
    // MARK: - Delete
    func deleteScript(id: UUID) async throws {
        let docRef = db.collection(collection).document(id.uuidString)
        try await docRef.delete()
        print("🗑️ Deleted script: \(id)")
    }
    
    // MARK: - Conversion Helpers
    
    // MARK: - REPLACE scriptToFirebase() with this complete version

    private func scriptToFirebase(_ script: YTSCRIPT) -> [String: Any] {
        var data: [String: Any] = [
            "id": script.id.uuidString,
            "title": script.title,
            "writingStyle": script.writingStyle.rawValue,
            "createdAt": Timestamp(date: script.createdAt),
            "lastModified": Timestamp(date: script.lastModified),
            "status": script.status,
            "targetMinutes": script.targetMinutes,
            "wordsPerMinute": script.wordsPerMinute,
            "objective": script.objective,
            "targetEmotion": script.targetEmotion,
            "audienceNotes": script.audienceNotes,
            "brainDumpRaw": script.brainDumpRaw
        ]

        // Source topic link (for scripts created from ResearchTopic)
        if let sourceTopicId = script.sourceTopicId {
            data["sourceTopicId"] = sourceTopicId
        }
        
        // Points
        data["points"] = script.points.map { point in
            [
                "id": point.id.uuidString,
                "text": point.text,
                "tag": point.tag,
                "shockScore": point.shockScore,
                "isKeeper": point.isKeeper
            ]
        }
        
        // Research Points
        data["researchPoints"] = script.researchPoints.map { point in
            var pointData: [String: Any] = [
                "id": point.id.uuidString,
                "title": point.title,
                "rawNotes": point.rawNotes,
                "visualNotes": point.visualNotes,
                "activeVersionIndex": point.activeVersionIndex
            ]
            
            pointData["polishedVersions"] = point.polishedVersions.map { version in
                [
                    "id": version.id.uuidString,
                    "content": version.content,
                    "createdAt": Timestamp(date: version.createdAt),
                    "note": version.note,
                    "promptUsed": version.promptUsed
                ]
            }
            
            return pointData
        }
        
        // ========== NEW: ANGLE DATA ==========
        // Generated Angles
        data["generatedAngles"] = script.generatedAngles.map { angle in
            [
                "id": angle.id,
                "angle_statement": angle.angleStatement,
                "nuke_point": angle.nukePoint,
                "hook_type": angle.hookType,
                "why_it_matters": angle.whyItMatters,
                "supporting_points": angle.supportingPoints
            ]
        }
        
        // Selected Angle ID
        if let selectedAngleId = script.selectedAngleId {
            data["selectedAngleId"] = selectedAngleId
        }
        
        data["manualAngle"] = script.manualAngle
        // ========== END ANGLE DATA ==========
        
        // Outline Sections
        // Outline Sections (COMPLETE VERSION with versions and sentences)
        data["outlineSections"] = script.outlineSections.map { section in
            [
                "id": section.id.uuidString,
                "name": section.name,
                "orderIndex": section.orderIndex,
                "targetWordCount": section.targetWordCount as Any,
                "bulletPoints": section.bulletPoints,
                "rawSpokenText": section.rawSpokenText,
                "polishedText": section.polishedText,
                
                
                // NEW: Save version history with sentences and parts
                "sectionVersions": section.sectionVersions.map { version in
                    [
                        "id": version.id.uuidString,
                        "timestamp": Timestamp(date: version.timestamp ?? Date()),
                        "polishedText": version.polishedText ?? "",
                        "wordCount": version.wordCount,
                        "sentences": version.sentences.map { sentence in
                            [
                                "id": sentence.id.uuidString,
                                "text": sentence.text,
                                "orderIndex": sentence.orderIndex,
                                "part": sentence.part.rawValue  // ← SAVES THE PART!
                            ]
                        }
                    ]
                },
                "currentVersionIndex": section.currentVersionIndex,
                "appliedHacks": section.appliedHacks,
                "storyLoopContext": section.storyLoopContext,
                "storyLoopReveal": section.storyLoopReveal,
                "revealExceedsExpectations": section.revealExceedsExpectations,
                "isArchived": section.isArchived
            ]
        }
        
        // Packaging (if exists)
        if let packaging = script.packaging {
            data["packaging"] = [
                "chosenAngleTitle": packaging.chosenAngleTitle,
                "chosenHook": packaging.chosenHook,
                "notes": packaging.notes,
                "titleIdeas": packaging.titleIdeas
            ]
        }
        
//        // Outline Blocks
//        data["outlineBlocks"] = script.outlineBlocks.map { block in
//            [
//                "id": block.id.uuidString,
//                "name": block.name,
//                "orderIndex": block.orderIndex,
//                "targetSeconds": block.targetSeconds,
//                "what": block.what,
//                "why": block.why,
//                "proof": block.proof,
//                "rehook": block.rehook,
//                "visualNotes": block.visualNotes
//            ]
//        }
        
        // Sections
        data["sections"] = script.sections.map { section in
            var sectionData: [String: Any] = [
                "id": section.id.uuidString,
                "label": section.label,
                "rawSpoken": section.rawSpoken,
                "activeVersionIndex": section.activeVersionIndex
            ]
            
            if let outlineBlockID = section.outlineBlockID {
                sectionData["outlineBlockID"] = outlineBlockID.uuidString
            }
            
            sectionData["versions"] = section.versions.map { version in
                [
                    "id": version.id.uuidString,
                    "content": version.content,
                    "createdAt": Timestamp(date: version.createdAt ?? Date()),
                    "note": version.note
                ]
            }
            
            return sectionData
        }
        
        return data
    }
    

    
    // MARK: - REPLACE firebaseToScript() with this complete version

    private func firebaseToScript(_ data: [String: Any], id: String) -> YTSCRIPT? {
        guard let idString = data["id"] as? String,
              let uuid = UUID(uuidString: idString),
              let title = data["title"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let lastModifiedTimestamp = data["lastModified"] as? Timestamp
        else {
            print("❌ Failed to parse script: \(id)")
            return nil
        }
        
        let script = YTSCRIPT(
            id: uuid,
            title: title,
            createdAt: createdAtTimestamp.dateValue()
        )
        
        script.lastModified = lastModifiedTimestamp.dateValue()
        script.status = data["status"] as? String ?? "draft"
        script.targetMinutes = data["targetMinutes"] as? Double ?? 12.0
        script.wordsPerMinute = data["wordsPerMinute"] as? Double ?? 155.0
        script.objective = data["objective"] as? String ?? ""
        script.targetEmotion = data["targetEmotion"] as? String ?? "surprise"
        script.audienceNotes = data["audienceNotes"] as? String ?? ""
        script.brainDumpRaw = data["brainDumpRaw"] as? String ?? ""
        let writingStyleString = data["writingStyle"] as? String ?? "kallaway"
        script.writingStyle = WritingStyle(rawValue: writingStyleString) ?? .kallaway
        script.sourceTopicId = data["sourceTopicId"] as? String
        
        // Points
        if let pointsArray = data["points"] as? [[String: Any]] {
            script.points = pointsArray.compactMap { pointData in
                guard let idString = pointData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let text = pointData["text"] as? String else { return nil }
                
                return YTSCRIPTPoint(
                    id: id,
                    text: text,
                    tag: pointData["tag"] as? String ?? "fact",
                    shockScore: pointData["shockScore"] as? Int ?? 0,
                    isKeeper: pointData["isKeeper"] as? Bool ?? false
                )
            }
        }
        
        // Research Points
        if let researchPointsArray = data["researchPoints"] as? [[String: Any]] {
            script.researchPoints = researchPointsArray.compactMap { pointData in
                guard let idString = pointData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let title = pointData["title"] as? String else { return nil }
                
                let versions: [YTSCRIPTPointVersion]
                if let versionsArray = pointData["polishedVersions"] as? [[String: Any]] {
                    versions = versionsArray.compactMap { versionData in
                        guard let versionIDString = versionData["id"] as? String,
                              let versionID = UUID(uuidString: versionIDString),
                              let content = versionData["content"] as? String,
                              let createdAtTimestamp = versionData["createdAt"] as? Timestamp else { return nil }
                        
                        return YTSCRIPTPointVersion(
                            id: versionID,
                            content: content,
                            createdAt: createdAtTimestamp.dateValue(),
                            note: versionData["note"] as? String ?? "",
                            promptUsed: versionData["promptUsed"] as? String ?? ""
                        )
                    }
                } else {
                    versions = []
                }
                
                return YTSCRIPTResearchPoint(
                    id: id,
                    title: title,
                    rawNotes: pointData["rawNotes"] as? String ?? "",
                    visualNotes: pointData["visualNotes"] as? String ?? "",
                    polishedVersions: versions,
                    activeVersionIndex: pointData["activeVersionIndex"] as? Int ?? -1
                )
            }
        }
        
        // ========== NEW: ANGLE DATA ==========
        // Generated Angles
        if let anglesArray = data["generatedAngles"] as? [[String: Any]] {
            script.generatedAngles = anglesArray.compactMap { angleDict -> YTSCRIPTAngleOption? in
                guard let id = angleDict["id"] as? Int,
                      let statement = angleDict["angle_statement"] as? String,
                      let nukePoint = angleDict["nuke_point"] as? String,
                      let hookType = angleDict["hook_type"] as? String,
                      let whyItMatters = angleDict["why_it_matters"] as? String,
                      let supportingPoints = angleDict["supporting_points"] as? [String] else {
                    return nil
                }
                
                return YTSCRIPTAngleOption(  // Changed from YTSCRIPT.AngleOption
                        id: id,
                        angleStatement: statement,
                        nukePoint: nukePoint,
                        hookType: hookType,
                        whyItMatters: whyItMatters,
                        supportingPoints: supportingPoints
                    )
            }
        }
        
        // Selected Angle ID
        script.selectedAngleId = data["selectedAngleId"] as? Int
        script.manualAngle = data["manualAngle"] as? String ?? ""
        // ========== END ANGLE DATA ==========
        
        // Outline Sections
        // Outline Sections (COMPLETE VERSION with versions and sentences)
        // Outline Sections (COMPLETE VERSION with versions and sentences)
        if let sectionsArray = data["outlineSections"] as? [[String: Any]] {
            script.outlineSections = sectionsArray.compactMap { sectionData -> YTSCRIPTOutlineSection2? in
                guard let idString = sectionData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let name = sectionData["name"] as? String else { return nil }
                
                var section = YTSCRIPTOutlineSection2(
                    id: id,
                    name: name,
                    orderIndex: sectionData["orderIndex"] as? Int ?? 0,
                    targetWordCount: sectionData["targetWordCount"] as? Int,
                    bulletPoints: sectionData["bulletPoints"] as? [String] ?? [],
                    rawSpokenText: sectionData["rawSpokenText"] as? String ?? "",
                    polishedText: sectionData["polishedText"] as? String ?? ""
                )
                
                // NEW: Load version history with sentences and parts
                if let versionsArray = sectionData["sectionVersions"] as? [[String: Any]] {
                    section.sectionVersions = versionsArray.compactMap { versionData -> YTSCRIPTSectionVersion? in
                        guard let id = UUID(uuidString: versionData["id"] as? String ?? ""),
                              let timestamp = (versionData["timestamp"] as? Timestamp)?.dateValue(),
                              let polishedText = versionData["polishedText"] as? String,
                              let wordCount = versionData["wordCount"] as? Int else { return nil }
                        
                        let sentencesArray = versionData["sentences"] as? [[String: Any]] ?? []
                        let sentences = sentencesArray.compactMap { sentenceData -> YTSCRIPTOutlineSentence? in
                            guard let sentenceId = UUID(uuidString: sentenceData["id"] as? String ?? ""),
                                  let text = sentenceData["text"] as? String,
                                  let orderIndex = sentenceData["orderIndex"] as? Int else { return nil }
                            
                            let partString = sentenceData["part"] as? String ?? "unknown"
                            let part = KallawayPart(rawValue: partString) ?? .unknown
                            
                            return YTSCRIPTOutlineSentence(id: sentenceId, text: text, orderIndex: orderIndex, part: part)
                        }
                        
                        return YTSCRIPTSectionVersion(
                            id: id,
                            timestamp: timestamp,
                            polishedText: polishedText,
                            sentences: sentences
                        )
                    }
                }
                
                section.currentVersionIndex = sectionData["currentVersionIndex"] as? Int ?? -1
                section.appliedHacks = sectionData["appliedHacks"] as? [String] ?? []
                section.storyLoopContext = sectionData["storyLoopContext"] as? String ?? ""
                section.storyLoopReveal = sectionData["storyLoopReveal"] as? String ?? ""
                section.revealExceedsExpectations = sectionData["revealExceedsExpectations"] as? Bool ?? false
                section.isArchived = sectionData["isArchived"] as? Bool ?? false
                
                return section
            }
        }
        
        // Packaging
        if let packagingData = data["packaging"] as? [String: Any] {
            script.packaging = YTSCRIPTPackaging(
                chosenAngleTitle: packagingData["chosenAngleTitle"] as? String ?? "",
                chosenHook: packagingData["chosenHook"] as? String ?? "",
                notes: packagingData["notes"] as? String ?? "",
                titleIdeas: packagingData["titleIdeas"] as? [String] ?? []
            )
        }
        
       
        
        // Sections
        if let sectionsArray = data["sections"] as? [[String: Any]] {
            script.sections = sectionsArray.compactMap { sectionData in
                guard let idString = sectionData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let label = sectionData["label"] as? String else { return nil }
                
                let outlineBlockID: UUID?
                if let outlineIDString = sectionData["outlineBlockID"] as? String {
                    outlineBlockID = UUID(uuidString: outlineIDString)
                } else {
                    outlineBlockID = nil
                }
                
                let versions: [YTSCRIPTSectionVersion]
                if let versionsArray = sectionData["versions"] as? [[String: Any]] {
                    versions = versionsArray.compactMap { versionData in
                        guard let versionIDString = versionData["id"] as? String,
                              let versionID = UUID(uuidString: versionIDString),
                              let content = versionData["content"] as? String,
                              let createdAtTimestamp = versionData["createdAt"] as? Timestamp else { return nil }
                        
                        return YTSCRIPTSectionVersion(
                            id: versionID,
                            content: content,
                            createdAt: createdAtTimestamp.dateValue(),
                            note: versionData["note"] as? String ?? ""
                        )
                    }
                } else {
                    versions = []
                }
                
                return YTSCRIPTSection(
                    id: id,
                    outlineBlockID: outlineBlockID,
                    label: label,
                    rawSpoken: sectionData["rawSpoken"] as? String ?? "",
                    versions: versions,
                    activeVersionIndex: sectionData["activeVersionIndex"] as? Int ?? -1
                )
            }
        }
        
        return script
    }

    
//
}

