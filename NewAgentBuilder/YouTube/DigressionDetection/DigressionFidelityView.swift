import SwiftUI

// MARK: - View Model

@MainActor
class DigressionFidelityViewModel: ObservableObject {
    let video: YouTubeVideo

    // Config
    @Published var detectionMode: DetectionMode = .llmFirst
    @Published var temperature: Double = 0.3
    @Published var runCount: Int = 3
    @Published var enableLLMEscalation = false
    @Published var enabledTypes: Set<DigressionType> = Set(DigressionType.allCases)

    // Progress
    @Published var isRunning = false
    @Published var currentRun = 0
    @Published var currentPhase = ""

    // Results
    @Published var runs: [DigressionFidelityRunResult] = []
    @Published var sentences: [SentenceTelemetry] = []
    @Published var errorMessage: String?

    init(video: YouTubeVideo) {
        self.video = video
    }

    // MARK: Computed

    var crossRunComparison: [CrossRunDigressionComparison] {
        guard !runs.isEmpty, !sentences.isEmpty else { return [] }
        let storage = DigressionFidelityStorage(videoId: video.videoId, runs: runs)
        return storage.buildCrossRunComparison(sentences: sentences)
    }

    var unanimousDigressions: [CrossRunDigressionComparison] {
        crossRunComparison.filter { $0.isUnanimous }
    }

    var divergentDigressions: [CrossRunDigressionComparison] {
        crossRunComparison.filter { $0.isDivergent }
    }

    var typeConsistency: [DigressionType: Double] {
        let storage = DigressionFidelityStorage(videoId: video.videoId, runs: runs)
        return storage.typeConsistency()
    }

    // MARK: Validation (recalculated from stored data)

    func validationsForRun(_ run: DigressionFidelityRunResult) -> [ValidatedDigression] {
        DigressionRulesValidator.shared.validate(
            digressions: run.digressions,
            sentences: sentences
        )
    }

    // MARK: Load

    func loadSentences() async {
        do {
            let tests = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            guard let latest = tests.first else {
                errorMessage = "No sentence fidelity test found. Run a fidelity test first."
                return
            }
            sentences = latest.sentences
        } catch {
            errorMessage = "Failed to load sentences: \(error.localizedDescription)"
        }
    }

    var hasSavedResults: Bool {
        DigressionFidelityStorage.load(videoId: video.videoId) != nil
    }

    func loadFromDefaults() {
        guard let storage = DigressionFidelityStorage.load(videoId: video.videoId) else {
            return
        }
        runs = storage.runs
        errorMessage = nil
    }

    // MARK: Run

    func runFidelityTest() async {
        guard !sentences.isEmpty else {
            errorMessage = "No sentences loaded"
            return
        }

        isRunning = true
        errorMessage = nil
        runs = []

        let config = DigressionDetectionConfig(
            enableLLMEscalation: enableLLMEscalation,
            temperature: temperature,
            maxConcurrentLLMCalls: 5,
            enabledTypes: enabledTypes,
            minConfidenceThreshold: 0.0,
            boundaryBoostEnabled: true,
            boundaryBoostAmount: 0.2,
            detectionMode: detectionMode
        )

        for i in 1...runCount {
            currentRun = i
            currentPhase = "Run \(i) of \(runCount)..."

            let result = await DigressionDetectionService.shared.detectDigressions(
                videoId: video.videoId,
                from: sentences,
                config: config
            ) { [weak self] step, total, phase in
                Task { @MainActor in
                    self?.currentPhase = "Run \(i): \(phase)"
                }
            }

            let runResult = DigressionFidelityRunResult(
                runNumber: i,
                temperature: temperature,
                enabledLLMEscalation: enableLLMEscalation,
                digressions: result.digressions,
                cleanSentenceIndices: result.cleanSentenceIndices,
                totalSentences: result.totalSentences,
                detectionMode: detectionMode
            )

            runs.append(runResult)
        }

        // Save
        var storage = DigressionFidelityStorage(videoId: video.videoId, runs: runs)
        storage.save()

        isRunning = false
        currentPhase = "Complete"
    }

