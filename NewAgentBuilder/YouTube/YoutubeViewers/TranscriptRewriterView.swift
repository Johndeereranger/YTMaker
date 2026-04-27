//
//  TranscriptRewriterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/2/26.
//
import SwiftUI

//struct TranscriptRewriterView2: View {
//    let transcript: String
//    
//    @State private var sentences: [String] = []
//    @State private var selectedSentenceIndex: Int? = nil
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Tap any sentence to mark your progress")
//                .font(.caption)
//                .foregroundColor(.secondary)
//            
//            ScrollView {
//                VStack(alignment: .leading, spacing: 8) {
//                    ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
//                        Text(sentence)
//                            .font(.body)
//                            .foregroundColor(sentenceColor(for: index))
//                            .padding(.vertical, 4)
//                            .onTapGesture {
//                                selectedSentenceIndex = index
//                            }
//                    }
//                }
//                .padding()
//            }
//            .frame(maxHeight: 400)
//            .background(Color.gray.opacity(0.05))
//            .cornerRadius(8)
//            
//            if let selected = selectedSentenceIndex {
//                HStack {
//                    Text("Progress: \(selected + 1) / \(sentences.count)")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    
//                    Spacer()
//                    
//                    Button("Reset") {
//                        selectedSentenceIndex = nil
//                    }
//                    .font(.caption)
//                    .buttonStyle(.bordered)
//                }
//            }
//        }
//        .onAppear {
//            sentences = parseSentences(from: transcript)
//        }
//    }
//    
//    private func sentenceColor(for index: Int) -> Color {
//        guard let selected = selectedSentenceIndex else {
//            return .primary
//        }
//        
//        if index <= selected {
//            return .secondary // Already processed
//        } else {
//            return .primary // Not yet processed
//        }
//    }
//    
//    private func parseSentences(from text: String) -> [String] {
//        var sentences: [String] = []
//        
//        let lines = text.components(separatedBy: .newlines)
//            .map { $0.trimmingCharacters(in: .whitespaces) }
//            .filter { !$0.isEmpty }
//        
//        // Check if pre-formatted
//        let looksLikeFormattedSentences = lines.count > 1 && lines.allSatisfy { line in
//            let sentenceEndings = line.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
//            let hasMinLength = line.count > 10
//            let endsWithPunctuation = line.last == "." || line.last == "!" || line.last == "?"
//            return hasMinLength && sentenceEndings == 1 && endsWithPunctuation
//        }
//        
//        if looksLikeFormattedSentences {
//            return lines
//        }
//        
//        // Join and parse
//        let fullText = lines.joined(separator: " ")
//        
//        // Replace abbreviations
//        var processedText = fullText
//        var abbreviationMap: [String: String] = [:]
//        let abbreviations = ["Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Sr.", "Jr.", "U.S.", "U.K.", "U.N.", "E.U.", "A.M.", "P.M.", "Inc.", "Ltd.", "Corp.", "Co.", "vs.", "etc.", "i.e.", "e.g.", "St.", "Ave.", "Blvd.", "Rd.", "Mt.", "Ft."]
//        
//        for (index, abbr) in abbreviations.enumerated() {
//            if fullText.contains(abbr) {
//                let placeholder = "ABBR\(index)PLACEHOLDER"
//                abbreviationMap[placeholder] = abbr
//                processedText = processedText.replacingOccurrences(of: abbr, with: placeholder)
//            }
//        }
//        
//        // Replace decimal numbers
//        let numberPattern = "\\d+\\.\\d+"
//        if let numberRegex = try? NSRegularExpression(pattern: numberPattern) {
//            let matches = numberRegex.matches(in: processedText, range: NSRange(processedText.startIndex..., in: processedText))
//            for (index, match) in matches.enumerated().reversed() {
//                if let range = Range(match.range, in: processedText) {
//                    let number = String(processedText[range])
//                    let placeholder = "NUM\(index)PLACEHOLDER"
//                    abbreviationMap[placeholder] = number
//                    processedText = processedText.replacingOccurrences(of: number, with: placeholder)
//                }
//            }
//        }
//        
//        // Split sentences
//        let pattern = "([.!?]+[\"')]?)\\s+(?=[A-Z])"
//        do {
//            let regex = try NSRegularExpression(pattern: pattern, options: [])
//            let nsString = processedText as NSString
//            let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
//            
//            var lastIndex = 0
//            for match in matches {
//                let endIndex = match.range.location + match.range.length
//                var sentence = nsString.substring(with: NSRange(location: lastIndex, length: endIndex - lastIndex))
//                    .trimmingCharacters(in: .whitespaces)
//                
//                for (placeholder, original) in abbreviationMap {
//                    sentence = sentence.replacingOccurrences(of: placeholder, with: original)
//                }
//                
//                if !sentence.isEmpty {
//                    sentences.append(sentence)
//                }
//                lastIndex = endIndex
//            }
//            
//            // Last sentence
//            if lastIndex < nsString.length {
//                var lastSentence = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespaces)
//                for (placeholder, original) in abbreviationMap {
//                    lastSentence = lastSentence.replacingOccurrences(of: placeholder, with: original)
//                }
//                if !lastSentence.isEmpty {
//                    sentences.append(lastSentence)
//                }
//            }
//        } catch {
//            sentences = fullText.components(separatedBy: ". ")
//                .map { $0.trimmingCharacters(in: .whitespaces) }
//                .filter { !$0.isEmpty }
//                .map { $0.hasSuffix(".") ? $0 : $0 + "." }
//        }
//        
//        return sentences.isEmpty ? [fullText] : sentences
//    }
//}
struct TranscriptRewriterView: View {
    let transcript: String
    
