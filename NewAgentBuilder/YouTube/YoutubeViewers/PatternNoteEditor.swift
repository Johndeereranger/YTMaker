//
//  PatternNoteEditor.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/3/26.
//
import SwiftUI

struct PatternNoteEditor: View {
    let pattern: MarkedPattern
    let onSave: (MarkedPattern) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var note: String
    
    init(pattern: MarkedPattern, onSave: @escaping (MarkedPattern) -> Void) {
        self.pattern = pattern
        self.onSave = onSave
        _note = State(initialValue: pattern.note ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: pattern.type.icon)
                        .foregroundColor(pattern.type.color)
                    Text(pattern.type.rawValue)
                        .font(.headline)
                }
                
                Text(pattern.snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Text("Add Note:")
                    .font(.subheadline)
                
                TextEditor(text: $note)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3))
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = pattern
                        updated.note = note.isEmpty ? nil : note
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
