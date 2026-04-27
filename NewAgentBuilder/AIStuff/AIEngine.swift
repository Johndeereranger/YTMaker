

//
//  AIEngine.swift
//  Artifical
//
//  Created by Byron Smith on 3/24/25.
//
import Foundation

public class AIEngine {
    private var adapter: ModelAdapter = GPT4ModelAdapter()
    public init(model: AIModel = .gpt4o) {
        self.adapter = Self.adapterFor(model: model)
    }
   
    private static func adapterFor(model: AIModel) -> ModelAdapter {
        switch model.provider {
        case "openai":
            return GPT4ModelAdapter(model: model)
        case "claude":
            return ClaudeModelAdapter(model: model)
        case "azure":
            return AzureOpenAIModelAdapter(model: model)
        case "grok":
            return GPT4ModelAdapter(model: .gpt4o) // fallback until Grok supported
        default:
            return GPT4ModelAdapter(model: .gpt4o)
        }
    }

    public func run(
         prompt: String,
         promptBackgroundInfo: String,
         modelOverride: AIModel? = nil
     ) async -> String {
         let selectedAdapter = modelOverride.map(Self.adapterFor) ?? adapter
         return await selectedAdapter.generate_response(
             prompt: prompt,
             promptBackgroundInfo: promptBackgroundInfo,
             params: [:]
         )
     }

    public func runBatch(
         prompts: [String],
         promptBackgroundInfo: String,
         modelOverride: AIModel? = nil
     ) async -> [String] {
         let selectedAdapter = modelOverride.map(Self.adapterFor) ?? adapter
         return await selectedAdapter.generate_batch_response(
             prompts: prompts,
             promptBackgroundInfo: promptBackgroundInfo
         )
     }
    
    public func runWithBundle(
           prompt: String,
           promptBackgroundInfo: String,
           params: [String: Any] = [:],
           modelOverride: AIModel? = nil
       ) async -> AIResponseBundle? {
           let selectedAdapter = modelOverride.map(Self.adapterFor) ?? adapter
           return await selectedAdapter.generate_response_bundle(
               prompt: prompt,
               promptBackgroundInfo: promptBackgroundInfo,
               params: params
           )
       }
    
    public func analyzeImage(
        url: String,
        prompt: String,
        promptBackgroundInfo: String,
        params: [String: Any] = [:],
        modelOverride: AIModel? = nil
    ) async -> AIResponseBundle? {
        let selectedAdapter = modelOverride.map(Self.adapterFor) ?? adapter
        return await selectedAdapter.analyzeImageURL(
            url: url,
            prompt: prompt,
            promptBackgroundInfo: promptBackgroundInfo,
            params: params
        )
    }
    
    public func runWithCacheSupport(
        prompt: String,
        reusableContext: String,
        params: [String: Any] = [:],
        modelOverride: AIModel? = nil
    ) async -> AIResponseBundle? {
        let selectedAdapter = modelOverride.map(Self.adapterFor) ?? adapter
        
        if let claudeAdapter = selectedAdapter as? ClaudeModelAdapter {
            return await claudeAdapter.generate_cached_response(
                prompt: prompt,
                cacheablePromptBackgroundInfo: reusableContext,
                params: params
            )
        } else {
            // Fallback to regular run
            return await selectedAdapter.generate_response_bundle(
                prompt: prompt,
                promptBackgroundInfo: reusableContext,
                params: params
            )
        }
    }
}
