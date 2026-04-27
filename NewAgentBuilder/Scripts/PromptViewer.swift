//
//  PromptViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/2/25.
//


import SwiftUI

struct PromptViewer: View {
    @StateObject private var viewModel = PromptViewerViewModel()

    var body: some View {
            VStack {
                // Search bar
                TextField("Search prompts...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.top)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.filteredPrompts) { prompt in
                            PromptCard(prompt: prompt) {
                                // Generate new prompt action - not hooked up yet
                                print("Generate new prompt for ID: \(prompt.id)")
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Prompt Viewer")
            .onAppear {
                Task {
                    await viewModel.loadPrompts()
                }
            }
        
    }
}

struct PromptCard: View {
    let prompt: ImagePrompt
    let onGenerateNewPrompt: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Thumbnail image
            AsyncImage(url: URL(string: prompt.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipped()
                        .cornerRadius(8)
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .cornerRadius(8)
                        .overlay(ProgressView())
                @unknown default:
                    EmptyView()
                }
            }
            
            // Prompt content
            VStack(alignment: .leading, spacing: 12) {
                // Primary prompt text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(prompt.prompt)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("ID:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(prompt.id)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    if let seed = prompt.seed {
                        HStack {
                            Text("Seed:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(seed)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    
                    HStack {
                        if let steps = prompt.samplingSteps {
                            Text("Steps: \(steps)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let guidance = prompt.guidance {
                            Text("Guidance: \(String(format: "%.1f", guidance))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                
                // Generate new prompt button
                Button(action: onGenerateNewPrompt) {
                    HStack {
                        Image(systemName: "wand.and.rays")
                        Text("Generate New Prompt")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer(minLength: 0)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// ViewModel
class PromptViewerViewModel: ObservableObject {
    @Published var prompts: [ImagePrompt] = []
    @Published var searchText: String = ""
    
    var filteredPrompts: [ImagePrompt] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return prompts
        }
        let searchLower = searchText.lowercased()
        return prompts.filter { prompt in
            prompt.prompt.lowercased().contains(searchLower)
        }
    }

    func loadPrompts() async {
        do {
            self.prompts = try await ImagePromptManager.instance.fetchAllPrompts()
        } catch {
            print("❌ Failed to load image prompts: \(error)")
        }
    }
}
