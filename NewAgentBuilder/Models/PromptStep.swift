//
//  PromptStep.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//
import Foundation
import FirebaseFirestore

import Foundation

enum FlowStrategy: String, Codable, CaseIterable {
    case promptChaining
    case sharedInput
    case queryEnhanced
    case imageInput
}


// MARK: - PromptStep Model
struct PromptStep: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var prompt: String
    var notes: String
    var flowStrategy: FlowStrategy
    var isBatchEligible: Bool = false
    var aiModel: AIModel?
    var useCashe: Bool = false
    var temperature: Double = 0.7  // 0.0 = deterministic, 1.0 = creative

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        notes: String = "",
        flowStrategy: FlowStrategy = .promptChaining,
        isBatchEligible: Bool = false,
        aiModel: AIModel? = nil,
        useCashe: Bool = false,
        temperature: Double = 0.7
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.notes = notes
        self.flowStrategy = flowStrategy
        self.isBatchEligible = isBatchEligible
        self.aiModel = aiModel
        self.useCashe = useCashe
        self.temperature = temperature
    }
    init?(dictionary: [String: Any]) {
        guard
            let idString = dictionary["id"] as? String,
            let id = UUID(uuidString: idString),
            let title = dictionary["title"] as? String,
            let prompt = dictionary["prompt"] as? String
            
        else {
            return nil
        }
        let aiModelRaw = dictionary["aiModel"] as? String
        self.id = id
        self.title = title
        self.prompt = prompt
        self.notes = dictionary["notes"] as? String ?? ""
        self.isBatchEligible = dictionary["isBatchEligible"] as? Bool ?? false

        if let raw = dictionary["flowStrategy"] as? String,
           let strategy = FlowStrategy(rawValue: raw) {
            self.flowStrategy = strategy
        } else {
            self.flowStrategy = .promptChaining
        }

        let aiModel = AIModel(rawValue: aiModelRaw ?? "") // Will be nil if invalid
        self.aiModel = aiModel
        self.useCashe = dictionary["useCashe"] as? Bool ?? false
        self.temperature = dictionary["temperature"] as? Double ?? 0.7
    }

    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = data["title"] as? String,
              let prompt = data["prompt"] as? String
              
        else { return nil }
        self.useCashe = data["useCashe"] as? Bool ?? false
        self.id = id
        self.title = title
        self.prompt = prompt
        self.notes = data["notes"] as? String ?? ""
        self.isBatchEligible = data["isBatchEligible"] as? Bool ?? false
        
        // FlowStrategy parsing with fallback
        if let raw = data["flowStrategy"] as? String,
           let strategy = FlowStrategy(rawValue: raw) {
            self.flowStrategy = strategy
        } else {
            self.flowStrategy = .promptChaining
        }
        
        let aiModelRaw = data["aiModel"] as? String
        let aiModel = AIModel(rawValue: aiModelRaw ?? "") // Will be nil if invalid
        self.aiModel = aiModel
        self.temperature = data["temperature"] as? Double ?? 0.7
    }

    static func == (lhs: PromptStep, rhs: PromptStep) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
extension PromptStep {
//    private static let batchEligibleIds: Set<UUID> = [
//        UUID(uuidString: "32B53A03-6A90-4B0B-B38E-B5D00B50E20A")!,
//        UUID(uuidString: "F37C35D5-A4B1-4AA4-B1C0-D6530BB968D6")!,
//        UUID(uuidString: "0BEF2330-71FC-4039-88C0-21BC3322401D")!,
//        UUID(uuidString: "E792C74D-A88A-4477-98E0-29419A114E92")!,
//        UUID(uuidString: "9C4AE81F-4D2A-4574-97E4-729D2AFB021E")!,
//        UUID(uuidString: "E0E1F1E7-674B-4D0B-ADE6-6C18E803A75E")!,
//        UUID(uuidString: "14A5DC21-ECC2-4DA2-A648-34B40517DC42")!,
//        UUID(uuidString: "B2694E3C-1DC7-4D36-A30D-CDC4321F1021")!,
//        UUID(uuidString: "6989E1C5-31FC-4D77-AB3F-6BCE7180E25D")!,
//        UUID(uuidString: "8C70CD29-EBAA-4667-9883-B87889287B07")!
//    ]
    
   
}

