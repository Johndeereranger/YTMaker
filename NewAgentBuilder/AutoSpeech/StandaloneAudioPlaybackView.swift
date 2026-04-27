//
//  StandaloneAudioPlaybackView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//


import SwiftUI
import AVFoundation
import UserInfoLibrary

struct StandaloneAudioPlaybackView: View {
    let soundBeats: [SoundBeat]
    let imagePrompts: [ImagePrompt] // all image prompts passed in externally

    @State private var isPlaying = false
    @State private var isLoadingImages = true
    @State private var currentIndex = 0
    @State private var player: AVAudioPlayer?
    @State private var imagesByBeatId: [UUID: UIImage] = [:]

    var body: some View {
        VStack(spacing: 16) {
            Text(currentBeat?.text ?? "No Text")
                .font(.caption)
            if isLoadingImages {
                ProgressView("Loading Images...")
            } else if let currentBeat = currentBeat,
                      let currentImage = imagesByBeatId[currentBeat.id] {
                Image(uiImage: currentImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 450)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(Text("No Image").foregroundColor(.gray))
            }
            
//            VStack(spacing: 12) {
//                Button(isPlaying ? "🔊 Playing..." : "🗣️ Play Audio with Images") {
//                    Task {
//                        await playAllAudioWithImages()
//                    }
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(isPlaying || isLoadingImages)
//                
//                Button("📥 Load Image Prompts") {
//                    Task {
//                        await preloadImages()
//                    }
//                }
//                .buttonStyle(.bordered)
//                .disabled(isLoadingImages)
//            }
            
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    Button("⏮ Back") {
                        if currentIndex > 0 {
                            currentIndex -= 1
                            playCurrentBeat()
                        }
                    }
                    .disabled(isLoadingImages || currentIndex == 0)

                    Button(isPlaying ? "⏸ Pause" : "▶️ Play") {
                        Task {
                            if isPlaying {
                                player?.pause()
                                isPlaying = false
                            } else {
                                if player?.isPlaying == true {
                                    player?.play()
                                    isPlaying = true
                                } else {
                                    await playCurrentBeat()
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoadingImages)

                    Button("⏭ Next") {
                        if currentIndex < soundBeats.count - 1 {
                            currentIndex += 1
                            playCurrentBeat()
                        }
                    }
                    .disabled(isLoadingImages || currentIndex >= soundBeats.count - 1)
                }

                Button("📥 Load Image Prompts") {
                    Task {
                        await preloadImages()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingImages)
            }


            if isPlaying {
                Text("Now playing sound \(currentIndex + 1) of \(soundBeats.count)")
            }
        }
        .task {
            await preloadImages()
        }
    }
    private func playCurrentBeat() {
        guard currentIndex < soundBeats.count else { return }
        let beat = soundBeats[currentIndex]
        guard let url = FileManagerSingleton.instance.getAudioWAVFileURL(beat: beat) else {
            print("❌ No audio file for beat \(beat.id)")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            print("❌ Failed to play beat \(beat.id): \(error)")
        }
    }

    private var currentBeat: SoundBeat? {
        guard currentIndex < soundBeats.count else { return nil }
        return soundBeats[currentIndex]
    }

    private func preloadImages() async {
        isLoadingImages = true
        var results: [UUID: UIImage] = [:]

        for beat in soundBeats {
            guard let selectedId = beat.selectedImagePromptId,
                  let imagePrompt = imagePrompts.first(where: { $0.id == selectedId }) else {
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
        if let firstIndex = soundBeats.firstIndex(where: { results[$0.id] != nil }) {
            currentIndex = firstIndex
        }

        print("✅ Loaded images for beats:", results.keys)
        isLoadingImages = false
    }

    private func playAllAudioWithImages() async {
        let validBeats = soundBeats.filter { FileManagerSingleton.instance.audioFileExists(for: $0) }
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
