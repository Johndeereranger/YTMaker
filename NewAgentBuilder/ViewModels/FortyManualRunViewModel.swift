//
//  FortyManualRunViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 7/9/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FortyManualRunViewModel: ObservableObject {
    @Published var droppedInput: String = ""
    @Published var stepOutputs: [String] = []
    @Published var isRunning: Bool = false
    @Published var errorMessage: String?
    @Published var singleOutput: String = ""
    @Published var debugMode: Bool = false
    
    init() {}
    
    private var converter: LineByLineSwiftConverter {
        LineByLineSwiftConverter(debugMode: debugMode)
    }
    
    func createStepOutputs() async {
          guard !droppedInput.isEmpty else {
              errorMessage = "No input provided"
              return
          }
          
          isRunning = true
          errorMessage = nil
          
          do {
              let individualFunctions = splitIntoFunctions(droppedInput)
              
              var results: [String] = []
              
              // Convert each function separately
              for (index, function) in individualFunctions.enumerated() {
                  let result = converter.convertSwiftFunction(function)
                  results.append("\(result)")
              }
              
              // Update outputs
              stepOutputs = results
              singleOutput = results.first ?? ""
              
              print("✅ Converted \(individualFunctions.count) functions successfully")
              // Process the input
//              let result = converter.convertSwiftFunction(droppedInput)
//              
//              // Update outputs
//              stepOutputs = [result]
//              singleOutput = result
//              
//              print("✅ Converted function successfully")
              
          } catch {
              errorMessage = "Conversion failed: \(error.localizedDescription)"
              stepOutputs = []
          }
          
          isRunning = false
      }
     
    // Helper function to split Swift code into individual functions
    private func splitIntoFunctions(_ swiftCode: String) -> [String] {
        let lines = swiftCode.components(separatedBy: "\n")
        var functions: [String] = []
        var currentFunction: [String] = []
        var braceCount = 0
        var inFunction = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line starts a function
            if trimmedLine.contains("func ") && trimmedLine.contains("AttributedString") {
                // If we were already building a function, save it
                if inFunction && !currentFunction.isEmpty {
                    functions.append(currentFunction.joined(separator: "\n"))
                }
                
                // Start new function
                currentFunction = [line]
                braceCount = 0
                inFunction = true
                
                // Count braces in the function declaration line
                braceCount += line.filter { $0 == "{" }.count
                braceCount -= line.filter { $0 == "}" }.count
                
            } else if inFunction {
                // Add line to current function
                currentFunction.append(line)
                
                // Count braces
                braceCount += line.filter { $0 == "{" }.count
                braceCount -= line.filter { $0 == "}" }.count
                
                // If braces are balanced, function is complete
                if braceCount == 0 {
                    functions.append(currentFunction.joined(separator: "\n"))
                    currentFunction = []
                    inFunction = false
                }
            }
        }
        
        // Handle case where last function doesn't end properly
        if inFunction && !currentFunction.isEmpty {
            functions.append(currentFunction.joined(separator: "\n"))
        }
        
        return functions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
     // MARK: - Helper Methods
     func clearAll() {
         droppedInput = ""
         stepOutputs = []
         singleOutput = ""
         errorMessage = nil
     }
     
     func exportDayManager() -> String {
         return ""
         // Return the complete DayManager if it exists
//         if let dayManagerIndex = stepOutputs.firstIndex(of: "=== COMPLETE DAY MANAGER ==="),
//            dayManagerIndex + 1 < stepOutputs.count {
//             return stepOutputs[dayManagerIndex + 1]
//         }
//         
//         // Otherwise generate from current outputs
//         let kotlinFunctions = stepOutputs.filter { $0.contains("@Composable") }
//         return converter.generateDayManager(fromConvertedFunctions: kotlinFunctions)
     }
     
     func getFormattedOutput() -> String {
         return stepOutputs.joined(separator: "\n\n")
     }
}
