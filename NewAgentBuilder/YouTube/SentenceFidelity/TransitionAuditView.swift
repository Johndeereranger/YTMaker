//
//  TransitionAuditView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/20/26.
//
//  Diagnostic tool for auditing isTransition tags across all sentence fidelity data.
//  Helps identify forward transitions vs dismissal transitions vs misclassified.
//

import SwiftUI

// MARK: - Classification Enum

enum TransitionClassification: String, CaseIterable {
    case unclassified = "Unclassified"
    case forward = "Forward"
    case dismissal = "Dismissal"
    case unclear = "Unclear"

    var color: Color {
        switch self {
        case .unclassified: return .gray
        case .forward: return .green
        case .dismissal: return .orange
        case .unclear: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .unclassified: return "questionmark.circle"
        case .forward: return "arrow.right.circle.fill"
        case .dismissal: return "arrow.uturn.backward.circle.fill"
        case .unclear: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Audit Item

struct AuditItem: Identifiable {
    let id = UUID()
    let sentenceIndex: Int
    let text: String
    let videoTitle: String
    let videoId: String
    let isTransition: Bool
    let hasFirstPerson: Bool
    let stance: String
    let perspective: String
    let contextBefore: [String]   // up to 3 sentences before
    let contextAfter: [String]    // up to 3 sentences after
    var classification: TransitionClassification = .unclassified
}

// MARK: - Audit Tab

enum AuditTab: String, CaseIterable {
    case transitions = "Transitions"
    case digressionEntries = "Entries"
    case regexTest = "Regex"
    case search = "Search"
}

// MARK: - Regex Tier

enum RegexTier: String, CaseIterable {
    case dismissal = "Tier 1: Dismissal"
    case misclassified = "Tier 2: Misclassified"
    case forward = "Tier 3: Forward"
    case noMatch = "No Match"

    var color: Color {
        switch self {
        case .dismissal: return .orange
        case .misclassified: return .red
        case .forward: return .green
        case .noMatch: return .gray
        }
    }

    var description: String {
        switch self {
        case .dismissal: return "Sentences that close a digression and return to the main narrative (\"Anyway, that's beside the point\", \"back to the story\")"
        case .misclassified: return "Narrative continuations incorrectly tagged as transitions (\"So the CIA...\", \"So he crosses...\")"
        case .forward: return "Genuine forward transitions that advance the narrative to a new topic (\"Now let's talk about...\", \"Moving on to...\", \"Next up...\")"
        case .noMatch: return "No regex matched — needs manual review to determine if forward, dismissal, or misclassified"
        }
    }
}

struct RegexMatch: Identifiable {
    let id = UUID()
    let item: AuditItem
    let tier: RegexTier
    let matchedPattern: String
}

// MARK: - Regex Classifier

struct TransitionRegexClassifier {

    // Tier 1: Dismissal — closing a digression, returning to main thread
    static let dismissalPatterns: [(pattern: String, label: String)] = [
        (#"^anyway,?\s+(that'?s\s+beside\s+the\s+point|story\s+for\s+another\s+day|that'?s\s+not\s+the\s+point|that'?s\s+another\s+story|i\s+digress|back\s+to|let'?s\s+get\s+back|moving\s+on(?!\s+to))"#, "anyway + dismissal"),
        (#"^(let'?s\s+get\s+back\s+to|back\s+to\s+(the\s+)?(story|topic|video|map|point|main))"#, "back to [topic]"),
        (#"^(with\s+that,?\s+let'?s\s+(get\s+back|dive\s+back|return))"#, "with that, let's get back"),
        (#"^(now\s+back\s+to)"#, "now back to"),
        (#"^(all\s*right,?\s+let'?s\s+get\s+back\s+to)"#, "alright let's get back"),
        (#"^(okay,?\s+(let'?s\s+get\s+back|i'?m\s+gonna\s+get\s+back))"#, "okay let's get back"),
        (#"^(where\s+were\s+we)"#, "where were we"),
        (#"^(but\s+(i\s+digress|back\s+to|anyway))"#, "but I digress / but anyway"),
    ]

    // Tier 2: Misclassified — narrative continuations that shouldn't be transitions
    static let misclassifiedPatterns: [(pattern: String, label: String)] = [
        (#"^so\s+(the|he|she|they|it|his|her|this|that|a|an|one|two|three|four|five|El|within|basically|fast|soon|now|in\s+the|over\s+the|at\s+the|around|after|before|by\s+the|from|when|while|during|eventually|finally|instead)\s"#, "so + narrative continuation"),
        (#"^(and\s+so\s+(the|he|she|they|it|his|her|this|that))\s"#, "and so + narrative"),
    ]

    // Tier 3: Forward — genuine forward transitions that advance to a new topic
    static let forwardPatterns: [(pattern: String, label: String)] = [
        // Explicit topic shifts
        (#"^now\s+let'?s\s+(talk|dive|look|get\s+into|move|discuss|turn|jump|shift|go)"#, "now let's [verb]"),
        (#"^let'?s\s+(talk|dive|look|get\s+into|move|discuss|turn|jump|shift|go)"#, "let's [verb]"),
        (#"^moving\s+on\s+(to|from)"#, "moving on to/from"),
        (#"^next\s+up"#, "next up"),
        (#"^(so\s+)?speaking\s+of\s+(which|that|this)"#, "speaking of"),
        (#"^(so\s+)?the\s+next\s+(thing|part|step|piece|chapter|section|topic)"#, "the next [thing]"),

        // Pivots with structural markers
        (#"^(okay|ok|alright|all\s*right),?\s+(so\s+)?let'?s\s+(talk|dive|look|get\s+into|move|discuss|turn|jump|shift|go)"#, "okay, let's [verb]"),
        (#"^(okay|ok|alright|all\s*right),?\s+(so\s+)?(now|here'?s|this\s+is\s+where|the\s+next)"#, "okay, now/here's"),
        (#"^(okay|ok|alright|all\s*right),?\s+so\s+moving"#, "okay so moving"),
        (#"^now,?\s+(here'?s|this\s+is\s+where|the\s+interesting|the\s+crazy|the\s+wild|the\s+important|the\s+big|the\s+real)"#, "now, here's/this is where"),
        (#"^(so\s+)?here'?s\s+(the|where|what|how)"#, "here's the/where/what"),

        // Numbered/sequential markers
        (#"^(first|second|third|fourth|fifth|number\s+one|number\s+two|number\s+three|step\s+one|step\s+two|part\s+one|part\s+two|reason\s+number)"#, "ordinal marker"),

        // Explicit shift language
        (#"^(but\s+)?(now|so)\s+let\s+me\s+tell\s+you\s+(about|what|how|why)"#, "let me tell you about"),
        (#"^(but\s+)?let\s+me\s+(explain|show|walk\s+you|break\s+down|give\s+you)"#, "let me explain/show"),
        (#"^which\s+(brings|leads|takes)\s+(us|me)\s+to"#, "which brings us to"),
        (#"^(and\s+)?(this|that)\s+(brings|leads|takes)\s+(us|me)\s+to"#, "this brings us to"),
        (#"^(and\s+)?this\s+is\s+where\s+(it|things|the\s+story|everything)"#, "this is where"),

        // "But" + new topic introduction
        (#"^but\s+here'?s\s+(the|where|what)"#, "but here's"),
        (#"^but\s+(now|then)\s+"#, "but now/then"),

        // Fast forward / time skip
        (#"^(so\s+)?(fast\s+forward|flash\s+forward|cut\s+to)"#, "fast forward / cut to"),
    ]

    static func classify(_ text: String) -> (tier: RegexTier, matchedPattern: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Tier 1: Dismissal
        for (pattern, label) in dismissalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    return (.dismissal, label)
                }
            }
        }

        // Tier 2: Misclassified
        for (pattern, label) in misclassifiedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    return (.misclassified, label)
                }
            }
        }

        // Tier 3: Forward
        for (pattern, label) in forwardPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    return (.forward, label)
                }
            }
        }

        // No match
        return (.noMatch, "no regex matched")
    }
}

// MARK: - View Model

@MainActor
class TransitionAuditViewModel: ObservableObject {

    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?

    @Published var transitionItems: [AuditItem] = []
    @Published var digressionEntryItems: [AuditItem] = []

    @Published var totalSentencesScanned = 0
    @Published var totalVideosScanned = 0

    @Published var selectedTab: AuditTab = .transitions

    // Search
    @Published var searchText = ""
    @Published var searchResults: [AuditItem] = []
    private var allTestRuns: [SentenceFidelityTest] = []

    private let firebaseService = SentenceFidelityFirebaseService.shared

    private let digressionPrefixes = [
        "wait,", "wait ", "wait.", "hold on", "side note",
        "actually, funny story", "oh, and", "oh and",
        "by the way", "funny enough", "fun fact",
        "quick aside", "real quick", "before i forget"
    ]

    // MARK: - Load

    func loadData() async {
        isLoading = true
        loadingMessage = "Fetching sentence data from Firebase..."
        errorMessage = nil

        do {
            let runs = try await firebaseService.getAllTestRuns()
            loadingMessage = "Scanning \(runs.count) videos..."
            scanSentences(from: runs)
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
        loadingMessage = ""
    }

    private func scanSentences(from runs: [SentenceFidelityTest]) {
        allTestRuns = runs
        var transitions: [AuditItem] = []
        var entries: [AuditItem] = []
        var totalSentences = 0

        for test in runs {
            let sentences = test.sentences
            totalSentences += sentences.count

            for i in 0..<sentences.count {
                let sentence = sentences[i]

                // Grab up to 10 before (regex dismissal uses all 10, transitions tab shows 3) and 5 after
                let beforeStart = max(0, i - 10)
                let afterEnd = min(sentences.count - 1, i + 5)
                let before = beforeStart < i ? (beforeStart..<i).map { sentences[$0].text } : []
                let after = i + 1 <= afterEnd ? ((i + 1)...afterEnd).map { sentences[$0].text } : []

                let item = AuditItem(
                    sentenceIndex: sentence.sentenceIndex,
                    text: sentence.text,
                    videoTitle: test.videoTitle,
                    videoId: test.videoId,
                    isTransition: sentence.isTransition,
                    hasFirstPerson: sentence.hasFirstPerson,
                    stance: sentence.stance,
                    perspective: sentence.perspective,
                    contextBefore: before,
                    contextAfter: after
                )

                if sentence.isTransition {
                    transitions.append(item)
                }

                let lower = sentence.text.lowercased().trimmingCharacters(in: .whitespaces)
                if digressionPrefixes.contains(where: { lower.hasPrefix($0) }) {
                    entries.append(item)
                }
            }
        }

        transitionItems = transitions
        digressionEntryItems = entries
        totalSentencesScanned = totalSentences
        totalVideosScanned = runs.count
    }

    // MARK: - Classification

    func classify(_ item: AuditItem, as classification: TransitionClassification) {
        if let index = transitionItems.firstIndex(where: { $0.id == item.id }) {
            transitionItems[index].classification = classification
        }
    }

    // MARK: - Stats

    var forwardCount: Int { transitionItems.filter { $0.classification == .forward }.count }
    var dismissalCount: Int { transitionItems.filter { $0.classification == .dismissal }.count }
    var unclearCount: Int { transitionItems.filter { $0.classification == .unclear }.count }
    var classifiedCount: Int { transitionItems.filter { $0.classification != .unclassified }.count }

    var digressionEntriesAlsoTransition: Int {
        digressionEntryItems.filter { $0.isTransition }.count
    }

    // MARK: - Regex Classification

    @Published var regexResults: [RegexMatch] = []

    var regexDismissals: [RegexMatch] { regexResults.filter { $0.tier == .dismissal } }
    var regexMisclassified: [RegexMatch] { regexResults.filter { $0.tier == .misclassified } }
    var regexForward: [RegexMatch] { regexResults.filter { $0.tier == .forward } }
    var regexNoMatch: [RegexMatch] { regexResults.filter { $0.tier == .noMatch } }

    func runRegexClassification() {
        regexResults = transitionItems.map { item in
            let result = TransitionRegexClassifier.classify(item.text)
            return RegexMatch(item: item, tier: result.tier, matchedPattern: result.matchedPattern)
        }
    }

    func generateRegexReport(tier: RegexTier? = nil) -> String {
        let items = tier.map { t in regexResults.filter { $0.tier == t } } ?? regexResults
        var lines: [String] = []

        let title = tier?.rawValue ?? "All Tiers"
        lines.append("=== REGEX CLASSIFICATION: \(title) ===")
        lines.append("Date: \(Date().formatted())")
        lines.append("Total transitions: \(transitionItems.count)")
        lines.append("Tier 1 Dismissal: \(regexDismissals.count)")
        lines.append("Tier 2 Misclassified: \(regexMisclassified.count)")
        lines.append("Tier 3 Forward: \(regexForward.count)")
        lines.append("No Match: \(regexNoMatch.count)")
        lines.append("")

        if let tier = tier {
            lines.append("--- \(tier.rawValue) ---")
            lines.append(tier.description)
            lines.append("")
        }

        let byVideo = Dictionary(grouping: items, by: \.item.videoTitle)
        for (title, matches) in byVideo.sorted(by: { $0.key < $1.key }) {
            lines.append("\(title):")
            for match in matches.sorted(by: { $0.item.sentenceIndex < $1.item.sentenceIndex }) {
                let tierLabel = tier == nil ? " [\(match.tier.rawValue)]" : ""
                lines.append("  #\(match.item.sentenceIndex): \(match.item.text)\(tierLabel)")
                lines.append("    Matched: \(match.matchedPattern)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Phrase Search

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let lowerQuery = query.lowercased()
        var results: [AuditItem] = []

        for test in allTestRuns {
            let sentences = test.sentences
            for i in 0..<sentences.count {
                let sentence = sentences[i]
                guard sentence.text.lowercased().contains(lowerQuery) else { continue }

                let beforeStart = max(0, i - 5)
                let afterEnd = min(sentences.count - 1, i + 5)
                let before = beforeStart < i ? (beforeStart..<i).map { sentences[$0].text } : []
                let after = i + 1 <= afterEnd ? ((i + 1)...afterEnd).map { sentences[$0].text } : []

                results.append(AuditItem(
                    sentenceIndex: sentence.sentenceIndex,
                    text: sentence.text,
                    videoTitle: test.videoTitle,
                    videoId: test.videoId,
                    isTransition: sentence.isTransition,
                    hasFirstPerson: sentence.hasFirstPerson,
                    stance: sentence.stance,
                    perspective: sentence.perspective,
                    contextBefore: before,
                    contextAfter: after
                ))
            }
        }

        searchResults = results
    }

    // MARK: - Report

    func generateReport() -> String {
        var lines: [String] = []
        lines.append("=== TRANSITION AUDIT REPORT ===")
        lines.append("Date: \(Date().formatted())")
        lines.append("Videos scanned: \(totalVideosScanned)")
        lines.append("Total sentences: \(totalSentencesScanned)")
        lines.append("Transitions found: \(transitionItems.count)")
        lines.append("Digression entries found: \(digressionEntryItems.count)")
        lines.append("")

        lines.append("--- Classification Summary ---")
        lines.append("Classified: \(classifiedCount) / \(transitionItems.count)")
        lines.append("Forward: \(forwardCount)")
        lines.append("Dismissal: \(dismissalCount)")
        lines.append("Unclear: \(unclearCount)")
        lines.append("")

        lines.append("--- Transition Sentences ---")
        let transitionsByVideo = Dictionary(grouping: transitionItems, by: \.videoTitle)
        for (title, items) in transitionsByVideo.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            lines.append("\(title):")
            for item in items.sorted(by: { $0.sentenceIndex < $1.sentenceIndex }) {
                let tag = item.classification == .unclassified ? "" : " [\(item.classification.rawValue.uppercased())]"
                lines.append("  #\(item.sentenceIndex): \(item.text)\(tag)")
            }
        }
        lines.append("")

        lines.append("--- Digression Entry Candidates ---")
        let entriesByVideo = Dictionary(grouping: digressionEntryItems, by: \.videoTitle)
        for (title, items) in entriesByVideo.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            lines.append("\(title):")
            for item in items.sorted(by: { $0.sentenceIndex < $1.sentenceIndex }) {
                let alsoTransition = item.isTransition ? " [ALSO TRANSITION]" : ""
                lines.append("  #\(item.sentenceIndex): \(item.text)\(alsoTransition)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - View

struct TransitionAuditView: View {
    @StateObject private var viewModel = TransitionAuditViewModel()
    @State private var copiedButton: String?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if viewModel.totalSentencesScanned == 0 {
                emptyView
            } else {
                resultsView
            }
        }
        .navigationTitle("Transition Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    private func copyWithFeedback(_ key: String, text: String) {
        UIPasteboard.general.string = text
        copiedButton = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if copiedButton == key { copiedButton = nil }
        }
    }

    private func copyButton(_ key: String, label: String, color: Color, text: @escaping () -> String) -> some View {
        let isCopied = copiedButton == key
        return Button {
            copyWithFeedback(key, text: text())
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                Text(isCopied ? "Copied!" : label)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isCopied ? Color.green : color)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(viewModel.loadingMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await viewModel.loadData() }
            }
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No sentence fidelity data found.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Run sentence tagging on videos first.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsSection
                    .padding(.horizontal)

                copyButtonsSection
                    .padding(.horizontal)

                Picker("Tab", selection: $viewModel.selectedTab) {
                    ForEach(AuditTab.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch viewModel.selectedTab {
                case .transitions:
                    transitionsSection
                case .digressionEntries:
                    entriesSection
                case .regexTest:
                    regexTestSection
                case .search:
                    searchSection
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Copy Buttons

    private var copyButtonsSection: some View {
        VStack(spacing: 8) {
            // Row 1: Audit report
            copyButton("report", label: "Copy Audit Report", color: .blue) {
                viewModel.generateReport()
            }

            // Row 2: Regex buttons
            if !viewModel.regexResults.isEmpty {
                HStack(spacing: 8) {
                    copyButton("regex-all", label: "All Regex", color: .purple) {
                        viewModel.generateRegexReport()
                    }
                    copyButton("regex-t1", label: "Dismissal (\(viewModel.regexDismissals.count))", color: .orange) {
                        viewModel.generateRegexReport(tier: .dismissal)
                    }
                }
                HStack(spacing: 8) {
                    copyButton("regex-t2", label: "Misclassified (\(viewModel.regexMisclassified.count))", color: .red) {
                        viewModel.generateRegexReport(tier: .misclassified)
                    }
                    copyButton("regex-t3", label: "Forward (\(viewModel.regexForward.count))", color: .green) {
                        viewModel.generateRegexReport(tier: .forward)
                    }
                }
                HStack(spacing: 8) {
                    copyButton("regex-t4", label: "No Match (\(viewModel.regexNoMatch.count))", color: .gray) {
                        viewModel.generateRegexReport(tier: .noMatch)
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                statBox(label: "Videos", value: "\(viewModel.totalVideosScanned)", color: .blue)
                statBox(label: "Sentences", value: "\(viewModel.totalSentencesScanned)", color: .blue)
                statBox(label: "Transitions", value: "\(viewModel.transitionItems.count)", color: .orange)
                statBox(label: "Entries", value: "\(viewModel.digressionEntryItems.count)", color: .purple)
            }

            if viewModel.classifiedCount > 0 {
                HStack(spacing: 16) {
                    statBox(label: "Forward", value: "\(viewModel.forwardCount)", color: .green)
                    statBox(label: "Dismissal", value: "\(viewModel.dismissalCount)", color: .orange)
                    statBox(label: "Unclear", value: "\(viewModel.unclearCount)", color: .yellow)
                    statBox(label: "Classified", value: "\(viewModel.classifiedCount)/\(viewModel.transitionItems.count)", color: .gray)
                }
            }
        }
    }

    private func statBox(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Transitions List

    private var transitionsSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.transitionItems) { item in
                transitionRow(item)
            }
        }
        .padding(.horizontal)
    }

    private func transitionRow(_ item: AuditItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Context window (show last 3 of stored context)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(item.contextBefore.suffix(3).enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Highlighted transition sentence
                Text(item.text)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(6)

                ForEach(Array(item.contextAfter.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Text(item.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("#\(item.sentenceIndex)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                classificationChip(item: item, classification: .forward)
                classificationChip(item: item, classification: .dismissal)
                classificationChip(item: item, classification: .unclear)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    private func classificationChip(item: AuditItem, classification: TransitionClassification) -> some View {
        let isSelected = item.classification == classification
        return Button {
            viewModel.classify(item, as: classification)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: classification.icon)
                    .font(.caption2)
                Text(classification.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? classification.color : classification.color.opacity(0.15))
            .foregroundColor(isSelected ? .white : classification.color)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Digression Entries List

    private var entriesSection: some View {
        LazyVStack(spacing: 12) {
            if viewModel.digressionEntriesAlsoTransition > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(viewModel.digressionEntriesAlsoTransition) entries also tagged isTransition")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }

            ForEach(viewModel.digressionEntryItems) { item in
                entryRow(item)
            }
        }
        .padding(.horizontal)
    }

    private func entryRow(_ item: AuditItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.text)
                    .font(.body)
                    .lineLimit(4)

                if item.isTransition {
                    Text("TRANSITION")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }

            HStack {
                Text(item.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("#\(item.sentenceIndex)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                if item.hasFirstPerson {
                    Text("1P")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }

                Text(item.perspective)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(item.stance)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Regex Test Section

    private var regexTestSection: some View {
        LazyVStack(spacing: 16) {
            if viewModel.regexResults.isEmpty {
                Button {
                    viewModel.runRegexClassification()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Regex Classification")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            } else {
                // Summary
                regexSummarySection

                // Results by tier
                ForEach(RegexTier.allCases, id: \.self) { tier in
                    regexTierSection(tier)
                }
            }
        }
        .padding(.horizontal)
    }

    private var regexSummarySection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                statBox(label: "Dismissal", value: "\(viewModel.regexDismissals.count)", color: .orange)
                statBox(label: "Misclassified", value: "\(viewModel.regexMisclassified.count)", color: .red)
            }
            HStack(spacing: 16) {
                statBox(label: "Forward", value: "\(viewModel.regexForward.count)", color: .green)
                statBox(label: "No Match", value: "\(viewModel.regexNoMatch.count)", color: .gray)
            }
        }
    }

    private func regexTierSection(_ tier: RegexTier) -> some View {
        let matches = viewModel.regexResults.filter { $0.tier == tier }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(tier.color)
                    .frame(width: 10, height: 10)
                Text("\(tier.rawValue) (\(matches.count))")
                    .font(.headline)
            }

            Text(tier.description)
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(matches) { match in
                regexMatchRow(match)
            }
        }
    }

    private func regexMatchRow(_ match: RegexMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Dismissal tier: show 10 sentences before for context
            if match.tier == .dismissal && !match.item.contextBefore.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(match.item.contextBefore.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // Highlighted dismissal sentence
                    Text(match.item.text)
                        .font(.body)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.25))
                        .cornerRadius(6)
                }
            } else {
                Text(match.item.text)
                    .font(.body)
                    .lineLimit(3)
            }

            HStack {
                Text(match.item.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("#\(match.item.sentenceIndex)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Text(match.matchedPattern)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(match.tier.color.opacity(0.15))
                    .foregroundColor(match.tier.color)
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search sentences...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { viewModel.performSearch() }

                Button {
                    viewModel.performSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .padding(8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            if !viewModel.searchResults.isEmpty {
                Text("\(viewModel.searchResults.count) matches for \"\(viewModel.searchText)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.searchResults) { item in
                    searchResultRow(item)
                }
            }
            .padding(.horizontal)
        }
    }

    private func searchResultRow(_ item: AuditItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 5 sentences before
            ForEach(Array(item.contextBefore.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Highlighted matched sentence
            Text(item.text)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(6)

            // 5 sentences after
            ForEach(Array(item.contextAfter.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Metadata
            HStack {
                Text(item.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("#\(item.sentenceIndex)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                if item.isTransition {
                    Text("TRANSITION")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}
