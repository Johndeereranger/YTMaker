//
//  FeedbackEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/6/25.
//


import SwiftUI

struct FeedbackEditorView: View {
    @Binding var note: String
    @Binding var rating: Int
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feedback")
                .font(.headline)

            TextField("Add a note...", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 4) {
                Text("Rating:")
                ForEach(1...5, id: \.self) { value in
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundColor(value <= rating ? .yellow : .gray)
                        .onTapGesture {
                            rating = value
                        }
                }
            }

            Button("Save Feedback") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}