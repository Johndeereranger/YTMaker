//
//  BoundaryDetectionView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

// MARK: - Boundary Detection View

/// Main view for visualizing boundary detection results
struct BoundaryDetectionView: View {
    let video: YouTubeVideo
    let fidelityTest: SentenceFidelityTest

    @State private var result: BoundaryDetectionResult?
    @State private var selectedChunk: Chunk?
    @State private var params = BoundaryDetectionParams.default
    @State private var copiedDeepDive = false

    private let service = BoundaryDetectionService.shared

    var body: some View {
        Group {
            if let result = result {
                if selectedChunk != nil {
                    chunkDetailView
                } else {
                    chunkListView(result)
                }
            } else {
                ProgressView("Detecting boundaries...")
            }
        }
        .navigationTitle(selectedChunk != nil ? "Chunk \(selectedChunk!.chunkIndex + 1)" : "Boundaries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if selectedChunk == nil {
                    Menu {
                        Button("Copy Report") {
                            copyReport()
                        }
                        Button("Copy All Chunks") {
                            copyAllChunks()
                        }

                        Divider()

                        Button {
                            copyDeepDiveDebug()
                        } label: {
                            Label(
                                copiedDeepDive ? "Copied!" : "Copy Deep Dive Debug",
                                systemImage: copiedDeepDive ? "checkmark" : "ladybug"
                            )
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }

                    Button {
                        runDetection()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                } else {
                    Button("Copy") {
                        if let chunk = selectedChunk {
                            UIPasteboard.general.string = chunk.fullText
                        }
                    }
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                if selectedChunk != nil {
                    Button("Back") {
                        selectedChunk = nil
                    }
                }
            }
        }
        .onAppear {
            runDetection()
        }
    }

    // MARK: - Chunk List

    private func chunkListView(_ result: BoundaryDetectionResult) -> some View {
        List {
            // Stats Section
            Section {
                statsHeader(result)
            }

            // Chunks Section
            Section("Chunks (\(result.chunkCount))") {
                ForEach(result.chunks) { chunk in
                    Button {
                        selectedChunk = chunk
                    } label: {
                        chunkRow(chunk)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statsHeader(_ result: BoundaryDetectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(result.chunkCount) Chunks")
                        .font(.headline)
                    Text("\(result.totalSentences) sentences total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f", result.averageChunkSize))
                        .font(.headline)
                    Text("avg sentences/chunk")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Trigger distribution
            if !result.triggerDistribution.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(result.triggerDistribution.sorted(by: { $0.value > $1.value })), id: \.key) { type, count in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForTrigger(type))
                                    .frame(width: 8, height: 8)
                                Text("\(type.displayName): \(count)")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorForTrigger(type).opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    private func chunkRow(_ chunk: Chunk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Chunk \(chunk.chunkIndex + 1)")
                    .font(.headline)

                if let trigger = chunk.profile.boundaryTrigger {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForTrigger(trigger.type))
                            .frame(width: 8, height: 8)
                        Text(trigger.type.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForTrigger(trigger.type).opacity(0.2))
                    .cornerRadius(4)
                }

                Spacer()

                Text(chunk.positionLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Metadata
            HStack(spacing: 12) {
                Label("\(chunk.sentenceCount)", systemImage: "text.alignleft")
                Label(chunk.profile.dominantPerspective.rawValue, systemImage: "person")
                Label(chunk.profile.dominantStance.rawValue, systemImage: "bubble.left")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Top tags
            if !chunk.profile.tagDensity.topTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chunk.profile.tagDensity.topTags, id: \.name) { tag in
                        Text("\(tag.name) \(Int(tag.value * 100))%")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            // Preview text
            Text(chunk.preview)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var chunkDetailView: some View {
        if let chunk = selectedChunk {
            List {
                // Trigger Info
                if let trigger = chunk.profile.boundaryTrigger {
                    Section("Boundary Trigger") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(colorForTrigger(trigger.type))
                                    .frame(width: 12, height: 12)
                                Text(trigger.type.displayName)
                                    .font(.headline)
                                Text("(\(trigger.confidence.rawValue))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(trigger.type.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Profile Section
                Section("Profile") {
                    HStack {
                        Text("Position")
                        Spacer()
                        Text(chunk.positionLabel)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Sentences")
                        Spacer()
                        Text("\(chunk.startSentence) - \(chunk.endSentence) (\(chunk.sentenceCount))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Perspective")
                        Spacer()
                        Text(chunk.profile.dominantPerspective.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Stance")
                        Spacer()
                        Text(chunk.profile.dominantStance.rawValue)
                            .foregroundColor(.secondary)
                    }
                }

                // Tag Density Section
                if !chunk.profile.tagDensity.displayValues.isEmpty {
                    Section("Tag Density") {
                        ForEach(chunk.profile.tagDensity.displayValues, id: \.name) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text("\(Int(tag.value * 100))%")
                                    .foregroundColor(.secondary)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }

                // Sentences Section
                Section("Sentences (\(chunk.sentenceCount))") {
                    ForEach(chunk.sentences) { sentence in
                        sentenceRow(sentence)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func sentenceRow(_ sentence: SentenceTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("[\(sentence.sentenceIndex)]")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .leading)

                Text(sentence.text)
                    .font(.subheadline)
            }

            // Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if sentence.hasFirstPerson {
                        tagBadge("1P", color: .blue)
                    }
                    if sentence.hasSecondPerson {
                        tagBadge("2P", color: .green)
                    }
                    if sentence.hasContrastMarker {
                        tagBadge("CONTRAST", color: .orange)
                    }
                    if sentence.hasRevealLanguage {
                        tagBadge("REVEAL", color: .purple)
                    }
                    if sentence.hasChallengeLanguage {
                        tagBadge("CHALLENGE", color: .red)
                    }
                    if sentence.hasStatistic {
                        tagBadge("STAT", color: .cyan)
                    }
                    if sentence.hasNamedEntity {
                        tagBadge("ENT", color: .indigo)
                    }
                    if sentence.isTransition {
                        tagBadge("TRANS", color: .yellow)
                    }
                    if sentence.isSponsorContent {
                        tagBadge("SPONSOR", color: .pink)
                    }
                    if sentence.isCallToAction {
                        tagBadge("CTA", color: .mint)
                    }

                    Spacer()

                    Text(sentence.stance)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(sentence.perspective)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tagBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.3))
            .cornerRadius(3)
    }

    // MARK: - Actions

    private func runDetection() {
        result = service.detectBoundaries(from: fidelityTest, params: params)
    }

    private func copyReport() {
        guard let result = result else { return }
        let report = service.generateReport(for: result)
        UIPasteboard.general.string = report
    }

    private func copyAllChunks() {
        guard let result = result else { return }
        let text = service.exportChunksAsText(result.chunks)
        UIPasteboard.general.string = text
    }

    private func copyDeepDiveDebug() {
        let report = service.generateDeepDiveReport(from: fidelityTest, params: params)
        UIPasteboard.general.string = report

        withAnimation {
            copiedDeepDive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedDeepDive = false
            }
        }
    }

    // MARK: - Helpers

    private func colorForTrigger(_ type: BoundaryTrigger.BoundaryTriggerType) -> Color {
        switch type {
        case .transition: return .blue
        case .sponsor: return .pink
        case .cta: return .mint
        case .contrastQuestion: return .orange
        case .reveal: return .purple
        case .perspectiveShift: return .green
        }
    }
}
