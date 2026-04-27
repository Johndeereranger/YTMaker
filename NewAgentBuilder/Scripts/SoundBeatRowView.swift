//
//  SoundBeatRowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/20/25.
//
import SwiftUI
import UserInfoLibrary

struct SoundBeatRowView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let script: Script
    let beat: SoundBeat
    let selectedImageID: String?
    let imagePrompts: [ImagePrompt]
    let onSelectImage: (ImagePrompt) -> Void
    let onImageGenerated: (ImagePrompt) -> Void
    var onImageTapped: ((ImagePrompt) -> Void)? = nil
    let onStatusUpdate: (MatchStrength) -> Void
    let onImageAddedFromLibrary: (ImagePrompt) -> Void
    
    @State private var exportImage: UIImage?
    @State private var exportFileName: String = "export.png"
    @State private var isExporting = false
    
    @State private var showingImageSelector = false
    
    var body: some View {
        Group{
            if sizeClass == .compact {
                VStack(spacing: 6){
                    if let selectedImage = selectedImagePrompt {
                        BeatSelectedImageView(
                            selectedImageURL: selectedImage.url,
                            onTap: { _ in
                                onImageTapped?(selectedImage)
                            }
                        )
                    } else {
                        BeatSelectedImageView(selectedImageURL: nil)
                    }
                    if imagePrompts.count > 1 {
                      
                        ImagePromptScrollView(
                            beatID: beat.id,
                            imagePrompts: imagePrompts,
                            selectedID: beat.selectedImagePromptId,
                            onSelect: onSelectImage,
                            onLongPress: { imagePrompt in
                                onImageTapped?(imagePrompt)
                            }
                        )
                    }
                    //BeatTextDetails(beat: beat)
                    BeatTextDetails(
                        beat: beat,
                        onStatusUpdate: onStatusUpdate // Pass it through
                    )
                    BeatActionButtons(script: script, beat: beat, onImageGenerated: onImageGenerated)
                }
            } else {
                HStack(spacing: 16) {
                    if let selectedImage = selectedImagePrompt {
                        BeatSelectedImageView(
                            selectedImageURL: selectedImage.url,
                            onTap: { _ in
                                onImageTapped?(selectedImage)
                            }
                        )
                    } else {
                        BeatSelectedImageView(selectedImageURL: nil)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        //BeatTextDetails(beat: beat)
                        BeatTextDetails(
                            beat: beat,
                            onStatusUpdate: onStatusUpdate // Pass it through
                        )
                        if imagePrompts.count > 1 {
                          
                            ImagePromptScrollView(
                                beatID: beat.id,
                                imagePrompts: imagePrompts,
                                selectedID: beat.selectedImagePromptId,
                                onSelect: onSelectImage,
                                onLongPress: { imagePrompt in
                                    onImageTapped?(imagePrompt)
                                }
                            )
                        }
                        BeatActionButtons(script: script, beat: beat, onImageGenerated: onImageGenerated)
                        HStack {
                            Button {
                                showingImageSelector = true
                            } label: {
                                Label("Select Image", systemImage: "photo.on.rectangle.angled")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                            Button("Export to Files") {
                                guard let selected = selectedImagePrompt else { return }

                                Task {
                                    do {
                                        let uiImage = try await ImageStoreManager.shared.retrieveImage(
                                            name: selected.originalFilename,
                                            remotePath: selected.url
                                        )

                                        let processedImage = ImageExporter.makeWhiteTransparent(uiImage)

                                        exportImage = processedImage
                                        exportFileName = (selected.originalFilename as NSString).deletingPathExtension + ".png"
                                        isExporting = true
                                    } catch {
                                        print("❌ Failed to export image: \(error)")
                                    }
                                }
                            }
                            
                            if selectedImageID != nil {
                                Text(selectedImagePrompt?.originalFilename ?? "")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

            }
                
        }
      
        .fileExporter(
            isPresented: $isExporting,
            document: ImageFile(image: exportImage ?? UIImage(), filename: exportFileName),
            contentType: .png,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result {
                print("❌ Export failed: \(error)")
            } else {
                print("✅ Export succeeded")
            }
        }
    #if targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingImageSelector) {
            NavigationView {
                ImagePromptSelectorView { selectedPrompt in
                    showingImageSelector = false
                    onImageAddedFromLibrary(selectedPrompt)
                }
                .navigationTitle("Select Image")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingImageSelector = false
                        }
                    }
                }
            }
        }
        #else
        .sheet(isPresented: $showingImageSelector) {
            ImagePromptSelectorSheet { selectedPrompt in
                showingImageSelector = false
                onImageAddedFromLibrary(selectedPrompt)
            }
        }
        #endif
    }
    
    private var selectedImagePrompt: ImagePrompt? {
        if let selectedID = beat.selectedImagePromptId,
           let matched = imagePrompts.first(where: { $0.id == selectedID }) {
            return matched
        } else if let fallback = imagePrompts.first {
            return fallback
        } else {
            return nil
        }
    }
}

