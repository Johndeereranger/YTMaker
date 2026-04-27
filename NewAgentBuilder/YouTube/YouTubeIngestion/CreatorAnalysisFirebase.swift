//
//  CreatorAnalysisFirebase.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Creator Analysis Firebase Service
class CreatorAnalysisFirebase {
    static let shared = CreatorAnalysisFirebase()
    
    private let db = Firestore.firestore()
    
    private let videoCollection = "youtube_videos"
    private let sectionsCollection = "youtube_video_sections"
    private let beatCollection = "youtube_video_beat_sections"
    
    // MARK: - Video Operations
    
    func saveVideo(video: YouTubeVideo) async throws {
        let docRef = db.collection(videoCollection).document(video.videoId)
        
        let dict: [String: Any] = [
            "videoId": video.videoId,
            "channelId": video.channelId,
            "title": video.title,
            "duration": video.duration,
            "transcript": video.transcript as Any,
            "publishedAt": video.publishedAt as Any
        ]
        
        try await docRef.setData(dict)
        print("✅ Saved video: \(video.videoId)")
    }
    
    func loadVideo(videoId: String) async throws -> YouTubeVideo? {
        let docRef = db.collection(videoCollection).document(videoId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return try parseVideo(data)
    }
    
    private func parseVideo(_ data: [String: Any]) throws -> YouTubeVideo {
        guard let videoId = data["videoId"] as? String,
              let channelId = data["channelId"] as? String,
              let title = data["title"] as? String,
              let description = data["description"] as? String,
              let publishedAtTimestamp = data["publishedAt"] as? Timestamp,
              let duration = data["duration"] as? String,
              let thumbnailUrl = data["thumbnailUrl"] as? String,
              let statsDict = data["stats"] as? [String: Any],
              let viewCount = statsDict["viewCount"] as? Int,
              let likeCount = statsDict["likeCount"] as? Int,
              let commentCount = statsDict["commentCount"] as? Int,
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video data"])
        }
        
        let stats = VideoStats(
            viewCount: viewCount,
            likeCount: likeCount,
            commentCount: commentCount
        )
        
        var video = YouTubeVideo(
            videoId: videoId,
            channelId: channelId,
            title: title,
            description: description,
            publishedAt: publishedAtTimestamp.dateValue(),
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            stats: stats,
            createdAt: createdAtTimestamp.dateValue()
        )
        
        // Optional fields
        video.transcript = data["transcript"] as? String
        video.factsText = data["factsText"] as? String
        video.summaryText = data["summaryText"] as? String
        video.notHunting = data["notHunting"] as? Bool ?? false
        video.notes = data["notes"] as? String
        video.videoType = data["videoType"] as? String
        video.hook = data["hook"] as? String
        if let hookTypeString = data["hookType"] as? String {
            video.hookType = HookType(rawValue: hookTypeString)
        }
        video.intro = data["intro"] as? String
        
        return video
    }
    // MARK: - Section Operations (from A1a)
    
    func saveSection(section: SectionData, videoId: String, channelId: String) async throws {
        let docRef = db.collection(sectionsCollection).document(section.id)

        var dict: [String: Any] = [
            "sectionId": section.id,
            "videoId": videoId,
            "channelId": channelId,
            "role": section.role,
            "goal": section.goal,
            "logicSpineStep": section.logicSpineStep,
            "beatIds": [] // Will be populated later
        ]

        // Save word boundaries (new format)
        if let startWord = section.startWordIndex {
            dict["startWordIndex"] = startWord
        }
        if let endWord = section.endWordIndex {
            dict["endWordIndex"] = endWord
        }

        // Save time range if present (legacy support)
        if let timeRange = section.timeRange {
            dict["timeRange"] = [
                "start": timeRange.start,
                "end": timeRange.end
            ]
        }

        try await docRef.setData(dict)
        print("✅ Saved section: \(section.id)")
    }

    func saveSections(sections: [SectionData], videoId: String, channelId: String) async throws {
        let batch = db.batch()

        for section in sections {
            let docRef = db.collection(sectionsCollection).document(section.id)

            var dict: [String: Any] = [
                "sectionId": section.id,
                "videoId": videoId,
                "channelId": channelId,
                "role": section.role,
                "goal": section.goal,
                "logicSpineStep": section.logicSpineStep,
                "beatIds": []
            ]

            // Save word boundaries (new format)
            if let startWord = section.startWordIndex {
                dict["startWordIndex"] = startWord
            }
            if let endWord = section.endWordIndex {
                dict["endWordIndex"] = endWord
            }

            // Save time range if present (legacy support)
            if let timeRange = section.timeRange {
                dict["timeRange"] = [
                    "start": timeRange.start,
                    "end": timeRange.end
                ]
            }

            batch.setData(dict, forDocument: docRef)
        }

        try await batch.commit()
        print("✅ Saved \(sections.count) sections")
    }
    
