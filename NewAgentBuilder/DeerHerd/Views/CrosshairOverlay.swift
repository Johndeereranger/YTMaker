//
//  CrosshairOverlay.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/25/25.
//
import SwiftUI

struct CrosshairOverlay: View {
    let onAddPoint: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Image(systemName: "plus")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                    Button("Add Point") { onAddPoint() }
                        .buttonStyle(.borderedProminent)
                    Button("Save") { onSave() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
}