    // MARK: Copy Text — Summary

    var summaryText: String {
        guard !runs.isEmpty else { return "No runs completed" }

        var lines: [String] = []
        lines.append("════════════════════════════════════════════════════════════════")
        lines.append("DIGRESSION FIDELITY REPORT")
        lines.append("════════════════════════════════════════════════════════════════")
        lines.append("Video: \(video.title)")
        lines.append("Mode: \(detectionMode.displayName)")
        lines.append("Config: temp=\(String(format: "%.2f", temperature)), runs=\(runs.count), LLM=\(enableLLMEscalation || detectionMode == .llmFirst ? "ON" : "OFF")")
        lines.append("")

        // WHAT: Cross-run fidelity
        let comparison = crossRunComparison
        let unanimousCount = comparison.filter { $0.isUnanimous }.count
        let divergentCount = comparison.filter { $0.isDivergent }.count
        let unanimousCleanCount = comparison.filter { $0.isUnanimouslyClean }.count

        lines.append("WHAT — Fidelity Results:")
        lines.append("  Unanimous Digression: \(unanimousCount) sentences")
        lines.append("  Unanimous Clean: \(unanimousCleanCount) sentences")
        lines.append("  Divergent: \(divergentCount) sentences")
        lines.append("")

        // WHAT: Per-run breakdown
        lines.append("WHAT — Per-Run Breakdown:")
        for run in runs {
            let typeCounts = Dictionary(grouping: run.digressions, by: { $0.type })
                .mapValues { $0.count }
                .sorted { $0.key.displayName < $1.key.displayName }
            let typeStr = typeCounts.map { "\($0.key.displayName): \($0.value)" }.joined(separator: ", ")
            lines.append("  Run \(run.runNumber): \(run.digressionCount) digressions — \(typeStr)")
            for d in run.digressions {
                lines.append("    \(d.type.displayName): s\(d.startSentence)-\(d.endSentence) (\(d.sentenceCount)s) conf=\(String(format: "%.1f", d.confidence))")
            }
        }
        lines.append("")

        // WHY: Type consistency
        lines.append("WHY — Type Consistency:")
        let tc = typeConsistency
        for type in DigressionType.allCases {
            if let consistency = tc[type] {
                lines.append("  \(type.displayName): \(String(format: "%.0f%%", consistency * 100)) agreement")
            }
        }
        lines.append("")

        lines.append("WHY — Scoring Logic:")
        lines.append("  Consistency = (runs detecting sentence as digression) / (total runs)")
        lines.append("  Unanimous = all runs agree (consistency = 1.0)")
        lines.append("  Divergent = runs disagree (0 < consistency < 1.0)")

        return lines.joined(separator: "\n")
    }

    // MARK: Copy Text — Run Detail

