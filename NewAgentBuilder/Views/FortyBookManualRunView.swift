//
//  FortyBookManualRunView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 7/9/25.
//

import SwiftUI

struct FortyBookManualRunView: View {
    @StateObject private var viewModel = FortyManualRunViewModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                                Button("Clear All") {
                                    viewModel.clearAll()
                                }
                                .foregroundColor(.red)
                                
                                Spacer()
                                
                                Toggle("Debug Mode", isOn: $viewModel.debugMode)
                                    .toggleStyle(SwitchToggleStyle())
                            }
                CopyButtonsView(
                                 stepOutputs: viewModel.stepOutputs,
                                 originalInput: viewModel.droppedInput
                             )
                CopyButton(label: "Copy all Text", valueToCopy: viewModel.getFormattedOutput())

                ResultsView2(stepOutputs: viewModel.stepOutputs)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
                InputBarPasteOnly { inputText in
                    viewModel.droppedInput = inputText
                    print("✅ droppedInput set to \(inputText.prefix(40))...")
                    Task { await viewModel.createStepOutputs() }
                } onTopRightTap: {
                    print("ℹ️ Top-right tap (InputBar2)")
                }
            
        }
    }
}




struct CopyButtonsView: View {
    var stepOutputs: [String]
    var originalInput: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stepOutputs.isEmpty {
                Text("No outputs to copy yet.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                Text("📋 Copy Test Data")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(stepOutputs.indices, id: \.self) { index in
                            CopyButtonRow(
                                index: index,
                                swiftInput: extractSwiftFunction(from: originalInput, at: index),
                                kotlinOutput: stepOutputs[index]
                            )
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
    
    // Helper to extract individual Swift functions from the original input
    private func extractSwiftFunction(from input: String, at index: Int) -> String {
        let functions = splitIntoFunctions(input)
        return index < functions.count ? functions[index] : "Function \(index + 1) not found"
    }
    
    // Same splitting logic as in your ViewModel
    private func splitIntoFunctions(_ swiftCode: String) -> [String] {
        let lines = swiftCode.components(separatedBy: "\n")
        var functions: [String] = []
        var currentFunction: [String] = []
        var braceCount = 0
        var inFunction = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.contains("func ") && trimmedLine.contains("AttributedString") {
                if inFunction && !currentFunction.isEmpty {
                    functions.append(currentFunction.joined(separator: "\n"))
                }
                
                currentFunction = [line]
                braceCount = 0
                inFunction = true
                
                braceCount += line.filter { $0 == "{" }.count
                braceCount -= line.filter { $0 == "}" }.count
                
            } else if inFunction {
                currentFunction.append(line)
                
                braceCount += line.filter { $0 == "{" }.count
                braceCount -= line.filter { $0 == "}" }.count
                
                if braceCount == 0 {
                    functions.append(currentFunction.joined(separator: "\n"))
                    currentFunction = []
                    inFunction = false
                }
            }
        }
        
        if inFunction && !currentFunction.isEmpty {
            functions.append(currentFunction.joined(separator: "\n"))
        }
        
        return functions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct CopyButtonRow: View {
    let index: Int
    let swiftInput: String
    let kotlinOutput: String
    
    private var testData: String {
        return "RAW SWIFT Input \(swiftInput) created this output \(kotlinOutput)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Function identifier
            Text("Function \(index + 1)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            // Preview of Swift function name
            if let functionName = extractFunctionName(from: swiftInput) {
                Text("Swift: \(functionName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Copy button with your exact format
            CopyButton(
                label: "Copy Test Data \(index + 1)",
                valueToCopy: testData,
                font: .caption
            )
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Extract function name for preview
    private func extractFunctionName(from swiftCode: String) -> String? {
        let lines = swiftCode.components(separatedBy: "\n")
        for line in lines {
            if line.contains("func ") && line.contains("AttributedString") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let funcRange = trimmed.range(of: "func "),
                   let parenRange = trimmed.range(of: "()") {
                    let functionName = String(trimmed[funcRange.upperBound..<parenRange.lowerBound])
                    return functionName.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}
