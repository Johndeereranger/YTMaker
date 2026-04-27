//
//  IngestionPhase.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//


import SwiftUI
import Combine

// MARK: - Enums

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

enum IngestionFlow {
    case manual          // Full A1a → A1b → A1c flow with review steps
    case fastAnalysis    // A1a → A1b only, skip A1c, auto-save scriptSummary
}

// MARK: - ViewModel

@MainActor
class ManualIngestionViewModel: ObservableObject {
    
    // MARK: - Dependencies
    let video: YouTubeVideo
    var aiEngine: AIEngine?
    
    // MARK: - Flow Control
    @Published var currentFlow: IngestionFlow = .manual
    @Published var currentPhase: IngestionPhase = .a1a_sections
    
    // MARK: - A1a State
    @Published var a1aStep: PhaseStep = .showPrompt
    @Published var sectionPrompt: String = ""
    @Published var sectionResponse: String = ""
    @Published var processedAlignment: AlignmentData?
    @Published var savedAlignment: AlignmentData?
    
    // MARK: - A1b State (per section - NOT saved to Firebase until transition)
    @Published var a1bStep: PhaseStep = .showPrompt
    @Published var currentSectionIndex: Int = 0
    @Published var beatPrompt: String = ""
    @Published var beatResponse: String = ""
    @Published var currentSectionBeatData: SimpleBeatData?
    
    // MARK: - A1c State (per beat - SAVED to Firebase)
    @Published var a1cStep: PhaseStep = .showPrompt
    @Published var currentBeatIndex: Int = 0
    @Published var beatDocPrompt: String = ""
    @Published var beatDocResponse: String = ""
    @Published var processedBeatDoc: BeatDoc?
    @Published var savedBeatDocsForSection: [BeatDoc] = []
    
    // MARK: - Shared State
    @Published var isProcessing = false
    @Published var error: String?
    
    // MARK: - Auto-run State
    @Published var autoRunning = false
    @Published var autoRunProgress: String = ""
    @Published var autoRunError: (phase: String, error: String)?
    @Published var showAutoRunConfirmation = false
    var pendingAutoRunAction: (() -> Void)?
    
    // MARK: - Analysis Status
    @Published var analysisStatus: AnalysisStatus?
    @Published var showStatusView = false
    
    // MARK: - Computed Properties
    
    var navigationTitle: String {
        switch currentPhase {
        case .a1a_sections:
            return "A1a: Analyze Structure"
        case .a1b_beats:
            return "A1b: Extract Beats (Section \(currentSectionIndex + 1))"
        case .a1c_beatDocs:
            return "A1c: Beat Doc (Beat \(currentBeatIndex + 1))"
        }
    }
    
