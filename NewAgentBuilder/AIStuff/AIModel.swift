//
//  AIModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/8/25.
//


//
//  AIModel.swift
//  Artifical
//
//  Created by Byron Smith on 5/8/25.
//

import Foundation


public enum AIModel: String, CaseIterable, Codable {
    // Claude
    case claude3Haiku = "claude-3-haiku-20240307"
    case claude3Sonnet = "claude-3-sonnet-20240229"
    case claude3Opus = "claude-3-opus-20240229"
    case claude35Sonnet = "claude-3-5-sonnet-20241022"
    case claude35Haiku = "claude-3-5-haiku-20241022"
    case claude37Sonnet = "claude-3-7-sonnet-20250219"
    case claude4Sonnet = "claude-sonnet-4-20250514"
    case claude4Opus = "claude-opus-4-20250514"
    case claude41Opus = "claude-opus-4-1-20250805"
    case claude45Sonnet = "claude-sonnet-4-5-20250929"
    case claude45Haiku = "claude-haiku-4-5-20251001"
    case claude45Opus = "claude-opus-4-5-20251101"
    case claude46Opus = "claude-opus-4-6"

    // OpenAI
    case gpt4 = "gpt-4"
    case gpt4Turbo = "gpt-4-turbo"
    case gpt4o = "gpt-4o"
    
    case azureGpt4o = "azure-gpt-4o"

    // Grok
    case grok1 = "grok-1"
    case grok1_5 = "grok-1.5"

    public var provider: String {
        if rawValue.starts(with: "gpt") { return "openai" }
        if rawValue.starts(with: "grok") { return "grok" }
        if rawValue.starts(with: "claude") { return "claude" }
        if rawValue.starts(with: "azure") { return "azure" }
        return "unknown"
    }
}

public struct AIResponseBundle {
    let content: String
    let modelUsed: String
    let finishReason: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cachedTokens: Int?
}
