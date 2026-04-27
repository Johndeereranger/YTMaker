//
//  PatternReferenceGuide.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/4/26.
//


import SwiftUI

struct PatternReferenceGuide: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Curiosity & Tension
                    sectionHeader("CURIOSITY & TENSION MECHANICS")
                    patternCard(.question)
                    patternCard(.delay)
                    patternCard(.tease)
                    patternCard(.data)
                    patternCard(.turn)
                    
                    Divider().padding(.vertical)
                    
                    // Content Flow
                    sectionHeader("CONTENT FLOW & CONNECTION")
                    patternCard(.ramble)
                    patternCard(.crossPromo)
                    
                    Divider().padding(.vertical)
                    
                    // Credibility
                    sectionHeader("CREDIBILITY BUILDING")
                    patternCard(.authority)
                    patternCard(.shield)
                    patternCard(.pattern)
                    patternCard(.scope)
                    patternCard(.effortTrust)
                    patternCard(.engageTrap)
                }
                .padding()
            }
            .navigationTitle("Pattern Reference Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.primary)
    }
    
    private func patternCard(_ type: PatternType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                    .font(.title3)
                
                Text(type.rawValue)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(type.color)
            }
            
            Text(type.description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !type.examples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(type.examples, id: \.self) { example in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(example)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(type.color.opacity(0.05))
        .cornerRadius(12)
    }
}