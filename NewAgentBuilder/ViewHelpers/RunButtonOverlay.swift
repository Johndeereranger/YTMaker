//
//  RunButtonOverlay.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/2/25.
//
import SwiftUI

struct RunButtonOverlay: View {
    var onSend: () -> Void

    var body: some View {
        Button(action: {
            onSend()
        }) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(16)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 3)
        }
//        .padding(.bottom, 24)
//        .padding(.trailing, 24)
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

struct EditPromptButtonOverlay: View {
    var onEditPrompt: () -> Void

    var body: some View {
        Button(action: {
            onEditPrompt()
        }) {
            Text("Edit Prompt")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(20)
                .shadow(radius: 3)
        }
//        .padding(.bottom, 24)
//        .padding(.leading, 24)
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

