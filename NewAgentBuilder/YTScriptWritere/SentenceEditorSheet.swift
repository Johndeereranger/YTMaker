//
//  SentenceEditorSheet.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//
import SwiftUI

// MARK: - Sentence Editor Sheet
struct SentenceEditorSheet: View {
    @ObservedObject var sentence: Sentence
    @Binding var isPresented: Bool  // ADD THIS
    let onSave: () -> Void
    
    @State private var editedText: String = ""
    @State private var editedFlags: [SentenceFlag] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sentence Text") {
                    TextEditor(text: $editedText)
                        .frame(minHeight: 100)
                }
                
                Section("Flags") {
                    ForEach(SentenceFlag.allCases, id: \.self) { flag in
                        Toggle(flag.rawValue, isOn: Binding(
                            get: { editedFlags.contains(flag) },
                            set: { isOn in
                                if isOn {
                                    if !editedFlags.contains(flag) {
                                        editedFlags.append(flag)
                                    }
                                } else {
                                    editedFlags.removeAll { $0 == flag }
                                }
                            }
                        ))
                    }
                }
                
                Section {
                    Button("Regenerate This Sentence") {
                        // Mock regeneration
                        editedText = "This is a regenerated sentence."
                    }
                    
                    HStack {
                        CopyButton(
                            label: "Fix Prompt",
                            valueToCopy: """
                            Current sentence: \(sentence.text)
                            
                            Task: Rewrite ONLY this sentence to fix any issues while maintaining flow.
                            """
                        )
                    }
                    
                    Button(role: .destructive) {
                        sentence.text = ""
                        sentence.flags.removeAll()
                        onSave()
                        isPresented = false  // USE BINDING
                    } label: {
                        Text("Delete Sentence")
                    }
                }
            }
            .navigationTitle("Edit Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false  // USE BINDING
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        sentence.text = editedText
                        sentence.flags = editedFlags
                        onSave()
                        isPresented = false  // USE BINDING
                    }
                }
            }
            .onAppear {
                editedText = sentence.text
                editedFlags = sentence.flags
            }
        }
        // ADD: Handle Escape key on Mac
        #if targetEnvironment(macCatalyst)
        .onExitCommand {
            isPresented = false
        }
        #endif
    }
}