struct BeatActionButtons: View {
    let script: Script
    let beat: SoundBeat
    let onImageGenerated: (ImagePrompt) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if beat.needsImageGeneration {
                ImageGenerationButton(
                    initialPrompt: beat.generatedPrompt,
                    beatID: beat.id,
                    onComplete: onImageGenerated
                )
            }
            CopyButton(label: "Script with Index", valueToCopy: generateInput(script: script, soundBeat: beat) )
            CopyButton(label: "Prompt", valueToCopy: beat.generatedPrompt ?? "No Prompt")
        }
        .font(.caption)
    }
    
    func generateInput(script: Script, soundBeat: SoundBeat) -> String {
        return """
        You are evaluating one specific line within a full script.  Do not evaluate it in isolation. Instead, consider how it fits into the **narrative flow** of the script: - What came before sets the context. - What follows shows the direction or consequence. Choose an image that reflects the **emotional and conceptual shift** at that point — not just the literal meaning of the focused line. Below is the full script:
        \(script.content)
        Your focus is only on one section and an image to represent that section which is: \(soundBeat.text)
        """
    }
}



//struct BeatTextDetails: View {
//    let beat: SoundBeat
//    var body: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text("🗣️ \(beat.text)")
//                .font(.subheadline)
//                .fixedSize(horizontal: false, vertical: true)
//            
//            if let prompt = beat.generatedPrompt {
//                Text("🎯 \(prompt)")
//                    .font(.footnote)
//                    .foregroundColor(.secondary)
//            }
//            
//            if let matchedPromptId = beat.selectedImagePromptId {
//                Text("✅ Matched Prompt ID: \(matchedPromptId)")
//                    .font(.caption)
//                    .foregroundColor(.green)
//            }
//        }
//        
//    }
//}
struct BeatTextDetails: View {
    let beat: SoundBeat
    let onStatusUpdate: (MatchStrength) -> Void // Add this parameter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Add match status at top
            HStack {
                MatchStatusBadge(
                    strength: beat.bestSystemMatch?.strength,
                    onStatusUpdate: onStatusUpdate
                )
//                Spacer()
//                if beat.needsHumanReview {
//                    Label("Review", systemImage: "exclamationmark.triangle")
//                        .font(.caption)
//                        .foregroundColor(.orange)
//                }
            }
            
            Text("🗣️ \(beat.text)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            
            if let prompt = beat.generatedPrompt {
                Text("🎯 \(prompt)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            if let matchedPromptId = beat.selectedImagePromptId {
                Text("✅ Selected: \(matchedPromptId)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            // Show system match if different from selected
//            if let systemId = beat.systemMatchedPromptId,
//               systemId != beat.selectedImagePromptId {
//                Text("🤖 System suggested: \(systemId)")
//                    .font(.caption)
//                    .foregroundColor(.blue)
//            }
        }
    }
}

struct BeatSelectedImageView: View {
    let selectedImageURL: String?
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        if let matchedImage = selectedImageURL,
           let url = URL(string: matchedImage) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 200, height: 200)
            .cornerRadius(8)
            .clipped()
            .onTapGesture {
                onTap?(matchedImage)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 2) // 🔴 Red border added here
            )
        } else {
            Color.red
                .frame(width: 100, height: 100)
                .cornerRadius(8)
        }
    }
}