    func loadSection(sectionId: String) async throws -> SectionData? {
        let docRef = db.collection(sectionsCollection).document(sectionId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return try parseSection(data)
    }
    
    func loadSectionsForVideo(videoId: String) async throws -> [SectionData] {
        print("🔍 loadSectionsForVideo: \(videoId)")
        print("🔍 Collection: \(sectionsCollection)")

        do {
            // Query without ordering - we'll sort client-side to handle both old and new formats
            let snapshot = try await db.collection(sectionsCollection)
                .whereField("videoId", isEqualTo: videoId)
                .getDocuments()

            print("🔍 Found \(snapshot.documents.count) section documents")

            var sections = snapshot.documents.compactMap { doc in
                try? parseSection(doc.data())
            }

            // Sort by word index if available, otherwise by time range
            sections.sort { a, b in
                // Prefer word index ordering (new format)
                if let aStart = a.startWordIndex, let bStart = b.startWordIndex {
                    return aStart < bStart
                }
                // Fall back to time range ordering (legacy format)
                if let aTime = a.timeRange?.start, let bTime = b.timeRange?.start {
                    return aTime < bTime
                }
                // If mixed, word index sections come first
                if a.startWordIndex != nil { return true }
                if b.startWordIndex != nil { return false }
                return false
            }

            print("🔍 Parsed and sorted \(sections.count) sections")
            return sections

        } catch {
            print("❌ loadSectionsForVideo error: \(error)")
            throw error
        }
    }
    func loadSectionsByRole(role: String, channelId: String? = nil) async throws -> [SectionData] {
        var query = db.collection(sectionsCollection)
            .whereField("role", isEqualTo: role)
        
        if let channelId = channelId {
            query = query.whereField("channelId", isEqualTo: channelId)
        }
        
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? parseSection(doc.data())
        }
    }
    
    private func parseSection(_ data: [String: Any]) throws -> SectionData {
        guard let id = data["sectionId"] as? String,
              let role = data["role"] as? String,
              let goal = data["goal"] as? String,
              let logicSpineStep = data["logicSpineStep"] as? String else {
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid section data"])
        }

        // Parse optional timeRange (legacy data)
        var timeRange: TimeRange? = nil
        if let timeRangeDict = data["timeRange"] as? [String: Int],
           let start = timeRangeDict["start"],
           let end = timeRangeDict["end"] {
            timeRange = TimeRange(start: start, end: end)
        }

        // Parse optional word indexes (new format)
        let startWordIndex = data["startWordIndex"] as? Int
        let endWordIndex = data["endWordIndex"] as? Int

        return SectionData(
            id: id,
            timeRange: timeRange,
            startWordIndex: startWordIndex,
            endWordIndex: endWordIndex,
            role: role,
            goal: goal,
            logicSpineStep: logicSpineStep
        )
    }
    
    // MARK: - Beat Operations (SimpleBeat from A1b - boundaries only)
    
    func saveBeat(beat: SimpleBeat, videoId: String, channelId: String, sectionId: String) async throws {
        let docRef = db.collection("beats").document(beat.beatId)
        
        let dict: [String: Any] = [
            "beatId": beat.beatId,
            "videoId": videoId,
            "channelId": channelId,
            "sectionId": sectionId,
            "type": beat.type,
            "text": beat.text,
            "startWordIndex": beat.startWordIndex,
            "endWordIndex": beat.endWordIndex,
            "timeRange": [
                "start": beat.timeRange.start,
                "end": beat.timeRange.end
            ]
        ]
        
        try await docRef.setData(dict)
        print("✅ Saved beat: \(beat.beatId)")
    }
    
    func saveBeats(beats: [SimpleBeat], videoId: String, channelId: String, sectionId: String) async throws {
        let batch = db.batch()
        
        for beat in beats {
            let docRef = db.collection("beats").document(beat.beatId)
            
            let dict: [String: Any] = [
                "beatId": beat.beatId,
                "videoId": videoId,
                "channelId": channelId,
                "sectionId": sectionId,
                "type": beat.type,
                "text": beat.text,
                "startWordIndex": beat.startWordIndex,
                "endWordIndex": beat.endWordIndex,
                "timeRange": [
                    "start": beat.timeRange.start,
                    "end": beat.timeRange.end
                ]
            ]
            
            batch.setData(dict, forDocument: docRef)
        }
        
        try await batch.commit()
        
        // Update section with beatIds
        let sectionRef = db.collection(sectionsCollection).document(sectionId)
        try await sectionRef.updateData([
            "beatIds": beats.map { $0.beatId }
        ])
        
        print("✅ Saved \(beats.count) beats for section: \(sectionId)")
    }
    
    func loadBeat(beatId: String) async throws -> SimpleBeat? {
        let docRef = db.collection("beats").document(beatId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return try parseSimpleBeat(data)
    }
    
    func loadBeatsForSection(sectionId: String) async throws -> [SimpleBeat] {
        let snapshot = try await db.collection("beats")
            .whereField("sectionId", isEqualTo: sectionId)
            .order(by: "startWordIndex")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? parseSimpleBeat(doc.data())
        }
    }
    
