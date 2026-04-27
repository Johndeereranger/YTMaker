//
//  ManualIngestionView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//




import SwiftUI

struct ManualIngestionViewOld: View {
    let video: YouTubeVideo
    @Environment(\.dismiss) private var dismiss
    
    // Phase tracking
    @State private var currentPhase: IngestionPhase = .a1a_sections
    
    // A1a state
    @State private var a1aStep: PhaseStep = .showPrompt
    @State private var sectionPrompt: String = ""
    @State private var sectionResponse: String = ""
    @State private var processedAlignment: AlignmentData?
    @State private var savedAlignment: AlignmentData?
    
    // A1b state (per section - NOT saved to Firebase)
    @State private var a1bStep: PhaseStep = .showPrompt
    @State private var currentSectionIndex: Int = 0
    @State private var beatPrompt: String = ""
    @State private var beatResponse: String = ""
    @State private var currentSectionBeatData: SimpleBeatData? // Temporary, in-memory only
    
    // A1c state (per beat - SAVED to Firebase)
    @State private var a1cStep: PhaseStep = .showPrompt
    @State private var currentBeatIndex: Int = 0
    @State private var beatDocPrompt: String = ""
    @State private var beatDocResponse: String = ""
    @State private var processedBeatDoc: BeatDoc?
    @State private var savedBeatDocsForSection: [BeatDoc] = []
    
    // Shared state
    @State private var isProcessing = false
    @State private var error: String?
    
    // AI Auto-run state
    @State private var aiEngine: AIEngine?
    @State private var autoRunning = false
    @State private var autoRunProgress: String = ""
    @State private var autoRunError: (phase: String, error: String)?
    @State private var showAutoRunConfirmation = false
    @State private var pendingAutoRunAction: (() -> Void)?
    
    
    @State private var analysisStatus: AnalysisStatus?
    @State private var showStatusView = false
    
    
    enum IngestionPhase {
        case a1a_sections
        case a1b_beats
        case a1c_beatDocs
    }
    
    enum PhaseStep {
        case showPrompt
        case pasteResponse
        case processing
        case review
        case saving
        case complete
    }
    