    var autoRunConfirmationMessage: String {
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
    
    // MARK: - Init
    
    init(video: YouTubeVideo) {
        self.video = video
        self.aiEngine = AIEngine(model: .claude35Sonnet)
    }
    
    // MARK: - Lifecycle
    
    func onAppear() async {
        await checkExistingAnalysis()
        
        if currentPhase == .a1a_sections && a1aStep == .showPrompt && !showStatusView {
            generateSectionPrompt()
        }
    }
    
    // MARK: - Status Check
    
    func checkExistingAnalysis() async {
        print("🔍 checkExistingAnalysis starting for video: \(video.videoId)")
        do {
            let alignment = try await CreatorAnalysisFirebase.shared.loadAlignmentDoc(
                videoId: video.videoId,
                channelId: video.channelId
            )

            print("🔍 loadAlignmentDoc returned: \(alignment == nil ? "nil" : "has data")")

            // Always create a status - even if no alignment exists
            // This allows fidelity testing without prior analysis
            if let alignment = alignment {
                print("🔍 Alignment found with \(alignment.sections.count) sections")

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

                analysisStatus = status
                savedAlignment = alignment
            } else {
                // No alignment exists - create minimal status for fidelity testing
                print("🔍 No alignment - creating minimal status for fidelity testing")
                let status = AnalysisStatus(
                    videoId: video.videoId,
                    channelId: video.channelId,
                    alignment: nil,
                    sectionStatuses: []
                )
                analysisStatus = status
            }

            // Always show status view - fidelity testing is always available
            showStatusView = true

        } catch {
            print("Error loading analysis: \(error.localizedDescription)")
            // Still show status view for fidelity testing
            let status = AnalysisStatus(
                videoId: video.videoId,
                channelId: video.channelId,
                alignment: nil,
                sectionStatuses: []
            )
            analysisStatus = status
            showStatusView = true
        }
    }
    
    // MARK: - Resume/Reprocess
    
    func startFresh() async {
        await reprocess(.a1a)
    }
    
    func resumeFromStatus(_ status: AnalysisStatus) {
        showStatusView = false
        
        guard let alignment = status.alignment else {
            currentPhase = .a1a_sections
            a1aStep = .showPrompt
            generateSectionPrompt()
            return
        }
        
        savedAlignment = alignment
        
        guard let incompleteSectionIndex = status.sectionStatuses.firstIndex(where: { !$0.isComplete }) else {
            currentPhase = .a1c_beatDocs
            Task { await computeAndSaveScriptSummary() }
            a1cStep = .complete
            return
        }
        
        let sectionStatus = status.sectionStatuses[incompleteSectionIndex]
        currentSectionIndex = incompleteSectionIndex
        
        if !sectionStatus.a1bComplete {
            currentPhase = .a1b_beats
            a1bStep = .showPrompt
            generateBeatPrompt()
        } else {
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
    
    func reprocess(_ target: ReprocessTarget) async {
        do {
            switch target {
            case .a1a:
                let sections = try await CreatorAnalysisFirebase.shared.loadSectionsForVideo(
                    videoId: video.videoId
                )
                
                for section in sections {
                    let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                        sectionId: section.id
                    )
                    for beatDoc in beatDocs {
                        try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatDoc.beatId)
                    }
                    try await CreatorAnalysisFirebase.shared.deleteSection(sectionId: section.id)
                }
                
                try await CreatorAnalysisFirebase.shared.clearVideoAnalysis(videoId: video.videoId)
                
                showStatusView = false
                savedAlignment = nil
                processedAlignment = nil
                currentSectionIndex = 0
                currentBeatIndex = 0
                currentPhase = .a1a_sections
                a1aStep = .showPrompt
                generateSectionPrompt()
                
            case .section(let sectionId):
                let beatDocs = try await CreatorAnalysisFirebase.shared.loadBeatDocsForSection(
                    sectionId: sectionId
                )
                
                for beatDoc in beatDocs {
                    try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatDoc.beatId)
                }
                
                if let alignment = savedAlignment,
                   let index = alignment.sections.firstIndex(where: { $0.id == sectionId }) {
                    showStatusView = false
                    currentSectionIndex = index
                    currentSectionBeatData = nil
                    currentBeatIndex = 0
                    currentPhase = .a1b_beats
                    a1bStep = .showPrompt
                    generateBeatPrompt()
                }
                
            case .beat(let sectionId, let beatId):
                try await CreatorAnalysisFirebase.shared.deleteBeatDoc(beatId: beatId)
                
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
            
        } catch {
            print("Reprocess error: \(error.localizedDescription)")
            self.error = "Failed to reprocess: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Run Missing Beats
    
    func runMissingBeatsInSection(_ sectionStatus: SectionAnalysisStatus) async {
        guard let alignment = savedAlignment ?? analysisStatus?.alignment else { return }
        
        let missingIndices = sectionStatus.incompleteBeatIndices
        guard !missingIndices.isEmpty else { return }
        
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
        
        for beatIndex in missingIndices {
            currentBeatIndex = beatIndex
            autoRunProgress = "Fixing beat \(beatIndex + 1) of section \(sectionStatus.sectionIndex + 1)..."
            generateBeatDocPrompt()
            
            await autoRunA1c()
            
            if autoRunError != nil { break }
            
            if a1cStep == .review {
                await saveBeatDoc()
            }
        }
        
        autoRunning = false
        await checkExistingAnalysis()
        showStatusView = true
    }
    
    func runAllMissingBeats() async {
        guard let status = analysisStatus else { return }
        
        for sectionStatus in status.sectionStatuses where !sectionStatus.incompleteBeatIndices.isEmpty {
            await runMissingBeatsInSection(sectionStatus)
            if autoRunError != nil { break }
        }
        
        await checkExistingAnalysis()
        showStatusView = true
    }
    
    // MARK: - A1a Methods
    
    func generateSectionPrompt() {
        let engine = SectionPromptEngine(video: video)
        sectionPrompt = engine.generatePrompt()
    }
    
    func processSectionResponse() async {
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
    
    // MARK: - Save Fidelity Result

    /// Save an alignment from a fidelity test run (when no existing analysis)
    func saveFidelityResult(_ alignment: AlignmentData) async {
        print("\n========================================")
        print("💾 SAVING FIDELITY RESULT TO FIREBASE")
        print("========================================")

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

            savedAlignment = alignment
            print("✅ Fidelity result saved successfully!")

            // Refresh the analysis status
            await checkExistingAnalysis()

        } catch {
            print("❌ Failed to save fidelity result: \(error.localizedDescription)")
        }
    }

    func saveAlignment() async {
        print("\n========================================")
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
            
            savedAlignment = alignment
            a1aStep = .complete
            
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
            a1aStep = .review
        }
    }
    
    // MARK: - A1b Methods
    
    func generateBeatPrompt() {
        guard let alignment = savedAlignment else { return }

        let engine = BeatPromptEngine(
            video: video,
            sections: alignment.sections,
            currentIndex: currentSectionIndex
        )
        beatPrompt = engine.generatePrompt()
    }
    
    func processBeatResponse() async {
        a1bStep = .processing
        error = nil
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        guard let alignment = savedAlignment else { return }

        let engine = BeatPromptEngine(video: video, sections: alignment.sections, currentIndex: currentSectionIndex)
        
        do {
            let response = try engine.parseResponse(beatResponse)
            let beatData = try engine.calculateTimestamps(response: response)
            
            currentSectionBeatData = beatData
            a1bStep = .review
            
        } catch {
            self.error = error.localizedDescription
            a1bStep = .pasteResponse
        }
    }
    
    func saveBeatsAndTransitionToA1c() async {
        guard let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1bStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            for (index, beat) in beatData.beats.enumerated() {
                let beatDoc = createMinimalBeatDoc(beat: beat, index: index, section: section, beatData: beatData)
                
                try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                    beatDoc: beatDoc,
                    videoId: video.videoId,
                    channelId: video.channelId,
                    sectionId: section.id
                )
            }
            
            currentPhase = .a1c_beatDocs
            a1cStep = .showPrompt
            currentBeatIndex = 0
            savedBeatDocsForSection = []
            generateBeatDocPrompt()
            
        } catch {
            self.error = "Failed to save beats: \(error.localizedDescription)"
            a1bStep = .review
        }
    }
    
