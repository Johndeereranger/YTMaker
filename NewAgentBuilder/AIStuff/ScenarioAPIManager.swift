//
//  ScenarioAPIManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/16/25.
//


import Foundation
import SwiftUI
import CryptoKit

struct GeneratedImageResult {
    let url: URL
    let seed: String
}



class ScenarioAPIManager {
    // MARK: - Properties
    private let baseURL = "https://api.cloud.scenario.com/v1"
    private let apiKey: String
    private let apiSecret: String
    private let session: URLSession
    
    // MARK: - Initialization
    init(key: String, secret: String, session: URLSession = .shared) {
        self.apiKey = key
        self.apiSecret = secret
        self.session = session
    }
    
    // MARK: - Models
    struct ImageGenerationRequest: Encodable {
        let modelId: String
        let prompt: String
        let numInferenceSteps: Int?
        let numSamples: Int?
        let guidance: Double?
        let width: Int?
        let height: Int?
        let negativePrompt: String?
        
        enum CodingKeys: String, CodingKey {
            case modelId
            case prompt
            case numInferenceSteps
            case numSamples
            case guidance
            case width
            case height
            case negativePrompt
        }
    }
    
    struct SeededImageGenerationRequest: Encodable {
        let modelId: String
        let prompt: String
        let numInferenceSteps: Int?
        let numSamples: Int?
        let guidance: Double?
        let width: Int?
        let height: Int?
        let negativePrompt: String?
        let seed: String?
        
        enum CodingKeys: String, CodingKey {
            case modelId
            case prompt
            case numInferenceSteps
            case numSamples
            case guidance
            case width
            case height
            case negativePrompt
            case seed
        }
    }
    
    struct ImageGenerationResponse: Decodable {
        struct Job: Decodable {
            let jobId: String
        }
        let job: Job
    }
    
    struct JobStatusResponse: Decodable {
        let job: Job
        
        struct Job: Decodable {
            let jobId: String
            let status: String
            let metadata: Metadata?
            
            struct Metadata: Decodable {
                let inferenceId: String?
                let assetIds: [String]?
                
