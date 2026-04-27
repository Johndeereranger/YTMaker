//
//  AppNavigation.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//


import SwiftUI
import Combine

// MARK: - Navigation Destinations for AI Agent App
enum AppNavigation: Hashable, Equatable {
    //case agentList
    case newAgent
    case agentDetail
    case editPromptStep(PromptStep?)
    case agentRunner(Agent,ChatSession)
    case chatSessionList(Agent)
    case promptRunList(Agent,PromptStep)
    case imageUpload
    case deerImageUpload
    case harvestAnalysis
    case weatherData
    case historicalWeatherData
    case weatherHarvestData
    case monthTempHarvestView
    case scriptList
    case scriptDetail(Script)
    case imageViewer
    case textToSpeech
    case fortyBookAutoRun
    case genericAutoRun
    case fileDrop
    case mermaidViewer
    case soapAgentRunner
    case promptViewer
    case fortyBookManualRun
    case bloodTracking
    case exportButtonView
    case youtubeImporter
    case youtubeChannelList
    case youtubeVideoList(String, String) // channelId, channelName
    case youtubeVideoDetail(YouTubeVideo)
    case youtubeSearch
    case youtubeChannelVideos(String) // channelId
    case youtubeInsiteAdder
    case minimalTest1
    case minimalTest2
    case minimalTest3
    case minimalTest4
    case minimalTest5
    case researchTopic
    //Script Writing
    case scriptHome
    case scriptEditor(YTScript)
    case pointEditor(YTScript, Point)
    case fullScriptView(YTScript)
    case scriptSettings
    //New Script Editor
    case newScriptEditor(YTSCRIPT)
    case newScriptHome
    case newSectionEditor(YTSCRIPT, UUID)
    case patternViewer
    //Video Ingestion
    // Phase 1 - Creator Analysis
     case creatorStudyList
     case creatorDetail(YouTubeChannel)
     case videoAnalysisDetail(YouTubeVideo)
     case manualIngestion(YouTubeVideo)
     case alignmentViewer(YouTubeVideo)
     case promptFidelityDebugger
    // Pre-A0 / Taxonomy Building
     case preA0Browse(YouTubeChannel)
     case taxonomyBatchRunner(YouTubeChannel)
     case templateDashboard(YouTubeChannel)
     case a1aPromptBuilder(YouTubeChannel)
     case a1aPromptWorkbench(YouTubeChannel, LockedTemplate)
     case sentenceFidelityTest(YouTubeVideo, YouTubeChannel)
     case boundaryDetection(YouTubeVideo, SentenceFidelityTest)
     case sectionSplitterFidelity(YouTubeVideo)
     case rhetoricalTwinFinder(String, String)  // channelId, templateId
    case transitionAudit
    case creatorRhetoricalStyle(YouTubeChannel)
    case sequenceBookends(YouTubeChannel)
    case videoRhetoricalSequence(YouTubeVideo)
    case creatorChunkBrowser(YouTubeChannel, [YouTubeVideo])

    // Digression Detection
    case digressionDetection(YouTubeVideo)
    case digressionFidelity(YouTubeVideo)
    case batchDigressionDashboard(YouTubeChannel)
    case digressionDeepDive(AggregatedDigression)
    case digressionChunkComparison(YouTubeChannel)

    // Slot Fidelity Tester
    case slotFidelityTester(YouTubeVideo, YouTubeChannel)

    // Batch Slot Fidelity
    case batchSlotFidelity(YouTubeChannel)
    case batchSlotVideoDetail(String)  // videoId

    // Confusable Pairs
    case confusablePairs(YouTubeChannel)

    // Narrative Spine
    case narrativeSpineFidelityTester(YouTubeVideo, YouTubeChannel)
    case creatorNarrativeProfile(YouTubeChannel)

    // Spine-Rhetorical Alignment
    case spineAlignmentFidelityTester(YouTubeVideo, YouTubeChannel)
    case spineAlignmentMappingTable(YouTubeChannel)
    case spineAlignmentConfusablePairs(YouTubeChannel)

    // Creator Fingerprint
    case creatorFingerprint(YouTubeChannel)

    // Section Questions
    case sectionQuestions(YouTubeChannel)

    // Ground Truth
    case groundTruth(YouTubeVideo)

    // Prompt Experiment Lab
    case promptExperimentLab(YouTubeVideo)

    // Semantic Script Writer
    case semanticScriptWriter

    // Shape Script Writer (new approach)
    case shapeScriptWriter

    // Gist Script Writer (rambling → gists → match against Johnny's corpus)
    case gistScriptWriter

    // Markov Script Writer (chain building with Markov transition probabilities)
    case markovScriptWriter

    // Arc Script Writer (production pipeline: spine → gaps → expand → synthesize → edit)
    case arcScriptWriter

    case exifViewer
    case kmlViewer
    
    // Deer Herd Analysis
    case deerHerdHome
    case propertyList
    case propertyDetail(Property)
    case propertyCreate
    case importPhotos(Property)
    case importKML(Property, [Photo]) // property + already imported photos
    case matchReview(Property, FlightSession) // review auto-matching results
    case mapView(Property)
    case buckProfileList(Property)
    case buckProfileDetail(BuckProfile)
    case buckProfileCreate(Property)
    case deerReport(Property)
    case deerSettings
    
    case newImportWizard
    
    case kmlImport
    case pinMapView(sessionId: String)
    case allPinsMapView
    
    case propertyPhotoImportFlow(Property)
    case scriptBreakdownFullscreen(YouTubeVideo)

    // Video Editor (Raw Video Processing Pipeline)
    case videoEditorHome
    case videoEditorProject(VideoProject)
    case videoEditorGapReview(VideoProject)
    case videoEditorDuplicateReview(VideoProject)
    case videoEditorMoveEditor(VideoProject)  // Stage 2: Apply moves to simplified timeline

    // Preset Library (Phase 2 - FCPXML Edit Presets)
    case presetLibrary
    case moveLibrary

//    case editPromptStep(agentId: UUID, step: PromptStep)
}

// MARK: - Navigation ViewModel
class NavigationViewModel: ObservableObject {
    
    @Published var currentAgentViewModel: AgentDetailViewModel?
    @Published var currentAgent: Agent?
    
    @Published var path = NavigationPath() {
        didSet {
            print("🔹 Navigation Path Updated: \(path)")
        }
    }

    /// Push a new destination onto the navigation stack
    func push(_ destination: AppNavigation) {
        print("🚀 Navigating to: \(destination)")
        path.append(destination)
    }
    
    func pushAgent(_ agent: Agent) {
        currentAgent = agent
        path.append(AppNavigation.agentDetail)
    }
    
    func pushStep(_ step: PromptStep?) {
        guard let currentAgent else { return }
        currentAgentViewModel = .init(agent: currentAgent)
        path.append(AppNavigation.editPromptStep(step))
    }

    /// Pop the last destination from the navigation stack
    func pop() {
        if !path.isEmpty {
            print("⬅️ Popping last view from navigation stack")
            path.removeLast()
        } else {
            print("⚠️ Attempted to pop but navigation stack is empty!")
        }
    }

    /// Reset the navigation path to the root
    func reset() {
        print("🔄 Resetting navigation stack")
        path = NavigationPath()
    }
}
