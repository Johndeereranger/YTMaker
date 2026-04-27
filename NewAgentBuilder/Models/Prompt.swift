//
//  Prompt.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//


import Foundation
import FirebaseFirestore



// MARK: - Prompt
/// Versioned prompt template with output and metadata.
/// Child of PromptStep.
struct Prompt: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var content: String
    var version: Int
    var createdAt: Date
    var output: String?
    var metadata: [String: String]?
    
    init(id: UUID = UUID(), content: String, version: Int = 1, createdAt: Date = Date(), output: String? = nil, metadata: [String: String]? = nil) {
        self.id = id
        self.content = content
        self.version = version
        self.createdAt = createdAt
        self.output = output
        self.metadata = metadata
    }
    
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let content = data["content"] as? String,
              let version = data["version"] as? Int,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        self.id = id
        self.content = content
        self.version = version
        self.createdAt = createdAt
        self.output = data["output"] as? String
        self.metadata = data["metadata"] as? [String: String]
    }
    
    // CRUD Methods
    mutating func update(content: String, metadata: [String: String]? = nil) {
        self.content = content
        self.metadata = metadata
    }
    
    mutating func incrementVersion() {
        self.version += 1
        self.createdAt = Date()
    }
    
    static func ==(lhs: Prompt, rhs: Prompt) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
