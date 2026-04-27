//
//  ArcScriptWriterView.swift
//  NewAgentBuilder
//
//  Production script writing pipeline.
//  Promotes the Arc pipeline phases to top-level tabs alongside
//  Synthesis and Prose Editor, with placeholders for Expand and Allocate.
//
//  Shares session data with MarkovScriptWriter via the same
//  persisted MarkovSessionStorage file.
//

import SwiftUI

// MARK: - Tab Enum

enum ArcScriptTab: Int, CaseIterable, Identifiable {
    case input = 0
    case spine = 1
    case gaps = 2
    case respond = 3
    case pass2 = 4
    case expand = 5
    case allocate = 6
    case synthesis = 7
    case editor = 8

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .input:     return "Input"
        case .spine:     return "Spine"
        case .gaps:      return "Gaps"
        case .respond:   return "Respond"
        case .pass2:     return "Pass 2"
        case .expand:    return "Expand"
        case .allocate:  return "Allocate"
        case .synthesis: return "Synthesis"
        case .editor:    return "Editor"
        }
    }

    /// Map tab to ArcPipelinePhase for the phase views' "Next"/"Back" bindings.
    var arcPhase: ArcPipelinePhase? {
        switch self {
        case .spine:   return .spineGeneration
        case .gaps:    return .gapDetection
        case .respond: return .respond
        case .pass2:   return .pass2
        default:       return nil
        }
    }

    /// Reverse lookup: ArcPipelinePhase → ArcScriptTab
    static func from(arcPhase: ArcPipelinePhase) -> ArcScriptTab? {
        switch arcPhase {
        case .spineGeneration: return .spine
        case .gapDetection:    return .gaps
        case .respond:         return .respond
        case .pass2:           return .pass2
        }
    }
}

// MARK: - ArcScriptWriterView

struct ArcScriptWriterView: View {
    @StateObject private var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: ArcComparisonViewModel
    @StateObject private var gapVM: GapAnalysisViewModel
    @StateObject private var pass2VM: ArcComparisonViewModel

    @State private var selectedTab = 0
    @State private var showingHistorySheet = false

