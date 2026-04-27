//
//  ChatSession.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/5/25.
//


import Foundation
import Firebase

struct ChatSession: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var agentId: UUID
    var title: String
    var createdAt: Date

    // Standard init
    init(
        id: UUID = UUID(),
        agentId: UUID,
        title: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.createdAt = createdAt
    }

    // Firestore-compatible dictionary init
    init?(dictionary: [String: Any]) {
        guard
            let idString = dictionary["id"] as? String,
            let id = UUID(uuidString: idString),
            let agentIdString = dictionary["agentId"] as? String,
            let agentId = UUID(uuidString: agentIdString),
            let title = dictionary["title"] as? String,
            let createdAtRaw = dictionary["createdAt"]
        else {
            return nil
        }

        self.id = id
        self.agentId = agentId
        self.title = title
        if let timestamp = createdAtRaw as? Timestamp {
                self.createdAt = timestamp.dateValue()
            } else if let interval = createdAtRaw as? TimeInterval {
                self.createdAt = Date(timeIntervalSince1970: interval)
            } else {
                return nil
            }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
