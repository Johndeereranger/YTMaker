//
//  AgentExecutionEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/28/25.
//


import Foundation
import SwiftUI

class AgentExecutionEngine: ObservableObject {
    private let agent: Agent
    private let session: ChatSession
    @Published var isThinking = false
    
    init(agent: Agent, session: ChatSession) {
        self.agent = agent
        self.session = session
    }
    
    // MARK: - Core Execution Method
    
    /// Unified step execution - handles all strategies and run types
    func runStep(
        step: PromptStep,
        userInput: String,
        sharedInput: String? = nil,
        purpose: PromptRunPurpose = .normal,
        inputID: String? = nil
    ) async throws -> PromptRun {
        isThinking = true
        defer { isThinking = false }
        
        // Strategy-based input preparation
        let finalInput = await prepareInput(for: step, userInput: userInput, sharedInput: sharedInput)
        
        // Determine if this is an image input
        let isImage = userInput.lowercased().hasPrefix("http") &&
                      (userInput.contains(".jpg") || userInput.contains(".png"))

        
        // Execute AI call
        let bundle = try await executePrompt(
            promptStep: step,
            userInput: userInput,
            finalInput: finalInput,
            stepPrompt: step.prompt
        )
        
        let fullRun = buildPromptRun(
            step: step,
            userInput: userInput,
            finalPrompt: step.prompt + "\n" + finalInput,
            response: bundle,
            inputID: inputID ?? userInput.normalized().sha256ToUUID(),
            purpose: purpose
        )
        return fullRun
    }
    
    private func executePrompt(
        promptStep: PromptStep,
        userInput: String,
        finalInput: String,
        stepPrompt: String
    ) async throws -> AIResponseBundle {
        let engine = AIEngine()
        let modelOverride = promptStep.aiModel
        if isImageInput(userInput) {
            guard let imageResponse = await engine.analyzeImage(
                url: userInput,
                prompt: finalInput,
                promptBackgroundInfo: stepPrompt,
                params: [
                    "temperature": 0.7,
                    "max_tokens": 1000
                ],
                modelOverride: modelOverride
            ) else {
                throw NSError(domain: "AIEngine", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get AI image analysis response"
                ])
            }
            return imageResponse
        } else {
            if promptStep.useCashe {
                guard let response = await engine.runWithCacheSupport(prompt: finalInput, reusableContext: stepPrompt, modelOverride: modelOverride) else {
                    throw NSError(domain: "AIEngine", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to get AI response using Cache"
                    ])
                }
                return response
            } else {
                guard let textResponse = await engine.runWithBundle(
                    prompt: finalInput,
                    promptBackgroundInfo: stepPrompt,
                    params: ["temperature": promptStep.temperature],
                    modelOverride: modelOverride
                ) else {
                    throw NSError(domain: "AIEngine", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to get AI response Run With Bundle"
                    ])
                }
                return textResponse
            }
        }
    }
    
    private func prepareInput(
        for step: PromptStep,
        userInput: String,
        sharedInput: String?
    ) async -> String {
        let isImageURL = userInput.lowercased().hasPrefix("http") && (userInput.contains(".jpg") || userInput.contains(".png"))
        if isImageURL{
            return userInput
        }
        
        var currentInput = userInput
        let hasDataSources = await DataSourceManager.instance.hasDataSources(for: step.id)
            if hasDataSources {
                if let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id),
                   !resolvedData.isEmpty {
                    currentInput = mergePrompt(currentInput, with: resolvedData)
                    print("✅ Applied data source enhancement")
                }
            }
        
        let hasHTMLChunks = HTMLProcessor.instance.hasChunks(for: step.id)
            if hasHTMLChunks {
                let enhanced = HTMLProcessor.instance.injectChunk(
                    for: step.id,
                    finalInput: currentInput,
                    userInput: userInput
                )
                if enhanced != currentInput {
                    currentInput = enhanced
                    print("✅ Applied HTML chunk enhancement")
                }
            }

        return currentInput
        // floor strategy was set up during the refactor, but it was not working so I've kind of factored it to not work here and it seems to be working OK
//        switch step.flowStrategy {
//        case .promptChaining:
//            return userInput
//        case .sharedInput:
//            return sharedInput ?? userInput
//        case .queryEnhanced:
//            let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id)
//            let mergedInput = mergePrompt(userInput, with: resolvedData)
//            return HTMLProcessor.instance.injectChunk(
//                for: step.id,
//                finalInput: mergedInput,
//                userInput: userInput
//            )
//        case .imageInput:
//            return userInput
//        }
    }
    // MARK: - Helper Methods
    
    /// Merges user input with external data
    private func mergePrompt(_ input: String, with data: String?) -> String {
        guard let data = data, !data.isEmpty else { return input }
        return "\(input)\n\nAdditional Context:\n\(data)"
    }
    private func buildPromptRun(
        step: PromptStep,
        userInput: String,
        finalPrompt: String,
        response: AIResponseBundle,
        inputID: String,
        purpose: PromptRunPurpose
    ) -> PromptRun {
        PromptRun(
            promptStepId: step.id,
            chatSessionId: session.id,
            basePrompt: step.prompt,
            userInput: userInput,
            finalPrompt: finalPrompt,
            response: response.content,
            createdAt: Date(),
            modelUsed: response.modelUsed,
            promptTokenCount: response.promptTokens,
            completionTokenCount: response.completionTokens,
            totalTokenCount: response.totalTokens,
            finishReason: response.finishReason,
            cachedTokens: response.cachedTokens,
            inputID: inputID,
            purpose: purpose,
            imageURL: nil // or add param if used
        )
    }

    private func buildPromptRun(from run: PromptRun, response: AIResponseBundle) -> PromptRun {
        PromptRun(
            promptStepId: run.promptStepId,
            chatSessionId: run.chatSessionId,
            basePrompt: run.basePrompt,
            userInput: run.userInput,
            finalPrompt: run.basePrompt + "\n" + run.userInput,
            response: response.content,
            createdAt: Date(),
            modelUsed: response.modelUsed,
            promptTokenCount: response.promptTokens,
            completionTokenCount: response.completionTokens,
            totalTokenCount: response.totalTokens,
            finishReason: response.finishReason,
            cachedTokens: response.cachedTokens,
            inputID: run.inputID,
            purpose: run.purpose,
            imageURL: run.imageURL
        )
    }
    
    // MARK: - Strategy-Specific Helpers
    
    /// Determines if input should be treated as an image
    private func isImageInput(_ input: String) -> Bool {
        return input.lowercased().hasPrefix("http") &&
               (input.contains(".jpg") || input.contains(".png") || 
                input.contains(".jpeg") || input.contains(".gif") || 
                input.contains(".webp"))
    }
    
    /// Prepares input for query-enhanced strategy
    private func prepareQueryEnhancedInput(
        userInput: String,
        step: PromptStep
    ) async -> String {
        let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id)
        let mergedInput = mergePrompt(userInput, with: resolvedData)
        return HTMLProcessor.instance.injectChunk(
            for: step.id,
            finalInput: mergedInput,
            userInput: userInput
        )
    }
}
