//
//  ClaudeModelAdapter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/2/25.
//

// MARK: - ClaudeModelAdapter
// File: ClaudeModelAdapter.swift
// Purpose: Adapter for Claude API (Anthropic).
// Part of the AI Agent Framework - App-Specific Optimization
// Created: June 02, 2025

import Foundation


/// Adapter for integrating with the Claude API.
/// - Interacts with:
///   - `AIProcessingCore`: Executes AI tasks using Claude.
/// - Key Role: Provides a bridge between the framework and Claude API, configurable via parameters.
public class ClaudeModelAdapter: ModelAdapter {
    // MARK: - Properties
    
    /// API key for Claude access.
  //  private let apiKey: String
    
    /// Configurable Claude model.
    private let model: AIModel
    
    /// Base URL for Claude API.
    private let baseUrl = "https://api.anthropic.com/v1/messages"
    private let apiKey = Secrets.anthropicAPIKey

    // MARK: - Initialization
    

    public init( model: AIModel = .claude35Sonnet) {
//        guard !apiKey.isEmpty else {
//            fatalError("ClaudeModelAdapter: API key cannot be empty")
//        }
//        self.apiKey = apiKey
        self.model = model
    }
  
    // MARK: - Public Methods
    
    /// Generates a response using the Claude API.
    /// - Parameters:
    ///   - prompt: The input prompt to process.
    ///   - promptBackgroundInfo: System prompt/background information.
    ///   - params: Additional parameters (e.g., temperature, max_tokens).
    /// - Returns: The generated response string.
    public func generate_response(
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> String {
        let config = validatedParameters(from: params)
#if DEBUG
        print("""
        Sending request:
        System: \(promptBackgroundInfo)
        User: \(prompt)
        temperature: \(config.temperature), max_tokens: \(config.maxTokens)
        """)
#endif
        
        return await sendClaudeRequest(
            prompt: prompt,
            promptBackgroundInfo: promptBackgroundInfo,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        ) ?? "Error: No response from Claude"
    }
    
    /// Generates a response bundle with detailed metadata using the Claude API.
    /// - Parameters:
    ///   - prompt: The input prompt to process.
    ///   - promptBackgroundInfo: System prompt/background information.
    ///   - params: Additional parameters (e.g., temperature, max_tokens).
    /// - Returns: An AIResponseBundle with response and metadata.
    public func generate_response_bundle(
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle? {
        let config = validatedParameters(from: params)
//#if DEBUG
        print("""
        Bundle request:
        System: \(promptBackgroundInfo)
        User: \(prompt)
        temperature: \(config.temperature), max_tokens: \(config.maxTokens)
        """)
   //     #endif

        return await sendClaudeRequestFull(
            prompt: prompt,
            promptBackgroundInfo: promptBackgroundInfo,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )
    }
    
    /// Generates batch responses for multiple prompts concurrently.
    /// - Parameters:
    ///   - prompts: Array of prompts to process.
    ///   - promptBackgroundInfo: System prompt/background information.
    /// - Returns: Array of response strings.
    public func generate_batch_response(
        prompts: [String],
        promptBackgroundInfo: String
    ) async -> [String] {
        await withTaskGroup(of: String.self) { group in
            for prompt in prompts {
                group.addTask { [weak self] in
                    guard let self else { return "Error: Adapter deallocated" }
                    return await self.sendClaudeRequest(
                        prompt: prompt,
                        promptBackgroundInfo: promptBackgroundInfo,
                        temperature: 0.7,
                        maxTokens: 6000
                    ) ?? "Error: No response from Claude"
                }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }
    }
    
    /// Analyzes an image by URL with a prompt and background info.
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
        let config = validatedParameters(from: params, defaultMaxTokens: 1000)
        
        guard let base64Image = await fetchAndEncodeImage(from: url) else {
            print("Failed to fetch or encode image from URL: \(url)")
            return nil
        }

        let messages: [[String: Any]] = [
            ["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image", "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]]
            ]]
        ]

        let jsonData: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "system": promptBackgroundInfo,
            "messages": messages
        ]

        guard let url = URL(string: baseUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            print("Invalid request setup for image analysis")
            return nil
        }

        var request = URLRequest(url: url)
        configureRequest(&request, httpBody: httpBody)

        return await executeRequest(request)
    }
    
