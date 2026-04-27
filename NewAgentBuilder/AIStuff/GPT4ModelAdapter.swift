//
//  GPT4ModelAdapter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/8/25.
//
//


// MARK: - GPT4ModelAdapter
// File: GPT4ModelAdapter.swift
// Purpose: Adapter for GPT-4 API (swap for Claude, Grok).
// Part of the AI Agent Framework - App-Specific Optimization
// Created: March 06, 2025

import Foundation

/// Adapter for integrating with the GPT-4 API.
/// - Interacts with:
///   - `AIProcessingCore`: Executes AI tasks using GPT-4.
/// - Key Role: Provides a bridge between the framework and GPT-4 API, configurable via parameters.
public class GPT4ModelAdapter: ModelAdapter {
    // MARK: - Properties
    
    /// API key for GPT-4 access.
    public let apiKey: String
    public let model: AIModel
    // MARK: - Initialization
    
    /// Initializes the GPT-4 adapter with an API key.
    public init(apiKey: String = Secrets.openAIAPIKey, model: AIModel = .gpt4o) {
        self.apiKey = apiKey
        self.model = model
    }
    
    // MARK: - Methods
        
        /// Generates a response using the GPT-4 API.
        /// - Parameters:
        ///   - prompt: The input prompt to process.
        ///   - params: Additional parameters (e.g., temperature, max_tokens).
        /// - Returns: The generated response string.
    public func generate_response(prompt: String, promptBackgroundInfo: String, params: [String: Any]) async -> String {
        let temperature = params["temperature"] as? Double ?? 0.7
        let maxTokens = params["max_tokens"] as? Int ?? 5000
        
        #if DEBUG
        print("""
        GPT4ModelAdapter sending request:
        System: \(promptBackgroundInfo)
        User: \(prompt)
        temperature: \(temperature), max_tokens: \(maxTokens)
        """)
        #endif

        return await sendOpenAIRequest(prompt: prompt, promptBackgroundInfo: promptBackgroundInfo, temperature: temperature, maxTokens: maxTokens) ?? "Error: No response from GPT-4"
    }
    public func generate_response_bundle(
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any],
        
    ) async -> AIResponseBundle? {
        let temperature = params["temperature"] as? Double ?? 0.7
        let maxTokens = params["max_tokens"] as? Int ?? 10000

        #if DEBUG
        print("""
        GPT4ModelAdapter (bundle) request:
        System: \(promptBackgroundInfo)
        User: \(prompt)
        temperature: \(temperature), max_tokens: \(maxTokens)
        """)
        #endif

        return await sendOpenAIRequestFull(
            prompt: prompt,
            promptBackgroundInfo: promptBackgroundInfo,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
    public func generate_batch_response(prompts: [String], promptBackgroundInfo: String) async -> [String] {
           let apiUrl = "https://api.openai.com/v1/chat/completions"
           
           // Format prompts into OpenAI API batch format
           let messages = prompts.map { ["role": "user", "content": $0] }
           let jsonData: [String: Any] = [
            "model": model.rawValue,
               "messages": messages,
               "temperature": 0.7,
               "max_tokens": 500
           ]
           
           guard let url = URL(string: apiUrl),
                 let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
               return Array(repeating: "Error: Invalid request", count: prompts.count)
           }
           
           var request = URLRequest(url: url)
            
           request.httpMethod = "POST"
           request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           request.httpBody = httpBody
           
           do {
               let (data, _) = try await URLSession.shared.data(for: request)
               let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
               
               let responses = (responseJSON?["choices"] as? [[String: Any]])?.compactMap { choice in
                   (choice["message"] as? [String: Any])?["content"] as? String
               }
               
               return responses ?? Array(repeating: "Error: No response", count: prompts.count)
           } catch {
               return Array(repeating: "Error: \(error.localizedDescription)", count: prompts.count)
           }
       }
        // MARK: - Private Methods
        
        /// Sends an API request to OpenAI GPT-4.
        /// - Parameters:
        ///   - prompt: The input prompt.
        ///   - temperature: Controls randomness (0 = deterministic, 1 = creative).
        ///   - maxTokens: Limits response length.
        /// - Returns: The GPT-4 response text or nil if an error occurred.
    private func sendOpenAIRequest(prompt: String, promptBackgroundInfo: String, temperature: Double, maxTokens: Int) async -> String? {
        let apiUrl = "https://api.openai.com/v1/chat/completions"

        let jsonData: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": promptBackgroundInfo],
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let url = URL(string: apiUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            return "Error: Invalid request setup"
        }

        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let raw = String(data: data, encoding: .utf8) {
                print("📦 Raw OpenAI response:\n\(raw)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return "Error: Invalid GPT-4 API response"
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    func sendOpenAIRequestFull(
        prompt: String,
        promptBackgroundInfo: String,
        temperature: Double,
        maxTokens: Int
    ) async -> AIResponseBundle? {
        let apiUrl = "https://api.openai.com/v1/chat/completions"

        let jsonData: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": promptBackgroundInfo],
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let url = URL(string: apiUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            return nil
        }

        var request = URLRequest(url: url)
     
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelUsed = json["model"] as? String,
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let finishReason = choices.first?["finish_reason"] as? String,
                  let usage = json["usage"] as? [String: Any],
                  let promptTokens = usage["prompt_tokens"] as? Int,
                  let completionTokens = usage["completion_tokens"] as? Int,
                  let totalTokens = usage["total_tokens"] as? Int
            else {
                return nil
            }

            let cachedTokens = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int

            return AIResponseBundle(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                modelUsed: modelUsed,
                finishReason: finishReason,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens
            )
        } catch {
            print("❌ Error calling OpenAI: \(error)")
            return nil
        }
    }
    
    // MARK: - Public Methods (Protocol Conformance)

    /// Analyze an image by URL with a prompt and background info.
    /// - Parameters:
    ///   - url: The image URL to analyze.
    ///   - prompt: The prompt to accompany the image.
    ///   - promptBackgroundInfo: Background system prompt.
    ///   - params: Additional parameters for the request.
    /// - Returns: An AIResponseBundle with the analysis, or nil on error.
    public func analyzeImageURL(
        url: String,
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle? {
        let temperature = params["temperature"] as? Double ?? 0.7
        let maxTokens = params["max_tokens"] as? Int ?? 1000
        let apiUrl = "https://api.openai.com/v1/chat/completions"

        let messages: [[String: Any]] = [
            ["role": "system", "content": promptBackgroundInfo],
            ["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": url]]
            ]]
        ]

        let jsonData: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let url = URL(string: apiUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            return nil
        }

        var request = URLRequest(url: url)
       
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Failed to deserialize JSON from data.")
                return nil
            }

            guard let modelUsed = json["model"] as? String else {
                print("❌ Missing or invalid 'model' in response.", json)
                return nil
            }

            guard let choices = json["choices"] as? [[String: Any]] else {
                print("❌ Missing or invalid 'choices' array.")
                return nil
            }

            guard let message = choices.first?["message"] as? [String: Any] else {
                print("❌ Missing 'message' in first choice.")
                return nil
            }

            guard let content = message["content"] as? String else {
                print("❌ Missing or invalid 'content' in message.")
                return nil
            }

            guard let finishReason = choices.first?["finish_reason"] as? String else {
                print("❌ Missing or invalid 'finish_reason'.")
                return nil
            }

            guard let usage = json["usage"] as? [String: Any] else {
                print("❌ Missing or invalid 'usage' in response.")
                return nil
            }

            guard let promptTokens = usage["prompt_tokens"] as? Int else {
                print("❌ Missing or invalid 'prompt_tokens'.")
                return nil
            }

            guard let completionTokens = usage["completion_tokens"] as? Int else {
                print("❌ Missing or invalid 'completion_tokens'.")
                return nil
            }

            guard let totalTokens = usage["total_tokens"] as? Int else {
                print("❌ Missing or invalid 'total_tokens'.")
                return nil
            }

            let cachedTokens = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int

            return AIResponseBundle(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                modelUsed: modelUsed,
                finishReason: finishReason,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens
            )
        } catch {
            print("❌ Error calling OpenAI for image analysis: \(error)")
            return nil
        }
    }
}

// MARK: - Notes Reference
/// Matches "GPT4ModelAdapter" in AIAgentNotes.swift:
/// - Adapter for GPT-4 API, swappable with Claude or Grok.
/// - Implements generate_response(prompt: String, params: [String: Any]) -> String.
/// - Configured via AgentFactory for AIProcessingCore.
/// - Requires optimization: Placeholder for real GPT-4 API integration.
