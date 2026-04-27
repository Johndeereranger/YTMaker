//
//  GPTPromptGenerator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/14/25.
//
import Foundation

class GPTPromptGenerator {
    static func generatePrompt(from imageURL: String) async throws -> String {
        guard let agentId = UUID(uuidString: "43E8BA28-3D1D-4ECA-8EB2-E14B9EA39D66") else {
            throw NSError(domain: "InvalidUUID", code: 1, userInfo: [NSLocalizedDescriptionKey: "Agent ID is not a valid UUID"])
        }
        let agent = try await AgentManager.instance.fetchAgent(with: agentId)
        guard let step = agent?.promptSteps.first else {
            throw NSError(domain: "GPTPromptGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing prompt step"])
        }

        let session = ChatSession(agentId: agent!.id, title: "Image Prompt: \(UUID().uuidString)")
        let viewModel = await AgentRunnerViewModel(agent: agent!, session: session)

        let response = try await viewModel.runImageAnalysisStep(
                imageURL: imageURL,
                userPrompt: imageURL, // ⬅️ Input (image URL as 'user input')
                backgroundPrompt: step.prompt // ⬅️ System prompt is the instruction / intent
            )

        let run = PromptRun(
            promptStepId: step.id,
            chatSessionId: session.id,
            basePrompt: step.prompt,
            userInput: imageURL,
            finalPrompt: step.prompt,
            response: response.content,
            createdAt: Date(),
            modelUsed: response.modelUsed,
            promptTokenCount: response.promptTokens,
            completionTokenCount: response.completionTokens,
            totalTokenCount: response.totalTokens,
            finishReason: response.finishReason,
            openAIRequestId: nil,
            cachedTokens: response.cachedTokens,
            inputID: imageURL.normalized().sha256ToUUID(),
            purpose: .normal,
            imageURL: imageURL
        )

        try await PromptRunManager.instance.savePromptRun(run)
        return run.response
    }
}