    // MARK: - Private Methods
    
    /// Validates and extracts parameters from the params dictionary.
    private func validatedParameters(from params: [String: Any], defaultMaxTokens: Int = 5000) -> ClaudeParameters {
        let temperature = min(max(params["temperature"] as? Double ?? 1.0, 0.0), 1.0)
        let maxTokens = max(params["max_tokens"] as? Int ?? defaultMaxTokens, 1)
        return ClaudeParameters(temperature: temperature, maxTokens: maxTokens)
    }
    
    /// Fetches an image from a URL and encodes it as base64.
    private func fetchAndEncodeImage(from url: String) async -> String? {
        guard let imageUrl = URL(string: url) else {
            print("Invalid image URL: \(url)")
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageUrl)
            return data.base64EncodedString()
        } catch {
            print("Error fetching image: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Configures a URLRequest with common headers and body.
    private func configureRequest(_ request: inout URLRequest, httpBody: Data) {
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = httpBody
        request.timeoutInterval = 300
    }
    
    /// Sends an API request to Claude.
    /// - Returns: The Claude response text or nil if an error occurred.
    private func sendClaudeRequest(
        prompt: String,
        promptBackgroundInfo: String,
        temperature: Double,
        maxTokens: Int
    ) async -> String? {
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let jsonData: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "system": promptBackgroundInfo,
            "messages": messages
        ]

        guard let url = URL(string: baseUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            print("Invalid request setup")
            return nil
        }

        var request = URLRequest(url: url)
        configureRequest(&request, httpBody: httpBody)

        guard let response = await executeRequest(request) else {
            return nil
        }
        return response.content
    }
    
    /// Sends a full API request to Claude and returns detailed response bundle.
    /// - Returns: An AIResponseBundle with response and metadata, or nil if error occurred.
    private func sendClaudeRequestFull(
        prompt: String,
        promptBackgroundInfo: String,
        temperature: Double,
        maxTokens: Int
    ) async -> AIResponseBundle? {
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let jsonData: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "system": promptBackgroundInfo,
            "messages": messages
        ]

        guard let url = URL(string: baseUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            print("Invalid request setup")
            return nil
        }

        var request = URLRequest(url: url)
        configureRequest(&request, httpBody: httpBody)

        return await executeRequest(request)
    }
    
    /// Executes an API request with retry logic for rate limits.
    private func executeRequest(_ request: URLRequest) async -> AIResponseBundle? {
        var retryCount = 0
        let maxRetries = 3
        // Quick print – shows method + URL + some headers
            print("=== URLRequest ===")
            print("Method:     \(request.httpMethod ?? "—")")
            print("URL:        \(request.url?.absoluteString ?? "—")")
            print("Headers:    \(request.allHTTPHeaderFields ?? [:])")
            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                print("Body (UTF-8):")
                print(bodyStr.prefix(1000))   // avoid flooding console with huge JSON
                if bodyStr.count > 1000 { print("... (truncated)") }
            } else {
                print("Body:       — (nil or not UTF-8)")
            }
            print("=================")
        