    var body: some View {
        Group {
            if showStatusView, let status = analysisStatus {
                AnalysisStatusView(
                    video: video,
                    status: status,
                    onResume: { resumeFromStatus(status) },
                    onReprocess: { target in Task { await reprocess(target) } },
                    onStartFresh: { Task { await startFresh() } },
                    onRunMissingInSection: { sectionStatus in Task { await runMissingBeatsInSection(sectionStatus) } },
                    onRunAllMissing: { Task { await runAllMissingBeats() } },
                    onSaveA1aResult: { alignment in Task { await saveFidelityResult(alignment) } }
                )
            } else {
                mainIngestionView
            }
        }
        .overlay {
            if autoRunning {
                autoRunOverlay
            }
        }
        .alert("Auto-Run Error", isPresented: .constant(autoRunError != nil)) {
            Button("OK") {
                autoRunError = nil
            }
        } message: {
            if let err = autoRunError {
                Text("Failed at \(err.phase):\n\(err.error)")
            }
        }
        .confirmationDialog(
            "Auto-Run Confirmation",
            isPresented: $showAutoRunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                pendingAutoRunAction?()
                pendingAutoRunAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAutoRunAction = nil
            }
        } message: {
            Text(autoRunConfirmationMessage)
        }
        .onAppear {
            // Initialize AI engine
            aiEngine = AIEngine(model: .claude35Sonnet)
            
            // Check for existing analysis first
            Task {
                await checkExistingAnalysis()
            }
            
            // Only generate prompt if no existing analysis found
            if currentPhase == .a1a_sections && a1aStep == .showPrompt && !showStatusView {
                generateSectionPrompt()
            }
        }
    }

    private var mainIngestionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Video Info
                videoInfoSection
                
                Divider()
                
                // Phase-specific UI
                switch currentPhase {
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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
    
    private func runMissingBeatsInSection(_ sectionStatus: SectionAnalysisStatus) async {
        guard let alignment = savedAlignment ?? analysisStatus?.alignment else { return }
        
        let missingIndices = sectionStatus.incompleteBeatIndices
        guard !missingIndices.isEmpty else { return }
        
        // Setup section context
        await MainActor.run {
            showStatusView = false
            currentSectionIndex = sectionStatus.sectionIndex
            let simpleBeats = sectionStatus.beatDocs.map { beatDoc in
                SimpleBeat(
                    beatId: beatDoc.beatId,
                    type: beatDoc.type,
                    timeRange: TimeRange(start: 0, end: 0),
                    text: beatDoc.text,
                    startWordIndex: beatDoc.startWordIndex,
                    endWordIndex: beatDoc.endWordIndex,
                    stance: beatDoc.stance,
                    tempo: beatDoc.tempo,
                    formality: beatDoc.styleFormality,
                    questionCount: beatDoc.questionCount,
                    containsAnchor: beatDoc.containsAnchor,
                    anchorText: beatDoc.anchorText,
                    anchorFunction: beatDoc.anchorFunction,
                    proofMode: beatDoc.proofMode,
                    moveKey: beatDoc.moveKey,
                    sectionId: beatDoc.sectionId,
                    boundaryText: nil,
                    matchConfidence: nil
                )
            }
            currentSectionBeatData = SimpleBeatData(
                sectionId: sectionStatus.section.id,
                sectionRole: sectionStatus.section.role,
                beatCount: simpleBeats.count,
                beats: simpleBeats
            )
            savedAlignment = alignment
            currentPhase = .a1c_beatDocs
            autoRunning = true
        }
        
        for beatIndex in missingIndices {
            await MainActor.run {
                currentBeatIndex = beatIndex
                autoRunProgress = "Fixing beat \(beatIndex + 1) of section \(sectionStatus.sectionIndex + 1)..."
                generateBeatDocPrompt()
            }
            
            await autoRunA1c()
            
            if autoRunError != nil { break }
            
            if a1cStep == .review {
                await saveBeatDoc()
            }
        }
        
        await MainActor.run {
            autoRunning = false
        }
        
        await checkExistingAnalysis()
        
        await MainActor.run {
            showStatusView = true
        }
    }

    private func runAllMissingBeats() async {
        guard let status = analysisStatus else { return }
        
        for sectionStatus in status.sectionStatuses where !sectionStatus.incompleteBeatIndices.isEmpty {
            await runMissingBeatsInSection(sectionStatus)
            if autoRunError != nil { break }
        }
        
        await checkExistingAnalysis()
        
        await MainActor.run {
            showStatusView = true
        }
    }
    
    private func checkExistingAnalysis() async {
        print("🔍 checkExistingAnalysis starting for video: \(video.videoId)")
        do {
            // Try to load alignment (A1a data) using EXISTING method
            let alignment = try await CreatorAnalysisFirebase.shared.loadAlignmentDoc(
                videoId: video.videoId,
                channelId: video.channelId
            )
            
            print("🔍 loadAlignmentDoc returned: \(alignment == nil ? "nil" : "has data")")
            
            // If no alignment, A1a not done - jump straight to A1a
            guard let alignment = alignment else {
                await MainActor.run {
                    showStatusView = false
                    currentPhase = .a1a_sections
                    a1aStep = .showPrompt
                    generateSectionPrompt()
                }
                return
            }
            
            print("🔍 Alignment found with \(alignment.sections.count) sections")
            
            // A1a is done, check each section's beatDocs using EXISTING method
            var sectionStatuses: [SectionAnalysisStatus] = []
            
            for (index, section) in alignment.sections.enumerated() {
                let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                    sectionId: section.id
                )
                
                sectionStatuses.append(SectionAnalysisStatus(
                    section: section,
                    sectionIndex: index,
                    beatDocs: beatDocs
                ))
            }
            
            let status = AnalysisStatus(
                videoId: video.videoId,
                channelId: video.channelId,
                alignment: alignment,
                sectionStatuses: sectionStatuses
            )
            
            await MainActor.run {
                analysisStatus = status
                
                // Show status view if ANY work has been done
                if status.a1aComplete {
                    showStatusView = true
                } else {
                    // Nothing done yet - jump straight in
                    showStatusView = false
                    currentPhase = .a1a_sections
                    a1aStep = .showPrompt
                    generateSectionPrompt()
                }
            }
            
        } catch {
            print("No existing analysis found: \(error.localizedDescription)")
            // No existing analysis - start fresh
            await MainActor.run {
                showStatusView = false
                currentPhase = .a1a_sections
                a1aStep = .showPrompt
                generateSectionPrompt()
            }
        }
    }
    
   
    
    private func startFresh() async {
        await reprocess(.a1a)
    }

    private func saveFidelityResult(_ alignment: AlignmentData) async {
        do {
            try await CreatorAnalysisFirebase.shared.saveSections(
                sections: alignment.sections,
                videoId: video.videoId,
                channelId: video.channelId
            )

            try await YouTubeFirebaseService.shared.saveVideoAnalysis(
                videoId: video.videoId,
                videoSummary: alignment.videoSummary,
                logicSpine: alignment.logicSpine,
                bridgePoints: alignment.bridgePoints,
                validationStatus: alignment.validationStatus,
                validationIssues: alignment.validationIssues,
                extractionDate: alignment.extractionDate
            )

            await MainActor.run {
                savedAlignment = alignment
            }
            print("✅ Fidelity result saved!")

            await checkExistingAnalysis()
        } catch {
            print("❌ Failed to save fidelity result: \(error)")
        }
    }

    private func resumeFromStatus(_ status: AnalysisStatus) {
        showStatusView = false
        
        // If A1a not complete, start there
        guard let alignment = status.alignment else {
            currentPhase = .a1a_sections
            a1aStep = .showPrompt
            generateSectionPrompt()
            return
        }
        
        // Set savedAlignment so the rest of the flow works
        savedAlignment = alignment
        
        // Find first incomplete section
        guard let incompleteSectionIndex = status.sectionStatuses.firstIndex(where: { !$0.isComplete }) else {
            // Everything is complete - show complete state
            currentPhase = .a1c_beatDocs
            Task {
                    await computeAndSaveScriptSummary()
                }
            a1cStep = .complete
            return
        }
        
        let sectionStatus = status.sectionStatuses[incompleteSectionIndex]
        currentSectionIndex = incompleteSectionIndex
        
        if !sectionStatus.a1bComplete {
            // No beats yet - need to run A1b for this section
            currentPhase = .a1b_beats
            a1bStep = .showPrompt
            generateBeatPrompt()
        } else {
            // A1b done - convert existing beatDocs to SimpleBeatData for current flow
            let simpleBeats = sectionStatus.beatDocs.map { beatDoc in
                SimpleBeat(
                    beatId: beatDoc.beatId,
                    type: beatDoc.type,
                    timeRange: TimeRange(start: 0, end: 0),
                    text: beatDoc.text,
                    startWordIndex: beatDoc.startWordIndex,
                    endWordIndex: beatDoc.endWordIndex,
                    stance: beatDoc.stance,
                    tempo: beatDoc.tempo,
                    formality: beatDoc.styleFormality,
                    questionCount: beatDoc.questionCount,
                    containsAnchor: beatDoc.containsAnchor,
                    anchorText: beatDoc.anchorText,
                    anchorFunction: beatDoc.anchorFunction,
                    proofMode: beatDoc.proofMode,
                    moveKey: beatDoc.moveKey,
                    sectionId: beatDoc.sectionId,
                    boundaryText: nil,
                    matchConfidence: nil
                )
            }

            currentSectionBeatData = SimpleBeatData(
                sectionId: sectionStatus.section.id,
                sectionRole: sectionStatus.section.role,
                beatCount: simpleBeats.count,
                beats: simpleBeats
            )
            currentPhase = .a1c_beatDocs
            currentBeatIndex = sectionStatus.completedBeats
            a1cStep = .showPrompt
            generateBeatDocPrompt()
        }
    }

    private func reprocess(_ target: ReprocessTarget) async {
        do {
            switch target {
            case .a1a:
                // Load sections using existing method
                let sections = try await CreatorAnalysisFirebase.shared.loadSectionsForVideo(
                    videoId: video.videoId
                )
                
                // Delete each section
                for section in sections {
                    // Delete beatDocs for this section first
                    let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                        sectionId: section.id
                    )
                    for beatDoc in beatDocs {
                        try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatDoc.beatId)
                    }
                    
                    // Delete section
                    try await CreatorAnalysisFirebase.shared.deleteSection(sectionId: section.id)
                }
                
                // Clear video-level analysis
                try await CreatorAnalysisFirebase.shared.clearVideoAnalysis(videoId: video.videoId)
                
                await MainActor.run {
                    showStatusView = false
                    savedAlignment = nil
                    processedAlignment = nil
                    currentSectionIndex = 0
                    currentBeatIndex = 0
                    currentPhase = .a1a_sections
                    a1aStep = .showPrompt
                    generateSectionPrompt()
                }
                
            case .section(let sectionId):
                // Delete all beatDocs for this section
                let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                    sectionId: sectionId
                )
                
                for beatDoc in beatDocs {
                    try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatDoc.beatId)
                }
                
                // Find section index and restart at A1b
                if let alignment = savedAlignment,
                   let index = alignment.sections.firstIndex(where: { $0.id == sectionId }) {
                    await MainActor.run {
                        showStatusView = false
                        currentSectionIndex = index
                        currentSectionBeatData = nil
                        currentBeatIndex = 0
                        currentPhase = .a1b_beats
                        a1bStep = .showPrompt
                        generateBeatPrompt()
                    }
                }
                
            case .beat(let sectionId, let beatId):
                // Delete specific beatDoc
                try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatId)
                
                // Find section and beat index, restart at that beat
                if let alignment = savedAlignment,
                   let sectionIndex = alignment.sections.firstIndex(where: { $0.id == sectionId }) {
                    
                    let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                        sectionId: sectionId
                    )
                    
                    if let beatIndex = beatDocs.firstIndex(where: { $0.beatId == beatId }) {
                        let section = alignment.sections[sectionIndex]
                        let simpleBeats = beatDocs.map { beatDoc in
                            SimpleBeat(
                                beatId: beatDoc.beatId,
                                type: beatDoc.type,
                                timeRange: TimeRange(start: 0, end: 0),
                                text: beatDoc.text,
                                startWordIndex: beatDoc.startWordIndex,
                                endWordIndex: beatDoc.endWordIndex,
                                stance: beatDoc.stance,
                                tempo: beatDoc.tempo,
                                formality: beatDoc.styleFormality,
                                questionCount: beatDoc.questionCount,
                                containsAnchor: beatDoc.containsAnchor,
                                anchorText: beatDoc.anchorText,
                                anchorFunction: beatDoc.anchorFunction,
                                proofMode: beatDoc.proofMode,
                                moveKey: beatDoc.moveKey,
                                sectionId: beatDoc.sectionId,
                                boundaryText: nil,
                                matchConfidence: nil
                            )
                        }

                        await MainActor.run {
                            showStatusView = false
                            currentSectionIndex = sectionIndex
                            currentSectionBeatData = SimpleBeatData(
                                sectionId: sectionId,
                                sectionRole: section.role,
                                beatCount: simpleBeats.count,
                                beats: simpleBeats
                            )
                            currentBeatIndex = beatIndex
                            currentPhase = .a1c_beatDocs
                            a1cStep = .showPrompt
                            generateBeatDocPrompt()
                        }
                    }
                }
            }

        } catch {
            print("Reprocess error: \(error.localizedDescription)")
            await MainActor.run {
                self.error = "Failed to reprocess: \(error.localizedDescription)"
            }
        }
    }
    
    private var navigationTitle: String {
        switch currentPhase {
        case .a1a_sections:
            return "A1a: Analyze Structure"
        case .a1b_beats:
            return "A1b: Extract Beats (Section \(currentSectionIndex + 1))"
        case .a1c_beatDocs:
            return "A1c: Beat Doc (Beat \(currentBeatIndex + 1))"
        }
    }
    
    private var autoRunConfirmationMessage: String {
        guard let alignment = savedAlignment else { return "" }
        
        if currentPhase == .a1b_beats {
            let remainingSections = alignment.sections.count - currentSectionIndex
            return "This will automatically process \(remainingSections) section(s) and all their beats. This may take several minutes and use significant API tokens."
        } else if currentPhase == .a1c_beatDocs {
            guard let beatData = currentSectionBeatData else { return "" }
            let remainingBeats = beatData.beats.count - currentBeatIndex
            let remainingSections = alignment.sections.count - currentSectionIndex
            return "This will process \(remainingBeats) remaining beat(s) in this section, plus \(remainingSections - 1) more section(s)."
        }
        return ""
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
                
                Text(autoRunProgress)
                    .font(.headline)
                    .foregroundColor(.primary)  // ← Changed from .white to .primary
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Cancel") {
                    autoRunning = false
                }
                .buttonStyle(.borderedProminent)  // ← Changed from .bordered
                .tint(.red)  // ← Changed from .white
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )
        }
    }
    
    // MARK: - ScriptSummary Computation

    private func computeAndSaveScriptSummary() async {
        guard let alignment = savedAlignment else { return }
        
        // Load all beatDocs for this video
        var allBeats: [BeatDoc] = []
        for section in alignment.sections {
            do {
                let sectionBeats = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                    sectionId: section.id
                )
                allBeats.append(contentsOf: sectionBeats)
            } catch {
                print("Failed to load beats for section \(section.id): \(error)")
            }
        }
        
        guard !allBeats.isEmpty else {
            print("No beats found for scriptSummary")
            return
        }
        
        // Compute scriptSummary
        let summary = computeScriptSummary(
            sections: alignment.sections,
            beats: allBeats
        )
        
        // Save to video doc
        do {
            try await YouTubeFirebaseService.shared.saveScriptSummary(
                videoId: video.videoId,
                summary: summary
            )
            print("✅ ScriptSummary saved for video \(video.videoId)")
        } catch {
            print("❌ Failed to save scriptSummary: \(error)")
        }
    }

    private func computeScriptSummary(sections: [SectionData], beats: [BeatDoc]) -> ScriptSummary {
        // Section sequence
        let sectionSequence = sections.map { $0.role }
        
        // Turn position (normalized 0-1)
        let turnPosition: Double = {
            guard let turnIndex = sections.firstIndex(where: { $0.role.uppercased() == "TURN" }) else {
                return 0.5 // default if no turn found
            }
            return Double(turnIndex) / Double(max(sections.count - 1, 1))
        }()
        
        // Beat distribution overall
        var beatDistribution: [String: Int] = [:]
        for beat in beats {
            beatDistribution[beat.type, default: 0] += 1
        }
        
        // Beat distribution by section
        var beatDistributionBySection: [String: [String: Int]] = [:]
        for section in sections {
            let sectionBeats = beats.filter { $0.sectionId == section.id }
            var dist: [String: Int] = [:]
            for beat in sectionBeats {
                dist[beat.type, default: 0] += 1
            }
            beatDistributionBySection[section.role] = dist
        }
        
        // Stance counts
        var stanceCounts: [String: Int] = [:]
        for beat in beats {
            let stance = beat.stance.isEmpty ? "neutral" : beat.stance
            stanceCounts[stance, default: 0] += 1
        }
        
        // Tempo counts
        var tempoCounts: [String: Int] = [:]
        for beat in beats {
            let tempo = beat.tempo.isEmpty ? "medium" : beat.tempo
            tempoCounts[tempo, default: 0] += 1
        }
        
        // Average formality
        let formalityValues = beats.map { $0.styleFormality }
        let avgFormality = formalityValues.isEmpty ? 5.0 : Double(formalityValues.reduce(0, +)) / Double(formalityValues.count)
        
        // Average sentence length (from beat text)
        let sentenceLengths = beats.map { beat -> Double in
            let words = beat.text.split(separator: " ").count
            let sentences = max(beat.sentenceCount, 1)
            return Double(words) / Double(sentences)
        }
        let avgSentenceLength = sentenceLengths.isEmpty ? 0.0 : sentenceLengths.reduce(0, +) / Double(sentenceLengths.count)
        
        // Total question count
        let questionCount = beats.reduce(0) { $0 + $1.questionCount }
        
        // Anchors (where containsAnchor == true)
        var anchorTexts: [String] = []
        var anchorFunctions: [String] = []
        var anchorSectionRoles: [String] = []
        
        for beat in beats where beat.containsAnchor {
            anchorTexts.append(beat.anchorText)
            anchorFunctions.append(beat.anchorFunction)
            anchorSectionRoles.append(beat.sectionRole)
        }
        
        return ScriptSummary(
            sectionSequence: sectionSequence,
            turnPosition: turnPosition,
            sectionCount: sections.count,
            totalBeats: beats.count,
            beatDistribution: beatDistribution,
            beatDistributionBySection: beatDistributionBySection,
            stanceCounts: stanceCounts,
            tempoCounts: tempoCounts,
            avgFormality: avgFormality,
            avgSentenceLength: avgSentenceLength,
            questionCount: questionCount,
            anchorTexts: anchorTexts,
            anchorFunctions: anchorFunctions,
            anchorSectionRoles: anchorSectionRoles,
            computedAt: Date()
        )
    }
    
    // MARK: - A1a Sections View
    
    @ViewBuilder
    private var a1aSectionsView: some View {
        switch a1aStep {
        case .showPrompt:
            VStack(spacing: 16) {
                PromptDisplayView(
                    prompt: sectionPrompt,
                    stepNumber: 1,
                    stepTitle: "Copy Prompt",
                    onCopy: {
                        UIPasteboard.general.string = sectionPrompt
                    },
                    onNext: {
                        a1aStep = .pasteResponse
                    }
                )
                
                // Auto-run button
                Button {
                    Task { await autoRunA1a() }
                } label: {
                    Label("Auto-Run with Claude", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(autoRunning)
            }
            
        case .pasteResponse:
            ResponsePasteView(
                response: $sectionResponse,
                stepNumber: 2,
                stepTitle: "Paste JSON Response",
                error: error,
                onBack: {
                    a1aStep = .showPrompt
                    error = nil
                },
                onProcess: {
                    Task {
                        await processSectionResponse()
                    }
                }
            )
            
        case .processing:
            ProgressView()
                .scaleEffect(1.5)
            Text("Calculating timestamps...")
                .font(.headline)
            
        case .review:
            SectionReviewView(
                alignment: processedAlignment!,
                onBack: {
                    a1aStep = .pasteResponse
                    error = nil
                },
                onSave: {
                    Task {
                        await saveAlignment()
                    }
                }
            )
            
        case .saving:
            ProgressView()
                .scaleEffect(1.5)
            Text("Saving to Firebase...")
                .font(.headline)
            
        case .complete:
            A1aCompleteView(
                alignment: savedAlignment!,
                onDone: {
                    dismiss()
                },
                onContinue: {
                    // Start A1b for first section
                    currentPhase = .a1b_beats
                    a1bStep = .showPrompt
                    currentSectionIndex = 0
                    generateBeatPrompt()
                }
            )
        }
    }
    
    // MARK: - A1b Beats View
    
    @ViewBuilder
    private var a1bBeatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Progress indicator
            if let alignment = savedAlignment {
                sectionProgressView(alignment: alignment)
                Divider()
            }
            
            // Step views
            switch a1bStep {
            case .showPrompt:
                VStack(spacing: 16) {
                    PromptDisplayView(
                        prompt: beatPrompt,
                        stepNumber: 1,
                        stepTitle: "Copy Beat Extraction Prompt",
                        onCopy: {
                            UIPasteboard.general.string = beatPrompt
                        },
                        onNext: {
                            a1bStep = .pasteResponse
                        }
                    )
                    
                    // Auto-run button
                    Button {
                        Task { await autoRunA1b() }
                    } label: {
                        Label("Auto-Run Beat Extraction", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(autoRunning)
                }
                
            case .pasteResponse:
                ResponsePasteView(
                    response: $beatResponse,
                    stepNumber: 2,
                    stepTitle: "Paste Beat JSON Response",
                    error: error,
                    onBack: {
                        a1bStep = .showPrompt
                        error = nil
                    },
                    onProcess: {
                        Task {
                            await processBeatResponse()
                        }
                    }
                )
                
            case .processing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing beats...")
                    .font(.headline)
                
            case .review:
                SimpleBeatReviewView(
                    beatData: currentSectionBeatData!,
                    onBack: {
                        a1bStep = .pasteResponse
                        error = nil
                    },
                    onContinue: {
                        // Save beats to Firebase, then transition to A1c
                        Task {
                            await saveBeatsAndTransitionToA1c()
                        }
                    }
                )
                
            case .saving:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Saving beats...")
                    .font(.headline)
                
            case .complete:
                EmptyView() // A1b doesn't have complete state
            }
        }
    }
    
    // MARK: - A1c BeatDocs View
    
    @ViewBuilder
    private var a1cBeatDocsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Progress indicator
            if let beatData = currentSectionBeatData {
                beatProgressView(beatData: beatData)
                Divider()
            }
            
            // Multi-step auto-run buttons
            if a1cStep == .showPrompt {
                VStack(spacing: 12) {
                    Button {
                        Task { await autoRunAllBeatsInSection() }
                    } label: {
                        Label("🚀 Auto-Run All Beats in This Section", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(autoRunning)
                    
                    Button {
                        showAutoRunConfirmation = true
                        pendingAutoRunAction = {
                            Task { await autoRunToCompletion() }
                        }
                    } label: {
                        Label("🚀 Finish This Video Automatically", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(autoRunning)
                }
                .padding(.bottom, 8)
            }
            
            // Step views
            switch a1cStep {
            case .showPrompt:
                VStack(spacing: 16) {
                    PromptDisplayView(
                        prompt: beatDocPrompt,
                        stepNumber: 1,
                        stepTitle: "Copy BeatDoc Extraction Prompt",
                        onCopy: {
                            UIPasteboard.general.string = beatDocPrompt
                        },
                        onNext: {
                            a1cStep = .pasteResponse
                        }
                    )
                    
                    // Single-step auto-run
                    Button {
                        Task { await autoRunA1c() }
                    } label: {
                        Label("Auto-Run This BeatDoc", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(autoRunning)
                }
                
            case .pasteResponse:
                ResponsePasteView(
                    response: $beatDocResponse,
                    stepNumber: 2,
                    stepTitle: "Paste BeatDoc JSON Response",
                    error: error,
                    onBack: {
                        a1cStep = .showPrompt
                        error = nil
                    },
                    onProcess: {
                        Task {
                            await processBeatDocResponse()
                        }
                    }
                )
                
            case .processing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing BeatDoc...")
                    .font(.headline)
                
            case .review:
                BeatDocReviewView(
                    beatDoc: processedBeatDoc!,
                    onBack: {
                        a1cStep = .pasteResponse
                        error = nil
                    },
                    onSave: {
                        Task {
                            await saveBeatDoc()
                        }
                    }
                )
                
            case .saving:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Saving BeatDoc to Firebase...")
                    .font(.headline)
                
            case .complete:
                AllBeatsCompleteView(
                    totalSections: savedAlignment?.sections.count ?? 0,
                    totalBeatsProcessed: savedBeatDocsForSection.count,
                    onDone: {
                        dismiss()
                    }
                )
            }
        }
    }
    
    // MARK: - A1a Helper Methods
    
    private func generateSectionPrompt() {
        let engine = SectionPromptEngine(video: video)
        sectionPrompt = engine.generatePrompt()
    }
    
    private func processSectionResponse() async {
        a1aStep = .processing
        error = nil
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let engine = SectionPromptEngine(video: video)
        
        do {
            let response = try engine.parseResponse(sectionResponse)
            let alignmentData = engine.calculateTimestamps(response: response)
            
            processedAlignment = alignmentData
            a1aStep = .review
            
        } catch {
            self.error = error.localizedDescription
            a1aStep = .pasteResponse
        }
    }
    
    private func saveAlignment() async {
        print("\n")
        print("========================================")
        print("💾 STARTING FIREBASE SAVE")
        print("========================================")
        
        guard let alignment = processedAlignment else {
            print("❌ No processedAlignment - this shouldn't happen")
            return
        }
        
        print("✅ Have alignment data:")
        print("  - Sections: \(alignment.sections.count)")
        print("  - Video ID: \(video.videoId)")
        print("  - Channel ID: \(video.channelId)")
        
        a1aStep = .saving
        error = nil
        
        print("\n📤 State changed to .saving")
        
        do {
            // 1. Save sections
            try await CreatorAnalysisFirebase.shared.saveSections(
                sections: alignment.sections,
                videoId: video.videoId,
                channelId: video.channelId
            )
            
            // 2. Save analysis to video doc
            try await YouTubeFirebaseService.shared.saveVideoAnalysis(
                videoId: video.videoId,
                videoSummary: alignment.videoSummary,
                logicSpine: alignment.logicSpine,
                bridgePoints: alignment.bridgePoints,
                validationStatus: alignment.validationStatus,
                validationIssues: alignment.validationIssues,
                extractionDate: alignment.extractionDate
            )
            
            savedAlignment = alignment
            a1aStep = .complete
            
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            a1aStep = .review
        }
    }
    
    // MARK: - A1b Helper Methods
    
    private func generateBeatPrompt() {
        guard let alignment = savedAlignment else { return }

        let engine = BeatPromptEngine(
            video: video,
            sections: alignment.sections,
            currentIndex: currentSectionIndex
        )
        beatPrompt = engine.generatePrompt()
    }
    
    private func processBeatResponse() async {
        a1bStep = .processing
        error = nil
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        guard let alignment = savedAlignment else { return }

        let engine = BeatPromptEngine(video: video, sections: alignment.sections, currentIndex: currentSectionIndex)

        do {
            let response = try engine.parseResponse(beatResponse)
            let beatData = try engine.calculateTimestamps(response: response)
            
            currentSectionBeatData = beatData // Store in memory temporarily
            a1bStep = .review
            
        } catch {
            self.error = error.localizedDescription
            a1bStep = .pasteResponse
        }
    }
    private func saveBeatsAndTransitionToA1c() async {
        guard let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1bStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            // Save minimal BeatDocs (A1b data only - everything else defaults to empty/0/false)
            for (index, beat) in beatData.beats.enumerated() {
                let wordCount = beat.endWordIndex - beat.startWordIndex + 1
                let minimalBeatDoc = BeatDoc(
                    // MARK: - IDENTITY & ORIGIN
                    beatId: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
                    beatKey: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
                    sectionId: section.id,
                    sectionKey: section.id,
                    sourceVideoId: video.videoId,
                    sourceChannelId: video.channelId,
                    type: beat.type,
                    beatRole: "standard",
                    
                    // MARK: - CONTENT
                    text: beat.text,
                    
                    // MARK: - TEXT ANCHORING
                    sentenceIndexScope: "transcript",
                    sentenceStartIndex: 0,
                    sentenceEndIndex: 0,
                    startWordIndex: beat.startWordIndex,
                    endWordIndex: beat.endWordIndex,
                    wordCount: wordCount,
                    startCharIndex: 0,
                    endCharIndex: 0,
                    
                    // MARK: - COMPILER / EXTRACTION INTENT
                    compilerFunction: "",
                    compilerWhyNow: "",
                    compilerSetsUp: "",
                    compilerEvidenceKind: "none",
                    compilerEvidenceText: "",
                    
                    // MARK: - CORE RETRIEVAL
                    moveKey: "UNKNOWN",
                    mechanicsTags: [],
                    retrievalPriority: "medium",
                    
                    // MARK: - PROOF (A1b clustering field)
                    proofMode: beat.proofMode,
                    proofDensity: "none",
                    
                    // MARK: - MECHANICS (A1b clustering fields)
                    tempo: beat.tempo,
                    stance: beat.stance,
                    sentenceCount: 1,
                    avgSentenceLength: Double(wordCount),
                    sentenceLengthVariance: 0.0,
                    questionCount: beat.questionCount,
                    teaseDistance: 0,
                    personalVoice: false,
                    informationDensity: "moderate",
                    cognitiveLoad: "moderate",
                    
                    // MARK: - ENHANCED MECHANICS
                    sentenceRhythm: "none",
                    emotionalDirection: "flat",
                    questionPlacement: "none",
                    promiseExplicit: false,
                    
                    // MARK: - SPECIFICITY
                    namedEntities: [],
                    temporalAnchors: [],
                    quantitativeAnchors: [],
                    
                    // MARK: - CONTRAST
                    contrastPresent: false,
                    contrastType: "none",
                    
                    // MARK: - RHETORICAL DEVICES
                    rhetoricalDeviceLabels: [],
                    questionRhetorical: 0,
                    questionGenuine: 0,
                    questionOpen: 0,
                    questionSelfAnswer: 0,
                    
                    // MARK: - TOPIC (CORE)
                    topicPrimary: "",
                    topicSecondary: [],
                    topicSpecificity: "general_principle",
                    
                    // MARK: - TOPIC DEPTH
                    topicAbstraction: "none",
                    domainSpecificity: "broadly_applicable",
                    topicAccessibility: "general_audience",
                    subjectCategories: [],
                    crossDomainApplicability: [],
                    
                    // MARK: - STYLE (A1b clustering field)
                    styleFormality: beat.formality,
                    styleVocabularyLevel: 5,
                    styleHumor: "none",
                    
                    // MARK: - VOICE DETAILS
                    pronounUsage: "mixed",
                    casualMarkers: [],
                    contractions: "moderate",
                    humorDensity: "none",
                    profanity: false,
                    profanityType: "none",
                    
                    // MARK: - QUALITY & REUSABILITY
                    qualityLevel: "medium",
                    anchorStrength: 0,
                    reusabilityLevel: "medium",
                    qualityReasoning: "",
                    reusabilityScore: 5,
                    
                    // MARK: - REUSABILITY DETAILS
                    adaptationDifficulty: "moderate",
                    crossTopicViability: [],
                    usageFrequency: "moderate",
                    cooldownRecommendation: 0,
                    overuseRisk: "low",
                    contextDependency: "lightly_dependent",
                    frequencyClass: "common_pattern",
                    
                    // MARK: - HUMAN VALIDATION
                    humanValidatedBy: "",
                    humanValidatedAt: "",
                    
                    // MARK: - PROMISE/PAYOFF
                    promiseType: "none",
                    payoffType: "",
                    requiresPayoffWithinBeats: 0,
                    promiseStrength: "none",
                    
                    // MARK: - VOICE MOVES
                    voiceMoves: [],
                    customVoiceMoves: [],
                    customRhetoricalTags: [],
                    
                    // MARK: - ANCHORS (A1b clustering fields)
                    anchorIds: [],
                    containsAnchor: beat.containsAnchor,
                    anchorText: beat.anchorText,
                    anchorFunction: beat.anchorFunction,
                    anchorIsReusable: false,
                    anchorFamily: "none",
                    
                    // MARK: - BEAT RELATIONSHIPS
                    setsUpBeatIds: [],
                    paysOffBeatIds: [],
                    callsBackToBeatIds: [],
                    referencesBeatIds: [],
                    similarMoveKeys: [],
                    
                    // MARK: - SEMANTIC CONSTRAINTS
                    semanticConstraints: [],
                    mustIntroduce: "",
                    requiresContext: [],
                    
                    // MARK: - TRANSITIONS
                    transitionType: "",
                    transitionExpectation: "",
                    transitionBridgeType: "",
                    forwardPromiseBeatId: "",
                    forwardPromiseWillDeliver: "",
                    forwardPromiseType: "",
                    
                    // MARK: - TEMPLATE
                    templatePattern: "",
                    templateSlots: [],
                    templateApplicableTo: [],
                    templateRequiresSpecificity: false,
                    templateRequiresTimestamp: false,
                    templateRequiresNamedEntity: false,
                    templateExampleTopic: "",
                    templateExampleResult: "",
                    templateViability: "none",
                    
                    // MARK: - POSITION METADATA
                    orderIndex: index,
                    beatIndexInSection: index + 1,
                    sectionRole: section.role,
                    globalBeatIndex: 0,
                    totalBeatsInSection: beatData.beats.count,
                    totalBeatsInScript: 0,
                    
                    // MARK: - EMOTION
                    emotionArcPosition: "",
                    emotionTargetFeelings: [],
                    emotionAudienceState: "",
                    emotionDevice: "",
                    emotionValence: 0,
                    emotionArousal: 0,
                    emotionIntensity: 0,
                    emotionTrajectory: "stable",
                    
                    // MARK: - MUSIC BRIEF
                    musicBrief: "",
                    musicInstrumentation: [],
                    musicTempoRange: "",
                    musicMood: "",
                    musicDynamicRange: "",
                    
                    // MARK: - ARGUMENT STRUCTURE
                    argumentPolarity: "neutral",
                    argumentResolutionStyle: "",
                    argumentMove: "",
                    argumentEvidenceStrategy: "",
                    logicalFlow: "linear",
                    argumentStructure: "claim_evidence",
                    
                    // MARK: - FACTUAL CLAIMS
                    hasFactualClaims: false,
                    hasNumbers: false,
                    hasQuotes: false,
                    hasHistoricalReferences: false,
                    claimRisk: "low",
                    claimKinds: [],
                    requiresHedge: false,
                    specificityLevel: "",
                    
                    // MARK: - RHETORICAL DETAIL
                    rhetoricalDetail_foreshadowing_usage: "",
                    rhetoricalDetail_foreshadowing_example: "",
                    rhetoricalDetail_specificity_usage: "",
                    rhetoricalDetail_specificity_example: "",
                    
                    // MARK: - NARRATIVE
                    narrativeTechniques: [],
                    
                    // MARK: - VOICE METRICS
                    pronounFrequency: 0,
                    directAddress: false,
                    toneIndicators: [],
                    
                    // MARK: - PROSE DESCRIPTIONS
                    mechanicsDescription: "",
                    topicDescription: "",
                    
                    // MARK: - WRITER GUIDANCE
                    writerHints: [],
                    avoidContexts: [],
                    
                    // MARK: - PERFORMANCE SIGNALS
                    performanceRetentionAtBeat: 0.0,
                    performanceEngagementLift: "unknown",
                    performanceConfidence: 0.0,
                    
                    // MARK: - EXTRACTION METADATA
                    extractedAt: ISO8601DateFormatter().string(from: Date()),
                    extractedBy: "A1b_beat_extractor",
                    extractorVersion: "2.0",
                    parseConfidence: 0.8,
                    manualReviewRequired: false,
                    reviewNotes: ""
                )
                
                try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                    beatDoc: minimalBeatDoc,
                    videoId: video.videoId,
                    channelId: video.channelId,
                    sectionId: section.id
                )
            }
            
            await MainActor.run {
                currentPhase = .a1c_beatDocs
                a1cStep = .showPrompt
                currentBeatIndex = 0
                savedBeatDocsForSection = []
                generateBeatDocPrompt()
            }
            
        } catch {
            await MainActor.run {
                self.error = "Failed to save beats: \(error.localizedDescription)"
                a1bStep = .review
            }
        }
    }
    
    private func saveBeatsAndTransitionToA1cOld() async {
        guard let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1bStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            // Save minimal BeatDocs (A1b data only - everything else defaults to empty/0/false)
            for (index, beat) in beatData.beats.enumerated() {
                let wordCount = beat.endWordIndex - beat.startWordIndex + 1
                let minimalBeatDoc = BeatDoc(
                    // MARK: - IDENTITY & ORIGIN
                    beatId: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
                    beatKey: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
                    sectionId: section.id,
                    sectionKey: section.id,
                    sourceVideoId: video.videoId,
                    sourceChannelId: video.channelId,
                    type: beat.type,
                    beatRole: "standard", // default
                    
                    // MARK: - CONTENT
                    text: beat.text,
                    
                    // MARK: - TEXT ANCHORING
                    sentenceIndexScope: "transcript",
                    sentenceStartIndex: 0, // default
                    sentenceEndIndex: 0, // default
                    startWordIndex: beat.startWordIndex,
                    endWordIndex: beat.endWordIndex,
                    wordCount: wordCount,
                    startCharIndex: 0, // default
                    endCharIndex: 0, // default
                    
                    // MARK: - COMPILER / EXTRACTION INTENT
                    compilerFunction: "",
                    compilerWhyNow: "",
                    compilerSetsUp: "",
                    compilerEvidenceKind: "none",
                    compilerEvidenceText: "",
                    
                    // MARK: - CORE RETRIEVAL
                    moveKey: "UNKNOWN",
                    mechanicsTags: [],
                    retrievalPriority: "medium",
                    
                    // MARK: - PROOF
                    proofMode: "none",
                    proofDensity: "none",
                    
                    // MARK: - MECHANICS (CORE)
                    tempo: "medium",
                    stance: "neutral",
                    sentenceCount: 1,
                    avgSentenceLength: Double(wordCount),
                    sentenceLengthVariance: 0.0,
                    questionCount: 0,
                    teaseDistance: 0,
                    personalVoice: false,
                    informationDensity: "moderate",
                    cognitiveLoad: "moderate",
                    
                    // MARK: - ENHANCED MECHANICS
                    sentenceRhythm: "none",
                    emotionalDirection: "flat",
                    questionPlacement: "none",
                    promiseExplicit: false,
                    
                    // MARK: - SPECIFICITY
                    namedEntities: [],
                    temporalAnchors: [],
                    quantitativeAnchors: [],
                    
                    // MARK: - CONTRAST
                    contrastPresent: false,
                    contrastType: "none",
                    
                    // MARK: - RHETORICAL DEVICES
                    rhetoricalDeviceLabels: [],
                    questionRhetorical: 0,
                    questionGenuine: 0,
                    questionOpen: 0,
                    questionSelfAnswer: 0,
                    
                    // MARK: - TOPIC (CORE)
                    topicPrimary: "",
                    topicSecondary: [],
                    topicSpecificity: "general_principle",
                    
                    // MARK: - TOPIC DEPTH
                    topicAbstraction: "none",
                    domainSpecificity: "broadly_applicable",
                    topicAccessibility: "general_audience",
                    subjectCategories: [],
                    crossDomainApplicability: [],
                    
                    // MARK: - STYLE (CORE)
                    styleFormality: 5,
                    styleVocabularyLevel: 5,
                    styleHumor: "none",
                    
                    // MARK: - VOICE DETAILS
                    pronounUsage: "mixed",
                    casualMarkers: [],
                    contractions: "moderate",
                    humorDensity: "none",
                    profanity: false,
                    profanityType: "none",
                    
                    // MARK: - QUALITY & REUSABILITY
                    qualityLevel: "medium",
                    anchorStrength: 0,
                    reusabilityLevel: "medium",
                    qualityReasoning: "",
                    reusabilityScore: 5,
                    
                    // MARK: - REUSABILITY DETAILS
                    adaptationDifficulty: "moderate",
                    crossTopicViability: [],
                    usageFrequency: "moderate",
                    cooldownRecommendation: 0,
                    overuseRisk: "low",
                    contextDependency: "lightly_dependent",
                    frequencyClass: "common_pattern",
                    
                    // MARK: - HUMAN VALIDATION
                    humanValidatedBy: "",
                    humanValidatedAt: "",
                    
                    // MARK: - PROMISE/PAYOFF
                    promiseType: "none",
                    payoffType: "",
                    requiresPayoffWithinBeats: 0,
                    promiseStrength: "none",
                    
                    // MARK: - VOICE MOVES
                    voiceMoves: [],
                    customVoiceMoves: [],
                    customRhetoricalTags: [],
                    
                    // MARK: - ANCHORS
                    anchorIds: [],
                    containsAnchor: false,
                    anchorText: "",
                    anchorFunction: "none",
                    anchorIsReusable: false,
                    anchorFamily: "none",
                    
                    // MARK: - BEAT RELATIONSHIPS (ALL UUIDs)
                    setsUpBeatIds: [],
                    paysOffBeatIds: [],
                    callsBackToBeatIds: [],
                    referencesBeatIds: [],
                    similarMoveKeys: [],
                    
                    // MARK: - SEMANTIC CONSTRAINTS
                    semanticConstraints: [],
                    mustIntroduce: "",
                    requiresContext: [],
                    
                    // MARK: - TRANSITIONS
                    transitionType: "",
                    transitionExpectation: "",
                    transitionBridgeType: "",
                    forwardPromiseBeatId: "",
                    forwardPromiseWillDeliver: "",
                    forwardPromiseType: "",
                    
                    // MARK: - TEMPLATE
                    templatePattern: "",
                    templateSlots: [],
                    templateApplicableTo: [],
                    templateRequiresSpecificity: false,
                    templateRequiresTimestamp: false,
                    templateRequiresNamedEntity: false,
                    templateExampleTopic: "",
                    templateExampleResult: "",
                    templateViability: "none",
                    
                    // MARK: - POSITION METADATA
                    orderIndex: index,
                    beatIndexInSection: index + 1,
                    sectionRole: section.role,
                    globalBeatIndex: 0, // will need to be calculated later
                    totalBeatsInSection: beatData.beats.count,
                    totalBeatsInScript: 0, // will need to be calculated later
                    
                    // MARK: - EMOTION
                    emotionArcPosition: "",
                    emotionTargetFeelings: [],
                    emotionAudienceState: "",
                    emotionDevice: "",
                    emotionValence: 0,
                    emotionArousal: 0,
                    emotionIntensity: 0,
                    emotionTrajectory: "stable",
                    
                    // MARK: - MUSIC BRIEF
                    musicBrief: "",
                    musicInstrumentation: [],
                    musicTempoRange: "",
                    musicMood: "",
                    musicDynamicRange: "",
                    
                    // MARK: - ARGUMENT STRUCTURE
                    argumentPolarity: "neutral",
                    argumentResolutionStyle: "",
                    argumentMove: "",
                    argumentEvidenceStrategy: "",
                    logicalFlow: "linear",
                    argumentStructure: "claim_evidence",
                    
                    // MARK: - FACTUAL CLAIMS
                    hasFactualClaims: false,
                    hasNumbers: false,
                    hasQuotes: false,
                    hasHistoricalReferences: false,
                    claimRisk: "low",
                    claimKinds: [],
                    requiresHedge: false,
                    specificityLevel: "",
                    
                    // MARK: - RHETORICAL DETAIL
                    rhetoricalDetail_foreshadowing_usage: "",
                    rhetoricalDetail_foreshadowing_example: "",
                    rhetoricalDetail_specificity_usage: "",
                    rhetoricalDetail_specificity_example: "",
                    
                    // MARK: - NARRATIVE
                    narrativeTechniques: [],
                    
                    // MARK: - VOICE METRICS
                    pronounFrequency: 0,
                    directAddress: false,
                    toneIndicators: [],
                    
                    // MARK: - PROSE DESCRIPTIONS
                    mechanicsDescription: "",
                    topicDescription: "",
                    
                    // MARK: - WRITER GUIDANCE
                    writerHints: [],
                    avoidContexts: [],
                    
                    // MARK: - PERFORMANCE SIGNALS
                    performanceRetentionAtBeat: 0.0,
                    performanceEngagementLift: "unknown",
                    performanceConfidence: 0.0,
                    
                    // MARK: - EXTRACTION METADATA
                    extractedAt: ISO8601DateFormatter().string(from: Date()),
                    extractedBy: "A1b_beat_extractor",
                    extractorVersion: "1.0",
                    parseConfidence: 0.8,
                    manualReviewRequired: false,
                    reviewNotes: ""
                )
                
                try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                    beatDoc: minimalBeatDoc,
                    videoId: video.videoId,
                    channelId: video.channelId,
                    sectionId: section.id
                )
            }
            
            await MainActor.run {
                currentPhase = .a1c_beatDocs
                a1cStep = .showPrompt
                currentBeatIndex = 0
                savedBeatDocsForSection = []
                generateBeatDocPrompt()
            }
            
        } catch {
            await MainActor.run {
                self.error = "Failed to save beats: \(error.localizedDescription)"
                a1bStep = .review
            }
        }
    }
    
    // MARK: - A1c Helper Methods
    
    private func generateBeatDocPrompt() {
        guard let alignment = savedAlignment,
              let beatData = currentSectionBeatData else { return }
        
        let section = alignment.sections[currentSectionIndex]
        let beat = beatData.beats[currentBeatIndex]
        
        let engine = BeatDocPromptEngine(
            video: video,
            beat: beat,
            section: section,
            allBeatsInSection: beatData.beats
        )
        beatDocPrompt = engine.generatePrompt()
    }
    
    private func processBeatDocResponse() async {
        a1cStep = .processing
        error = nil
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        guard let alignment = savedAlignment,
              let beatData = currentSectionBeatData else { return }
        
        let section = alignment.sections[currentSectionIndex]
        let beat = beatData.beats[currentBeatIndex]
        
        let engine = BeatDocPromptEngine(
            video: video,
            beat: beat,
            section: section,
            allBeatsInSection: beatData.beats
        )
        
        do {
            let response = try engine.parseResponse(beatDocResponse)
            
            // Convert BeatDocResponse to BeatDoc
            processedBeatDoc = convertToBeatDoc(response)
            a1cStep = .review
            
        } catch {
            self.error = error.localizedDescription
            a1cStep = .pasteResponse
        }
    }
    
    private func saveBeatDoc() async {
        guard let beatDoc = processedBeatDoc,
              let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1cStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            // Save BeatDoc to Firebase (flat structure with references)
            try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                beatDoc: beatDoc,
                videoId: video.videoId,
                channelId: video.channelId,
                sectionId: section.id
            )
            
            savedBeatDocsForSection.append(beatDoc)
            
            // Check if more beats in this section
            if currentBeatIndex < beatData.beats.count - 1 {
                // Next beat in same section
                currentBeatIndex += 1
                beatDocResponse = ""
                processedBeatDoc = nil
                a1cStep = .showPrompt
                generateBeatDocPrompt()
                
            } else {
                // Done with all beats in this section
                // Check if more sections
                if currentSectionIndex < (alignment.sections.count - 1) {
                    // Next section - back to A1b
                    currentSectionIndex += 1
                    currentPhase = .a1b_beats
                    a1bStep = .showPrompt
                    beatResponse = ""
                    currentSectionBeatData = nil
                    savedBeatDocsForSection = []
                    generateBeatPrompt()
                    
                } else {
                    // ALL DONE - all sections and beats complete
                    Task {
                            await computeAndSaveScriptSummary()
                        }
                    a1cStep = .complete
                }
            }
            
        } catch {
            self.error = "Failed to save BeatDoc: \(error.localizedDescription)"
            a1cStep = .review
        }
    }
    
    // MARK: - AI Auto-Run Methods
    private func autoRunA1a() async {
        await MainActor.run {
            autoRunning = true
            autoRunProgress = "Running A1a..."
            autoRunError = nil
        }
        
        do {
            let stepId = UUID()
            let a1aStep = PromptStep(
                id: stepId,
                title: "Section Analysis",
                prompt: sectionPrompt,
                notes: "",
                flowStrategy: .promptChaining,
                isBatchEligible: false,
                aiModel: .claude4Sonnet,
                useCashe: false
            )
            
            let agentId = UUID()
            let tempAgent = Agent(
                id: agentId,
                name: "A1a Temp",
                promptSteps: [a1aStep],
                chatSessions: []
            )
            
            let tempSession = ChatSession(
                id: UUID(),
                agentId: agentId,
                title: "A1a Analysis",
                createdAt: Date()
            )
            
            let executionEngine = AgentExecutionEngine(agent: tempAgent, session: tempSession)
            
            // Call runStep directly
            let run = try await executionEngine.runStep(
                step: a1aStep,
                userInput: "You are a helpful youtube video analyst",  // Empty because prompt is self-contained
                sharedInput: nil,
                purpose: .normal,
                inputID: nil
            )
            
            await MainActor.run {
                sectionResponse = run.response
            }
            
            await processSectionResponse()
            
            await MainActor.run {
                autoRunning = false
            }
            
        } catch {
            await MainActor.run {
                autoRunError = (phase: "A1a", error: error.localizedDescription)
                autoRunning = false
                a1aStep = .pasteResponse
            }
        }
    }
    

    private func autoRunA1b() async {
        await MainActor.run {
            autoRunning = true
            autoRunProgress = "Running A1b...\nSection \(currentSectionIndex + 1)..."
            autoRunError = nil
        }
        
        do {
            let stepId = UUID()
            let a1bStep = PromptStep(
                id: stepId,
                title: "Beat Extraction",
                prompt: beatPrompt,
                notes: "",
                flowStrategy: .promptChaining,
                isBatchEligible: false,
                aiModel: .claude4Sonnet,
                useCashe: false
            )
            
            let agentId = UUID()
            let tempAgent = Agent(
                id: agentId,
                name: "A1b Temp",
                promptSteps: [a1bStep],
                chatSessions: []
            )
            
            let tempSession = ChatSession(
                id: UUID(),
                agentId: agentId,
                title: "A1b Beats",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: tempAgent, session: tempSession)
            
            let dummyRun = PromptRun(
                promptStepId: stepId,
                chatSessionId: tempSession.id,
                basePrompt: beatPrompt,
                userInput: "",
                finalPrompt: beatPrompt,
                response: "",
                createdAt: Date(),
                inputID: UUID().uuidString,
                purpose: .normal
            )
            
            await runner.runCall(
                method: .normal(input: "You are a helpful youtube video analyst"),
                run: dummyRun,
                overridePrompt: beatPrompt
            )
            
            guard let lastRun = runner.promptRuns.last,
                  !lastRun.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "AI", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No response from Claude"])
            }
            
            await MainActor.run {
                beatResponse = lastRun.response
            }
            
            await processBeatResponse()
            
            await MainActor.run {
                autoRunning = false
            }
            
        } catch {
            await MainActor.run {
                autoRunError = (phase: "A1b Section \(currentSectionIndex + 1)", error: error.localizedDescription)
                autoRunning = false
                a1bStep = .pasteResponse
            }
        }
    }

    private func autoRunA1c() async {
        await MainActor.run {
            autoRunning = true
            autoRunProgress = "Running A1c...\nBeat \(currentBeatIndex + 1)..."
            autoRunError = nil
        }
        
        do {
            let stepId = UUID()
            let a1cStep = PromptStep(
                id: stepId,
                title: "BeatDoc",
                prompt: beatDocPrompt,
                notes: "",
                flowStrategy: .promptChaining,
                isBatchEligible: false,
                aiModel: .claude4Sonnet,
                useCashe: false
            )
            
            let agentId = UUID()
            let tempAgent = Agent(
                id: agentId,
                name: "A1c Temp",
                promptSteps: [a1cStep],
                chatSessions: []
            )
            
            let tempSession = ChatSession(
                id: UUID(),
                agentId: agentId,
                title: "A1c BeatDoc",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: tempAgent, session: tempSession)
            
            let dummyRun = PromptRun(
                promptStepId: stepId,
                chatSessionId: tempSession.id,
                basePrompt: beatDocPrompt,
                userInput: "",
                finalPrompt: beatDocPrompt,
                response: "",
                createdAt: Date(),
                inputID: UUID().uuidString,
                purpose: .normal
            )
            
            await runner.runCall(
                method: .normal(input: "You are a helpful youtube video analyst"),
                run: dummyRun,
                overridePrompt: beatDocPrompt
            )
            
            guard let lastRun = runner.promptRuns.last,
                  !lastRun.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "AI", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No response from Claude"])
            }
            
            await MainActor.run {
                beatDocResponse = lastRun.response
            }
            
            await processBeatDocResponse()
            
            await MainActor.run {
                autoRunning = false
            }
            
        } catch {
            await MainActor.run {
                autoRunError = (phase: "A1c Beat \(currentBeatIndex + 1)", error: error.localizedDescription)
                autoRunning = false
                a1cStep = .pasteResponse
            }
        }
    }
    
    private func autoRunAllBeatsInSection() async {
        guard let beatData = currentSectionBeatData else { return }
        
        await MainActor.run {
            autoRunning = true
        }
        
        // Loop through all beats in this section
        for beatIndex in 0..<beatData.beats.count {
            await MainActor.run {
                currentBeatIndex = beatIndex
                autoRunProgress = "Section \(currentSectionIndex + 1): Processing beat \(beatIndex + 1) of \(beatData.beats.count)..."
                generateBeatDocPrompt()
            }
            
            // Just call the working autoRunA1c function
            await autoRunA1c()
            
            if autoRunError != nil {
                // STOP on first error
                return
            }
            
            // Wait for review step to complete, then save
            if a1cStep == .review {
                await saveBeatDoc()
            }
        }
        
        await MainActor.run {
            autoRunning = false
        }
    }
    
    private func autoRunToCompletion() async {
        guard let alignment = savedAlignment else { return }
        
        autoRunning = true
        autoRunProgress = "Starting full video auto-run..."
        
        // If we're in A1b, run it first
        if currentPhase == .a1b_beats && a1bStep == .showPrompt {
            await autoRunA1b()
            if autoRunError != nil {
                await MainActor.run { autoRunning = false }
                return
            }
            
            // Wait for transition to A1c (happens in saveBeatsAndTransitionToA1c)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        // If we're in A1c, finish current section first
        if currentPhase == .a1c_beatDocs {
            await autoRunAllBeatsInSection()
            if autoRunError != nil {
                await MainActor.run { autoRunning = false }
                return
            }
        }
        
        // Now loop through remaining sections
        let totalSections = alignment.sections.count
        var sectionIdx = currentSectionIndex + 1
        
        while sectionIdx < totalSections {
            await MainActor.run {
                autoRunProgress = "Processing section \(sectionIdx + 1) of \(totalSections)..."
            }
            
            // Move to next section
            await MainActor.run {
                currentSectionIndex = sectionIdx
                currentPhase = .a1b_beats
                a1bStep = .showPrompt
                beatResponse = ""
                currentSectionBeatData = nil
                savedBeatDocsForSection = []
            }
            
            // Generate and run A1b
            await MainActor.run {
                generateBeatPrompt()
            }
            
            await autoRunA1b()
            if autoRunError != nil {
                await MainActor.run { autoRunning = false }
                return
            }
            
            // Wait for transition to A1c
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Run all A1c beats for this section
            await autoRunAllBeatsInSection()
            if autoRunError != nil {
                await MainActor.run { autoRunning = false }
                return
            }
            
            sectionIdx += 1
        }
        
        await MainActor.run {
            autoRunning = false
            autoRunProgress = "✅ Complete! All sections and beats processed."
        }
        
        // Show success for a moment before clearing
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await MainActor.run {
            autoRunProgress = ""
        }
    }
    
    private func convertToBeatDoc(_ response: BeatDocPromptEngine.BeatDocResponse) -> BeatDoc {
        return BeatDoc(
            // MARK: - IDENTITY & ORIGIN
            beatId: response.beatId,
            beatKey: response.beatKey,
            sectionId: response.sectionId,
            sectionKey: response.sectionKey,
            sourceVideoId: response.sourceVideoId,
            sourceChannelId: response.sourceChannelId,
            type: response.type,
            beatRole: response.beatRole,
            
            // MARK: - CONTENT
            text: response.text,
            
            // MARK: - TEXT ANCHORING
            sentenceIndexScope: response.sentenceIndexScope,
            sentenceStartIndex: response.sentenceStartIndex,
            sentenceEndIndex: response.sentenceEndIndex,
            startWordIndex: response.startWordIndex,
            endWordIndex: response.endWordIndex,
            wordCount: response.wordCount,
            startCharIndex: response.startCharIndex,
            endCharIndex: response.endCharIndex,
            
            // MARK: - COMPILER / EXTRACTION INTENT
            compilerFunction: response.compilerFunction,
            compilerWhyNow: response.compilerWhyNow,
            compilerSetsUp: response.compilerSetsUp,
            compilerEvidenceKind: response.compilerEvidenceKind,
            compilerEvidenceText: response.compilerEvidenceText,
            
            // MARK: - CORE RETRIEVAL
            moveKey: response.moveKey,
            mechanicsTags: response.mechanicsTags,
            retrievalPriority: response.retrievalPriority,
            
            // MARK: - PROOF
            proofMode: response.proofMode,
            proofDensity: response.proofDensity,
            
            // MARK: - MECHANICS (CORE)
            tempo: response.tempo,
            stance: response.stance,
            sentenceCount: response.sentenceCount,
            avgSentenceLength: response.avgSentenceLength,
            sentenceLengthVariance: response.sentenceLengthVariance,
            questionCount: response.questionCount,
            teaseDistance: response.teaseDistance,
            personalVoice: response.personalVoice,
            informationDensity: response.informationDensity,
            cognitiveLoad: response.cognitiveLoad,
            
            // MARK: - ENHANCED MECHANICS
            sentenceRhythm: response.sentenceRhythm,
            emotionalDirection: response.emotionalDirection,
            questionPlacement: response.questionPlacement,
            promiseExplicit: response.promiseExplicit,
            
            // MARK: - SPECIFICITY
            namedEntities: response.namedEntities,
            temporalAnchors: response.temporalAnchors,
            quantitativeAnchors: response.quantitativeAnchors,
            
            // MARK: - CONTRAST
            contrastPresent: response.contrastPresent,
            contrastType: response.contrastType,
            
            // MARK: - RHETORICAL DEVICES
            rhetoricalDeviceLabels: response.rhetoricalDeviceLabels,
            questionRhetorical: response.questionRhetorical,
            questionGenuine: response.questionGenuine,
            questionOpen: response.questionOpen,
            questionSelfAnswer: response.questionSelfAnswer,
            
            // MARK: - TOPIC (CORE)
            topicPrimary: response.topicPrimary,
            topicSecondary: response.topicSecondary,
            topicSpecificity: response.topicSpecificity,
            
            // MARK: - TOPIC DEPTH
            topicAbstraction: response.topicAbstraction,
            domainSpecificity: response.domainSpecificity,
            topicAccessibility: response.topicAccessibility,
            subjectCategories: response.subjectCategories,
            crossDomainApplicability: response.crossDomainApplicability,
            
            // MARK: - STYLE (CORE)
            styleFormality: response.styleFormality,
            styleVocabularyLevel: response.styleVocabularyLevel,
            styleHumor: response.styleHumor,
            
            // MARK: - VOICE DETAILS
            pronounUsage: response.pronounUsage,
            casualMarkers: response.casualMarkers,
            contractions: response.contractions,
            humorDensity: response.humorDensity,
            profanity: response.profanity,
            profanityType: response.profanityType,
            
            // MARK: - QUALITY & REUSABILITY
            qualityLevel: response.qualityLevel,
            anchorStrength: response.anchorStrength,
            reusabilityLevel: response.reusabilityLevel,
            qualityReasoning: response.qualityReasoning,
            reusabilityScore: response.reusabilityScore,
            
            // MARK: - REUSABILITY DETAILS
            adaptationDifficulty: response.adaptationDifficulty,
            crossTopicViability: response.crossTopicViability,
            usageFrequency: response.usageFrequency,
            cooldownRecommendation: response.cooldownRecommendation,
            overuseRisk: response.overuseRisk,
            contextDependency: response.contextDependency,
            frequencyClass: response.frequencyClass,
            
            // MARK: - HUMAN VALIDATION
            humanValidatedBy: response.humanValidatedBy,
            humanValidatedAt: response.humanValidatedAt,
            
            // MARK: - PROMISE/PAYOFF
            promiseType: response.promiseType,
            payoffType: response.payoffType,
            requiresPayoffWithinBeats: response.requiresPayoffWithinBeats,
            promiseStrength: response.promiseStrength,
            
            // MARK: - VOICE MOVES
            voiceMoves: response.voiceMoves,
            customVoiceMoves: response.customVoiceMoves,
            customRhetoricalTags: response.customRhetoricalTags,
            
            // MARK: - ANCHORS
            anchorIds: response.anchorIds,
            containsAnchor: response.containsAnchor,
            anchorText: response.anchorText,
            anchorFunction: response.anchorFunction,
            anchorIsReusable: response.anchorIsReusable,
            anchorFamily: response.anchorFamily,
            
            // MARK: - BEAT RELATIONSHIPS (ALL UUIDs)
            setsUpBeatIds: response.setsUpBeatIds,
            paysOffBeatIds: response.paysOffBeatIds,
            callsBackToBeatIds: response.callsBackToBeatIds,
            referencesBeatIds: response.referencesBeatIds,
            similarMoveKeys: response.similarMoveKeys,
            
            // MARK: - SEMANTIC CONSTRAINTS
            semanticConstraints: response.semanticConstraints,
            mustIntroduce: response.mustIntroduce,
            requiresContext: response.requiresContext,
            
            // MARK: - TRANSITIONS
            transitionType: response.transitionType,
            transitionExpectation: response.transitionExpectation,
            transitionBridgeType: response.transitionBridgeType,
            forwardPromiseBeatId: response.forwardPromiseBeatId,
            forwardPromiseWillDeliver: response.forwardPromiseWillDeliver,
            forwardPromiseType: response.forwardPromiseType,
            
            // MARK: - TEMPLATE
            templatePattern: response.templatePattern,
            templateSlots: response.templateSlots,
            templateApplicableTo: response.templateApplicableTo,
            templateRequiresSpecificity: response.templateRequiresSpecificity,
            templateRequiresTimestamp: response.templateRequiresTimestamp,
            templateRequiresNamedEntity: response.templateRequiresNamedEntity,
            templateExampleTopic: response.templateExampleTopic,
            templateExampleResult: response.templateExampleResult,
            templateViability: response.templateViability,
            
            // MARK: - POSITION METADATA
            orderIndex: response.orderIndex,
            beatIndexInSection: response.beatIndexInSection,
            sectionRole: response.sectionRole,
            globalBeatIndex: response.globalBeatIndex,
            totalBeatsInSection: response.totalBeatsInSection,
            totalBeatsInScript: response.totalBeatsInScript,
            
            // MARK: - EMOTION
            emotionArcPosition: response.emotionArcPosition,
            emotionTargetFeelings: response.emotionTargetFeelings,
            emotionAudienceState: response.emotionAudienceState,
            emotionDevice: response.emotionDevice,
            emotionValence: response.emotionValence,
            emotionArousal: response.emotionArousal,
            emotionIntensity: response.emotionIntensity,
            emotionTrajectory: response.emotionTrajectory,
            
            // MARK: - MUSIC BRIEF
            musicBrief: response.musicBrief,
            musicInstrumentation: response.musicInstrumentation,
            musicTempoRange: response.musicTempoRange,
            musicMood: response.musicMood,
            musicDynamicRange: response.musicDynamicRange,
            
            // MARK: - ARGUMENT STRUCTURE
            argumentPolarity: response.argumentPolarity,
            argumentResolutionStyle: response.argumentResolutionStyle,
            argumentMove: response.argumentMove,
            argumentEvidenceStrategy: response.argumentEvidenceStrategy,
            logicalFlow: response.logicalFlow,
            argumentStructure: response.argumentStructure,
            
            // MARK: - FACTUAL CLAIMS
            hasFactualClaims: response.hasFactualClaims,
            hasNumbers: response.hasNumbers,
            hasQuotes: response.hasQuotes,
            hasHistoricalReferences: response.hasHistoricalReferences,
            claimRisk: response.claimRisk,
            claimKinds: response.claimKinds,
            requiresHedge: response.requiresHedge,
            specificityLevel: response.specificityLevel,
            
            // MARK: - RHETORICAL DETAIL
            rhetoricalDetail_foreshadowing_usage: response.rhetoricalDetail_foreshadowing_usage,
            rhetoricalDetail_foreshadowing_example: response.rhetoricalDetail_foreshadowing_example,
            rhetoricalDetail_specificity_usage: response.rhetoricalDetail_specificity_usage,
            rhetoricalDetail_specificity_example: response.rhetoricalDetail_specificity_example,
            
            // MARK: - NARRATIVE
            narrativeTechniques: response.narrativeTechniques,
            
            // MARK: - VOICE METRICS
            pronounFrequency: response.pronounFrequency,
            directAddress: response.directAddress,
            toneIndicators: response.toneIndicators,
            
            // MARK: - PROSE DESCRIPTIONS
            mechanicsDescription: response.mechanicsDescription,
            topicDescription: response.topicDescription,
            
            // MARK: - WRITER GUIDANCE
            writerHints: response.writerHints,
            avoidContexts: response.avoidContexts,
            
            // MARK: - PERFORMANCE SIGNALS
            performanceRetentionAtBeat: response.performanceRetentionAtBeat,
            performanceEngagementLift: response.performanceEngagementLift,
            performanceConfidence: response.performanceConfidence,
            
            // MARK: - EXTRACTION METADATA
            extractedAt: response.extractedAt,
            extractedBy: response.extractedBy,
            extractorVersion: response.extractorVersion,
            parseConfidence: response.parseConfidence,
            manualReviewRequired: response.manualReviewRequired,
            reviewNotes: response.reviewNotes
        )
    }
    
    // MARK: - Progress Views
    
    private func sectionProgressView(alignment: AlignmentData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Section \(currentSectionIndex + 1) of \(alignment.sections.count)")
                .font(.headline)
            
            ProgressView(value: Double(currentSectionIndex), total: Double(alignment.sections.count))
            
            ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
                HStack {
                    if index < currentSectionIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if index == currentSectionIndex {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(section.role)")
                        .font(.subheadline)
                        .fontWeight(index == currentSectionIndex ? .bold : .regular)
                    
                    Spacer()
                }
                .padding(8)
                .background(index == currentSectionIndex ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func beatProgressView(beatData: SimpleBeatData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beat \(currentBeatIndex + 1) of \(beatData.beats.count)")
                .font(.headline)
            
            ProgressView(value: Double(currentBeatIndex), total: Double(beatData.beats.count))
            
            ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
                HStack {
                    if index < currentBeatIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if index == currentBeatIndex {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(beat.type)")
                        .font(.subheadline)
                        .fontWeight(index == currentBeatIndex ? .bold : .regular)
                    
                    Spacer()
                }
                .padding(8)
                .background(index == currentBeatIndex ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - SimpleBeat Review View

//struct SimpleBeatReviewView: View {
//    let beatData: SimpleBeatData
//    let onBack: () -> Void
//    let onContinue: () -> Void
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "3.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.orange)
//                Text("Review Beat Boundaries")
//                    .font(.headline)
//            }
//            
//            Text("These are just boundaries - full analysis comes in A1c")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            ScrollView {
//                VStack(alignment: .leading, spacing: 12) {
//                    ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
//                        VStack(alignment: .leading, spacing: 8) {
//                            HStack {
//                                Text(beat.type)
//                                    .font(.caption)
//                                    .padding(.horizontal, 8)
//                                    .padding(.vertical, 4)
//                                    .background(beatTypeColor(beat.type).opacity(0.2))
//                                    .foregroundColor(beatTypeColor(beat.type))
//                                    .cornerRadius(4)
//                                
//                                Spacer()
//                                
//                                Text("Words \(beat.startWordIndex)-\(beat.endWordIndex)")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            
//                            Text(String(beat.text.prefix(100)))
//                                .font(.body)
//                                .lineLimit(2)
//                        }
//                        .padding()
//                        .background(Color(.tertiarySystemBackground))
//                        .cornerRadius(8)
//                    }
//                }
//            }
//            .frame(maxHeight: 400)
//            
//            HStack {
//                Button(action: onBack) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: onContinue) {
//                    Label("Save & Continue to A1c", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    private func beatTypeColor(_ type: String) -> Color {
//        switch type {
//        case "TEASE": return .purple
//        case "QUESTION": return .blue
//        case "PROMISE": return .green
//        case "DATA": return .orange
//        case "STORY": return .pink
//        default: return .gray
//        }
//    }
//}
//
//// MARK: - BeatDoc Review View
//
//struct BeatDocReviewView: View {
//    let beatDoc: BeatDoc
//    let onBack: () -> Void
//    let onSave: () -> Void
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "3.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.orange)
//                Text("Review BeatDoc")
//                    .font(.headline)
//            }
//            
//            ScrollView {
//                VStack(alignment: .leading, spacing: 16) {
//                    // Key fields preview
//                    Group {
//                        InfoRow(label: "Move Key", value: beatDoc.moveKey)
//                        InfoRow(label: "Quality", value: beatDoc.qualityLevel)
//                        InfoRow(label: "Tempo", value: beatDoc.tempo)
//                        InfoRow(label: "Stance", value: beatDoc.stance)
//                        InfoRow(label: "Proof Mode", value: beatDoc.proofMode)
//                    }
//                    
//                    Divider()
//                    
//                    Text("Text Preview")
//                        .font(.headline)
//                    Text(String(beatDoc.text.prefix(200)))
//                        .font(.body)
//                    
//                    Divider()
//                    
//                    Text("Compiler Function")
//                        .font(.headline)
//                    Text(beatDoc.compilerFunction)
//                        .font(.body)
//                        .foregroundColor(.secondary)
//                }
//            }
//            .frame(maxHeight: 400)
//            
//            HStack {
//                Button(action: onBack) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: onSave) {
//                    Label("Save BeatDoc", systemImage: "square.and.arrow.down")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//}
//
//struct InfoRow: View {
//    let label: String
//    let value: String
//    
//    var body: some View {
//        HStack {
//            Text(label)
//                .font(.caption)
//                .foregroundColor(.secondary)
//            Spacer()
//            Text(value)
//                .font(.caption)
//                .fontWeight(.medium)
//        }
//        .padding(8)
//        .background(Color(.tertiarySystemBackground))
//        .cornerRadius(6)
//    }
//}
//
//// MARK: - All Beats Complete View
//
//struct AllBeatsCompleteView: View {
//    let totalSections: Int
//    let totalBeatsProcessed: Int
//    let onDone: () -> Void
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.title)
//                    .foregroundColor(.green)
//                Text("All Analysis Complete!")
//                    .font(.headline)
//            }
//            
//            VStack(alignment: .leading, spacing: 12) {
//                Text("✅ Processed \(totalSections) sections")
//                Text("✅ Created full BeatDocs for all beats")
//                Text("✅ All data saved to Firebase")
//            }
//            .font(.subheadline)
//            .padding()
//            .background(Color(.secondarySystemBackground))
//            .cornerRadius(8)
//            
//            Button(action: onDone) {
//                Text("Done")
//                    .frame(maxWidth: .infinity)
//            }
//            .buttonStyle(.borderedProminent)
//        }
//    }
//}
