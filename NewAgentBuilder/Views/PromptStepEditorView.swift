//
//  PromptStepEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/28/25.
//


// MARK: - PromptStepEditorView
import SwiftUI
// MARK: - PromptStepEditorView
import SwiftUI

struct PromptStepEditorView: View {
    //@State var existingStep: PromptStep
    @StateObject private var wrapper: PromptStepWrapper
    @Environment(\.agentDetailViewModel) var viewModel
    @Environment(\.dismiss) var dismiss

    /// New: Callback to allow parent to update local model
    var onSaveLocally: ((PromptStep) -> Void)? = nil

//    init(step: PromptStep? = nil, onSaveLocally: ((PromptStep) -> Void)? = nil) {
//        self.existingStep = step ?? .init(title: "New Step", prompt: "Do Something", aiModel: step?.aiModel )
//        self.onSaveLocally = onSaveLocally
//    }
    
    init(step: PromptStep? = nil, onSaveLocally: ((PromptStep) -> Void)? = nil) {
          let initial = step ?? PromptStep(title: "New Step", prompt: "Do Something", aiModel: step?.aiModel)
          _wrapper = StateObject(wrappedValue: PromptStepWrapper(step: initial))
          self.onSaveLocally = onSaveLocally
      }

//    var isExistingStep: Bool {
//        viewModel.agent.promptSteps.contains(where: { $0.id == existingStep.id })
//    }
    var isExistingStep: Bool {
            viewModel.agent.promptSteps.contains(where: { $0.id == wrapper.step.id })
        }

    var body: some View {
        Form {
            Section(header: Text("Prompt Step Details")) {
                Text(wrapper.step.id.uuidString)
                    .font(.caption)
                HStack {
//                    TextField("Step Title", text: $existingStep.title)
//                    //need a copy Step ID button here
//                    CopyButton(label: "Prompt", valueToCopy: existingStep.prompt)
//                    CopyButton(label: "StepID", valueToCopy: existingStep.id.uuidString)
                    TextField("Step Title", text: $wrapper.step.title)
                    CopyButton(label: "Prompt", valueToCopy: wrapper.step.prompt)
                    CopyButton(label: "StepID", valueToCopy: wrapper.step.id.uuidString)
                }

                TextEditor(text: $wrapper.step.prompt)
                    .frame(minHeight: 350)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                
                TextField("Notes (optional)", text: $wrapper.step.notes)
            }
            
            Section(header: Text("Processing")) {
                Toggle("Batch Eligible", isOn: $wrapper.step.isBatchEligible)
                    .help("When enabled, this step can be batched with other eligible steps for more efficient processing")
                Toggle("Use Cache", isOn: $wrapper.step.useCashe)
                    .help("When enabled, the step will reuse cached outputs if available.")

                Picker("AI Model", selection: Binding(
                    get: { wrapper.step.aiModel ?? .gpt4o },
                    set: { wrapper.step.aiModel = $0 }
                )) {
                    ForEach(AIModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                
                if wrapper.step.isBatchEligible {
                    Text("This step will be grouped with consecutive batch-eligible steps during execution")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            Button("Save") {
                            Task {
                                do {
                                    try await viewModel.saveStep(wrapper.step)
                                    onSaveLocally?(wrapper.step)
                                    dismiss()
                                } catch {
                                    print("Failed to save step: \(error)")
                                }
                            }
                        }
                        .disabled(wrapper.step.title.isEmpty || wrapper.step.prompt.isEmpty)
//            Button("Save") {
//                
//                Task {
//                    do {
//                        
//                        try await viewModel.saveStep(existingStep)
//
//                        // 🟢 Update local step in parent, if applicable
//                        onSaveLocally?(existingStep)
//
//                        dismiss()
//                    } catch {
//                        print("Failed to save step: \(error)")
//                    }
//                }
//            }
//            .disabled(existingStep.title.isEmpty || existingStep.prompt.isEmpty)
        }
        .navigationTitle(isExistingStep ? "Edit Prompt Step" : "New Prompt Step")
        #if(os(iOS))
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    final class PromptStepWrapper: ObservableObject {
        @Published var step: PromptStep

        init(step: PromptStep) {
            self.step = step
        }
    }
}
