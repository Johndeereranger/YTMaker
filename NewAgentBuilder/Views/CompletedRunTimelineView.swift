//
//  CompletedRunTimelineView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/12/25.
//
import SwiftUI

struct CompletedRunTimelineView: View {
    let steps: [PromptStep]
    let showFeedback: Bool
    let allRuns: [PromptRun]
    let onSaveFeedback: (UUID, String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(steps.indices, id: \.self) { index in
                let step = steps[index]
                let stepRuns = allRuns.filter { $0.promptStepId == step.id }
                if !stepRuns.isEmpty {
                    CompletedStepRunView(
                        step: step,
                        index: index,
                        runs: stepRuns,
                        showFeedback: showFeedback,
                        onSaveFeedback: onSaveFeedback
                    )
                }
            }
        }
    }
}


struct CompletedStepRunView: View {
    let step: PromptStep
    let index: Int
    let runs: [PromptRun]
    let showFeedback: Bool
    let onSaveFeedback: (UUID, String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeaderView(index: index, title: step.title)

            let historicalRuns = Array(runs.dropLast())
            let finalRun = runs.last

            if !historicalRuns.isEmpty {
                HistoricalRunGroupView(
                    runs: historicalRuns,
                    stepTitle: step.title,
                    showFeedback: showFeedback,
                    onSaveFeedback: { id, note, rating in
                          onSaveFeedback(id, note, rating ?? 0) // force default fallback
                      }
                )
            }

            if let finalRun {
                CompletedPromptCardView(run: finalRun)
                if !showFeedback {
                    if !finalRun.response.isEmpty {
                        FeedbackDisplayView(run: finalRun) { uid, note, rating in
                            onSaveFeedback(uid, note, rating)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}
