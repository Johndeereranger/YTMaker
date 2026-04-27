//
//  YTSCRIPTPitchDeckView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//


import SwiftUI

struct YTSCRIPTPitchDeckView: View {
    @Bindable var script: YTSCRIPT
    @StateObject private var topicManager = ResearchTopicManager.shared
    
    @State private var topic: ResearchTopic?
    @State private var isLoading = true
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading topic...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else if let error = errorMessage {
                    errorView(error)
                } else if script.sourceTopicId == nil {
                    noTopicLinkedView
                } else if var editableTopic = topic {
                    topicContent(topic: Binding(
                        get: { editableTopic },
                        set: { newValue in
                            editableTopic = newValue
                            self.topic = newValue
                            hasUnsavedChanges = true
                        }
                    ))
                } else {
                    topicNotFoundView
                }
            }
            .padding(24)
        }
        .navigationTitle("Pitch Deck")
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { saveChanges() }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task {
            await loadTopic()
        }
    }
    
    // MARK: - Topic Content
    @ViewBuilder
    private func topicContent(topic: Binding<ResearchTopic>) -> some View {
        // Planning & Organization
        planningSection(topic: topic)
        
        Divider()
        
        // Content Details
        contentSection(topic: topic)
        
        Divider()
        
        // Creative Elements
        creativeSection(topic: topic)
        
        Divider()
        
        // Research Notes
        notesSection(topic: topic)
    }
    
    // MARK: - Planning Section
    private func planningSection(topic: Binding<ResearchTopic>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Planning & Organization")
                .font(.headline)
            
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Topic title", text: topic.title)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Target Month
            VStack(alignment: .leading, spacing: 4) {
                Text("Target Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Target Month", selection: topic.targetPublishedMonth) {
                    ForEach(TopicMonth.allMonths, id: \.self) { month in
                        Text(month).tag(month)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Category
            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Category", selection: topic.category) {
                    ForEach(TopicCategory.defaultCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Status
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Status", selection: topic.status) {
                    ForEach(TopicStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Is Remake Toggle
            Toggle("Is Remake/Repurpose", isOn: topic.isRemake)
        }
    }
    
    // MARK: - Content Section
    private func contentSection(topic: Binding<ResearchTopic>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Details")
                .font(.headline)
            
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { topic.wrappedValue.description ?? "" },
                    set: { topic.wrappedValue.description = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // How helps brain
            VStack(alignment: .leading, spacing: 4) {
                Text("How does this help someone get inside the brain of a deer?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { topic.wrappedValue.howHelpsBrain ?? "" },
                    set: { topic.wrappedValue.howHelpsBrain = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Creative Section
    private func creativeSection(topic: Binding<ResearchTopic>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Creative Elements")
                .font(.headline)
            
            // Key Visuals
            VStack(alignment: .leading, spacing: 4) {
                Text("Key Visuals")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { topic.wrappedValue.keyVisuals ?? "" },
                    set: { topic.wrappedValue.keyVisuals = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Title Ideas
            VStack(alignment: .leading, spacing: 4) {
                Text("Title Ideas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { topic.wrappedValue.titleIdeas ?? "" },
                    set: { topic.wrappedValue.titleIdeas = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Thumbnail Ideas
            VStack(alignment: .leading, spacing: 4) {
                Text("Thumbnail Ideas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { topic.wrappedValue.thumbnailIdeas ?? "" },
                    set: { topic.wrappedValue.thumbnailIdeas = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Notes Section
    private func notesSection(topic: Binding<ResearchTopic>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research Notes")
                .font(.headline)
            
            TextEditor(text: Binding(
                get: { topic.wrappedValue.topicNotes ?? "" },
                set: { topic.wrappedValue.topicNotes = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 150)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Empty States
    private var noTopicLinkedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Topic Linked")
                .font(.title2)
            Text("This script was created without a research topic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private var topicNotFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Topic Not Found")
                .font(.title2)
            Text("The linked research topic could not be found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text("Error Loading Topic")
                .font(.title2)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadTopic() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Load Topic
    private func loadTopic() async {
        guard let topicId = script.sourceTopicId else {
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            topic = try await topicManager.fetchTopic(id: topicId)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Save Changes
    private func saveChanges() {
        guard let topic = topic else { return }
        
        isSaving = true
        
        Task {
            do {
                try await topicManager.updateTopic(topic)
                hasUnsavedChanges = false
            } catch {
                print("❌ Error saving topic: \(error)")
            }
            isSaving = false
        }
    }
}