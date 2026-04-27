//
//  AudioPlaybackWithImagesView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//

import SwiftUI
import AVFoundation
import UserInfoLibrary

struct AudioPlaybackWithImagesView: View {
   // @ObservedObject var viewModel: ScriptDetailViewModel
    @StateObject private var viewModel = ScriptDetailViewModel.instance
    @State private var isPlaying = false
    @State private var isLoadingImages = true
    @State private var currentIndex = 0
    @State private var player: AVAudioPlayer?
    @State private var imagesByBeatId: [UUID: UIImage] = [:]

    var body: some View {
        VStack(spacing: 16) {
            if isLoadingImages {
                ProgressView("Loading Images...")
            } else if let currentBeat = currentBeat,
                      let currentImage = imagesByBeatId[currentBeat.id] {
                Image(uiImage: currentImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(Text("No Image").foregroundColor(.gray))
            }

            Button(isPlaying ? "🔊 Playing..." : "🗣️ Play Audio with Images") {
                Task {
                    await playAllAudioWithImages()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPlaying || isLoadingImages)

            if isPlaying {
                Text("Now playing sound \(currentIndex + 1) of \(viewModel.soundBeats.count)")
            }
        }
        .task {
            if !viewModel.soundBeats.isEmpty {
                await preloadImages()
            }
        }
        .onChange(of: viewModel.soundBeats) { newBeats in
            if !newBeats.isEmpty {
                Task {
                    await preloadImages()
                }
            }
        }
    }

    private var currentBeat: SoundBeat? {
        guard currentIndex < viewModel.soundBeats.count else { return nil }
        return viewModel.soundBeats[currentIndex]
    }

    private func preloadImages() async {
        isLoadingImages = true

        var results: [UUID: UIImage] = [:]
        print("preloading sound beats: \(viewModel.soundBeats.count) and image Prompts: \(viewModel.imagePromptsByBeatId.count)" )
        for beat in viewModel.soundBeats {
            guard let selectedId = beat.selectedImagePromptId,
                  let imagePrompt = viewModel.imagePromptsByBeatId[beat.id]?.first(where: { $0.id == selectedId }) else {
                continue
            }
            let name = imagePrompt.originalFilename
            
            do {
                let image = try await ImageStoreManager.shared.retrieveImage(name: name, remotePath: name)
                results[beat.id] = image
            } catch {
                print("⚠️ Could not load image for beat \(beat.id): \(error)")
            }
        }
        for beat in viewModel.soundBeats {
            guard let imagePrompt = ScriptDetailViewModel.instance.selectedImagePromptForBeat(beat.id) else {
                continue
            }

            let name = imagePrompt.originalFilename
            do {
                let image = try await ImageStoreManager.shared.retrieveImage(name: name, remotePath: name)
                results[beat.id] = image
            } catch {
                print("❌ Failed to load image for beat \(beat.id) with name \(name): \(error)")
            }
        }

        imagesByBeatId = results
        if let firstIndex = viewModel.soundBeats.firstIndex(where: { results[$0.id] != nil }) {
            currentIndex = firstIndex
        }
        print("✅ Loaded images for beats:", results.keys)
        isLoadingImages = false
    }

    private func playAllAudioWithImages() async {
        let validBeats = viewModel.soundBeats.filter { FileManagerSingleton.instance.audioFileExists(for: $0) }
        guard !validBeats.isEmpty else { return }

        isPlaying = true
        currentIndex = 0

        for (i, beat) in validBeats.enumerated() {
            await MainActor.run {
                currentIndex = i
            }
            guard let url = FileManagerSingleton.instance.getAudioWAVFileURL(beat: beat) else { continue }

            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                player?.play()

                while let p = player, p.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch {
                print("❌ Failed to play audio for beat \(beat.id): \(error)")
            }
        }

        isPlaying = false
    }
}
