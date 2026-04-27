//
//  ImagePrompt.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//
//import Foundation
//
//import Foundation
//import FirebaseFirestore
//
//struct ImagePrompt: Identifiable, Codable, Equatable, Hashable {
//    var id: String
//    var originalFilename: String?// typically the filename or UUID string
//    var prompt: String
//    var url: String
//    var reusedBy: [String]
//    var status: PromptStatus
//    var createdAt: Date
//    var shortID: Int
//
//    // MARK: - Main Init
//    init(
//        id: String = UUID().uuidString,
//        originalFilename: String? = nil,
//        prompt: String = "",
//        url: String,
//        reusedBy: [String] = [],
//        status: PromptStatus = .new,
//        createdAt: Date = Date(),
//        shortID: Int = 0
//    ) {
//        self.id = id
//        self.originalFilename = originalFilename
//        self.prompt = prompt
//        self.url = url
//        self.reusedBy = reusedBy
//        self.status = status
//        self.createdAt = createdAt
//        self.shortID = shortID
//    }
//
//    // MARK: - Firestore Init
//    init?(document: DocumentSnapshot) {
//        guard let data = document.data(),
//              let id = data["id"] as? String,
//              let url = data["url"] as? String,
//              let prompt = data["prompt"] as? String
//        else {
//            return nil
//        }
//
//        self.id = id
//        self.url = url
//        self.prompt = prompt
//        self.reusedBy = data["reusedBy"] as? [String] ?? []
//        
//        if let statusString = data["status"] as? String,
//           let status = PromptStatus(rawValue: statusString) {
//            self.status = status
//        } else {
//            self.status = .new
//        }
//        
//        if let imageName = data["originalFilename"] as? String {
//           self.originalFilename = imageName
//            
//        } else {
//            self.originalFilename = nil
//        }
//
//        if let ts = data["createdAt"] as? Timestamp {
//            self.createdAt = ts.dateValue()
//        } else {
//            self.createdAt = Date()
//        }
//
//        self.shortID = data["shortID"] as? Int ?? 0
//    }
//
//    static func == (lhs: ImagePrompt, rhs: ImagePrompt) -> Bool {
//        lhs.id == rhs.id
//    }
//
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//    }
//}
//enum PromptStatus: String, Codable {
//    case new
//    case reused
//    case pendingReview
//}
import Foundation
import FirebaseFirestore

// MARK: - Model
struct ImagePrompt: Identifiable, Codable, Equatable, Hashable {
    var id: String                               // Unique ID
    var originalFilename: String               // Original filename or UUID
    var prompt: String                          // Full prompt text
    var detailedPrompt: String
    var promptTags: String
    var url: String                             // Image storage URL
    var sourceSoundBeatId: String?              // This is the sound Beat id that was used to create the image.
    var reusedBy: [String]                      // SoundBeat IDs using this image
    var status: ImageStatus                     // pending, processing, succeeded, etc.
    var createdAt: Date                         // Creation timestamp
    var shortID: Int                            // Human-readable ID
    var isHidden: Bool = false

    // Generation process tracking
    var processingStartedAt: Date?              // When generation started
    var processingCompletedAt: Date?            // When generation completed
    var errorMessage: String?                   // For failed generations

    // Generation metadata
    var attemptIndex: Int?                      // For batches of images
    var seed: String?                           // Generation seed
    var style: String?                          // Style used (optional)
    var guidance: Double?                       // Classifier-free guidance
    var samplingSteps: Int?                     // Inference step count
    var otherParameters: [String: String]?      // Extra metadata if needed

    // MARK: - Init
    init(
        id: String = UUID().uuidString,
        originalFilename: String,
        prompt: String = "",
        detailedPrompt: String = "",
        promptTags: String = "",
        url: String,
        sourceSoundBeatId: String? = nil,
        reusedBy: [String] = [],
        status: ImageStatus = .pending,
        createdAt: Date = Date(),
        shortID: Int = 0,
        processingStartedAt: Date? = nil,
        processingCompletedAt: Date? = nil,
        errorMessage: String? = nil,
        attemptIndex: Int? = nil,
        seed: String? = nil,
        style: String? = nil,
        guidance: Double? = nil,
        samplingSteps: Int? = nil,
        otherParameters: [String: String]? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.prompt = prompt
        self.detailedPrompt = detailedPrompt
        self.promptTags = promptTags
        self.url = url
        self.sourceSoundBeatId = sourceSoundBeatId
        self.reusedBy = reusedBy
        self.status = status
        self.createdAt = createdAt
        self.shortID = shortID
        self.processingStartedAt = processingStartedAt
        self.processingCompletedAt = processingCompletedAt
        self.errorMessage = errorMessage
        self.attemptIndex = attemptIndex
        self.seed = seed
        self.style = style
        self.guidance = guidance
        self.samplingSteps = samplingSteps
        self.otherParameters = otherParameters
        self.isHidden = isHidden
    }

    // MARK: - Firestore Init
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let id = data["id"] as? String,
              let url = data["url"] as? String,
              let prompt = data["prompt"] as? String
        else {
            return nil
        }

        self.id = id
        self.url = url
        self.prompt = prompt
        self.promptTags = data["promptTags"] as? String ?? ""
        self.detailedPrompt = data["detailedPrompt"] as? String ?? ""
        self.reusedBy = data["reusedBy"] as? [String] ?? []
        self.originalFilename = data["originalFilename"] as? String ?? ""
        self.shortID = data["shortID"] as? Int ?? 0
        self.isHidden = data["isHidden"] as? Bool ?? false

        if let statusRaw = data["status"] as? String,
           let parsedStatus = ImageStatus(rawValue: statusRaw) {
            self.status = parsedStatus
        } else {
            self.status = .pending
        }

        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let sourceSoundBeatId = data["sourceSoundBeatId"] as? String {
            self.sourceSoundBeatId = sourceSoundBeatId
        }

        if let ts = data["processingStartedAt"] as? Timestamp {
            self.processingStartedAt = ts.dateValue()
        }

        if let ts = data["processingCompletedAt"] as? Timestamp {
            self.processingCompletedAt = ts.dateValue()
        }

        self.errorMessage = data["errorMessage"] as? String
        self.attemptIndex = data["attemptIndex"] as? Int
        self.seed = data["seed"] as? String
        self.style = data["style"] as? String
        self.guidance = data["guidance"] as? Double
        self.samplingSteps = data["samplingSteps"] as? Int
        self.otherParameters = data["otherParameters"] as? [String: String]
    }

    // MARK: - Hashing & Equality
    static func == (lhs: ImagePrompt, rhs: ImagePrompt) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Status Enum
enum ImageStatus: String, Codable {
    case pending
    case processing
    case succeeded
    case failed
    case active
    case archived
}


extension ImagePrompt {
    var allTagsString: String {
        let cleanJSON = promptTags
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse tags: \(cleanJSON)")
            return ""
        }

        var result: [String] = []

        for value in json.values {
            if let string = value as? String {
                result.append(string)
            } else if let array = value as? [String] {
                result.append(contentsOf: array)
            }
        }

        return result.joined(separator: " ")
    }
}
