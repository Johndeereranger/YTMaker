//
//  ScriptDetailView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import SwiftUI

// MARK: - ScriptDetailView
struct ScriptDetailView: View {
    let script: Script
    @StateObject private var viewModel: ScriptDetailViewModel
    
//    init(script: Script) {
//        self.script = script
//        _viewModel = StateObject(wrappedValue: ScriptDetailViewModel(script: script))
//    }
    init(script: Script) {
        self.script = script

        let vm = ScriptDetailViewModel(script: script)
        ScriptDetailViewModel.instance = vm
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(script.title)
                    .font(.largeTitle)
                    .padding(.bottom, 8)
                
                DisclosureGroup("📝 Raw Prompt Preview") {
                    Text(script.content)
                        .font(.footnote)
                        .padding(.top, 2)
                }
                .padding(.bottom, 8)
                .tint(.primary)
                
               // ScriptDetailControlPanel(viewModel: viewModel)
                ScriptDetailControlPanel()
                if let selectedImage = viewModel.fullSizeImagePrompt {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🖼️ Selected Image Preview")
                            .font(.headline)
                        AsyncImage(url: URL(string: selectedImage.url)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 400)
                                .cornerRadius(12)
                        } placeholder: {
                            ProgressView()
                        }
                        .padding(.bottom, 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Prompt: \(selectedImage.prompt)")
                            Text("Seed: \(selectedImage.seed ?? "n/a")")
                            Text("Guidance: \(selectedImage.guidance?.description ?? "n/a")")
                            Text("Steps: \(selectedImage.samplingSteps?.description ?? "n/a")")
                            Text("ID: \(selectedImage.id)")
                        }
                        .font(.caption)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.bottom, 12)
                }
                //List {
                   // ForEach(viewModel.soundBeats, id: \.id) {beat in
                        ForEach(viewModel.soundBeats.sorted(by: { $0.order < $1.order }), id: \.id) { beat in
                        SoundBeatRowView(
                            script:script,
                            beat: beat,
                            selectedImageID: viewModel.selectedImagePromptForBeat(beat.id)?.id,
                            imagePrompts: viewModel.imagePromptsByBeatId[beat.id] ?? [],
                            onSelectImage: { selected in
                                Task {
                                    await viewModel.selectImagePrompt(selected.id, for: beat)
                                }
                            }, onImageGenerated: { newImagePrompt in
                                Task {
                                    await viewModel.imageGeneratedFor(beatID: beat.id, imagePrompt: newImagePrompt)
                                }
                            },
                            onImageTapped: { prompt in
                                    viewModel.fullSizeImagePrompt = prompt
                            }, onStatusUpdate: { newMatchStrength in
                                print(newMatchStrength, "set for the sound beat")
                            }, onImageAddedFromLibrary: { newimage in
                                Task {
                                    await viewModel.imageAddedFromlibrary(for: beat.id, imagePrompt: newimage)
                                }
                            }
                            
                        )
                 //   }
                }
                
                
            }
            .padding()
            .navigationTitle("Script Detail")
            .onAppear {
                Task {
                    await viewModel.loadSoundBeats()
                }
            }
        }
    }
}

// MARK: - ScriptDetailControlPanel
struct ScriptDetailControlPanel: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
  //  @ObservedObject var viewModel: ScriptDetailViewModel
    @StateObject private var viewModel = ScriptDetailViewModel.instance
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⚙️ Control Panel")
                .font(.headline)
            
            Button("▶️ Run Initial Pass") {
                Task {
                    await viewModel.runInitialPass()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isThinking)
            

            Group {
                if sizeClass == .compact {
                    VStack(alignment: .leading, spacing: 12) {
                        contentButtons
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        contentButtons
                    }
                }
            }
            
            Button("🖼️ Find Matching Database Images") {
                Task {
                    
                    await viewModel.findMatchingImagesInDataBase()
                }
            }
            .disabled(viewModel.isThinking)
            
            Button("📤 Export as JSON") {
                viewModel.exportBeatsAsJSON()
            }
            VStack(spacing: 4) {
                if let beatRun = viewModel.beatRun,
                   let matchingPromptRun = viewModel.matchingPromptRun,
                   let generatePromptRun = viewModel.generatePromptRun {
                    
                    DisclosureGroup("📝 Step 1: Beats Output") {
                        Text(beatRun.response)
                            .font(.caption)
                            .padding(.bottom, 4)
                    }

                    DisclosureGroup("🔍 Step 2: Matching Output") {
                        Text(matchingPromptRun.response)
                            .font(.caption)
                            .padding(.bottom, 4)
                    }

                    DisclosureGroup("🎨 Step 3: Generate Output") {
                        Text(generatePromptRun.response)
                            .font(.caption)
                    }
                } else {
                    Text("No debug output yet.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }
            
            if viewModel.isThinking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var contentButtons: some View {
        Button("🗣️ Generate Missing Speech") {
            Task { await viewModel.generateSpeech() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isThinking)

        AudioPlaybackView(soundBeats: viewModel.soundBeats.sorted(by: { $0.order < $1.order }))

        StandaloneAudioPlaybackView(
            soundBeats: viewModel.soundBeats.sorted(by: { $0.order < $1.order }),
            imagePrompts: selectedImagePrompts
        )
    }
    
    private var selectedImagePrompts: [ImagePrompt] {
        viewModel.soundBeats.compactMap { beat in
            guard let id = beat.selectedImagePromptId else {
                print("🚫 No selectedImagePromptId for beat \(beat.id)")
                return nil
            }

            guard let prompts = viewModel.imagePromptsByBeatId[beat.id], !prompts.isEmpty else {
                print("📭 No prompts found for beat \(beat.id)")
                return nil
            }

            if let matched = prompts.first(where: { $0.id == id }) {
                print("✅ Matched prompt \(id) for beat \(beat.id)")
                return matched
            } else {
                print("❌ selectedImagePromptId \(id) not found in prompts for beat \(beat.id)")
                return nil
            }
        }
    }
}