    func loadBeatsByType(type: String, channelId: String? = nil) async throws -> [SimpleBeat] {
        var query = db.collection("beats")
            .whereField("type", isEqualTo: type)
        
        if let channelId = channelId {
            query = query.whereField("channelId", isEqualTo: channelId)
        }
        
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? parseSimpleBeat(doc.data())
        }
    }
    
    private func parseSimpleBeat(_ data: [String: Any]) throws -> SimpleBeat {
        guard let beatId = data["beatId"] as? String,
              let type = data["type"] as? String,
              let text = data["text"] as? String,
              let startWordIndex = data["startWordIndex"] as? Int,
              let endWordIndex = data["endWordIndex"] as? Int,
              let timeRangeDict = data["timeRange"] as? [String: Int],
              let start = timeRangeDict["start"],
              let end = timeRangeDict["end"] else {
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid beat data"])
        }

        return SimpleBeat(
            beatId: beatId,
            type: type,
            timeRange: TimeRange(start: start, end: end),
            text: text,
            startWordIndex: startWordIndex,
            endWordIndex: endWordIndex,
            stance: data["stance"] as? String ?? "",
            tempo: data["tempo"] as? String ?? "",
            formality: data["formality"] as? Int ?? 0,
            questionCount: data["questionCount"] as? Int ?? 0,
            containsAnchor: data["containsAnchor"] as? Bool ?? false,
            anchorText: data["anchorText"] as? String ?? "",
            anchorFunction: data["anchorFunction"] as? String ?? "",
            proofMode: data["proofMode"] as? String ?? "",
            moveKey: data["moveKey"] as? String ?? "",
            sectionId: data["sectionId"] as? String ?? "",
            boundaryText: data["boundaryText"] as? String,
            matchConfidence: data["matchConfidence"] as? Double
        )
    }
    
    // MARK: - BeatDoc Operations (Full A1c analysis)
    
    func saveBeatDoc(beatDoc: BeatDoc, videoId: String, channelId: String, sectionId: String) async throws {
        let docRef = db.collection(beatCollection).document(beatDoc.beatId)
        
        let encoder = Firestore.Encoder()
        var encodedData = try encoder.encode(beatDoc)
        
        // Add references
        encodedData["videoId"] = videoId
        encodedData["channelId"] = channelId
        encodedData["sectionId"] = sectionId
        
        try await docRef.setData(encodedData)
        print("✅ Saved BeatDoc: \(beatDoc.beatId)")
    }
    
    func loadBeatDoc(beatId: String) async throws -> BeatDoc? {
        let docRef = db.collection(beatCollection).document(beatId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        let decoder = Firestore.Decoder()
        return try decoder.decode(BeatDoc.self, from: data)
    }
    
    func loadBeatDocsForSection(sectionId: String) async throws -> [BeatDoc] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("sectionId", isEqualTo: sectionId)
            .order(by: "orderIndex")
            .getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    func loadBeatDocsForVideo(videoId: String) async throws -> [BeatDoc] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "globalBeatIndex")
            .getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    // MARK: - Query Operations (The Power of Flat Structure)
    
    func queryBeatDocsByQuality(qualityLevel: String, limit: Int = 100) async throws -> [BeatDoc] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("qualityLevel", isEqualTo: qualityLevel)
            .limit(to: limit)
            .getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    func queryBeatDocsByMoveKey(moveKeyPrefix: String, limit: Int = 100) async throws -> [BeatDoc] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("moveKey", isGreaterThanOrEqualTo: moveKeyPrefix)
            .whereField("moveKey", isLessThan: moveKeyPrefix + "~")
            .limit(to: limit)
            .getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    func queryBeatDocsByType(type: String, channelId: String? = nil, limit: Int = 100) async throws -> [BeatDoc] {
        var query = db.collection(beatCollection)
            .whereField("type", isEqualTo: type)
        
        if let channelId = channelId {
            query = query.whereField("channelId", isEqualTo: channelId)
        }
        
        let snapshot = try await query.limit(to: limit).getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    func queryCanonicalHooks(limit: Int = 50) async throws -> [BeatDoc] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("qualityLevel", isEqualTo: "canonical")
            .whereField("moveKey", isGreaterThanOrEqualTo: "HOOK_")
            .whereField("moveKey", isLessThan: "HOOK_~")
            .limit(to: limit)
            .getDocuments()
        
        let decoder = Firestore.Decoder()
        return snapshot.documents.compactMap { doc in
            try? decoder.decode(BeatDoc.self, from: doc.data())
        }
    }
    
    // MARK: - Bulk Channel Queries (2 queries instead of N*M)

    /// Load ALL sections for a channel in one query. Returns [videoId: [SectionData]].
    func loadAllSections(forChannel channelId: String) async throws -> [String: [SectionData]] {
        let snapshot = try await db.collection(sectionsCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        var result: [String: [SectionData]] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            guard let videoId = data["videoId"] as? String,
                  let section = try? parseSection(data) else { continue }
            result[videoId, default: []].append(section)
        }
        print("📦 Bulk loaded \(snapshot.documents.count) sections for channel (across \(result.count) videos)")
        return result
    }

    /// Load ALL beat docs for a channel in one query. Returns [sectionId: [BeatDoc]].
    func loadAllBeatDocs(forChannel channelId: String) async throws -> [String: [BeatDoc]] {
        let snapshot = try await db.collection(beatCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        let decoder = Firestore.Decoder()
        var result: [String: [BeatDoc]] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            guard let sectionId = data["sectionId"] as? String,
                  let beatDoc = try? decoder.decode(BeatDoc.self, from: data) else { continue }
            result[sectionId, default: []].append(beatDoc)
        }
        print("📦 Bulk loaded \(snapshot.documents.count) beat docs for channel (across \(result.count) sections)")
        return result
    }

    // MARK: - Logic Spine & Bridge Points (stored on video doc)
    
    func saveLogicSpine(videoId: String, logicSpine: LogicSpineData) async throws {
        let docRef = db.collection(videoCollection).document(videoId)
        
        let dict: [String: Any] = [
            "logicSpine": [
                "chain": logicSpine.chain,
                "causalLinks": logicSpine.causalLinks.map { link in
                    [
                        "from": link.from,
                        "to": link.to,
                        "connection": link.connection
                    ]
                }
            ]
        ]
        
        try await docRef.updateData(dict)
        print("✅ Saved logic spine for video: \(videoId)")
    }
    
    // MARK: - Delete Operations

    func deleteSection(sectionId: String) async throws {
        try await db.collection(sectionsCollection).document(sectionId).delete()
        print("🗑️ Deleted section: \(sectionId)")
    }

    func deleteBeatDoc(beatId: String) async throws {
        try await db.collection(beatCollection).document(beatId).delete()
        print("🗑️ Deleted beatDoc: \(beatId)")
    }

    func clearVideoAnalysis(videoId: String) async throws {
        try await db.collection(videoCollection).document(videoId).updateData([
            "logicSpine": FieldValue.delete(),
            "bridgePoints": FieldValue.delete(),
            "validationStatus": FieldValue.delete(),
            "validationIssues": FieldValue.delete()
        ])
        print("🗑️ Cleared analysis for video: \(videoId)")
    }
    
    func saveBridgePoints(videoId: String, bridgePoints: [BridgePoint]) async throws {
        let docRef = db.collection(videoCollection).document(videoId)
        
        let dict: [String: Any] = [
            "bridgePoints": bridgePoints.map { point in
                [
                    "text": point.text,
                    "belongsTo": point.belongsTo,
                    "timestamp": point.timestamp
                ]
            }
        ]
        
        try await docRef.updateData(dict)
        print("✅ Saved bridge points for video: \(videoId)")
    }
    
    // MARK: - Legacy Alignment Doc Operations (for backward compatibility)

