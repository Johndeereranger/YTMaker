//
//  DuplicateCleanupView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/3/25.
//
import SwiftUI


// MARK: - Duplicate Cleanup View
struct DuplicateCleanupView: View {
    @Binding var isPresented: Bool
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var duplicateCount = 0
    @State private var deletedCount = 0
    @State private var errorMessage: String?
    @State private var scanComplete = false
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if !scanComplete {
                    // Scanning phase
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Find Duplicate Pins")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("This will scan all pins for exact duplicates (same location, time, name, and color)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if isScanning {
                            ProgressView()
                                .padding()
                            Text("Scanning pins...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                Task {
                                    await scanForDuplicates()
                                }
                            }) {
                                Text("Scan for Duplicates")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    }
                } else if duplicateCount > 0 {
                    // Found duplicates - cleanup phase
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Found \(duplicateCount) Duplicate Pins")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("These pins have exact matches. The oldest copy of each will be deleted, keeping the newest.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if isCleaning {
                            ProgressView()
                                .padding()
                            Text("Deleting duplicates...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if deletedCount > 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                
                                Text("Deleted \(deletedCount) Duplicates")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Button("Done") {
                                    isPresented = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Button(action: {
                                    Task {
                                        await cleanupDuplicates()
                                    }
                                }) {
                                    Text("Delete Duplicates")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                                .padding(.horizontal)
                                
                                Button("Cancel") {
                                    isPresented = false
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    // No duplicates found
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("No Duplicates Found")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("All pins are unique")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Done") {
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                if let error = errorMessage {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Clean Up Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func scanForDuplicates() async {
        isScanning = true
        errorMessage = nil
        
        do {
            let duplicates = try await firebaseManager.findDuplicatePins()
            
            // Count total duplicate pins (not sets)
            duplicateCount = duplicates.reduce(0) { $0 + $1.count - 1 }
            scanComplete = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isScanning = false
    }
    
    private func cleanupDuplicates() async {
        isCleaning = true
        errorMessage = nil
        
        do {
            deletedCount = try await firebaseManager.deleteDuplicatePins()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isCleaning = false
    }
}
