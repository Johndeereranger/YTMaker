//
//  AzureOpenAIModelAdapter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 8/21/25.
//
import Foundation


public class AzureOpenAIModelAdapter: ModelAdapter {
        private let model: AIModel
    private var deploymentName: String {
        switch model {
        case .azureGpt4o: return "gpt-4o"
        default: return "unknown"
        }
    }

    private var resourceName: String {
        switch model {
        case .azureGpt4o: return "bsmit-men3xaj2-swedencentral"//bsmit-melov4qh"
        default: return "unknown"
        }
    }
        private var apiKey: String { Secrets.azureAPIKey }
        
        public init(model: AIModel) {
            self.model = model
        }

    public func generate_response(prompt: String, promptBackgroundInfo: String, params: [String: Any]) async -> String {
        let temperature = params["temperature"] as? Double ?? 0.7
        let maxTokens = params["max_tokens"] as? Int ?? 500

        let endpoint = "https://\(resourceName).cognitiveservices.azure.com/openai/deployments/\(deploymentName)/chat/completions?api-version=2025-01-01-preview"
        //https://bsmit-men3xaj2-swedencentral.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": promptBackgroundInfo],
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let url = URL(string: endpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return "Error: Invalid request setup"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        //request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")

        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return "Error: Invalid Azure GPT response"
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    public func generate_batch_response(prompts: [String], promptBackgroundInfo: String) async -> [String] {
        return await withTaskGroup(of: String.self) { group in
            for prompt in prompts {
                group.addTask {
                    await self.generate_response(prompt: prompt, promptBackgroundInfo: promptBackgroundInfo, params: [:])
                }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }
    }

    public func generate_response_bundle(
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle? {
        let temperature = params["temperature"] as? Double ?? 0.7
        let maxTokens = params["max_tokens"] as? Int ?? 10000

        #if DEBUG
        print("""
        AzureOpenAIModelAdapter (bundle) request:
        System: \(promptBackgroundInfo)
        User: \(prompt)
        temperature: \(temperature), max_tokens: \(maxTokens)
        """)
        #endif

        return await sendAzureRequestFull(
            prompt: prompt,
            promptBackgroundInfo: promptBackgroundInfo,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func analyzeImageURL(
        url: String,
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any]
    ) async -> AIResponseBundle? {
        print(#function, "not implemented")
        return nil
    }
    
    private func sendAzureRequestFull(
        prompt: String,
        promptBackgroundInfo: String,
        temperature: Double,
        maxTokens: Int
    ) async -> AIResponseBundle? {
        let apiUrl = "https://\(resourceName).openai.azure.com/openai/deployments/\(deploymentName)/chat/completions?api-version=2024-03-01-preview"

        let jsonData: [String: Any] = [
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
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw response:\n\(raw)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let finishReason = choices.first?["finish_reason"] as? String,
                  let usage = json["usage"] as? [String: Any],
                  let promptTokens = usage["prompt_tokens"] as? Int,
                  let completionTokens = usage["completion_tokens"] as? Int,
                  let totalTokens = usage["total_tokens"] as? Int,
                    let requestId = json["id"] as? String,
                    let systemFingerprint = json["system_fingerprint"] as? String,
                    let createdTimestamp = json["created"] as? Int,
                    let modelUsed = json["model"] as? String,

                    let contentFilter = (choices.first?["content_filter_results"] as? [String: Any]),
                    let promptFilter = (json["prompt_filter_results"] as? [[String: Any]])?.first?["content_filter_results"] as? [String: Any]
            else {
                return nil
            }

            return AIResponseBundle(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                modelUsed: deploymentName, // Azure does not return model ID
                finishReason: finishReason,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: nil // Azure doesn't return cached_tokens
            )
        } catch {
            print("❌ Error calling Azure OpenAI: \(error)")
            return nil
        }
    }
}
