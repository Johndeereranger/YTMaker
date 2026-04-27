//
//  TextToSpeechTestView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//


import SwiftUI
import AVFoundation

struct TextToSpeechTestView: View {
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var audioData: Data? = nil
    @State private var player: AVAudioPlayer? = nil
    @State private var errorMessage: String? = nil

    private let apiManager = SpeechServiceAPIManager(apiKey: "AIzaSyBebujnYrA0peSJHNbAqmFAPUIyw0besJI")

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter text to speak", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            if isLoading {
                ProgressView("Generating audio...")
            } else if audioData != nil {
                Button("▶️ Play Audio") {
                    print("🔊 Play button tapped")
                    playAudio()
                }
            } else {
                Button("🛠️ Generate Speech") {
                    print("🛠️ Generate Speech button tapped with text: \(inputText)")
                    Task {
                        await generateSpeech()
                    }
                }
            }

            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private func generateSpeech() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter some text."
            print("⚠️ Input was empty")
            return
        }

        isLoading = true
        errorMessage = nil
        audioData = nil
        print("🚀 Starting speech generation for input: \(inputText)")

        do {
            let data = try await apiManager.synthesizeToData(text: inputText, voice: .neuralMaleI)
            print("✅ Successfully received audio data. Size: \(data.count) bytes")
            audioData = data
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error generating speech: \(error.localizedDescription)")
        }

        isLoading = false
        print("✅ Speech generation task completed")
    }

    private func playAudio() {
        guard let audioData = audioData else {
            print("❌ No audio data available to play")
            return
        }
        do {
            player = try AVAudioPlayer(data: audioData)
            player?.prepareToPlay()
            player?.play()
            print("🎧 Audio playback started")
        } catch {
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
            print("❌ Audio playback error: \(error.localizedDescription)")
        }
    }
}
