//
//  SpeechServiceAPIManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//


// MARK: - SpeechServiceAPIManager

import Foundation
import AVFoundation

final class SpeechServiceAPIManagers {
    private let apiKey: String
    private let baseURL: String = "https://texttospeech.googleapis.com/v1beta1/text:synthesize"
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func synthesizeToData(text: String, voice: VoiceType) async throws -> Data {
        let url = URL(string: baseURL + "?key=\(apiKey)")!

        let requestDict: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": "en-US", "name": voice.rawValue],
            "audioConfig": ["audioEncoding": "LINEAR16"]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw TTSError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioContent = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioContent) else {
            throw TTSError.failedToParseAudio
        }

        return audioData
    }



}

// MARK: - SpeechServiceAPIManager

import Foundation
import AVFoundation

final class SpeechServiceAPIManager {
    private let apiKey: String
    private let baseURL: String = "https://texttospeech.googleapis.com/v1beta1/text:synthesize"
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func synthesizeToData(text: String, voice: VoiceType) async throws -> Data {
        print("📤 Starting synthesizeToData with text: \(text)")
        let url = URL(string: baseURL + "?key=\(apiKey)")!

        let requestDict: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": "en-US", "name": voice.rawValue],
            "audioConfig": ["audioEncoding": "LINEAR16"]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestDict)
        print("📝 JSON payload: \(String(data: jsonData, encoding: .utf8) ?? "<invalid>")")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        print("🌐 Sending request to: \(url)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw TTSError.invalidResponse
        }

        print("📡 Status Code: \(httpResponse.statusCode)")
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "<no body>"
            print("❌ Server responded with error: \(responseBody)")
            throw TTSError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to decode JSON from response")
            throw TTSError.failedToParseAudio
        }

        print("✅ JSON response: \(json)")

        guard let audioContent = json["audioContent"] as? String else {
            print("❌ 'audioContent' missing in response")
            throw TTSError.failedToParseAudio
        }

        guard let audioData = Data(base64Encoded: audioContent) else {
            print("❌ Failed to decode base64 audio data")
            throw TTSError.failedToParseAudio
        }

        print("🎵 Successfully decoded audio data: \(audioData.count) bytes")
        return audioData
    }
}




// MARK: - Supporting Types

enum TTSError: Error {
    case invalidResponse
    case failedToParseAudio
    case network(Error)
    case storageFailed
    case audioSessionError
}

enum VoiceType: String {
    case undefined
    case waveNetFemale = "en-US-Wavenet-F"
    case waveNetMale = "en-US-Wavenet-D"
    case standardFemale = "en-US-Standard-E"
    case standardMale = "en-US-Standard-D"
    case neuralMale = "en-US-Neural2-J"
    case neuralMaleI = "en-US-Neural2-I"
}

struct TTSVoice: Identifiable, Codable {
    let id: String
    let name: String
    let language: String
    let gender: String
} 
