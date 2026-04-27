//
//  VideoEditorProjectView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Updated to use seconds accessors for CodableCMTime models.
//

import SwiftUI
import AVKit
import CoreMedia

struct VideoEditorProjectView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel: VideoProjectViewModel

    // Timeline state (local since it's UI-only)
    @State private var zoomLevel: Double = 30

    // Preview mode is controlled by viewModel.isPreviewingCuts
    // This is the single source of truth for both video and timeline

    init(project: VideoProject) {
        _viewModel = StateObject(wrappedValue: VideoProjectViewModel(project: project))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top: Video Preview
                videoPreviewSection
                    .frame(height: geometry.size.height * 0.4)

                Divider()

                // Middle: Timeline (placeholder for now)
                timelineSection
                    .frame(height: geometry.size.height * 0.2)

                Divider()

                // Bottom: Controls & Status
                controlsSection
                    .frame(height: geometry.size.height * 0.4)
            }
        }
        .navigationTitle(viewModel.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button {
                        viewModel.copyProjectDebugReport()
                    } label: {
                        Label("Gap Debug", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        viewModel.copyWaveformDebugReport()
                    } label: {
                        Label("Waveform Debug", systemImage: "waveform")
                    }
                    .disabled(viewModel.project.waveformData == nil)
                } label: {
                    Label("Debug", systemImage: "ladybug")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        // Export action
                    } label: {
                        Label("Export FCPXML", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.project.status != .readyToExport)

                    Button(role: .destructive) {
                        // Reset action
                    } label: {
                        Label("Reset Project", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            viewModel.reloadProject()
            viewModel.loadVideo()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Video Preview Section

    private var videoPreviewSection: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .cornerRadius(8)
                        .padding()
                } else if viewModel.isLoadingVideo {
                    VStack {
                        ProgressView()
                        Text("Loading video...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Could not load video")
                            .font(.headline)
                        if let error = viewModel.videoError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Preview mode indicator (only show if we have cuts and in preview mode)
            if viewModel.isPreviewingCuts && hasCutsToPreview {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                        Text("Preview Mode")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)

                    Text("\(cutsCount) cuts applied • \(formatCutTime())s saved")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
                .padding()
            }

            // Loading indicator when switching modes
            if viewModel.isLoadingPreview {
                VStack {
                    ProgressView()
                    Text("Loading preview...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
        }
        .background(Color.black.opacity(0.1))
    }

    private var hasCutsToPreview: Bool {
        viewModel.project.detectedGaps.contains {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }
    }

    private var cutsCount: Int {
        viewModel.project.detectedGaps.filter {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }.count
    }

    private func formatCutTime() -> String {
        let targetPause = viewModel.project.settings.targetPauseDuration
        let totalCutTime = viewModel.project.detectedGaps
            .filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }
            .reduce(0.0) { total, gap in
                // Only count the actual amount being cut (gap duration - kept pause)
                let keepDuration = min(targetPause, gap.durationSeconds)
                return total + max(0, gap.durationSeconds - keepDuration)
            }
        return String(format: "%.1f", totalCutTime)
    }

    /// Format time showing frames for small values
    private func formatFrameTime(_ time: TimeInterval) -> String {
        if time < 0.1 {
            // Show as frames (assuming 30fps)
            let frames = Int(round(time * 30))
            return "\(frames)f"
        } else {
            return String(format: "%.2fs", time)
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        Group {
            // Show timeline if we have duration AND (waveform OR transcription)
            // REFACTOR NOTE: Using videoDurationSeconds for TimeInterval parameter
            if let duration = viewModel.project.videoDurationSeconds,
               (viewModel.project.waveformData != nil || viewModel.project.isTranscribed) {
                TimelineView(
                    duration: duration,
                    words: viewModel.project.transcribedWords,
                    segments: viewModel.project.speechSegments,
                    gaps: viewModel.project.detectedGaps,
                    waveformData: viewModel.project.waveformData,
                    targetPauseDuration: viewModel.project.settings.targetPauseDuration,
                    currentTime: Binding(
                        get: { viewModel.currentPlaybackTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    zoomLevel: $zoomLevel,
                    previewMode: Binding(
                        get: { viewModel.isPreviewingCuts },
                        set: { newValue in
                            Task {
                                await viewModel.setPreviewMode(newValue)
                            }
                        }
                    ),
                    onSeek: { time in
                        viewModel.seek(to: time)
                    }
                )
            } else if viewModel.isExtractingWaveform {
                VStack {
                    ProgressView(value: viewModel.waveformProgress)
                        .frame(width: 200)
                    Text("Extracting waveform...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.1))
            } else {
                VStack {
                    Text("No waveform yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Detect gaps or transcribe to see timeline")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.1))
            }
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status card
                statusCard

                // Action buttons based on status
                actionButtons

                // Settings (collapsible)
                settingsSection
            }
            .padding()
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.project.status.icon)
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.project.status.displayName)
                    .font(.headline)

                if viewModel.isExtractingWaveform {
                    ProgressView(value: viewModel.waveformProgress)
                        .progressViewStyle(.linear)
                    Text(viewModel.transcriptionStatus.isEmpty ? "Extracting waveform \(Int(viewModel.waveformProgress * 100))%" : viewModel.transcriptionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if viewModel.isLoadingModel {
                    Text("Downloading Whisper model (first time only)...")
                        .font(.caption)
                        .foregroundColor(.orange)
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let progress = viewModel.transcriptionProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(viewModel.transcriptionStatus.isEmpty ? "\(Int(progress * 100))%" : viewModel.transcriptionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = viewModel.modelLoadError {
                    Text("Model error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // Show what data is available
                HStack(spacing: 8) {
                    if viewModel.project.waveformData != nil {
                        Label("Waveform", systemImage: "waveform.path")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if viewModel.project.isTranscribed {
                        Label("\(viewModel.project.transcribedWords.count) words", systemImage: "text.alignleft")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if !viewModel.project.detectedGaps.isEmpty {
                        Label("\(viewModel.project.detectedGaps.count) gaps", systemImage: "scissors")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.project.status {
        case .created, .videoImported:
            VStack(spacing: 12) {
                // Primary: Quick gap detection (no transcription needed)
                Button {
                    Task {
                        await viewModel.extractWaveformAndDetectGaps()
                    }
                } label: {
                    Label("Detect Gaps (Fast)", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(viewModel.isExtractingWaveform)

                // Secondary: Full transcription
                Button {
                    Task {
                        await viewModel.startTranscription()
                    }
                } label: {
                    Label("Transcribe with Whisper", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(viewModel.isTranscribing)

                Text("Waveform detection is sample-accurate. Transcription shows what was said (text only).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .transcribing:
            Button {
                viewModel.cancelTranscription()
            } label: {
                Label("Cancel", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
            .tint(.red)

        case .transcribed:
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.detectGaps()
                    }
                } label: {
                    Label("Detect Gaps & Pauses", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())

                if viewModel.project.waveformData == nil {
                    Text("Will extract waveform for sample-accurate detection")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

        case .gapsDetected, .reviewing:
            VStack(spacing: 12) {
                // Show gap count even if 0 pending (for re-review)
                let gapCount = viewModel.project.detectedGaps.count
                let pendingCount = viewModel.project.pendingGapsCount
                let cutsCount = viewModel.project.detectedGaps.filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }.count
                let targetPause = viewModel.project.settings.targetPauseDuration
                let totalCutTime = viewModel.project.detectedGaps
                    .filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }
                    .reduce(0.0) { total, gap in
                        // Only count the actual amount being cut (gap duration - kept pause)
                        let keepDuration = min(targetPause, gap.durationSeconds)
                        return total + max(0, gap.durationSeconds - keepDuration)
                    }

                // Gap detection controls
                VStack(spacing: 12) {
                    // Summary row
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(gapCount) gaps detected")
                                .font(.headline)
                            Text("\(cutsCount) will be cut • \(String(format: "%.1f", totalCutTime))s removed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        // Re-analyze button
                        Button {
                            Task {
                                await viewModel.detectGaps()
                            }
                        } label: {
                            Label("Re-analyze", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                    }

                    Divider()

                    // Quick settings
                    VStack(spacing: 10) {
                        // Silence threshold
                        HStack {
                            Text("Silence Threshold")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(viewModel.project.settings.silenceThreshold * 100))%")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.project.settings.silenceThreshold },
                                set: { viewModel.updateSetting(\.silenceThreshold, value: $0) }
                            ),
                            in: 0.02...0.25,
                            step: 0.01
                        )

                        // Min gap detection (frame-level precision: 1 frame @ 30fps ≈ 0.033s)
                        HStack {
                            Text("Min Gap to Detect")
                                .font(.caption)
                            Spacer()
                            Text(formatFrameTime(viewModel.project.settings.minimumGapDuration))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.project.settings.minimumGapDuration },
                                set: { viewModel.updateSetting(\.minimumGapDuration, value: $0) }
                            ),
                            in: 0.033...0.5,  // ~1 frame at 30fps to 0.5s
                            step: 0.017       // ~half frame increments
                        )

                        Divider()

                        // Target pause duration (what to keep when cutting)
                        HStack {
                            Text("Keep Pause")
                                .font(.caption)
                            Spacer()
                            Text(formatFrameTime(viewModel.project.settings.targetPauseDuration))
                                .font(.caption)
                                .foregroundColor(.green)
                                .frame(width: 50, alignment: .trailing)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.project.settings.targetPauseDuration },
                                set: { viewModel.updateSetting(\.targetPauseDuration, value: $0) }
                            ),
                            in: 0.0...0.5,
                            step: 0.05
                        )
                        Text("Gaps are trimmed to this duration, not removed entirely")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Adjust settings and tap Re-analyze to update gap detection")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Button {
                    nav.push(.videoEditorGapReview(viewModel.project))
                } label: {
                    if pendingCount > 0 {
                        Label("Review \(pendingCount) Gaps", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Review Gaps (\(gapCount) total)", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(pendingCount > 0 ? .orange : .blue)

                // Option to add transcription if not done yet
                if !viewModel.project.isTranscribed {
                    Button {
                        Task {
                            await viewModel.startTranscription()
                        }
                    } label: {
                        Label("Add Transcription (word-level detail)", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(viewModel.isTranscribing)

                    Text("Transcription adds readable text (timing is from waveform, not words)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Duplicate detection (requires transcription)
                if viewModel.project.isTranscribed {
                    if viewModel.project.repeatedPhrases.isEmpty {
                        // Option to detect duplicates
                        Button {
                            Task {
                                await viewModel.detectDuplicates()
                            }
                        } label: {
                            Label("Detect Duplicate Phrases", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(viewModel.isDetectingDuplicates)

                        Text("Find repeated sentences/phrases (multiple takes)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if viewModel.project.pendingDuplicatesCount > 0 {
                        // Review duplicates
                        Button {
                            nav.push(.videoEditorDuplicateReview(viewModel.project))
                        } label: {
                            Label("Review \(viewModel.project.pendingDuplicatesCount) Duplicates", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .tint(.orange)
                    } else if !viewModel.project.repeatedPhrases.isEmpty {
                        // All duplicates resolved - show summary
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(viewModel.project.repeatedPhrases.count) duplicates resolved")
                                .font(.subheadline)
                            Spacer()
                            Button("Review") {
                                nav.push(.videoEditorDuplicateReview(viewModel.project))
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if viewModel.project.pendingGapsCount == 0 && viewModel.project.pendingDuplicatesCount == 0 {
                    // Stage 2: Go to Move Editor to apply zooms/pans
                    Button {
                        nav.push(.videoEditorMoveEditor(viewModel.project))
                    } label: {
                        Label("Continue to Move Editor", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(.blue)

                    // Or skip directly to export
                    Button {
                        viewModel.markReadyToExport()
                    } label: {
                        Label("Skip to Export", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
            }

        case .readyToExport:
            VStack(spacing: 12) {
                // Primary action: Go to Move Editor
                Button {
                    nav.push(.videoEditorMoveEditor(viewModel.project))
                } label: {
                    Label("Continue to Move Editor", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.blue)

                // Secondary: Export directly
                Button {
                    Task {
                        await viewModel.exportFCPXML()
                    }
                } label: {
                    Label("Export FCPXML", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
            }

        case .exported:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                Text("Project Exported")
                    .font(.headline)

                // Can still go to Move Editor after export
                Button {
                    nav.push(.videoEditorMoveEditor(viewModel.project))
                } label: {
                    Label("Open Move Editor", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.blue)

                Button {
                    Task {
                        await viewModel.exportFCPXML()
                    }
                } label: {
                    Text("Export Again")
                }
                .buttonStyle(BorderedButtonStyle())
            }
        }
    }

    private var settingsSection: some View {
        DisclosureGroup("Gap Detection Settings") {
            VStack(alignment: .leading, spacing: 16) {
                // Min Gap Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Min Gap Duration")
                        Spacer()
                        Text("\(viewModel.project.settings.minimumGapDuration, specifier: "%.1f")s")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.project.settings.minimumGapDuration },
                            set: { viewModel.updateSetting(\.minimumGapDuration, value: $0) }
                        ),
                        in: 0.1...1.0,
                        step: 0.1
                    )
                    Text("Gaps shorter than this are ignored")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Silence threshold (waveform sensitivity)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Silence Threshold")
                        Spacer()
                        Text("\(Int(viewModel.project.settings.silenceThreshold * 100))%")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.project.settings.silenceThreshold },
                            set: { viewModel.updateSetting(\.silenceThreshold, value: $0) }
                        ),
                        in: 0.02...0.25,
                        step: 0.01
                    )
                    Text("Lower = more sensitive (detects quieter sounds as speech)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Auto-review threshold
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Auto-Review Threshold")
                        Spacer()
                        Text("\(viewModel.project.settings.autoReviewThreshold, specifier: "%.1f")s")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.project.settings.autoReviewThreshold },
                            set: { viewModel.updateSetting(\.autoReviewThreshold, value: $0) }
                        ),
                        in: 1.0...5.0,
                        step: 0.5
                    )
                    Text("Gaps longer than this are flagged for review")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Waveform status
                if viewModel.project.waveformData != nil {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.green)
                        Text("Waveform available (sample-accurate)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 4)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("No waveform yet - run gap detection to extract")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }

                // Re-detect button
                if viewModel.project.isTranscribed {
                    Button {
                        Task {
                            await viewModel.detectGaps()
                        }
                    } label: {
                        Label("Re-detect Gaps with New Settings", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .padding(.top, 8)
                }
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Video Project ViewModel

@MainActor
class VideoProjectViewModel: ObservableObject {
    @Published var project: VideoProject
    @Published var player: AVPlayer?
    @Published var isLoadingVideo = false
    @Published var videoError: String?
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double?
    @Published var transcriptionStatus: String = ""
    @Published var isLoadingModel = false
    @Published var modelLoadError: String?
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var isExtractingWaveform = false
    @Published var waveformProgress: Double = 0
    @Published var isPreviewingCuts = false
    @Published var isLoadingPreview = false
    @Published var isDetectingDuplicates = false

    private var videoURL: URL?
    private var transcriptionTask: Task<Void, Never>?
    private let transcriptionService = WhisperTranscriptionService.shared
    private let waveformService = AudioWaveformService.shared
    private let previewCompositionService = PreviewCompositionService.shared
    private let duplicateDetectionService = DuplicateDetectionService.shared
    private var timeObserver: Any?

    init(project: VideoProject) {
        self.project = project
    }

    // MARK: - Reload Project

    /// Reload project from storage to pick up changes from other views (e.g., gap review)
    func reloadProject() {
        let oldGapCount = project.detectedGaps.count
        let wasPreviewingCuts = isPreviewingCuts

        if let data = UserDefaults.standard.data(forKey: "VideoEditorProjects"),
           let projects = try? JSONDecoder().decode([VideoProject].self, from: data),
           let updatedProject = projects.first(where: { $0.id == project.id }) {
            project = updatedProject

            // CRITICAL: Repair duplicate rejection gaps
            // If user changed their selection, old gaps may be left behind
            var needsSave = false
            let beforeRepair = project.detectedGaps.count
            repairDuplicateRejectionGaps()
            if project.detectedGaps.count != beforeRepair {
                print("🔧 Repaired duplicate rejection gaps: \(beforeRepair) → \(project.detectedGaps.count)")
                needsSave = true
            }

            // Also merge any overlapping gaps
            let beforeMerge = project.detectedGaps.count
            project.detectedGaps = mergeOverlappingGaps(project.detectedGaps)
            if project.detectedGaps.count != beforeMerge {
                print("🔗 Merged overlapping gaps: \(beforeMerge) → \(project.detectedGaps.count)")
                needsSave = true
            }

            if needsSave {
                saveProject()
            }

            let autoRemovedCount = project.detectedGaps.filter { $0.removalStatus == .autoRemoved }.count
            print("🔄 Project reloaded: \(project.detectedGaps.count) gaps (was \(oldGapCount)), \(autoRemovedCount) auto-removed, status: \(project.status.displayName)")

            // If gaps changed and preview was on, force rebuild
            if project.detectedGaps.count != oldGapCount && wasPreviewingCuts {
                print("🔄 Gaps changed while preview was on - forcing rebuild")
                isPreviewingCuts = false
                Task {
                    await setPreviewMode(true)
                }
            }
        }
    }

    // MARK: - Load Video

    func loadVideo() {
        isLoadingVideo = true
        videoError = nil

        guard let url = project.resolveVideoURL() else {
            videoError = "Could not resolve video file location"
            isLoadingVideo = false
            return
        }

        // Start accessing security-scoped resource (may not be needed on iOS/Catalyst but safe to call)
        _ = url.startAccessingSecurityScopedResource()

        videoURL = url
        player = AVPlayer(url: url)
        isLoadingVideo = false

        // Set up time observer for playhead sync
        setupTimeObserver()
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        guard let player = player else { return }

        // Remove existing observer if any
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }

        // Observe time every 0.05 seconds for smooth playhead movement
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentPlaybackTime = time.seconds
            }
        }
    }

    // MARK: - Seek

    func seek(to time: TimeInterval) {
        guard let player = player else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentPlaybackTime = time
    }

    // MARK: - Transcription

    func startTranscription() async {
        guard let videoURL = videoURL else {
            videoError = "No video loaded"
            return
        }

        isTranscribing = true
        transcriptionProgress = 0.0
        transcriptionStatus = "Preparing..."
        project.status = .transcribing

        // Load model if needed
        if !transcriptionService.isModelLoaded {
            isLoadingModel = true
            transcriptionStatus = "Downloading Whisper model..."

            do {
                try await transcriptionService.loadModel(.base)
                isLoadingModel = false
            } catch {
                isLoadingModel = false
                modelLoadError = error.localizedDescription
                isTranscribing = false
                project.status = .videoImported
                return
            }
        }

        // Start transcription
        transcriptionTask = Task {
            do {
                let words = try await transcriptionService.transcribe(
                    videoURL: videoURL,
                    onProgress: { [weak self] progress, status in
                        Task { @MainActor in
                            self?.transcriptionProgress = progress
                            self?.transcriptionStatus = status
                        }
                    }
                )

                // Store results
                project.transcribedWords = words

                // Build speech segments from words
                project.speechSegments = buildSpeechSegments(from: words)

                // Check if gaps were already detected (waveform-only detection)
                let hadGaps = !project.detectedGaps.isEmpty

                if hadGaps {
                    // Keep the gapsDetected status since we had gaps
                    project.status = .gapsDetected
                } else {
                    project.status = .transcribed
                }

                isTranscribing = false
                transcriptionProgress = nil
                transcriptionStatus = ""

                print("✅ Transcription complete: \(words.count) words, \(project.speechSegments.count) segments")
                print("📊 Status set to: \(project.status.displayName)")

                // Save project
                saveProject()

                print("💾 Project saved, status: \(project.status.displayName)")

                // Extract waveform for visualization
                await extractWaveform()

                // Note: We don't re-detect gaps here. Waveform-based detection is more accurate
                // than word timestamps. Whisper words are good for text, not timing.

            } catch {
                print("❌ Transcription failed: \(error)")
                videoError = error.localizedDescription
                isTranscribing = false
                transcriptionProgress = nil
                transcriptionStatus = ""
                project.status = .videoImported
            }
        }
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
        transcriptionProgress = nil
        transcriptionStatus = ""
        project.status = .videoImported
    }

    // MARK: - Waveform Extraction

    func extractWaveform() async {
        guard let videoURL = videoURL else { return }

        // Skip if already extracted
        if project.waveformData != nil {
            print("📊 Waveform already extracted, skipping")
            return
        }

        isExtractingWaveform = true
        waveformProgress = 0

        do {
            let waveform = try await waveformService.extractWaveform(
                from: videoURL,
                samplesPerSecond: 50,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.waveformProgress = progress
                    }
                }
            )

            project.waveformData = waveform
            saveProject()

            print("✅ Waveform extracted: \(waveform.samples.count) samples")
        } catch {
            print("⚠️ Waveform extraction failed: \(error)")
            // Non-fatal - waveform is optional
        }

        isExtractingWaveform = false
    }

    /// Quick gap detection without transcription - uses waveform only
    func extractWaveformAndDetectGaps() async {
        guard let videoURL = videoURL else {
            videoError = "No video loaded"
            return
        }

        isExtractingWaveform = true
        waveformProgress = 0
        transcriptionStatus = "Extracting audio waveform..."

        // Step 1: Extract waveform if needed
        if project.waveformData == nil {
            do {
                let waveform = try await waveformService.extractWaveform(
                    from: videoURL,
                    samplesPerSecond: 50,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.waveformProgress = progress
                        }
                    }
                )
                project.waveformData = waveform
                print("✅ Waveform extracted: \(waveform.samples.count) samples")
            } catch {
                print("❌ Waveform extraction failed: \(error)")
                videoError = "Failed to extract audio: \(error.localizedDescription)"
                isExtractingWaveform = false
                transcriptionStatus = ""
                return
            }
        }

        // Step 2: Detect gaps from waveform (no transcription needed)
        transcriptionStatus = "Detecting gaps..."

        if let waveform = project.waveformData {
            // Detect silence regions directly from waveform
            let gaps = silenceDetectionService.detectGapsFromWaveform(
                waveform: waveform,
                words: [], // No words yet - pure waveform detection
                settings: project.settings
            )

            project.detectedGaps = gaps
            project.status = .gapsDetected
            saveProject()

            print("✅ Quick gap detection complete: \(gaps.count) gaps found")
            print("ℹ️  Note: Word boundaries not available - run transcription for refined detection")
        }

        isExtractingWaveform = false
        transcriptionStatus = ""
    }

    // MARK: - Build Speech Segments

    // REFACTOR NOTE: Using startSeconds/endSeconds for SpeechSegment creation
    private func buildSpeechSegments(from words: [TranscribedWord]) -> [SpeechSegment] {
        guard !words.isEmpty else { return [] }

        var segments: [SpeechSegment] = []
        var currentSegmentWords: [TranscribedWord] = []
        var segmentStart: TimeInterval = words[0].startSeconds

        let gapThreshold: TimeInterval = 0.5 // Gap larger than this starts new segment

        for (index, word) in words.enumerated() {
            if index > 0 {
                let previousWord = words[index - 1]
                let gap = word.startSeconds - previousWord.endSeconds

                if gap > gapThreshold {
                    // End current segment
                    if !currentSegmentWords.isEmpty {
                        let segment = SpeechSegment(
                            startSeconds: segmentStart,
                            endSeconds: previousWord.endSeconds,
                            wordIds: currentSegmentWords.map { $0.id }
                        )
                        segments.append(segment)
                    }

                    // Start new segment
                    currentSegmentWords = []
                    segmentStart = word.startSeconds
                }
            }

            currentSegmentWords.append(word)
        }

        // Don't forget the last segment
        if !currentSegmentWords.isEmpty, let lastWord = currentSegmentWords.last {
            let segment = SpeechSegment(
                startSeconds: segmentStart,
                endSeconds: lastWord.endSeconds,
                wordIds: currentSegmentWords.map { $0.id }
            )
            segments.append(segment)
        }

        return segments
    }

    // MARK: - Gap Detection

    private let gapDetectionService = GapDetectionService.shared
    private let silenceDetectionService = SilenceDetectionService.shared

    func detectGaps() async {
        print("🔍 Starting gap detection...")

        // Waveform-based detection is authoritative - it's sample-accurate
        // Word timestamps from Whisper are NOT reliable for timing (50-100ms off, often wrong)
        if let waveform = project.waveformData {
            print("📊 Using waveform-based silence detection (authoritative)")

            // Pure waveform detection - don't use word boundaries, they're less accurate
            let gaps = silenceDetectionService.detectGapsFromWaveform(
                waveform: waveform,
                words: [], // Don't use words - waveform is ground truth
                settings: project.settings
            )

            project.detectedGaps = gaps
            project.status = .gapsDetected
            saveProject()

            print("✅ Waveform gap detection complete: \(gaps.count) gaps found")
        } else {
            // No waveform - need to extract it first
            print("⚠️ No waveform data - extracting now...")
            await extractWaveformAndDetectGaps()
        }
    }

    // MARK: - Duplicate Detection

    func detectDuplicates() async {
        guard project.isTranscribed else {
            print("⚠️ Cannot detect duplicates without transcription")
            return
        }

        isDetectingDuplicates = true
        defer { isDetectingDuplicates = false }

        print("🔍 Starting duplicate phrase detection...")

        let duplicates = duplicateDetectionService.detectDuplicates(
            words: project.transcribedWords,
            settings: project.settings
        )

        project.repeatedPhrases = duplicates
        saveProject()

        if duplicates.isEmpty {
            print("✅ No duplicate phrases found")
        } else {
            print("✅ Found \(duplicates.count) duplicate phrases to review")
        }
    }

    // MARK: - Preview Mode (Unified)

    /// Set preview mode - syncs video player with timeline preview state
    /// When preview is ON: video plays cut composition, timeline shows collapsed waveform
    /// When preview is OFF: video plays original, timeline shows full waveform with gaps
    func setPreviewMode(_ enabled: Bool) async {
        guard let videoURL = videoURL else { return }

        if enabled {
            // Switch to preview mode
            let cutsToApply = project.detectedGaps.filter {
                $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
            }

            guard !cutsToApply.isEmpty else {
                print("⚠️ No cuts to preview - staying in edit mode")
                isPreviewingCuts = false
                return
            }

            isLoadingPreview = true

            do {
                // Create preview composition with target pause duration setting
                // Pass waveform data so cut points are refined to actual silence
                let previewItem = try await previewCompositionService.createPreviewComposition(
                    sourceURL: videoURL,
                    cuts: cutsToApply,
                    targetPauseDuration: project.settings.targetPauseDuration,
                    waveformData: project.waveformData
                )

                // Replace player item with preview composition
                player?.replaceCurrentItem(with: previewItem)
                isPreviewingCuts = true
                print("🎬 Preview mode ON (\(cutsToApply.count) cuts applied)")
            } catch {
                print("❌ Failed to create preview: \(error)")
                videoError = "Preview failed: \(error.localizedDescription)"
            }

            isLoadingPreview = false
        } else {
            // Switch back to edit mode - create NEW player item from original URL
            // (AVPlayerItem cannot be reused once associated with a player)
            let originalItem = AVPlayerItem(url: videoURL)
            player?.replaceCurrentItem(with: originalItem)
            isPreviewingCuts = false
            print("🎬 Edit mode ON (original video)")
        }
    }

    // MARK: - Export

    func markReadyToExport() {
        project.status = .readyToExport
        saveProject()
    }

    func exportFCPXML() async {
        // TODO: Implement FCPXML generation
        project.status = .exported
        saveProject()
    }

    // MARK: - Settings

    func updateSetting<T>(_ keyPath: WritableKeyPath<ProjectSettings, T>, value: T) {
        project.settings[keyPath: keyPath] = value
        saveProject()
    }

    // MARK: - Save

    private func saveProject() {
        // Update through the shared view model
        // This is a simplified approach - in production you'd use proper state management
        if let data = UserDefaults.standard.data(forKey: "VideoEditorProjects"),
           var projects = try? JSONDecoder().decode([VideoProject].self, from: data) {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                project.updatedAt = Date()
                projects[index] = project
                if let encoded = try? JSONEncoder().encode(projects) {
                    UserDefaults.standard.set(encoded, forKey: "VideoEditorProjects")
                }
            }
        }
    }

    func cleanup() {
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Stop accessing security-scoped resource
        videoURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Debug

    func copyProjectDebugReport() {
        let targetPause = project.settings.targetPauseDuration

        var report = """
        ════════════════════════════════════════════════════════════════
        VIDEO EDITOR PROJECT DEBUG REPORT
        Generated: \(Date())
        ════════════════════════════════════════════════════════════════

        PROJECT: \(project.name)
        STATUS: \(project.status.displayName)
        VIDEO DURATION: \(formatTimeMs(project.videoDurationSeconds ?? 0))
        PREVIEW MODE: \(isPreviewingCuts ? "ON" : "OFF")

        ════════════════════════════════════════════════════════════════
        SETTINGS
        ════════════════════════════════════════════════════════════════
        Target pause duration: \(String(format: "%.2f", targetPause))s
        Min gap duration: \(String(format: "%.2f", project.settings.minimumGapDuration))s
        Auto-review threshold: \(String(format: "%.2f", project.settings.autoReviewThreshold))s

        ════════════════════════════════════════════════════════════════
        ALL GAPS (\(project.detectedGaps.count) total)
        ════════════════════════════════════════════════════════════════

        """

        let sortedGaps = project.detectedGaps.sorted { $0.startTime < $1.startTime }

        for (index, gap) in sortedGaps.enumerated() {
            let willCut = gap.removalStatus == .remove || gap.removalStatus == .autoRemoved
            let cutAmount = willCut ? calculateActualCut(gap: gap, targetPause: targetPause) : nil

            report += """
            Gap \(index + 1): \(formatTimeMs(gap.startSeconds)) - \(formatTimeMs(gap.endSeconds))
              Duration: \(String(format: "%.3f", gap.durationSeconds))s
              Status: \(gap.removalStatus.displayName)
              Will cut: \(willCut ? "YES" : "NO")

            """

            if let cut = cutAmount {
                report += """
              CUT CALCULATION (centered pause):
                Gap duration: \(String(format: "%.3f", gap.durationSeconds))s
                Target pause: \(String(format: "%.3f", targetPause))s
                Half keep: \(String(format: "%.3f", cut.halfKeep))s
                Actual cut start: \(formatTimeMs(cut.cutStart))
                Actual cut end: \(formatTimeMs(cut.cutEnd))
                Time removed: \(String(format: "%.3f", cut.cutEnd - cut.cutStart))s

            """
            }
        }

        // Calculate what the preview should show
        let filteredCuts = sortedGaps.filter {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }

        // CRITICAL: Merge overlapping gaps (same as PreviewCompositionService)
        let cutsToApply = mergeOverlappingGaps(filteredCuts)

        report += """

        ════════════════════════════════════════════════════════════════
        PREVIEW COMPOSITION PLAN
        ════════════════════════════════════════════════════════════════

        Gaps before merge: \(filteredCuts.count)
        Gaps after merge: \(cutsToApply.count)

        Original duration: \(formatTimeMs(project.videoDurationSeconds ?? 0))

        SEGMENTS TO KEEP (in order):

        """

        var currentTime: TimeInterval = 0
        var outputTime: TimeInterval = 0
        var segmentIndex = 1

        for gap in cutsToApply {
            let cut = calculateActualCut(gap: gap, targetPause: targetPause)

            // Segment before this cut
            if cut.cutStart > currentTime {
                let segmentDuration = cut.cutStart - currentTime
                report += """
                Segment \(segmentIndex): KEEP
                  Source: \(formatTimeMs(currentTime)) - \(formatTimeMs(cut.cutStart))
                  Duration: \(String(format: "%.3f", segmentDuration))s
                  Output position: \(formatTimeMs(outputTime))

                """
                outputTime += segmentDuration
                segmentIndex += 1
            }

            // The cut itself
            let cutDuration = cut.cutEnd - cut.cutStart
            report += """
                [CUT]: \(formatTimeMs(cut.cutStart)) - \(formatTimeMs(cut.cutEnd))
                  Removed: \(String(format: "%.3f", cutDuration))s

            """

            currentTime = cut.cutEnd
        }

        // Final segment after last cut
        // REFACTOR NOTE: Using videoDurationSeconds for TimeInterval arithmetic
        if let duration = project.videoDurationSeconds, currentTime < duration {
            let finalDuration = duration - currentTime
            report += """
                Segment \(segmentIndex): KEEP (final)
                  Source: \(formatTimeMs(currentTime)) - \(formatTimeMs(duration))
                  Duration: \(String(format: "%.3f", finalDuration))s
                  Output position: \(formatTimeMs(outputTime))

            """
            outputTime += finalDuration
        }

        let totalRemoved = (project.videoDurationSeconds ?? 0) - outputTime
        report += """

        ════════════════════════════════════════════════════════════════
        SUMMARY
        ════════════════════════════════════════════════════════════════
        Original duration: \(formatTimeMs(project.videoDurationSeconds ?? 0))
        Preview duration: \(formatTimeMs(outputTime))
        Total removed: \(String(format: "%.3f", totalRemoved))s

        ════════════════════════════════════════════════════════════════
        END OF REPORT
        ════════════════════════════════════════════════════════════════
        """

        #if os(iOS)
        UIPasteboard.general.string = report
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif

        print("📋 Project debug report copied to clipboard (\(report.count) characters)")
    }

    /// Generate waveform-based cut boundary analysis
    /// This compares Whisper timestamps to actual audio silence boundaries
    func copyWaveformDebugReport() {
        guard let waveform = project.waveformData else {
            print("⚠️ No waveform data available")
            return
        }

        let refiner = CutBoundaryRefiner.shared
        let report = refiner.generateDebugReport(
            gaps: project.detectedGaps,
            waveform: waveform,
            targetPauseDuration: project.settings.targetPauseDuration
        )

        #if os(iOS)
        UIPasteboard.general.string = report
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif

        print("📋 Waveform debug report copied to clipboard (\(report.count) characters)")
    }

    private func calculateActualCut(gap: DetectedGap, targetPause: TimeInterval) -> (halfKeep: TimeInterval, cutStart: TimeInterval, cutEnd: TimeInterval) {
        let halfKeep = min(targetPause / 2.0, gap.durationSeconds / 2.0)
        let cutStart = gap.startSeconds + halfKeep
        let cutEnd = gap.endSeconds - halfKeep
        return (halfKeep, cutStart, cutEnd)
    }

    /// Merge overlapping or adjacent gaps into single contiguous gaps
    /// This is critical when duplicate rejection creates a gap that contains existing silence gaps
    // REFACTOR NOTE: Updated to use seconds accessors for TimeInterval comparisons
    private func mergeOverlappingGaps(_ gaps: [DetectedGap]) -> [DetectedGap] {
        guard !gaps.isEmpty else { return [] }

        let sorted = gaps.sorted { $0.startTime < $1.startTime }
        var merged: [DetectedGap] = []
        var current = sorted[0]

        for i in 1..<sorted.count {
            let next = sorted[i]

            // Check if next gap overlaps with or is adjacent to current (within 1ms)
            // REFACTOR NOTE: Using seconds for comparison with Double threshold
            if next.startSeconds <= current.endSeconds + 0.001 {
                // Merge: extend current gap to include next
                let newEndSeconds = max(current.endSeconds, next.endSeconds)

                // Keep the more aggressive removal status
                let newStatus: GapRemovalStatus = {
                    if current.removalStatus == .remove || next.removalStatus == .remove {
                        return .remove
                    } else if current.removalStatus == .autoRemoved || next.removalStatus == .autoRemoved {
                        return .autoRemoved
                    } else {
                        return current.removalStatus
                    }
                }()

                // REFACTOR NOTE: Using convenience initializer with seconds
                current = DetectedGap(
                    id: current.id,
                    startSeconds: current.startSeconds,
                    endSeconds: newEndSeconds,
                    precedingSegmentId: current.precedingSegmentId,
                    followingSegmentId: next.followingSegmentId,
                    removalStatus: newStatus
                )
            } else {
                // No overlap, save current and start new
                merged.append(current)
                current = next
            }
        }

        // Don't forget the last one
        merged.append(current)

        return merged
    }

    /// Repair gaps left behind from changing duplicate selections
    /// For each phrase with a selected occurrence, ensure no gap exists for that selected take
    private func repairDuplicateRejectionGaps() {
        var removedCount = 0

        for phrase in project.repeatedPhrases {
            guard let selectedId = phrase.selectedOccurrenceId,
                  let selectedOccurrence = phrase.occurrences.first(where: { $0.id == selectedId }) else {
                continue
            }

            // Remove any gap that matches the SELECTED occurrence's time range
            // (The selected take should be KEPT, not cut)
            let beforeCount = project.detectedGaps.count
            project.detectedGaps.removeAll { gap in
                // Check if this gap matches the selected occurrence's time range
                abs(gap.startSeconds - selectedOccurrence.startSeconds) < 0.1 &&
                abs(gap.endSeconds - selectedOccurrence.endSeconds) < 0.1
            }

            let removed = beforeCount - project.detectedGaps.count
            if removed > 0 {
                print("🔧 Removed \(removed) incorrect gap(s) for selected take: \"\(phrase.normalizedPhrase)\" at \(formatTimeMs(selectedOccurrence.startSeconds))")
                removedCount += removed
            }
        }

        if removedCount > 0 {
            print("🔧 Total repaired: removed \(removedCount) gaps for selected (kept) takes")
        }
    }

    private func formatTimeMs(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }
}

