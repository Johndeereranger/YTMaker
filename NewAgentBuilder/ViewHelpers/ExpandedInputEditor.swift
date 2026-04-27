//
//  ExpandedInputEditor.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/30/25.
//

import SwiftUI

struct ExpandedInputEditor: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var onSend: () -> Void
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollDismissesKeyboard(.interactively)
                        .focused($isEditorFocused)
                        .padding()
                        .frame(minHeight: 300, maxHeight: .infinity)  // ← key line
                        .layoutPriority(1)
                        .background(Color.platformBackground)
                        //.background(Color(.systemBackground))
                        .id("editor")
                }
//                .onAppear {
//                    isEditorFocused = true
//                    DispatchQueue.main.async {
//                        proxy.scrollTo("editor", anchor: .bottom)
//                    }
//                }
                .task {
                    // Slight delay allows layout to fully stabilize before focus triggers
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 sec
                    isEditorFocused = true
                }
                .onChange(of: text) { _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("editor", anchor: .bottom)
                    }
                }
            }

            // ✅ Top-right close button
            Button(action: {
                print("on Close Pressed")
                isPresented = false
               // dismiss()
                onClose()
            }) {
                Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .bold))
                        .padding(16) // ← This adds hit area
                        .background(Color.platformSecondaryBackground) // optional debug or styling
                        .clipShape(Circle()) // makes hitbox clear
            }
            .padding(.top, 24)
            .padding(.trailing, 24)

          
           
            Button(action: {
                onSend()
                isPresented = false
                //dismiss()
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(16)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
            .padding(.bottom, 24)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing) // ← optional: if not using ZStack(alignment)
            
        }
     
    }

}
