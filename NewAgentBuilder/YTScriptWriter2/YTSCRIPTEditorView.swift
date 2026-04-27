//
//  YTSCRIPTEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/8/25.
//
import SwiftUI

struct YTSCRIPTEditorView: View {
    @Bindable var script: YTSCRIPT
    @State private var selectedStep: YTSCRIPTStep = .mission
    @State private var saveTask: Task<Void, Never>?
    @State private var showMenu: Bool = false  // For iPhone menu
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad - Split View (always visible sidebar)
                iPadLayout
            } else {
                // iPhone - Slide-out menu
                iPhoneLayout
            }
        }
        .onChange(of: script.objective) { _, _ in autoSave() }
        .onChange(of: script.targetEmotion) { _, _ in autoSave() }
        .onChange(of: script.audienceNotes) { _, _ in autoSave() }
        .onChange(of: script.brainDumpRaw) { _, _ in autoSave() }
        .onChange(of: script.points) { _, _ in autoSave() }
        .onChange(of: script.researchPoints) { _, _ in autoSave() }
        .onChange(of: script.generatedAngles) { _, _ in autoSave() }
        .onChange(of: script.selectedAngleId) { _, _ in autoSave() }
        .onChange(of: script.manualAngle) { _, _ in autoSave() }
        .onChange(of: script.outlineSections) { _, _ in autoSave() }
        .onChange(of: script.selectedChannelId) { _, _ in autoSave() }
        .onChange(of: script.selectedStyleProfileId) { _, _ in autoSave() }
    }
    
    // MARK: - iPad Layout (Split View)
    private var iPadLayout: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle(script.title)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            contentView(for: selectedStep)
        }
    }
    
    // MARK: - iPhone Layout (Slide-out menu)
    private var iPhoneLayout: some View {
        ZStack {
            // Main content
            contentView(for: selectedStep)
            
            // Slide-out menu overlay
            if showMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showMenu = false
                        }
                    }
                
                HStack(spacing: 0) {
                    // Menu
                    sidebarContent
                        .frame(width: 280)
                        .background(Color(.systemBackground))
                        .transition(.move(edge: .leading))
                    
                    Spacer()
                }
            }
        }
        .navigationTitle(selectedStep.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation {
                        showMenu.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.large)
                }
            }
        }
    }
    
    // MARK: - Shared Sidebar Content
    private var sidebarContent: some View {
        List {
            ForEach(YTSCRIPTStep.allCases) { step in
                Button {
                    selectedStep = step
                    if horizontalSizeClass == .compact {
                        withAnimation {
                            showMenu = false  // Close menu on iPhone after selection
                        }
                    }
                } label: {
                    Label(step.rawValue, systemImage: step.icon)
                        .foregroundColor(selectedStep == step ? .accentColor : .primary)
                }
                .listRowBackground(selectedStep == step ? Color.accentColor.opacity(0.1) : Color.clear)
            }
        }
    }
    
    // MARK: - Shared Content View
    @ViewBuilder
    private func contentView(for step: YTSCRIPTStep) -> some View {
        switch step {
        case .pitchDeck:  // ← ADD THIS CASE
             YTSCRIPTPitchDeckView(script: script)
        case .mission:
            YTSCRIPTMissionView(script: script)
        case .brainDump:
            YTSCRIPTBrainDumpView(script: script)
        case .pointsResearch:
            YTSCRIPTPointsResearchView(script: script)
        case .outline:
            YTSCRIPTOutlineView(script: script)
        case .package:
            placeholderView(for: "Package")
        case .finalScript:
            FinalScriptView(script: script)
        case .polish:
            placeholderView(for: "Polish")
        case .angle:
            YTSCRIPTModePickerView(script: script)
        case .guidelines:
                YTSCRIPTGuidelinesView(script: script)
        }
    }
    
    private func placeholderView(for step: String) -> some View {
        VStack {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("\(step) - Coming Soon")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private func autoSave() {
        saveTask?.cancel()
        
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            
            script.lastModified = Date()
            
            do {
                try await YTSCRIPTManager.shared.updateScript(script)
            } catch {
                print("❌ Auto-save failed: \(error)")
            }
        }
    }
}
