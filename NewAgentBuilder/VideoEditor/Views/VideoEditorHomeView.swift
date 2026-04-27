//
//  VideoEditorHomeView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//

import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct VideoEditorHomeView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel = VideoEditorViewModel()
    @State private var showingClearAllConfirm = false

    /// Projects ready for Move Editor (exported or ready to export)
    private var readyForMovesProjects: [VideoProject] {
        viewModel.projects.filter { $0.status == .readyToExport || $0.status == .exported }
    }

    /// Projects still being consolidated (not yet exported)
    private var consolidationProjects: [VideoProject] {
        viewModel.projects.filter { $0.status != .readyToExport && $0.status != .exported }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Create New Project
                createProjectSection

                // Ready for Moves - direct access to Stage 2
                if !readyForMovesProjects.isEmpty {
                    readyForMovesSection
                }

                // Consolidation Projects (Stage 1 - in progress)
                if !consolidationProjects.isEmpty {
                    consolidationProjectsSection
                }
            }
            .padding()
        }
        .navigationTitle("Video Editor")
        .task {
            await viewModel.loadProjects()
        }
        .sheet(isPresented: $viewModel.showingFilePicker) {
            VideoFilePicker(onSelect: { url in
                Task {
                    await viewModel.createProject(from: url)
                }
            })
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Video Processing")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Import video, transcribe with Whisper, remove pauses, select best takes, export to Final Cut Pro.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Create Project Section

    private var createProjectSection: some View {
        VStack(spacing: 16) {
            Button {
                viewModel.showingFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("Import Video")
                            .font(.headline)
                        Text("Select a video file to start a new project")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Ready for Moves Section

    private var readyForMovesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)
                Text("Ready for Moves")
                    .font(.headline)
                Spacer()
                Text("\(readyForMovesProjects.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }

            Text("Click to open in Move Editor (Stage 2)")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(readyForMovesProjects) { project in
                ReadyForMovesCard(project: project) {
                    // Go directly to Move Editor
                    nav.push(.videoEditorMoveEditor(project))
                }
            }
        }
    }

    // MARK: - Consolidation Projects Section

    private var consolidationProjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scissors")
                    .foregroundColor(.orange)
                Text("Consolidation (Stage 1)")
                    .font(.headline)
                Spacer()

                Button {
                    showingClearAllConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .confirmationDialog("Clear All Projects?", isPresented: $showingClearAllConfirm) {
                    Button("Clear All Projects", role: .destructive) {
                        viewModel.clearAllProjects()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all projects.")
                }

                Text("\(consolidationProjects.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }

            ForEach(consolidationProjects) { project in
                ProjectCard(project: project) {
                    nav.push(.videoEditorProject(project))
                } onDelete: {
                    Task {
                        await viewModel.deleteProject(project)
                    }
                }
            }
        }
    }
}

// MARK: - Ready for Moves Card

struct ReadyForMovesCard: View {
    let project: VideoProject
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "film.stack")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)

                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Text(project.status.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if project.appliedMoves.count > 0 {
                            Text("\(project.appliedMoves.count) moves")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                Text("Open Move Editor")
                    .font(.caption)
                    .foregroundColor(.blue)

                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: VideoProject
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: project.status.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)

                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Text(project.status.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // REFACTOR NOTE: Using videoDurationSeconds for TimeInterval display
                        if let duration = project.videoDurationSeconds {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Progress indicators
                    if project.pendingGapsCount > 0 || project.pendingDuplicatesCount > 0 {
                        HStack(spacing: 12) {
                            if project.pendingGapsCount > 0 {
                                Label("\(project.pendingGapsCount) gaps", systemImage: "scissors")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if project.pendingDuplicatesCount > 0 {
                                Label("\(project.pendingDuplicatesCount) duplicates", systemImage: "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                Spacer()

                // Delete button
                Button {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Delete Project?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the project and all its data.")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video File Picker

struct VideoFilePicker: View {
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        Text("Use File > Open to select a video")
            .onAppear {
                openFilePicker()
            }
        #else
        VideoDocumentPicker(onSelect: { url in
            onSelect(url)
            dismiss()
        })
        #endif
    }

    #if os(macOS)
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
        dismiss()
    }
    #endif
}

#if os(iOS)
struct VideoDocumentPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            _ = url.startAccessingSecurityScopedResource()

            onSelect(url)
            // Note: Don't stop accessing here - the view model will handle it
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Document picker cancelled")
        }
    }
}
#endif
