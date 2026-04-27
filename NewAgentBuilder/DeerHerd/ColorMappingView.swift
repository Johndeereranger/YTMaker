//
//  ColorMappingView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


import SwiftUI


// MARK: - ColorMappingView.swift (FIXED)
import SwiftUI

struct ColorMappingView: View {
    @ObservedObject var viewModel: ImportViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Assign Pin Colors")
                .font(.title)
                .fontWeight(.bold)
            
            Text("What does each pin color represent?")
                .foregroundColor(.secondary)
            
            // Dynamic list based on actual KML colors
            List {
                ForEach(Array(viewModel.colorMappings.keys.sorted()), id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(colorForString(color))
                            .frame(width: 30, height: 30)
                        
                        Text(color.capitalized)
                            .font(.headline)
                        
                        Spacer()
                        
                        Picker("", selection: Binding(
                            get: { viewModel.colorMappings[color] ?? .buck },
                            set: { viewModel.colorMappings[color] = $0 }
                        )) {
                            ForEach(DeerClassification.allCases, id: \.self) { classification in
                                Text(classification.rawValue).tag(classification)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            
//            Button("Confirm & Match") {
//                Task {
//                    await viewModel.confirmColorMappings()
//                }
//            }
//            .buttonStyle(.borderedProminent)
//            .disabled(viewModel.isProcessing)
            Button("Confirm & Save") {
                Task {
                    if viewModel.selectedProperty != nil {
                        await viewModel.confirmColorMappings()
                    } else {
                        await viewModel.confirmColorMappingsGlobally()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)
            
            if viewModel.isProcessing {
                ProgressView("Matching photos to pins...")
            }
        }
        .padding()
    }
    
    private func colorForString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}