    /// Save beats for A1b-only flow (no transition to A1c)
    func saveBeatsOnly() async {
        guard let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1bStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            for (index, beat) in beatData.beats.enumerated() {
                let beatDoc = createMinimalBeatDoc(beat: beat, index: index, section: section, beatData: beatData)
                
                try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                    beatDoc: beatDoc,
                    videoId: video.videoId,
                    channelId: video.channelId,
                    sectionId: section.id
                )
            }
            
            a1bStep = .complete
            
        } catch {
            self.error = "Failed to save beats: \(error.localizedDescription)"
            a1bStep = .review
        }
    }
    
    // MARK: - A1c Methods
    
    func generateBeatDocPrompt() {
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
    
    func processBeatDocResponse() async {
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
            processedBeatDoc = convertToBeatDoc(response)
            a1cStep = .review
            
        } catch {
            self.error = error.localizedDescription
            a1cStep = .pasteResponse
        }
    }
    
    func saveBeatDoc() async {
        guard let beatDoc = processedBeatDoc,
              let beatData = currentSectionBeatData,
              let alignment = savedAlignment else { return }
        
        a1cStep = .saving
        error = nil
        
        let section = alignment.sections[currentSectionIndex]
        
        do {
            try await CreatorAnalysisFirebase.shared.saveBeatDoc(
                beatDoc: beatDoc,
                videoId: video.videoId,
                channelId: video.channelId,
                sectionId: section.id
            )
            
            savedBeatDocsForSection.append(beatDoc)
            
            if currentBeatIndex < beatData.beats.count - 1 {
                currentBeatIndex += 1
                beatDocResponse = ""
                processedBeatDoc = nil
                a1cStep = .showPrompt
                generateBeatDocPrompt()
                
            } else {
                if currentSectionIndex < (alignment.sections.count - 1) {
                    currentSectionIndex += 1
                    currentPhase = .a1b_beats
                    a1bStep = .showPrompt
                    beatResponse = ""
                    currentSectionBeatData = nil
                    savedBeatDocsForSection = []
                    generateBeatPrompt()
                    
                } else {
                    Task { await computeAndSaveScriptSummary() }
                    a1cStep = .complete
                }
            }
            
        } catch {
            self.error = "Failed to save BeatDoc: \(error.localizedDescription)"
            a1cStep = .review
        }
    }
    
    // MARK: - Auto-Run Methods
    
    func autoRunA1a() async {
        autoRunning = true
        autoRunProgress = "Running A1a..."
        autoRunError = nil
        
        do {
            let stepId = UUID()
            let a1aPromptStep = PromptStep(
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
                promptSteps: [a1aPromptStep],
                chatSessions: []
            )
            
            let tempSession = ChatSession(
                id: UUID(),
                agentId: agentId,
                title: "A1a Analysis",
                createdAt: Date()
            )
            
            let executionEngine = AgentExecutionEngine(agent: tempAgent, session: tempSession)
            
            let run = try await executionEngine.runStep(
                step: a1aPromptStep,
                userInput: "You are a helpful youtube video analyst",
                sharedInput: nil,
                purpose: .normal,
                inputID: nil
            )
            
            sectionResponse = run.response
            await processSectionResponse()
            autoRunning = false
            
        } catch {
            autoRunError = (phase: "A1a", error: error.localizedDescription)
            autoRunning = false
            a1aStep = .pasteResponse
        }
    }
    
    func autoRunA1b() async {
        autoRunning = true
        autoRunProgress = "Running A1b...\nSection \(currentSectionIndex + 1)..."
        autoRunError = nil
        
        do {
            let stepId = UUID()
            let a1bPromptStep = PromptStep(
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
                promptSteps: [a1bPromptStep],
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
            
            beatResponse = lastRun.response
            await processBeatResponse()
            autoRunning = false
            
        } catch {
            autoRunError = (phase: "A1b Section \(currentSectionIndex + 1)", error: error.localizedDescription)
            autoRunning = false
            a1bStep = .pasteResponse
        }
    }
    
    func autoRunA1c() async {
        autoRunning = true
        autoRunProgress = "Running A1c...\nBeat \(currentBeatIndex + 1)..."
        autoRunError = nil
        
        do {
            let stepId = UUID()
            let a1cPromptStep = PromptStep(
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
                promptSteps: [a1cPromptStep],
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
            
            beatDocResponse = lastRun.response
            await processBeatDocResponse()
            autoRunning = false
            
        } catch {
            autoRunError = (phase: "A1c Beat \(currentBeatIndex + 1)", error: error.localizedDescription)
            autoRunning = false
            a1cStep = .pasteResponse
        }
    }
    
    func autoRunAllBeatsInSection() async {
        guard let beatData = currentSectionBeatData else { return }
        
        autoRunning = true
        
        for beatIndex in 0..<beatData.beats.count {
            currentBeatIndex = beatIndex
            autoRunProgress = "Section \(currentSectionIndex + 1): Processing beat \(beatIndex + 1) of \(beatData.beats.count)..."
            generateBeatDocPrompt()
            
            await autoRunA1c()
            
            if autoRunError != nil { return }
            
            if a1cStep == .review {
                await saveBeatDoc()
            }
        }
        
        autoRunning = false
    }
    
    func autoRunToCompletion() async {
        guard let alignment = savedAlignment else { return }
        
        autoRunning = true
        autoRunProgress = "Starting full video auto-run..."
        
        if currentPhase == .a1b_beats && a1bStep == .showPrompt {
            await autoRunA1b()
            if autoRunError != nil {
                autoRunning = false
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        if currentPhase == .a1c_beatDocs {
            await autoRunAllBeatsInSection()
            if autoRunError != nil {
                autoRunning = false
                return
            }
        }
        
        let totalSections = alignment.sections.count
        var sectionIdx = currentSectionIndex + 1
        
        while sectionIdx < totalSections {
            autoRunProgress = "Processing section \(sectionIdx + 1) of \(totalSections)..."
            
            currentSectionIndex = sectionIdx
            currentPhase = .a1b_beats
            a1bStep = .showPrompt
            beatResponse = ""
            currentSectionBeatData = nil
            savedBeatDocsForSection = []
            
            generateBeatPrompt()
            
            await autoRunA1b()
            if autoRunError != nil {
                autoRunning = false
                return
            }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await autoRunAllBeatsInSection()
            if autoRunError != nil {
                autoRunning = false
                return
            }
            
            sectionIdx += 1
        }
        
        autoRunning = false
        autoRunProgress = "✅ Complete! All sections and beats processed."
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        autoRunProgress = ""
    }
    
    // MARK: - Fast Analysis Flow (A1a + A1b only, skip A1c)
    
    /// Run A1a + all A1b sections, then save scriptSummary. Skips A1c entirely.
    func runFastAnalysis() async {
        currentFlow = .fastAnalysis
        autoRunning = true
        autoRunError = nil
        
        // Step 1: Run A1a
        autoRunProgress = "Running A1a (Section Analysis)..."
        generateSectionPrompt()
        await autoRunA1a()
        
        if autoRunError != nil {
            autoRunning = false
            return
        }
        
        // Save A1a results
        if a1aStep == .review {
            await saveAlignment()
        }
        
        guard let alignment = savedAlignment else {
            autoRunError = (phase: "A1a", error: "Failed to save alignment")
            autoRunning = false
            return
        }
        
        // Step 2: Run A1b for all sections
        let totalSections = alignment.sections.count
        
        for sectionIdx in 0..<totalSections {
            autoRunProgress = "Running A1b: Section \(sectionIdx + 1) of \(totalSections)..."
            
            currentSectionIndex = sectionIdx
            currentPhase = .a1b_beats
            a1bStep = .showPrompt
            beatResponse = ""
            currentSectionBeatData = nil
            
            generateBeatPrompt()
            await autoRunA1b()
            
            if autoRunError != nil {
                autoRunning = false
                return
            }
            
            // Save beats (without transitioning to A1c)
            if a1bStep == .review {
                await saveBeatsOnly()
            }
            
            if autoRunError != nil {
                autoRunning = false
                return
            }
        }
        
        // Step 3: Compute and save scriptSummary
        autoRunProgress = "Computing script summary..."
        await computeAndSaveScriptSummary()
        
        autoRunning = false
        autoRunProgress = "✅ Fast analysis complete!"
        
        // Refresh status
        await checkExistingAnalysis()
    }
    
    /// Run A1b for all remaining sections (assumes A1a is already done)
    func runRemainingA1b() async {
        guard let alignment = savedAlignment else { return }
        
        autoRunning = true
        autoRunError = nil
        
        let totalSections = alignment.sections.count
        let startSection = currentSectionIndex
        
        for sectionIdx in startSection..<totalSections {
            autoRunProgress = "Running A1b: Section \(sectionIdx + 1) of \(totalSections)..."
            
            currentSectionIndex = sectionIdx
            currentPhase = .a1b_beats
            a1bStep = .showPrompt
            beatResponse = ""
            currentSectionBeatData = nil
            
            generateBeatPrompt()
            await autoRunA1b()
            
            if autoRunError != nil {
                autoRunning = false
                return
            }
            
            if a1bStep == .review {
                await saveBeatsOnly()
            }
        }
        
        // Compute scriptSummary after all sections
        autoRunProgress = "Computing script summary..."
        await computeAndSaveScriptSummary()
        
        autoRunning = false
        autoRunProgress = "✅ All sections processed!"
        
        await checkExistingAnalysis()
    }
    
    // MARK: - Script Summary
    
    func computeAndSaveScriptSummary() async {
        guard let alignment = savedAlignment else { return }
        
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
        
        let summary = computeScriptSummary(sections: alignment.sections, beats: allBeats)
        
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
        let sectionSequence = sections.map { $0.role }
        
        let turnPosition: Double = {
            guard let turnIndex = sections.firstIndex(where: { $0.role.uppercased() == "TURN" }) else {
                return 0.5
            }
            return Double(turnIndex) / Double(max(sections.count - 1, 1))
        }()
        
        var beatDistribution: [String: Int] = [:]
        for beat in beats {
            beatDistribution[beat.type, default: 0] += 1
        }
        
        var beatDistributionBySection: [String: [String: Int]] = [:]
        for section in sections {
            let sectionBeats = beats.filter { $0.sectionId == section.id }
            var dist: [String: Int] = [:]
            for beat in sectionBeats {
                dist[beat.type, default: 0] += 1
            }
            beatDistributionBySection[section.role] = dist
        }
        
        var stanceCounts: [String: Int] = [:]
        for beat in beats {
            let stance = beat.stance.isEmpty ? "neutral" : beat.stance
            stanceCounts[stance, default: 0] += 1
        }
        
        var tempoCounts: [String: Int] = [:]
        for beat in beats {
            let tempo = beat.tempo.isEmpty ? "medium" : beat.tempo
            tempoCounts[tempo, default: 0] += 1
        }
        
        let formalityValues = beats.map { $0.styleFormality }
        let avgFormality = formalityValues.isEmpty ? 5.0 : Double(formalityValues.reduce(0, +)) / Double(formalityValues.count)
        
        let sentenceLengths = beats.map { beat -> Double in
            let words = beat.text.split(separator: " ").count
            let sentences = max(beat.sentenceCount, 1)
            return Double(words) / Double(sentences)
        }
        let avgSentenceLength = sentenceLengths.isEmpty ? 0.0 : sentenceLengths.reduce(0, +) / Double(sentenceLengths.count)
        
        let questionCount = beats.reduce(0) { $0 + $1.questionCount }
        
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
    
    // MARK: - Helper Methods
    private func extractTextFromTranscript(startWordIndex: Int, endWordIndex: Int) -> String {
        guard let transcript = video.transcript else { return "" }
        
        let words = transcript.split(separator: " ", omittingEmptySubsequences: true)
        let startIdx = max(0, startWordIndex)
        let endIdx = min(words.count - 1, endWordIndex)
        
        guard startIdx <= endIdx, startIdx < words.count else {
            return ""
        }
        
        return words[startIdx...endIdx].joined(separator: " ")
    }
    
    private func createMinimalBeatDoc(beat: SimpleBeat, index: Int, section: SectionData, beatData: SimpleBeatData) -> BeatDoc {
        let wordCount = beat.endWordIndex - beat.startWordIndex + 1
        return BeatDoc(
            beatId: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
            beatKey: "\(section.id)_\(section.role.lowercased())_b\(index + 1)",
            sectionId: section.id,
            sectionKey: section.id,
            sourceVideoId: video.videoId,
            sourceChannelId: video.channelId,
            type: beat.type,
            beatRole: "standard",
            // Use beat.text (computed from sentence boundaries) instead of re-extracting by word indexes
            text: beat.text,
            sentenceIndexScope: "transcript",
            sentenceStartIndex: 0,
            sentenceEndIndex: 0,
            startWordIndex: beat.startWordIndex,
            endWordIndex: beat.endWordIndex,
            wordCount: wordCount,
            startCharIndex: 0,
            endCharIndex: 0,
            compilerFunction: "",
            compilerWhyNow: "",
            compilerSetsUp: "",
            compilerEvidenceKind: "none",
            compilerEvidenceText: "",
            moveKey: beat.moveKey,
            mechanicsTags: [],
            retrievalPriority: "medium",
            proofMode: beat.proofMode,
            proofDensity: "none",
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
            sentenceRhythm: "none",
            emotionalDirection: "flat",
            questionPlacement: "none",
            promiseExplicit: false,
            namedEntities: [],
            temporalAnchors: [],
            quantitativeAnchors: [],
            contrastPresent: false,
            contrastType: "none",
            rhetoricalDeviceLabels: [],
            questionRhetorical: 0,
            questionGenuine: 0,
            questionOpen: 0,
            questionSelfAnswer: 0,
            topicPrimary: "",
            topicSecondary: [],
            topicSpecificity: "general_principle",
            topicAbstraction: "none",
            domainSpecificity: "broadly_applicable",
            topicAccessibility: "general_audience",
            subjectCategories: [],
            crossDomainApplicability: [],
            styleFormality: beat.formality,
            styleVocabularyLevel: 5,
            styleHumor: "none",
            pronounUsage: "mixed",
            casualMarkers: [],
            contractions: "moderate",
            humorDensity: "none",
            profanity: false,
            profanityType: "none",
            qualityLevel: "medium",
            anchorStrength: 0,
            reusabilityLevel: "medium",
            qualityReasoning: "",
            reusabilityScore: 5,
            adaptationDifficulty: "moderate",
            crossTopicViability: [],
            usageFrequency: "moderate",
            cooldownRecommendation: 0,
            overuseRisk: "low",
            contextDependency: "lightly_dependent",
            frequencyClass: "common_pattern",
            humanValidatedBy: "",
            humanValidatedAt: "",
            promiseType: "none",
            payoffType: "",
            requiresPayoffWithinBeats: 0,
            promiseStrength: "none",
            voiceMoves: [],
            customVoiceMoves: [],
            customRhetoricalTags: [],
            anchorIds: [],
            containsAnchor: beat.containsAnchor,
            anchorText: beat.anchorText,
            anchorFunction: beat.anchorFunction,
            anchorIsReusable: false,
            anchorFamily: "none",
            setsUpBeatIds: [],
            paysOffBeatIds: [],
            callsBackToBeatIds: [],
            referencesBeatIds: [],
            similarMoveKeys: [],
            semanticConstraints: [],
            mustIntroduce: "",
            requiresContext: [],
            transitionType: "",
            transitionExpectation: "",
            transitionBridgeType: "",
            forwardPromiseBeatId: "",
            forwardPromiseWillDeliver: "",
            forwardPromiseType: "",
            templatePattern: "",
            templateSlots: [],
            templateApplicableTo: [],
            templateRequiresSpecificity: false,
            templateRequiresTimestamp: false,
            templateRequiresNamedEntity: false,
            templateExampleTopic: "",
            templateExampleResult: "",
            templateViability: "none",
            orderIndex: index,
            beatIndexInSection: index + 1,
            sectionRole: section.role,
            globalBeatIndex: 0,
            totalBeatsInSection: beatData.beats.count,
            totalBeatsInScript: 0,
            emotionArcPosition: "",
            emotionTargetFeelings: [],
            emotionAudienceState: "",
            emotionDevice: "",
            emotionValence: 0,
            emotionArousal: 0,
            emotionIntensity: 0,
            emotionTrajectory: "stable",
            musicBrief: "",
            musicInstrumentation: [],
            musicTempoRange: "",
            musicMood: "",
            musicDynamicRange: "",
            argumentPolarity: "neutral",
            argumentResolutionStyle: "",
            argumentMove: "",
            argumentEvidenceStrategy: "",
            logicalFlow: "linear",
            argumentStructure: "claim_evidence",
            hasFactualClaims: false,
            hasNumbers: false,
            hasQuotes: false,
            hasHistoricalReferences: false,
            claimRisk: "low",
            claimKinds: [],
            requiresHedge: false,
            specificityLevel: "",
            rhetoricalDetail_foreshadowing_usage: "",
            rhetoricalDetail_foreshadowing_example: "",
            rhetoricalDetail_specificity_usage: "",
            rhetoricalDetail_specificity_example: "",
            narrativeTechniques: [],
            pronounFrequency: 0,
            directAddress: false,
            toneIndicators: [],
            mechanicsDescription: "",
            topicDescription: "",
            writerHints: [],
            avoidContexts: [],
            performanceRetentionAtBeat: 0.0,
            performanceEngagementLift: "unknown",
            performanceConfidence: 0.0,
            extractedAt: ISO8601DateFormatter().string(from: Date()),
            extractedBy: "A1b_beat_extractor",
            extractorVersion: "2.0",
            parseConfidence: 0.8,
            manualReviewRequired: false,
            reviewNotes: ""
        )
    }
    
    private func convertToBeatDoc(_ response: BeatDocPromptEngine.BeatDocResponse) -> BeatDoc {
        return BeatDoc(
            beatId: response.beatId,
            beatKey: response.beatKey,
            sectionId: response.sectionId,
            sectionKey: response.sectionKey,
            sourceVideoId: response.sourceVideoId,
            sourceChannelId: response.sourceChannelId,
            type: response.type,
            beatRole: response.beatRole,
            text: response.text,
            sentenceIndexScope: response.sentenceIndexScope,
            sentenceStartIndex: response.sentenceStartIndex,
            sentenceEndIndex: response.sentenceEndIndex,
            startWordIndex: response.startWordIndex,
            endWordIndex: response.endWordIndex,
            wordCount: response.wordCount,
            startCharIndex: response.startCharIndex,
            endCharIndex: response.endCharIndex,
            compilerFunction: response.compilerFunction,
            compilerWhyNow: response.compilerWhyNow,
            compilerSetsUp: response.compilerSetsUp,
            compilerEvidenceKind: response.compilerEvidenceKind,
            compilerEvidenceText: response.compilerEvidenceText,
            moveKey: response.moveKey,
            mechanicsTags: response.mechanicsTags,
            retrievalPriority: response.retrievalPriority,
            proofMode: response.proofMode,
            proofDensity: response.proofDensity,
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
            sentenceRhythm: response.sentenceRhythm,
            emotionalDirection: response.emotionalDirection,
            questionPlacement: response.questionPlacement,
            promiseExplicit: response.promiseExplicit,
            namedEntities: response.namedEntities,
            temporalAnchors: response.temporalAnchors,
            quantitativeAnchors: response.quantitativeAnchors,
            contrastPresent: response.contrastPresent,
            contrastType: response.contrastType,
            rhetoricalDeviceLabels: response.rhetoricalDeviceLabels,
            questionRhetorical: response.questionRhetorical,
            questionGenuine: response.questionGenuine,
            questionOpen: response.questionOpen,
            questionSelfAnswer: response.questionSelfAnswer,
            topicPrimary: response.topicPrimary,
            topicSecondary: response.topicSecondary,
            topicSpecificity: response.topicSpecificity,
            topicAbstraction: response.topicAbstraction,
            domainSpecificity: response.domainSpecificity,
            topicAccessibility: response.topicAccessibility,
            subjectCategories: response.subjectCategories,
            crossDomainApplicability: response.crossDomainApplicability,
            styleFormality: response.styleFormality,
            styleVocabularyLevel: response.styleVocabularyLevel,
            styleHumor: response.styleHumor,
            pronounUsage: response.pronounUsage,
            casualMarkers: response.casualMarkers,
            contractions: response.contractions,
            humorDensity: response.humorDensity,
            profanity: response.profanity,
            profanityType: response.profanityType,
            qualityLevel: response.qualityLevel,
            anchorStrength: response.anchorStrength,
            reusabilityLevel: response.reusabilityLevel,
            qualityReasoning: response.qualityReasoning,
            reusabilityScore: response.reusabilityScore,
            adaptationDifficulty: response.adaptationDifficulty,
            crossTopicViability: response.crossTopicViability,
            usageFrequency: response.usageFrequency,
            cooldownRecommendation: response.cooldownRecommendation,
            overuseRisk: response.overuseRisk,
            contextDependency: response.contextDependency,
            frequencyClass: response.frequencyClass,
            humanValidatedBy: response.humanValidatedBy,
            humanValidatedAt: response.humanValidatedAt,
            promiseType: response.promiseType,
            payoffType: response.payoffType,
            requiresPayoffWithinBeats: response.requiresPayoffWithinBeats,
            promiseStrength: response.promiseStrength,
            voiceMoves: response.voiceMoves,
            customVoiceMoves: response.customVoiceMoves,
            customRhetoricalTags: response.customRhetoricalTags,
            anchorIds: response.anchorIds,
            containsAnchor: response.containsAnchor,
            anchorText: response.anchorText,
            anchorFunction: response.anchorFunction,
            anchorIsReusable: response.anchorIsReusable,
            anchorFamily: response.anchorFamily,
            setsUpBeatIds: response.setsUpBeatIds,
            paysOffBeatIds: response.paysOffBeatIds,
            callsBackToBeatIds: response.callsBackToBeatIds,
            referencesBeatIds: response.referencesBeatIds,
            similarMoveKeys: response.similarMoveKeys,
            semanticConstraints: response.semanticConstraints,
            mustIntroduce: response.mustIntroduce,
            requiresContext: response.requiresContext,
            transitionType: response.transitionType,
            transitionExpectation: response.transitionExpectation,
            transitionBridgeType: response.transitionBridgeType,
            forwardPromiseBeatId: response.forwardPromiseBeatId,
            forwardPromiseWillDeliver: response.forwardPromiseWillDeliver,
            forwardPromiseType: response.forwardPromiseType,
            templatePattern: response.templatePattern,
            templateSlots: response.templateSlots,
            templateApplicableTo: response.templateApplicableTo,
            templateRequiresSpecificity: response.templateRequiresSpecificity,
            templateRequiresTimestamp: response.templateRequiresTimestamp,
            templateRequiresNamedEntity: response.templateRequiresNamedEntity,
            templateExampleTopic: response.templateExampleTopic,
            templateExampleResult: response.templateExampleResult,
            templateViability: response.templateViability,
            orderIndex: response.orderIndex,
            beatIndexInSection: response.beatIndexInSection,
            sectionRole: response.sectionRole,
            globalBeatIndex: response.globalBeatIndex,
            totalBeatsInSection: response.totalBeatsInSection,
            totalBeatsInScript: response.totalBeatsInScript,
            emotionArcPosition: response.emotionArcPosition,
            emotionTargetFeelings: response.emotionTargetFeelings,
            emotionAudienceState: response.emotionAudienceState,
            emotionDevice: response.emotionDevice,
            emotionValence: response.emotionValence,
            emotionArousal: response.emotionArousal,
            emotionIntensity: response.emotionIntensity,
            emotionTrajectory: response.emotionTrajectory,
            musicBrief: response.musicBrief,
            musicInstrumentation: response.musicInstrumentation,
            musicTempoRange: response.musicTempoRange,
            musicMood: response.musicMood,
            musicDynamicRange: response.musicDynamicRange,
            argumentPolarity: response.argumentPolarity,
            argumentResolutionStyle: response.argumentResolutionStyle,
            argumentMove: response.argumentMove,
            argumentEvidenceStrategy: response.argumentEvidenceStrategy,
            logicalFlow: response.logicalFlow,
            argumentStructure: response.argumentStructure,
            hasFactualClaims: response.hasFactualClaims,
            hasNumbers: response.hasNumbers,
            hasQuotes: response.hasQuotes,
            hasHistoricalReferences: response.hasHistoricalReferences,
            claimRisk: response.claimRisk,
            claimKinds: response.claimKinds,
            requiresHedge: response.requiresHedge,
            specificityLevel: response.specificityLevel,
            rhetoricalDetail_foreshadowing_usage: response.rhetoricalDetail_foreshadowing_usage,
            rhetoricalDetail_foreshadowing_example: response.rhetoricalDetail_foreshadowing_example,
            rhetoricalDetail_specificity_usage: response.rhetoricalDetail_specificity_usage,
            rhetoricalDetail_specificity_example: response.rhetoricalDetail_specificity_example,
            narrativeTechniques: response.narrativeTechniques,
            pronounFrequency: response.pronounFrequency,
            directAddress: response.directAddress,
            toneIndicators: response.toneIndicators,
            mechanicsDescription: response.mechanicsDescription,
            topicDescription: response.topicDescription,
            writerHints: response.writerHints,
            avoidContexts: response.avoidContexts,
            performanceRetentionAtBeat: response.performanceRetentionAtBeat,
            performanceEngagementLift: response.performanceEngagementLift,
            performanceConfidence: response.performanceConfidence,
            extractedAt: response.extractedAt,
            extractedBy: response.extractedBy,
            extractorVersion: response.extractorVersion,
            parseConfidence: response.parseConfidence,
            manualReviewRequired: response.manualReviewRequired,
            reviewNotes: response.reviewNotes
        )
    }
}
