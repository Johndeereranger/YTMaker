//
//  ImportFlowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - ImportFlowView.swift (Updated)
import SwiftUI

import SwiftUI

struct ImportFlowView: View {
    let property: Property
    //@StateObject private var viewModel: ImportViewModel
    @EnvironmentObject var viewModel: ImportViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
//    init(property: Property) {
//        self.property = property
//        _viewModel = StateObject(wrappedValue: ImportViewModel())
//    }
    
    var body: some View {
        NavigationView {
            Group {
                switch viewModel.currentStep {
                case .selectProperty:
                    Text("Select Property")
                case .importPhotos:
                    UnifiedImportView(viewModel: viewModel)
                case .reviewPhotos:
                    ReviewPhotosView(viewModel: viewModel)
                case .optionalKML:
                    UnifiedImportView(viewModel: viewModel)
                case .colorMapping:
                    ColorMappingView(viewModel: viewModel)
                case .matchKML:
                    KMLMatchResultsView(viewModel: viewModel)
                case .complete:
                    ImportCompleteView(viewModel: viewModel, property: property)
                }
            }
            .navigationTitle("Import Flight Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.selectedProperty = property
            viewModel.currentStep = .importPhotos
        }
    }
}

/// MARK: - UnifiedImportView.swift (REBUILT - Using existing views)
import SwiftUI

struct UnifiedImportView: View {
    @ObservedObject var viewModel: ImportViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // PHOTOS SECTION
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundColor(.blue)
                        Text("Drone Photos")
                            .font(.headline)
                        Spacer()
                        if !viewModel.importedPhotos.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    ImportPhotosViewDragDrop(viewModel: viewModel)
                        .frame(height: 300)
                }
                .padding(.horizontal)
                
                Divider()
                
                // KML SECTION
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "map")
                            .foregroundColor(.green)
                        Text("KML Classification (Optional)")
                            .font(.headline)
                        Spacer()
                    }
                    
                    OptionalKMLView(viewModel: viewModel)
                        .frame(height: 350)
                }
                .padding(.horizontal)
                
                // CONTINUE BUTTON
                if !viewModel.importedPhotos.isEmpty {
                    Button(action: {
                        Task {
                            await viewModel.savePhotosWithoutKML()
                        }
                    }) {
                        Text("Complete Import")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - ImportPhotosViewDragDrop.swift (FIXED)
import SwiftUI
import UniformTypeIdentifiers

struct ImportPhotosViewDragDrop: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var isDragging = false
    @State private var isFileImporterPresented = false
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.importedPhotos.isEmpty && !viewModel.isProcessing {
                // Drag and Drop Zone
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDragging ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isDragging ? Color.blue : Color.gray,
                                       style: StrokeStyle(lineWidth: 3, dash: [10]))
                        )
                    
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundColor(isDragging ? .blue : .gray)
                        
                        Text("Drop Photos Here")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Drag and drop JPG files from your drone")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("or")
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            isFileImporterPresented = true
                        }) {
                            Label("Browse Files", systemImage: "folder")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .padding()
                .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                }
            } else if viewModel.isProcessing {
                VStack(spacing: 20) {
                    ProgressView(value: viewModel.uploadProgress) {
                        Text("Processing photos...")
                    }
                    .padding(.horizontal, 40)
                    
                    if !viewModel.processingMessage.isEmpty {
                        Text(viewModel.processingMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(Int(viewModel.uploadProgress * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            } else {
                // Photos imported - show summary
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Imported \(viewModel.importedPhotos.count) Photos")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Photos are ready to view on the map")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Review Photos") {
                        viewModel.currentStep = .reviewPhotos
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.jpeg, .jpg],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await viewModel.importPhotos(from: urls)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        
        for provider in providers {
            // Try file URL first (when dragging from Finder)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url,
                          ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return }
                    
                    DispatchQueue.main.async {
                        Task {
                            await self.viewModel.importPhotos(from: [url])
                        }
                    }
                }
                handled = true
            }
            
            // Try image data (when dragging from other apps)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data = data else { return }
                    
                    // Write to temp file so we can process it
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("temp_\(UUID().uuidString).jpg")
                    
                    do {
                        try data.write(to: tempURL)
                        DispatchQueue.main.async {
                            Task {
                                await self.viewModel.importPhotos(from: [tempURL])
                            }
                        }
                    } catch {
                        print("Error writing temp file: \(error)")
                    }
                }
                handled = true
            }
        }
        
        return handled
    }
}

// MARK: - OptionalKMLView.swift (FIXED)
import SwiftUI
import UniformTypeIdentifiers


// MARK: - ReviewPhotosView.swift (New)
import SwiftUI
// MARK: - ReviewPhotosView.swift (FIXED)
import SwiftUI

struct ReviewPhotosView: View {
    @ObservedObject var viewModel: ImportViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Review Photos")
                .font(.title)
                .fontWeight(.bold)
            
            // Changed from photoObservations to importedPhotos
            Text("\(viewModel.importedPhotos.count) photos imported")
                .font(.headline)
                .foregroundColor(.secondary)
            
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100))
                ], spacing: 12) {
                    // Changed from photoObservations to importedPhotos
                    ForEach(viewModel.importedPhotos) { photo in
                        AsyncImageView(url: photo.thumbnailUrl ?? photo.firebaseStorageUrl)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            
            VStack(spacing: 12) {
                Text("Do you have a KML file with deer classifications?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 16) {
                    Button("Add KML Later") {
                        Task {
                            await viewModel.savePhotosWithoutKML()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Import KML Now") {
                        viewModel.currentStep = .optionalKML
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}
// MARK: - OptionalKMLView.swift (New)
import SwiftUI
import UniformTypeIdentifiers

struct OptionalKMLView2: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add KML (Optional)")
                .font(.title)
                .fontWeight(.bold)
            
            Text("KML files add deer classifications (buck/doe) to your photos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Drag and Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDragging ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isDragging ? Color.green : Color.gray,
                                   style: StrokeStyle(lineWidth: 3, dash: [10]))
                    )
                
                VStack(spacing: 16) {
                    Image(systemName: "map")
                        .font(.system(size: 80))
                        .foregroundColor(isDragging ? .green : .gray)
                    
                    Text("Drop KML File Here")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("or")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        // File picker fallback
                    }) {
                        Label("Browse for KML", systemImage: "folder")
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .padding()
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
            
            Button("Skip KML - Save Photos Only") {
                Task {
                    await viewModel.savePhotosWithoutKML()
                }
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
        .padding()
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url,
                       ["kml", "kmz"].contains(url.pathExtension.lowercased()) {
                        Task {
                            await viewModel.importKML(from: url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
