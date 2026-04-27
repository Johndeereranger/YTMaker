//
//  GapRamblingPadView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Dedicated sheet for responding to gap analysis questions.
//  Extracted from the inline GapRamblingView to eliminate scroll-in-scroll
//  conflicts and re-render pressure from the Arc tab's deep view hierarchy.
//
//  User picks a gap path, taps questions to insert [Q: ...] headers into
//  the text editor, then rambles below each one.
//  Output saves to session.arcGapRamblingText.
//

import SwiftUI

struct GapRamblingPadView: View {

    let runId: UUID
    let pathResults: [GapPathResult]
    let coordinator: MarkovScriptWriterCoordinator

    @Environment(\.dismiss) private var dismiss

    // All state local — no @ObservedObject, no re-render pressure from parent
    @State private var text: String = ""
    @State private var usedQuestionIds: Set<UUID> = []
    @State private var selectedPathId: String?
    @State private var didSave = false

    // MARK: - Computed

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Paths that completed with at least one finding.
    private var availablePaths: [GapPathResult] {
        pathResults.filter { $0.status == .completed && !$0.findings.isEmpty }
    }

    /// Findings for the currently selected path.
    private var activeFindings: [GapFinding] {
        guard let pathId = selectedPathId else {
            return availablePaths
                .flatMap(\.findings)
                .sorted { $0.priority < $1.priority }
        }
        guard let result = availablePaths.first(where: { $0.path.rawValue == pathId }) else {
            return []
        }
        return result.findings.sorted { $0.priority < $1.priority }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top section: path picker + scrollable question list
                questionPanel
                    .frame(maxHeight: 280)

                Divider()

                // Bottom section: editor with its own scroll context
                editorPanel
            }
            .navigationTitle("Gap Rambling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Label(didSave ? "Saved" : "Save",
                              systemImage: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                    }
                    .tint(didSave ? .green : .blue)
                }
            }
            .onAppear {
                restoreState()
            }
        }
    }

    // MARK: - Question Panel

    private var questionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Path picker
            pathPicker

            // Question list
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activeFindings) { finding in
                        questionRow(for: finding)
                    }
                }
                .padding(.horizontal)
            }

            // Used count
            HStack {
                Text("\(usedQuestionIds.count)/\(activeFindings.count) used")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private var pathPicker: some View {
        Picker("Gap Path", selection: $selectedPathId) {
            let allCount = availablePaths.flatMap(\.findings).count
            Text("All (\(allCount))").tag(nil as String?)
            ForEach(availablePaths, id: \.path.rawValue) { result in
                Text("\(result.path.rawValue): \(result.path.displayName) (\(result.findings.count))")
                    .tag(result.path.rawValue as String?)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .onAppear {
            guard selectedPathId == nil else { return }
            if let g6 = availablePaths.first(where: { $0.path == .g6_synthesis }) {
                selectedPathId = g6.path.rawValue
            }
        }
    }

    private func questionRow(for finding: GapFinding) -> some View {
        let isUsed = usedQuestionIds.contains(finding.id)
        return Button {
            insertQuestion(finding)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(priorityColor(finding.priority))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                Text(finding.questionToRambler)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isUsed ? Color.gray.opacity(0.12) : Color.blue.opacity(0.08))
            .foregroundColor(isUsed ? .secondary : .primary)
            .cornerRadius(8)
        }
        .disabled(isUsed)
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mac Catalyst-safe UITextView — own scroll context, no parent conflict
            RamblingTextViewRepresentable(text: $text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            // Action bar
            HStack(spacing: 12) {
                CompactCopyButton(text: text)
                Text("Copy")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Actions

    /// Direct insertion — no binding ping-pong, single state mutation.
    private func insertQuestion(_ finding: GapFinding) {
        let header = "[Q: \(finding.questionToRambler)]"
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = header + "\n"
        } else {
            if !text.hasSuffix("\n\n") {
                if text.hasSuffix("\n") {
                    text += "\n"
                } else {
                    text += "\n\n"
                }
            }
            text += header + "\n"
        }
        usedQuestionIds.insert(finding.id)
    }

    private func save() {
        coordinator.session.arcGapRamblingText = text
        coordinator.persistSession()
        didSave = true
    }

    private func restoreState() {
        let saved = coordinator.session.arcGapRamblingText
        guard !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = saved

        // Restore used question IDs by scanning saved text for markers
        let allFindings = pathResults
            .filter { $0.status == .completed }
            .flatMap(\.findings)
        for finding in allFindings {
            let marker = "[Q: \(finding.questionToRambler)]"
            if saved.contains(marker) {
                usedQuestionIds.insert(finding.id)
            }
        }
    }

    // MARK: - Helpers

    private func priorityColor(_ priority: GapPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        }
    }
}

// MARK: - Menu-Safe UITextView for Mac Catalyst

/// UITextView subclass that blocks format-related menu actions (Font, Spelling,
/// Substitutions, Transformations, Speech, Writing Direction, Layout Orientation).
/// On Mac Catalyst, these menus corrupt the NSMenu hierarchy — orphaned parent-child
/// references cause RemoteViewService to spin when any .menu Picker opens on the
/// same screen. Allowlisting only basic edit actions prevents registration.
fileprivate class MenuSafeTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(cut(_:)),
             #selector(copy(_:)),
             #selector(paste(_:)),
             #selector(selectAll(_:)),
             #selector(select(_:)),
             #selector(UIResponderStandardEditActions.delete(_:)),
             #selector(UIResponderStandardEditActions.toggleBoldface(_:)),
             #selector(UIResponderStandardEditActions.toggleItalics(_:)),
             #selector(UIResponderStandardEditActions.toggleUnderline(_:)):
            return super.canPerformAction(action, withSender: sender)
        default:
            return false
        }
    }
}

/// UIViewRepresentable wrapping MenuSafeTextView.
/// Follows the CatalystTextEditor pattern from TranscriptRewriterView.swift.
fileprivate struct RamblingTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> MenuSafeTextView {
        let tv = MenuSafeTextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.text = text
        return tv
    }

    func updateUIView(_ uiView: MenuSafeTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RamblingTextViewRepresentable
        init(_ parent: RamblingTextViewRepresentable) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
