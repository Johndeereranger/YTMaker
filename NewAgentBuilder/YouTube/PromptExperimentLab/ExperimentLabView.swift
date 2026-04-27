import SwiftUI

struct ExperimentLabView: View {
    let video: YouTubeVideo
    @StateObject private var viewModel: ExperimentLabViewModel

    @State private var selectedTab = 0
    @State private var showConfig = true
    @State private var expandedExperiments: Set<UUID> = []
    @State private var editingLabelId: UUID?
    @State private var editLabelText = ""

    // Copy button states
    @State private var isSummaryCopied = false
    @State private var isComparisonCopied = false
    @State private var isSummaryPromptsCopied = false
    @State private var copiedRunDetailId: UUID?

    init(video: YouTubeVideo) {
        self.video = video
        _viewModel = StateObject(wrappedValue: ExperimentLabViewModel(video: video))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                tabBar
                tabContent
                footer
            }

            if viewModel.isRunning {
                progressOverlay
            }
        }
        .navigationTitle("Prompt Experiment Lab")
        .onAppear {
            viewModel.loadExperiments()
        }
        .alert("Edit Label", isPresented: Binding(
            get: { editingLabelId != nil },
            set: { if !$0 { editingLabelId = nil } }
        )) {
            TextField("Label", text: $editLabelText)
            Button("Save") {
                if let id = editingLabelId {
                    viewModel.updateLabel(experimentId: id, label: editLabelText)
                }
                editingLabelId = nil
            }
            Button("Cancel", role: .cancel) { editingLabelId = nil }
        } message: {
            Text("Enter a label for this experiment")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Text("\(viewModel.experiments.count) experiment\(viewModel.experiments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(viewModel.sentences.count) sentences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Config Panel

    private var configPanel: some View {
        DisclosureGroup("Run Configuration", isExpanded: $showConfig) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Window Size").font(.caption2).foregroundColor(.secondary)
                        Stepper("\(viewModel.windowSize)", value: $viewModel.windowSize, in: 3...10)
                            .font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step Size").font(.caption2).foregroundColor(.secondary)
                        Stepper("\(viewModel.stepSize)", value: $viewModel.stepSize, in: 1...5)
                            .font(.caption)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature: \(String(format: "%.1f", viewModel.temperature))").font(.caption2).foregroundColor(.secondary)
                        Slider(value: $viewModel.temperature, in: 0...1, step: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sister Runs").font(.caption2).foregroundColor(.secondary)
                        Stepper("\(viewModel.sisterRunCount)", value: $viewModel.sisterRunCount, in: 1...5)
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt Variant").font(.caption2).foregroundColor(.secondary)
                    Picker("Variant", selection: $viewModel.selectedPromptVariant) {
                        Text("Legacy").tag(SectionSplitterPromptVariant.legacy)
                        Text("Classification").tag(SectionSplitterPromptVariant.classification)
                        Text("Classification V2").tag(SectionSplitterPromptVariant.classificationV2)
                        Text("Classification Original").tag(SectionSplitterPromptVariant.classificationOriginal)
                    }
                    .pickerStyle(.segmented)
                    .font(.caption2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual Label (optional)").font(.caption2).foregroundColor(.secondary)
                    TextField("e.g. v3 tighter TURN definition", text: $viewModel.manualLabel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                Button {
                    Task { await viewModel.runExperiment() }
                } label: {
                    Label("Run Experiment", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning || viewModel.sentences.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tabButton("Experiments", tag: 0, icon: "list.bullet.rectangle.fill")
                tabButton("Compare", tag: 1, icon: "rectangle.split.3x3.fill",
                          badge: viewModel.selectedRunIds.count)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ label: String, tag: Int, icon: String, badge: Int = 0) -> some View {
        Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 4) {
                Label(label, systemImage: icon)
                    .font(.caption)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selectedTab == tag ? Color.accentColor : Color.gray.opacity(0.15))
            .foregroundColor(selectedTab == tag ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            ScrollView {
                LazyVStack(spacing: 8) {
                    configPanel
                    experimentList
                }
            }
        case 1:
            if viewModel.selectedRuns.count >= 2 {
                ExperimentComparisonView(
                    selectedRuns: viewModel.selectedRuns,
                    sentences: viewModel.sentences,
                    experiments: viewModel.experiments
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.split.3x3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select 2+ runs to compare")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Check runs in the Experiments tab, then switch here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Experiment List

    private var experimentList: some View {
        ForEach(viewModel.experiments) { experiment in
            experimentCard(experiment)
        }
        .padding(.horizontal)
    }

    private func experimentCard(_ experiment: PromptExperiment) -> some View {
        let isExpanded = expandedExperiments.contains(experiment.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedExperiments.remove(experiment.id)
                    } else {
                        expandedExperiments.insert(experiment.id)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(experiment.displayLabel)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            configBadge(experiment.configSummary)
                            Text("\(experiment.sisterRuns.count) sister\(experiment.sisterRuns.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDate(experiment.createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Boundary summary (always visible)
            boundaryQuickSummary(experiment)

            // Selectable run checkboxes
            selectableRunGrid(experiment)

            // Expanded detail
            if isExpanded {
                expandedExperimentDetail(experiment)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func configBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
    }

    private func boundaryQuickSummary(_ experiment: PromptExperiment) -> some View {
        let digCounts = experiment.sisterRuns.map { $0.withDigressions.finalGapIndices.count }
        let cleanCounts = experiment.sisterRuns.compactMap { $0.withoutDigressions?.finalGapIndices.count }
        let digStr = digCounts.map { "\($0)" }.joined(separator: ",")
        let cleanStr = cleanCounts.map { "\($0)" }.joined(separator: ",")

        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("+Dig: \(digStr)")
                    .font(.caption2.monospaced())
            }
            if !cleanStr.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("-Dig: \(cleanStr)")
                        .font(.caption2.monospaced())
                }
            }
        }
    }

    private func selectableRunGrid(_ experiment: PromptExperiment) -> some View {
        let runs = viewModel.allSelectableRuns.filter { $0.experimentId == experiment.id }
        let selectedCount = runs.filter { viewModel.isRunSelected($0) }.count

        // Group: show Final runs prominently, Pass1 as secondary
        let finalRuns = runs.filter { $0.passType == .final }
        let pass1Runs = runs.filter { $0.passType == .pass1 }

        return VStack(alignment: .leading, spacing: 4) {
            // Select All / Clear All for this experiment
            HStack(spacing: 8) {
                Button {
                    for run in runs {
                        if !viewModel.selectedRunIds.contains(run.id) {
                            viewModel.selectedRunIds.insert(run.id)
                        }
                    }
                } label: {
                    Text("Select All")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.accentColor)
                .disabled(selectedCount == runs.count)

                Button {
                    for run in runs {
                        viewModel.selectedRunIds.remove(run.id)
                    }
                } label: {
                    Text("Clear")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(selectedCount == 0)

                Spacer()

                if selectedCount > 0 {
                    Text("\(selectedCount)/\(runs.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Final runs
            FlowLayout(spacing: 4) {
                ForEach(finalRuns) { run in
                    runCheckbox(run)
                }
            }
            // Pass1 runs (smaller, secondary)
            if !pass1Runs.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(pass1Runs) { run in
                        runCheckbox(run, secondary: true)
                    }
                }
            }
        }
    }

    private func runCheckbox(_ run: SelectableRun, secondary: Bool = false) -> some View {
        let isSelected = viewModel.isRunSelected(run)

        return Button {
            viewModel.toggleRunSelection(run)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(secondary ? .caption2 : .caption)
                    .foregroundColor(isSelected ? run.color : .secondary)
                Text(run.label)
                    .font(secondary ? .system(size: 9) : .caption2)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? run.color.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? run.color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func expandedExperimentDetail(_ experiment: PromptExperiment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Per-sister-run details
            ForEach(experiment.sisterRuns) { sister in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sister Run \(sister.runNumber)")
                        .font(.caption.bold())

                    sisterRunDetail(sister)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    editLabelText = experiment.manualLabel ?? ""
                    editingLabelId = experiment.id
                } label: {
                    Label("Edit Label", systemImage: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                copyButton(
                    label: "Run Detail",
                    icon: "doc.on.doc",
                    isCopied: Binding(
                        get: { copiedRunDetailId == experiment.id },
                        set: { if !$0 { copiedRunDetailId = nil } }
                    )
                ) {
                    let text = viewModel.copyRunDetail(experiment: experiment)
                    ExperimentCopyService.copyToClipboard(text)
                    copiedRunDetailId = experiment.id
                }

                Spacer()

                Button(role: .destructive) {
                    viewModel.deleteExperiment(experiment)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private func sisterRunDetail(_ sister: ExperimentSisterRun) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let dig = sister.withDigressions
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 5, height: 5)
                Text("+Dig: \(dig.finalGapIndices.count) boundaries")
                    .font(.caption2)
                Text("(P1: \(dig.pass1GapIndices.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.1f", dig.runDuration))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let clean = sister.withoutDigressions {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("-Dig: \(clean.finalGapIndices.count) boundaries")
                        .font(.caption2)
                    Text("(P1: \(clean.pass1GapIndices.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", clean.runDuration))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Show final gap indices
            let gaps = dig.finalGapIndices.sorted().map { "\($0)" }.joined(separator: ", ")
            Text("Gaps: [\(gaps)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.leading, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            copyButton(label: "All Summary", icon: "doc.plaintext", isCopied: $isSummaryCopied) {
                let text = viewModel.copyAllSummary()
                ExperimentCopyService.copyToClipboard(text)
            }

            copyButton(label: "Summary+Prompts", icon: "doc.text", isCopied: $isSummaryPromptsCopied) {
                let text = viewModel.copySummaryWithPrompts()
                ExperimentCopyService.copyToClipboard(text)
            }

            if viewModel.selectedRuns.count >= 2 {
                copyButton(label: "Comparison", icon: "rectangle.split.3x3", isCopied: $isComparisonCopied) {
                    let text = viewModel.copyComparison()
                    ExperimentCopyService.copyToClipboard(text)
                }
            }

            Spacer()

            if !viewModel.selectedRunIds.isEmpty {
                Button {
                    viewModel.clearSelection()
                } label: {
                    Text("Clear (\(viewModel.selectedRunIds.count))")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Copy Button

    private func copyButton(
        label: String,
        icon: String,
        isCopied: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied.wrappedValue = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied.wrappedValue = false
                }
            }
        } label: {
            Label(
                isCopied.wrappedValue ? "Copied" : label,
                systemImage: isCopied.wrappedValue ? "checkmark" : icon
            )
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isCopied.wrappedValue ? .green : nil)
    }

    // MARK: - Progress Overlay

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                    .tint(.white)

                Text("Running Experiment")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(viewModel.progressMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                ProgressView(value: viewModel.progressValue)
                    .tint(.green)
                    .frame(width: 200)

                Text("\(Int(viewModel.progressValue * 100))%")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm"
        return fmt.string(from: date)
    }
}

// Uses FlowLayout from VideoRhetoricalSequenceView.swift