                // Add CodingKeys to handle optional fields
                private enum CodingKeys: String, CodingKey {
                    case inferenceId, assetIds
                }
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    inferenceId = try container.decodeIfPresent(String.self, forKey: .inferenceId)
                    assetIds = try container.decodeIfPresent([String].self, forKey: .assetIds) ?? []
                }
            }
        }
    }
    
    // MARK: - API Methods
    func generateImage(
        prompt: String,
        modelId: String = "hGvp7AwKAQugXTY5UnK7U2e4",
        numInferenceSteps: Int? = 30,
        numSamples: Int? = 1,
        guidance: Double? = 7.5,
        width: Int? = 1024,
        height: Int? = 1024,
        negativePrompt: String? = "ugly, bad, low quality, blurry"
    ) async throws -> [URL] {
        let endpoint = "\(baseURL)/generate/txt2img"
        guard let url = URL(string: endpoint) else {
            throw ScenarioAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Basic Auth exactly as shown in the Python example
        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        // Set headers
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let generationRequest = ImageGenerationRequest(
            modelId: modelId,
            prompt: prompt,
            numInferenceSteps: numInferenceSteps,
            numSamples: numSamples,
            guidance: guidance,
            width: width,
            height: height,
            negativePrompt: negativePrompt
        )
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(generationRequest)
            
            print("🔑 Auth Header: \(request.value(forHTTPHeaderField: "Authorization") ?? "none")")
            print("🔑 API Key Header: \(request.value(forHTTPHeaderField: "X-Api-Key") ?? "none")")
            
            let (data, response) = try await session.data(for: request)
            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Response:\n\(raw)")
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ScenarioAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            
            let decodedResponse = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
            let jobId = decodedResponse.job.jobId
            
            // Poll job status
            return try await pollJobStatus(jobId: jobId)
        } catch {
            throw ScenarioAPIError.networkError(error)
        }
    }
    
    func generateImageWithSeed(
        prompt: String,
        modelId: String = "hGvp7AwKAQugXTY5UnK7U2e4",
        numInferenceSteps: Int? = 30,
        numSamples: Int? = 1,
        guidance: Double? = 7.5,
        width: Int? = 1024,
        height: Int? = 1024,
        negativePrompt: String? = "ugly, bad, low quality, blurry",
        seed: String? = nil
    ) async throws -> [GeneratedImageResult] {
        let endpoint = "\(baseURL)/generate/txt2img"
        guard let url = URL(string: endpoint) else {
            throw ScenarioAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        // Use same struct you're already using, but seed must be added
        let generationRequest = SeededImageGenerationRequest(
            modelId: modelId,
            prompt: prompt,
            numInferenceSteps: numInferenceSteps,
            numSamples: numSamples,
            guidance: guidance,
            width: width,
            height: height,
            negativePrompt: negativePrompt,
            seed: seed
        )

        request.httpBody = try JSONEncoder().encode(generationRequest)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ScenarioAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        let jobId = decoded.job.jobId

        let urlsAndSeeds = try await pollJobStatusWithSeeds(jobId: jobId)
        return urlsAndSeeds
    }
    func pollJobStatusWithSeeds(jobId: String) async throws -> [GeneratedImageResult] {
        let endpoint = "\(baseURL)/jobs/\(jobId)"
        guard let url = URL(string: endpoint) else {
            throw ScenarioAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Basic auth
        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        var status = "queued"
        var assetIds: [String] = []
        
        // Try polling for up to 5 minutes (60 x 5 seconds)
        for _ in 0..<60 {
            let (data, response) = try await session.data(for: request)
            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Polling response:\n\(raw)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ScenarioAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            
            do {
                let jobResponse = try JSONDecoder().decode(JobStatusResponse.self, from: data)
                status = jobResponse.job.status
                
                print("📊 Job Status: \(status)")
                
                // Check if we have asset IDs yet
                if let metadata = jobResponse.job.metadata,
                   let ids = metadata.assetIds, !ids.isEmpty {
                    assetIds = ids
                    break // We have the assets, exit the loop
                }
                
                if status == "success" {
                    break // Job is complete, exit the loop
                } else if status == "failure" {
                    throw ScenarioAPIError.jobFailed // Job failed, throw error
                }
                
                // Wait 5 seconds before polling again
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                print("⚠️ Error decoding job response: \(error)")
                throw error
            }
        }
        
        // If we reached here without getting assets and status is still not success, throw timeout error
        if status != "success" && assetIds.isEmpty {
            throw ScenarioAPIError.jobTimeout
        }
        
        // Now fetch metadata for each asset to get the seeds
        var results: [GeneratedImageResult] = []
        
        for assetId in assetIds {
            // Fetch the asset metadata to get the seed
            let assetMetadataURL = URL(string: "\(baseURL)/assets/\(assetId)")!
            var metadataRequest = URLRequest(url: assetMetadataURL)
            metadataRequest.httpMethod = "GET"
            metadataRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
            
            let (metadataData, _) = try await session.data(for: metadataRequest)
            
            // Try to extract the seed from the metadata
            if let json = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
               let assetInfo = json["asset"] as? [String: Any],
               let metadata = assetInfo["metadata"] as? [String: Any],
               let seed = metadata["seed"] as? String {
                
                let assetURL = URL(string: "https://app.scenario.com/assets/\(assetId)")!
                results.append(GeneratedImageResult(url: assetURL, seed: seed))
            } else {
                // Fallback if we can't extract the seed
                let assetURL = URL(string: "https://app.scenario.com/assets/\(assetId)")!
                results.append(GeneratedImageResult(url: assetURL, seed: "unknown"))
            }
        }
        
        return results
    }
    func pollJobStatusWithSeedss(jobId: String) async throws -> [GeneratedImageResult] {
        var attempts = 0

        while attempts < 30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let endpoint = "\(baseURL)/jobs/\(jobId)"
            guard let url = URL(string: endpoint) else {
                throw ScenarioAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let credentials = "\(apiKey):\(apiSecret)"
            let base64Credentials = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)

            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Polling response:\n\(raw)")
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ScenarioAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            let jobResponse = try JSONDecoder().decode(JobStatusResponse.self, from: data)
            let job = jobResponse.job
            let status = job.status

            print("📊 Job Status: \(status)")

            if status == "success", let assetIds = job.metadata?.assetIds, !assetIds.isEmpty {
                        // Instead of immediately returning with "unknown" seeds
                        // First fetch each asset to get its metadata including the seed
                        var results: [GeneratedImageResult] = []
                        
                        for assetId in assetIds {
                            // Fetch the asset metadata to get the seed
                            let assetMetadataURL = URL(string: "\(baseURL)/assets/\(assetId)")!
                            var metadataRequest = URLRequest(url: assetMetadataURL)
                            metadataRequest.httpMethod = "GET"
                            metadataRequest.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                            
                            let (metadataData, _) = try await session.data(for: metadataRequest)
                            
                            // Try to extract the seed from the metadata
                            if let json = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                               let assetInfo = json["asset"] as? [String: Any],
                               let metadata = assetInfo["metadata"] as? [String: Any],
                               let seed = metadata["seed"] as? String {
                                
                                let assetURLString = "\(baseURL)/assets/\(assetId)/content"
                                guard let url = URL(string: assetURLString) else {
                                    throw ScenarioAPIError.invalidURL
                                }
                                
                                results.append(GeneratedImageResult(url: url, seed: seed))
                            } else {
                                // Fallback if we can't extract the seed
                                let assetURLString = "\(baseURL)/assets/\(assetId)/content"
                                guard let url = URL(string: assetURLString) else {
                                    throw ScenarioAPIError.invalidURL
                                }
                                
                                results.append(GeneratedImageResult(url: url, seed: "unknown"))
                            }
                        }
                        
                        return results
                    }


            if status == "failure" {
                throw ScenarioAPIError.jobFailed
            }

            attempts += 1
        }

        throw ScenarioAPIError.jobTimeout
    }
  

    private func createSignature(secret: String, dateString: String) -> String {
        // Create a signature string based on the API secret and date
        let stringToSign = "SCENARIO-HMAC-SHA256\n\(dateString)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        
        // Format according to AWS Signature V4 style requirements
        let authHeader = "SCENARIO-HMAC-SHA256 " +
                         "Credential=\(apiKey), " +
                         "SignedHeaders=content-type;host;x-amz-date, " +
                         "Signature=\(Data(signature).base64EncodedString())"
        
        print("🔑 Auth Header: \(authHeader)")
        return authHeader
    }
    
    
    private func pollJobStatus(jobId: String) async throws -> [URL] {
        let endpoint = "\(baseURL)/jobs/\(jobId)"
        guard let url = URL(string: endpoint) else {
            throw ScenarioAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Basic auth
        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        print("🔑 Polling Auth Header: \(authHeader)")
        
        var status = "queued"
        var assetIds: [String] = []
        
        // Try polling for up to 5 minutes (60 x 5 seconds)
        for _ in 0..<60 {
            let (data, response) = try await session.data(for: request)
            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Polling response:\n\(raw)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ScenarioAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            
            do {
                let jobResponse = try JSONDecoder().decode(JobStatusResponse.self, from: data)
                status = jobResponse.job.status
                
                print("📊 Current job status: \(status)")
                
                // Check if we have asset IDs yet
                if let metadata = jobResponse.job.metadata,
                   let ids = metadata.assetIds, !ids.isEmpty {
                    assetIds = ids
                    break // We have the assets, exit the loop
                }
                
                if status == "success" {
                    break // Job is complete, exit the loop
                } else if status == "failure" {
                    throw ScenarioAPIError.jobFailed // Job failed, throw error
                }
                
                // Wait 5 seconds before polling again
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                print("⚠️ Error decoding job response: \(error)")
                throw error
            }
        }
        
        // If we reached here without getting assets and status is still not success, throw timeout error
        if status != "success" && assetIds.isEmpty {
            throw ScenarioAPIError.jobTimeout
        }
        
        // Convert asset IDs to URLs
        let imageURLs = assetIds.compactMap { assetId in
            URL(string: "https://app.scenario.com/assets/\(assetId)")
        }
        
        return imageURLs
    }
    
    // Fetch image as UIImage

//    // IMPORTANT: Updated to use Basic Auth for fetching images
//    func fetchImage(from url: URL) async throws -> UIImage {
//        var request = URLRequest(url: url)
//        
//        // Use Basic Auth for consistency with other API calls
//        let credentials = "\(apiKey):\(apiSecret)"
//        let base64Credentials = Data(credentials.utf8).base64EncodedString()
//        let authHeader = "Basic \(base64Credentials)"
//        
//        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
//        request.setValue("application/json", forHTTPHeaderField: "accept")
//        
//        print("🔑 Fetch Image Auth Header: \(authHeader)")
//        print("🖼️ Fetching image from URL: \(url)")
//        
//        do {
//            let (data, response) = try await session.data(for: request)
//            
//            guard let httpResponse = response as? HTTPURLResponse,
//                  (200...299).contains(httpResponse.statusCode) else {
//                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
//                print("❌ HTTP error during image fetch: \(statusCode)")
//                throw ScenarioAPIError.invalidResponse
//            }
//            
//            guard let image = UIImage(data: data) else {
//                print("❌ Could not convert data to image")
//                throw ScenarioAPIError.invalidImageData
//            }
//            
//            print("✅ Successfully fetched image")
//            return image
//        } catch {
//            print("❌ Image fetch error: \(error)")
//            throw error
//        }
//    }
    
    // Main function to fetch image that tries multiple approaches
    func fetchImage(from originalUrl: URL) async throws -> UIImage {
        // Generate all possible URL formats to try
        let urlsToTry = generateUrlVariations(from: originalUrl)
        print("🔍 Will try \(urlsToTry.count) different URL formats for asset")
        
        // Try each URL format until one works
        var lastError: Error = ScenarioAPIError.invalidURL
        
        for (index, url) in urlsToTry.enumerated() {
            print("🔗 Attempt \(index+1)/\(urlsToTry.count): \(url)")
            
            do {
                // First try the direct image fetch
                return try await fetchImageWithBasicAuth(from: url)
            } catch let error as ScenarioAPIError {
                if case .invalidImageData = error,
                   url.absoluteString.contains("/assets/") && !url.absoluteString.contains("/content") {
                    // If this is the metadata endpoint returning JSON (not an image)
                    // Try to extract the download URL from the JSON and use that
                    print("📋 This might be a metadata endpoint, trying to extract download URL")
                    do {
                        return try await fetchImageFromMetadata(from: url)
                    } catch {
                        print("❌ Failed to extract image from metadata: \(error)")
                    }
                }
                
                print("❌ URL format \(index+1) failed: \(error)")
                lastError = error
                // Continue to next URL format
            } catch {
                print("❌ URL format \(index+1) failed: \(error)")
                lastError = error
                // Continue to next URL format
            }
        }
        
        // If we get here, all URL formats failed
        print("❌ All URL formats failed. Last error: \(lastError)")
        throw lastError
    }

    // Generate different URL formats to try
    private func generateUrlVariations(from url: URL) -> [URL] {
        // Extract the asset ID from the URL path
        let assetId = url.lastPathComponent
        
        // Original URL is always the first to try
        var urlsToTry = [url]
        
        // Add additional URL formats if this looks like an asset ID
        if assetId.hasPrefix("asset_") {
            let additionalUrls: [URL?] = [
                // API formats
                URL(string: "https://api.cloud.scenario.com/v1/assets/\(assetId)"),
                URL(string: "https://api.cloud.scenario.com/v1/assets/\(assetId)/content"),
                URL(string: "https://api.cloud.scenario.com/v1/assets/\(assetId)/download"),
                
                // Web app formats
                URL(string: "https://app.scenario.com/assets/\(assetId)"),
                URL(string: "https://app.scenario.com/assets/\(assetId)/content"),
                URL(string: "https://app.scenario.com/assets/\(assetId)/download"),
                
                // Additional formats with different domains
                URL(string: "https://assets.scenario.com/v1/assets/\(assetId)"),
                URL(string: "https://cdn.scenario.com/v1/assets/\(assetId)")
            ]
            
            // Add only valid URLs
            urlsToTry.append(contentsOf: additionalUrls.compactMap { $0 })
        }
        
        return urlsToTry
    }

    // Fetch with Basic Auth
    private func fetchImageWithBasicAuth(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        
        // Use Basic Auth
        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("image/*", forHTTPHeaderField: "Accept") // Accept any image format
        
        print("🔑 Auth Header: \(authHeader)")
        print("🌐 URL: \(url)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Debug the response
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode)")
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                print("📡 Content type: \(contentType)")
                print("📦 Data size: \(data.count) bytes")
                
                // Check for HTTP errors
                if httpResponse.statusCode == 404 {
                    throw ScenarioAPIError.assetNotFound
                } else if httpResponse.statusCode == 403 {
                    // Try to extract message from the response
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("⚠️ 403 Forbidden response: \(errorText)")
                    }
                    throw ScenarioAPIError.httpError(statusCode: httpResponse.statusCode)
                } else if httpResponse.statusCode != 200 {
                    throw ScenarioAPIError.httpError(statusCode: httpResponse.statusCode)
                }
                
                // Check if we got JSON instead of an image
                if contentType.contains("application/json") {
                    throw ScenarioAPIError.invalidImageData
                }
            }
            
            // Try to create an image from the data
            guard let image = UIImage(data: data) else {
                throw ScenarioAPIError.invalidImageData
            }
            
            print("✅ Successfully fetched image: \(image.size.width) x \(image.size.height)")
            return image
        } catch {
            print("❌ Fetch error: \(error)")
            throw error
        }
    }

    // Extract image URL from metadata and fetch it
    private func fetchImageFromMetadata(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        
        // Use Basic Auth
        let credentials = "\(apiKey):\(apiSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ScenarioAPIError.invalidResponse
        }
        
        // Try to decode the JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScenarioAPIError.invalidImageData
        }
        
        // Look for download URL in the JSON
        print("📋 Asset metadata received, searching for image URL...")
        
        // Print the JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📋 JSON: \(jsonString)")
        }
        
        // Try various paths where the URL might be stored
        var downloadUrl: URL? = nil
        
        // Try to find "url", "downloadUrl", or similar fields at any level
        func findUrls(in dict: [String: Any], path: String = "") {
            for (key, value) in dict {
                let newPath = path.isEmpty ? key : "\(path).\(key)"
                
                if key.lowercased().contains("url") || key.lowercased().contains("download") || key.lowercased().contains("content"),
                   let urlString = value as? String,
                   urlString.hasPrefix("http"),
                   downloadUrl == nil {
                    print("📋 Found potential URL field: \(newPath) = \(urlString)")
                    downloadUrl = URL(string: urlString)
                }
                
                // Recursively check nested dictionaries
                if let nestedDict = value as? [String: Any] {
                    findUrls(in: nestedDict, path: newPath)
                }
                
                // Check arrays
                if let array = value as? [[String: Any]] {
                    for (index, item) in array.enumerated() {
                        findUrls(in: item, path: "\(newPath)[\(index)]")
                    }
                }
            }
        }
        
        findUrls(in: json)
        
        // If we found a URL, try to fetch it
        if let downloadUrl = downloadUrl {
            print("📋 Found download URL: \(downloadUrl)")
            return try await fetchImageWithBasicAuth(from: downloadUrl)
        }
        
        // If we can't find a URL, try the /content path
        if let contentUrl = URL(string: "\(url.absoluteString)/content") {
            print("📋 No download URL found, trying /content path: \(contentUrl)")
            return try await fetchImageWithBasicAuth(from: contentUrl)
        }
        
        throw ScenarioAPIError.invalidImageData
    }
    

}

