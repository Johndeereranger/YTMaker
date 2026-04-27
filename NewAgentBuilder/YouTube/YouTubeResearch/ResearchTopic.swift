//
//  ResearchTopic.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//
import Foundation

//struct ResearchTopic: Identifiable, Codable {
//    var id: String                   // ✅ Stored property, set once
//    var title: String
//    var description: String?
//    var videoIds: [String]
//    var createdAt: Date
//    var topicNotes: String?
//    
//    // Helper initializer for new topics
//    init(title: String, description: String? = nil, videoIds: [String] = [], topicNotes: String? = nil) {
//        self.id = UUID().uuidString  // Set once during creation
//        self.title = title
//        self.description = description
//        self.videoIds = videoIds
//        self.createdAt = Date()
//        self.topicNotes = topicNotes
//    }
//}

// MARK: - Status Enum
enum TopicStatus: String, Codable, CaseIterable {
    case idea = "Idea"
    case selected = "Selected"
    case published = "Published"
}

// MARK: - Updated ResearchTopic
struct ResearchTopic: Identifiable, Codable {
    var id: String
    var title: String
    var description: String?
    var videoIds: [String]
    var createdAt: Date
    var topicNotes: String?
    
    // New fields
    var buildOrder: Int
    var targetPublishedMonth: String
    var category: String
    var isRemake: Bool
    var keyVisuals: String?
    var titleIdeas: String?
    var thumbnailIdeas: String?
    var status: TopicStatus
    var howHelpsBrain: String?
    
    // MARK: - Custom Codable Implementation
    enum CodingKeys: String, CodingKey {
        case id, title, description, videoIds, createdAt, topicNotes
        case buildOrder, targetPublishedMonth, category, isRemake
        case keyVisuals, titleIdeas, thumbnailIdeas, status, howHelpsBrain
    }
    
    // Custom decoder that provides defaults for missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields (these existed before)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        videoIds = try container.decodeIfPresent([String].self, forKey: .videoIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        topicNotes = try container.decodeIfPresent(String.self, forKey: .topicNotes)
        
        // New fields with defaults for backward compatibility
        buildOrder = try container.decodeIfPresent(Int.self, forKey: .buildOrder) ?? 1000
        targetPublishedMonth = try container.decodeIfPresent(String.self, forKey: .targetPublishedMonth) ?? "no month"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "no category"
        isRemake = try container.decodeIfPresent(Bool.self, forKey: .isRemake) ?? false
        keyVisuals = try container.decodeIfPresent(String.self, forKey: .keyVisuals)
        titleIdeas = try container.decodeIfPresent(String.self, forKey: .titleIdeas)
        thumbnailIdeas = try container.decodeIfPresent(String.self, forKey: .thumbnailIdeas)
        status = try container.decodeIfPresent(TopicStatus.self, forKey: .status) ?? .idea
        howHelpsBrain = try container.decodeIfPresent(String.self, forKey: .howHelpsBrain)
    }
    
    // Helper initializer for new topics
    init(title: String,
         description: String? = nil,
         videoIds: [String] = [],
         topicNotes: String? = nil,
         buildOrder: Int = 1000,
         targetPublishedMonth: String = "no month",
         category: String = "no category",
         isRemake: Bool = false,
         keyVisuals: String? = nil,
         titleIdeas: String? = nil,
         thumbnailIdeas: String? = nil,
         status: TopicStatus = .idea,
         howHelpsBrain: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.videoIds = videoIds
        self.createdAt = Date()
        self.topicNotes = topicNotes
        self.buildOrder = buildOrder
        self.targetPublishedMonth = targetPublishedMonth
        self.category = category
        self.isRemake = isRemake
        self.keyVisuals = keyVisuals
        self.titleIdeas = titleIdeas
        self.thumbnailIdeas = thumbnailIdeas
        self.status = status
        self.howHelpsBrain = howHelpsBrain
    }
}

// MARK: - Category Helper
enum TopicCategory {
    static let defaultCategories = [
        "no category",
        "Corn",
        "Deer Related (Non-Tactics)",
        "Hunting Tactics",
        "Thermal Drone",
        "Gear & Equipment",
        "Deer Behavior",
        "Habitat",
        "DeerBrain Analytics"
    ]
}