    init() {
        let coord = MarkovScriptWriterCoordinator()
        _coordinator = StateObject(wrappedValue: coord)
        _vm = StateObject(wrappedValue: ArcComparisonViewModel(coordinator: coord))
        _gapVM = StateObject(wrappedValue: GapAnalysisViewModel(coordinator: coord))
        _pass2VM = StateObject(wrappedValue: ArcComparisonViewModel(coordinator: coord, isPass2: true))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar (run info + history)
            topBar

            Divider()

            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ArcScriptTab.allCases) { tab in
                        Button {
                            withAnimation { selectedTab = tab.rawValue }
                        } label: {
                            Text(tab.title)
                                .font(.caption)
                                .fontWeight(selectedTab == tab.rawValue ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTab == tab.rawValue ? Color.accentColor : Color.secondary.opacity(0.15))
                                .foregroundColor(selectedTab == tab.rawValue ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    ArcInputView(coordinator: coordinator)
                case 1:
                    phaseScrollWrapper {
                        if let msg = vm.prerequisiteMessage {
                            prerequisiteWarning(msg)
                        } else {
                            ArcSpinePhaseView(vm: vm, selectedPhase: arcPhaseBinding)
                        }
                    }
                case 2:
                    phaseScrollWrapper {
                        if let msg = vm.prerequisiteMessage {
                            prerequisiteWarning(msg)
                        } else {
                            ArcGapPhaseView(gapVM: gapVM, selectedPhase: arcPhaseBinding)
                        }
                    }
                case 3:
                    phaseScrollWrapper {
                        if let msg = vm.prerequisiteMessage {
                            prerequisiteWarning(msg)
                        } else {
                            ArcResponsePhaseView(gapVM: gapVM, selectedPhase: arcPhaseBinding)
                        }
                    }
                case 4:
                    phaseScrollWrapper {
                        if let msg = vm.prerequisiteMessage {
                            prerequisiteWarning(msg)
                        } else {
                            ArcPass2PhaseView(vm: pass2VM, selectedPhase: arcPhaseBinding)
                        }
                    }
                case 5:
                    phaseScrollWrapper {
                        placeholderView("Section Expansion", description: "Expand each spine beat using creator corpus patterns. Compare rambling depth against what the creator typically does in each section type.", phase: "Step 2")
                    }
                case 6:
                    phaseScrollWrapper {
                        placeholderView("Content Allocation", description: "Hard-gate rambling chunks to specific sections. Each chunk is assigned to exactly one section — no content bleed.", phase: "Step 3")
                    }
                case 7:
                    SynthesisView(coordinator: coordinator)
                case 8:
                    ProseEditorView(coordinator: coordinator)
                default:
                    ArcInputView(coordinator: coordinator)
                }
            }
        }
        .navigationTitle("Arc Script Writer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("Refresh from Gist Writer") {
                        coordinator.refreshFromGistWriter()
                    }
                    Button("Clear Session", role: .destructive) {
                        coordinator.clearSession()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if coordinator.isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: .constant(coordinator.errorMessage != nil)) {
            Button("OK") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
        .task {
            // Load channels and chain run
            await coordinator.loadAvailableChannels()
            await coordinator.loadLatestChainRunIfNeeded()

            // Load all histories immediately (local file I/O)
            vm.loadRunHistory()
            gapVM.loadGapHistory()
            pass2VM.loadRunHistory()
            print("[ArcScriptWriter] .task — histories: arc=\(vm.runHistory.count), gap=\(gapVM.gapRunHistory.count), pass2=\(pass2VM.runHistory.count)")

            // Wire gapVM + pass2VM if dependencies already loaded
            if vm.dependenciesLoaded {
                wireGapDependencies()
                wirePass2Dependencies()
            }

            // Load dependencies if needed
            if !vm.dependenciesLoaded && !vm.isLoadingDependencies {
                await vm.loadDependencies()
                if vm.dependenciesLoaded {
                    wireGapDependencies()
                    wirePass2Dependencies()
                }
            }

            // Auto-load most recent arc run
            if vm.currentRun == nil, let mostRecent = vm.runHistory.first {
                vm.loadSavedRun(mostRecent)
            }

            // Wire arc results to gap VM
            if vm.currentRun != nil {
                gapVM.updateAvailableResults(from: vm.currentRun)
            }

            // Auto-load most recent gap run
            if gapVM.currentGapRun == nil, let mostRecentGap = gapVM.gapRunHistory.first {
                gapVM.loadSavedRun(mostRecentGap)
            }

            // Wire gap findings to pass 2
            wireGapFindings()

            // Auto-load most recent pass 2 run
            if pass2VM.currentRun == nil, let mostRecentP2 = pass2VM.runHistory.first {
                pass2VM.loadSavedRun(mostRecentP2)
            }

            print("[ArcScriptWriter] Auto-loaded: arcRun=\(vm.currentRun != nil), gapRun=\(gapVM.currentGapRun != nil), pass2Run=\(pass2VM.currentRun != nil)")
        }
        .onChange(of: vm.dependenciesLoaded) { loaded in
            if loaded {
                wireGapDependencies()
                wirePass2Dependencies()
            }
        }
        .onChange(of: vm.currentRun?.id) { _ in
            gapVM.updateAvailableResults(from: vm.currentRun)
        }
        .onChange(of: gapVM.currentGapRun?.id) { _ in
            wireGapFindings()
        }
        .sheet(isPresented: $showingHistorySheet) {
            ArcRunHistorySheet(vm: vm, gapVM: gapVM, pass2VM: pass2VM)
        }
    }

    // MARK: - Phase Binding Adapter

