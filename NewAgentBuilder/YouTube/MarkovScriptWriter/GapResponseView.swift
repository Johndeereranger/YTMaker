//
//  GapResponseView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Gap response tab for MarkovScriptWriter.
//  Shows top-ranked dead end gaps with LLM guidance questions,
//  accepts user rambling to fill those gaps, extracts gists,
//  and rebuilds the chain with the new content.
//

import SwiftUI

struct GapResponseView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coordinator.currentChainRun != nil {
                    headerSection

                    if coordinator.activeGapResponses.isEmpty {
                        if let run = coordinator.currentChainRun, !run.deadEnds.isEmpty {
                            guidanceNotGeneratedState(deadEndCount: run.deadEnds.count)
                        } else {
                            noGapsState
                        }
                    } else {
                        ForEach(Array(coordinator.activeGapResponses.enumerated()), id: \.element.id) { index, gap in
                            gapCard(index: index, gap: gap)
                        }

                        commitSection

                        if coordinator.gapPreBuildSnapshot != nil {
                            beforeAfterSection
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .onAppear {
            coordinator.loadGapResponsesFromDeadEnds()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gap Response")
                    .font(.headline)
                Spacer()

                Menu {
                    MenuCopyButton(
                        text: buildFullReport(),
                        label: "Copy Full Report",
                        systemImage: "doc.on.doc"
                    )
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }

                Button {
                    coordinator.loadGapResponsesFromDeadEnds()
                } label: {
                    Label("Reload Gaps", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Text("Read each guidance question, then ramble to fill the gap. Extract gists, then rebuild the chain.")
                .font(.caption)
                .foregroundColor(.secondary)

            let completedCount = coordinator.activeGapResponses.filter { $0.extractionStatus == .completed }.count
            let totalGists = coordinator.activeGapResponses.flatMap(\.extractedGists).count

            HStack(spacing: 16) {
                statBadge(value: "\(coordinator.activeGapResponses.count)", label: "Gaps")
                statBadge(value: "\(completedCount)", label: "Responded")
                statBadge(value: "\(totalGists)", label: "New Gists")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Gap Card

    private func gapCard(index: Int, gap: GapResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                Text("#\(index + 1)")
                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

                moveTypeBadge(gap.targetMoveType)

                Text("[\(gap.targetMoveType.category.rawValue)]")
                    .font(.caption2).foregroundColor(.secondary)

                Spacer()

                Text("\(gap.sourceDeadEndIds.count) dead ends")
                    .font(.caption2).foregroundColor(.secondary)

                Text("upside \(String(format: "%.2f", gap.upsideScore))")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.blue)
            }

            // Cascade info
            cascadeInfoSection(for: gap)

            // Rich chain context (arc, positions, move definition, corpus examples)
            chainContextSection(for: gap)

            // Guidance question (prominent)
            VStack(alignment: .leading, spacing: 4) {
                Text("What to ramble about:")
                    .font(.caption2).fontWeight(.semibold).foregroundColor(.blue)
                Text(gap.guidanceQuestion)
                    .font(.callout)
                    .foregroundColor(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            .cornerRadius(8)

            // TextEditor for user response
            VStack(alignment: .leading, spacing: 4) {
                Text("Your rambling response:")
                    .font(.caption2).fontWeight(.semibold)

                TextEditor(text: textBinding(for: gap.id))
                    .frame(minHeight: 120)
                    .font(.body)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .cornerRadius(8)

                HStack {
                    Text("\(gap.rawRamblingText.split(separator: " ").count) words")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await coordinator.extractGistsForGap(at: index) }
                    } label: {
                        Label(
                            gap.extractionStatus == .extracting ? "Extracting..." : "Extract Gists",
                            systemImage: "wand.and.stars"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gap.rawRamblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || gap.extractionStatus == .extracting)
                }
            }

            // Extraction results
            if gap.extractionStatus == .extracting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Extracting gists from your rambling...")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else if gap.extractionStatus == .completed {
                extractedGistsDebugSection(gap)
            } else if gap.extractionStatus == .failed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundColor(.red)
                    Text("Extraction failed — try again").font(.caption).foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: - Cascade Info

    private func cascadeInfoSection(for gap: GapResponse) -> some View {
        Group {
            if let cascade = coordinator.currentChainRun?.cascadeResults.first(where: { $0.moveType == gap.targetMoveType }) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle").font(.caption2)
                        Text("Fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)

                    if cascade.completionCount > 0 {
                        Text("\(cascade.completionCount)/\(cascade.deadEndCount) become completions")
                            .font(.caption2).foregroundColor(.green)
                    }

                    if let nextBlocker = cascade.nextBlockageMove {
                        Text("Next blocker: \(nextBlocker.displayName)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.04))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Chain Context (arc, positions, move definition, corpus examples)

    private func chainContextSection(for gap: GapResponse) -> some View {
        // Use representative data from moveTypeGuidance (consistent with guidance prompt)
        let mtg = coordinator.currentChainRun?.moveTypeGuidance[gap.targetMoveType]
        let pathSoFar = mtg?.representativePathSoFar
        let positionIndex = mtg?.representativePositionIndex

        // Backward compat fallback: re-find from dead ends if no moveTypeGuidance
        let fallbackDe: DeadEnd? = (pathSoFar == nil)
            ? (coordinator.currentChainRun?.deadEnds ?? [])
                .filter { $0.rawCandidateMoveTypes.contains(gap.targetMoveType) }
                .max(by: { $0.positionIndex < $1.positionIndex })
            : nil

        let arcPath = pathSoFar ?? fallbackDe?.pathSoFar ?? []
        let arcPosition = positionIndex ?? fallbackDe?.positionIndex ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            // Section A: Chain Arc
            if !arcPath.isEmpty {
                chainArcSection(pathSoFar: arcPath, positionIndex: arcPosition, targetMove: gap.targetMoveType)
            }

            // Section B: Position Context — parsed from the actual prompt (correct gist mapping)
            positionContextSection(from: gap.guidancePrompt)

            // Section C: Target Move Definition
            moveDefinitionSection(move: gap.targetMoveType)

            // Section D: Creator Corpus Examples (from guidance prompt)
            creatorCorpusSection(from: gap.guidancePrompt)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: - Section A: Chain Arc

    private func chainArcSection(pathSoFar: [String], positionIndex: Int, targetMove: RhetoricalMoveType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chain arc (\(positionIndex) positions):")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(pathSoFar.enumerated()), id: \.offset) { idx, moveName in
                        let parsed = RhetoricalMoveType.parse(moveName)
                        let color = parsed.map { categoryColor($0.category) } ?? .gray

                        VStack(spacing: 1) {
                            Text("\(idx)")
                                .font(.system(size: 7)).foregroundColor(.secondary)
                            Text(parsed?.displayName ?? moveName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(color)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(color.opacity(0.1))
                        .cornerRadius(4)

                        if idx < pathSoFar.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7)).foregroundColor(.secondary)
                        }
                    }

                    // Gap position
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7)).foregroundColor(.secondary)

                    VStack(spacing: 1) {
                        Text("\(positionIndex)")
                            .font(.system(size: 7)).foregroundColor(.red)
                        Text("??? \(targetMove.displayName)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Section B: Position Context (parsed from prompt)

    private struct PositionLine {
        let positionIndex: String
        let moveName: String
        let premise: String      // empty if "(no matching gist)"
        let coverageTag: String
        let isGap: Bool
    }

    /// Parse position context lines from the guidance prompt.
    /// Format: "- Position N (Move Name): \"premise\" (coverage tag)"
    /// or:     "- Position N (???): MISSING — this is the gap."
    private func parsePositionLines(from prompt: String) -> [PositionLine] {
        let marker = "Recent context (user's rambling content):"
        guard let markerRange = prompt.range(of: marker) else { return [] }
        let afterMarker = String(prompt[markerRange.upperBound...])

        // Find the end of the position section (next section starts with "\nThe last thing" or "\nThe chain needs")
        let endMarkers = ["\nThe last thing established", "\nThe chain needs a"]
        var sectionText = afterMarker
        for end in endMarkers {
            if let endRange = sectionText.range(of: end) {
                sectionText = String(sectionText[..<endRange.lowerBound])
            }
        }

        var results: [PositionLine] = []
        let lines = sectionText.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- Position") else { continue }

            // Check if gap line
            if trimmed.contains("MISSING") || trimmed.contains("???") {
                // "- Position N (???): MISSING — this is the gap."
                let posNum = extractPositionNumber(from: trimmed)
                results.append(PositionLine(positionIndex: posNum, moveName: "???", premise: "", coverageTag: "", isGap: true))
                continue
            }

            // Parse: "- Position N (Move Name): \"premise\" (tag)" or "- Position N (Move Name): (tag)"
            let posNum = extractPositionNumber(from: trimmed)
            let moveName = extractMoveName(from: trimmed)

            // Check if there's a quoted premise
            var premise = ""
            var coverageTag = ""

            if let quoteStart = trimmed.firstIndex(of: "\"") {
                let afterQuote = trimmed[trimmed.index(after: quoteStart)...]
                if let quoteEnd = afterQuote.firstIndex(of: "\"") {
                    premise = String(afterQuote[..<quoteEnd])
                }
            }

            // Extract coverage tag (last parenthesized text)
            if let lastOpen = trimmed.lastIndex(of: "("),
               let lastClose = trimmed.lastIndex(of: ")"),
               lastClose > lastOpen {
                let tagContent = String(trimmed[trimmed.index(after: lastOpen)..<lastClose])
                // Don't grab the move name parentheses
                if !tagContent.contains("Position") && RhetoricalMoveType.parse(tagContent) == nil {
                    coverageTag = "(\(tagContent))"
                }
            }

            results.append(PositionLine(positionIndex: posNum, moveName: moveName, premise: premise, coverageTag: coverageTag, isGap: false))
        }

        return results
    }

    private func extractPositionNumber(from line: String) -> String {
        // "- Position 3 (Move): ..." → "3"
        guard let posRange = line.range(of: "Position ") else { return "?" }
        let afterPos = line[posRange.upperBound...]
        let numChars = afterPos.prefix(while: { $0.isNumber })
        return String(numChars)
    }

    private func extractMoveName(from line: String) -> String {
        // "- Position 3 (Move Name): ..." → "Move Name"
        guard let openParen = line.firstIndex(of: "("),
              let closeParen = line.firstIndex(of: ")"),
              closeParen > openParen else { return "?" }
        return String(line[line.index(after: openParen)..<closeParen])
    }

    private func positionContextSection(from prompt: String) -> some View {
        let positions = parsePositionLines(from: prompt)

        return VStack(alignment: .leading, spacing: 6) {
            if !positions.isEmpty {
                Text("Recent positions (your content):")
                    .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, pos in
                    if pos.isGap {
                        HStack(alignment: .top, spacing: 8) {
                            Text(pos.positionIndex)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                                .frame(width: 20)

                            Text("MISSING — this is the gap")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                        .padding(6)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(6)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Text(pos.positionIndex)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    let parsed = RhetoricalMoveType.parse(pos.moveName)
                                    Text(pos.moveName)
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(parsed.map { categoryColor($0.category) } ?? .primary)

                                    if !pos.coverageTag.isEmpty {
                                        Text(pos.coverageTag)
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if !pos.premise.isEmpty {
                                    Text("\"\(pos.premise)\"")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                } else if pos.coverageTag.contains("no matching") {
                                    Text("(no matching gist)")
                                        .font(.caption2).italic()
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Section C: Target Move Definition

    private func moveDefinitionSection(move: RhetoricalMoveType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The chain needs this move next:")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 8) {
                moveTypeBadge(move)

                VStack(alignment: .leading, spacing: 4) {
                    Text(move.rhetoricalDefinition)
                        .font(.caption)
                        .foregroundColor(.primary)

                    Text("Example: \"\(move.examplePhrase)\"")
                        .font(.caption2).italic()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.15), lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: - Section D: Creator Corpus Examples

    private func creatorCorpusSection(from prompt: String) -> some View {
        // Extract the corpus examples section from the guidance prompt
        let corpusExamples = extractCorpusExamples(from: prompt)

        return VStack(alignment: .leading, spacing: 6) {
            if !corpusExamples.isEmpty {
                Text("How creators execute this move (real script text):")
                    .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

                ForEach(Array(corpusExamples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(example.text)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(8)

                        if !example.matchInfo.isEmpty {
                            Text(example.matchInfo)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.15), lineWidth: 1))
                    .cornerRadius(6)
                }
            }
        }
    }

    private struct CorpusExample {
        let text: String
        let matchInfo: String
    }

    /// Parse corpus examples from the guidance prompt text.
    /// The prompt has a section: "Here is how creators actually execute this move (raw script text):"
    /// followed by entries like: - "creator text..." \n  [Structural match: ...]
    private func extractCorpusExamples(from prompt: String) -> [CorpusExample] {
        let marker = "Here is how creators actually execute this move"
        guard let markerRange = prompt.range(of: marker) else { return [] }

        let afterMarker = String(prompt[markerRange.upperBound...])

        // Split on "- \"" pattern which starts each example
        let parts = afterMarker.components(separatedBy: "\n- \"")
        var examples: [CorpusExample] = []

        for part in parts.dropFirst() { // Skip the first part (before the first example)
            // Find the closing quote + structural match info
            let lines = part.components(separatedBy: "\n")
            var textLines: [String] = []
            var matchInfo = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[Structural match:") {
                    matchInfo = trimmed
                    break
                } else if trimmed.hasPrefix("Based on the story") || trimmed.hasPrefix("This gap blocked") {
                    break // Hit the next prompt section
                } else if !trimmed.isEmpty {
                    textLines.append(trimmed)
                }
            }

            if !textLines.isEmpty {
                var fullText = textLines.joined(separator: " ")
                // Clean up trailing quote if present
                if fullText.hasSuffix("\"") {
                    fullText = String(fullText.dropLast())
                }
                examples.append(CorpusExample(text: fullText, matchInfo: matchInfo))
            }
        }

        return examples
    }

    // MARK: - Extracted Gists Debug Section

    private func extractedGistsDebugSection(_ gap: GapResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Coverage verdict
            HStack(spacing: 8) {
                Image(systemName: gap.coversTargetMove ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(gap.coversTargetMove ? .green : .red)
                Text(gap.coversTargetMove
                    ? "Covers target move: \(gap.targetMoveType.displayName)"
                    : "Does NOT cover target move: \(gap.targetMoveType.displayName)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(gap.coversTargetMove ? .green : .red)

                Spacer()

                if let dur = gap.extractionDurationSeconds {
                    Text("\(String(format: "%.1f", dur))s")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(gap.coversTargetMove ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
            .cornerRadius(8)

            // Move coverage map
            Text("Move coverage from new gists:")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(gap.eligibleMoves.sorted(by: { $0.key.displayName < $1.key.displayName }), id: \.key) { move, count in
                    Text("\(move.displayName): \(count)")
                        .font(.system(size: 9))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(move == gap.targetMoveType ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundColor(move == gap.targetMoveType ? .green : .primary)
                        .cornerRadius(4)
                }
            }

            // Per-gist detail
            Text("Extracted gists (\(gap.extractedGists.count)):")
                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

            ForEach(gap.extractedGists) { gist in
                gistDetailCard(gist: gist, targetMove: gap.targetMoveType)
            }
        }
    }

    // MARK: - Gist Detail Card

    private func gistDetailCard(gist: RamblingGist, targetMove: RhetoricalMoveType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Chunk \(gist.chunkIndex + 1)")
                    .font(.caption).fontWeight(.semibold)

                Text(gist.gistA.frame.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)

                if let move = gist.moveLabel {
                    Text(move)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                if let conf = gist.confidence {
                    Text("\(Int(conf * 100))%")
                        .font(.caption2)
                        .foregroundColor(conf >= 0.8 ? .green : conf >= 0.6 ? .orange : .red)
                }
            }

            // GistA premise
            Text("GistA: \(gist.gistA.premise)")
                .font(.caption2).foregroundColor(.secondary)

            // GistB premise
            Text("GistB: \(gist.gistB.premise)")
                .font(.caption2).foregroundColor(.secondary)

            // Frame expansion
            let expansion = FrameExpansionIndex.expansionMoves(for: gist.gistA.frame)
            HStack(spacing: 4) {
                Text("Expands to:")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                ForEach(expansion, id: \.self) { move in
                    Text(move.displayName)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(move == targetMove ? Color.green.opacity(0.2) : Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }
            }

            // Source text
            Text(gist.sourceText)
                .font(.caption2).foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Commit & Rebuild

    private var commitSection: some View {
        let allNewGists = coordinator.activeGapResponses.flatMap(\.extractedGists)
        let completedGaps = coordinator.activeGapResponses.filter { $0.extractionStatus == .completed }
        let coversTarget = completedGaps.filter(\.coversTargetMove).count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Commit & Rebuild")
                .font(.subheadline).fontWeight(.semibold)

            HStack(spacing: 16) {
                statBadge(value: "\(allNewGists.count)", label: "New Gists")
                statBadge(value: "\(completedGaps.count)", label: "Gaps Filled")
                statBadge(value: "\(coversTarget)/\(completedGaps.count)", label: "On Target")
            }

            Text("This will append \(allNewGists.count) gists to the session (\(coordinator.session.ramblingGists.count) existing), rebuild the expansion index, and run a new chain build.")
                .font(.caption2).foregroundColor(.secondary)

            Button {
                coordinator.commitGapGistsAndRebuild()
            } label: {
                Label("Commit Gists & Rebuild Chain", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(allNewGists.isEmpty || coordinator.isLoading)
        }
        .padding()
        .background(Color.green.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: - Before / After Comparison

    private var beforeAfterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Before / After Comparison")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if let report = coordinator.gapResponseBeforeAfterReport() {
                    Menu {
                        MenuCopyButton(text: report, label: "Copy Report", systemImage: "doc.on.doc")
                    } label: {
                        Image(systemName: "square.and.arrow.up").font(.caption)
                    }
                }
            }

            if let snapshot = coordinator.gapPreBuildSnapshot, let newRun = coordinator.currentChainRun {
                HStack(spacing: 0) {
                    // Before column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BEFORE")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                        Text("Gists: \(snapshot.gistCountBefore)")
                            .font(.caption2)
                        if let len = snapshot.bestChainLengthBefore {
                            Text("Chain: \(len) positions")
                                .font(.caption2)
                        }
                        if let cov = snapshot.bestCoverageBefore {
                            Text("Coverage: \(Int(cov * 100))%")
                                .font(.caption2)
                        }
                        Text("Dead ends: \(snapshot.deadEndCountBefore)")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // After column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AFTER")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.green)
                        Text("Gists: \(coordinator.session.ramblingGists.count)")
                            .font(.caption2)
                        if let newBest = newRun.bestChain {
                            Text("Chain: \(newBest.positions.count) positions")
                                .font(.caption2)
                            Text("Coverage: \(Int(newBest.coverageScore * 100))%")
                                .font(.caption2)
                        }
                        Text("Dead ends: \(newRun.deadEnds.count)")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Move-level diff
                moveCoverageDiff(snapshot: snapshot)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    private func moveCoverageDiff(snapshot: GapPreBuildSnapshot) -> some View {
        let afterIndex = coordinator.expansionIndex ?? FrameExpansionIndex(gists: coordinator.session.ramblingGists)
        let newMoveCounts = afterIndex.moveToGists.mapValues { $0.count }
        let allMoves = Set(snapshot.moveCountsBefore.keys).union(newMoveCounts.keys)
        let changed = allMoves.filter { snapshot.moveCountsBefore[$0] != newMoveCounts[$0] }
            .sorted { $0.displayName < $1.displayName }

        return Group {
            if !changed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move coverage changes:")
                        .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)

                    ForEach(changed, id: \.self) { move in
                        let before = snapshot.moveCountsBefore[move] ?? 0
                        let after = newMoveCounts[move] ?? 0
                        let delta = after - before

                        HStack {
                            Text(move.displayName)
                                .font(.caption2)
                            Spacer()
                            Text("\(before) -> \(after)")
                                .font(.system(size: 10, design: .monospaced))
                            Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(delta > 0 ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("No Chain Run")
                .font(.headline).foregroundColor(.secondary)
            Text("Build a chain first (Chain tab), then come here to fill content gaps.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private var noGapsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40)).foregroundColor(.green)
            Text("No Dead Ends")
                .font(.headline).foregroundColor(.green)
            Text("The chain completed without hitting any dead ends — no guidance gaps to fill.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func guidanceNotGeneratedState(deadEndCount: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40)).foregroundColor(.orange)
            Text("Guidance Not Generated")
                .font(.headline).foregroundColor(.orange)
            Text("\(deadEndCount) dead end\(deadEndCount == 1 ? "" : "s") found, but guidance hasn't been generated yet. Go back to Dead Ends and run guidance generation first.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func moveTypeBadge(_ move: RhetoricalMoveType) -> some View {
        Text(move.displayName)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(categoryColor(move.category).opacity(0.15))
            .foregroundColor(categoryColor(move.category))
            .cornerRadius(4)
    }

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .purple
        case .tension: return .orange
        case .revelation: return .red
        case .evidence: return .green
        case .closing: return .indigo
        }
    }

    private func abbreviateMove(_ name: String) -> String {
        // Convert "personal-stake" to "PStake", etc.
        let parts = name.split(separator: "-")
        if parts.count == 1 {
            return String(name.prefix(6))
        }
        let first = String(parts[0].prefix(1)).uppercased()
        let rest = String(parts.last ?? "")
        return first + String(rest.prefix(1)).uppercased() + String(rest.dropFirst().prefix(4))
    }

    // MARK: - Full Report

    private func buildFullReport() -> String {
        var lines: [String] = []
        let gaps = coordinator.activeGapResponses
        let completedCount = gaps.filter { $0.extractionStatus == .completed }.count
        let totalGists = gaps.flatMap(\.extractedGists).count

        lines.append("=== GAP RESPONSE REPORT ===")
        lines.append("Gaps: \(gaps.count) | Responded: \(completedCount) | New Gists: \(totalGists)")
        lines.append("")

        for (index, gap) in gaps.enumerated() {
            lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            lines.append("GAP #\(index + 1): \(gap.targetMoveType.displayName) [\(gap.targetMoveType.category.rawValue)]")
            lines.append("Upside: \(String(format: "%.2f", gap.upsideScore)) | Dead ends: \(gap.sourceDeadEndIds.count)")

            // Cascade info
            if let cascade = coordinator.currentChainRun?.cascadeResults.first(where: { $0.moveType == gap.targetMoveType }) {
                lines.append("Cascade: fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions, \(cascade.completionCount)/\(cascade.deadEndCount) become completions")
                if let next = cascade.nextBlockageMove {
                    lines.append("  Next blocker: \(next.displayName)")
                }
            }
            lines.append("")

            // Chain arc — use stored representative from moveTypeGuidance
            let mtg = coordinator.currentChainRun?.moveTypeGuidance[gap.targetMoveType]
            let arcPath = mtg?.representativePathSoFar
                ?? (coordinator.currentChainRun?.deadEnds ?? [])
                    .filter { $0.rawCandidateMoveTypes.contains(gap.targetMoveType) }
                    .max(by: { $0.positionIndex < $1.positionIndex })?.pathSoFar
            let arcPosition = mtg?.representativePositionIndex
                ?? (coordinator.currentChainRun?.deadEnds ?? [])
                    .filter { $0.rawCandidateMoveTypes.contains(gap.targetMoveType) }
                    .max(by: { $0.positionIndex < $1.positionIndex })?.positionIndex

            if let path = arcPath, let pos = arcPosition {
                let arcStr = path.compactMap { RhetoricalMoveType.parse($0)?.displayName ?? $0 }
                    .joined(separator: " → ")
                lines.append("CHAIN ARC (\(pos) positions):")
                lines.append("  \(arcStr) → ??? \(gap.targetMoveType.displayName)")
                lines.append("")
            }

            // Position context — parsed from prompt (matches what the view shows)
            let positionLines = parsePositionLines(from: gap.guidancePrompt)
            if !positionLines.isEmpty {
                lines.append("RECENT POSITIONS:")
                for pos in positionLines {
                    if pos.isGap {
                        lines.append("  Position \(pos.positionIndex) (???): MISSING — this is the gap")
                    } else if !pos.premise.isEmpty {
                        lines.append("  Position \(pos.positionIndex) (\(pos.moveName)): \"\(pos.premise)\" \(pos.coverageTag)")
                    } else {
                        lines.append("  Position \(pos.positionIndex) (\(pos.moveName)): (no matching gist) \(pos.coverageTag)")
                    }
                }
                lines.append("")
            }

            // Move definition
            lines.append("TARGET MOVE: \(gap.targetMoveType.displayName)")
            lines.append("  \(gap.targetMoveType.rhetoricalDefinition)")
            lines.append("  Example: \"\(gap.targetMoveType.examplePhrase)\"")
            lines.append("")

            // Creator corpus examples
            let corpusExamples = extractCorpusExamples(from: gap.guidancePrompt)
            if !corpusExamples.isEmpty {
                lines.append("CREATOR CORPUS EXAMPLES:")
                for example in corpusExamples {
                    lines.append("  \"\(example.text)\"")
                    if !example.matchInfo.isEmpty {
                        lines.append("  \(example.matchInfo)")
                    }
                    lines.append("")
                }
            }

            // Guidance question
            lines.append("GUIDANCE QUESTION:")
            lines.append("  \(gap.guidanceQuestion)")
            lines.append("")

            // User response + extraction results
            if !gap.rawRamblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("USER RAMBLING (\(gap.rawRamblingText.split(separator: " ").count) words):")
                lines.append("  \(gap.rawRamblingText)")
                lines.append("")
            }

            if gap.extractionStatus == .completed {
                let coversStr = gap.coversTargetMove ? "YES" : "NO"
                lines.append("EXTRACTION RESULTS: \(gap.extractedGists.count) gists | Covers target: \(coversStr)")
                if let dur = gap.extractionDurationSeconds {
                    lines.append("  Duration: \(String(format: "%.1f", dur))s")
                }

                // Move coverage
                let moveCoverage = gap.eligibleMoves.sorted { $0.key.displayName < $1.key.displayName }
                    .map { "\($0.key.displayName): \($0.value)" }
                    .joined(separator: ", ")
                lines.append("  Move coverage: \(moveCoverage)")

                // Per-gist
                for gist in gap.extractedGists {
                    let expansion = FrameExpansionIndex.expansionMoves(for: gist.gistA.frame)
                        .map(\.displayName).joined(separator: ", ")
                    lines.append("  Chunk \(gist.chunkIndex + 1) [\(gist.gistA.frame.rawValue)]:")
                    lines.append("    GistA: \(gist.gistA.premise)")
                    lines.append("    GistB: \(gist.gistB.premise)")
                    lines.append("    Expands to: \(expansion)")
                }
                lines.append("")
            }
        }

        // Before/after
        if let report = coordinator.gapResponseBeforeAfterReport() {
            lines.append(report)
        }

        return lines.joined(separator: "\n")
    }

    /// Safe binding that looks up by ID instead of array index
    private func textBinding(for gapId: UUID) -> Binding<String> {
        Binding(
            get: {
                coordinator.activeGapResponses.first(where: { $0.id == gapId })?.rawRamblingText ?? ""
            },
            set: { newValue in
                if let idx = coordinator.activeGapResponses.firstIndex(where: { $0.id == gapId }) {
                    coordinator.activeGapResponses[idx].rawRamblingText = newValue
                }
            }
        )
    }
}
