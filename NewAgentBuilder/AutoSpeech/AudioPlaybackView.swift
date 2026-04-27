//
//  AudioPlaybackView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/21/25.
//


import SwiftUI
import AVFoundation

struct AudioPlaybackView: View {
    let soundBeats: [SoundBeat]
    @State private var isPlaying = false
    @State private var currentIndex = 0
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack {
            Button(isPlaying ? "🔊 Playing..." : "🗣️ Play Audio") {
                Task {
                    await playAllAudio()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPlaying)

            if isPlaying {
                Text("Playing sound \(currentIndex + 1) of \(soundBeats.count)")
            }
        }
    }

    private func playAllAudio() async {
        let validBeats = soundBeats.filter { FileManagerSingleton.instance.audioFileExists(for: $0) }
        guard !validBeats.isEmpty else { return }

        isPlaying = true
        currentIndex = 0

        for (i, beat) in validBeats.enumerated() {
            currentIndex = i
            guard let url = FileManagerSingleton.instance.getAudioWAVFileURL(beat: beat) else { continue }

            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                player?.play()

                // Wait until finished
                while let p = player, p.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
            } catch {
                print("❌ Failed to play audio for \(beat.id): \(error)")
            }
        }

        isPlaying = false
    }
}