//    func loadAllAlignmentDocs(channelId: String) async throws -> [AlignmentData] {
//        // Query sections for this channel and construct AlignmentData
//        let sections = try await db.collection(sectionsCollection)
//            .whereField("channelId", isEqualTo: channelId)
//            .getDocuments()
//        
//        // Group sections by videoId
//        var videoSections: [String: [SectionData]] = [:]
//        for doc in sections.documents {
//            if let section = try? parseSection(doc.data()),
//               let videoId = doc.data()["videoId"] as? String {
//                videoSections[videoId, default: []].append(section)
//            }
//        }
//        
//        // Build AlignmentData for each video
//        var alignments: [AlignmentData] = []
//        for (videoId, sections) in videoSections {
//            // Load video to get logic spine and bridge points
//            if let video = try? await loadVideo(videoId: videoId),
//               let videoData = try? await db.collection(videoCollection).document(videoId).getDocument().data() {
//                
//                var logicSpine = LogicSpineData(chain: [], causalLinks: [])
//                var bridgePoints: [BridgePoint] = []
//                
//                // Parse logic spine if exists
//                if let spineDict = videoData["logicSpine"] as? [String: Any] {
//                    logicSpine = parseLogicSpine(spineDict)
//                }
//                
//                // Parse bridge points if exists
//                if let pointsArray = videoData["bridgePoints"] as? [[String: Any]] {
//                    bridgePoints = parseBridgePoints(pointsArray)
//                }
//                
//                let alignment = AlignmentData(
//                    videoId: videoId,
//                    channelId: channelId,
//                    sections: sections.sorted { $0.timeRange.start < $1.timeRange.start },
//                    logicSpine: logicSpine,
//                    bridgePoints: bridgePoints
//                )
//                alignments.append(alignment)
//            }
//        }
//        
//        return alignments
//    }
    
    func loadAllAlignmentDocs(channelId: String) async throws -> [AlignmentData] {
        // Query sections for this channel and construct AlignmentData
        let sections = try await db.collection(sectionsCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()
        
        // Group sections by videoId
        var videoSections: [String: [SectionData]] = [:]
        for doc in sections.documents {
            if let section = try? parseSection(doc.data()),
               let videoId = doc.data()["videoId"] as? String {
                videoSections[videoId, default: []].append(section)
            }
        }
        
        // Build AlignmentData for each video
        var alignments: [AlignmentData] = []
        for (videoId, sections) in videoSections {
            // Load video to get logic spine and bridge points
            if let video = try? await loadVideo(videoId: videoId),
               let videoData = try? await db.collection(videoCollection).document(videoId).getDocument().data() {
                
                var logicSpine = LogicSpineData(chain: [], causalLinks: [])
                var bridgePoints: [BridgePoint] = []
                let videoSummary = videoData["videoSummary"] as? String ?? ""
                
                // Parse logic spine if exists
                if let spineDict = videoData["logicSpine"] as? [String: Any] {
                    logicSpine = parseLogicSpine(spineDict)
                }
                
                // Parse bridge points if exists
                if let pointsArray = videoData["bridgePoints"] as? [[String: Any]] {
                    bridgePoints = parseBridgePoints(pointsArray)
                }
                
                // Sort sections by word index if available, otherwise by time range
                let sortedSections = sections.sorted { a, b in
                    // Prefer word index ordering (new format)
                    if let aStart = a.startWordIndex, let bStart = b.startWordIndex {
                        return aStart < bStart
                    }
                    // Fall back to time range ordering (legacy format)
                    if let aTime = a.timeRange?.start, let bTime = b.timeRange?.start {
                        return aTime < bTime
                    }
                    // If mixed, word index sections come first
                    if a.startWordIndex != nil { return true }
                    if b.startWordIndex != nil { return false }
                    return false
                }

                let alignment = AlignmentData(
                    videoId: videoId,
                    channelId: channelId,
                    videoSummary: videoSummary,
                    sections: sortedSections,
                    logicSpine: logicSpine,
                    bridgePoints: bridgePoints
                )
                alignments.append(alignment)
            }
        }
        
        return alignments
    }

//    func loadAggregation(channelId: String) async throws -> AggregationData? {
//        let docRef = db.collection("aggregations").document(channelId)
//        let document = try await docRef.getDocument()
//        
//        guard document.exists, let data = document.data() else {
//            return nil
//        }
//        
//        let jsonData = try JSONSerialization.data(withJSONObject: data)
//        let decoder = JSONDecoder()
//        return try decoder.decode(AggregationData.self, from: jsonData)
//    }

    // MARK: - Helper parsers for legacy support

    private func parseLogicSpine(_ data: [String: Any]) -> LogicSpineData {
        let chain = data["chain"] as? [String] ?? []
        let linksArray = data["causalLinks"] as? [[String: Any]] ?? []
        let causalLinks = linksArray.compactMap { linkDict -> CausalLink? in
            guard let from = linkDict["from"] as? String,
                  let to = linkDict["to"] as? String,
                  let connection = linkDict["connection"] as? String else {
                return nil
            }
            return CausalLink(from: from, to: to, connection: connection)
        }
        
        return LogicSpineData(chain: chain, causalLinks: causalLinks)
    }

    private func parseBridgePoints(_ data: [[String: Any]]) -> [BridgePoint] {
        return data.compactMap { pointDict -> BridgePoint? in
            guard let text = pointDict["text"] as? String,
                  let belongsTo = pointDict["belongsTo"] as? [String],
                  let timestamp = pointDict["timestamp"] as? Int else {
                return nil
            }
            return BridgePoint(text: text, belongsTo: belongsTo, timestamp: timestamp)
        }
    }
    
    // MARK: - Aggregation Operations

    func saveAggregation(data: AggregationData) async throws {
        let docRef = db.collection("aggregations").document(data.channelId)
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        
        guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "Encode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode aggregation"])
        }
        
        try await docRef.setData(dict)
        print("✅ Saved aggregation for channel: \(data.channelId)")
    }

    func loadAggregation(channelId: String) async throws -> AggregationData? {
        let docRef = db.collection("aggregations").document(channelId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        return try decoder.decode(AggregationData.self, from: jsonData)
    }

    // MARK: - Snippet Operations

    func saveSnippets(snippets: [SnippetData]) async throws {
        guard !snippets.isEmpty else { return }
        
        let batch = db.batch()
        
        for snippet in snippets {
            let docRef = db.collection("snippets").document(snippet.id.uuidString)
            
            let dict: [String: Any] = [
                "videoId": snippet.videoId,
                "channelId": snippet.channelId,
                "sectionId": snippet.sectionId,
                "beatType": snippet.beatType,
                "text": snippet.text,
                "role": snippet.role,
                "intent": snippet.intent,
                "tempo": snippet.tempo,
                "stance": snippet.stance,
                "teaseDistance": snippet.teaseDistance as Any,
                "sentenceCount": snippet.sentenceCount,
                "avgSentenceLength": snippet.avgSentenceLength,
                "questionCount": snippet.questionCount,
                "dataPoints": snippet.dataPoints,
                "mechanicsDescription": snippet.mechanicsDescription,
                "rhetoricalDevices": snippet.rhetoricalDevices,
                "primaryTopic": snippet.primaryTopic,
                "secondaryTopics": snippet.secondaryTopics,
                "specificity": snippet.specificity,
                "topicDescription": snippet.topicDescription,
                "vocabularyLevel": snippet.vocabularyLevel,
                "formality": snippet.formality,
                "profanity": snippet.profanity,
                "humorStyle": snippet.humorStyle,
                "personalVoice": snippet.personalVoice,
                "qualityTier": snippet.qualityTier.rawValue,
                "qualityReasoning": snippet.qualityReasoning
            ]
            
            batch.setData(dict, forDocument: docRef)
        }
        
        try await batch.commit()
        print("✅ Saved \(snippets.count) snippets")
    }

    func loadSnippets(channelId: String, videoId: String? = nil) async throws -> [SnippetData] {
        var query: Query = db.collection("snippets")
            .whereField("channelId", isEqualTo: channelId)
        
        if let videoId = videoId {
            query = query.whereField("videoId", isEqualTo: videoId)
        }
        
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? parseSnippetData(doc.data())
        }
    }

    private func parseSnippetData(_ data: [String: Any]) throws -> SnippetData {
        guard let videoId = data["videoId"] as? String,
              let channelId = data["channelId"] as? String,
              let sectionId = data["sectionId"] as? String,
              let beatType = data["beatType"] as? String,
              let text = data["text"] as? String,
              let qualityTierString = data["qualityTier"] as? String,
              let qualityTier = QualityTier(rawValue: qualityTierString) else {
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid snippet data"])
        }
        
        return SnippetData(
            videoId: videoId,
            channelId: channelId,
            sectionId: sectionId,
            beatType: beatType,
            text: text,
            role: data["role"] as? String ?? "",
            intent: data["intent"] as? String ?? "",
            tempo: data["tempo"] as? String ?? "",
            stance: data["stance"] as? String ?? "",
            teaseDistance: data["teaseDistance"] as? Int,
            sentenceCount: data["sentenceCount"] as? Int ?? 0,
            avgSentenceLength: data["avgSentenceLength"] as? Double ?? 0,
            questionCount: data["questionCount"] as? Int ?? 0,
            dataPoints: data["dataPoints"] as? Int ?? 0,
            mechanicsDescription: data["mechanicsDescription"] as? String ?? "",
            rhetoricalDevices: data["rhetoricalDevices"] as? [String] ?? [],
            primaryTopic: data["primaryTopic"] as? String ?? "",
            secondaryTopics: data["secondaryTopics"] as? [String] ?? [],
            specificity: data["specificity"] as? String ?? "",
            topicDescription: data["topicDescription"] as? String ?? "",
            vocabularyLevel: data["vocabularyLevel"] as? Int ?? 5,
            formality: data["formality"] as? Int ?? 5,
            profanity: data["profanity"] as? Bool ?? false,
            humorStyle: data["humorStyle"] as? String ?? "none",
            personalVoice: data["personalVoice"] as? Bool ?? false,
            qualityTier: qualityTier,
            qualityReasoning: data["qualityReasoning"] as? String ?? ""
        )
    }

    // MARK: - Alignment Doc Operations (Flat Structure)

    func saveAlignmentDoc(data: AlignmentData) async throws {
        // Save sections
        try await saveSections(sections: data.sections, videoId: data.videoId, channelId: data.channelId)
        
        // Save logic spine and bridge points on video doc
        try await saveLogicSpine(videoId: data.videoId, logicSpine: data.logicSpine)
        try await saveBridgePoints(videoId: data.videoId, bridgePoints: data.bridgePoints)
        
        // Save validation metadata on video doc
        let docRef = db.collection(videoCollection).document(data.videoId)
        try await docRef.updateData([
            "validationStatus": data.validationStatus.rawValue,
            "validationIssues": data.validationIssues?.map { issue in
                [
                    "severity": issue.severity.rawValue,
                    "type": issue.type.rawValue,
                    "message": issue.message
                ]
            } ?? [],
            "extractionDate": Timestamp(date: data.extractionDate)
        ])
        
        print("✅ Saved alignment doc for video: \(data.videoId)")
    }

    func loadAlignmentDoc(videoId: String, channelId: String) async throws -> AlignmentData? {
        // Load sections
        let sections = try await loadSectionsForVideo(videoId: videoId)
        
        guard !sections.isEmpty else {
            return nil
        }
        
        // Load video doc for logic spine, bridge points, validation
        let videoDoc = try await db.collection(videoCollection).document(videoId).getDocument()
        guard let videoData = videoDoc.data() else {
            return nil
        }
        
        var logicSpine = LogicSpineData(chain: [], causalLinks: [])
        var bridgePoints: [BridgePoint] = []
        let videoSummary = videoData["videoSummary"] as? String ?? ""
        
        if let spineDict = videoData["logicSpine"] as? [String: Any] {
            logicSpine = parseLogicSpine(spineDict)
        }
        
        if let pointsArray = videoData["bridgePoints"] as? [[String: Any]] {
            bridgePoints = parseBridgePoints(pointsArray)
        }
        
        var alignment = AlignmentData(
            videoId: videoId,
            channelId: channelId,
            videoSummary: videoSummary,
            sections: sections,
            logicSpine: logicSpine,
            bridgePoints: bridgePoints
        )
        
        if let statusString = videoData["validationStatus"] as? String,
           let status = ValidationStatus(rawValue: statusString) {
            alignment.validationStatus = status
        }
        
        if let issuesArray = videoData["validationIssues"] as? [[String: Any]] {
            alignment.validationIssues = issuesArray.compactMap { issueDict -> ValidationIssue? in
                guard let severityString = issueDict["severity"] as? String,
                      let severity = ValidationIssue.Severity(rawValue: severityString),
                      let typeString = issueDict["type"] as? String,
                      let type = ValidationIssue.IssueType(rawValue: typeString),
                      let message = issueDict["message"] as? String else {
                    return nil
                }
                return ValidationIssue(severity: severity, type: type, message: message)
            }
        }
        
        if let timestamp = videoData["extractionDate"] as? Timestamp {
            alignment.extractionDate = timestamp.dateValue()
        }
        
        return alignment
    }
    
