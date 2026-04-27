//
//  PromptRun.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/30/25.
//


import Foundation
import FirebaseFirestore
import Foundation
import FirebaseFirestore

//struct PromptRun: Identifiable, Codable, Equatable, Hashable {
//    var id: UUID = UUID()
//    var promptStepId: UUID
//    var chatSessionId: UUID?
//    var basePrompt: String
//    var userInput: String
//    var finalPrompt: String
//    var response: String
//    var createdAt: Date = Date()
//    var parentRunId: UUID? = ni
//    
//    var feedbackRating: Int? = nil
//    var feedbackNote: String? = nil
//    
//    var isFeedbackComplete: Bool {
//        !(feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
//        (feedbackRating != nil)
//    }
//
//    init(
//        id: UUID = UUID(),
//        promptStepId: UUID,
//        chatSessionId: UUID? = nil,
//        basePrompt: String,
//        userInput: String,
//        finalPrompt: String,
//        response: String,
//        createdAt: Date = Date(),
//        parentRunId: UUID? = nil,
//        feedbackRating: Int? = nil,
//        feedbackNote: String? = nil
//    ) {
//        self.id = id
//        self.promptStepId = promptStepId
//        self.chatSessionId = chatSessionId
//        self.basePrompt = basePrompt
//        self.userInput = userInput
//        self.finalPrompt = finalPrompt
//        self.response = response
//        self.createdAt = createdAt
//        self.parentRunId = parentRunId
//        self.feedbackRating = feedbackRating
//        self.feedbackNote = feedbackNote
//    }
//
//    init?(document: DocumentSnapshot) {
//        guard let data = document.data(),
//              let idString = data["id"] as? String,
//              let id = UUID(uuidString: idString),
//              let promptStepIdString = data["promptStepId"] as? String,
//              let promptStepId = UUID(uuidString: promptStepIdString),
//              let basePrompt = data["basePrompt"] as? String,
//              let userInput = data["userInput"] as? String,
//              let finalPrompt = data["finalPrompt"] as? String,
//              let response = data["response"] as? String,
//              let timestamp = data["createdAt"] as? Timestamp
//        else {
//            return nil
//        }
//
//        self.id = id
//        self.promptStepId = promptStepId
//        self.chatSessionId = (data["chatSessionId"] as? String).flatMap { UUID(uuidString: $0) }
//        self.basePrompt = basePrompt
//        self.userInput = userInput
//        self.finalPrompt = finalPrompt
//        self.response = response
//        self.createdAt = timestamp.dateValue()
//        self.parentRunId = (data["parentRunId"] as? String).flatMap { UUID(uuidString: $0) }
//        self.feedbackRating = data["feedbackRating"] as? Int
//        self.feedbackNote = data["feedbackNote"] as? String
//    }
//
//    static let empty = PromptRun(
//        promptStepId: UUID(),
//        basePrompt: "",
//        userInput: "",
//        finalPrompt: "",
//        response: ""
//    )
//}

enum PromptRunPurpose: String, Codable, CaseIterable {
    case normal
    case retry
    case fork
    case inputVariation // 👈 you're testing one prompt with multiple inputs
    case diagnostic
}


struct PromptRun: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var promptStepId: UUID
    var chatSessionId: UUID?
    var basePrompt: String
    var userInput: String
    var finalPrompt: String
    var response: String
    var createdAt: Date = Date()
   
   
    var inputID: String? = nil
    var purpose: PromptRunPurpose = .normal
    
    var feedbackRating: Int? = nil
    var feedbackNote: String? = nil

    // 🔧 NEW diagnostic & tracking fields
    var modelUsed: String? = nil
    var promptTokenCount: Int? = nil
    var completionTokenCount: Int? = nil
    var totalTokenCount: Int? = nil
    var finishReason: String? = nil
    var openAIRequestId: String? = nil
    var cachedTokens: Int? = nil
    var imageURL: String? = nil

    var isFeedbackComplete: Bool {
        !(feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (feedbackRating != nil)
    }

    init(
        id: UUID = UUID(),
        promptStepId: UUID,
        chatSessionId: UUID? = nil,
        basePrompt: String,
        userInput: String,
        finalPrompt: String,
        response: String,
        createdAt: Date = Date(),
        feedbackRating: Int? = nil,
        feedbackNote: String? = nil,
        modelUsed: String? = nil,
        promptTokenCount: Int? = nil,
        completionTokenCount: Int? = nil,
        totalTokenCount: Int? = nil,
        finishReason: String? = nil,
        openAIRequestId: String? = nil,
        cachedTokens: Int? = nil,
        inputID: String? = nil,
           purpose: PromptRunPurpose = .normal,
        imageURL: String? = nil
    ) {
        self.id = id
        self.promptStepId = promptStepId
        self.chatSessionId = chatSessionId
        self.basePrompt = basePrompt
        self.userInput = userInput
        self.finalPrompt = finalPrompt
        self.response = response
        self.createdAt = createdAt
       
        self.feedbackRating = feedbackRating
        self.feedbackNote = feedbackNote
        self.modelUsed = modelUsed
        self.promptTokenCount = promptTokenCount
        self.completionTokenCount = completionTokenCount
        self.totalTokenCount = totalTokenCount
        self.finishReason = finishReason
        self.openAIRequestId = openAIRequestId
        self.cachedTokens = cachedTokens
        self.inputID = inputID
              self.purpose = purpose
        self.imageURL = imageURL
    }

    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let promptStepIdString = data["promptStepId"] as? String,
              let promptStepId = UUID(uuidString: promptStepIdString),
              let basePrompt = data["basePrompt"] as? String,
              let userInput = data["userInput"] as? String,
              let finalPrompt = data["finalPrompt"] as? String,
              let response = data["response"] as? String,
              let timestamp = data["createdAt"] as? Timestamp
        else {
            return nil
        }

        self.id = id
        self.promptStepId = promptStepId
        self.chatSessionId = (data["chatSessionId"] as? String).flatMap { UUID(uuidString: $0) }
        self.basePrompt = basePrompt
        self.userInput = userInput
        self.finalPrompt = finalPrompt
        self.response = response
        self.createdAt = timestamp.dateValue()
        //self.parentRunId = (data["parentRunId"] as? String).flatMap { UUID(uuidString: $0) }
        self.feedbackRating = data["feedbackRating"] as? Int
        self.feedbackNote = data["feedbackNote"] as? String

        // 🔧 new fields
        self.modelUsed = data["modelUsed"] as? String
        self.promptTokenCount = data["promptTokenCount"] as? Int
        self.completionTokenCount = data["completionTokenCount"] as? Int
        self.totalTokenCount = data["totalTokenCount"] as? Int
        self.finishReason = data["finishReason"] as? String
        self.openAIRequestId = data["openAIRequestId"] as? String
        self.cachedTokens = data["cachedTokens"] as? Int
        self.inputID = data["inputID"] as? String
        self.imageURL = data["imageURL"] as? String
        if let purposeString = data["purpose"] as? String,
           let parsedPurpose = PromptRunPurpose(rawValue: purposeString) {
            self.purpose = parsedPurpose
        } else {
            self.purpose = .normal
        }
    }

    static let empty = PromptRun(
        promptStepId: UUID(),
        basePrompt: "",
        userInput: "",
        finalPrompt: "",
        response: ""
    )
}
