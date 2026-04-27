//
//  InlineFeedbackInput.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/7/25.
//


import SwiftUI

struct InlineFeedbackInput: View {
    @Binding var note: String
    @Binding var rating: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
 
            ZStack(alignment: .topLeading) {
                if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Feedback is required to continue…")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $note)
                    .frame(minHeight: 60)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                    .opacity(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.85 : 1)
            }

            // Feedback Rating
            HStack(spacing: 12) {
                Spacer()
                Picker("Rating", selection: $rating) {
                    ForEach(1...5, id: \.self) { i in
                        Text("\(i)").tag(i)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 280)
                Spacer()
            }
        }
    }
}