//    // In CreatorAnalysisFirebase
//    func checkAnalysisStatus(videoId: String, channelId: String) async throws -> AnalysisStatus {
//        let db = Firestore.firestore()
//        
//        // Check A1a
//        let videoDoc = try await db
//            .collection("channels").document(channelId)
//            .collection("videos").document(videoId)
//            .getDocument()
//        
//        let a1aComplete = videoDoc.data()?["logicSpine"] != nil
//        
//        // Check sections and beatDocs
//        let sectionsSnapshot = try await db
//            .collection("channels").document(channelId)
//            .collection("videos").document(videoId)
//            .collection("sections")
//            .getDocuments()
//        
//        var sectionStatuses: [SectionStatus] = []
//        
//        for (index, sectionDoc) in sectionsSnapshot.documents.enumerated() {
//            let sectionId = sectionDoc.documentID
//            let sectionData = sectionDoc.data()
//            let sectionRole = sectionData["role"] as? String ?? ""
//            
//            // Check beatDocs for this section
//            let beatDocsSnapshot = try await db
//                .collection("channels").document(channelId)
//                .collection("videos").document(videoId)
//                .collection("sections").document(sectionId)
//                .collection("beatDocs")
//                .getDocuments()
//            
//            let beatDocStatuses = beatDocsSnapshot.documents.map { doc in
//                let data = doc.data()
//                return BeatDocStatus(
//                    beatId: doc.documentID,
//                    type: data["type"] as? String ?? "",
//                    enrichmentLevel: data["enrichmentLevel"] as? String ?? "none"
//                )
//            }
//            
//            let a1bComplete = !beatDocStatuses.isEmpty
//            
//            sectionStatuses.append(SectionStatus(
//                sectionId: sectionId,
//                sectionIndex: index,
//                sectionRole: sectionRole,
//                a1bComplete: a1bComplete,
//                beatDocs: beatDocStatuses
//            ))
//        }
//        
//        return AnalysisStatus(
//            videoId: videoId,
//            a1aComplete: a1aComplete,
//            sections: sectionStatuses
//        )
//    }
//
//    func deleteAnalysis(videoId: String, channelId: String, target: ReprocessTarget) async throws {
//        let db = Firestore.firestore()
//        let videoRef = db
//            .collection("channels").document(channelId)
//            .collection("videos").document(videoId)
//        
//        switch target {
//        case .a1a:
//            // Delete logicSpine and all sections
//            try await videoRef.updateData([
//                "logicSpine": FieldValue.delete(),
//                "bridgePoints": FieldValue.delete(),
//                "validationStatus": FieldValue.delete()
//            ])
//            
//            let sectionsSnapshot = try await videoRef.collection("sections").getDocuments()
//            for doc in sectionsSnapshot.documents {
//                try await doc.reference.delete()
//            }
//            
//        case .section(let sectionId):
//            // Delete all beatDocs for this section
//            let beatDocsSnapshot = try await videoRef
//                .collection("sections").document(sectionId)
//                .collection("beatDocs")
//                .getDocuments()
//            
//            for doc in beatDocsSnapshot.documents {
//                try await doc.reference.delete()
//            }
//            
//        case .beat(let beatId):
//            // Delete specific beatDoc
//            // Need sectionId - would need to pass it in
//            break
//        }
//    }


    





}
import Foundation
import FirebaseFirestore

