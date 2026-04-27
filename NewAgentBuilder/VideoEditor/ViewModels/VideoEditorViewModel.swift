//
//  VideoEditorViewModel.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class VideoEditorViewModel: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var isLoading = false
    @Published var showingFilePicker = false
    @Published var showingError = false
    @Published var errorMessage: String?

    private let storageKey = "VideoEditorProjects"

    // MARK: - Load Projects

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        // Load from UserDefaults for now (local-first)
        // TODO: Could migrate to Firebase later if needed
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([VideoProject].self, from: data) {
            projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: - Save Projects

    private func saveProjects() {
        if let encoded = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - Create Project

    func createProject(from videoURL: URL) async {
        // Create bookmark for sandbox-safe access
        guard let bookmarkData = VideoProject.createBookmark(from: videoURL) else {
            errorMessage = "Failed to create bookmark for video file"
            showingError = true
            return
        }

        // Get video duration
        let asset = AVAsset(url: videoURL)
        let videoDuration: CodableCMTime
        do {
            let durationCMTime = try await asset.load(.duration)
            // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime
            // OLD CODE: duration = CMTimeGetSeconds(durationCMTime)
            videoDuration = CodableCMTime(durationCMTime)
        } catch {
            errorMessage = "Failed to load video duration: \(error.localizedDescription)"
            showingError = true
            return
        }

        // Create project
        let projectName = videoURL.deletingPathExtension().lastPathComponent
        let project = VideoProject(
            name: projectName,
            videoBookmarkData: bookmarkData,
            videoFileName: videoURL.lastPathComponent,
            videoDuration: videoDuration,
            status: .videoImported
        )

        projects.insert(project, at: 0)
        saveProjects()

        // Stop accessing security scoped resource if on iOS
        videoURL.stopAccessingSecurityScopedResource()
    }

    // MARK: - Delete Project

    func deleteProject(_ project: VideoProject) async {
        projects.removeAll { $0.id == project.id }
        saveProjects()
    }

    // MARK: - Clear All Projects

    func clearAllProjects() {
        projects.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("🗑️ All video editor projects cleared")
    }

    // MARK: - Update Project

    func updateProject(_ project: VideoProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.updatedAt = Date()
            projects[index] = updated
            saveProjects()
        }
    }

    // MARK: - Get Project

    func getProject(id: UUID) -> VideoProject? {
        projects.first { $0.id == id }
    }
}
