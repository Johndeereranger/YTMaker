//
//  InputEditorWithRunButton.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
////
//// MARK: - InputEditorWithRunButtonView
////// MARK: - AgentRunnerView
//import SwiftUI
//import Combine
//
//
//import SwiftUI
//import Combine
//struct ViewHeightKey: PreferenceKey {
//    static var defaultValue: CGFloat = 44
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = nextValue()
//    }
//}
//
//struct InputEditorWithRunButtonView: View {
//    @Binding var text: String
//    var onRun: () -> Void
//
//    @State private var isExpanded = false
//    @FocusState private var isFocused: Bool
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
//                        // Hidden Text for measuring
//                        Text(text)
//                            .font(.body)
//                            .lineLimit(10)
//                            .padding(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                            .background(
//                                GeometryReader { geometry in
//                                    Color.clear
//                                        .preference(key: ViewHeightKey.self, value: geometry.size.height)
//                                }
//                            )
//                            .background(Color.red.opacity(0.3))
//                            //.hidden()
//
//                        
//                        TextEditor(text: $text)
//                                .font(.body)
//                                .padding(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
//                                .frame(minHeight: minHeight, maxHeight: isExpanded ? UIScreen.main.bounds.height * 0.5 : maxHeight) //
//                                //.frame(height: isExpanded ? UIScreen.main.bounds.height * 0.5 : dynamicHeight) //Breakes it
//                                .background(Color(UIColor.secondarySystemBackground))
//                                .background(Color.yellow.opacity(0.3))
//                                .cornerRadius(12)
//                                .focused($isFocused)
//                                .padding(.trailing, 48)
//                                .onChange(of: text) { _ in
//                                    recalculateHeight()
//                                }
//                                .onPreferenceChange(ViewHeightKey.self) { newHeight in
//                                    print("🧩 New measured height:", newHeight)
//                                    if !isExpanded {
//                                        dynamicHeight = min(max(newHeight, minHeight), maxHeight)
//                                    }
//                                }
//                                .fixedSize(horizontal: false, vertical: true) // Let T
//                    }
//                    .frame(maxWidth: .infinity)
//                    .fixedSize(horizontal: false, vertical: true)
//
//                    // Run button
//                    Button(action: onRun) {
//                        Image(systemName: "arrow.up.circle.fill")
//                            .font(.system(size: 36))
//                            .foregroundColor(.blue)
//                            .background(Color.white)
//                            .clipShape(Circle())
//                            .shadow(radius: 4)
//                    }
//                    .padding(8)
//                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//                }
//                .padding(.bottom, keyboardHeight)
//
//                // Expand/Collapse Buttons
//                if dynamicHeight >= 100 && !isExpanded {
//                    Button(action: { isExpanded = true }) {
//                        Image(systemName: "arrow.up.left.and.arrow.down.right")
//                            .font(.system(size: 16, weight: .bold))
//                            .foregroundColor(.gray)
//                            .padding(8)
//                    }
//                }
//
//                if isExpanded {
//                    Button(action: { isExpanded = false }) {
//                        Image(systemName: "arrow.down.right.and.arrow.up.left")
//                            .font(.system(size: 16, weight: .bold))
//                            .foregroundColor(.gray)
//                            .padding(8)
//                    }
//                }
//            }
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding([.horizontal, .top])
//        .background(Color(UIColor.systemGroupedBackground))
//        .ignoresSafeArea(.keyboard, edges: .bottom)
//        .onReceive(Publishers.keyboardHeight) { height in
//            self.keyboardHeight = height
//        }
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                text += " " // append a space (forces relayout)
//                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
//        }
//    }
//
//    private func recalculateHeight() {
//        DispatchQueue.main.async {
//            print("🛠 recalculateHeight called")
//           // dynamicHeight += 0.0001
//        }
//    }
//}
//
//
//// Keyboard publisher (reuse)
//extension Publishers {
//    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
//        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
//            .map { notification -> CGFloat in
//                let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
//                return UIScreen.main.bounds.height - frame.origin.y
//            }
//            .eraseToAnyPublisher()
//    }
//}
//
//
//// Example usage:
///*
//InputEditorWithRunButtonView(text: $viewModel.userInput) {
//    Task { await viewModel.runCurrentStep() }
//}
//*/
//
//
//// MARK: - InputEditorWithRunButton States & Constraints
//
///// Defines the UI states for a ChatGPT-style text input box.
///// These are abstracted for step-by-step implementation.
//
//// ---
//// ✅ STATE 1: Empty Input
//// - No text typed
//// - No keyboard
//// - Box has minimal height (e.g. 44pt)
//// - Send button (arrow) is disabled or hidden
//// ---
//
//// ---
//// ✅ STATE 2: Keyboard Activated
//// - User taps into input field
//// - Keyboard shows
//// - Box is now active, begins responding to input
//// - Minimum height remains small (e.g. 44pt)
//// ---
//
//// ---
//// ✅ STATE 3: Growing Input
//// - User starts typing multiple lines
//// - Input field auto-grows (using GeometryReader or preference key)
//// - Max height not yet reached
//// - Box size increases smoothly (animated if possible)
//// ---
//
//// ---
//// ✅ STATE 4: Max Height Reached
//// - Box stops growing after a defined maxHeight (e.g. 150pt or 5 lines)
//// - Internal scrolling begins inside TextEditor
//// - Send button remains sticky at the bottom
//// ---
//
//// ---
//// ✅ STATE 5: Expand / Fullscreen Mode
//// - Top-right button toggles expanded view
//// - Input field takes over most of the screen
//// - Can dismiss fullscreen with same button or tap away
//// - Input grows freely without height constraint
//// ---
//
//// Constraints & UI Details:
//// --------------------------
//// - Initial height: ~44pt
//// - Expandable up to: 150pt
//// - Above 150pt: scrollable TextEditor
//// - Run button:
////    - Always visible (bottom right)
////    - Matches arrow style from ChatGPT
//// - Optional fullscreen button appears only after ~3 lines
//// - Support keyboard-aware layout (using .ignoresSafeArea or padding)
//
//// NEXT STEP: Build `InputEditorWithRunButtonView` with this behavior
