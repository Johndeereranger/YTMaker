//
//  ArcPipelineView.swift
//  NewAgentBuilder
//
//  Three-phase pipeline for Narrative Arc workflow:
//  Phase 1: Spine Generation (P1-P5)
//  Phase 2: Gap Detection (G1-G6)
//  Phase 3: Respond to Gaps (rambling editor)
//

import SwiftUI

// MARK: - Pipeline Phase Enum

enum ArcPipelinePhase: Int, CaseIterable, Identifiable {
    case spineGeneration = 0
    case gapDetection = 1
    case respond = 2
    case pass2 = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .spineGeneration: return "Spine Generation"
        case .gapDetection:    return "Gap Detection"
        case .respond:         return "Respond"
        case .pass2:           return "Pass 2"
        }
    }

    var icon: String {
        switch self {
        case .spineGeneration: return "1.circle.fill"
        case .gapDetection:    return "2.circle.fill"
        case .respond:         return "3.circle.fill"
        case .pass2:           return "4.circle.fill"
        }
    }
}

// MARK: - ArcPipelineView

struct ArcPipelineView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: ArcComparisonViewModel
    @StateObject private var gapVM: GapAnalysisViewModel
    @StateObject private var pass2VM: ArcComparisonViewModel

    @State private var selectedPhase: ArcPipelinePhase = .spineGeneration
    @State private var showingHistorySheet = false

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
        _vm = StateObject(wrappedValue: ArcComparisonViewModel(coordinator: coordinator))
        _gapVM = StateObject(wrappedValue: GapAnalysisViewModel(coordinator: coordinator))
        _pass2VM = StateObject(wrappedValue: ArcComparisonViewModel(coordinator: coordinator, isPass2: true))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Persistent top bar (always visible)
            topBar

            Divider()

            // Phase content (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let msg = vm.prerequisiteMessage {
                        prerequisiteWarning(msg)
                    } else {
                        switch selectedPhase {
                        case .spineGeneration:
                            ArcSpinePhaseView(vm: vm, selectedPhase: $selectedPhase)
                        case .gapDetection:
                            ArcGapPhaseView(gapVM: gapVM, selectedPhase: $selectedPhase)
                        case .respond:
                            ArcResponsePhaseView(gapVM: gapVM, selectedPhase: $selectedPhase)
                        case .pass2:
                            ArcPass2PhaseView(vm: pass2VM, selectedPhase: $selectedPhase)
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            // Load all histories immediately (local file I/O, no dependencies needed)
            vm.loadRunHistory()
            gapVM.loadGapHistory()
            pass2VM.loadRunHistory()
            print("[ArcPipeline] .task — histories: arc=\(vm.runHistory.count), gap=\(gapVM.gapRunHistory.count), pass2=\(pass2VM.runHistory.count)")

            // Wire gapVM + pass2VM if dependencies already loaded (e.g. navigating back)
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

            // Auto-load most recent arc run if none loaded
            if vm.currentRun == nil, let mostRecent = vm.runHistory.first {
                vm.loadSavedRun(mostRecent)
            }

            // Wire arc results to gap VM AFTER loading arc run
            if vm.currentRun != nil {
                gapVM.updateAvailableResults(from: vm.currentRun)
            }

            // Auto-load most recent gap run if none loaded
            if gapVM.currentGapRun == nil, let mostRecentGap = gapVM.gapRunHistory.first {
                gapVM.loadSavedRun(mostRecentGap)
            }

            // Wire gap findings to pass 2 after gap run is loaded
            wireGapFindings()

            // Auto-load most recent pass 2 run if none loaded
            if pass2VM.currentRun == nil, let mostRecentP2 = pass2VM.runHistory.first {
                pass2VM.loadSavedRun(mostRecentP2)
            }

            print("[ArcPipeline] Auto-loaded: arcRun=\(vm.currentRun != nil), gapRun=\(gapVM.currentGapRun != nil), pass2Run=\(pass2VM.currentRun != nil)")
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
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { showing in if !showing { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showingHistorySheet) {
            ArcRunHistorySheet(vm: vm, gapVM: gapVM, pass2VM: pass2VM)
        }
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

    /// Extract best gap findings from the gap VM's current run and pass them to the Pass 2 VM.
    /// Also wires the first-pass spine (from the arc result that gap detection analyzed) for V6–V10 enrichment.
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

        // Wire ALL findings from ALL paths (for Q→A matching in enrichment)
        let allFindings = gapRun.pathResults
            .filter { $0.status == .completed }
            .flatMap(\.findings)
            .filter { $0.refinementStatus != .resolved }
        pass2VM.allGapFindings = allFindings

        // Prefer G6 synthesis findings for gap-aware rules; fall back to all
        let g6 = gapRun.pathResults.first { $0.path == .g6_synthesis && $0.status == .completed }
        if let g6, !g6.findings.isEmpty {
            pass2VM.gapFindings = g6.findings
        } else {
            pass2VM.gapFindings = allFindings
        }
        print("[ArcPipeline] Wired \(pass2VM.gapFindings.count) gap findings (G6), \(pass2VM.allGapFindings.count) all findings, firstPassSpine=\(pass2VM.firstPassSpine != nil) to Pass 2 VM")
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            // Run selector row
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
                    // Re-scan disk first (catches runs saved in previous sessions or after initial .task)
                    vm.loadRunHistory()
                    gapVM.loadGapHistory()
                    pass2VM.loadRunHistory()
                    print("[ArcPipeline] Load Recent tapped — arcHistory: \(vm.runHistory.count), gapHistory: \(gapVM.gapRunHistory.count), pass2History: \(pass2VM.runHistory.count)")

                    if let mostRecent = vm.runHistory.first {
                        vm.loadSavedRun(mostRecent)
                    }
                    // Wire arc results → gap VM immediately after loading
                    gapVM.updateAvailableResults(from: vm.currentRun)
                    if let mostRecentGap = gapVM.gapRunHistory.first {
                        gapVM.loadSavedRun(mostRecentGap)
                    }
                    if let mostRecentP2 = pass2VM.runHistory.first {
                        pass2VM.loadSavedRun(mostRecentP2)
                    }
                    print("[ArcPipeline] Load Recent done — arcRun=\(vm.currentRun != nil), gapRun=\(gapVM.currentGapRun != nil), pass2Run=\(pass2VM.currentRun != nil)")
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

            // Phase picker (segmented control)
            Picker("Phase", selection: $selectedPhase) {
                ForEach(ArcPipelinePhase.allCases) { phase in
                    Label(phase.title, systemImage: phase.icon)
                        .tag(phase)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
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
}