struct ImagePromptScrollView: View {
    let beatID: UUID
    let imagePrompts: [ImagePrompt]
    let selectedID: String?
    let onSelect: (ImagePrompt) -> Void
    let onLongPress: (ImagePrompt) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(imagePrompts, id: \.id) { imagePrompt in
                    TappableImageView(
                        imagePrompt: imagePrompt,
                        selectedID: selectedID,
                        onTap: {
                            print("🟦 Tapped on \(imagePrompt.id)")
                            onSelect(imagePrompt)
                        },
                        onLongPress: {_ in
                            print("🟥 Long pressed on \(imagePrompt.id)")
                            onLongPress(imagePrompt)
                        }
                    )
                }
            }
        }
        .frame(height: 60)
    }
}

struct TappableImageViewW: View { // This works
    let imagePrompt: ImagePrompt
    let selectedID: String?
    let onTap: () -> Void
    let onLongPress: (ImagePrompt) -> Void

    var body: some View {
        AsyncImage(url: URL(string: imagePrompt.url)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ProgressView()
        }
        .frame(width: 60, height: 60)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    imagePrompt.id == selectedID ? Color.blue : Color.clear,
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle()) // Ensure full area is tappable
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress(imagePrompt)
        }
    }
}

struct TappableImageView: View {
    let imagePrompt: ImagePrompt
    let selectedID: String?
    let onTap: () -> Void
    let onLongPress: (ImagePrompt) -> Void

    @State private var image: UIImage? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Color.gray
                    .overlay(Text("⚠️ Load Failed").font(.caption))
            }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(imagePrompt.id == selectedID ? Color.blue : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress(imagePrompt) }
        .task {
            guard image == nil else { return }
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

         let name = imagePrompt.originalFilename

        let firebasePath = extractFirebaseStoragePath(from: imagePrompt.url)
        if firebasePath.isEmpty {
            print("❌ Failed to extract Firebase storage path from URL: \(imagePrompt.url)")
            return
        }

        do {
            image = try await ImageStoreManager.shared.retrieveImage(
                name: name,
                remotePath: firebasePath
            )
        } catch {
            print("❌ ImageStoreManager failed to load image for \(name): \(error)")
        }
    }

    private func extractFirebaseStoragePath(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let range = components.path.range(of: "/o/") else {
            return ""
        }
        let encodedPath = String(components.path[range.upperBound...])
        return encodedPath.removingPercentEncoding ?? encodedPath
    }
}

struct MatchStatusBadge: View {
    let strength: MatchStrength?
    let onStatusUpdate: (MatchStrength) -> Void
    @State private var showingStatusPicker = false
    
    var body: some View {
        Button(action: { showingStatusPicker = true }) {
            HStack(spacing: 4) {
                Text(strength?.emoji ?? "❓")
                Text(strength?.rawValue.uppercased() ?? "UNKNOWN")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .cornerRadius(16)
        }
        .sheet(isPresented: $showingStatusPicker) {
            MatchStatusPicker(
                currentStatus: strength ?? .none,
                onSelect: { newStatus in
                    onStatusUpdate(newStatus)
                    showingStatusPicker = false
                }
            )
        }
    }
    
    private var backgroundColor: Color {
        switch strength {
        case .strong: return .green
        case .moderate: return .blue
        case .weak: return .orange
        case .none: return .red
        case nil: return .gray
        case .some(.none):
            return.gray
        }
    }
}

// MARK: - Status Picker Sheet
struct MatchStatusPicker: View {
    let currentStatus: MatchStrength
    let onSelect: (MatchStrength) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(MatchStrength.allCases, id: \.self) { status in
                    Button(action: { onSelect(status) }) {
                        HStack {
                            Text(status.emoji)
                            Text(status.rawValue.capitalized)
                            Spacer()
                            if status == currentStatus {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Update Match Quality")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


import UniformTypeIdentifiers

struct ImageFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    let image: UIImage
    let filename: String

    init(image: UIImage, filename: String) {
        self.image = image
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        fatalError("Not needed")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
