//
//  PromptRunThreadView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/30/25.
//
import SwiftUI


extension Binding where Value == Int? {
    func defaulted(to defaultValue: Int) -> Binding<Int> {
        Binding<Int>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

extension Binding where Value == String? {
    func defaulted(to defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

struct PromptActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(configuration.isPressed ? 0.2 : 0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
    }
}

struct PromptRunThreadView: View {
    let agent: Agent
    //let runs: [PromptRun]
    @Binding var runs: [PromptRun]
    @Binding var isPromptExpanded: Bool
    @Binding var isInputExpanded: Bool
    @Binding var isEditingInput: Bool
    @Binding var isEditingPrompt: Bool
    
    
    let promptSteps: [PromptStep]
    var onRetry: (PromptRun) -> Void
    var onFork: (PromptRun) -> Void
    var onPromote: (PromptRun) -> Void
    var onRunPrompt: (PromptRun) -> Void
    var onDiagnose: (PromptRun) -> Void
    @State private var showMissingFeedback: Bool = false
    @State private var missingMessage: String?
    
   //// @State private var isPromptExpanded = false
    //@State private var isEditingPrompt = false
    

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($runs) { $run in
                
                PromptInputCardView(run: $run, isPromptExpanded: $isPromptExpanded, isInputExpanded: $isInputExpanded, isEditingInput: $isEditingInput, isEditingPrompt: $isEditingPrompt) { updatedRun in
                    onRunPrompt(updatedRun)
                }

                // Assistant Message (LLM)
                if !run.response.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            if !agent.isChatAgent {
                            
                                Text("Your Feedback")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $run.feedbackNote.defaulted(to: ""))
                                    .frame(minHeight: 60)
                                    .padding(8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        Group {
                                            if run.feedbackNote?.isEmpty ?? true {
                                                Text("Feedback is required to continue…")
                                                    .foregroundColor(.gray)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    )
                            }
                                copyPIOButton(for: run)
                        }
                        
                        
                        // Feedback: Rating
                        HStack(spacing: 12) {
                            Spacer()
                            if run.finishReason == "length"{
                                Text("Hit Token Limit")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            if run.finishReason == "content_filter"{
                                Text("Content Filter")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            if !agent.isChatAgent {
                                
                                
                                Picker("Rating", selection: $run.feedbackRating.defaulted(to: 0)) {
                                    ForEach(1...5, id: \.self) { i in
                                        Text("\(i)").tag(i)
                                    }
                                }
                                .onChange(of: run.feedbackRating) { newRating in
                                    if newRating == 5 && (run.feedbackNote?.isEmpty ?? true) {
                                        run.feedbackNote = "✅ This is good"
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 280)
                            }
                            Spacer()
                        }

                        if showMissingFeedback {
                            HStack {
                                Spacer()
                                Text(missingMessage ?? "")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Spacer()
                            }
                        }

                            // Action Buttons
                            HStack(spacing: 24) {
                                Button("Retry") {
                                    if validateFeedback(for: run, onAgent: agent,  onInvalid: { self.missingMessage = $0; showMissingFeedback = true }) {
                                             onRetry(run)
                                         }
                                }
                                .buttonStyle(PromptActionButtonStyle())
                                Button("Fork") {
                                    print("Fork Button Pressed")
                                    if validateFeedback(for: run, onAgent: agent, onInvalid: { self.missingMessage = $0; showMissingFeedback = true }) {
                                        Task { @MainActor in
                                                   onFork(run)
                                               }
                                           }
                                }
                                Button("Ask AI for Help") {
                                    if validateFeedback(for: run, onAgent: agent, onInvalid: { self.missingMessage = $0; showMissingFeedback = true }) {
                                        Task { @MainActor in
                                                   onDiagnose(run)
                                               }
                                    }
                                }
                                .buttonStyle(PromptActionButtonStyle())
                                .buttonStyle(PromptActionButtonStyle())
                                if !isFinalStep(run){
                                    Button("Use This Prompt") {
                                        if validateFeedback(for: run, onAgent: agent,  onInvalid: { self.missingMessage = $0; showMissingFeedback = true }) {
                                                   onPromote(run)
                                               }
                                    }
                                    .buttonStyle(PromptActionButtonStyle())
                                }
                             
                            }
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        HStack {
                            Spacer()
                            
                            
                            if run.purpose == .diagnostic {
                                Button("Save This As New Prompt Step") {
                                    AgentViewModel.instance.updatePromptStepPrompt(agentId: self.agent.id, stepId: run.promptStepId, newPrompt: run.response)
                                }
                                .buttonStyle(PromptActionButtonStyle())
                                .padding(.top, 4)
                                .foregroundColor(.blue)
                                .padding(.top, 4)
                            }
                            Spacer()
                        }
                        
                        if isFinalStep(run) && !agent.isChatAgent{
                            Text("End of Agent Workflow")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 60)
    
    }
    
    func validateFeedback(for run: PromptRun, onAgent: Agent, onInvalid: (String) -> Void) -> Bool {
        if agent.isChatAgent { return true }
        if run.isFeedbackComplete { return true }

        if run.feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            onInvalid("Input feedback on the Prompt before proceeding.")
        } else {
            onInvalid("Input feedback Rating on the Prompt before proceeding.")
        }

        return false
    }
    func copyPIOButton(for run: PromptRun) -> some View {
        Button(action: {
            let text = """
            I've got this prompt: "\(run.basePrompt)"
            With this input: "\(run.userInput)"
            And the assistant said: "\(run.response)"

            I'd like to provide some feedback.
            """
            UIPasteboard.general.string = text
        }) {
            Text("Copy Prompt-Input-Output")
                .foregroundColor(.blue)
        }
        .buttonStyle(PromptActionButtonStyle())
        .padding(.top, 4)
    }
    
    func isFinalStep(_ run: PromptRun) -> Bool {
        guard let stepIndex = promptSteps.firstIndex(where: { $0.id == run.promptStepId }) else { return false }
        return stepIndex == promptSteps.count - 1
    }
}

//
//struct PromptActionButtonStyle: ButtonStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        configuration.label
//            .font(.footnote)
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(Color.blue.opacity(configuration.isPressed ? 0.2 : 0.1))
//            .foregroundColor(.blue)
//            .cornerRadius(8)
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(Color.blue, lineWidth: 1)
//            )
//    }
//}

//
//import SwiftUI
//
//struct PromptRunResponseView: View {
//    @Binding var run: PromptRun
//    var onRetry: (PromptRun) -> Void
//    var onFork: (PromptRun) -> Void
//    var onPromote: (PromptRun) -> Void
//
//    @State private var showMissingFeedback = false
//    @State private var missingMessage: String?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            HStack{
//                Text("Assistant4")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                Button {
//                    UIPasteboard.general.string = run.feedbackNote
//                    if let note = run.feedbackNote {
//                          UIPasteboard.general.string = note
//                          print("📋 Copied feedback note to clipboard: \(note)")
//                      } else {
//                          print("⚠️ No feedback note to copy.")
//                      }
//                } label: {
//                    Image(systemName: "doc.on.doc")
//                        .foregroundColor(.blue)
//                        .padding(4)
//                }
//                Spacer()
//                
//                
//            }
//
//            Text(run.response)
//                .font(.body)
//                .padding(12)
//                .background(Color.green.opacity(0.1))
//                .cornerRadius(12)
//
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Your Feedback")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//
//                TextEditor(text: $run.feedbackNote.defaulted(to: ""))
//                    .frame(minHeight: 60)
//                    .padding(8)
//                    .background(Color(UIColor.secondarySystemBackground))
//                    .cornerRadius(8)
//                    .overlay(
//                        Group {
//                            if run.feedbackNote?.isEmpty ?? true {
//                                Text("Feedback is required to continue…")
//                                    .foregroundColor(.gray)
//                                    .padding(.horizontal, 12)
//                                    .padding(.vertical, 8)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//                            }
//                        }
//                    )
//            }
//
//            // Feedback: Rating
//            HStack(spacing: 12) {
//                Spacer()
//                Picker("Rating", selection: $run.feedbackRating.defaulted(to: 0)) {
//                    ForEach(1...5, id: \.self) { i in
//                        Text("\(i)").tag(i)
//                    }
//                }
//                .pickerStyle(SegmentedPickerStyle())
//                .frame(width: 280)
//                Spacer()
//            }
//
//            if showMissingFeedback {
//                HStack {
//                    Spacer()
//                    Text(missingMessage ?? "")
//                        .foregroundColor(.red)
//                        .font(.caption)
//                    Spacer()
//                }
//            }
//
//            // Action Buttons
//            HStack(spacing: 24) {
//                Button("Retry") {
//                    if validateFeedback() {
//                        onRetry(run)
//                    }
//                }
//                .buttonStyle(PromptActionButtonStyle())
//
//                Button("Fork") {
//                    if validateFeedback() {
//                        Task { @MainActor in onFork(run) }
//                    }
//                }
//                .buttonStyle(PromptActionButtonStyle())
//
//                Button("Use This Prompt") {
//                    if validateFeedback() {
//                        onPromote(run)
//                    }
//                }
//                .buttonStyle(PromptActionButtonStyle())
//            }
//            .font(.footnote)
//            .foregroundColor(.blue)
//            .padding(.top, 4)
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//    }
//
//    func validateFeedback() -> Bool {
//        if run.isFeedbackComplete { return true }
//
//        if run.feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
//            missingMessage = "Input feedback on the Prompt before proceeding."
//        } else {
//            missingMessage = "Input feedback Rating on the Prompt before proceeding."
//        }
//
//        showMissingFeedback = true
//        return false
//    }
//}


struct ParsedAttributedCodeView: View {
    let raw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(codeBlocks, id: \.self) { block in
                VStack(alignment: .leading, spacing: 8) {
                    // Optional text preview
                    Text(preview(from: block))
                        .font(.body)
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                    // Copy button
                    Button {
                        UIPasteboard.general.string = block
                        print("📋 Copied block to clipboard")
                    } label: {
                        Label("Copy Code1", systemImage: "doc.on.doc")
                            .font(.caption)
                            .padding(.bottom, 2)
                    }

                    // Code block
                    Text(block)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
    }

    private var codeBlocks: [String] {
        var blocks: [String] = []

        let startFence = "```swift"
        let endFence = "```"

        var search = raw

        while let startRange = search.range(of: startFence),
              let endRange = search.range(of: endFence, range: startRange.upperBound..<search.endIndex) {

            let codeStart = startRange.upperBound
            let codeEnd = endRange.lowerBound
            let codeBlock = String(search[codeStart..<codeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

            blocks.append(codeBlock)

            search = String(search[endRange.upperBound...]) // continue after the endFence
        }

        return blocks
    }

    private func preview(from code: String) -> String {
        guard let startRange = code.range(of: #"AttributedString\("#, options: .regularExpression),
              let endRange = code.range(of: #"(?<!\\)""#, options: .regularExpression, range: startRange.upperBound..<code.endIndex)
        else {
            return "Preview unavailable"
        }

        return String(code[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



struct ParsedAttributedCodeViewShort: View {
    let raw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(codeBlocks, id: \.self) { block in
                VStack(alignment: .leading, spacing: 8) {
                    // Optional text preview
//                    Text(preview(from: block))
//                        .font(.body)
//                        .padding(8)
//                        .background(Color.green.opacity(0.1))
//                        .cornerRadius(8)

                    // Copy button
                    Button {
                        UIPasteboard.general.string = block
                        print("📋 Copied block to clipboard")
                    } label: {
                        Label("Copy Code2", systemImage: "doc.on.doc")
                            .font(.caption)
                            .padding(.bottom, 2)
                    }

                    // Code block
                    Text(String(block.prefix(100)) + "…")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
    }
    

    private var codeBlocks: [String] {
        var blocks: [String] = []

        let startFence = "```swift"
        let endFence = "```"

        var search = raw

        while let startRange = search.range(of: startFence),
              let endRange = search.range(of: endFence, range: startRange.upperBound..<search.endIndex) {

            let codeStart = startRange.upperBound
            let codeEnd = endRange.lowerBound
            let codeBlock = String(search[codeStart..<codeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

            blocks.append(codeBlock)

            search = String(search[endRange.upperBound...]) // continue after the endFence
        }

        return blocks
    }

    private func preview(from code: String) -> String {
        guard let startRange = code.range(of: #"AttributedString\("#, options: .regularExpression),
              let endRange = code.range(of: #"(?<!\\)""#, options: .regularExpression, range: startRange.upperBound..<code.endIndex)
        else {
            return "Preview unavailable"
        }

        return String(code[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodePreviewBlock: View {
    let code: String
    
    var body: some View {
        VStack(alignment: .leading) {
            CopyButton(label: "Code", valueToCopy: code)
            
            Text(code.prefix(100) + (code.count > 100 ? "…" : ""))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }
}
