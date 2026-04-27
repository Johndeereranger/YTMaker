//
//  AgentRunnerView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
//
// MARK: - AgentRunnerView
// MARK: - AgentRunnerView
import SwiftUI
// MARK: - AgentRunnerView
import SwiftUI

struct AgentRunnerView: View {
    @StateObject private var viewModel: AgentRunnerViewModel
    @Namespace private var scrollArea
    @State private var userInput: String = ""
    let onAgentUpdate: (Agent) -> Void

//    init(agent: Agent, session: ChatSession) {
//        _viewModel = StateObject(wrappedValue: AgentRunnerViewModel(agent: agent, session: session))
//    }
    init(agent: Agent, session: ChatSession, onAgentUpdate: @escaping (Agent) -> Void = { _ in }) {
         _viewModel = StateObject(wrappedValue: AgentRunnerViewModel(agent: agent, session: session))
         self.onAgentUpdate = onAgentUpdate
     }
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isChatMode {
                Text("Chat Mode")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: 1).id("scrollTop")
                        ChatSessionHeaderView(
                            title: Binding(
                                get: { viewModel.chatSession.title },
                                set: { viewModel.updateSessionTitle($0) }
                            ),
                            onSave: {
                                AgentViewModel.instance.updateAgentInstance(viewModel.agent)
                                viewModel.updateSessionTitle($0) }
                        )
                        
                        CompletedRunTimelineView(
                            steps: viewModel.agent.promptSteps,
                            showFeedback: !viewModel.isChatMode,
                            allRuns: viewModel.allRuns.filter { !$0.response.isEmpty }
                        ) { runId, note, rating in
                            viewModel.updateForkFeedback(runId: runId, note: note, rating: rating)
                        }
                        
                        if let step = viewModel.currentStep {
                             StepHeaderView(
                                 index: viewModel.currentStepIndex,
                                 title: step.title
                             )
                            
                            HistoricalRunGroupView(
                                runs: viewModel.extraRunsForStep(step.id),
                                stepTitle: step.title,
                                showFeedback: !viewModel.isChatMode
                            ) { runId, note, rating in
                                viewModel.updateForkFeedback(runId: runId, note: note, rating: rating ?? 0)
                            }
                              
                         }
                      
                        PromptRunThreadView(
                            agent: viewModel.agent,
                            runs: $viewModel.promptRuns,
                            isPromptExpanded: $viewModel.isPromptExpanded,
                            isInputExpanded: $viewModel.isInputExpanded,
                            isEditingInput: $viewModel.forceShowInputBar,
                            isEditingPrompt: $viewModel.isEditingPrompt,
                            promptSteps: viewModel.promptSteps,
                            onRetry: { run in
                                Task {
                                    await viewModel.retryPromptRun(run)
                                }
                            },
                            onFork: { run in
                                //viewModel.userInput = run.userInput
                                Task {
                                    await viewModel.prepareForkDraft(from: run)
                                }
//                                Task {
//                                     await viewModel.forkPromptRun(run)
//                                 }
                            },
                            onPromote: { run in
                                //viewModel.updatePrompt(for: run.promptStepId, newPrompt: run.basePrompt)
                                Task {
                                        await viewModel.promoteAndAdvanceToNextStep(using: run)
                                    }
                            },
                            onRunPrompt: { run in
                                Task {
                                    await viewModel.runPromptRun(run)
                                }
                            },
                            onDiagnose: { run in
                                Task {
                                    await viewModel.createDiagnosticRun(from: run)
                                }
                            }
                        )
                        Spacer().frame(height: 80)
                        Color.clear.frame(height: 1).id("scrollBottom")
                    }
                }
                .onChange(of: viewModel.agent) { updated in
                          onAgentUpdate(updated)
                      }
                .overlay(
                    ZStack {
                            // Run Button: pinned to bottom right
                        if !viewModel.isInputBarVisible {
                            RunButtonOverlay {
                                Task {
                                    if let last = viewModel.promptRuns.last {
                                        await viewModel.runPromptRun(last)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 10)
                            .padding(.bottom, 10)
                        }
                        
                        if viewModel.mode == .forking || viewModel.mode == .extraStep {
                            EditPromptButtonOverlay {
                                viewModel.isEditingPrompt.toggle()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.leading, 10)
                            .padding(.bottom, 10)
                        }

                            // Scroll Arrows: centered horizontally at bottom
                            ScrollArrowButtons(
                                scrollTop: { withAnimation { proxy.scrollTo("scrollTop", anchor: .top) } },
                                scrollBottom: { withAnimation { proxy.scrollTo("scrollBottom", anchor: .bottom) } }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 10)
                        
                        // 🧠 Thinking Indicator — bottom center
                        if viewModel.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Thinking...")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 10)
                        }
                        }
                    
             
                    
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isInputBarVisible {
                InputBar2 { inputText in
                    print("On Send Pressed", inputText)
                    Task {
                        await viewModel.runCurrentStepSmart(input: inputText)
                    }
                } onTopRightTap: {
                    print("onTopRightTap")
                }
            } else {
                EmptyView()
            }

        }
        .onAppear() {
            Task {
                await viewModel.loadPromptRuns()
            }
        }
        .navigationTitle(viewModel.agent.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
      //  .navigationBarTitleDisplayMode(.inline)
     
    }
    
       
    
}


struct AgentPromptStepDisplayView: View {
    let step: PromptStep?
    let output: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear.frame(height: 1).id("scrollTop")

            if let step = step {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Running Step: \(step.title)")
                        .font(.headline)

                    Text(step.prompt)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                    if let output = output {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Result:")
                                .font(.headline)
                            Text(output)
                                .font(.body)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            } else {
                Text("All steps completed!")
                    .font(.title)
                    .padding()
            }

            Color.clear.frame(height: 1).id("scrollBottom")
        }
    }
}
