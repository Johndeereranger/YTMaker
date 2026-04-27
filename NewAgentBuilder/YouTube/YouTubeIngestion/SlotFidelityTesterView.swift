//
//  SlotFidelityTesterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class SlotFidelityViewModel: ObservableObject {
    let video: YouTubeVideo
    let channel: YouTubeChannel
    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    // Config
    @Published var runCount: Int = 3
    @Published var temperature: Double = 0.1
    @Published var selectedSection: Int = 0

    // Progress
    @Published var isRunning = false
    @Published var currentRun = 0
    @Published var currentPhase = ""

    // Results
    @Published var runs: [SlotFidelityRun] = []
    @Published var originalSentences: [String] = []   // With parentheticals, for display
    @Published var sectionSentences: [String] = []     // Cleaned, sent to LLM
    @Published var sectionMoveType: String = ""
    @Published var sectionCategory: String = ""
    @Published var errorMessage: String?

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        self.video = video
        self.channel = channel
    }

    // MARK: - Section Count

    var availableSections: Int {
        min(video.rhetoricalSequence?.moves.count ?? 0, 2)
    }

    // MARK: - Load Section Sentences

    func loadSectionSentences() {
        runs = []
        guard let sequence = video.rhetoricalSequence,
              let transcript = video.transcript else {
            errorMessage = "No rhetorical sequence or transcript"
            return
        }

        let allSentences = SentenceParser.parse(transcript)
        guard !allSentences.isEmpty else {
            errorMessage = "No sentences parsed"
            return
        }

        let moves = Array(sequence.moves.prefix(2))
        guard selectedSection < moves.count else {
            errorMessage = "Section \(selectedSection + 1) not available"
            return
        }

        let move = moves[selectedSection]
        let startIdx = move.startSentence ?? 0
        let endIdx = move.endSentence ?? min(startIdx + 20, allSentences.count - 1)

        guard startIdx < allSentences.count else {
            errorMessage = "Section start beyond transcript"
            return
        }

        let clampedEnd = min(endIdx, allSentences.count - 1)
        let raw = Array(allSentences[startIdx...clampedEnd])
        originalSentences = raw
        sectionSentences = raw.map { DeterministicHints.stripParentheticals($0) }
        sectionMoveType = move.moveType.rawValue
        sectionCategory = move.moveType.category.rawValue
        errorMessage = nil
    }

    // MARK: - Run Fidelity Test

    func runFidelityTest() async {
        guard !sectionSentences.isEmpty else {
            errorMessage = "No sentences loaded"
            return
        }

        isRunning = true
        errorMessage = nil
        runs = []
        currentPhase = "Launching \(runCount) runs in parallel..."

        let hints = sectionSentences.map { DeterministicHints.compute(for: $0) }
        let capturedSentences = sectionSentences
        let capturedOriginals = originalSentences
        let capturedMove = sectionMoveType
        let capturedCategory = sectionCategory
        let capturedTemp = temperature
        let totalRuns = runCount

        let collected = await withTaskGroup(
            of: (Int, [SlotFidelitySentenceResult])?.self
        ) { group in
            for i in 1...totalRuns {
                group.addTask {
                    do {
                        let results = try await DonorLibraryA2Service.shared.callSlotAnnotation(
                            sentences: capturedSentences,
                            hints: hints,
                            moveType: capturedMove,
                            category: capturedCategory,
                            temperature: capturedTemp
                        )

                        let sentenceResults: [SlotFidelitySentenceResult] = results.enumerated().map { idx, r in
                            SlotFidelitySentenceResult(
                                sentenceIndex: idx,
                                rawText: idx < capturedOriginals.count ? capturedOriginals[idx] : "",
                                phrases: r.phrases,
                                slotSequence: r.slotSequence,
                                slotSignature: r.slotSequence.joined(separator: "|"),
                                sentenceFunction: r.sentenceFunction,
                                hints: r.deterministicHints,
                                hintMismatches: r.hintMismatches
                            )
                        }
                        return (i, sentenceResults)
                    } catch {
                        return nil
                    }
                }
            }

            var results: [(Int, [SlotFidelitySentenceResult])] = []
            for await result in group {
                if let result {
                    results.append(result)
                    await MainActor.run {
                        currentRun = results.count
                        currentPhase = "\(results.count)/\(totalRuns) runs complete"
                    }
                }
            }
            return results.sorted { $0.0 < $1.0 }
        }

        runs = collected.map { runNum, sentenceResults in
            SlotFidelityRun(runNumber: runNum, temperature: temperature, results: sentenceResults)
        }

        if runs.count < totalRuns {
            errorMessage = "\(totalRuns - runs.count) run(s) failed"
        }

        isRunning = false
        currentPhase = "Complete"
        saveResults()
    }

    // MARK: - Computed Comparisons

    var sentenceComparisons: [SlotFidelitySentenceComparison] {
        guard !runs.isEmpty, !sectionSentences.isEmpty else { return [] }
        let sentenceCount = sectionSentences.count

        return (0..<sentenceCount).map { idx in
            let runsForSentence = runs.compactMap { run -> SlotFidelitySentenceResult? in
                idx < run.results.count ? run.results[idx] : nil
            }

            let signatures = runsForSentence.map { $0.slotSignature }
            let functions = runsForSentence.map { $0.sentenceFunction }

            let dominantSig = mostCommon(signatures) ?? ""
            let sigMatch = signatures.isEmpty ? 0 : Double(signatures.filter { $0 == dominantSig }.count) / Double(signatures.count)
            let allSigsMatch = Set(signatures).count <= 1

            let dominantFunc = mostCommon(functions) ?? ""
            let funcMatch = Set(functions).count <= 1

            // Build phrase alignment
            let phraseAlignment = buildPhraseAlignment(from: runsForSentence)

            // Collect hint mismatches across runs
            let allMismatches = Array(Set(runsForSentence.flatMap { $0.hintMismatches }))

            return SlotFidelitySentenceComparison(
                sentenceIndex: idx,
                rawText: idx < originalSentences.count ? originalSentences[idx] : sectionSentences[idx],
                runsAgreedOnSignature: allSigsMatch,
                signatureConsistency: sigMatch,
                dominantSignature: dominantSig,
                runsAgreedOnFunction: funcMatch,
                dominantFunction: dominantFunc,
                phraseAlignment: phraseAlignment,
                hintMismatchesAcrossRuns: allMismatches,
                perRunSignatures: signatures,
                perRunFunctions: functions
            )
        }
    }

    var signatureMatchRate: Double {
        let comps = sentenceComparisons
        guard !comps.isEmpty else { return 0 }
        return Double(comps.filter { $0.runsAgreedOnSignature }.count) / Double(comps.count)
    }

    var functionMatchRate: Double {
        let comps = sentenceComparisons
        guard !comps.isEmpty else { return 0 }
        return Double(comps.filter { $0.runsAgreedOnFunction }.count) / Double(comps.count)
    }

    var phraseMatchRate: Double {
        let comps = sentenceComparisons
        guard !comps.isEmpty else { return 0 }
        let allAlignments = comps.flatMap { $0.phraseAlignment }
        guard !allAlignments.isEmpty else { return 0 }
        return Double(allAlignments.filter { $0.isUnanimous }.count) / Double(allAlignments.count)
    }

    var perTypeConsistency: [(type: String, rate: Double)] {
        guard !runs.isEmpty else { return [] }

        var typeAppearances: [String: Int] = [:]
        var typeAgreements: [String: Int] = [:]

        for comp in sentenceComparisons {
            let allTypes = Set(comp.perRunSignatures.flatMap { $0.split(separator: "|").map(String.init) })
            for type in allTypes {
                typeAppearances[type, default: 0] += 1
                let runsWithType = comp.perRunSignatures.filter { sig in
                    sig.split(separator: "|").map(String.init).contains(type)
                }.count
                if runsWithType == runs.count {
                    typeAgreements[type, default: 0] += 1
                }
            }
        }

        return typeAppearances.map { type, total in
            let agreed = typeAgreements[type] ?? 0
            return (type: type, rate: total > 0 ? Double(agreed) / Double(total) : 0)
        }.sorted { $0.rate > $1.rate }
    }

    var unanimousCount: Int {
        sentenceComparisons.filter { $0.runsAgreedOnSignature }.count
    }

    var divergentCount: Int {
        sentenceComparisons.filter { !$0.runsAgreedOnSignature }.count
    }

    var hintMismatchCount: Int {
        sentenceComparisons.filter { !$0.hintMismatchesAcrossRuns.isEmpty }.count
    }

    // MARK: - Phrase Alignment Builder

    private func buildPhraseAlignment(from results: [SlotFidelitySentenceResult]) -> [PhraseAlignment] {
        guard !results.isEmpty else { return [] }

        // Use first run's phrases as reference, align other runs against them
        let reference = results[0].phrases
        var alignments: [PhraseAlignment] = []

        for (phraseIdx, refPhrase) in reference.enumerated() {
            var rolesPerRun: [Int: String] = [1: refPhrase.role]

            for runIdx in 1..<results.count {
                let otherPhrases = results[runIdx].phrases
                // Find matching phrase by text overlap
                if phraseIdx < otherPhrases.count {
                    rolesPerRun[runIdx + 1] = otherPhrases[phraseIdx].role
                } else {
                    // Try to find by text similarity
                    let match = otherPhrases.first { $0.text.lowercased() == refPhrase.text.lowercased() }
                    rolesPerRun[runIdx + 1] = match?.role ?? "missing"
                }
            }

            let roles = Array(rolesPerRun.values)
            let dominant = mostCommon(roles) ?? refPhrase.role
            let unanimous = Set(roles.filter { $0 != "missing" }).count <= 1

            alignments.append(PhraseAlignment(
                phraseText: refPhrase.text,
                rolesPerRun: rolesPerRun,
                isUnanimous: unanimous,
                dominantRole: dominant
            ))
        }

        return alignments
    }

    private func mostCommon(_ items: [String]) -> String? {
        guard !items.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Copy Text

    var summaryText: String {
        let comps = sentenceComparisons
        var lines: [String] = []
        lines.append("SLOT FIDELITY TEST — \(video.title)")
        lines.append("Section \(selectedSection + 1): \(sectionMoveType) | \(sectionCategory)")
        lines.append("Runs: \(runs.count) | Temperature: \(String(format: "%.2f", temperature))")
        lines.append("")
        lines.append("WHAT: Signature Match: \(String(format: "%.0f%%", signatureMatchRate * 100)) (\(unanimousCount)/\(comps.count) sentences)")
        lines.append("WHAT: Phrase Match: \(String(format: "%.0f%%", phraseMatchRate * 100))")
        lines.append("WHAT: Function Match: \(String(format: "%.0f%%", functionMatchRate * 100))")
        lines.append("WHAT: Hint Mismatches: \(hintMismatchCount) sentences flagged")
        lines.append("")
        lines.append("WHY: Per-Type Consistency:")
        for tc in perTypeConsistency {
            let displayName = SlotType(rawValue: tc.type)?.displayName ?? tc.type
            lines.append("  \(displayName): \(String(format: "%.0f%%", tc.rate * 100))")
        }
        return lines.joined(separator: "\n")
    }

    var phraseDetailText: String {
        var lines: [String] = []
        lines.append("PHRASE DETAIL — \(video.title) — Section \(selectedSection + 1)")
        lines.append("")
        for comp in sentenceComparisons {
            let matchIcon = comp.runsAgreedOnSignature ? "OK" : "DIVERGENT"
            lines.append("[\(comp.sentenceIndex + 1)] [\(matchIcon)] \(String(format: "%.0f%%", comp.signatureConsistency * 100))")
            lines.append("  \"\(comp.rawText)\"")
            for (runIdx, sig) in comp.perRunSignatures.enumerated() {
                lines.append("  Run \(runIdx + 1): [\(sig)]")
            }
            if !comp.hintMismatchesAcrossRuns.isEmpty {
                lines.append("  HINT MISMATCHES: \(comp.hintMismatchesAcrossRuns.joined(separator: "; "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    var commonalityText: String {
        var lines: [String] = []
        lines.append("COMMONALITY MATRIX — \(video.title) — Section \(selectedSection + 1)")
        lines.append("")
        for comp in sentenceComparisons {
            lines.append("[\(comp.sentenceIndex + 1)] \"\(String(comp.rawText.prefix(60)))...\"")
            for align in comp.phraseAlignment {
                let roleStr = align.rolesPerRun.sorted(by: { $0.key < $1.key }).map { "R\($0.key):\($0.value)" }.joined(separator: " | ")
                let status = align.isUnanimous ? "UNANIMOUS" : "DIVERGENT"
                lines.append("  \"\(align.phraseText)\" → \(status) [\(roleStr)]")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    var fullDebugText: String {
        let divider = String(repeating: "=", count: 60)
        return [summaryText, "", divider, "", phraseDetailText, "", divider, "", commonalityText].joined(separator: "\n")
    }

    // MARK: - Storage

    private var storageKey: String {
        "slot_fidelity_\(video.videoId)_section\(selectedSection)"
    }

    func saveResults() {
        guard !runs.isEmpty else { return }
        let stored = StoredSlotFidelityTest(
            videoId: video.videoId,
            videoTitle: video.title,
            channelId: channel.channelId,
            sectionIndex: selectedSection,
            testDate: Date(),
            runCount: runs.count,
            temperature: temperature,
            signatureMatchRate: signatureMatchRate,
            phraseMatchRate: phraseMatchRate,
            functionMatchRate: functionMatchRate,
            hintMismatchCount: hintMismatchCount
        )

        var history = loadStoredTests()
        history.insert(stored, at: 0)
        if history.count > 5 { history = Array(history.prefix(5)) }

        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func loadStoredTests() -> [StoredSlotFidelityTest] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tests = try? JSONDecoder().decode([StoredSlotFidelityTest].self, from: data) else {
            return []
        }
        return tests
    }

    var hasSavedResults: Bool {
        !loadStoredTests().isEmpty
    }

    // MARK: - Confusable Pairs

    @Published var savedPairsCount: Int?
    @Published var isSavingPairs = false

    func extractAndSaveConfusablePairs() async {
        let comps = sentenceComparisons
        guard !comps.isEmpty else { return }

        isSavingPairs = true
        let pairs = ConfusablePairService.shared.extractPairs(
            from: comps,
            moveType: sectionMoveType,
            creatorId: channel.channelId,
            videoId: video.videoId
        )

        guard !pairs.isEmpty else {
            savedPairsCount = 0
            isSavingPairs = false
            return
        }

        do {
            try await ConfusablePairService.shared.savePairs(pairs)
            savedPairsCount = pairs.count
        } catch {
            errorMessage = "Confusable save failed: \(error.localizedDescription)"
        }
        isSavingPairs = false
    }
}

// MARK: - Data Types

struct SlotFidelityRun: Identifiable {
    let id = UUID()
    let runNumber: Int
    let temperature: Double
    let results: [SlotFidelitySentenceResult]
}

struct SlotFidelitySentenceResult {
    let sentenceIndex: Int
    let rawText: String
    let phrases: [SentencePhrase]
    let slotSequence: [String]
    let slotSignature: String
    let sentenceFunction: String
    let hints: [String]
    let hintMismatches: [String]
}

struct SlotFidelitySentenceComparison: Identifiable {
    var id: Int { sentenceIndex }
    let sentenceIndex: Int
    let rawText: String
    let runsAgreedOnSignature: Bool
    let signatureConsistency: Double
    let dominantSignature: String
    let runsAgreedOnFunction: Bool
    let dominantFunction: String
    let phraseAlignment: [PhraseAlignment]
    let hintMismatchesAcrossRuns: [String]
    let perRunSignatures: [String]
    let perRunFunctions: [String]
}

struct PhraseAlignment: Identifiable {
    let id = UUID()
    let phraseText: String
    let rolesPerRun: [Int: String]
    let isUnanimous: Bool
    let dominantRole: String
}

struct StoredSlotFidelityTest: Codable, Identifiable {
    var id: String { "\(videoId)_\(sectionIndex)_\(testDate.timeIntervalSince1970)" }
    let videoId: String
    let videoTitle: String
    let channelId: String
    let sectionIndex: Int
    let testDate: Date
    let runCount: Int
    let temperature: Double
    let signatureMatchRate: Double
    let phraseMatchRate: Double
    let functionMatchRate: Double
    let hintMismatchCount: Int
}

// MARK: - Main View

struct SlotFidelityTesterView: View {
    @StateObject private var vm: SlotFidelityViewModel
    @State private var selectedTab = 0
    @State private var expandedSentences: Set<Int> = []
    @State private var confusableSaveConfirmed = false

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        _vm = StateObject(wrappedValue: SlotFidelityViewModel(video: video, channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                configSection
                progressSection

                if !vm.runs.isEmpty {
                    tabPickerSection

                    switch selectedTab {
                    case 0: summaryTab
                    case 1: phraseDetailTab
                    case 2: commonalityTab
                    default: EmptyView()
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
        }
        .navigationTitle("Slot Fidelity Tester")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.loadSectionSentences()
        }
        .onChange(of: vm.selectedSection) { _, _ in
            vm.loadSectionSentences()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.video.title)
                .font(.subheadline.bold())
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(vm.sectionSentences.count) sentences", systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if vm.availableSections > 1 {
                    Picker("Section", selection: $vm.selectedSection) {
                        ForEach(0..<vm.availableSections, id: \.self) { idx in
                            Text("Section \(idx + 1)").tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                } else {
                    Text("Section 1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !vm.sectionMoveType.isEmpty {
                HStack(spacing: 6) {
                    Text(vm.sectionMoveType)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.teal.opacity(0.15))
                        .foregroundColor(.teal)
                        .cornerRadius(4)

                    Text(vm.sectionCategory)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Runs:")
                        .font(.caption)
                    Text("\(vm.runCount)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 20)
                    Stepper("", value: $vm.runCount, in: 2...10)
                        .labelsHidden()
                }

                HStack(spacing: 6) {
                    Text("Temp:")
                        .font(.caption)
                    Text(String(format: "%.2f", vm.temperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 36)
                    Slider(value: $vm.temperature, in: 0.0...1.0, step: 0.05)
                        .frame(maxWidth: 120)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await vm.runFidelityTest() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run Fidelity Test")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.teal.opacity(0.15))
                    .foregroundColor(.teal)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(vm.isRunning || vm.sectionSentences.isEmpty)

                if vm.hasSavedResults {
                    let stored = vm.loadStoredTests()
                    if let latest = stored.first {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Last: \(latest.testDate, style: .relative) ago")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("Sig: \(String(format: "%.0f%%", latest.signatureMatchRate * 100)) | Phr: \(String(format: "%.0f%%", latest.phraseMatchRate * 100))")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if vm.isRunning {
            VStack(spacing: 6) {
                ProgressView(value: Double(vm.currentRun), total: Double(vm.runCount))
                    .tint(.teal)
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(vm.currentPhase)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Tab Picker

    private var tabPickerSection: some View {
        HStack(spacing: 8) {
            Picker("Tab", selection: $selectedTab) {
                Text("Summary").tag(0)
                Text("Phrase Detail").tag(1)
                Text("Commonality").tag(2)
            }
            .pickerStyle(.segmented)

            CompactCopyButton(text: vm.fullDebugText)
        }
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Agreement pills
            HStack(spacing: 12) {
                agreementPill(count: vm.unanimousCount, label: "Unanimous", color: .green)
                agreementPill(count: vm.divergentCount, label: "Divergent", color: .orange)
                agreementPill(count: vm.hintMismatchCount, label: "Hint Mismatch", color: .red)

                Spacer()

                CompactCopyButton(text: vm.summaryText)
            }

            // Match rates
            VStack(alignment: .leading, spacing: 8) {
                matchRateRow(
                    label: "Signature Match",
                    rate: vm.signatureMatchRate,
                    detail: "\(vm.unanimousCount)/\(vm.sentenceComparisons.count) sentences"
                )
                matchRateRow(
                    label: "Phrase Match",
                    rate: vm.phraseMatchRate,
                    detail: "phrase roles identical"
                )
                matchRateRow(
                    label: "Function Match",
                    rate: vm.functionMatchRate,
                    detail: "sentence function agreed"
                )
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Per-type consistency
            if !vm.perTypeConsistency.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-Type Consistency")
                        .font(.subheadline.bold())

                    ForEach(vm.perTypeConsistency, id: \.type) { tc in
                        HStack(spacing: 8) {
                            slotTypeBadge(tc.type)
                                .frame(width: 140, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemGray4))
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(tc.rate >= 0.9 ? Color.green : (tc.rate >= 0.6 ? Color.orange : Color.red))
                                        .frame(width: geo.size.width * tc.rate, height: 8)
                                }
                            }
                            .frame(height: 8)

                            Text(String(format: "%.0f%%", tc.rate * 100))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundColor(tc.rate >= 0.9 ? .green : (tc.rate >= 0.6 ? .orange : .red))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            // Hint mismatches
            let mismatched = vm.sentenceComparisons.filter { !$0.hintMismatchesAcrossRuns.isEmpty }
            if !mismatched.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hint Mismatches")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(mismatched.count) flagged")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    ForEach(mismatched) { comp in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(comp.sentenceIndex + 1)] \(comp.rawText)")
                                .font(.caption)
                                .lineLimit(1)
                            ForEach(comp.hintMismatchesAcrossRuns, id: \.self) { mismatch in
                                Text(mismatch)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(4)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

            // Confusable Pairs — save button (visible when divergent phrases exist)
            if vm.divergentCount > 0 {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await vm.extractAndSaveConfusablePairs()
                            confusableSaveConfirmed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                confusableSaveConfirmed = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: confusableSaveConfirmed ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                                .font(.system(size: 10))
                            Text(confusableSaveConfirmed ? "Saved" : "Save Confusable Pairs")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(confusableSaveConfirmed ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
                        .foregroundColor(confusableSaveConfirmed ? .green : .purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSavingPairs)

                    if vm.isSavingPairs {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    if let count = vm.savedPairsCount {
                        Text(count == 0 ? "No confusable pairs found" : "\(count) pairs saved")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Phrase Detail Tab

    private var phraseDetailTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Phrase Detail")
                    .font(.subheadline.bold())
                Spacer()
                CompactCopyButton(text: vm.phraseDetailText)
            }

            ForEach(vm.sentenceComparisons) { comp in
                phraseDetailRow(comp)
            }
        }
    }

    private func phraseDetailRow(_ comp: SlotFidelitySentenceComparison) -> some View {
        let isExpanded = expandedSentences.contains(comp.sentenceIndex)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSentences.remove(comp.sentenceIndex)
                    } else {
                        expandedSentences.insert(comp.sentenceIndex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("[\(comp.sentenceIndex + 1)]")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)

                    Text(comp.rawText)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Spacer()

                    // Run agreement dots
                    HStack(spacing: 3) {
                        ForEach(0..<comp.perRunSignatures.count, id: \.self) { runIdx in
                            let isMatch = comp.perRunSignatures[runIdx] == comp.dominantSignature
                            Circle()
                                .fill(isMatch ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(String(format: "%.0f%%", comp.signatureConsistency * 100))
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundColor(comp.runsAgreedOnSignature ? .green : .orange)
                        .frame(width: 36, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Per-run signatures
                    ForEach(0..<comp.perRunSignatures.count, id: \.self) { runIdx in
                        HStack(alignment: .top, spacing: 6) {
                            Text("Run \(runIdx + 1):")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .leading)

                            // Show phrases for this run
                            if runIdx < vm.runs.count, comp.sentenceIndex < vm.runs[runIdx].results.count {
                                let result = vm.runs[runIdx].results[comp.sentenceIndex]
                                FlowLayout(spacing: 3) {
                                    ForEach(result.phrases.indices, id: \.self) { pIdx in
                                        let phrase = result.phrases[pIdx]
                                        Text(phrase.role)
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(slotColor(phrase.role).opacity(0.15))
                                            .foregroundColor(slotColor(phrase.role))
                                            .cornerRadius(3)
                                    }
                                }
                            }
                        }
                    }

                    // Sentence function comparison
                    HStack(spacing: 4) {
                        Text("Function:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(0..<comp.perRunFunctions.count, id: \.self) { idx in
                            Text(comp.perRunFunctions[idx])
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(comp.runsAgreedOnFunction ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }

                    // Hint mismatches
                    if !comp.hintMismatchesAcrossRuns.isEmpty {
                        ForEach(comp.hintMismatchesAcrossRuns, id: \.self) { mismatch in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text(mismatch)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(.leading, 36)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(comp.runsAgreedOnSignature ? Color(.systemGray6) : Color.orange.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Commonality Tab

    private var commonalityTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Phrase Commonality Matrix")
                    .font(.subheadline.bold())
                Spacer()
                CompactCopyButton(text: vm.commonalityText)
            }

            ForEach(vm.sentenceComparisons) { comp in
                commonalityRow(comp)
            }
        }
    }

    private func commonalityRow(_ comp: SlotFidelitySentenceComparison) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("[\(comp.sentenceIndex + 1)]")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Text(comp.rawText)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", comp.signatureConsistency * 100))
                    .font(.caption2.bold())
                    .foregroundColor(comp.runsAgreedOnSignature ? .green : .orange)
            }

            // Phrase alignment visualization
            ForEach(comp.phraseAlignment) { align in
                HStack(spacing: 6) {
                    Text("\"\(String(align.phraseText.prefix(30)))\"")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 180, alignment: .leading)
                        .lineLimit(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 7))
                        .foregroundColor(.gray)

                    // Per-run role badges
                    HStack(spacing: 3) {
                        ForEach(Array(align.rolesPerRun.keys.sorted()), id: \.self) { runNum in
                            let role = align.rolesPerRun[runNum] ?? "missing"
                            Text(shortSlotName(role))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(align.isUnanimous ? Color.green.opacity(0.15) : slotColor(role).opacity(0.15))
                                .foregroundColor(align.isUnanimous ? .green : slotColor(role))
                                .cornerRadius(3)
                        }
                    }

                    Spacer()

                    let voteCount = align.rolesPerRun.values.filter { $0 == align.dominantRole }.count
                    let total = align.rolesPerRun.count
                    Text("\(voteCount)/\(total)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(align.isUnanimous ? .green : .orange)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private func agreementPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.caption.bold())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func matchRateRow(label: String, rate: Double, detail: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(String(format: "%.0f%%", rate * 100))
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(rate >= 0.9 ? .green : (rate >= 0.7 ? .orange : .red))
            Text("(\(detail))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func slotTypeBadge(_ type: String) -> some View {
        let displayName = SlotType(rawValue: type)?.displayName ?? type
        return Text(displayName)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(slotColor(type).opacity(0.12))
            .foregroundColor(slotColor(type))
            .cornerRadius(4)
    }

    private func slotColor(_ type: String) -> Color {
        switch type {
        case "geographic_location": return .blue
        case "visual_detail": return .cyan
        case "quantitative_claim": return .purple
        case "temporal_marker": return .orange
        case "actor_reference": return .green
        case "contradiction": return .red
        case "sensory_detail": return .mint
        case "rhetorical_question": return .pink
        case "evaluative_claim": return .yellow
        case "pivot_phrase": return .indigo
        case "direct_address": return .teal
        case "narrative_action": return .brown
        case "abstract_framing": return .gray
        case "comparison": return .purple
        case "empty_connector": return .gray
        case "factual_relay": return .cyan
        case "reaction_beat": return .pink
        case "visual_anchor": return .mint
        default: return .secondary
        }
    }

    private func shortSlotName(_ type: String) -> String {
        switch type {
        case "geographic_location": return "GEO"
        case "visual_detail": return "VIS"
        case "quantitative_claim": return "QNT"
        case "temporal_marker": return "TMP"
        case "actor_reference": return "ACT"
        case "contradiction": return "CTR"
        case "sensory_detail": return "SNS"
        case "rhetorical_question": return "RHQ"
        case "evaluative_claim": return "EVL"
        case "pivot_phrase": return "PVT"
        case "direct_address": return "DIR"
        case "narrative_action": return "NAR"
        case "abstract_framing": return "ABS"
        case "comparison": return "CMP"
        case "empty_connector": return "EMT"
        case "factual_relay": return "FCT"
        case "reaction_beat": return "RXN"
        case "visual_anchor": return "VAN"
        case "other": return "OTH"
        case "missing": return "---"
        default: return String(type.prefix(3)).uppercased()
        }
    }
}