    func runDetailText(for run: DigressionFidelityRunResult) -> String {
        var lines: [String] = []
        lines.append("═══ RUN \(run.runNumber) DETAIL ═══")
        lines.append("Mode: \(run.detectionMode?.displayName ?? detectionMode.displayName)")
        lines.append("Temp: \(String(format: "%.2f", run.temperature))")
        lines.append("Digressions: \(run.digressionCount)")
        lines.append("")

        let validations = validationsForRun(run)

        for (idx, d) in run.digressions.enumerated() {
            lines.append("[\(idx + 1)] \(d.type.displayName) — s\(d.startSentence)-\(d.endSentence) (\(d.sentenceCount) sentences)")
            lines.append("  Confidence: \(String(format: "%.1f", d.confidence)) | Method: \(d.detectionMethod.displayName)")
            if let brief = d.briefContent {
                lines.append("  Brief: \(brief)")
            }

            if let validation = validations.first(where: { $0.annotation.id == d.id }) {
                lines.append("  Rules Verdict: \(validation.verdict.rawValue.uppercased())")
                for check in validation.checks {
                    let icon = check.passed ? "PASS" : "FAIL"
                    lines.append("    [\(icon)] \(check.name): \(check.detail)")
                }
                if let reason = validation.contradictionReason {
                    lines.append("  WHY contradicted: \(reason)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var allRunsDetailText: String {
        runs.map { runDetailText(for: $0) }.joined(separator: "\n\n")
    }

    // MARK: Copy Text — Transcript

    var annotatedTranscriptText: String {
        guard !runs.isEmpty, !sentences.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("═══ ANNOTATED TRANSCRIPT (all \(runs.count) runs) ═══")
        lines.append("Video: \(video.title)")
        lines.append("Mode: \(detectionMode.displayName), Temp: \(String(format: "%.2f", temperature))")
        lines.append("")

        for sentence in sentences {
            let idx = sentence.sentenceIndex

            var runLabels: [String] = []
            for run in runs {
                if let d = run.digressions.first(where: { $0.contains(sentenceIndex: idx) }) {
                    runLabels.append("R\(run.runNumber):\(d.type.displayName)")
                }
            }

            let prefix = runLabels.isEmpty ? "  " : "▶ "
            lines.append("\(prefix)[s\(idx)] \(sentence.text)")

            if !runLabels.isEmpty {
                lines.append("    → \(runLabels.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Copy Text — Validation

    func validationReportText(for run: DigressionFidelityRunResult) -> String {
        let validations = validationsForRun(run)
        return DigressionRulesValidator.shared.generateDebugReport(validations: validations)
    }
}

// MARK: - Main View

struct DigressionFidelityView: View {
    @StateObject private var viewModel: DigressionFidelityViewModel

    init(video: YouTubeVideo) {
        _viewModel = StateObject(wrappedValue: DigressionFidelityViewModel(video: video))
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsSection
            Divider()

            if viewModel.isRunning {
                progressSection
            } else if !viewModel.runs.isEmpty {
                resultsSection
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Digression Fidelity")
        .task {
            await viewModel.loadSentences()
            viewModel.loadFromDefaults()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(viewModel.video.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if !viewModel.sentences.isEmpty {
                    Text("\(viewModel.sentences.count) sentences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Detection mode picker
            Picker("Mode", selection: $viewModel.detectionMode) {
                ForEach(DetectionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.2f")")
                        .font(.caption)
                    Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.05)
                        .frame(width: 150)
                }

                Stepper("Runs: \(viewModel.runCount)", value: $viewModel.runCount, in: 1...10)
                    .frame(width: 140)

                if viewModel.detectionMode == .rulesFirst {
                    Toggle("LLM", isOn: $viewModel.enableLLMEscalation)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .frame(width: 80)
                }

                Spacer()

                Button {
                    viewModel.loadFromDefaults()
                } label: {
                    Label("Load Saved", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning || !viewModel.hasSavedResults)

                Button {
                    Task { await viewModel.runFidelityTest() }
                } label: {
                    Label("Run Test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning || viewModel.sentences.isEmpty)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Run \(viewModel.currentRun) of \(viewModel.runCount)")
                .font(.headline)

            Text(viewModel.currentPhase)
                .font(.subheadline)
                .foregroundColor(.orange)

            ProgressView(value: Double(viewModel.currentRun), total: Double(viewModel.runCount))
                .frame(width: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if viewModel.sentences.isEmpty {
                ProgressView()
                Text("Loading sentences...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Digression Fidelity Test")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Runs digression detection multiple times and compares results across runs to measure consistency.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Text("\(viewModel.sentences.count) sentences loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results (4 Tabs)

    @State private var selectedTab: ResultsTab = .summary
    @State private var selectedRunIndex: Int = 0

    private enum ResultsTab: String, CaseIterable {
        case summary = "Summary"
        case runDetail = "Run Detail"
        case transcript = "Transcript"
        case validate = "Validate"
    }

    private var resultsSection: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(ResultsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .summary:
                summaryView
            case .runDetail:
                runDetailView
            case .transcript:
                transcriptView
            case .validate:
                validateView
            }
        }
    }

    // MARK: - Summary Tab

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stats header with copy buttons
            HStack {
                Text("Digressions across \(viewModel.runs.count) runs")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    statBadge("\(viewModel.unanimousDigressions.count) unanimous", color: .blue)
                    statBadge("\(viewModel.divergentDigressions.count) divergent", color: viewModel.divergentDigressions.isEmpty ? .green : .orange)
                }

                FadeOutCopyButton(text: viewModel.summaryText, label: "Copy Summary", systemImage: "doc.on.doc")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Per-run summary lines
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.runs) { run in
                    let digressionRanges = run.digressions.map { "s\($0.startSentence)-\($0.endSentence)" }.joined(separator: ", ")
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("Run \(run.runNumber):")
                                .font(.caption2.bold())
                            Text("\(run.digressionCount) digressions")
                                .font(.caption2)
                            ForEach(DigressionType.allCases) { type in
                                let count = run.typeDistribution[type] ?? 0
                                if count > 0 {
                                    HStack(spacing: 2) {
                                        Circle()
                                            .fill(type.color)
                                            .frame(width: 6, height: 6)
                                        Text("\(count)")
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        if !digressionRanges.isEmpty {
                            Text("  at \(digressionRanges)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            Divider()

            // Cross-run comparison table
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Type consistency
                    typeConsistencySection

                    Divider()
                        .padding(.vertical, 4)

                    // Cross-run comparison table header
                    HStack(spacing: 0) {
                        Text("Sentence")
                            .frame(width: 70, alignment: .leading)

                        Text("Text")
                            .frame(width: 200, alignment: .leading)

                        ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                            Text("R\(runNum)")
                                .frame(width: 35)
                        }

                        Text("Types")
                            .frame(width: 100, alignment: .leading)

                        Text("Match")
                            .frame(width: 60)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))

                    // Only show sentences that are digressions in at least one run
                    let digressionSentences = viewModel.crossRunComparison.filter { $0.runsDetected > 0 }
                    ForEach(digressionSentences) { comparison in
                        comparisonRow(comparison)
                    }
                }
            }
        }
    }

    private var typeConsistencySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type Consistency")
                .font(.caption.bold())
                .padding(.top, 8)

            ForEach(DigressionType.allCases) { type in
                if let consistency = viewModel.typeConsistency[type] {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(type.color)
                            .frame(width: 8, height: 8)
                        Text(type.displayName)
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)

                        // Per-run count
                        ForEach(viewModel.runs) { run in
                            let count = run.typeDistribution[type] ?? 0
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.3))
                                .frame(width: 25)
                        }

                        Text(String(format: "%.0f%%", consistency * 100))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundColor(consistency >= 1.0 ? .green : .orange)
                            .frame(width: 40)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func comparisonRow(_ comparison: CrossRunDigressionComparison) -> some View {
        HStack(spacing: 0) {
            Text("s\(comparison.sentenceIndex)")
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)

            Text(String(comparison.sentenceText.prefix(40)))
                .font(.caption)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)

            ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                let runIndex = runNum - 1
                let isDigression = runIndex < viewModel.runs.count &&
                    viewModel.runs[runIndex].digressions.contains { $0.contains(sentenceIndex: comparison.sentenceIndex) }
                Image(systemName: isDigression ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundColor(isDigression ? .orange : .gray.opacity(0.3))
                    .frame(width: 35)
            }

            // Types found across runs
            HStack(spacing: 2) {
                ForEach(Array(comparison.typesFound), id: \.self) { type in
                    Circle()
                        .fill(type.color)
                        .frame(width: 6, height: 6)
                }
                if comparison.typesFound.count > 1 {
                    Text("(\(comparison.typesFound.count))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 100, alignment: .leading)

            Text(comparison.isUnanimous ? "100%" : "\(Int(comparison.consistency * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(comparison.isUnanimous ? .green : .orange)
                .frame(width: 60)
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .background(
            comparison.isDivergent
                ? Color.orange.opacity(0.08)
                : comparison.isUnanimous
                    ? Color.blue.opacity(0.05)
                    : Color.clear
        )
    }

    // MARK: - Run Detail Tab

    private var runDetailView: some View {
        VStack(spacing: 0) {
            if !viewModel.runs.isEmpty {
                // Run picker + copy buttons
                HStack {
                    Picker("Run", selection: $selectedRunIndex) {
                        ForEach(viewModel.runs.indices, id: \.self) { index in
                            Text("Run \(viewModel.runs[index].runNumber)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedRunIndex < viewModel.runs.count {
                        FadeOutCopyButton(
                            text: viewModel.runDetailText(for: viewModel.runs[selectedRunIndex]),
                            label: "Copy Run",
                            systemImage: "doc.on.doc"
                        )
                        FadeOutCopyButton(
                            text: viewModel.allRunsDetailText,
                            label: "Copy All",
                            systemImage: "doc.on.doc.fill"
                        )
                    }
                }
                .padding()

                Divider()

                if selectedRunIndex < viewModel.runs.count {
                    let run = viewModel.runs[selectedRunIndex]

                    // Run stats header
                    HStack(spacing: 12) {
                        Text("\(run.digressionCount) digressions")
                            .font(.caption.bold())
                        Text("temp: \(String(format: "%.2f", run.temperature))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(run.detectionMode?.displayName ?? viewModel.detectionMode.displayName)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)

                        ForEach(DigressionType.allCases) { type in
                            let count = run.typeDistribution[type] ?? 0
                            if count > 0 {
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(type.color)
                                        .frame(width: 6, height: 6)
                                    Text("\(type.displayName): \(count)")
                                        .font(.caption2)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            let validations = viewModel.validationsForRun(run)

                            ForEach(run.digressions) { digression in
                                digressionDetailCard(
                                    digression,
                                    validation: validations.first { $0.annotation.id == digression.id }
                                )
                            }

                            if run.digressions.isEmpty {
                                Text("No digressions detected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func digressionDetailCard(_ d: DigressionAnnotation, validation: ValidatedDigression?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: type + range + confidence
            HStack(spacing: 8) {
                Circle()
                    .fill(d.type.color)
                    .frame(width: 10, height: 10)

                Text(d.type.displayName)
                    .font(.caption.bold())
                    .foregroundColor(d.type.color)

                Text("s\(d.startSentence)-\(d.endSentence)")
                    .font(.caption.monospaced())

                Text("(\(d.sentenceCount) sentences)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("conf: \(String(format: "%.1f", d.confidence))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Text(d.detectionMethod.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
            }

            // Brief content
            if let brief = d.briefContent {
                Text(brief)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Entry/exit markers
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.caption2)
                    Text(d.entryMarker)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    Image(systemName: "arrow.left.to.line")
                        .font(.caption2)
                    Text(d.exitMarker)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }

            // Mechanical flags
            HStack(spacing: 12) {
                if d.hasCTA {
                    Label("CTA", systemImage: "megaphone")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                if d.perspectiveShift {
                    Label("Perspective Shift", systemImage: "person.2")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                if d.stanceShift {
                    Label("Stance Shift", systemImage: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
            }

            // Validation verdict
            if let v = validation {
                Divider()
                verdictSection(v)
            }

            // Transcript excerpt (first 3 sentences of the digression)
            if !viewModel.sentences.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 1) {
                    let rangeSentences = viewModel.sentences.filter { d.contains(sentenceIndex: $0.sentenceIndex) }
                    ForEach(rangeSentences.prefix(3), id: \.sentenceIndex) { sentence in
                        HStack(alignment: .top, spacing: 4) {
                            Text("s\(sentence.sentenceIndex)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(sentence.text)
                                .font(.caption2)
                                .lineLimit(2)
                        }
                    }
                    if rangeSentences.count > 3 {
                        Text("... +\(rangeSentences.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                }
            }
        }
        .padding(10)
        .background(d.type.color.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(d.type.color.opacity(0.2), lineWidth: 1)
        )
    }

    private func verdictSection(_ validation: ValidatedDigression) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: validation.verdict.symbol)
                    .foregroundColor(validation.verdict.color)
                    .font(.caption2)
                Text("Rules:")
                    .font(.caption2.bold())
                Text(validation.verdict.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundColor(validation.verdict.color)
                Text("(\(validation.checks.filter(\.passed).count)/\(validation.checks.count) checks passed)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let reason = validation.contradictionReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
            }

            // Individual gate checks
            ForEach(validation.checks) { check in
                HStack(spacing: 4) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(check.passed ? .green : .red)
                        .font(.caption2)
                    Text(check.name)
                        .font(.caption2.bold())
                    Text(check.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Transcript Tab

    private var transcriptView: some View {
        VStack(spacing: 0) {
            // Header with copy button
            HStack {
                Text("Full Transcript — All \(viewModel.runs.count) Runs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                FadeOutCopyButton(text: viewModel.annotatedTranscriptText, label: "Copy Transcript", systemImage: "doc.on.doc")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.sentences, id: \.sentenceIndex) { sentence in
                        transcriptRow(sentence)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func transcriptRow(_ sentence: SentenceTelemetry) -> some View {
        let comparison = viewModel.crossRunComparison.first { $0.sentenceIndex == sentence.sentenceIndex }
        let isDigressionEntry = viewModel.runs.contains { run in
            run.digressions.contains { $0.startSentence == sentence.sentenceIndex }
        }
        let isDigressionExit = viewModel.runs.contains { run in
            run.digressions.contains { $0.endSentence == sentence.sentenceIndex }
        }

        return VStack(alignment: .leading, spacing: 0) {
            // Entry annotation
            if isDigressionEntry {
                let entries = viewModel.runs.compactMap { run in
                    run.digressions.first { $0.startSentence == sentence.sentenceIndex }
                }
                if let first = entries.first {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.caption2)
                        Text("\(first.type.displayName) ENTRY")
                            .font(.caption2.bold())
                        Text("(\(entries.count)/\(viewModel.runs.count) runs)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(first.type.color)
                    .padding(.leading, 36)
                    .padding(.bottom, 2)
                }
            }

            // Sentence row
            HStack(alignment: .top, spacing: 8) {
                Text("s\(sentence.sentenceIndex)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)

                // Per-run indicators
                HStack(spacing: 2) {
                    ForEach(viewModel.runs) { run in
                        let digression = run.digressions.first { $0.contains(sentenceIndex: sentence.sentenceIndex) }
                        Circle()
                            .fill(digression != nil ? digression!.type.color : Color.green.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: CGFloat(viewModel.runs.count) * 8 + 4)

                Text(sentence.text)
                    .font(.caption2)
                    .lineLimit(3)

                Spacer()

                if let comp = comparison, comp.runsDetected > 0 {
                    Text("\(comp.runsDetected)/\(comp.totalRuns)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(comp.isUnanimous ? .blue : .orange)
                }
            }
            .padding(.vertical, 1)
            .background(
                comparison?.isDivergent == true
                    ? Color.orange.opacity(0.05)
                    : comparison?.isUnanimous == true
                        ? Color.blue.opacity(0.05)
                        : Color.clear
            )

            // Exit annotation
            if isDigressionExit {
                let exits = viewModel.runs.compactMap { run in
                    run.digressions.first { $0.endSentence == sentence.sentenceIndex }
                }
                if let first = exits.first {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.caption2)
                        Text("\(first.type.displayName) EXIT")
                            .font(.caption2.bold())
                        Text("(\(exits.count)/\(viewModel.runs.count) runs)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(first.type.color)
                    .padding(.leading, 36)
                    .padding(.top, 2)

                    Divider()
                        .overlay(first.type.color.opacity(0.3))
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Validate Tab

    @State private var validateRunIndex: Int = 0

    private var validateView: some View {
        VStack(spacing: 0) {
            if !viewModel.runs.isEmpty {
                // Run picker + copy
                HStack {
                    Picker("Run", selection: $validateRunIndex) {
                        ForEach(viewModel.runs.indices, id: \.self) { index in
                            Text("Run \(viewModel.runs[index].runNumber)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    if validateRunIndex < viewModel.runs.count {
                        FadeOutCopyButton(
                            text: viewModel.validationReportText(for: viewModel.runs[validateRunIndex]),
                            label: "Copy Report",
                            systemImage: "doc.on.doc"
                        )
                    }
                }
                .padding()

                Divider()

                if validateRunIndex < viewModel.runs.count {
                    let run = viewModel.runs[validateRunIndex]
                    let validations = viewModel.validationsForRun(run)

                    // Verdict summary badges
                    HStack(spacing: 8) {
                        let confirmed = validations.filter { $0.verdict == .confirmed }.count
                        let neutral = validations.filter { $0.verdict == .neutral }.count
                        let contradicted = validations.filter { $0.verdict == .contradicted }.count

                        statBadge("\(confirmed) confirmed", color: .green)
                        statBadge("\(neutral) neutral", color: .secondary)
                        statBadge("\(contradicted) contradicted", color: .orange)

                        Spacer()

                        Text("\(validations.count) digressions validated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)

                    Divider()

                    // Validation table
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack(spacing: 0) {
                                Text("#")
                                    .frame(width: 30, alignment: .leading)
                                Text("Type")
                                    .frame(width: 130, alignment: .leading)
                                Text("Range")
                                    .frame(width: 80, alignment: .leading)
                                Text("Verdict")
                                    .frame(width: 100, alignment: .leading)
                                Text("Checks")
                                    .frame(width: 80, alignment: .leading)
                                Text("Detail")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))

                            ForEach(Array(validations.enumerated()), id: \.offset) { idx, validation in
                                validationRow(index: idx + 1, validation: validation)
                            }
                        }
                    }
                }
            }
        }
    }

    private func validationRow(index: Int, validation: ValidatedDigression) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("\(index)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 30, alignment: .leading)

                HStack(spacing: 4) {
                    Circle()
                        .fill(validation.annotation.type.color)
                        .frame(width: 6, height: 6)
                    Text(validation.annotation.type.displayName)
                        .font(.caption)
                }
                .frame(width: 130, alignment: .leading)

                Text("s\(validation.annotation.startSentence)-\(validation.annotation.endSentence)")
                    .font(.caption.monospaced())
                    .frame(width: 80, alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: validation.verdict.symbol)
                        .foregroundColor(validation.verdict.color)
                    Text(validation.verdict.rawValue.capitalized)
                        .foregroundColor(validation.verdict.color)
                }
                .font(.caption)
                .frame(width: 100, alignment: .leading)

                Text("\(validation.checks.filter(\.passed).count)/\(validation.checks.count)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 80, alignment: .leading)

                // Brief or contradiction reason
                if let reason = validation.contradictionReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let brief = validation.annotation.briefContent {
                    Text(brief)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }

            // Expandable gate checks
            DisclosureGroup("Gate Checks") {
                ForEach(validation.checks) { check in
                    HStack(spacing: 4) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(check.passed ? .green : .red)
                            .font(.caption2)
                        Text(check.name)
                            .font(.caption2.bold())
                        Text(check.detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .font(.caption2)
            .padding(.leading, 30)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(
            validation.verdict == .contradicted
                ? Color.orange.opacity(0.08)
                : validation.verdict == .confirmed
                    ? Color.green.opacity(0.05)
                    : Color.clear
        )
    }

    // MARK: - Helpers

    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