// MARK: - A3 FirebaseExtensions

extension CreatorAnalysisFirebase {
    
    // MARK: - StyleProfile Operations
    
    func saveStyleProfile(_ profile: StyleProfile) async throws {
        let docRef = db.collection("styleProfiles").document(profile.profileId)
        
        let dict: [String: Any] = [
            "profileId": profile.profileId,
            "channelId": profile.channelId,
            "name": profile.name,
            "description": profile.description,
            "triggerTopics": profile.triggerTopics,
            
            // Centroid - flattened
            "centroidAvgTurnPosition": profile.centroidAvgTurnPosition,
            "centroidAvgSectionCount": profile.centroidAvgSectionCount,
            "centroidAvgBeatCount": profile.centroidAvgBeatCount,
            "centroidBeatDistribution": profile.centroidBeatDistribution,
            "centroidStanceDistribution": profile.centroidStanceDistribution,
            "centroidTempoDistribution": profile.centroidTempoDistribution,
            
            // Choreography - flattened
            "typicalSectionSequence": profile.typicalSectionSequence,
            "turnPositionMean": profile.turnPositionMean,
            "turnPositionStdDev": profile.turnPositionStdDev as Any,
            "turnPositionMin": profile.turnPositionMin as Any,
            "turnPositionMax": profile.turnPositionMax as Any,
            
            // Voice - flattened
            "voiceStanceDistribution": profile.voiceStanceDistribution,
            "voiceTempoDistribution": profile.voiceTempoDistribution,
            "voiceAvgFormality": profile.voiceAvgFormality,
            
            // Discriminators
            "discriminators": profile.discriminators,
            
            // References
            "exemplarIds": profile.exemplarIds,
            "videoCount": profile.videoCount,
            "createdAt": Timestamp(date: profile.createdAt),
            "updatedAt": Timestamp(date: profile.updatedAt)
        ]
        
        try await docRef.setData(dict)
        print("✅ Saved StyleProfile: \(profile.profileId)")
    }
    
