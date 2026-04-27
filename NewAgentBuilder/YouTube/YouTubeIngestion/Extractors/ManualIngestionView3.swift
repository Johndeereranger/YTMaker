//
//  ManualIngestionView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//


import SwiftUI

struct ManualIngestionView: View {
    let video: YouTubeVideo
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ManualIngestionViewModel
    
    init(video: YouTubeVideo) {
        self.video = video
        _viewModel = StateObject(wrappedValue: ManualIngestionViewModel(video: video))
    }
    
    var body: some View {
        Group {
            if viewModel.showStatusView, let status = viewModel.analysisStatus {
                AnalysisStatusView(
                    video: video,
                    status: status,
                    onResume: { viewModel.resumeFromStatus(status) },
                    onReprocess: { target in Task { await viewModel.reprocess(target) } },
                    onStartFresh: { Task { await viewModel.startFresh() } },
                    onRunMissingInSection: { sectionStatus in Task { await viewModel.runMissingBeatsInSection(sectionStatus) } },
                    onRunAllMissing: { Task { await viewModel.runAllMissingBeats() } },
                    onSaveA1aResult: { alignment in Task { await viewModel.saveFidelityResult(alignment) } }
                )
            } else {
                mainIngestionView
            }
        }
        .overlay {
            if viewModel.autoRunning {
                autoRunOverlay
            }
        }
        .alert("Auto-Run Error", isPresented: .constant(viewModel.autoRunError != nil)) {
            Button("OK") {
                viewModel.autoRunError = nil
            }
        } message: {
            if let err = viewModel.autoRunError {
                Text("Failed at \(err.phase):\n\(err.error)")
            }
        }
        .confirmationDialog(
            "Auto-Run Confirmation",
            isPresented: $viewModel.showAutoRunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                viewModel.pendingAutoRunAction?()
                viewModel.pendingAutoRunAction = nil
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingAutoRunAction = nil
            }
        } message: {
            Text(viewModel.autoRunConfirmationMessage)
        }
        .onAppear {
            Task { await viewModel.onAppear() }
        }
    }

    private var mainIngestionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                videoInfoSection
                
                // Flow Selection
                flowSelectionSection
                
                Divider()
                
                switch viewModel.currentPhase {
                case .a1a_sections:
                    a1aSectionsView
                case .a1b_beats:
                    a1bBeatsView
                case .a1c_beatDocs:
                    a1cBeatDocsView
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
    
    // MARK: - Flow Selection
    
    private var flowSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Mode")
                .font(.headline)
            
            HStack(spacing: 12) {
                // Fast Analysis Button
                Button {
                    Task { await viewModel.runFastAnalysis() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                        Text("Fast Analysis")
                            .font(.subheadline.bold())
                        Text("A1a + A1b only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.autoRunning || viewModel.savedAlignment != nil)
                
                // Manual Flow indicator
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title2)
                    Text("Manual Mode")
                        .font(.subheadline.bold())
                    Text("Step by step")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                )
            }
            
            if viewModel.currentFlow == .fastAnalysis {
                Text("⚡ Running Fast Analysis - A1a → A1b for all sections, then computing scriptSummary")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Video Info Section
    
    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
            
            HStack {
                Label(video.duration, systemImage: "clock")
                Spacer()
                if let transcript = video.transcript {
                    Label("\(transcript.split(separator: " ").count) words", systemImage: "text.alignleft")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Auto-Run Overlay
    
    private var autoRunOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                
                Text(viewModel.autoRunProgress)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Cancel") {
                    viewModel.autoRunning = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
        }
    }
    
    // MARK: - A1a Sections View
    
    @ViewBuilder
    private var a1aSectionsView: some View {
        switch viewModel.a1aStep {
        case .showPrompt:
            VStack(spacing: 16) {
                PromptDisplayView(
                    prompt: viewModel.sectionPrompt,
                    stepNumber: 1,
                    stepTitle: "Copy Prompt",
                    onCopy: {
                        UIPasteboard.general.string = viewModel.sectionPrompt
                    },
                    onNext: {
                        viewModel.a1aStep = .pasteResponse
                    }
                )
                
                Button {
                    Task { await viewModel.autoRunA1a() }
                } label: {
                    Label("Auto-Run with Claude", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.autoRunning)
            }
            
        case .pasteResponse:
            ResponsePasteView(
                response: $viewModel.sectionResponse,
                stepNumber: 2,
                stepTitle: "Paste JSON Response",
                error: viewModel.error,
                onBack: {
                    viewModel.a1aStep = .showPrompt
                    viewModel.error = nil
                },
                onProcess: {
                    Task { await viewModel.processSectionResponse() }
                }
            )
            
        case .processing:
            ProgressView()
                .scaleEffect(1.5)
            Text("Calculating timestamps...")
                .font(.headline)
            
        case .review:
            SectionReviewView(
                alignment: viewModel.processedAlignment!,
                onBack: {
                    viewModel.a1aStep = .pasteResponse
                    viewModel.error = nil
                },
                onSave: {
                    Task { await viewModel.saveAlignment() }
                }
            )
            
        case .saving:
            ProgressView()
                .scaleEffect(1.5)
            Text("Saving to Firebase...")
                .font(.headline)
            
        case .complete:
            A1aCompleteView(
                alignment: viewModel.savedAlignment!,
                onDone: { dismiss() },
                onContinue: {
                    viewModel.currentPhase = .a1b_beats
                    viewModel.a1bStep = .showPrompt
                    viewModel.currentSectionIndex = 0
                    viewModel.generateBeatPrompt()
                }
            )
        }
    }
    
    // MARK: - A1b Beats View
    
    @ViewBuilder
    private var a1bBeatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let alignment = viewModel.savedAlignment {
                sectionProgressView(alignment: alignment)
                Divider()
            }
            
            switch viewModel.a1bStep {
            case .showPrompt:
                VStack(spacing: 16) {
                    // Fast remaining sections button
                    if viewModel.currentSectionIndex == 0 {
                        Button {
                            Task { await viewModel.runRemainingA1b() }
                        } label: {
                            Label("🚀 Auto-Run All Sections (A1b Only)", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(viewModel.autoRunning)
                    }
                    
                    PromptDisplayView(
                        prompt: viewModel.beatPrompt,
                        stepNumber: 1,
                        stepTitle: "Copy Beat Extraction Prompt",
                        onCopy: {
                            UIPasteboard.general.string = viewModel.beatPrompt
                        },
                        onNext: {
                            viewModel.a1bStep = .pasteResponse
                        }
                    )
                    
                    Button {
                        Task { await viewModel.autoRunA1b() }
                    } label: {
                        Label("Auto-Run Beat Extraction", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.autoRunning)
                }
                
            case .pasteResponse:
                ResponsePasteView(
                    response: $viewModel.beatResponse,
                    stepNumber: 2,
                    stepTitle: "Paste Beat JSON Response",
                    error: viewModel.error,
                    onBack: {
                        viewModel.a1bStep = .showPrompt
                        viewModel.error = nil
                    },
                    onProcess: {
                        Task { await viewModel.processBeatResponse() }
                    }
                )
                
            case .processing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing beats...")
                    .font(.headline)
                
            case .review:
                SimpleBeatReviewView(
                    beatData: viewModel.currentSectionBeatData!,
                    onBack: {
                        viewModel.a1bStep = .pasteResponse
                        viewModel.error = nil
                    },
                    onContinue: {
                        Task { await viewModel.saveBeatsAndTransitionToA1c() }
                    }
                )
                
            case .saving:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Saving beats...")
                    .font(.headline)
                
            case .complete:
                EmptyView()
            }
        }
    }
    
    // MARK: - A1c BeatDocs View
    
    @ViewBuilder
    private var a1cBeatDocsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let beatData = viewModel.currentSectionBeatData {
                beatProgressView(beatData: beatData)
                Divider()
            }
            
            if viewModel.a1cStep == .showPrompt {
                VStack(spacing: 12) {
                    Button {
                        Task { await viewModel.autoRunAllBeatsInSection() }
                    } label: {
                        Label("🚀 Auto-Run All Beats in This Section", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.autoRunning)
                    
                    Button {
                        viewModel.showAutoRunConfirmation = true
                        viewModel.pendingAutoRunAction = {
                            Task { await viewModel.autoRunToCompletion() }
                        }
                    } label: {
                        Label("🚀 Finish This Video Automatically", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.autoRunning)
                }
                .padding(.bottom, 8)
            }
            
            switch viewModel.a1cStep {
            case .showPrompt:
                VStack(spacing: 16) {
                    PromptDisplayView(
                        prompt: viewModel.beatDocPrompt,
                        stepNumber: 1,
                        stepTitle: "Copy BeatDoc Extraction Prompt",
                        onCopy: {
                            UIPasteboard.general.string = viewModel.beatDocPrompt
                        },
                        onNext: {
                            viewModel.a1cStep = .pasteResponse
                        }
                    )
                    
                    Button {
                        Task { await viewModel.autoRunA1c() }
                    } label: {
                        Label("Auto-Run This BeatDoc", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.autoRunning)
                }
                
            case .pasteResponse:
                ResponsePasteView(
                    response: $viewModel.beatDocResponse,
                    stepNumber: 2,
                    stepTitle: "Paste BeatDoc JSON Response",
                    error: viewModel.error,
                    onBack: {
                        viewModel.a1cStep = .showPrompt
                        viewModel.error = nil
                    },
                    onProcess: {
                        Task { await viewModel.processBeatDocResponse() }
                    }
                )
                
            case .processing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing BeatDoc...")
                    .font(.headline)
                
            case .review:
                BeatDocReviewView(
                    beatDoc: viewModel.processedBeatDoc!,
                    onBack: {
                        viewModel.a1cStep = .pasteResponse
                        viewModel.error = nil
                    },
                    onSave: {
                        Task { await viewModel.saveBeatDoc() }
                    }
                )
                
            case .saving:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Saving BeatDoc to Firebase...")
                    .font(.headline)
                
            case .complete:
                AllBeatsCompleteView(
                    totalSections: viewModel.savedAlignment?.sections.count ?? 0,
                    totalBeatsProcessed: viewModel.savedBeatDocsForSection.count,
                    onDone: { dismiss() }
                )
            }
        }
    }
    
    // MARK: - Progress Views
    
    private func sectionProgressView(alignment: AlignmentData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Section \(viewModel.currentSectionIndex + 1) of \(alignment.sections.count)")
                .font(.headline)
            
            ProgressView(value: Double(viewModel.currentSectionIndex), total: Double(alignment.sections.count))
            
            ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
                HStack {
                    if index < viewModel.currentSectionIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if index == viewModel.currentSectionIndex {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(section.role)")
                        .font(.subheadline)
                        .fontWeight(index == viewModel.currentSectionIndex ? .bold : .regular)
                    
                    Spacer()
                }
                .padding(8)
                .background(index == viewModel.currentSectionIndex ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func beatProgressView(beatData: SimpleBeatData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beat \(viewModel.currentBeatIndex + 1) of \(beatData.beats.count)")
                .font(.headline)
            
            ProgressView(value: Double(viewModel.currentBeatIndex), total: Double(beatData.beats.count))
            
            ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
                HStack {
                    if index < viewModel.currentBeatIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if index == viewModel.currentBeatIndex {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(beat.type)")
                        .font(.subheadline)
                        .fontWeight(index == viewModel.currentBeatIndex ? .bold : .regular)
                    
                    Spacer()
                }
                .padding(8)
                .background(index == viewModel.currentBeatIndex ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Views

struct SimpleBeatReviewView: View {
    let beatData: SimpleBeatData
    let onBack: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "3.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Review Beat Boundaries")
                    .font(.headline)
            }
            
            Text("These are just boundaries - full analysis comes in A1c")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(beat.type)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(beatTypeColor(beat.type).opacity(0.2))
                                    .foregroundColor(beatTypeColor(beat.type))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                Text("Words \(beat.startWordIndex)-\(beat.endWordIndex)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(String(beat.text.prefix(100)))
                                .font(.body)
                                .lineLimit(2)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onContinue) {
                    Label("Save & Continue to A1c", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func beatTypeColor(_ type: String) -> Color {
        switch type {
        case "TEASE": return .purple
        case "QUESTION": return .blue
        case "PROMISE": return .green
        case "DATA": return .orange
        case "STORY": return .pink
        default: return .gray
        }
    }
}

struct BeatDocReviewView: View {
    let beatDoc: BeatDoc
    let onBack: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "3.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Review BeatDoc")
                    .font(.headline)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        InfoRow(label: "Move Key", value: beatDoc.moveKey)
                        InfoRow(label: "Quality", value: beatDoc.qualityLevel)
                        InfoRow(label: "Tempo", value: beatDoc.tempo)
                        InfoRow(label: "Stance", value: beatDoc.stance)
                        InfoRow(label: "Proof Mode", value: beatDoc.proofMode)
                    }
                    
                    Divider()
                    
                    Text("Text Preview")
                        .font(.headline)
                    Text(String(beatDoc.text.prefix(200)))
                        .font(.body)
                    
                    Divider()
                    
                    Text("Compiler Function")
                        .font(.headline)
                    Text(beatDoc.compilerFunction)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxHeight: 400)
            
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onSave) {
                    Label("Save BeatDoc", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }
}

struct AllBeatsCompleteView: View {
    let totalSections: Int
    let totalBeatsProcessed: Int
    let onDone: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
                Text("All Analysis Complete!")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("✅ Processed \(totalSections) sections")
                Text("✅ Created full BeatDocs for all beats")
                Text("✅ All data saved to Firebase")
            }
            .font(.subheadline)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}