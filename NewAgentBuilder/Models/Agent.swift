//
//  Agent.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//


import Foundation
import FirebaseFirestore

import Foundation
import FirebaseFirestore

struct Agent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var category: String?
    var promptSteps: [PromptStep]
    var enabledPromptStepIds: [UUID] = []
    var chatSessions: [ChatSession] = []
    var isChatAgent: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        category: String? = nil,
        promptSteps: [PromptStep] = [],
        enabledPromptStepIds: [UUID] = [],
        chatSessions: [ChatSession] = [],
        isChatAgent: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.promptSteps = promptSteps
        self.enabledPromptStepIds = enabledPromptStepIds
        self.chatSessions = chatSessions
        self.isChatAgent = isChatAgent
    }

    init?(document: DocumentSnapshot) {
        guard
            let data = document.data(),
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = data["name"] as? String
        else {
            return nil
        }

        self.id = id
        self.name = name
        self.description = data["description"] as? String
        self.category = data["category"] as? String
        
        if let isChatAgent = data["isChatAgent"] as? Bool {
            self.isChatAgent = isChatAgent
        } else {
            self.isChatAgent = false
        }

        if let stepsData = data["promptSteps"] as? [[String: Any]] {
            self.promptSteps = stepsData.compactMap { PromptStep(dictionary: $0) }
        } else {
            self.promptSteps = []
           
        }
        if let idStrings = data["enabledPromptStepIds"] as? [String] {
             self.enabledPromptStepIds = idStrings.compactMap { UUID(uuidString: $0) }
         } else {
             self.enabledPromptStepIds = []
         }
        if let sessions = data["chatSessions"] as? [[String: Any]] {
            self.chatSessions = sessions.compactMap { dict in
                guard
                    let idStr = dict["id"] as? String,
                    let agentIdStr = dict["agentId"] as? String,
                    let title = dict["title"] as? String,
                    let timestamp = dict["createdAt"] as? Timestamp,
                    let id = UUID(uuidString: idStr),
                    let agentId = UUID(uuidString: agentIdStr)
                else { return nil }

                return ChatSession(
                    id: id,
                    agentId: agentId,
                    title: title,
                    createdAt: timestamp.dateValue()
                )
            }
        } else {
            self.chatSessions = []
        }
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static let empty = Agent(name: "")
}


extension Agent {
    var usesWeekTitle: Bool {
        return id.uuidString == "91B60D7A-9463-42D9-A684-0D97FA73EA84"
    }

    func generateSessionTitle(selectedWeek: Int) -> String {
        if usesWeekTitle {
            return "Week \(selectedWeek)"
        } else {
            return "Session \(chatSessions.count + 1)"
        }
    }
}
