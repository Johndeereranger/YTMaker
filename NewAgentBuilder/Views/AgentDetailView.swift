//
//  AgentDetailView.swift
//  AgentBuilder
//
//  Created by Byron Smith on 4/17/25.
//


// MARK: - AgentDetailView
import SwiftUI

struct AgentDetailView: View {
    //let agent: Agent
    @StateObject var viewModel: AgentDetailViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var isPresentingNewPromptStep = false
    @State private var newStepTitle = ""
    @State private var newPromptContent = ""
    @FocusState private var isTextEditorFocused: Bool
    var onSave: (Agent) -> Void
    
    @State private var editingStep: PromptStep? = nil

    @State private var stepListId: UUID = UUID()
    
    

    
    init(agent: Agent, onSave: @escaping (Agent) -> Void) {
        //self.agent = agent
        _viewModel = StateObject(wrappedValue: AgentDetailViewModel(agent: agent))
        self.onSave = onSave
    }
    
    var body: some View {
        
        VStack(alignment: .leading) {
            Text(viewModel.agent.name)
                .font(.largeTitle)
                .padding(.bottom, 4)
            
            CopyButton(label: "AgentID", valueToCopy: viewModel.agent.id.uuidString, font: .caption)
                .padding(.bottom, 8)

            if let desc = viewModel.agent.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Text("Prompt Steps")
                .font(.headline)
            
            List {
                //ForEach(viewModel.agent.promptSteps) { step in
                ForEach(viewModel.agent.promptSteps, id: \.id) { step in
                    HStack {
                        PromptStepRowView(
                            step: step,
                            isEnabled: viewModel.isStepEnabled(step),
                            onTap: {
                                editingStep = step
                                // nav.pushStep(step)
                            },
                            onEnableToggle: {
                                if viewModel.isStepEnabled(step) {
                                    viewModel.disablePromptStep(step)
                                } else {
                                    viewModel.enablePromptStep(step)
                                }
                            }
                        )
                        Spacer()
                        Button {
                            print("Tapped engineering for \(step.id)")
                            nav.push(.promptRunList(viewModel.agent, step))
                          } label: {
                              Image(systemName: "wrench.and.screwdriver.fill")
                                  .foregroundColor(.blue)
                                  .padding(.trailing, 8)
                          }
                          .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .onDelete(perform: deletePromptStep)
                .onMove { indices, newOffset in
                    viewModel.reorderPromptSteps(from: indices, to: newOffset)
                }
            }
            .id(stepListId)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        editingStep = PromptStep(title: "", prompt: "")
                    }) {
                        Image(systemName: "plus")
                    }
                }
                #elseif os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        editingStep = PromptStep(title: "", prompt: "")
                    }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Prompt Step") // optional hover tooltip
                }
                #endif
            }
              .navigationDestination(item: $editingStep) { step in
                
                  PromptStepEditorView(step: step) { updatedStep in
                      print("PromptStepEditorView finished")
                      var updatedAgent = viewModel.agent
                      if let index = updatedAgent.promptSteps.firstIndex(where: { $0.id == updatedStep.id }) {
                          updatedAgent.promptSteps[index] = updatedStep
                      } else {
                          updatedAgent.promptSteps.append(updatedStep) // ✅ New Step insert
                      }
                      viewModel.agent = updatedAgent
                      stepListId = UUID()
                  }
                  .environment(\.agentDetailViewModel, viewModel)
              }
        }
        
        .padding()
        .environmentObject(viewModel)
        .onDisappear {
            onSave(viewModel.agent)
        }
        .onAppear {
           // print("\(viewModel.agent.promptSteps[0].prompt)")
        }
        
    }
    
    private func deletePromptStep(at offsets: IndexSet) {
        for index in offsets {
            let step = viewModel.agent.promptSteps[index]
            viewModel.deletePromptStep(step)
        }
    }
}
