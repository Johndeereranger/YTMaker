//
//  AgentListView.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//

import SwiftUI
import Combine
// MARK: - AgentListView
// A clean, split-out version of the agent list
import SwiftUI
import Combine

struct AgentListView: View {
  //  @ObservedObject var viewModel: AgentViewModel
    @StateObject private var viewModel = AgentViewModel.instance
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showEditSheet = false
    @State private var editingAgent: Agent? = nil

    // Clear rhetorical sequences state
    @State private var isClearingSequences = false
    @State private var clearedSequencesCount: Int? = nil

    var body: some View {
        List {
            //minTest
            videoEditorSection
            youtubeScriptWriting
            youtubeSection
            creatorAnalysisSection
            testSection
            ForEach(viewModel.agents) { agent in
                AgentRowView(agent: agent) {
                    nav.pushAgent(agent)
                } onRun: {
                    let sessionIndex = agent.chatSessions.count + 1
                       let session = ChatSession(
                           id: UUID(),
                           agentId: agent.id,
                           title: "Session \(sessionIndex)",
                           createdAt: Date()
                       )
                        print("agent \(agent.id) has \(agent.chatSessions.count) sessions. Adding new session \(sessionIndex)...")
                    Task {
                            do {
                                var updatedAgent = agent
                                updatedAgent.chatSessions.append(session)

                                try await AgentManager().updateChatSessions(
                                    agentId: updatedAgent.id,
                                    chatSessions: updatedAgent.chatSessions
                                )
                                print("Updated Agent with new session has \(updatedAgent.chatSessions.count) sessions...")
                                // ✅ Reload from Firestore to get the latest version with new session
                                let reloaded = try await AgentManager().fetchAgent(with: agent.id)

                                // ✅ Push with fresh instance
                                // ✅ Replace stale agent in viewModel
                                if let updated = reloaded {
                                    if let index = viewModel.agents.firstIndex(where: { $0.id == updated.id }) {
                                        viewModel.agents[index] = updated
                                    }
                                    nav.push(.agentRunner(updated, session))
                                }

                            } catch {
                                print("❌ Failed to save session to Firestore: \(error.localizedDescription)")
                            }
                        }
                } onHistory: {
                    nav.push(.chatSessionList(agent))
                }
                    onDelete: {
                    viewModel.deleteAgent(agent)
                }
            }
            scriptWritingSection
            deerHerdSection
            exifViewerSection
            bookWritingSection

        }
        .navigationTitle("Agents")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    editingAgent = nil
                    showEditSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
            #elseif os(macOS)
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    editingAgent = nil
                    showEditSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
            #endif
        }
        .sheet(isPresented: $showEditSheet) {
            AgentEditSheet(agent: editingAgent) { name, desc in
                if let agent = editingAgent {
                    viewModel.updateAgent(agent, name: name, description: desc)
                } else {
                    viewModel.addAgent(name: name, description: desc)
                }
                showEditSheet = false
            }
        }
    }
    
    // MARK: - Video Editor Section

    private var videoEditorSection: some View {
        Section(header: Text("Video Editor")) {
            Button {
                nav.push(.videoEditorHome)
            } label: {
                HStack {
                    Image(systemName: "film.stack")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading) {
                        Text("Video Editor")
                        Text("Import, transcribe, remove pauses, export FCPXML")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }

            Button {
                nav.push(.presetLibrary)
            } label: {
                HStack {
                    Image(systemName: "tray.2.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Preset Library")
                        Text("Import FCPXML, extract reusable edit presets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var youtubeScriptWriting: some View {
        Section(header: Text("YouTube Script Writer")) {
            Button {
                nav.push(.scriptHome)
            } label: {
                Label("YouTube Scripts", systemImage: "doc.text")
            }
            Button {
                nav.push(.newScriptHome)
            } label: {
                Label("New YouTube Scripts", systemImage: "doc.text")
            }
            
            Button {
                nav.push(.patternViewer)
            } label: {
                Label("Pattern Viewer", systemImage: "book.closed")
            }

            Button {
                nav.push(.semanticScriptWriter)
            } label: {
                Label("Semantic Script Writer", systemImage: "sparkles.rectangle.stack")
            }

            Button {
                nav.push(.shapeScriptWriter)
            } label: {
                Label("Shape Script Writer (New)", systemImage: "rectangle.3.group")
            }

            Button {
                nav.push(.gistScriptWriter)
            } label: {
                Label("Gist Script Writer", systemImage: "text.quote")
            }

            Button {
                nav.push(.markovScriptWriter)
            } label: {
                Label("Markov Script Writer", systemImage: "chart.dots.scatter")
            }

            Button {
                nav.push(.arcScriptWriter)
            } label: {
                Label("Arc Script Writer", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
    }


    private var bookWritingSection: some View {
        Section(header: Text("FortyBook")) {
            
            Button {
                nav.push(.fortyBookAutoRun)
            } label: {
                Label("Book Auto Writer", systemImage: "book")
            }
            Button {
                nav.push(.soapAgentRunner)
            } label: {
                Label("SOAP Notes Processor", systemImage: "stethoscope")
            }
            Button {
                nav.push(.genericAutoRun)
            } label: {
                Label("Generic Auto Run", systemImage: "gearshape.2")
            }
            
            Button {
                nav.push(.fortyBookManualRun)
            } label: {
                Label("40 Book Auto Run", systemImage: "Book")
            }
            
            
        }
    }
    private var minTest: some View {
        Section(header: Text("Minimal Tests")) {
            Button {
                nav.push(.minimalTest1)
            } label: {
                Label("Test 1: Basic View", systemImage: "1.circle")
            }
            
            Button {
                nav.push(.minimalTest2)
            } label: {
                Label("Test 2: With ViewModel", systemImage: "2.circle")
            }
            
            Button {
                nav.push(.minimalTest3)
            } label: {
                Label("Test 3: With Async Task", systemImage: "3.circle")
            }
            
            Button {
                nav.push(.minimalTest4)
            } label: {
                Label("Test 4: VideoSearchViewModel", systemImage: "4.circle")
            }
            
            Button {
                nav.push(.minimalTest5)
            } label: {
                Label("Test 5: Firebase Call", systemImage: "5.circle")
            }
        }
    }
    
    private var youtubeSection: some View {
        Section(header: Text("YouTube Database")) {
            Button(action: {
                nav.push(.youtubeImporter)
            }) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.red)
                    Text("Import Channel or Video")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            
            Button(action: {
                nav.push(.youtubeChannelList)
            }) {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.red)
                    Text("View Channels")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            Button(action: {
                nav.push(.youtubeSearch)
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.red)
                    Text("Search Videos")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            
            Button(action: {
                nav.push(.researchTopic)
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.red)
                    Text("Topic List")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            Button(action: {
                nav.push(.youtubeInsiteAdder)
            }) {
                HStack {
                    Image(systemName: "plus")
                        .foregroundColor(.red)
                    Text("Add Youtube Insight")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            
        }
    }
    private var exifViewerSection: some View {
        Section(header: Text("EXIF / LRF Tools")) {
            Button {
                nav.push(.exifViewer)
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                    Text("DJI LRF Target Viewer")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            
            Button {
                nav.push(.kmlViewer)
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                    Text("KML Viewer")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
        }
    }
    private var testSection: some View {
        Section(header: Text("Test Section")) {
            
            Button {
                nav.push(.bloodTracking)
            } label: {
                Label("Blood Tracking", systemImage: "book")
            }
            
            Button {
                nav.push(.deerImageUpload)
            } label: {
                Label("📷 Deer Upload Images", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                nav.push(.harvestAnalysis)
            } label: {
                Label("Harvest Analysis", systemImage: "photo.on.rectangle.angled")
            }
   
            Button {
                nav.push(.weatherData)
            } label: {
                Label("Weather Data Viewer", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                nav.push(.historicalWeatherData)
            } label: {
                Label("Historical Data Viewer", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                nav.push(.weatherHarvestData)
            } label: {
                Label("Weather & Harvest Data Viewer", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                nav.push(.monthTempHarvestView)
            } label: {
                Label("Month Temp Harvest View", systemImage: "photo.on.rectangle.angled")
            }
            
            
            Button {
                nav.push(.exportButtonView)
            } label: {
                Label("Export Button View", systemImage: "photo.on.rectangle.angled")
            }
            
            
            
        }
    }
    // MARK: - Updated AgentListView Section
    // Add this to your existing AgentListView

    private var deerHerdSection: some View {
        Section(header: Text("Deer Herd Analysis")) {
            Button {
                nav.push(.deerHerdHome)
            } label: {
                HStack {
                    Image(systemName: "binoculars.fill")
                        .foregroundColor(.green)
                    Text("Deer Herd Analysis")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var scriptWritingSection: some View {
        Section(header: Text("Script Writing")) {
            Button {
                Task {
                           do {
                               try await ImagePromptManager.instance.printAllTags()
                               // nav.push(.promptViewer)
                           } catch {
                               print("❌ Failed to print tags: \(error)")
                           }
                       }
            } label: {
                Label("View Prompts", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                Task {
                     let prompts = try? await ImagePromptManager.instance.fetchAllPrompts()
                    if let safePrompts = prompts {
                        for prompt in safePrompts {
                            print(prompt.prompt)
                        }
                    }
                    
                }
                
            } label: {
                Label("List All Prompts", systemImage: "text.justify.left")
            }

            Button {
                nav.push(.imageUpload)
            } label: {
                Label("📷 Upload Images", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                nav.push(.scriptList)
            } label: {
                Label("📝 Manage Scripts", systemImage: "text.justify.left")
            }
            
            Button {
                nav.push(.imageViewer)
            } label: {
                Label("📷 Image Viewer", systemImage: "photo.on.rectangle.angled")
            }
            Button {
                nav.push(.textToSpeech)
            } label: {
                Label("Text to Speech", systemImage: "photo.on.rectangle.angled")
            }
            Button {
                nav.push(.fileDrop)
            }label: {
                Label("File Drop", systemImage: "tray.and.arrow.down")
            }
            Button {
                nav.push(.mermaidViewer)
            }label: {
                Label("Mermaid Viewer", systemImage: "tray.and.arrow.down")
            }
            
            ScenarioTestView()
//            Button {
//                Task {
//                    do {
//                        let imageURL = try await ScenarioAPIManager.instance.generateImage(
//                            prompt: "A stick figure climbing a mountain at sunrise"
//                        )
//                        print("✅ Image URL: \(imageURL)")
//                    } catch {
//                        print("❌ Failed to generate image: \(error)")
//                    }
//                }
//            } label: {
//                Label("Test Image", systemImage: "text.justify.left")
//            }
        }
    }
}

// MARK: - AgentRowView
//struct AgentRowView: View {
//    let agent: Agent
//    let onTap: () -> Void
//    let onEdit: () -> Void
//    let onDelete: () -> Void
//
//    var body: some View {
//        VStack(alignment: .leading) {
//            Text(agent.name)
//                .font(.headline)
//            if let description = agent.description {
//                Text(description)
//                    .font(.subheadline)
//                    .foregroundColor(.gray)
//            }
//        }
//        .padding(.vertical, 4)
//        .onTapGesture { onTap() }
//        .contextMenu {
//            Button("Edit", action: onEdit)
//            Button("Delete", role: .destructive, action: onDelete)
//        }
//    }
//}
struct AgentRowView: View {
    let agent: Agent
    let onDetail: () -> Void
    let onRun: () -> Void
    let onHistory: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text(agent.name)
                        .font(.headline)
                    if let description = agent.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                HStack(spacing: 16) {
                    Button(action: onDetail) {
                        Image(systemName: "info.circle")
                    }
                    Button(action: onRun) {
                        Image(systemName: "play.circle.fill")
                    }
                    Button(action: onHistory) {
                        Image(systemName: "book.closed")
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }

 
    }
}

extension AgentListView {
    var creatorAnalysisSection: some View {
        Section(header: Text("Creator Analysis (Phase 1)")) {
            Button {
                nav.push(.creatorStudyList)
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    Text("Study Creators")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }

            Button {
                nav.push(.transitionAudit)
            } label: {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.orange)
                    Text("Transition Audit")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }

            // Clear all rhetorical sequences button
            Button {
                clearAllRhetoricalSequences()
            } label: {
                HStack {
                    if isClearingSequences {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    Text("Clear All Rhetorical Sequences")
                        .foregroundColor(.red)
                    Spacer()
                    if let count = clearedSequencesCount {
                        Text("\(count) cleared")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .disabled(isClearingSequences)
        }
    }

    private func clearAllRhetoricalSequences() {
        isClearingSequences = true
        clearedSequencesCount = nil

        Task {
            do {
                let count = try await YouTubeFirebaseService.shared.clearAllRhetoricalSequences()
                await MainActor.run {
                    clearedSequencesCount = count
                    isClearingSequences = false
                }
            } catch {
                await MainActor.run {
                    print("Failed to clear sequences: \(error)")
                    isClearingSequences = false
                }
            }
        }
    }
}


// MARK: - AgentEditSheet
struct AgentEditSheet: View {
    let agent: Agent?
    let onSave: (String, String?) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    
    @State private var editorText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(agent == nil ? "Add Agent" : "Edit Agent")
                .font(.title2)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)
            
    

            HStack {
                Spacer()
                Button("Save") {
                    onSave(name, description.isEmpty ? nil : description)
                }
                .disabled(name.isEmpty)
                Spacer()
            }
        }
        .padding()
        .onAppear {
            name = agent?.name ?? ""
            description = agent?.description ?? ""
        }
    }
}
// MARK: - IdentifiableError
/// A simple wrapper for error messages to use with `.alert(item:)`
struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}
