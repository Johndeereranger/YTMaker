//
//  PropertyPhotoImportFlowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/3/25.
//


// MARK: - PropertyPhotoImportFlowView.swift (NEW FILE)
import SwiftUI

/// Photo import flow for properties - assumes pins already imported
/// Uses global ImportViewModel.instance
/// // MARK: - PropertyPhotoUploadView (ADD DUPLICATE FEEDBACK)

struct PropertyPhotoUploadView: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isProcessing {
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.uploadProgress)
                        .progressViewStyle(.linear)
                    
                    Text(viewModel.processingMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(viewModel.uploadProgress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Select Photos to Import")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose drone photos from your property")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Show stats if photos were imported
                    if !viewModel.importedPhotos.isEmpty {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Imported: \(viewModel.importedPhotos.count) photos")
                            }
                            
                            // Show duplicate count if any
                            if viewModel.skippedDuplicateCount > 0 {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.orange)
                                    Text("Skipped: \(viewModel.skippedDuplicateCount) duplicates")
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Button(action: {
                        showFilePicker = true
                    }) {
                        Label("Choose Photos", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(viewModel.isProcessing)
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.jpeg, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await viewModel.importPhotos(from: urls)
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }
}
struct PropertyPhotoImportFlowView: View {
    let property: Property
    @EnvironmentObject var viewModel: ImportViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                switch viewModel.currentStep {
                case .importPhotos:
                    PropertyPhotoUploadView(viewModel: viewModel)
                    
                case .matchKML:
                    // Reuse existing match results view
                    KMLMatchResultsView(viewModel: viewModel)
                    
                case .complete:
                    PropertyPhotoCompleteView(viewModel: viewModel, property: property)
                    
                default:
                    // Shouldn't hit other steps in this flow
                    Text("Unexpected step: \(String(describing: viewModel.currentStep))")
                }
            }
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Set up for property photo import
            viewModel.selectedProperty = property
            viewModel.currentStep = .importPhotos
            
            // Load unassigned pins in background
            Task {
                await viewModel.loadUnassignedPinsForMatching()
            }
        }
        .onDisappear {
            // Clean up when leaving flow
            viewModel.reset()
        }
    }
}

// MARK: - Step 1: Photo Upload View
struct PropertyPhotoUploadView2: View {
    @ObservedObject var viewModel: ImportViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            if !viewModel.isProcessing && viewModel.importedPhotos.isEmpty {
                // Instructions
                VStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Text("Photos will be automatically matched to existing pins")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    if viewModel.kmlPins.isEmpty {
                        Text("⚠️ No unassigned pins found. Photos will be marked as 'Unknown'.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal)
                    } else {
                        Text("✅ \(viewModel.kmlPins.count) pins available for matching")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.bottom)
            }
            
            // Reuse existing drag & drop view
            ImportPhotosViewDragDrop(viewModel: viewModel)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 3: Complete Screen
// MARK: - PropertyPhotoCompleteView (SHOW DUPLICATES)

struct PropertyPhotoCompleteView: View {
    @ObservedObject var viewModel: ImportViewModel
    let property: Property
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            // Title
            Text("Import Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            // Stats
            VStack(spacing: 12) {
                HStack(spacing: 40) {
                    StatBox(
                        value: "\(viewModel.matchedPairs.count)",
                        label: "Matched",
                        color: .green
                    )
                    
                    StatBox(
                        value: "\(viewModel.unmatchedPhotos.count)",
                        label: "Unmatched",
                        color: .orange
                    )
                }
                
                Text("\(viewModel.observations.count) total observations created")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // ONLY THING ADDED: Show duplicates if any
                if viewModel.skippedDuplicateCount > 0 {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text("Skipped \(viewModel.skippedDuplicateCount) duplicate photos")
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 16) {
                // Primary: View on Map
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        nav.push(.mapView(property))
                    }
                }) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("View on Property Map")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Secondary: Import More
                Button(action: {
                    // Reset and stay in flow for another batch
                    viewModel.currentStep = .importPhotos
                    viewModel.importedPhotos = []
                    viewModel.observations = []
                    viewModel.matchedPairs = []
                    viewModel.unmatchedPhotos = []
                    // Keep kmlPins loaded for next batch
                }) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Import More Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                // Tertiary: Back to Property
                Button(action: {
                    dismiss()
                }) {
                    Text("Back to Property")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}
struct PropertyPhotoCompleteView2: View {
    @ObservedObject var viewModel: ImportViewModel
    let property: Property
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            // Title
            Text("Import Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            // Stats
            VStack(spacing: 12) {
                HStack(spacing: 40) {
                    StatBox(
                        value: "\(viewModel.matchedPairs.count)",
                        label: "Matched",
                        color: .green
                    )
                    
                    StatBox(
                        value: "\(viewModel.unmatchedPhotos.count)",
                        label: "Unmatched",
                        color: .orange
                    )
                }
                
                Text("\(viewModel.observations.count) total observations created")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 16) {
                // Primary: View on Map
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        nav.push(.mapView(property))
                    }
                }) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("View on Property Map")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Secondary: Import More
                Button(action: {
                    // Reset and stay in flow for another batch
                    viewModel.currentStep = .importPhotos
                    viewModel.importedPhotos = []
                    viewModel.observations = []
                    viewModel.matchedPairs = []
                    viewModel.unmatchedPhotos = []
                    // Keep kmlPins loaded for next batch
                }) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Import More Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                // Tertiary: Back to Property
                Button(action: {
                    dismiss()
                }) {
                    Text("Back to Property")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Helper Views
struct StatBox: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
