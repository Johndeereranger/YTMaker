//
//  OpenerMatcherView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/11/26.
//
//  Opener Matcher tab for MarkovScriptWriter.
//  Reads corpus data from the coordinator but owns its own state.
//  Runs a single LLM call to match ramblings against corpus openings,
//  returning 3 strategies × 2 matches each.
//

import SwiftUI

struct OpenerMatcherView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    // View-owned state — not on the coordinator
    @State private var result: OpenerMatchResult?
    @State private var isRunning = false
    @State private var runningMessage = ""
    @State private var runError: String?
    @State private var expandedMatchIds: Set<UUID> = []
    @State private var showAntiMatches = false
    @State private var showDebug = false

    // Step 2: Gist Filter state
    @State private var gistFilterResult: OpenerGistFilterResult?
    @State private var isFiltering = false
    @State private var filteringMessage = ""
    @State private var filterError: String?
    @State private var showFilterDebug = false

    // Step 3: Draft state
    @State private var draftResult: OpenerDraftResult?
    @State private var isDrafting = false
    @State private var draftingMessage = ""
    @State private var draftError: String?
    @State private var showDraftDebug = false

    // Step 4: Rewrite state
    @State private var rewriteResult: OpenerRewriteResult?
    @State private var isRewriting = false
    @State private var rewritingMessage = ""
    @State private var rewriteError: String?
    @State private var showRewriteDebug = false
    @State private var expandedRewriteAnalysisIds: Set<UUID> = []

    private static let persistenceKey = "OpenerMatcher.LastResult"
    private static let gistFilterPersistenceKey = "OpenerMatcher.LastGistFilterResult"
    private static let draftPersistenceKey = "OpenerMatcher.LastDraftResult"
    private static let rewritePersistenceKey = "OpenerMatcher.LastRewriteResult"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result {
                    resultView(result)
                } else if isRunning {
                    loadingView
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .onAppear {
            loadPersistedResult()
        }
    }

    // MARK: - Persistence (own UserDefaults key)

    private func loadPersistedResult() {
        guard result == nil,
              let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let saved = try? JSONDecoder().decode(OpenerMatchResult.self, from: data) else { return }
        result = saved

        // Also load gist filter result
        if gistFilterResult == nil,
           let filterData = UserDefaults.standard.data(forKey: Self.gistFilterPersistenceKey),
           let savedFilter = try? JSONDecoder().decode(OpenerGistFilterResult.self, from: filterData) {
            gistFilterResult = savedFilter
        }

        // Also load draft result
        if draftResult == nil,
           let draftData = UserDefaults.standard.data(forKey: Self.draftPersistenceKey),
           let savedDraft = try? JSONDecoder().decode(OpenerDraftResult.self, from: draftData) {
            draftResult = savedDraft
        }

        // Also load rewrite result
        if rewriteResult == nil,
           let rewriteData = UserDefaults.standard.data(forKey: Self.rewritePersistenceKey),
           let savedRewrite = try? JSONDecoder().decode(OpenerRewriteResult.self, from: rewriteData) {
            rewriteResult = savedRewrite
        }
    }

    private func persistResult(_ r: OpenerMatchResult) {
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func persistGistFilterResult(_ r: OpenerGistFilterResult) {
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.gistFilterPersistenceKey)
        }
    }

    private func persistDraftResult(_ r: OpenerDraftResult) {
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.draftPersistenceKey)
        }
    }

    private func persistRewriteResult(_ r: OpenerRewriteResult) {
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.rewritePersistenceKey)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "theatermask.and.paintbrush")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Opener Matcher")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Find the best structural opening template from the creator's corpus for your rambling material.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Status badges
            if !coordinator.corpusVideos.isEmpty {
                Text("\(coordinator.corpusVideos.count) corpus videos loaded")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            if !coordinator.session.ramblingGists.isEmpty {
                Text("\(coordinator.session.ramblingGists.count) gists loaded")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button {
                runOpenerMatch()
            } label: {
                Label("Run Opener Match", systemImage: "sparkles")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.corpusVideos.isEmpty || coordinator.session.ramblingGists.isEmpty)

            if coordinator.corpusVideos.isEmpty {
                Text("Load corpus first (Input tab)")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if coordinator.session.ramblingGists.isEmpty {
                Text("Import gists from Gist Writer first")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let error = runError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.2)
            Text(runningMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Run Logic (self-contained)

    private func runOpenerMatch() {
        let videos = coordinator.corpusVideos
        let seqs = coordinator.sequences
        let titles = coordinator.videoTitles
        let ramblingText = coordinator.session.rawRamblingText
        let gists = coordinator.session.ramblingGists

        isRunning = true
        runningMessage = "Computing opening patterns..."
        runError = nil

        Task { @MainActor in
            // Step 1: Compute opening patterns from sequence data
            let patterns = OpeningPatternService.computeOpeningPatterns(
                sequences: seqs,
                titles: titles,
                depth: 2,
                minFrequency: 3
            )

            guard !patterns.isEmpty else {
                runError = "No opening patterns found with 3+ videos. Need more rhetorical sequences."
                isRunning = false
                return
            }

            print("📊 Opener Matcher: \(patterns.count) patterns found")
            for p in patterns {
                print("   \(p.label): \(p.frequency) videos")
            }

            // Step 2: Build corpus openings for sample extraction
            let allOpenings = buildCorpusOpenings(videos: videos, sequences: seqs, titles: titles, depth: 2)
            let openingsByVideoId = Dictionary(uniqueKeysWithValues: allOpenings.map { ($0.videoId, $0) })

            // Step 3: For each pattern, get 2 sample openings
            var patternSamples: [String: [OpenerMatcherPromptEngine.CorpusOpening]] = [:]
            for pattern in patterns {
                let sampleVideos = pattern.videos.prefix(2)
                let samples = sampleVideos.compactMap { openingsByVideoId[$0.videoId] }
                patternSamples[pattern.label] = samples
            }

            // Token budget estimate
            let totalWords = patternSamples.values.flatMap { $0 }.reduce(0) { sum, o in
                sum + o.sectionTexts.reduce(0) { $0 + $1.text.split(separator: " ").count }
            } + ramblingText.split(separator: " ").count
            let tokenEstimate = Int(Double(totalWords) * 1.3)
            print("📊 Opener Matcher: \(patterns.count) patterns, ~\(totalWords) words, ~\(tokenEstimate) estimated input tokens")

            runningMessage = "Matching patterns (\(patterns.count) patterns, ~\(tokenEstimate) tokens)..."

            // Step 4: Build prompt
            let (systemPrompt, userPrompt) = OpenerMatcherPromptEngine.buildPatternPrompt(
                patterns: patterns,
                patternSamples: patternSamples,
                rawRamblingText: ramblingText,
                ramblingGists: gists
            )

            // Step 5: Call LLM
            let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
            let bundle = await adapter.generate_response_bundle(
                prompt: userPrompt,
                promptBackgroundInfo: systemPrompt,
                params: ["temperature": 0.3, "max_tokens": 4000]
            )

            let rawResponse = bundle?.content ?? ""
            let telemetry = bundle.map { SectionTelemetry(from: $0) }

            if let telemetry {
                print("📊 Opener Matcher TOKENS — In: \(telemetry.promptTokens) | Out: \(telemetry.completionTokens) | Total: \(telemetry.totalTokens)")
            }

            // Step 6: Parse response
            let validLabels = Set(patterns.map(\.label))
            do {
                let parsed = try OpenerMatcherPromptEngine.parsePatternResponse(
                    rawResponse: rawResponse,
                    validPatternLabels: validLabels
                )

                // Step 7: Expand selected patterns to N matches
                let patternsByLabel = Dictionary(uniqueKeysWithValues: patterns.map { ($0.label, $0) })

                let strategies = parsed.strategies.map { strategy -> OpenerStrategy in
                    let pattern = patternsByLabel[strategy.pattern_label]!
                    let matches = pattern.videos.enumerated().map { (idx, video) -> OpenerRankedMatch in
                        OpenerRankedMatch(
                            id: UUID(),
                            rank: idx + 1,
                            videoId: video.videoId,
                            videoTitle: titles[video.videoId] ?? video.title,
                            matchReasoning: strategy.match_reasoning,
                            openingStrategySummary: "Part of \(strategy.pattern_label) pattern (\(pattern.frequency) videos)"
                        )
                    }
                    return OpenerStrategy(
                        id: UUID(),
                        strategyId: strategy.strategy_id,
                        strategyName: strategy.strategy_name,
                        strategyDescription: strategy.strategy_description,
                        matches: matches,
                        patternLabel: strategy.pattern_label
                    )
                }

                let matchResult = OpenerMatchResult(
                    id: UUID(),
                    ramblingProfile: RamblingProfile(
                        entryEnergy: parsed.rambling_profile.entry_energy,
                        emotionalTrajectory: parsed.rambling_profile.emotional_trajectory,
                        stakesShape: parsed.rambling_profile.stakes_shape,
                        complexityLoad: parsed.rambling_profile.complexity_load,
                        speakerPosture: parsed.rambling_profile.speaker_posture
                    ),
                    strategies: strategies,
                    antiMatches: [],
                    promptVersion: OpenerMatcherPromptEngine.PROMPT_VERSION,
                    analyzedAt: Date(),
                    corpusVideoCount: allOpenings.count,
                    inputTokenEstimate: tokenEstimate,
                    promptSent: userPrompt,
                    systemPromptSent: systemPrompt,
                    rawResponse: rawResponse,
                    telemetry: telemetry
                )

                result = matchResult
                persistResult(matchResult)

                // Cascade invalidation: clear downstream results
                gistFilterResult = nil
                draftResult = nil
                rewriteResult = nil
                UserDefaults.standard.removeObject(forKey: Self.gistFilterPersistenceKey)
                UserDefaults.standard.removeObject(forKey: Self.draftPersistenceKey)
                UserDefaults.standard.removeObject(forKey: Self.rewritePersistenceKey)

                let totalMatches = strategies.reduce(0) { $0 + $1.matches.count }
                print("✅ Opener Matcher: \(strategies.count) strategies, \(totalMatches) total matches")

            } catch {
                print("❌ Opener Matcher parse error: \(error.localizedDescription)")
                print("📄 Raw response (\(rawResponse.count) chars): \(rawResponse.prefix(500))...")
                runError = "Opener match failed: \(error.localizedDescription)"
            }

            isRunning = false
            runningMessage = ""
        }
    }

    /// Extract opening sections from each corpus video (first `depth` rhetorical moves).
    private func buildCorpusOpenings(
        videos: [String: YouTubeVideo],
        sequences: [String: RhetoricalSequence],
        titles: [String: String],
        depth: Int
    ) -> [OpenerMatcherPromptEngine.CorpusOpening] {

        var openings: [OpenerMatcherPromptEngine.CorpusOpening] = []

        for (videoId, seq) in sequences {
            guard let video = videos[videoId],
                  let transcript = video.transcript else { continue }

            let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            guard !sortedMoves.isEmpty else { continue }

            let slice = Array(sortedMoves.prefix(depth))
            let sentences = SentenceParser.parse(transcript)

            var sectionTexts: [(label: String, text: String)] = []

            // Check if any move in the slice has sentence boundaries
            let hasAnySentenceBoundaries = slice.contains { $0.startSentence != nil && $0.endSentence != nil }

            if hasAnySentenceBoundaries {
                // Normal path: extract text per move using sentence boundaries
                for move in slice {
                    let label = move.moveType.displayName
                    var textLines: [String] = []

                    if let start = move.startSentence, let end = move.endSentence,
                       !sentences.isEmpty, start < sentences.count {
                        let safeEnd = min(end, sentences.count - 1)
                        for i in start...safeEnd {
                            textLines.append(sentences[i])
                        }
                    } else {
                        textLines.append(move.briefDescription)
                    }

                    sectionTexts.append((label: label, text: textLines.joined(separator: " ")))
                }
            } else {
                // Fallback: no sentence boundaries on moves — grab first ~150 words
                // of transcript directly (~60 seconds at 2.5 words/sec)
                let targetWordCount = 150
                var wordsSoFar = 0
                var collectedSentences: [String] = []

                for sentence in sentences {
                    collectedSentences.append(sentence)
                    wordsSoFar += sentence.split(separator: " ").count
                    if wordsSoFar >= targetWordCount { break }
                }

                let moveLabels = slice.map { $0.moveType.displayName }.joined(separator: " → ")
                sectionTexts.append((label: moveLabels, text: collectedSentences.joined(separator: " ")))
            }

            openings.append(OpenerMatcherPromptEngine.CorpusOpening(
                videoId: videoId,
                title: titles[videoId] ?? videoId,
                sectionTexts: sectionTexts
            ))
        }

        return openings
    }

    private func selectOpener(videoId: String) {
        result?.selectedVideoId = videoId
        if let result {
            persistResult(result)
        }
    }

    // MARK: - Results

    private func resultView(_ result: OpenerMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with re-run
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opener Match Results")
                        .font(.headline)
                    Text("\(result.corpusVideoCount) videos analyzed \u{2022} \(result.strategies.flatMap(\.matches).count) matches across \(result.strategies.count) strategies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                CompactCopyButton(text: buildFullResultsText(result))

                Button {
                    runOpenerMatch()
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
            }

            if let error = runError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Rambling Profile
            ramblingProfileCard(result.ramblingProfile)

            // Strategies
            ForEach(result.strategies) { strategy in
                strategySection(strategy, selectedVideoId: result.selectedVideoId)
            }

            // Step 2: Gist Filter
            gistFilterSection(result)

            // Step 3: Draft Openings (only after filter)
            if gistFilterResult != nil {
                draftSection(result)
            }

            // Anti-matches
            if !result.antiMatches.isEmpty {
                antiMatchesSection(result.antiMatches)
            }

            // Debug
            debugSection(result)
        }
    }

    // MARK: - Rambling Profile Card

    private func ramblingProfileCard(_ profile: RamblingProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.wave.2")
                    .foregroundColor(.blue)
                Text("Rambling Profile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            profileRow("Entry Energy", profile.entryEnergy)
            profileRow("Emotional Trajectory", profile.emotionalTrajectory)
            profileRow("Stakes Shape", profile.stakesShape)
            profileRow("Complexity Load", profile.complexityLoad)
            profileRow("Speaker Posture", profile.speakerPosture)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(.caption)
        }
    }

    // MARK: - Strategy Section

    private func strategySection(_ strategy: OpenerStrategy, selectedVideoId: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(strategy.strategyId)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(strategyColor(strategy.strategyId))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(strategy.strategyName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(strategy.strategyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(strategy.matches) { match in
                matchCard(match, isSelected: match.videoId == selectedVideoId)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func strategyColor(_ id: String) -> Color {
        switch id {
        case "A": return .blue
        case "B": return .purple
        case "C": return .orange
        default: return .gray
        }
    }

    // MARK: - Match Card

    private func matchCard(_ match: OpenerRankedMatch, isSelected: Bool) -> some View {
        let isExpanded = expandedMatchIds.contains(match.id)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedMatchIds.remove(match.id)
                    } else {
                        expandedMatchIds.insert(match.id)
                    }
                }
            } label: {
                HStack {
                    Text("#\(match.rank)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 20)
                        .background(match.rank == 1 ? Color.green : Color.gray)
                        .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.videoTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if let seq = coordinator.sequences[match.videoId] {
                            let first2 = seq.moves.sorted(by: { $0.chunkIndex < $1.chunkIndex }).prefix(2)
                            let labels = first2.map { $0.moveType.displayName }.joined(separator: " → ")
                            Text(labels)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if isSelected {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.openingStrategySummary)
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Why this match:")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(match.matchReasoning)
                        .font(.caption)

                    HStack {
                        Button {
                            selectOpener(videoId: match.videoId)
                        } label: {
                            Label(
                                isSelected ? "Selected" : "Select as Opener",
                                systemImage: isSelected ? "checkmark.seal.fill" : "checkmark.seal"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isSelected ? .green : .accentColor)
                        .disabled(isSelected)

                        Spacer()

                        CompactCopyButton(text: "[\(match.videoTitle)]\n\(match.openingStrategySummary)\n\n\(match.matchReasoning)")
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(10)
        .background(isSelected ? Color.green.opacity(0.08) : Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Step 2: Gist Filter Section

    private func gistFilterSection(_ matchResult: OpenerMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            // Filter button
            if isFiltering {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text(filteringMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if gistFilterResult != nil {
                Button {
                    runGistFilter(from: matchResult)
                } label: {
                    Label("Re-filter Gists", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    runGistFilter(from: matchResult)
                } label: {
                    Label("Filter Gists to Positions", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if let error = filterError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Filter results
            if let gistFilterResult {
                ForEach(gistFilterResult.strategyFilters) { strategyFilter in
                    gistFilterCard(strategyFilter)
                }

                gistFilterDebugSection(gistFilterResult)
            }
        }
    }

    private func gistFilterCard(_ filter: OpenerStrategyFilter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(filter.strategyId)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(strategyColor(filter.strategyId))
                    .cornerRadius(6)

                Text(filter.strategyName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()
            }

            ForEach(filter.positions) { position in
                gistFilterPositionCard(position)
            }
        }
        .padding()
        .background(strategyColor(filter.strategyId).opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(strategyColor(filter.strategyId).opacity(0.2), lineWidth: 1)
        )
    }

    private func gistFilterPositionCard(_ position: OpenerFilterPosition) -> some View {
        let gists = coordinator.session.ramblingGists
        let selectedGist = position.selectedGistId.flatMap { id in
            gists.first { $0.id == id }
        }

        return VStack(alignment: .leading, spacing: 8) {
            // Position header with move label + category
            HStack {
                Text("Position \(position.positionIndex + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Text("[\(position.corpusMoveLabel)]")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                Text("(\(position.corpusMoveCategory))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Deterministic filter summary
            let frameNames = position.eligibleFrames.map(\.displayName).joined(separator: ", ")
            Text("\(position.candidateCount) of \(gists.count) gists eligible \u{2022} frames: \(frameNames)")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Corpus section text snippet
            if !position.corpusSectionText.isEmpty {
                Text(String(position.corpusSectionText.prefix(150)) + (position.corpusSectionText.count > 150 ? "..." : ""))
                    .font(.caption2)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
            }

            // Selected gist
            if let gist = selectedGist {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Gist \(gist.chunkIndex + 1)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("[\(gist.gistA.frame.displayName)]")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    Text(gist.gistA.subject.joined(separator: ", "))
                        .font(.caption)
                    Text(gist.gistA.premise)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(gist.sourceText.prefix(200)) + (gist.sourceText.count > 200 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                }
                .padding(8)
                .background(Color.green.opacity(0.05))
                .cornerRadius(6)
            }

            // LLM reasoning
            if !position.selectionReasoning.isEmpty {
                Text(position.selectionReasoning)
                    .font(.caption2)
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private func gistFilterDebugSection(_ filterResult: OpenerGistFilterResult) -> some View {
        DisclosureGroup(isExpanded: $showFilterDebug) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(filterResult.strategyFilters) { filter in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(filter.strategyId)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(strategyColor(filter.strategyId))
                                .cornerRadius(4)
                            Text(filter.strategyName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: buildGistFilterCopyText(filter))
                        }

                        if let t = filter.telemetry {
                            Text("Input: \(t.promptTokens) | Output: \(t.completionTokens) | Total: \(t.totalTokens) | Model: \(t.modelUsed)")
                                .font(.caption2)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }

                        // Selected gist details per position
                        ForEach(filter.positions) { pos in
                            if let gistId = pos.selectedGistId,
                               let gist = coordinator.session.ramblingGists.first(where: { $0.id == gistId }) {
                                let copyText = "POSITION \(pos.positionIndex + 1) [\(pos.corpusMoveLabel)]\nFrame: \(gist.gistA.frame.displayName)\nSubject: \(gist.gistA.subject.joined(separator: ", "))\nPremise: \(gist.gistA.premise)\n\nSOURCE TEXT:\n\(gist.sourceText)"

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Position \(pos.positionIndex + 1) Selected Gist")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        Text("[\(pos.corpusMoveLabel)]")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                        Spacer()
                                        CompactCopyButton(text: copyText)
                                    }
                                    Text("Frame: \(gist.gistA.frame.displayName) | Subject: \(gist.gistA.subject.joined(separator: ", "))")
                                        .font(.caption2)
                                        .monospaced()
                                    Text("Premise: \(gist.gistA.premise)")
                                        .font(.caption2)
                                        .monospaced()
                                        .foregroundColor(.secondary)
                                    HStack {
                                        Text(gist.sourceText)
                                            .font(.caption2)
                                            .monospaced()
                                            .foregroundColor(.secondary)
                                            .lineLimit(20)
                                        Spacer()
                                        CompactCopyButton(text: gist.sourceText)
                                    }
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                                }
                            }
                        }

                        // Copy both gists' raw text together
                        let bothGistsText = filter.positions
                            .sorted(by: { $0.positionIndex < $1.positionIndex })
                            .compactMap { pos -> String? in
                                guard let gistId = pos.selectedGistId,
                                      let gist = coordinator.session.ramblingGists.first(where: { $0.id == gistId }) else { return nil }
                                return "--- POSITION \(pos.positionIndex + 1) [\(pos.corpusMoveLabel)] ---\n\(gist.sourceText)"
                            }
                            .joined(separator: "\n\n")

                        if !bothGistsText.isEmpty {
                            HStack {
                                Text("Both Gists Raw Text")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                CompactCopyButton(text: bothGistsText)
                            }
                        }

                        debugTextBlock("System Prompt", filter.systemPromptSent)
                        debugTextBlock("User Prompt", filter.userPromptSent)
                        debugTextBlock("Raw Response", filter.rawResponse)
                    }

                    if filter.id != filterResult.strategyFilters.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Gist Filter Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("prompts, responses, telemetry")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func buildGistFilterCopyText(_ filter: OpenerStrategyFilter) -> String {
        var lines: [String] = []
        lines.append("GIST FILTER — Strategy \(filter.strategyId): \(filter.strategyName)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        for pos in filter.positions {
            lines.append("POSITION \(pos.positionIndex + 1): [\(pos.corpusMoveLabel)] (\(pos.corpusMoveCategory))")
            lines.append("Eligible frames: \(pos.eligibleFrames.map(\.rawValue).joined(separator: ", "))")
            lines.append("Candidates: \(pos.candidateCount)")
            if let gistId = pos.selectedGistId {
                lines.append("Selected: \(gistId.uuidString)")
            }
            lines.append("Reasoning: \(pos.selectionReasoning)")
            lines.append("")
        }

        lines.append(String(repeating: "=", count: 60))
        lines.append("SYSTEM PROMPT:")
        lines.append(filter.systemPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("USER PROMPT:")
        lines.append(filter.userPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("RAW RESPONSE:")
        lines.append(filter.rawResponse)
        return lines.joined(separator: "\n")
    }

    // MARK: - Step 2: Run Logic (Gist Filter)

    private func runGistFilter(from matchResult: OpenerMatchResult) {
        let gists = coordinator.session.ramblingGists
        let seqs = coordinator.sequences
        let videos = coordinator.corpusVideos
        let titles = coordinator.videoTitles

        isFiltering = true
        filteringMessage = "Building expansion index..."
        filterError = nil

        Task { @MainActor in
            // 1. Build FrameExpansionIndex from user gists
            let expansionIndex = FrameExpansionIndex(gists: gists)

            // 2. Build corpus openings once for section text extraction
            let allOpenings = buildCorpusOpenings(videos: videos, sequences: seqs, titles: titles, depth: 2)
            let openingsByVideoId = Dictionary(uniqueKeysWithValues: allOpenings.map { ($0.videoId, $0) })

            // 3. For each strategy, build filter input
            filteringMessage = "Filtering gists by frame eligibility..."

            var promptTuples: [(strategy: OpenerStrategy, system: String, user: String, positionData: [(moveTypes: [RhetoricalMoveType], eligibleFrames: [GistFrame], candidateIds: [UUID], candidateGists: [RamblingGist], corpusSections: [(videoTitle: String, moveLabel: String, text: String)])])] = []

            for strategy in matchResult.strategies {
                // For each position (0 and 1), gather data from BOTH matched videos
                var positionInputs: [OpenerMatcherPromptEngine.GistFilterPositionInput] = []
                var positionData: [(moveTypes: [RhetoricalMoveType], eligibleFrames: [GistFrame], candidateIds: [UUID], candidateGists: [RamblingGist], corpusSections: [(videoTitle: String, moveLabel: String, text: String)])] = []

                for posIdx in 0..<2 {
                    var moveTypesAtPosition: [RhetoricalMoveType] = []
                    var corpusSections: [(videoTitle: String, moveLabel: String, text: String)] = []

                    for match in strategy.matches {
                        guard let seq = seqs[match.videoId] else { continue }
                        let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
                        guard posIdx < sortedMoves.count else { continue }

                        let corpusMove = sortedMoves[posIdx]
                        moveTypesAtPosition.append(corpusMove.moveType)

                        // Get section text from corpus openings
                        let sectionText: String
                        if let opening = openingsByVideoId[match.videoId],
                           posIdx < opening.sectionTexts.count {
                            sectionText = opening.sectionTexts[posIdx].text
                        } else {
                            sectionText = corpusMove.briefDescription
                        }

                        corpusSections.append((
                            videoTitle: match.videoTitle,
                            moveLabel: corpusMove.moveType.displayName,
                            text: sectionText
                        ))
                    }

                    // Deterministic filter: union eligible gists across all move types at this position
                    var candidateIdSet = Set<UUID>()
                    var allEligibleFrames = Set<GistFrame>()
                    for moveType in moveTypesAtPosition {
                        let ids = expansionIndex.eligibleGists(for: moveType, excluding: [])
                        candidateIdSet.formUnion(ids)
                        let frames = FrameExpansionIndex.framesForMove(moveType)
                        allEligibleFrames.formUnion(frames)
                    }

                    let candidateIds = Array(candidateIdSet)
                    let candidateGists = candidateIds.compactMap { id in
                        gists.first { $0.id == id }
                    }
                    let eligibleFrames = Array(allEligibleFrames).sorted(by: { $0.rawValue < $1.rawValue })

                    // If no candidates, fall back to all gists
                    let finalCandidates = candidateGists.isEmpty ? gists : candidateGists

                    positionInputs.append(OpenerMatcherPromptEngine.GistFilterPositionInput(
                        positionIndex: posIdx,
                        corpusMoveTypes: moveTypesAtPosition,
                        corpusSections: corpusSections,
                        candidateGists: finalCandidates
                    ))

                    positionData.append((
                        moveTypes: moveTypesAtPosition,
                        eligibleFrames: eligibleFrames,
                        candidateIds: candidateGists.isEmpty ? gists.map(\.id) : candidateIds,
                        candidateGists: finalCandidates,
                        corpusSections: corpusSections
                    ))

                    if candidateGists.isEmpty {
                        print("⚠️ Gist Filter: Strategy \(strategy.strategyId) Position \(posIdx) — no eligible gists, falling back to all \(gists.count)")
                    } else {
                        print("📊 Gist Filter: Strategy \(strategy.strategyId) Position \(posIdx) — \(candidateGists.count) of \(gists.count) gists eligible")
                    }
                }

                let input = OpenerMatcherPromptEngine.GistFilterInput(
                    strategyId: strategy.strategyId,
                    strategyName: strategy.strategyName,
                    positions: positionInputs
                )
                let (system, user) = OpenerMatcherPromptEngine.buildGistFilterPrompt(input: input)
                promptTuples.append((strategy: strategy, system: system, user: user, positionData: positionData))
            }

            guard promptTuples.count == 3 else {
                filterError = "Could not build gist filter prompts for all 3 strategies (got \(promptTuples.count))."
                isFiltering = false
                return
            }

            // 4. Fire 3 LLM calls in parallel
            filteringMessage = "Matching gists to positions (3 parallel calls)..."

            let p0 = promptTuples[0]
            let p1 = promptTuples[1]
            let p2 = promptTuples[2]

            async let r0 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p0.user, promptBackgroundInfo: p0.system,
                params: ["temperature": 0.2, "max_tokens": 1000]
            )
            async let r1 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p1.user, promptBackgroundInfo: p1.system,
                params: ["temperature": 0.2, "max_tokens": 1000]
            )
            async let r2 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p2.user, promptBackgroundInfo: p2.system,
                params: ["temperature": 0.2, "max_tokens": 1000]
            )

            let bundles = await [r0, r1, r2]

            // 5. Parse responses, build OpenerGistFilterResult
            var strategyFilters: [OpenerStrategyFilter] = []

            for (i, bundle) in bundles.enumerated() {
                let strategy = promptTuples[i].strategy
                let rawResponse = bundle?.content ?? ""
                let telemetry = bundle.map { SectionTelemetry(from: $0) }

                if let telemetry {
                    print("📊 Gist Filter \(strategy.strategyId) TOKENS — In: \(telemetry.promptTokens) | Out: \(telemetry.completionTokens) | Total: \(telemetry.totalTokens)")
                }

                // Collect all valid gist IDs for validation
                let allCandidateIds = Set(promptTuples[i].positionData.flatMap(\.candidateIds))

                var positions: [OpenerFilterPosition] = []

                do {
                    let parsed = try OpenerMatcherPromptEngine.parseGistFilterResponse(
                        rawResponse: rawResponse,
                        validGistIds: allCandidateIds
                    )

                    // Build position 0
                    let pd0 = promptTuples[i].positionData[0]
                    let moveLabel0 = pd0.moveTypes.map(\.displayName).joined(separator: " / ")
                    let category0 = pd0.moveTypes.first?.category.rawValue ?? ""
                    let corpusText0 = pd0.corpusSections.map(\.text).joined(separator: "\n---\n")

                    positions.append(OpenerFilterPosition(
                        id: UUID(),
                        positionIndex: 0,
                        corpusMoveLabel: moveLabel0,
                        corpusMoveCategory: category0,
                        corpusSectionText: corpusText0,
                        eligibleFrames: pd0.eligibleFrames,
                        candidateGistIds: pd0.candidateIds,
                        candidateCount: pd0.candidateIds.count,
                        selectedGistId: UUID(uuidString: parsed.position_0.selected_gist_id),
                        selectionReasoning: parsed.position_0.reasoning
                    ))

                    // Build position 1
                    let pd1 = promptTuples[i].positionData[1]
                    let moveLabel1 = pd1.moveTypes.map(\.displayName).joined(separator: " / ")
                    let category1 = pd1.moveTypes.first?.category.rawValue ?? ""
                    let corpusText1 = pd1.corpusSections.map(\.text).joined(separator: "\n---\n")

                    positions.append(OpenerFilterPosition(
                        id: UUID(),
                        positionIndex: 1,
                        corpusMoveLabel: moveLabel1,
                        corpusMoveCategory: category1,
                        corpusSectionText: corpusText1,
                        eligibleFrames: pd1.eligibleFrames,
                        candidateGistIds: pd1.candidateIds,
                        candidateCount: pd1.candidateIds.count,
                        selectedGistId: UUID(uuidString: parsed.position_1.selected_gist_id),
                        selectionReasoning: parsed.position_1.reasoning
                    ))

                    print("✅ Gist Filter \(strategy.strategyId): Pos0=\(parsed.position_0.selected_gist_id.prefix(8))... Pos1=\(parsed.position_1.selected_gist_id.prefix(8))...")

                } catch {
                    print("❌ Gist Filter \(strategy.strategyId) parse error: \(error.localizedDescription)")

                    // Build positions with no selection on error
                    for posIdx in 0..<2 {
                        let pd = promptTuples[i].positionData[posIdx]
                        let moveLabel = pd.moveTypes.map(\.displayName).joined(separator: " / ")
                        let category = pd.moveTypes.first?.category.rawValue ?? ""
                        let corpusText = pd.corpusSections.map(\.text).joined(separator: "\n---\n")

                        positions.append(OpenerFilterPosition(
                            id: UUID(),
                            positionIndex: posIdx,
                            corpusMoveLabel: moveLabel,
                            corpusMoveCategory: category,
                            corpusSectionText: corpusText,
                            eligibleFrames: pd.eligibleFrames,
                            candidateGistIds: pd.candidateIds,
                            candidateCount: pd.candidateIds.count,
                            selectedGistId: nil,
                            selectionReasoning: "Parse error: \(error.localizedDescription)"
                        ))
                    }
                }

                strategyFilters.append(OpenerStrategyFilter(
                    id: UUID(),
                    strategyId: strategy.strategyId,
                    strategyName: strategy.strategyName,
                    positions: positions,
                    systemPromptSent: promptTuples[i].system,
                    userPromptSent: promptTuples[i].user,
                    rawResponse: rawResponse,
                    telemetry: telemetry
                ))
            }

            let newFilterResult = OpenerGistFilterResult(
                id: UUID(),
                strategyFilters: strategyFilters,
                filteredAt: Date()
            )

            gistFilterResult = newFilterResult
            persistGistFilterResult(newFilterResult)

            // Cascade invalidation: clear downstream results
            draftResult = nil
            rewriteResult = nil
            UserDefaults.standard.removeObject(forKey: Self.draftPersistenceKey)
            UserDefaults.standard.removeObject(forKey: Self.rewritePersistenceKey)

            print("✅ Gist Filter: \(strategyFilters.count) strategies filtered")

            isFiltering = false
            filteringMessage = ""
        }
    }

    // MARK: - Step 3: Draft Section

    private func draftSection(_ matchResult: OpenerMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            // Draft button
            if isDrafting {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text(draftingMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if draftResult != nil {
                if draftResult != nil {
                    Button {
                        runOpenerDrafts(from: matchResult)
                    } label: {
                        Label(
                            "Re-draft Openings",
                            systemImage: "sparkles"
                        )
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        runOpenerDrafts(from: matchResult)
                    } label: {
                        Label(
                            "Draft Openings",
                            systemImage: "sparkles"
                        )
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    runOpenerDrafts(from: matchResult)
                } label: {
                    Label("Draft Openings", systemImage: "sparkles")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if let error = draftError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Draft results
            if let draftResult {
                ForEach(draftResult.drafts) { draft in
                    draftCard(draft)
                }

                // Step 3: Rewrite section
                rewriteSection(draftResult)

                draftDebugSection(draftResult)
            }
        }
    }

    private func draftCard(_ draft: OpenerDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(draft.strategyId)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(strategyColor(draft.strategyId))
                    .cornerRadius(6)

                Text(draft.strategyName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                CompactCopyButton(text: buildDraftCopyText(draft))
            }

            Text(draft.draftText)
                .font(.callout)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .padding()
        .background(strategyColor(draft.strategyId).opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(strategyColor(draft.strategyId).opacity(0.2), lineWidth: 1)
        )
    }

    private func draftDebugSection(_ draftResult: OpenerDraftResult) -> some View {
        DisclosureGroup(isExpanded: $showDraftDebug) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(draftResult.drafts) { draft in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(draft.strategyId)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(strategyColor(draft.strategyId))
                                .cornerRadius(4)
                            Text(draft.strategyName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: buildDraftCopyText(draft))
                        }

                        if let t = draft.telemetry {
                            Text("Input: \(t.promptTokens) | Output: \(t.completionTokens) | Total: \(t.totalTokens) | Model: \(t.modelUsed)")
                                .font(.caption2)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }

                        debugTextBlock("System Prompt", draft.systemPromptSent)
                        debugTextBlock("User Prompt", draft.userPromptSent)
                        debugTextBlock("Raw Response", draft.rawResponse)
                    }

                    if draft.id != draftResult.drafts.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Draft Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("prompts, responses, telemetry")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Step 3: Run Logic

    private func runOpenerDrafts(from matchResult: OpenerMatchResult) {
        let videos = coordinator.corpusVideos
        let seqs = coordinator.sequences
        let titles = coordinator.videoTitles
        let ramblingText = coordinator.session.rawRamblingText
        let gists = coordinator.session.ramblingGists

        isDrafting = true
        draftingMessage = "Building corpus openings..."
        draftError = nil

        Task { @MainActor in
            // Build all corpus openings once, index by videoId
            let allOpenings = buildCorpusOpenings(videos: videos, sequences: seqs, titles: titles, depth: 2)
            let openingsByVideoId = Dictionary(uniqueKeysWithValues: allOpenings.map { ($0.videoId, $0) })

            draftingMessage = "Drafting 3 openings in parallel..."

            // Build prompts for each strategy
            var promptTuples: [(strategy: OpenerStrategy, system: String, user: String, openings: [OpenerMatcherPromptEngine.CorpusOpening])] = []

            for strategy in matchResult.strategies {
                let matchVideoIds = strategy.matches.map(\.videoId)
                let matchOpenings = matchVideoIds.compactMap { openingsByVideoId[$0] }

                guard !matchOpenings.isEmpty else {
                    print("⚠️ Opener Draft: Strategy \(strategy.strategyId) — no corpus openings found")
                    continue
                }

                // Use filtered gists if available, otherwise fall back to all gists
                let system: String
                let user: String

                if let filter = gistFilterResult?.strategyFilters.first(where: { $0.strategyId == strategy.strategyId }) {
                    // Resolve the 2 selected gist IDs to actual RamblingGist objects
                    let filteredGists = filter.positions
                        .sorted(by: { $0.positionIndex < $1.positionIndex })
                        .compactMap { pos -> RamblingGist? in
                            guard let gistId = pos.selectedGistId else { return nil }
                            return gists.first { $0.id == gistId }
                        }

                    if filteredGists.count == 2 {
                        print("📊 Opener Draft \(strategy.strategyId): Using 2 filtered gists")
                        (system, user) = OpenerMatcherPromptEngine.buildFilteredDraftPrompt(
                            strategy: strategy,
                            matchOpenings: matchOpenings,
                            filteredGists: filteredGists
                        )
                    } else {
                        print("⚠️ Opener Draft \(strategy.strategyId): Filter had \(filteredGists.count) gists, falling back to all")
                        (system, user) = OpenerMatcherPromptEngine.buildDraftPrompt(
                            strategy: strategy,
                            matchOpenings: matchOpenings,
                            rawRamblingText: ramblingText,
                            ramblingGists: gists
                        )
                    }
                } else {
                    (system, user) = OpenerMatcherPromptEngine.buildDraftPrompt(
                        strategy: strategy,
                        matchOpenings: matchOpenings,
                        rawRamblingText: ramblingText,
                        ramblingGists: gists
                    )
                }

                promptTuples.append((strategy: strategy, system: system, user: user, openings: matchOpenings))
            }

            guard promptTuples.count == 3 else {
                draftError = "Could not build prompts for all 3 strategies (got \(promptTuples.count)). Check that matched videos have rhetorical sequences."
                isDrafting = false
                return
            }

            // Fire 3 LLM calls in parallel
            let p0 = promptTuples[0]
            let p1 = promptTuples[1]
            let p2 = promptTuples[2]

            async let r0 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p0.user, promptBackgroundInfo: p0.system,
                params: ["temperature": 0.4, "max_tokens": 2000]
            )
            async let r1 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p1.user, promptBackgroundInfo: p1.system,
                params: ["temperature": 0.4, "max_tokens": 2000]
            )
            async let r2 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p2.user, promptBackgroundInfo: p2.system,
                params: ["temperature": 0.4, "max_tokens": 2000]
            )

            let bundles = await [r0, r1, r2]

            // Assemble drafts
            var drafts: [OpenerDraft] = []
            for (i, bundle) in bundles.enumerated() {
                let strategy = promptTuples[i].strategy
                let rawResponse = bundle?.content ?? ""
                let draftText = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                let telemetry = bundle.map { SectionTelemetry(from: $0) }

                if let telemetry {
                    print("📊 Opener Draft \(strategy.strategyId) TOKENS — In: \(telemetry.promptTokens) | Out: \(telemetry.completionTokens) | Total: \(telemetry.totalTokens)")
                }

                drafts.append(OpenerDraft(
                    id: UUID(),
                    strategyId: strategy.strategyId,
                    strategyName: strategy.strategyName,
                    draftText: draftText,
                    systemPromptSent: promptTuples[i].system,
                    userPromptSent: promptTuples[i].user,
                    rawResponse: rawResponse,
                    telemetry: telemetry
                ))
            }

            let newDraftResult = OpenerDraftResult(
                id: UUID(),
                drafts: drafts,
                draftedAt: Date()
            )

            draftResult = newDraftResult
            persistDraftResult(newDraftResult)
            print("✅ Opener Draft: \(drafts.count) drafts completed")

            isDrafting = false
            draftingMessage = ""
        }
    }

    // MARK: - Step 4: Rewrite Section

    private func rewriteSection(_ draftResult: OpenerDraftResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            // Rewrite button
            if isRewriting {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text(rewritingMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if rewriteResult != nil {
                Button {
                    runOpenerRewrites(from: draftResult)
                } label: {
                    Label("Re-rewrite Openings", systemImage: "pencil.and.outline")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    runOpenerRewrites(from: draftResult)
                } label: {
                    Label("Rewrite Openings", systemImage: "pencil.and.outline")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if let error = rewriteError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Rewrite results
            if let rewriteResult {
                ForEach(rewriteResult.rewrites) { rewrite in
                    rewriteCard(rewrite)
                }

                rewriteDebugSection(rewriteResult)
            }
        }
    }

    private func rewriteCard(_ rewrite: OpenerRewrite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(rewrite.strategyId)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(strategyColor(rewrite.strategyId))
                    .cornerRadius(6)

                Text(rewrite.strategyName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                CompactCopyButton(text: buildRewriteCopyText(rewrite))
            }

            Text(rewrite.rewriteText)
                .font(.callout)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            // Voice Analysis disclosure
            if !rewrite.voiceAnalysis.isEmpty {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedRewriteAnalysisIds.contains(rewrite.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedRewriteAnalysisIds.insert(rewrite.id)
                            } else {
                                expandedRewriteAnalysisIds.remove(rewrite.id)
                            }
                        }
                    )
                ) {
                    Text(rewrite.voiceAnalysis)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                } label: {
                    Text("Voice Analysis")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(strategyColor(rewrite.strategyId).opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(strategyColor(rewrite.strategyId).opacity(0.2), lineWidth: 1)
        )
    }

    private func rewriteDebugSection(_ rewriteResult: OpenerRewriteResult) -> some View {
        DisclosureGroup(isExpanded: $showRewriteDebug) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rewriteResult.rewrites) { rewrite in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rewrite.strategyId)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(strategyColor(rewrite.strategyId))
                                .cornerRadius(4)
                            Text(rewrite.strategyName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: buildRewriteCopyText(rewrite))
                        }

                        if let t = rewrite.telemetry {
                            Text("Input: \(t.promptTokens) | Output: \(t.completionTokens) | Total: \(t.totalTokens) | Model: \(t.modelUsed)")
                                .font(.caption2)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }

                        debugTextBlock("System Prompt", rewrite.systemPromptSent)
                        debugTextBlock("User Prompt", rewrite.userPromptSent)
                        debugTextBlock("Raw Response", rewrite.rawResponse)
                    }

                    if rewrite.id != rewriteResult.rewrites.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Rewrite Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("prompts, responses, telemetry")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Step 4: Run Logic

    private func runOpenerRewrites(from draftResult: OpenerDraftResult) {
        let videos = coordinator.corpusVideos
        let seqs = coordinator.sequences
        let titles = coordinator.videoTitles

        isRewriting = true
        rewritingMessage = "Building corpus openings..."
        rewriteError = nil

        Task { @MainActor in
            let allOpenings = buildCorpusOpenings(videos: videos, sequences: seqs, titles: titles, depth: 2)
            let openingsByVideoId = Dictionary(uniqueKeysWithValues: allOpenings.map { ($0.videoId, $0) })

            rewritingMessage = "Rewriting 3 openings in parallel..."

            // Build prompts for each draft
            var promptTuples: [(draft: OpenerDraft, system: String, user: String)] = []

            for draft in draftResult.drafts {
                // Find the strategy to get the matched video IDs
                guard let strategy = result?.strategies.first(where: { $0.strategyId == draft.strategyId }) else {
                    print("⚠️ Opener Rewrite: Could not find strategy \(draft.strategyId)")
                    continue
                }

                let matchVideoIds = strategy.matches.map(\.videoId)
                let matchOpenings = matchVideoIds.compactMap { openingsByVideoId[$0] }

                guard !matchOpenings.isEmpty else {
                    print("⚠️ Opener Rewrite: Strategy \(draft.strategyId) — no corpus openings found")
                    continue
                }

                let (system, user) = OpenerMatcherPromptEngine.buildRewritePrompt(
                    draftText: draft.draftText,
                    matchOpenings: matchOpenings
                )
                promptTuples.append((draft: draft, system: system, user: user))
            }

            guard promptTuples.count == 3 else {
                rewriteError = "Could not build rewrite prompts for all 3 drafts (got \(promptTuples.count))."
                isRewriting = false
                return
            }

            // Fire 3 LLM calls in parallel
            let p0 = promptTuples[0]
            let p1 = promptTuples[1]
            let p2 = promptTuples[2]

            async let r0 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p0.user, promptBackgroundInfo: p0.system,
                params: ["temperature": 0.3, "max_tokens": 3000]
            )
            async let r1 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p1.user, promptBackgroundInfo: p1.system,
                params: ["temperature": 0.3, "max_tokens": 3000]
            )
            async let r2 = ClaudeModelAdapter(model: .claude4Sonnet).generate_response_bundle(
                prompt: p2.user, promptBackgroundInfo: p2.system,
                params: ["temperature": 0.3, "max_tokens": 3000]
            )

            let bundles = await [r0, r1, r2]

            // Assemble rewrites
            var rewrites: [OpenerRewrite] = []
            for (i, bundle) in bundles.enumerated() {
                let draft = promptTuples[i].draft
                let rawResponse = bundle?.content ?? ""
                let telemetry = bundle.map { SectionTelemetry(from: $0) }

                let parsed = OpenerMatcherPromptEngine.parseRewriteResponse(rawResponse: rawResponse)

                if let telemetry {
                    print("📊 Opener Rewrite \(draft.strategyId) TOKENS — In: \(telemetry.promptTokens) | Out: \(telemetry.completionTokens) | Total: \(telemetry.totalTokens)")
                }

                rewrites.append(OpenerRewrite(
                    id: UUID(),
                    strategyId: draft.strategyId,
                    strategyName: draft.strategyName,
                    rewriteText: parsed.rewriteText,
                    voiceAnalysis: parsed.voiceAnalysis,
                    originalDraftText: draft.draftText,
                    systemPromptSent: promptTuples[i].system,
                    userPromptSent: promptTuples[i].user,
                    rawResponse: rawResponse,
                    telemetry: telemetry
                ))
            }

            let newRewriteResult = OpenerRewriteResult(
                id: UUID(),
                rewrites: rewrites,
                rewrittenAt: Date()
            )

            rewriteResult = newRewriteResult
            persistRewriteResult(newRewriteResult)
            print("✅ Opener Rewrite: \(rewrites.count) rewrites completed")

            isRewriting = false
            rewritingMessage = ""
        }
    }

    // MARK: - Anti-Matches

    private func antiMatchesSection(_ antiMatches: [OpenerAntiMatch]) -> some View {
        DisclosureGroup(isExpanded: $showAntiMatches) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(antiMatches) { am in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(am.videoTitle)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(am.reasoning)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Anti-Matches")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("(\(antiMatches.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Debug Section

    private func debugSection(_ result: OpenerMatchResult) -> some View {
        DisclosureGroup(isExpanded: $showDebug) {
            VStack(alignment: .leading, spacing: 12) {
                if let t = result.telemetry {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token Telemetry")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text("Input: \(t.promptTokens) | Output: \(t.completionTokens) | Total: \(t.totalTokens)")
                            .font(.caption2)
                            .monospaced()
                        Text("Estimated input tokens: ~\(result.inputTokenEstimate)")
                            .font(.caption2)
                            .monospaced()
                        Text("Model: \(t.modelUsed)")
                            .font(.caption2)
                            .monospaced()
                    }
                }

                Text("Corpus: \(result.corpusVideoCount) videos | Prompt version: \(result.promptVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                debugTextBlock("System Prompt", result.systemPromptSent)
                debugTextBlock("User Prompt", result.promptSent)
                debugTextBlock("Raw LLM Response", result.rawResponse)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("prompts, response, telemetry")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func debugTextBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                CompactCopyButton(text: text)
            }
            Text(text.prefix(2000) + (text.count > 2000 ? "\n... (\(text.count) chars total)" : ""))
                .font(.caption2)
                .monospaced()
                .foregroundColor(.secondary)
                .lineLimit(20)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
        }
    }

    // MARK: - Text Builders

    private func buildDraftCopyText(_ draft: OpenerDraft) -> String {
        var lines: [String] = []
        lines.append("DRAFT OPENING — Strategy \(draft.strategyId): \(draft.strategyName)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        lines.append("DRAFT TEXT:")
        lines.append(draft.draftText)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("SYSTEM PROMPT:")
        lines.append(draft.systemPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("USER PROMPT:")
        lines.append(draft.userPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("RAW RESPONSE:")
        lines.append(draft.rawResponse)
        return lines.joined(separator: "\n")
    }

    private func buildRewriteCopyText(_ rewrite: OpenerRewrite) -> String {
        var lines: [String] = []
        lines.append("REWRITTEN OPENING — Strategy \(rewrite.strategyId): \(rewrite.strategyName)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        lines.append("REWRITTEN TEXT:")
        lines.append(rewrite.rewriteText)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("VOICE ANALYSIS:")
        lines.append(rewrite.voiceAnalysis)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("ORIGINAL DRAFT:")
        lines.append(rewrite.originalDraftText)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("SYSTEM PROMPT:")
        lines.append(rewrite.systemPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("USER PROMPT:")
        lines.append(rewrite.userPromptSent)
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("RAW RESPONSE:")
        lines.append(rewrite.rawResponse)
        return lines.joined(separator: "\n")
    }

    private func buildFullResultsText(_ result: OpenerMatchResult) -> String {
        var lines: [String] = []
        lines.append("OPENER MATCH RESULTS")
        lines.append("====================")
        lines.append("")

        lines.append("RAMBLING PROFILE:")
        lines.append("  Entry Energy: \(result.ramblingProfile.entryEnergy)")
        lines.append("  Emotional Trajectory: \(result.ramblingProfile.emotionalTrajectory)")
        lines.append("  Stakes Shape: \(result.ramblingProfile.stakesShape)")
        lines.append("  Complexity Load: \(result.ramblingProfile.complexityLoad)")
        lines.append("  Speaker Posture: \(result.ramblingProfile.speakerPosture)")
        lines.append("")

        for strategy in result.strategies {
            lines.append("STRATEGY \(strategy.strategyId): \(strategy.strategyName)")
            lines.append(strategy.strategyDescription)
            lines.append("")
            for match in strategy.matches {
                let selected = match.videoId == result.selectedVideoId ? " [SELECTED]" : ""
                lines.append("  #\(match.rank) \(match.videoTitle)\(selected)")
                lines.append("  \(match.openingStrategySummary)")
                lines.append("  Why: \(match.matchReasoning)")
                lines.append("")
            }
        }

        if !result.antiMatches.isEmpty {
            lines.append("ANTI-MATCHES:")
            for am in result.antiMatches {
                lines.append("  X \(am.videoTitle): \(am.reasoning)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

