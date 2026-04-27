//
//  PromptStepRowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
//


// MARK: - PromptStepRowView
import SwiftUI

struct PromptStepRowView: View {
    let step: PromptStep
    let isEnabled: Bool
    let onTap: () -> Void
    let onEnableToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(step.title)
                    .font(.headline)

                if !isEnabled {
                    Text("(Disabled)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text(step.prompt)
                .font(.caption)
                .lineLimit(2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if isEnabled {
                Button(role: .destructive) {
                    onEnableToggle()
                } label: {
                    Label("Disable", systemImage: "eye.slash")
                }
            } else {
                Button {
                    onEnableToggle()
                } label: {
                    Label("Enable", systemImage: "eye")
                }
                .tint(.green)
            }
        }
    }
}
