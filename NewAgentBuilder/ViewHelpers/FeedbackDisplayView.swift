//
//  FeedbackDisplayView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/7/25.
//


import SwiftUI

import SwiftUI

struct FeedbackDisplayView: View {
    let run: PromptRun
    let startsInEditMode: Bool
    let onSave: (UUID, String, Int) -> Void

    @State private var isEditing = false
    @State private var editableNote: String = ""
    @State private var editableRating: Int = 0
    
    
    init(
        run: PromptRun,
        startsInEditMode: Bool = false,
        onSave: @escaping (UUID, String, Int) -> Void
    ) {
        self.run = run
        self.startsInEditMode = startsInEditMode
        self.onSave = onSave
        _isEditing = State(initialValue: startsInEditMode)
        _editableNote = State(initialValue: run.feedbackNote ?? "")
        _editableRating = State(initialValue: run.feedbackRating ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Assistant Response
            HStack{
                Text("Assistant1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            
                
                CopyButton(label: "", valueToCopy: run.response, font: .caption)
                Spacer()
            }

            Text(run.response)
                .font(.body)
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            // Feedback Header + Edit Toggle
            HStack {
                Text("Your Feedback")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    if isEditing {
                        // Cancel edits: discard changes
                        editableNote = run.feedbackNote ?? ""
                        editableRating = run.feedbackRating ?? 0
                        isEditing = false
                    } else {
                        // Begin editing: load current
                        editableNote = run.feedbackNote ?? ""
                        editableRating = run.feedbackRating ?? 0
                        isEditing = true
                    }
                } label: {
                    Image(systemName: isEditing ? "xmark.circle" : "pencil")
                }
            }

            // Editable vs Static View
            if isEditing {
                InlineFeedbackInput(note: $editableNote, rating: $editableRating)
                if !startsInEditMode {
                    HStack {
                        Spacer()
                        Button("Save Feedback") {
                            onSave(run.id, editableNote, editableRating)
                            isEditing = false
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.footnote)
                        Spacer()
                    }
                }
            } else {
                if let note = run.feedbackNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.body)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                HStack {
                    if let rating = run.feedbackRating, rating > 0 {
                        Text("Rating: \(rating)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    if let note = run.feedbackNote {
                        CopyButton(label: "Feedback Note", valueToCopy: note, font: .caption)
                    }
//                    Button {
//                        UIPasteboard.general.string = run.feedbackNote
//                        if let note = run.feedbackNote {
//                              UIPasteboard.general.string = note
//                              print("📋 Copied feedback note to clipboard: \(note)")
//                          } else {
//                              print("⚠️ No feedback note to copy.")
//                          }
//                    } label: {
//                        Image(systemName: "doc.on.doc")
//                            .foregroundColor(.blue)
//                            .padding(4)
//                    }
                }
            }
        }
        .onAppear {
            editableNote = run.feedbackNote ?? ""
            editableRating = run.feedbackRating ?? 0
        }
        .onChange(of: run.id) { _ in
            editableNote = run.feedbackNote ?? ""
            editableRating = run.feedbackRating ?? 0
            if startsInEditMode {
                isEditing = true
            }
        }
    }
}
