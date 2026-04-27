//
//  DeerImageUploadView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/4/25.
//


import SwiftUI
import UniformTypeIdentifiers

struct DeerImageUploadView: View {
    @StateObject private var viewModel = DeerImageUploadViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Load Historical Data")
                    .font(.headline)
                HStack {
                    Text("Year:")
                    TextField("2024", value: $viewModel.year, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Button("Load") {
                        viewModel.loadData(for: viewModel.year)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Divider()
            // 🖼️ Image Section or Drop Zone
            if let original = viewModel.selectedImage {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Original Image
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Year:")
                                TextField("2024", value: $viewModel.year, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                            
                            Text("Y-axis tick values (bottom to top):")
                                .font(.caption)
                            
                            ScrollView {
                                ForEach(0..<viewModel.yTickValues.count, id: \.self) { i in
                                    HStack {
                                        Text("Tick \(i+1):")
                                            .frame(width: 60, alignment: .leading)
                                        TextField("Value", value: $viewModel.yTickValues[i], format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                    }
                                }
                            }
                            .frame(height: 150)
                            
                            Button("Analyze") {
                                viewModel.analyzeImage()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.yTickValues.isEmpty)
                        }

                        // Debug Image
                        if let debug = viewModel.debugImage {
                            VStack(spacing: 4) {
                                Text("Debug Overlay")
                                    .font(.caption)
                                Image(uiImage: debug)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 600, height: 600)
                                    .border(Color.red)
                            }
                        }
                    }
     

                    // Data Table
                    if !viewModel.barValues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("📊 Harvest Data")
                                .font(.headline)

                            ScrollView {
                                ForEach(viewModel.barValues) { bar in
                                    HStack {
                                        Text(bar.date)
                                            .frame(width: 80, alignment: .leading)
                                        Text("\(bar.value)")
                                            .bold()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .frame(height: 300)
                        }
                    }
                }

                Divider().padding(.vertical)

                // Reset Button
                Button("Reset") {
                    viewModel.selectedImage = nil
                    viewModel.debugImage = nil
                    viewModel.barValues = []
                }
                .buttonStyle(.bordered)
            } else {
                // Drop Zone
                VStack {
                    Text("Drop graph image here")
                        .font(.headline)
                        .padding(.bottom, 8)

                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 400, height: 300)
                        .cornerRadius(12)
                        .overlay(
                            Text("Drag & drop an image")
                                .foregroundColor(.secondary)
                        )
                }
            }
        }
        .padding()
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        viewModel.loadImage(image)  // Don't analyze yet!
                    }
                }
                handled = true
            }
        }
        return handled
    }
    private func handleDropold(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        viewModel.selectedImage = image
                        viewModel.analyzeImage()
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