    func loadStyleProfile(profileId: String) async throws -> StyleProfile? {
        let docRef = db.collection("styleProfiles").document(profileId)
        let document = try await docRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return parseStyleProfile(data)
    }
    
    func loadStyleProfiles(channelId: String) async throws -> [StyleProfile] {
        let snapshot = try await db.collection("styleProfiles")
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            parseStyleProfile(doc.data())
        }
    }
    
    private func parseStyleProfile(_ data: [String: Any]) -> StyleProfile? {
        guard let profileId = data["profileId"] as? String,
              let channelId = data["channelId"] as? String,
              let name = data["name"] as? String,
              let description = data["description"] as? String else {
            return nil
        }
        
        return StyleProfile(
            profileId: profileId,
            channelId: channelId,
            name: name,
            description: description,
            triggerTopics: data["triggerTopics"] as? [String] ?? [],
            centroidAvgTurnPosition: data["centroidAvgTurnPosition"] as? Double ?? 0.5,
            centroidAvgSectionCount: data["centroidAvgSectionCount"] as? Double ?? 5,
            centroidAvgBeatCount: data["centroidAvgBeatCount"] as? Double ?? 20,
            centroidBeatDistribution: data["centroidBeatDistribution"] as? [String: Double] ?? [:],
            centroidStanceDistribution: data["centroidStanceDistribution"] as? [String: Double] ?? [:],
            centroidTempoDistribution: data["centroidTempoDistribution"] as? [String: Double] ?? [:],
            typicalSectionSequence: data["typicalSectionSequence"] as? [String] ?? [],
            turnPositionMean: data["turnPositionMean"] as? Double ?? 0.5,
            turnPositionStdDev: data["turnPositionStdDev"] as? Double,
            turnPositionMin: data["turnPositionMin"] as? Double,
            turnPositionMax: data["turnPositionMax"] as? Double,
            voiceStanceDistribution: data["voiceStanceDistribution"] as? [String: Double] ?? [:],
            voiceTempoDistribution: data["voiceTempoDistribution"] as? [String: Double] ?? [:],
            voiceAvgFormality: data["voiceAvgFormality"] as? Double ?? 5.0,
            discriminators: data["discriminators"] as? [String] ?? [],
            exemplarIds: data["exemplarIds"] as? [String] ?? [],
            videoCount: data["videoCount"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    // MARK: - StyleExemplar Operations
    
    func saveStyleExemplar(_ exemplar: StyleExemplar) async throws {
        let docRef = db.collection("styleExemplars").document(exemplar.exemplarId)
        
        let dict: [String: Any] = [
            "exemplarId": exemplar.exemplarId,
            "styleId": exemplar.styleId,
            "channelId": exemplar.channelId,
            "videoId": exemplar.videoId,
            "rank": exemplar.rank,
            "distanceFromCentroid": exemplar.distanceFromCentroid,
            "rationale": exemplar.rationale,
            "snippetBeatIds": exemplar.snippetBeatIds,
            "snippetTexts": exemplar.snippetTexts,
            "snippetWhys": exemplar.snippetWhys,
            "createdAt": Timestamp(date: exemplar.createdAt)
        ]
        
        try await docRef.setData(dict)
        print("✅ Saved StyleExemplar: \(exemplar.exemplarId)")
    }
    
    func saveStyleExemplars(_ exemplars: [StyleExemplar]) async throws {
        guard !exemplars.isEmpty else { return }
        
        let batch = db.batch()
        
        for exemplar in exemplars {
            let docRef = db.collection("styleExemplars").document(exemplar.exemplarId)
            
            let dict: [String: Any] = [
                "exemplarId": exemplar.exemplarId,
                "styleId": exemplar.styleId,
                "channelId": exemplar.channelId,
                "videoId": exemplar.videoId,
                "rank": exemplar.rank,
                "distanceFromCentroid": exemplar.distanceFromCentroid,
                "rationale": exemplar.rationale,
                "snippetBeatIds": exemplar.snippetBeatIds,
                "snippetTexts": exemplar.snippetTexts,
                "snippetWhys": exemplar.snippetWhys,
                "createdAt": Timestamp(date: exemplar.createdAt)
            ]
            
            batch.setData(dict, forDocument: docRef)
        }
        
        try await batch.commit()
        print("✅ Saved \(exemplars.count) StyleExemplars")
    }
    
    func loadStyleExemplars(profileId: String) async throws -> [StyleExemplar] {
        let snapshot = try await db.collection("styleExemplars")
            .whereField("profileId", isEqualTo: profileId)
            .order(by: "rank")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            parseStyleExemplar(doc.data())
        }
    }
    
    private func parseStyleExemplar(_ data: [String: Any]) -> StyleExemplar? {
        guard let exemplarId = data["exemplarId"] as? String,
              let styleId = data["styleId"] as? String,
              let channelId = data["channelId"] as? String,
              let videoId = data["videoId"] as? String else {
            return nil
        }
        
        return StyleExemplar(
            exemplarId: exemplarId,
            styleId: styleId,
            channelId: channelId,
            videoId: videoId,
            rank: data["rank"] as? Int ?? 0,
            distanceFromCentroid: data["distanceFromCentroid"] as? Double ?? 0,
            rationale: data["rationale"] as? String ?? "",
            snippetBeatIds: data["snippetBeatIds"] as? [String] ?? [],
            snippetTexts: data["snippetTexts"] as? [String] ?? [],
            snippetWhys: data["snippetWhys"] as? [String] ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    // MARK: - Delete Operations for A3
    
    func deleteStyleProfile(profileId: String) async throws {
        // Delete exemplars first
        let exemplars = try await loadStyleExemplars(profileId: profileId)
        for exemplar in exemplars {
            try await db.collection("styleExemplars").document(exemplar.exemplarId).delete()
        }
        
        // Delete profile
        try await db.collection("styleProfiles").document(profileId).delete()
        print("🗑️ Deleted StyleProfile and \(exemplars.count) exemplars: \(profileId)")
    }
    
    func deleteAllStyleData(channelId: String) async throws {
        // Load all profiles for channel
        let profiles = try await loadStyleProfiles(channelId: channelId)
        
        for profile in profiles {
            try await deleteStyleProfile(profileId: profile.profileId)
        }
        
        print("🗑️ Deleted all style data for channel: \(channelId)")
    }
}