    /// Translates between ArcPipelinePhase (used by phase views) and the tab index.
    private var arcPhaseBinding: Binding<ArcPipelinePhase> {
        Binding(
            get: {
                ArcScriptTab(rawValue: selectedTab)?.arcPhase ?? .spineGeneration
            },
            set: { phase in
                if let tab = ArcScriptTab.from(arcPhase: phase) {
                    withAnimation { selectedTab = tab.rawValue }
                }
            }
        )
    }

    // MARK: - Dependency Wiring

    private func wireGapDependencies() {
        gapVM.creatorProfile = vm.creatorProfile
        gapVM.representativeSpines = vm.representativeSpines
        gapVM.transitionMatrix = vm.spineTransitionMatrix
    }

    private func wirePass2Dependencies() {
        pass2VM.creatorProfile = vm.creatorProfile
        pass2VM.representativeSpines = vm.representativeSpines
        pass2VM.spineTransitionMatrix = vm.spineTransitionMatrix
        pass2VM.allThroughlines = vm.allThroughlines
        pass2VM.spineCount = vm.spineCount
        pass2VM.dependenciesLoaded = vm.dependenciesLoaded
        wireGapFindings()
    }

    private func wireGapFindings() {
        // Wire first-pass spine from the arc result that gap detection used
        if let arcResult = gapVM.selectedArcResult {
            pass2VM.firstPassSpine = arcResult.outputSpine
        }

        guard let gapRun = gapVM.currentGapRun else {
            pass2VM.gapFindings = []
            pass2VM.allGapFindings = []
            return
        }

        // Wire ALL findings from ALL paths (for Q->A matching in enrichment)
        let allFindings = gapRun.pathResults
            .filter { $0.status == .completed }
            .flatMap(\.findings)
            .filter { $0.refinementStatus != .resolved }
        pass2VM.allGapFindings = allFindings

        // Prefer G6 synthesis findings; fall back to all
        let g6 = gapRun.pathResults.first { $0.path == .g6_synthesis && $0.status == .completed }
        if let g6, !g6.findings.isEmpty {
            pass2VM.gapFindings = g6.findings
        } else {
            pass2VM.gapFindings = allFindings
        }
        print("[ArcScriptWriter] Wired \(pass2VM.gapFindings.count) gap findings (G6), \(pass2VM.allGapFindings.count) all findings, firstPassSpine=\(pass2VM.firstPassSpine != nil) to Pass 2 VM")
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if let run = vm.currentRun {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(run.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                Text(run.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(run.modelUsed)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())

                FlowLayout(spacing: 4) {
                    ForEach(run.pathResults.filter { $0.status == .completed }, id: \.id) { result in
                        Text(result.path.rawValue)
                            .font(.caption2.monospaced().weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            } else {
                Text("No run loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.loadRunHistory()
                gapVM.loadGapHistory()
                pass2VM.loadRunHistory()

                if let mostRecent = vm.runHistory.first {
                    vm.loadSavedRun(mostRecent)
                }
                gapVM.updateAvailableResults(from: vm.currentRun)
                if let mostRecentGap = gapVM.gapRunHistory.first {
                    gapVM.loadSavedRun(mostRecentGap)
                }
                if let mostRecentP2 = pass2VM.runHistory.first {
                    pass2VM.loadSavedRun(mostRecentP2)
                }
            } label: {
                Label("Load Recent", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingHistorySheet = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    // MARK: - Phase Scroll Wrapper

    /// Wraps phase content in a ScrollView + VStack + padding to match how
    /// ArcPipelineView originally hosted these views. Phase views are bare
    /// VStacks — they don't have their own ScrollView.
    private func phaseScrollWrapper<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
    }

    // MARK: - Placeholder

    private func placeholderView(_ title: String, description: String, phase: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text(phase)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Prerequisite Warning

    private func prerequisiteWarning(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(coordinator.loadingMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}
