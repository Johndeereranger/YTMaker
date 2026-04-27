//
//  ProseEditorView.swift
//  NewAgentBuilder
//
//  Human-in-the-loop prose editor tab for the Markov Script Writer.
//  Brief → Generate → Mark up sentences → Reconstruct → Iterate.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ProseEditorView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: ProseEditorViewModel

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
        _vm = StateObject(wrappedValue: ProseEditorViewModel(coordinator: coordinator))
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch vm.phase {
                    case .brief:
                        briefInputSection
                    case .editing:
                        briefSummaryBanner
                        statsBar
                        sentenceEditorSection
                        actionButtonsSection
                    case .generating:
                        briefSummaryBanner
                        generatingSection
                    }
                }
                .padding()
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Brief Input

    private var briefInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prose Editor")
                .font(.headline)

            Text("Describe what you want to write about. The AI will generate prose, then you mark up individual sentences and iterate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $vm.briefInput)
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            TextField("Style reference (optional)", text: $vm.styleProfileRef)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            // Show available gist context
            if !coordinator.session.ramblingGists.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.session.ramblingGists.prefix(5)) { gist in
                            Text(gist.sourceText.prefix(120) + "...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text("\(coordinator.session.ramblingGists.count) gists available as context")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            HStack {
                Button {
                    vm.submitBrief()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.briefInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if vm.session.currentDraft != nil {
                    Button("Back to Editor") {
                        vm.phase = .editing
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Brief Summary Banner

    private var briefSummaryBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Round \(vm.session.currentRound)")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)

                    Text(vm.session.brief?.rawInput ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Edit Brief") {
                    vm.goBackToBrief()
                }
                .font(.caption2)
                .buttonStyle(.bordered)

                Button("Clear", role: .destructive) {
                    vm.clearSession()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        let stats = vm.sentenceStats
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                statBadge("\(stats.total) total", color: .primary)
                if stats.kept > 0 { statBadge("\(stats.kept) keep", color: .green) }
                if stats.edited > 0 { statBadge("\(stats.edited) edited", color: .blue) }
                if stats.flagged > 0 { statBadge("\(stats.flagged) flagged", color: .orange) }
                if stats.struck > 0 { statBadge("\(stats.struck) struck", color: .red) }
                if stats.pending > 0 { statBadge("\(stats.pending) pending", color: .gray) }

                Spacer()

                if stats.pending > 0 {
                    Button {
                        vm.markAllKeep()
                    } label: {
                        Label("Keep All Pending", systemImage: "checkmark.circle")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }

                CompactCopyButton(text: vm.fullProseText)
                FadeOutCopyButton(text: vm.copyFullReport(), label: "Report")
            }
        }
    }

    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(6)
    }

    // MARK: - Sentence Editor

    private var sentenceEditorSection: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(vm.sentences.enumerated()), id: \.element.id) { index, sentence in
                sentenceCard(index: index, sentence: sentence)
            }
        }
    }

    @ViewBuilder
    private func sentenceCard(index: Int, sentence: SentenceUnit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: position, status badge, word count
            HStack(spacing: 6) {
                Text("S\(sentence.position + 1)")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.secondary)

                statusBadge(sentence.status)

                Text("\(sentence.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                CompactCopyButton(text: sentence.text)
            }

            // Text display or inline editor
            if vm.editingId == sentence.id {
                // Inline edit mode
                TextEditor(text: $vm.editBuffer)
                    .frame(minHeight: 50)
                    .font(.callout)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 1)
                    )

                HStack {
                    Button("Save") {
                        vm.editText(at: index, newText: vm.editBuffer)
                        vm.editingId = nil
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        vm.editingId = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            } else {
                // Text display
                Text(sentence.text)
                    .font(.callout)
                    .strikethrough(sentence.status == .struck, color: .red)
                    .foregroundStyle(sentence.status == .struck ? .secondary : .primary)
            }

            // Annotation field (when flagged or struck)
            if sentence.status == .flagged || sentence.status == .struck {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    TextField(
                        sentence.status == .flagged ? "What should change?" : "What should go here?",
                        text: Binding(
                            get: { vm.sentences[index].annotation ?? "" },
                            set: { vm.sentences[index].annotation = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Status buttons
            HStack(spacing: 4) {
                statusButton(
                    icon: "checkmark.circle", label: "Keep", color: .green,
                    isActive: sentence.status == .keep
                ) {
                    vm.markKeep(at: index)
                }

                statusButton(
                    icon: "pencil.circle", label: "Edit", color: .blue,
                    isActive: vm.editingId == sentence.id
                ) {
                    vm.editBuffer = sentence.text
                    vm.editingId = sentence.id
                }

                statusButton(
                    icon: "flag.circle", label: "Flag", color: .orange,
                    isActive: sentence.status == .flagged
                ) {
                    vm.markFlagged(at: index, annotation: sentence.annotation ?? "")
                }

                statusButton(
                    icon: "strikethrough", label: "Strike", color: .red,
                    isActive: sentence.status == .struck
                ) {
                    vm.markStruck(at: index, annotation: sentence.annotation ?? "")
                }

                if sentence.status != .pending {
                    statusButton(
                        icon: "arrow.uturn.backward.circle", label: "Reset", color: .gray,
                        isActive: false
                    ) {
                        vm.resetToPending(at: index)
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground(for: sentence.status))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardBorderColor(for: sentence.status), lineWidth: 1)
        )
    }

    private func statusBadge(_ status: SentenceStatus) -> some View {
        let (text, color) = statusDisplay(status)
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func statusDisplay(_ status: SentenceStatus) -> (String, Color) {
        switch status {
        case .pending: return ("PENDING", .gray)
        case .keep: return ("KEEP", .green)
        case .edited: return ("EDITED", .blue)
        case .flagged: return ("FLAGGED", .orange)
        case .struck: return ("STRUCK", .red)
        }
    }

    private func cardBackground(for status: SentenceStatus) -> Color {
        switch status {
        case .keep, .edited: return Color.green.opacity(0.04)
        case .flagged: return Color.orange.opacity(0.04)
        case .struck: return Color.red.opacity(0.04)
        case .pending: return Color.secondary.opacity(0.03)
        }
    }

    private func cardBorderColor(for status: SentenceStatus) -> Color {
        switch status {
        case .keep, .edited: return Color.green.opacity(0.3)
        case .flagged: return Color.orange.opacity(0.3)
        case .struck: return Color.red.opacity(0.3)
        case .pending: return Color.secondary.opacity(0.15)
        }
    }

    private func statusButton(icon: String, label: String, color: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption2)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? color : .secondary)
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await vm.reconstruct() }
                } label: {
                    Label("Reconstruct", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!vm.hasWorkToDo)

                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = vm.fullProseText
                    #elseif canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.fullProseText, forType: .string)
                    #endif
                } label: {
                    Label("Good Enough", systemImage: "checkmark.seal")
                        .font(.callout.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            // Round history
            if vm.session.drafts.count > 1 {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.session.drafts) { draft in
                            HStack {
                                Text("Round \(draft.round)")
                                    .font(.caption.bold())
                                Text("\(draft.sentences.count) sentences")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                CompactCopyButton(
                                    text: draft.sentences
                                        .filter { $0.status != .struck }
                                        .map(\.text)
                                        .joined(separator: " ")
                                )
                            }
                        }
                    }
                } label: {
                    Text("\(vm.session.drafts.count) rounds in history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Generating Overlay

    private var generatingSection: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            ProgressView()
                .scaleEffect(1.2)

            Text(vm.generatingMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            if vm.session.currentRound > 0 {
                Text("Round \(vm.session.currentRound + 1)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}
