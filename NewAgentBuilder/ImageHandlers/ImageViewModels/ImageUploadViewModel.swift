//
//  ImageUploadViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//


import FirebaseStorage
import FirebaseFirestore
import UIKit
import SwiftUI
import UIKit
import UserInfoLibrary

@MainActor
class ImageUploadViewModel: ObservableObject {
    @Published var stagedImages: [UIImage] = [] // Dragged in, not yet uploaded
    @Published var uploadedPrompts: [ImagePrompt] = []

    private let promptManager = ImagePromptManager.instance
    private let firebaseImageManager = FirebaseImageManager.shared
    private let localImageManager = LocalImageManager.shared
    
    private var currentShortID: Int?
    var missingPromptCount: Int {
        uploadedPrompts.filter { $0.prompt.isEmpty }.count
    }

    init() {
//        Task {
//            await loadExistingPrompts()
//        }
    }
    
    func prepareShortIDCounterIfNeeded() async {
        if currentShortID == nil {
            currentShortID = try? await promptManager.nextShortID()
        }
    }

    func loadExistingPrompts() async {
        do {
            let prompts = try await promptManager.fetchAllPrompts()
            print("📦 Loaded prompts count: \(prompts.count)")
            
            self.uploadedPrompts = prompts
            for prompt in uploadedPrompts {
                print(prompt.id,prompt.originalFilename)
            }
        } catch {
            print("❌ Failed to load existing prompts: \(error)")
        }
    }

    func uploadAllImages() {
        Task {
            for image in stagedImages {
                await uploadImage(image)
            }
            stagedImages.removeAll()
        }
    }
    
    
    func removeStagedImage(_ image: UIImage) {
        if let index = stagedImages.firstIndex(of: image) {
            stagedImages.remove(at: index)
        }
    }
    
    func uploadStagedImagesWithShortIDs() async {
        do {
            let startingID = try await promptManager.nextShortID()
            for (index, image) in stagedImages.enumerated() {
                await uploadImage(image, withName: nil, shortID: startingID + index)
            }
            stagedImages.removeAll()
        } catch {
            print("❌ Failed to assign shortIDs: \(error)")
        }
    }
    func uploadImage(_ image: UIImage, withName name: String? = nil, shortID: Int) async {
        let imageID = UUID().uuidString
        let imageName = name ?? UUID().uuidString
        let imagePath = "stickImages/\(imageName).jpg"

        do {
            _ = try await localImageManager.saveImageLocally(image, withName: "\(imageName).jpg")
            let url = try await firebaseImageManager.storeImage(image, atPath: imagePath)

            let prompt = ImagePrompt(
                id: imageID,
                originalFilename: name ?? "No Name",
                prompt: "",
                url: url,
                reusedBy: [],
                status: .pending,
                createdAt: Date(),
                shortID: shortID
            )

            try await promptManager.savePrompt(prompt)
            uploadedPrompts.append(prompt)

        } catch {
            print("❌ Upload failed for \(imageID): \(error)")
        }
    }
    
    func uploadImageN(_ image: UIImage, withName name: String? = nil) async {
        await prepareShortIDCounterIfNeeded()

        guard let shortID = currentShortID else {
            print("❌ Failed to resolve shortID")
            return
        }

        currentShortID! += 1
        await uploadImage(image, withName: name, shortID: shortID)
    }

    func uploadImage(_ image: UIImage, withName name: String? = nil) async {
        let imageID = UUID().uuidString
        let imageName = name ?? UUID().uuidString
        let imagePath = "stickImages/\(imageName).jpg"

        do {
            // ✅ 1. Save locally
            _ = try await localImageManager.saveImageLocally(image, withName: "\(imageName).jpg")

            // ✅ 2. Upload to Firebase Storage
            let url = try await firebaseImageManager.storeImage(image, atPath: imagePath)

            // ✅ 3. Get next short ID
            let shortID = try await promptManager.nextShortID()

            // ✅ 4. Create metadata object
            let prompt = ImagePrompt(
                id: imageID,
                originalFilename: name ?? "No Name",
                prompt: "", // GPT prompt generated later
                url: url,
                reusedBy: [],
                status: .pending,
                createdAt: Date(),
                shortID: shortID
            )

            // ✅ 5. Save metadata to Firestore
            try await promptManager.savePrompt(prompt)

            // ✅ 6. Add to local list
            uploadedPrompts.append(prompt)

        } catch {
            print("❌ Upload failed for \(imageID): \(error)")
        }
    }

    func deletePrompt(_ prompt: ImagePrompt) async {
        do {
            try await promptManager.deletePrompt(id: prompt.id)
            uploadedPrompts.removeAll { $0.id == prompt.id }
        } catch {
            print("❌ Failed to delete prompt \(prompt.id): \(error)")
        }
    }
    func generateMissingPrompts() async {
        for i in uploadedPrompts.indices {
            if uploadedPrompts[i].prompt.isEmpty {
                do {
                    let image = uploadedPrompts[i]
                    let gptPrompt = try await GPTPromptGenerator.generatePrompt(from: image.url)
                    uploadedPrompts[i].prompt = gptPrompt

                    try await promptManager.savePrompt(uploadedPrompts[i])
                    print("✅ Prompt updated for \(image.originalFilename ?? image.id)")

                } catch {
                    print("❌ Failed to generate prompt for \(uploadedPrompts[i].id): \(error)")
                }
            }
        }
    }

    func reserveShortIDRange(count: Int) async throws -> Int {
        let starting = try await promptManager.nextShortID()
        currentShortID = starting + count
        return starting
    }
}
