//
//  ImageUploadView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//


import SwiftUI
import UniformTypeIdentifiers

struct ImageUploadView: View {
    @StateObject var viewModel = ImageUploadViewModel()
    @State private var selectedImage: UIImage?

    var body: some View {
        VStack(spacing: 20) {

            // 📸 Large preview
            if let selected = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: selected)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .cornerRadius(12)
                        .padding(.horizontal)

                    Button(action: {
                        viewModel.removeStagedImage(selected)
                        selectedImage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                            .padding(8)
                    }
                }
            }

            // 🔳 Grid of thumbnails (newest first)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.stagedImages.indices.reversed(), id: \.self) { index in
                        let image = viewModel.stagedImages[index]
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedImage = image
                            }
                    }
                }
                .padding(.horizontal)
            }

            // ⬆️ Upload button
            Button("Upload All Images") {
                Task {
                    for image in viewModel.stagedImages {
                        await viewModel.uploadImage(image)
                    }
                    viewModel.stagedImages.removeAll()
                    selectedImage = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            // ⬇️ Drop zone
            Text("Drag & drop image files here")
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            
            if viewModel.missingPromptCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("🧠 \(viewModel.missingPromptCount) images are missing prompts")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                    Button("Generate All Prompts") {
                        Task {
                            await viewModel.generateMissingPrompts()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top)
            }
        }
        .padding()
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .task {
            await viewModel.loadExistingPrompts()
        }
   
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        var imageLoadTasks: [(UIImage, String)] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    defer { group.leave() }

                    guard let url = url else {
                        print("⚠️ Failed to get file URL from drop: \(error?.localizedDescription ?? "unknown error")")
                        return
                    }

                    let filename = url.lastPathComponent
                    let baseName = (filename as NSString).deletingPathExtension

                    if viewModel.uploadedPrompts.contains(where: { $0.originalFilename == baseName }) {
                        print("⚠️ Skipping duplicate drop: \(filename)")
                        return
                    }

                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        imageLoadTasks.append((image, baseName))
                    } else {
                        print("❌ Could not read image from dropped file \(filename)")
                    }
                }
                handled = true
            }
        }

        group.notify(queue: .main) {
            Task {
                let count = imageLoadTasks.count
                guard count > 0 else { return }

                let startingID = try? await viewModel.reserveShortIDRange(count: count)
                guard let baseID = startingID else {
                    print("❌ Failed to reserve shortID range")
                    return
                }

                for (offset, (image, baseName)) in imageLoadTasks.enumerated() {
                    viewModel.stagedImages.append(image)
                    selectedImage = image
                    await viewModel.uploadImage(image, withName: baseName, shortID: baseID + offset)
                }
            }
        }

        return handled
    }
}
