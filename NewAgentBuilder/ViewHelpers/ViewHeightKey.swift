//
//  ViewHeightKey.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
//
//
//
//import SwiftUI
//import Combine
//
//struct InputEditorWithRunButtonView2: View {
//    @Binding var text: String
//    var onRun: () -> Void
//
//    @State private var isExpanded = false
//    @State private var dynamicHeight: CGFloat = 0
//    @State private var keyboardHeight: CGFloat = 0
//
//    private let minHeight: CGFloat = 44
//    private let maxHeight: CGFloat = 200
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            ZStack(alignment: .topTrailing) {
//                ZStack(alignment: .bottomTrailing) {
//                    ZStack(alignment: .topLeading) {
//                        MeasuredTextHeightView(text: text)
//                            .padding(.trailing, 48)
//
//                        GrowingTextEditor(
//                            text: $text,
//                            isExpanded: isExpanded,
//                            minHeight: minHeight,
//                            maxHeight: maxHeight,
//                            dynamicHeight: dynamicHeight,
//                            onTextChanged: recalculateHeight
//                        )
//                        .padding(.trailing, 48)
//                    }
//
//                    RunButton(
//                        action: onRun,
//                        isDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
//                    )
//                }
//                .padding(.bottom, keyboardHeight)
//
//                ExpandCollapseButton(
//                    isExpanded: isExpanded,
//                    dynamicHeight: dynamicHeight,
//                    toggle: { isExpanded.toggle() }
//                )
//            }
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding([.horizontal, .top])
//        .background(Color(UIColor.systemGroupedBackground))
//        .ignoresSafeArea(.keyboard, edges: .bottom)
//        .onReceive(Publishers.keyboardHeight) { height in
//            self.keyboardHeight = height
//        }
//        .onPreferenceChange(ViewHeightKey.self) { newHeight in
//            if !isExpanded {
//                dynamicHeight = min(max(newHeight, minHeight), maxHeight)
//            }
//        }
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                text += " "
//                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
//        }
//    }
//
//    private func recalculateHeight() {
//        DispatchQueue.main.async {
//            // Force update cycle if needed
//        }
//    }
//}
