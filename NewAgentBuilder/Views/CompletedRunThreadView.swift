//
//  CompletedRunThreadView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/3/25.
//
import SwiftUI


struct CompletedRunThreadView: View {
    let runs: [PromptRun]
    let steps: [PromptStep]
    let onSaveFeedback: (UUID, String, Int) -> Void
    
    @State private var editingRunId: UUID?
    @State private var editableNote: String = ""
    @State private var editableRating: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
          //  ForEach(runs) { run in
            ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                         if let step = steps.first(where: { $0.id == run.promptStepId }) {
                             StepHeaderView(index: index, title: step.title)
                         }
                CompletedPromptCardView(run: run)

                if !run.response.isEmpty {
                    FeedbackDisplayView(run: run) { uid, note, rating in
                        onSaveFeedback(uid, note, rating)
                    }
                }
                
                
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
}

struct CompletedPromptCardView: View {
    let run: PromptRun

    @State private var isPromptExpanded = false
    @State private var isInputExpanded = false

    var body: some View {
        PromptInputCardView(
            run: .constant(run),
            isPromptExpanded: $isPromptExpanded,
            isInputExpanded: $isInputExpanded,
            isEditingInput: .constant(false),
            isEditingPrompt: .constant(false),
            onPromptRun: { _ in }
        )
    }
}
