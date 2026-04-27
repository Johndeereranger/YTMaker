//
//  ModelAdapter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/8/25.
//



import Foundation

/// Protocol defining AI model adapter requirements (e.g., GPT-4, Claude, Grok).
protocol ModelAdapter {

    func generate_response(prompt: String, promptBackgroundInfo: String, params: [String: Any]) async -> String
    func generate_batch_response(prompts: [String], promptBackgroundInfo: String) async -> [String]
    func generate_response_bundle(
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle?
    
    func analyzeImageURL(
        url: String,
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle?
}
