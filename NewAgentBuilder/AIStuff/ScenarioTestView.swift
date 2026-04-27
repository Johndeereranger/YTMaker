//
//  ScenarioTestView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/16/25.
//


import SwiftUI

struct ScenarioTestView: View {
    @StateObject private var viewModel = ScenarioAPIViewModel(
        key: "api_Kgq1M7TG61xWPYGNrd7nLqxc",
        secret: "fhVeRXk9ovUb44XUNGWdZQUA"
    )

    @State private var prompt = "A stick figure climbing a mountain at sunrise"

    var body: some View {
        VStack(spacing: 20) {
            // Input field (optional)
            TextField("Enter Prompt", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // Show image if available
            if let image = viewModel.generatedImages.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

            // Generate button
            Button {
                print("Gnerte Image Pessed")
                Task {
                    await viewModel.generateImages(prompt: prompt)
                }
            } label: {
                Label(viewModel.isLoading ? "Generating..." : "Generate Image", systemImage: "wand.and.stars")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(viewModel.isLoading ? Color.gray.opacity(0.6) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .padding(.horizontal)

            // Error display
            if let error = viewModel.error {
                Text("❌ \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Generating...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
            }
        }
        .animation(.easeInOut, value: viewModel.isLoading)
    }
}
