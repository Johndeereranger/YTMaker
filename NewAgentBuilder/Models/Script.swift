//
//  Script.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import Foundation
import Firebase

// MARK: - Script Model
struct Script: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }

    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = data["title"] as? String,
              let content = data["content"] as? String,
              let timestamp = data["createdAt"] as? Timestamp else {
            return nil
        }

        self.id = id
        self.title = title
        self.content = content
        self.createdAt = timestamp.dateValue()
    }

    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "title": title,
            "content": content,
            "createdAt": Timestamp(date: createdAt)
        ]
    }

    static let empty = Script(id: UUID(), title: "", content: "")
}

import Foundation
import FirebaseFirestore

// MARK: - MatchStrength Enum
enum MatchStrength: String, Codable, CaseIterable {
    case strong = "strong"
    case moderate = "moderate"
    case weak = "weak"          // Changed from "low" to "weak"
    case none = "none"
    
    var needsReview: Bool {
        switch self {
        case .strong: return false
        case .moderate: return true  // Might want to review moderate matches
        case .weak, .none: return true
        }
    }
    
    var emoji: String {
        switch self {
        case .strong: return "🟢"
        case .moderate: return "🟡"
        case .weak: return "🟠"
        case .none: return "🔴"
        }
    }
    
    var autoSelect: Bool {
        switch self {
        case .strong, .moderate: return true  // Auto-select good matches
        case .weak, .none: return false       // Force generation for poor matches
        }
    }
}

struct SystemMatch: Codable, Equatable, Hashable {
    var promptId: String
    var strength: MatchStrength
    var rank: Int // 1-4, where 1 is best match
    
    init(promptId: String, strength: MatchStrength, rank: Int) {
        self.promptId = promptId
        self.strength = strength
        self.rank = rank
    }
}

// MARK: - SoundBeat Model
struct SoundBeat: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var scriptId: UUID
    var order: Int
    var text: String
    var generatedPrompt: String?
    var selectedImagePromptId: String?
    var matchedImageURL: String?
    var needsImageGeneration: Bool
    var localAudioFilePath: String?
    var systemMatches: [SystemMatch]
    
    // MARK: - Computed Properties
      var bestSystemMatch: SystemMatch? {
          return systemMatches.first // Should be sorted by rank
      }
      
      var hasSystemMatches: Bool {
          return !systemMatches.isEmpty
      }

    init(
        id: UUID = UUID(),
        scriptId: UUID,
        order: Int,
        text: String,
        generatedPrompt: String? = nil,
        selectedImagePromptId: String? = nil,
        matchedImageURL: String? = nil,
        needsImageGeneration: Bool = false,
        localAudioFilePath: String? = nil
        
    ) {
        self.id = id
        self.scriptId = scriptId
        self.order = order
        self.text = text
        self.generatedPrompt = generatedPrompt
        self.selectedImagePromptId = selectedImagePromptId
        self.matchedImageURL = matchedImageURL
        self.needsImageGeneration = needsImageGeneration
        self.localAudioFilePath = localAudioFilePath
        self.systemMatches = []
    }
    
    static func == (lhs: SoundBeat, rhs: SoundBeat) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Firestore Init
extension SoundBeat {
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let scriptIdString = data["scriptId"] as? String,
              let scriptId = UUID(uuidString: scriptIdString),
              let order = data["order"] as? Int,
              let text = data["text"] as? String,
              let needsImageGeneration = data["needsImageGeneration"] as? Bool else {
            return nil
        }
        
        self.id = id
        self.scriptId = scriptId
        self.order = order
        self.text = text
        self.generatedPrompt = data["generatedPrompt"] as? String
        self.selectedImagePromptId = data["selectedImagePromptId"] as? String
        self.matchedImageURL = data["matchedImageURL"] as? String
        self.needsImageGeneration = needsImageGeneration
        if let matchesData = data["systemMatches"] as? [[String: Any]] {
                self.systemMatches = matchesData.compactMap { matchData in
                    guard let promptId = matchData["promptId"] as? String,
                          let strengthRaw = matchData["strength"] as? String,
                          let strength = MatchStrength(rawValue: strengthRaw),
                          let rank = matchData["rank"] as? Int else {
                        return nil
                    }
                    return SystemMatch(promptId: promptId, strength: strength, rank: rank)
                }.sorted { $0.rank < $1.rank } // Keep sorted by rank
            } else {
                self.systemMatches = []
            }
        self.localAudioFilePath = data["localAudioFilePath"] as? String
    }
    
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "scriptId": scriptId.uuidString,
            "order": order,
            "text": text,
            "generatedPrompt": generatedPrompt as Any,
            "selectedImagePromptId": selectedImagePromptId as Any,
            "matchedImageURL": matchedImageURL as Any,
            "needsImageGeneration": needsImageGeneration,
            "localAudioFilePath": localAudioFilePath ?? "",
            "systemMatches": systemMatches.map { match in
                          [
                              "promptId": match.promptId,
                              "strength": match.strength.rawValue,
                              "rank": match.rank
                          ]
                      }
        ]
    }
    
    static let empty = SoundBeat(
        scriptId: UUID(),
        order: 0,
        text: "",
        needsImageGeneration: false
    )
}
