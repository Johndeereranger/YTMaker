//
//  AgentHomeView.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//
import SwiftUI

import SwiftUI

struct AgentHomeView: View {
    @StateObject private var nav = NavigationViewModel()
    //@State var agentViewModel: AgentViewModel = .init()//agentManager: AgentManager())
    @StateObject private var agentViewModel = AgentViewModel.instance
    @StateObject private var videoSearchViewModel = VideoSearchViewModel.instance
  
    
    @StateObject private var importViewModel = ImportViewModel.instance

    var body: some View {
        NavigationStack(path: $nav.path) {
            //AgentListView(viewModel: agentViewModel)
            AgentListView()
                .navigationTitle("AI Agent Hub")
                .navigationDestination(for: AppNavigation.self) { destination in
                    switch destination {
              
                    case .newAgent:
                        Text("🆕 New Agent View Placeholder")
                    case .agentDetail:
                        if let agent = nav.currentAgent {
                            AgentDetailView(agent: agent){ updatedAgent in
                                if let index = agentViewModel.agents.firstIndex(where: { $0.id == updatedAgent.id }) {
                                    agentViewModel.agents[index] = updatedAgent
                                }
                            }
                        }
                      case .editPromptStep(let existingStep):
                        if let viewModel = nav.currentAgentViewModel {
                            PromptStepEditorView(step: existingStep)
                                .environment(\.agentDetailViewModel, viewModel)
                        }
                    case .agentRunner(let agent, let session):
                        AgentRunnerView(agent: agent, session: session)
//                    default:
//                        Text("🚧 Not Implemented")
                    case .chatSessionList(let agent):
                        ChatSessionListView(agentId: agent.id)
                    case .promptRunList(let agent, let promptStep):
                        PromptRunInspectorView(agent: agent, stepId: promptStep.id)

                    case .scriptList:
                        ScriptListView()
                    case .scriptDetail(let script):
                        ScriptDetailView(script: script)
                    case .imageViewer:
                        ImagePromptViewer()
                    case .textToSpeech:
                        TextToSpeechTestView()
                    case .fortyBookAutoRun:
                        FortyBookAutoRunView()
                    case .genericAutoRun:
                        GenericAutoRunView()
                    case .fileDrop:
                        FileDropView()
                    case .mermaidViewer:
                        MermaidChartScreen()
                    case .soapAgentRunner:
                        SpecificAgentView()
                    case .promptViewer:
                        PromptViewer()
                    case .fortyBookManualRun:
                        FortyBookManualRunView()
                    case .researchTopic:
                        
                        ResearchTopicsListView()
                        
                    case .bloodTracking:
                        BloodTrackingCameraView()
                    case .youtubeImporter:
                        YouTubeImporterView()
                    case .youtubeChannelList:
                        YouTubeChannelListView()
                    case .youtubeChannelVideos(let channelId):
                        VideoSearchView(channelId: channelId)
                    case .minimalTest1:
                        MinimalTest1()
                    case .minimalTest2:
                        MinimalTest2()
                    case .minimalTest3:
                        MinimalTest3()
                    case .minimalTest4:
                        MinimalTest4()
                    case .minimalTest5:
                        MinimalTest5()
                    case .youtubeVideoList(let channelId, let channelName):
                        YouTubeVideoListView(channelId: channelId, channelName: channelName)
                    case .youtubeSearch:
                        VideoSearchView()
                    case .youtubeInsiteAdder:
                            AddYouTubeInsightView()
                    case .youtubeVideoDetail(let video):
                        YouTubeVideoDetailView(video: video)
                    case .imageUpload:
                        ImageUploadView()
                    case .deerImageUpload:
                        DeerImageUploadView()
                    case .monthTempHarvestView:
                        MonthTempHarvestView()
                        //TempDropHarvestAnalysis()
                    case .exportButtonView:
                        
                        ExportButtonView(viewModel: HarvestAnalysisViewModel())
                        
                    case .weatherHarvestData:
                        WeatherHarvestCorrelationView()
                    case .historicalWeatherData:
                        HistoricalWeatherViewer()
                    case .weatherData:
                        WeatherDataViewer()
                    case .harvestAnalysis:
                        HarvestAnalysisView()
                        
                        //Youtube Script Writing
                    case .scriptHome:
                        ScriptHomeView()
                    case .scriptEditor(let script):
                        ScriptEditorView(script: script)
                    case .pointEditor(let script, let point):
                        PointEditorView(script: script, point: point)
                    case .fullScriptView(let script):
                        FullScriptView(script: script)
                    case .scriptSettings:
                        ScriptSettingsView()
                        
                        //YouTube Video Ingestion
                    case .creatorStudyList:
                        CreatorStudyListView()

                    case .creatorDetail(let channel):
                        CreatorDetailView(channel: channel)

                    case .videoAnalysisDetail(let video):
                        AlignmentViewer(video: video)

                    case .manualIngestion(let video):
                        ManualIngestionView(video: video)

                    case .alignmentViewer(let video):
                        AlignmentViewer(video: video)

                    case .promptFidelityDebugger:
                        PromptFidelityDebugger()

                    case .preA0Browse(let channel):
                        PreA0BrowseView(channel: channel)

                    case .taxonomyBatchRunner(let channel):
                        TaxonomyBatchRunnerView(channel: channel)

                    case .templateDashboard(let channel):
                        TemplateDashboardView(channel: channel)

                    case .a1aPromptBuilder(let channel):
                        A1aPromptBuilderView(channel: channel)

                    case .a1aPromptWorkbench(let channel, let template):
                        A1aPromptWorkbenchView(channel: channel, template: template)

                    case .sentenceFidelityTest(let video, let channel):
                        SentenceFidelityTestView(video: video, channel: channel)

                    case .boundaryDetection(let video, let fidelityTest):
                        BoundaryDetectionView(video: video, fidelityTest: fidelityTest)

                    case .sectionSplitterFidelity(let video):
                        SectionSplitterFidelityView(video: video)

                    case .rhetoricalTwinFinder(let channelId, let templateId):
                        RhetoricalTwinFinderView(channelId: channelId, templateId: templateId)

                    case .transitionAudit:
                        TransitionAuditView()

                    case .creatorRhetoricalStyle(let channel):
                        CreatorRhetoricalStyleView(channelId: channel.channelId, channelName: channel.name)

                    case .sequenceBookends(let channel):
                        SequenceBookendsView(channel: channel)

                    case .videoRhetoricalSequence(let video):
                        VideoRhetoricalSequenceView(video: video)

                    case .creatorChunkBrowser(let channel, let videos):
                        CreatorChunkBrowserView(channel: channel, videos: videos)

                    // Digression Detection
                    case .digressionDetection(let video):
                        DigressionDetectionView(video: video)

                    case .digressionFidelity(let video):
                        DigressionFidelityView(video: video)

                    case .batchDigressionDashboard(let channel):
                        BatchDigressionDashboardView(channel: channel)

                    case .digressionDeepDive(let digression):
                        DigressionDeepDiveView(digression: digression)

                    case .digressionChunkComparison(let channel):
                        DigressionChunkComparisonView(channel: channel)

                    case .slotFidelityTester(let video, let channel):
                        SlotFidelityTesterView(video: video, channel: channel)

                    case .narrativeSpineFidelityTester(let video, let channel):
                        NarrativeSpineFidelityTesterView(video: video, channel: channel)

                    case .creatorNarrativeProfile(let channel):
                        CreatorNarrativeProfileView(channel: channel)

                    case .spineAlignmentFidelityTester(let video, let channel):
                        SpineAlignmentFidelityTesterView(video: video, channel: channel)

                    case .spineAlignmentMappingTable(let channel):
                        SpineAlignmentMappingTableView(channel: channel)

                    case .spineAlignmentConfusablePairs(let channel):
                        SpineAlignmentConfusablePairsView(channel: channel)

                    case .batchSlotFidelity(let channel):
                        BatchSlotFidelityView(channel: channel)

                    case .batchSlotVideoDetail(let videoId):
                        BatchVideoDetailView(videoId: videoId)

                    case .confusablePairs(let channel):
                        ConfusablePairView(channel: channel)

                    case .creatorFingerprint(let channel):
                        CreatorFingerprintView(channel: channel)

                    case .sectionQuestions(let channel):
                        SectionQuestionsView(channel: channel)

                    case .groundTruth(let video):
                        GroundTruthView(video: video)

                    case .promptExperimentLab(let video):
                        ExperimentLabView(video: video)

                    case .semanticScriptWriter:
                        SemanticScriptWriterView()

                    case .shapeScriptWriter:
                        ShapeScriptWriterView()

                    case .gistScriptWriter:
                        GistScriptWriterView()

                    case .markovScriptWriter:
                        MarkovScriptWriterView()

                    case .arcScriptWriter:
                        ArcScriptWriterView()

                        //New SCript Writer
                    case .newScriptEditor(let script):
                        YTSCRIPTEditorView(script: script)
                    case .newScriptHome:
                        YTSCRIPTHomeView()
                        
                    case .patternViewer:
                        PatternViewerView()
                    case .newSectionEditor(let script, let sectionId):  // ← ADD THIS
                        if let section = script.outlineSections.first(where: { $0.id == sectionId }) {
                            YTSCRIPTSectionEditorView(script: script, section: section)
                        }
                        
                        
                        
                        //Heard Analysis
                    case .exifViewer:
                        EXIFViewer()
                        
                    case .kmlViewer:
                        KMLViewer()
                        
                        
                        // MARK: - Updated AgentHomeView.swift navigation destination handling
                        // Add these cases to your existing switch statement in navigationDestination
                    case .newImportWizard:
                        NewImportWizardView()
                        case .deerHerdHome:
                            DeerHerdHomeView()

                        case .propertyList:
                            PropertyListView()

                        case .propertyDetail(let property):
                            PropertyDetailView(property: property)

                        case .propertyCreate:
                            Text("Property Create - Not directly navigated")

                        case .importPhotos(let property):
                            ImportFlowView(property: property)

                        case .importKML(let property, let photos):
                            Text("Import KML - Part of import flow")

                        case .matchReview(let property, let session):
                            Text("Match Review - Part of import flow")

                        case .mapView(let property):
                            DeerMapView(property: property)

                        case .buckProfileList(let property):
                            BuckProfileListView(property: property)

                        case .buckProfileDetail(let profile):
                            BuckProfileDetailView(profile: profile)

                        case .buckProfileCreate(let property):
                            Text("Buck Profile Create - Sheet based")

                        case .deerReport(let property):
                            DeerReportView(property: property)

                        case .deerSettings:
                            DeerSettingsView()
                        
                        case .kmlImport:
                            KMLImportFlowView()
                    case .pinMapView(let sessionId):
                        //TestPinMapView(sessionId: sessionId)
                        DeerMapView(sessionId: sessionId)
                    case .allPinsMapView:
                        DeerMapView()
                    case .scriptBreakdownFullscreen(let video):
                        ScriptBreakdownFullscreenView(video: video)
                    case .propertyPhotoImportFlow(let property):
                        PropertyPhotoImportFlowView(property: property)

                    // Video Editor
                    case .videoEditorHome:
                        VideoEditorHomeView()

                    case .videoEditorProject(let project):
                        VideoEditorProjectView(project: project)

                    case .videoEditorGapReview(let project):
                        GapReviewView(project: project)

                    case .videoEditorDuplicateReview(let project):
                        DuplicateReviewView(project: project)

                    case .videoEditorMoveEditor(let project):
                        MoveEditorView(project: project)

                    // Preset Library
                    case .presetLibrary:
                        PresetLibraryHomeView()

                    case .moveLibrary:
                        MoveLibraryView()
                    }


                }
        }
        #if os(macOS)
        // Disable swipe-back navigation gesture on macOS
        .gesture(
            DragGesture()
                .onChanged { _ in }
                .onEnded { _ in },
            including: .all
        )
        #endif
        .environmentObject(nav)
        .environmentObject(importViewModel)
        .environmentObject(videoSearchViewModel)
    }
}