// MARK: - Error Handling
enum ScenarioAPIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case networkError(Error)
    case invalidImageData
    case jobFailed
    case assetNotFound
    case jobTimeout
}

// MARK: - Observable Wrapper for SwiftUI
@MainActor
class ScenarioAPIViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var generatedImages: [UIImage] = []
    
    private let manager: ScenarioAPIManager
    
    init(key: String, secret: String) {
        self.manager = ScenarioAPIManager(key: key, secret: secret)
    }
    
    func generateImages(
        prompt: String,
        modelId: String = "model_hGvp7AwKAQugXTY5UnK7U2e4",
        numInferenceSteps: Int? = 30,
        numSamples: Int? = 1,
        guidance: Double? = 7.5,
        width: Int? = 1024,
        height: Int? = 1024,
        negativePrompt: String? = "ugly, bad, low quality, blurry"
    ) async {
        isLoading = true
        error = nil
        generatedImages = []
        
        do {
            let imageURLs = try await manager.generateImage(
                prompt: prompt,
                modelId: modelId,
                numInferenceSteps: numInferenceSteps,
                numSamples: numSamples,
                guidance: guidance,
                width: width,
                height: height,
                negativePrompt: negativePrompt
            )
            
            for url in imageURLs {
                let image = try await manager.fetchImage(from: url)
                generatedImages.append(image)
            }
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    @MainActor
    func generateImagesWithSeed(
        prompt: String,
        modelId: String = "model_hGvp7AwKAQugXTY5UnK7U2e4",
        numInferenceSteps: Int = 30,
        numSamples: Int = 1,
        guidance: Double = 7.5,
        width: Int = 1024,
        height: Int = 1024,
        negativePrompt: String = "ugly, bad, low quality, blurry",
        seed: String? = nil
    ) async -> [ScenarioImageMetadata] {
        isLoading = true
        error = nil
        generatedImages = []
        defer { isLoading = false }

        do {
            let rawResults = try await manager.generateImageWithSeed(
                prompt: prompt,
                modelId: modelId,
                numInferenceSteps: numInferenceSteps,
                numSamples: numSamples,
                guidance: guidance,
                width: width,
                height: height,
                negativePrompt: negativePrompt,
                seed: seed
            )

            var output: [ScenarioImageMetadata] = []

            for (index, result) in rawResults.enumerated() {
                do {
                    print("🖼️ Fetching image \(index) from URL: \(result.url)")
                    let image = try await manager.fetchImage(from: result.url)
                    generatedImages.append(image)

                    output.append(
                        ScenarioImageMetadata(
                            image: image,
                            seed: result.seed,
                            guidance: guidance,
                            samplingSteps: numInferenceSteps,
                            style: nil,
                            attemptIndex: index,
                            modelId: modelId
                        )
                    )
                } catch {
                    print("❌ Failed to fetch image \(index): \(error)")
                }
            }

            isLoading = false
            return output

        } catch {
            self.error = error
            print("❌ Failed to generate image with seed: \(error)")
            //isLoading = false
            return []
        }
    }
}


struct ScenarioImageMetadata {
    let image: UIImage
    let seed: String?
    let guidance: Double?
    let samplingSteps: Int?
    let style: String?
    let attemptIndex: Int?
    let modelId: String
}
