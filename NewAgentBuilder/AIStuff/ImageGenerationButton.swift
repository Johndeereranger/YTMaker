//
//  ImageGenerationButton.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/20/25.
//
import SwiftUI
import UserInfoLibrary
import SwiftUI
import UserInfoLibrary

struct ImageGenerationButton: View {
    @StateObject private var viewModel: ImageGeneratorViewModel

    init(initialPrompt: String?, beatID: UUID, onComplete: @escaping (ImagePrompt) -> Void) {
        _viewModel = StateObject(wrappedValue: ImageGeneratorViewModel(
            prompt: initialPrompt ?? "",
            beatID: beatID,
            onComplete: onComplete
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Put editing and generation in separate states
            if !viewModel.isEditing {
                // Normal state: Generate button and Edit button
                HStack {
                    Button {
                        Task {
                            await viewModel.generate()
                        }
                    } label: {
                        Label(viewModel.isLoading ? "Generating..." : "Generate", systemImage: "sparkles")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.opacity(0.8))
                    .disabled(viewModel.isLoading)
                    
                    Spacer(minLength: 10)
                    
                    Button {
                        viewModel.isEditing.toggle()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
            } else {
                // Edit mode: Configuration options with Save/Cancel buttons
                VStack(alignment: .leading, spacing: 10) {
                    Text("Edit Generation Parameters")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    TextField("Edit Prompt", text: $viewModel.prompt)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    HStack {
                        Text("Guidance: \(String(format: "%.1f", viewModel.guidance))")
                            .frame(width: 100, alignment: .leading)
                        Slider(value: $viewModel.guidance, in: 1...10, step: 0.5)
                    }

                    HStack {
                        Text("Steps: \(viewModel.steps)")
                            .frame(width: 100, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(viewModel.steps) },
                            set: { viewModel.steps = Int($0) }
                        ), in: 1...30, step: 1)
                    }
                    
                    TextField("Seed (optional)", text: Binding(
                        get: { viewModel.seed ?? "" },
                        set: { viewModel.seed = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    // Clear buttons for edit mode
                    HStack(spacing: 12) {
                        Button(role: .cancel) {
                            viewModel.isEditing = false
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        
                        Spacer()
                        
                        Button {
                            viewModel.isEditing = false
                            Task {
                                await viewModel.generate()
                            }
                        } label: {
                            Text("Save & Generate")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(viewModel.isLoading)
                        
                        Spacer()
                        
                        Button {
                            viewModel.isEditing = false
                        } label: {
                            Text("Save Settings")
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            if let error = viewModel.error {
                Text("❌ \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if viewModel.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
}
struct ImageGenerationButton2: View {
    @StateObject private var viewModel: ImageGeneratorViewModel

    init(initialPrompt: String?, beatID: UUID, onComplete: @escaping (ImagePrompt) -> Void) {
        _viewModel = StateObject(wrappedValue: ImageGeneratorViewModel(
            prompt: initialPrompt ?? "",
            beatID: beatID,
            onComplete: onComplete
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    Task {
                        await viewModel.generate()
                    }
                }) {
                    Label(viewModel.isLoading ? "Generating..." : "Generate", systemImage: "sparkles")
                }
                .disabled(viewModel.isLoading)

                Button(action: { viewModel.isEditing.toggle() }) {
                    Image(systemName: "pencil")
                }
            }

            if viewModel.isEditing {
                TextField("Edit Prompt", text: $viewModel.prompt)
                HStack {
                    Text("Guidance: \(viewModel.guidance)")
                    Slider(value: $viewModel.guidance, in: 1...10, step: 0.5)
                }

                HStack {
                    Text("Steps: \(viewModel.steps)")
                    Slider(value: Binding(
                        get: { Double(viewModel.steps) },
                        set: { viewModel.steps = Int($0) }
                    ), in: 1...30, step: 1)
                }
                
                TextField("Seed (optional)", text: Binding(
                    get: { viewModel.seed ?? "" },
                    set: { viewModel.seed = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if let error = viewModel.error {
                Text("❌ \(error)").foregroundColor(.red).font(.caption)
            }
        }
    }
}

class ImageGeneratorViewModel: ObservableObject {
    @Published var prompt: String
    @Published var guidance: Double = 7.5
    @Published var steps: Int = 30
    @Published var seed: String? = nil
    @Published var isLoading = false
    @Published var isEditing = false
    @Published var error: String?

    private let beatID: UUID
    private let onComplete: (ImagePrompt) -> Void

    init(prompt: String, beatID: UUID, onComplete: @escaping (ImagePrompt) -> Void) {
        self.prompt = prompt
        self.beatID = beatID
        self.onComplete = onComplete
    }

    func generate() async {
        guard !isLoading else { return }

        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }

        do {
            let scenarioVM = await ScenarioAPIViewModel(
                key: Constants.scenarioAPIKey,
                secret: Constants.scenarioAPISecret
            )

            let metadataList = await scenarioVM.generateImagesWithSeed(
                prompt: prompt,
                numInferenceSteps: steps,
                guidance: guidance,
                seed: seed
            )

            guard let metadata = metadataList.first else {
                DispatchQueue.main.async {
                    self.error = "No image returned"
                    self.isLoading = false
                    self.onComplete(ImagePrompt.errorPlaceholder(beatID: self.beatID, error: "No image returned"))
                }
                return
            }

            let image = metadata.image
            let storedFilename = "\(UUID().uuidString).jpg"
            let remotePath = "stickImages/\(storedFilename)"

            let fbUrl = try await ImageStoreManager.shared.storeImage(
                image,
                name: storedFilename,
                remotePath: remotePath
            )

            let shortID = try await ImagePromptManager.instance.nextShortID()

            let promptModel = try await ImagePromptManager.instance.createPrompt(
                from: image,
                filename: storedFilename,
                prompt: prompt,
                url: fbUrl,
                shortID: shortID,
                beatId: beatID,
                seed: metadata.seed,
                style: metadata.style,
                guidance: metadata.guidance ?? guidance,
                samplingSteps: metadata.samplingSteps ?? steps,
                attemptIndex: metadata.attemptIndex ?? 0
            )

            DispatchQueue.main.async {
                self.onComplete(promptModel)
                self.isLoading = false
            }

        } catch {
            DispatchQueue.main.async {
                self.error = error.localizedDescription
                self.onComplete(ImagePrompt.errorPlaceholder(beatID: self.beatID, error: error.localizedDescription))
                self.isLoading = false
            }
        }
    }
}

extension ImagePrompt {
    static func errorPlaceholder(beatID: UUID, error: String) -> ImagePrompt {
        return ImagePrompt(
            id: UUID().uuidString,
            originalFilename: UUID().uuidString + ".jpg",
            prompt: "",
            url: "",
            sourceSoundBeatId: beatID.uuidString,
            reusedBy: [],
            status: .failed,
            createdAt: Date(),
            shortID: -1,
            processingStartedAt: nil,
            processingCompletedAt: Date(),
            errorMessage: error,
            attemptIndex: nil,
            seed: nil,
            style: nil,
            guidance: nil,
            samplingSteps: nil,
            otherParameters: nil
        )
    }
}
class ImageGeneratorViewModels: ObservableObject {
    @Published var prompt: String
    @Published var guidance: Double = 7.5
    @Published var steps: Int = 30
    @Published var seed: String? = nil
    @Published var isLoading = false
    @Published var isEditing = false
    @Published var error: String?

    private let beatID: UUID
    private let onComplete: (ImagePrompt) -> Void

    init(prompt: String, beatID: UUID, onComplete: @escaping (ImagePrompt) -> Void) {
        self.prompt = prompt
        self.beatID = beatID
        self.onComplete = onComplete
    }

    func generate() async {
        do {
            DispatchQueue.main.async {
                self.isLoading = true
                self.error = nil
            }
           

            let scenarioVM = await ScenarioAPIViewModel(
                key: Constants.scenarioAPIKey,
                secret: Constants.scenarioAPISecret
            )

            let metadataList = await scenarioVM.generateImagesWithSeed(
                prompt: prompt,
                numInferenceSteps: steps,
                guidance: guidance,
                seed: seed
            )
            print("🧪 Received \(metadataList.count) metadata entries")
            for (index, item) in metadataList.enumerated() {
                print("📸 \(index): seed=\(item.seed ?? "nil"), guidance=\(item.guidance ?? -1), steps=\(item.samplingSteps ?? -1)")
            }
            guard let metadata = metadataList.first else {
                DispatchQueue.main.async {
                    
                    
                    self.error = "No image returned"
                    self.isLoading = false
                }
                return
            }

            let image = metadata.image

            // ✅ Step 2: Determine canonical filename and storage path
            let storedFilename = "\(UUID().uuidString).jpg"
            let remotePath = "stickImages/\(storedFilename)"

            // ✅ Step 3: Store image (local + Firebase) via unified manager
            let fbUrl = try await ImageStoreManager.shared.storeImage(
                image,
                name: storedFilename,
                remotePath: remotePath
            )

            // ✅ Step 4: Get shortID and build the prompt model
            let shortID = try await ImagePromptManager.instance.nextShortID()

            let promptModel = try await ImagePromptManager.instance.createPrompt(
                from: image,
                filename: storedFilename,
                prompt: prompt,
                url: fbUrl,
                shortID: shortID,
                beatId: beatID,
                seed: metadata.seed,
                style: metadata.style,
                guidance: metadata.guidance ?? guidance,
                samplingSteps: metadata.samplingSteps ?? steps,
                attemptIndex: metadata.attemptIndex ?? 0
            )

            onComplete(promptModel)

        } catch {
            self.error = error.localizedDescription
        }

        DispatchQueue.main.async {
             self.isLoading = false
         }
    }
}
