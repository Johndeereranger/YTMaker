//
//  PresetDetailView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Detail view for viewing and editing a preset.
//

import SwiftUI

struct PresetDetailView: View {
    let preset: any EditPreset
    let onSave: (any EditPreset) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""
    @State private var editedDescription: String = ""
    @State private var editedTags: String = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section("Basic Info") {
                    TextField("Name", text: $editedName)

                    TextField("Description", text: $editedDescription, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Tags (comma-separated)", text: $editedTags)
                }

                // Type-specific info
                Section("Details") {
                    HStack {
                        Text("Type")
                        Spacer()
                        Label(preset.editType.displayName, systemImage: preset.editType.icon)
                            .foregroundColor(.secondary)
                    }

                    if let source = preset.sourceFile {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(source)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Created")
                        Spacer()
                        Text(preset.createdAt, style: .date)
                            .foregroundColor(.secondary)
                    }
                }

                // Type-specific details
                typeSpecificSection

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Preset", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Preset Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editedName = preset.name
                editedDescription = preset.description ?? ""
                editedTags = preset.tags.joined(separator: ", ")
            }
            .confirmationDialog("Delete Preset?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This preset will be permanently deleted.")
            }
        }
    }

    // MARK: - Type-Specific Section

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch preset.editType {
        case .transform:
            if let transform = preset as? TransformPreset {
                transformSection(transform)
            }

        case .textOverlay:
            if let textOverlay = preset as? TextOverlayPreset {
                textOverlaySection(textOverlay)
            }

        case .transition:
            if let transition = preset as? TransitionPreset {
                transitionSection(transition)
            }

        case .bRoll:
            if let bRoll = preset as? BRollPreset {
                bRollSection(bRoll)
            }
        }
    }

    private func transformSection(_ transform: TransformPreset) -> some View {
        Section("Transform Properties") {
            if transform.position != nil {
                HStack {
                    Text("Position Animation")
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            }

            if transform.scale != nil {
                HStack {
                    Text("Scale Animation")
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            }

            if transform.rotation != nil {
                HStack {
                    Text("Rotation Animation")
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            }

            HStack {
                Text("Anchor Edge")
                Spacer()
                Text(transform.anchorEdge == .start ? "Start" : "End")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func textOverlaySection(_ textOverlay: TextOverlayPreset) -> some View {
        Section("Text Style") {
            HStack {
                Text("Template")
                Spacer()
                Text(textOverlay.templateName)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Font")
                Spacer()
                Text("\(textOverlay.fontFamily) \(textOverlay.fontFace)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Size")
                Spacer()
                Text("\(Int(textOverlay.fontSize)) pt")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Alignment")
                Spacer()
                Text(textOverlay.alignment.rawValue.capitalized)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Lane")
                Spacer()
                Text("\(textOverlay.lane)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func transitionSection(_ transition: TransitionPreset) -> some View {
        Section("Transition Properties") {
            HStack {
                Text("Effect")
                Spacer()
                Text(transition.effectName)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Duration")
                Spacer()
                Text(String(format: "%.2fs", transition.defaultDuration.seconds))
                    .foregroundColor(.secondary)
            }

            if !transition.parameters.isEmpty {
                HStack {
                    Text("Parameters")
                    Spacer()
                    Text("\(transition.parameters.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func bRollSection(_ bRoll: BRollPreset) -> some View {
        Section("B-Roll Properties") {
            if let mediaRef = bRoll.mediaReference {
                HStack {
                    Text("Media")
                    Spacer()
                    Text(mediaRef.fileName)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Lane")
                Spacer()
                Text("\(bRoll.lane)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Audio")
                Spacer()
                Text(bRoll.audioBehavior.displayName)
                    .foregroundColor(.secondary)
            }

            if bRoll.transform != nil {
                HStack {
                    Text("Has Transform")
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Save

    private func saveChanges() {
        // Parse tags
        let tags = editedTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Would need to create updated copy based on type
        // For now this is a placeholder - real implementation would
        // update the specific preset type and save via storage service
        print("Saving preset with name: \(editedName), tags: \(tags)")
    }
}

// MARK: - Preview

#Preview {
    PresetDetailView(
        preset: TransformPreset(
            name: "Sample Transform",
            description: "A sample transform for preview",
            tags: ["sample", "preview"]
        ),
        onSave: { _ in },
        onDelete: { }
    )
}
