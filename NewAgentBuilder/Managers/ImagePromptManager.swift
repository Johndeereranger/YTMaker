//
//  ImagePromptManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//

import Foundation
import FirebaseFirestore

class ImagePromptManager {
    static let instance = ImagePromptManager()
    private let db = Firestore.firestore()
    private let collection = "imagePrompts"
    private var cachedPrompts: [ImagePrompt]? = nil
    private init() {}

    // Fetch all image prompts
    func fetchAllPrompts() async throws -> [ImagePrompt] {
            // Return cached if available
            if let cached = cachedPrompts {
                return cached
            }

            return try await fetchAndCachePrompts()
        }
    private func fetchAndCachePrompts() async throws -> [ImagePrompt] {
          let snapshot = try await db.collection(collection).getDocuments()
          let prompts = snapshot.documents.compactMap { ImagePrompt(document: $0) }

          self.cachedPrompts = prompts
          

          return prompts
      }
    
    func forceRefreshPrompts() async throws -> [ImagePrompt] {
        return try await fetchAndCachePrompts()
    }
//    func fetchAllPrompts() async throws -> [ImagePrompt] {
//        let snapshot = try await db.collection(collection).getDocuments()
//        //try await printAllTags()
//        return snapshot.documents.compactMap { ImagePrompt(document: $0) }
//    }
    
