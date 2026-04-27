//
//  ForkGroupView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/3/25.
//


import SwiftUI


// MARK: - Updated ForkGroupView with Divider + Label
//struct ForkGroupView: View {
//    let forks: [PromptRun]
//    let stepTitle: String // e.g., "Step 2"
//    var onSaveFeedback: (UUID, String, Int) -> Void
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            if !forks.isEmpty {
//                Divider().padding(.top)
//                Text("Forks for \(stepTitle)")
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//                //ForEach(forks.indices, id: \.self) { index in
//                ForEach(forks.indices, id: \.self) { index in
//                    IndividualForkView(run: forks[index], forkIndex: index, onSaveFeedback: onSaveFeedback)
//                }
//                Divider()
//            }
//        }
//        .padding(.horizontal)
//    }
//}


// MARK: - HistoricalRunGroupView
struct HistoricalRunGroupView: View {
    let runs: [PromptRun]
    let stepTitle: String
    let showFeedback: Bool
    let onSaveFeedback: (UUID, String, Int?) -> Void

    private struct LabeledRun {
        let run: PromptRun
        let label: String
    }

    private var labeledRuns: [LabeledRun] {
        // Group runs by purpose, sort chronologically, and label
        let sortedRuns = runs.sorted { $0.createdAt < $1.createdAt }
        var forkIndex = 1
        var retryIndex = 1
        var diagnosticIndex = 1
        return sortedRuns.map { run in
            let label: String
            switch run.purpose {
            case .fork:
                label = "Fork \(forkIndex)"
                forkIndex += 1
            case .retry:
                label = "Retry \(retryIndex)"
                retryIndex += 1
            case .diagnostic:
                label = "Diagnostic \(diagnosticIndex)"
                diagnosticIndex += 1
            default:
                label = "Run"
            }
            return LabeledRun(run: run, label: label)
        }
    }

    var body: some View {
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Previous Runs for \"\(stepTitle)\"")
                    .font(.headline)
                ForEach(Array(labeledRuns.enumerated()), id: \.element.run.id) { idx, labeled in
                    IndividualForkView(
                        run: labeled.run,
                        label: labeled.label,
                        showFeedback: showFeedback,
                        onSaveFeedback: onSaveFeedback
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Updated IndividualForkView with Editable Title and Feedback
struct IndividualForkView: View {
    @State private var isExpanded = false
    @State private var isEditingFeedback = false
    @State private var customTitle: String = ""
    @State private var editableNote: String = ""
    @State private var editableRating: Int = 0
    
    let run: PromptRun
    let label: String
    let showFeedback: Bool
    var onSaveFeedback: (UUID, String, Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    CompletedPromptCardView(run: run)
                    if showFeedback {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Feedback")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button {
                                    isEditingFeedback.toggle()
                                    editableNote = run.feedbackNote ?? ""
                                    editableRating = run.feedbackRating ?? 0
                                } label: {
                                    Image(systemName: "pencil")
                                }
                            }
                            
                            if isEditingFeedback {
                                TextEditor(text: $editableNote)
                                    .frame(minHeight: 80)
                                    .padding(8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                
                                Picker("Rating", selection: $editableRating) {
                                    ForEach(1...5, id: \.self) { i in
                                        Text("\(i)").tag(i)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .padding(.top, 4)
                                
                                Button(action: {
                                    onSaveFeedback(run.id, editableNote, editableRating)
                                    isEditingFeedback = false
                                }) {
                                    Text("Save Feedback")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 8)
                            } else if let note = run.feedbackNote, !note.isEmpty {
                                Text(note)
                                    .font(.body)
                                    .padding(8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                
                                if let rating = run.feedbackRating, rating > 0 {
                                    Text("Rating: \(rating)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    TextField("\(label)", text: $customTitle)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