        while retryCount < maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid HTTP response")
                    return nil
                }
                
                if httpResponse.statusCode == 429 {
                    retryCount += 1
                    let delay = pow(2.0, Double(retryCount))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("HTTP error: Status code \(httpResponse.statusCode)")
                    
                    if let errorBody = String(data: data, encoding: .utf8) {
                           print("Claude error response: \(errorBody)")
                       }
                    return nil
                }
                
                //#if DEBUG
                if let raw = String(data: data, encoding: .utf8) {
                    print("Raw Claude response: \(raw)")
                } else {
                    print("Raw Claude response: Unable to decode as UTF-8")
                }
                //#endif
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let model = json["model"] as? String,
                      let contentArray = json["content"] as? [[String: Any]] else {
                    print("❌ Invalid Claude API response format")
                    return nil
                }

                let text = contentArray
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")

                guard let stopReason = json["stop_reason"] as? String,
                      let usage = json["usage"] as? [String: Any],
                      let inputTokens = usage["input_tokens"] as? Int,
                      let outputTokens = usage["output_tokens"] as? Int else {
                    print("❌ Missing usage or stop_reason in response")
                    return nil
                }

                let totalTokens = inputTokens + outputTokens
                let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int
                let cacheReadTokens = usage["cache_read_input_tokens"] as? Int
                
                let cachedTokens: Int? = {
                    if let creation = cacheCreationTokens, let read = cacheReadTokens {
                        return creation + read
                    } else if let creation = cacheCreationTokens {
                        return creation
                    } else if let read = cacheReadTokens {
                        return read
                    } else {
                        return nil
                    }
                }()

                // Token count and cost logging
                let estimatedCost = PromptCostEstimator.instance.estimateCost(model: model, promptTokens: inputTokens, completionTokens: outputTokens)
                let costString = String(format: "$%.4f", estimatedCost)
                print("📊 TOKENS - In: \(inputTokens) | Out: \(outputTokens) | Total: \(totalTokens) | Cost: \(costString)" + (cachedTokens != nil ? " | Cached: \(cachedTokens!)" : ""))

                return AIResponseBundle(
                    content: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelUsed: model,
                    finishReason: stopReason,
                    promptTokens: inputTokens,
                    completionTokens: outputTokens,
                    totalTokens: totalTokens,
                    cachedTokens: cachedTokens
                )
            } catch {
                print("Error calling Claude: \(error.localizedDescription)")
                return nil
            }
        }
        
        print("Max retries reached for request")
        return nil
    }
    public func generate_cached_response(
        prompt: String,
        cacheablePromptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle? {
        let config = validatedParameters(from: params)

    
        print("""
        Cached request:
        System (cacheable): \(cacheablePromptBackgroundInfo.prefix( 100))
        User: \(prompt)
        temperature: \(config.temperature), max_tokens: \(config.maxTokens)
        """)
    

        guard model == .claude35Sonnet || model == .claude3Opus || model == .claude3Haiku else {
            print("❌ Caching only supported on Claude 3.5 Sonnet / Opus / Haiku")
            return nil
        }

        let estimatedTokens = cacheablePromptBackgroundInfo.count / 4
        if estimatedTokens < 1024 {
            print("⚠️ Cacheable content only ~\(estimatedTokens) tokens (less than 1024)")
        }

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": cacheablePromptBackgroundInfo,
                        "cache_control": ["type": "ephemeral"]
                    ],
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ]
        ]

        let jsonData: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "messages": messages
        ]

        guard let url = URL(string: baseUrl),
              let httpBody = try? JSONSerialization.data(withJSONObject: jsonData) else {
            print("❌ JSON encoding or URL setup failed")
            return nil
        }

        var request = URLRequest(url: url)
        configureRequest(&request, httpBody: httpBody)
        
        let result = await executeRequest(request)

        if let result = result {
            print("✅ Received AIResponseBundle", result)
           // print(result)
           

        } else {
            print("❌ No response returned from Claude")
        }

        return result
    }
}

// MARK: - Supporting Types

/// Configuration parameters for Claude requests.
private struct ClaudeParameters {
    let temperature: Double
    let maxTokens: Int
}

// MARK: - Notes Reference
/// ClaudeModelAdapter implementation notes:
/// - Adapter for Anthropic's Claude API, swappable with GPT-4 or other models.
/// - Implements `ModelAdapter` protocol for AIProcessingCore integration.
/// - Uses Claude's Messages API with proper authentication headers.
/// - Supports configurable Claude models via `ClaudeModel` enum.
/// - Image analysis fetches and encodes images from URLs to base64.
/// - Includes rate limit handling with exponential backoff.
/// - Uses `os.log` for secure, privacy-aware logging.
/// - Validates parameters to ensure compliance with Claude API constraints.