    @State private var sentences: [String] = []
    @State private var selectedSentenceIndex: Int? = nil
    @State private var mode: RewriteMode = .read
    @State private var typedText: String = ""
    @State private var currentTypingIndex: Int = 0
    @FocusState private var isTextFieldFocused: Bool
    
    enum RewriteMode: String, CaseIterable {
        case read = "Read"
        case type = "Type"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode picker
            Picker("Mode", selection: $mode) {
                ForEach(RewriteMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in
                // Reset state when switching modes
                selectedSentenceIndex = nil
                typedText = ""
                currentTypingIndex = 0
            }
            
            if mode == .read {
                readModeView
            } else {
                typeModeView
            }
        }
        .onAppear {
            sentences = parseSentences(from: transcript)
        }
    }
    
    // MARK: - Read Mode (Original)
    
    private var readModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap any sentence to mark your progress")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                        Text(sentence)
                            .font(.body)
                            .foregroundColor(sentenceColor(for: index))
                            .padding(.vertical, 4)
                            .onTapGesture {
                                selectedSentenceIndex = index
                            }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            if let selected = selectedSentenceIndex {
                HStack {
                    Text("Progress: \(selected + 1) / \(sentences.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Reset") {
                        selectedSentenceIndex = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Type Mode
    
    private var typeModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress indicator
            HStack {
                Text("Sentences \(currentTypingIndex + 1)-\(min(currentTypingIndex + 2, sentences.count)) of \(sentences.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Reset") {
                    currentTypingIndex = 0
                    typedText = ""
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            if currentTypingIndex < sentences.count {
                // Original sentences (dimmed) - show 2 at a time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sentences[currentTypingIndex])
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if currentTypingIndex + 1 < sentences.count {
                            Text(sentences[currentTypingIndex + 1])
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                
                // Typing area
                // Typing area
                // Typing area
                // Typing area
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Type it out:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Press Enter to continue")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    CatalystTextEditor(text: $typedText, onEnterPressed: {
                        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            nextSentence()
                        }
                    })
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isTextFieldFocused)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Skip") {
                        nextSentence()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Next") {
                        nextSentence()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                // Completion
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("Practice Complete!")
                        .font(.headline)
                    
                    Text("You've typed all \(sentences.count) sentences.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Start Over") {
                        currentTypingIndex = 0
                        typedText = ""
                        isTextFieldFocused = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Helpers
    
    private func nextSentence() {
        typedText = ""  // Clear first
        
        if currentTypingIndex + 2 < sentences.count {
            currentTypingIndex += 2
        } else {
            currentTypingIndex = sentences.count
        }
        
        // Refocus after advancing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func sentenceColor(for index: Int) -> Color {
        guard let selected = selectedSentenceIndex else {
            return .primary
        }
        
        if index <= selected {
            return .secondary // Already processed
        } else {
            return .primary // Not yet processed
        }
    }
    
    private func parseSentences(from text: String) -> [String] {
        return SentenceParser.parse(text)
    }
}


import UIKit
import SwiftUI

struct CatalystTextEditor: UIViewRepresentable {
    @Binding var text: String
    let onEnterPressed: () -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = EnterHandlingTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.onEnterPressed = onEnterPressed
        textView.text = text
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: CatalystTextEditor
        
        init(_ parent: CatalystTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

class EnterHandlingTextView: UITextView {
    var onEnterPressed: (() -> Void)?
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleEnter))
        ]
    }
    
    @objc func handleEnter() {
        onEnterPressed?()
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var didHandleEvent = false
        for press in presses {
            guard let key = press.key else { continue }
            
            // Check for Enter without modifiers
            if key.keyCode == .keyboardReturnOrEnter && key.modifierFlags.isEmpty {
                onEnterPressed?()
                didHandleEvent = true
            }
        }
        
        if !didHandleEvent {
            super.pressesBegan(presses, with: event)
        }
    }
}
