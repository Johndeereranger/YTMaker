//
//  SpecificAgentView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/30/25.
//


import SwiftUI

struct SpecificAgentView: View {
    @StateObject private var viewModel = GenericAutoRunViewModel()
    @ObservedObject private var agentViewModel = AgentViewModel.instance
    @State private var selectedAgentId: UUID?
    @State private var inputText: String = ""

    private let hardcodedAgentID = UUID(uuidString: "07D6B5AA-9034-4EF1-A287-CE7C25A29585")!

    var body: some View {

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        Text("SOAP Notes Processor")
                            .font(.headline)
                        Spacer()
                    }

                    SOAPOutputView(responses: viewModel.stepOutputs)

                    ClearButton(viewModel: viewModel, inputText: $inputText)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }

            // MARK: - Floating Centered Status View
            if viewModel.isRunning {
                VStack {
                    AgentRunStatusView(isRunning: true)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await viewModel.loadAgent()
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.chatSession == nil {
                InputBar2 { inputText in
                    viewModel.droppedInput = inputText
                    Task { await viewModel.runAllSteps() }
                } onTopRightTap: {
                    print("ℹ️ Top-right tap (InputBar2)")
                }
            }
        }
        .onAppear {
            if selectedAgentId == nil {
                selectedAgentId = hardcodedAgentID
                if let agent = agentViewModel.agents.first(where: { $0.id == hardcodedAgentID }) {
                    viewModel.setAgent(agent)
                }
            }
        }
    }
}


struct SOAPInputView: View {
    @Binding var inputText: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Paste transcription here:")
                .font(.headline)
            TextEditor(text: $inputText)
                .frame(height: 120)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray))
        }
    }
}

import SwiftUI

struct SOAPOutputView: View {
    let responses: [String]

    private let labels = ["Subjective", "Objective", "Assessment", "Plan"]

    var filteredResponses: [String] {
        responses.filter { !$0.contains("🏁 Finished agent run") }
    }

    var combinedText: String {
        zip(labels, filteredResponses)
            .map { "\($0):\n\($1.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n\n")
    }

    var body: some View {
        if !filteredResponses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: - Copy Button
                HStack {
                    Spacer()
                    CopyButton(label: "SOAP", valueToCopy: combinedText, font: .subheadline)
                    Spacer()
                }

                // MARK: - Combined Output
                Text(combinedText)
                    .font(.body)
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
        }
    }
}

struct ClearButton: View {
    @ObservedObject var viewModel: GenericAutoRunViewModel
    @Binding var inputText: String

    var body: some View {
        HStack {
            Spacer()
            
            if !viewModel.stepOutputs.isEmpty {
                Button("Clear & Start New Note") {
                    inputText = ""
                    viewModel.clearAll()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            Spacer()
        }
    }
}
