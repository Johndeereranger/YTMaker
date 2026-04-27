//
//  ChatSessionHeaderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/5/25.
//


// MARK: - ChatSessionHeaderView
import SwiftUI

struct ChatSessionHeaderViewol: View {
    @Binding var title: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Session Title", text: $title)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit {
                        commitEdit()
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
            } else {
                Text(title.isEmpty ? "Untitled Session" : title)
                    .font(.title2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Button(action: {
                if isEditing {
                    commitEdit()
                } else {
                    isEditing = true
                }
            }) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func commitEdit() {
        isEditing = false
        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
import SwiftUI

struct ChatSessionHeaderView: View {
    @Binding var title: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Centered Title or TextField
            if isEditing {
                TextField("Session Title", text: $title)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40) // Add padding so text field doesn’t collide with button
                    .onSubmit {
                        commitEdit()
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
            } else {
                Text(title.isEmpty ? "Untitled Session" : title)
                    .font(.title2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Right-aligned Edit/Check Button
            HStack {
                Spacer()
                Button(action: {
                    if isEditing {
                        commitEdit()
                    } else {
                        isEditing = true
                    }
                }) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private func commitEdit() {
        isEditing = false
        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
