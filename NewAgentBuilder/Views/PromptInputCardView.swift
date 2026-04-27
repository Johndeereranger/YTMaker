//
//  PromptInputCardView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/2/25.
//

import SwiftUI

struct PromptInputCardView: View {
    @Binding var run: PromptRun
    @Binding var isPromptExpanded: Bool
    @Binding var isInputExpanded: Bool
    @Binding var isEditingInput: Bool
    @Binding var isEditingPrompt: Bool
    @State private var isResponseExpanded = false
    var onPromptRun: (PromptRun) -> Void
    //@State private var isEditingPrompt = false
    //@State private var isEditingInput = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("You")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 6) {
                if !run.basePrompt.isEmpty {
                    HStack(alignment: .top) {
                        DisclosureGroup("Prompt", isExpanded: $isPromptExpanded) {
                            Text(run.basePrompt)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                        }
                        
                        CopyButton(label: "", valueToCopy: run.basePrompt, font: .body)
                            .foregroundColor(.gray)
                        if run.response.isEmpty {
                            Spacer(minLength: 20)
                            Button(action: {
                                isEditingPrompt = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    
                }
           

                    if !run.userInput.isEmpty {
                        HStack(alignment: .top) {
                            DisclosureGroup("Your Input", isExpanded: $isInputExpanded) {
                                Text(run.userInput)
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 2)
                            }
                            
                            
                            CopyButton(label: "", valueToCopy: run.userInput, font: .caption)

                            if run.response.isEmpty {
                                Spacer(minLength: 20)
                                Button(action: {
                                    isEditingInput = true
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if !run.response.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assistant2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(isExpanded: $isResponseExpanded) {
                            OutputContentView(content: run.response)
                        } label: {
                            HStack {
                                Text("Assistant2")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                CopyButton(label: "", valueToCopy: run.response, font: .caption)
                            }
                        }

                        if !isResponseExpanded {
                            OutputPreview(content: run.response)
                        }
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            
            }
            .sheet(isPresented: $isEditingPrompt) {
                ExpandedInputEditor(text: $run.basePrompt, isPresented: $isEditingPrompt) {
                    onPromptRun(run)
                } onClose: {
                    print("Closed")
                }

               
            }
        }
    }
