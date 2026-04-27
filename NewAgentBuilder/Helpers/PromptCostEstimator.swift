//
//  PromptCostEstimator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//

import Foundation
final class PromptCostEstimator {
    static let instance = PromptCostEstimator()
    

    
    private let prices: [String: (Double, Double)] = [
        // 🧠 OpenAI
        "gpt-4": (0.03 / 1000, 0.06 / 1000),
        "gpt-4-32k": (0.06 / 1000, 0.12 / 1000),
        "gpt-4-turbo": (0.01 / 1000, 0.03 / 1000),
        "gpt-4o": (0.005 / 1000, 0.015 / 1000),
        "gpt-3.5-turbo": (0.0005 / 1000, 0.0015 / 1000),

        // 📝 Grok (Placeholder, not publicly priced)
        "grok-1": (0.00, 0.00),
        "grok-1.5": (0.00, 0.00),

        // 📘 Claude v3 & 3.5 (Estimated or placeholder pricing)
        "claude-3-haiku-20240307": (0.00000025, 0.00000125),    // $0.25/$1.25 per MTok
        "claude-3-sonnet-20240229": (0.000003, 0.000015),       // $3/$15 per MTok
        "claude-3-opus-20240229": (0.000015, 0.000075),         // $15/$75 per MTok
        "claude-3-5-sonnet-20241022": (0.000003, 0.000015),     // $3/$15 per MTok
        "claude-3-5-haiku-20241022": (0.0000008, 0.000004),     // $0.80/$4 per MTok
        "claude-sonnet-4-20250514": (0.000003, 0.000015),       // $3/$15 per MTok
        "claude-opus-4-20250514": (0.000015, 0.000075)          // $15/$75 per MTok
    ]
    
    private init() {}
    func estimateCost(from run: PromptRun) -> Double {
        let model = run.modelUsed ?? ""
        let promptTokens = run.promptTokenCount ?? 0
        let completionTokens = run.completionTokenCount ?? 0
        return estimateCost(model: model, promptTokens: promptTokens, completionTokens: completionTokens)
    }
    
    func estimateCost(model: String, promptTokens: Int, completionTokens: Int) -> Double {
        let key = normalizedModelKey(from: model)
        guard let (promptRate, completionRate) = prices[key] else { return 0.0 }
        let promptCost = Double(promptTokens) * promptRate
        let completionCost = Double(completionTokens) * completionRate
        return promptCost + completionCost
    }
    
    private func normalizedModelKey(from raw: String) -> String {
        if raw.hasPrefix("gpt-4o") { return "gpt-4o" }
        if raw.hasPrefix("gpt-4-turbo") { return "gpt-4-turbo" }
        if raw.hasPrefix("gpt-4") { return "gpt-4" }
        if raw.hasPrefix("gpt-3.5-turbo") { return "gpt-3.5-turbo" }
        return raw.lowercased()
    }
}