    func printAllTags() async throws {
        print("🔥 CALLED printAllTags from: \(Thread.callStackSymbols.joined(separator: "\n"))")
        let allprompts = try await fetchAllPrompts()
        print(#function, allprompts.count)
        let sortedPrompts = allprompts.sorted { $0.shortID < $1.shortID }
        var totalString = ""
        for prompt in sortedPrompts {
            let promptString = "\(prompt.shortID) - \(prompt.promptTags)\n"
            totalString += promptString
        }
        print(totalString)
    }

    // Fetch a specific prompt
    func fetchPrompt(withID id: String) async throws -> ImagePrompt? {
        let doc = try await db.collection(collection).document(id).getDocument()
        return ImagePrompt(document: doc)
    }

    // Save or update an image prompt
    func savePrompt(_ prompt: ImagePrompt) async throws {
        var data: [String: Any] = [
            "id": prompt.id,
            "prompt": prompt.prompt,
            "detailedPrompt": prompt.detailedPrompt,
            "promptTags": prompt.promptTags,
            "url": prompt.url,
            "originalFilename": prompt.originalFilename ?? "",
            "reusedBy": prompt.reusedBy,
            "status": prompt.status.rawValue,
            "createdAt": Timestamp(date: prompt.createdAt),
            "shortID": prompt.shortID
        ]


        // Optional fields
        if let started = prompt.processingStartedAt {
            data["processingStartedAt"] = Timestamp(date: started)
        }
        if let completed = prompt.processingCompletedAt {
            data["processingCompletedAt"] = Timestamp(date: completed)
        }
        if let message = prompt.errorMessage {
            data["errorMessage"] = message
        }
        if let attemptIndex = prompt.attemptIndex {
            data["attemptIndex"] = attemptIndex
        }
        if let seed = prompt.seed {
            data["seed"] = seed
        }
        if let style = prompt.style {
            data["style"] = style
        }
        if let guidance = prompt.guidance {
            data["guidance"] = guidance
        }
        if let steps = prompt.samplingSteps {
            data["samplingSteps"] = steps
        }
        if let extras = prompt.otherParameters {
            data["otherParameters"] = extras
        }

        try await db.collection(collection).document(prompt.id).setData(data)
    }

    // Batch save
    func saveAll(_ prompts: [ImagePrompt]) async throws {
        let batch = db.batch()
        for prompt in prompts {
            var data: [String: Any] = [
                "id": prompt.id,
                "prompt": prompt.prompt,
                "detailedPrompt": prompt.detailedPrompt,
                "promptTags": prompt.promptTags,
                "url": prompt.url,
                "originalFilename": prompt.originalFilename ?? "",
                "reusedBy": prompt.reusedBy,
                "status": prompt.status.rawValue,
                "createdAt": Timestamp(date: prompt.createdAt),
                "shortID": prompt.shortID
            ]

            if let started = prompt.processingStartedAt {
                data["processingStartedAt"] = Timestamp(date: started)
            }
            if let completed = prompt.processingCompletedAt {
                data["processingCompletedAt"] = Timestamp(date: completed)
            }
            if let message = prompt.errorMessage {
                data["errorMessage"] = message
            }
            if let attemptIndex = prompt.attemptIndex {
                data["attemptIndex"] = attemptIndex
            }
            if let seed = prompt.seed {
                data["seed"] = seed
            }
            if let style = prompt.style {
                data["style"] = style
            }
            if let guidance = prompt.guidance {
                data["guidance"] = guidance
            }
            if let steps = prompt.samplingSteps {
                data["samplingSteps"] = steps
            }
            if let extras = prompt.otherParameters {
                data["otherParameters"] = extras
            }

            let ref = db.collection(collection).document(prompt.id)
            batch.setData(data, forDocument: ref)
        }
        try await batch.commit()
    }

    // Delete an image prompt by ID
    func deletePrompt(id: String) async throws {
        try await db.collection(collection).document(id).delete()
    }

    // Compute the next shortID based on existing ones
    func nextShortID() async throws -> Int {
        let prompts = try await fetchAllPrompts()
        let maxID = prompts.map(\.shortID).max() ?? 0
        return maxID + 1
    }
    // MARK: - Create Prompt from Scenario-generated Image
    func createPrompt(
        from image: UIImage,
        filename: String,
        prompt: String,
        url: String,
        shortID: Int,
        beatId: UUID,
        seed: String?,
        style: String?,
        guidance: Double?,
        samplingSteps: Int?,
        attemptIndex: Int?
    ) async throws -> ImagePrompt {
        let prompt = ImagePrompt(
            id: UUID().uuidString,
            originalFilename: filename,
            prompt: prompt, // To be filled by GPT
            detailedPrompt: "",
            promptTags: "",
            url: url,
            sourceSoundBeatId: beatId.uuidString,
            reusedBy: [beatId.uuidString],
            status: .succeeded,
            createdAt: Date(),
            shortID: shortID,
            processingStartedAt: nil,
            processingCompletedAt: Date(),
            errorMessage: nil,
            attemptIndex: attemptIndex,
            seed: seed,
            style: style,
            guidance: guidance,
            samplingSteps: samplingSteps,
            otherParameters: nil
        )
        
        try await savePrompt(prompt)
        return prompt
    }
    // MARK: - Fetch prompts for a specific beat
    func fetchPrompts(for beatId: UUID) async throws -> [ImagePrompt] {
        let snapshot = try await db.collection(collection)
            .whereField("reusedBy", arrayContains: beatId.uuidString)
            .getDocuments()
        return snapshot.documents.compactMap { ImagePrompt(document: $0) }
    }
    func appendReusedBy(promptId: String, beatId: String) async throws {
        let ref = db.collection("imagePrompts").document(promptId)
        try await ref.updateData([
            "reusedBy": FieldValue.arrayUnion([beatId])
        ])
    }
    
    // MARK: - Update detailedPrompt for a given image prompt
    func updateDetailedPrompt(for promptId: String, detailedPrompt: String) async throws {
        let ref = db.collection(collection).document(promptId)
        try await ref.updateData([
            "detailedPrompt": detailedPrompt
        ])
    }
    
    func updatePromptTags(for promptId: String, promptTags: String) async throws {
        let ref = db.collection(collection).document(promptId)
        try await ref.updateData([
            "promptTags": promptTags
        ])
    }
    func hidePrompt(for promptId: String) async throws {
        let ref = db.collection(collection).document(promptId)
        try await ref.updateData([
            "isHidden": true
        ])
    }
    func unHidePrompt(for promptId: String ) async throws {
        let ref = db.collection(collection).document(promptId)
        try await ref.updateData([
            "isHidden": false
        ])
    }

}
