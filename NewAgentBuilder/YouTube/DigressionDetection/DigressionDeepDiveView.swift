import SwiftUI

struct DigressionDeepDiveView: View {
    let digression: AggregatedDigression
    @EnvironmentObject var nav: NavigationViewModel

    // Scroll/highlight state for gate check → transcript jump
    @State private var highlightedSentences: Set<Int> = []
    @State private var scrollTarget: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                contextTranscriptSection
                Divider()
                perRunComparisonSection
                Divider()
                gateChecksSection
            }
            .padding()
        }
        .navigationTitle("\(digression.region.primaryType.displayName) Deep Dive")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge + range
            HStack(spacing: 8) {
                Circle()
                    .fill(digression.region.primaryType.color)
                    .frame(width: 12, height: 12)
                Text(digression.region.primaryType.displayName)
                    .font(.headline)
                    .foregroundColor(digression.region.primaryType.color)
                Text(digression.region.rangeLabel)
                    .font(.subheadline.monospaced())
                Text("(\(digression.region.sentenceCount) sentences)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Video title
            Text("Video: \(digression.videoTitle)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Confidence + Verdict
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Confidence:")
                        .font(.caption.bold())
                    Text(digression.confidenceTier.displayName)
                        .font(.caption)
                        .foregroundColor(digression.confidenceTier.color)
                }

                HStack(spacing: 4) {
                    Text("Rules:")
                        .font(.caption.bold())
                    Image(systemName: digression.rulesVerdict.symbol)
                        .foregroundColor(digression.rulesVerdict.color)
                        .font(.caption)
                    Text(digression.rulesVerdict.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(digression.rulesVerdict.color)
                }
            }

            // Brief content
            if let brief = digression.region.briefContent, !brief.isEmpty {
                Text(brief)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Action buttons
            HStack(spacing: 8) {
                FadeOutCopyButton(
                    text: BatchDigressionAnalysisService().generateSingleDigressionCopyText(digression),
                    label: "Copy with Context",
                    systemImage: "doc.on.doc"
                )
            }
        }
    }

    // MARK: - Context Transcript

    private var contextTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transcript Context")
                .font(.caption.bold())
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    // Context before
                    if !digression.contextBefore.isEmpty {
                        contextLabel("Context Before (\(digression.contextBefore.count) sentences)")

                        ForEach(digression.contextBefore, id: \.sentenceIndex) { sentence in
                            sentenceRow(sentence, isDigression: false)
                                .id(sentence.sentenceIndex)
                        }
                    }

                    // Digression start marker
                    digressionMarker(isStart: true)

                    // Digression sentences
                    ForEach(digression.digressionSentences, id: \.sentenceIndex) { sentence in
                        digressionSentenceRow(sentence)
                            .id(sentence.sentenceIndex)
                    }

                    // Digression end marker
                    digressionMarker(isStart: false)

                    // Context after
                    if !digression.contextAfter.isEmpty {
                        contextLabel("Context After (\(digression.contextAfter.count) sentences)")

                        ForEach(digression.contextAfter, id: \.sentenceIndex) { sentence in
                            sentenceRow(sentence, isDigression: false)
                                .id(sentence.sentenceIndex)
                        }
                    }
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func contextLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .padding(.leading, 36)
    }

    private func sentenceRow(_ sentence: SentenceTelemetry, isDigression: Bool) -> some View {
        let isHighlighted = highlightedSentences.contains(sentence.sentenceIndex)

        return HStack(alignment: .top, spacing: 8) {
            Text("s\(sentence.sentenceIndex)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text(sentence.text)
                .font(.caption2)
                .lineLimit(4)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.yellow.opacity(0.25) : Color.clear)
        .overlay(
            isHighlighted
                ? RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 2)
                : nil
        )
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    private func digressionSentenceRow(_ sentence: SentenceTelemetry) -> some View {
        let isHighlighted = highlightedSentences.contains(sentence.sentenceIndex)

        return HStack(alignment: .top, spacing: 8) {
            Text("s\(sentence.sentenceIndex)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)

            // Per-run indicators
            HStack(spacing: 2) {
                ForEach(digression.region.perRunAnnotation.keys.sorted(), id: \.self) { runNum in
                    let annotation = digression.region.perRunAnnotation[runNum]
                    let detected = annotation?.contains(sentenceIndex: sentence.sentenceIndex) ?? false
                    Circle()
                        .fill(detected ? digression.region.primaryType.color : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Text(sentence.text)
                .font(.caption2)
                .lineLimit(4)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isHighlighted
                ? Color.yellow.opacity(0.25)
                : digression.region.primaryType.color.opacity(0.08)
        )
        .overlay(
            isHighlighted
                ? RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 2)
                : nil
        )
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    private func digressionMarker(isStart: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isStart ? "arrow.right.to.line" : "arrow.left.to.line")
                .font(.caption2)
            Text(isStart ? "DIGRESSION START" : "DIGRESSION END")
                .font(.caption2.bold())

            if isStart {
                Spacer()
                // Per-run indicators
                HStack(spacing: 4) {
                    ForEach(digression.region.perRunAnnotation.keys.sorted(), id: \.self) { runNum in
                        let detected = digression.region.perRunAnnotation[runNum] != nil
                        HStack(spacing: 2) {
                            Text("R\(runNum)")
                                .font(.caption2.monospacedDigit())
                            Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.caption2)
                        }
                        .foregroundColor(detected ? .green : .gray)
                    }
                }
            }
        }
        .foregroundColor(digression.region.primaryType.color)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(digression.region.primaryType.color.opacity(0.1))
        .cornerRadius(4)
        .padding(.vertical, 2)
    }

    // MARK: - Per-Run Comparison

    private var perRunComparisonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Run Comparison")
                .font(.caption.bold())

            ForEach(digression.region.perRunAnnotation.keys.sorted(), id: \.self) { runNum in
                if let annotation = digression.region.perRunAnnotation[runNum] {
                    perRunRow(runNumber: runNum, annotation: annotation)
                }
            }

            // Show runs that did NOT detect this digression
            let allRunNums = Set(1...digression.region.totalRuns)
            let missingRuns = allRunNums.subtracting(Set(digression.region.perRunAnnotation.keys))
            ForEach(missingRuns.sorted(), id: \.self) { runNum in
                HStack(spacing: 8) {
                    Text("Run \(runNum):")
                        .font(.caption.bold())
                        .frame(width: 50, alignment: .leading)
                    Text("Not detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    private func perRunRow(runNumber: Int, annotation: DigressionAnnotation) -> some View {
        HStack(spacing: 8) {
            Text("Run \(runNumber):")
                .font(.caption.bold())
                .frame(width: 50, alignment: .leading)

            Text("s\(annotation.startSentence)-\(annotation.endSentence)")
                .font(.caption.monospaced())

            HStack(spacing: 4) {
                Circle()
                    .fill(annotation.type.color)
                    .frame(width: 6, height: 6)
                Text(annotation.type.displayName)
                    .font(.caption)
            }

            Text("conf: \(String(format: "%.1f", annotation.confidence))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)

            // Find validation for this annotation
            if let validation = digression.validatedDigressions.first(where: {
                $0.annotation.startSentence == annotation.startSentence &&
                $0.annotation.endSentence == annotation.endSentence
            }) {
                HStack(spacing: 2) {
                    Image(systemName: validation.verdict.symbol)
                        .font(.caption2)
                    Text(validation.verdict.rawValue.capitalized)
                        .font(.caption2)
                }
                .foregroundColor(validation.verdict.color)
            }

            Spacer()
        }
    }

    // MARK: - Gate Checks (with tap-to-scroll)

    private var gateChecksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gate Checks")
                    .font(.caption.bold())
                Text("(tap to jump to text)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let firstValidation = digression.validatedDigressions.first {
                // Verdict summary
                HStack(spacing: 4) {
                    Image(systemName: firstValidation.verdict.symbol)
                        .foregroundColor(firstValidation.verdict.color)
                    Text(firstValidation.verdict.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(firstValidation.verdict.color)
                    Text("(\(firstValidation.checks.filter(\.passed).count)/\(firstValidation.checks.count) checks passed)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let reason = firstValidation.contradictionReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .italic()
                }

                // Individual gate checks — tappable
                ForEach(firstValidation.checks) { check in
                    gateCheckRow(
                        check: check,
                        digressionStart: digression.region.mergedStart,
                        digressionEnd: digression.region.mergedEnd
                    )
                }
            } else {
                Text("No validation data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func gateCheckRow(check: ValidatedDigression.GateCheck, digressionStart: Int, digressionEnd: Int) -> some View {
        let targetSentences = check.relevantSentenceIndices(
            digressionStart: digressionStart,
            digressionEnd: digressionEnd
        )
        let primaryTarget = targetSentences.first ?? digressionStart

        return Button {
            jumpToSentence(primaryTarget, highlightRange: targetSentences)
        } label: {
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
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text("s\(primaryTarget)")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundColor(.blue)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color.blue.opacity(0.03))
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Jump to Sentence

    private func jumpToSentence(_ target: Int, highlightRange: [Int]) {
        // Clear previous highlights
        highlightedSentences.removeAll()

        // Set new highlights
        highlightedSentences = Set(highlightRange)
        scrollTarget = target

        // Fade highlights after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                highlightedSentences.removeAll()
            }
            scrollTarget = nil
        }
    }
}
