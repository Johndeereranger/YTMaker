//
//  OptionalKMLView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


import SwiftUI
import UniformTypeIdentifiers

struct OptionalKMLView: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var isDragging = false
    @State private var isFileImporterPresented = false
    @State private var statusMessage: String = "" // NEW: Status feedback
    @State private var statusColor: Color = .secondary // NEW: Status color
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add KML")
                .font(.title)
                .fontWeight(.bold)
            
            Text("KML files add deer classifications (buck/doe) to your photos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // NEW: Status Message
            if !statusMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal)
                .transition(.opacity)
            }
            
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
                        isFileImporterPresented = true
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
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "kml")!, UTType(filenameExtension: "kmz")!],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporter(result: result)
        }
    }
    
    // MARK: - Status Helper
    
    private var statusIcon: String {
        switch statusColor {
        case .green:
            return "checkmark.circle.fill"
        case .red:
            return "xmark.circle.fill"
        case .blue, .orange:
            return "arrow.triangle.2.circlepath"
        default:
            return "info.circle"
        }
    }
    
    private func setStatus(_ message: String, color: Color) {
        withAnimation {
            statusMessage = message
            statusColor = color
        }
        
        // Auto-clear success messages after 3 seconds
        if color == .green {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    if self.statusMessage == message {
                        self.statusMessage = ""
                    }
                }
            }
        }
    }
    
    // MARK: - File Handling
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("🔵 KML Drop: \(providers.count) providers")
        setStatus("Processing drop...", color: .blue)
        
        var handled = false
        
        for (index, provider) in providers.enumerated() {
            print("  Provider \(index): \(provider)")
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                print("  ✓ Has fileURL type")
                
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let error = error {
                        print("  ❌ Error: \(error)")
                        DispatchQueue.main.async {
                            self.setStatus("Error: \(error.localizedDescription)", color: .red)
                        }
                        return
                    }
                    
                    guard let url = url else {
                        print("  ❌ URL is nil")
                        DispatchQueue.main.async {
                            self.setStatus("Invalid file", color: .red)
                        }
                        return
                    }
                    
                    let ext = url.pathExtension.lowercased()
                    print("  📁 File: \(url.lastPathComponent)")
                    print("  📝 Extension: '\(ext)'")
                    
                    guard ["kml", "kmz"].contains(ext) else {
                        print("  ❌ Invalid extension: '\(ext)'")
                        DispatchQueue.main.async {
                            self.setStatus("Invalid file - need .kml or .kmz", color: .red)
                        }
                        return
                    }
                    
                    print("  ✅ Valid KML/KMZ - importing")
                    DispatchQueue.main.async {
                        self.setStatus("Importing \(url.lastPathComponent)...", color: .blue)
                        Task {
                            await self.importKML(from: url)
                        }
                    }
                }
                handled = true
            } else {
                print("  ❌ No fileURL type")
                print("  Available: \(provider.registeredTypeIdentifiers)")
            }
        }
        
        if !handled {
            print("🔴 No valid provider")
            setStatus("Unable to read file", color: .red)
        }
        
        return handled
    }
    
    private func handleFileImporter(result: Result<[URL], Error>) {
        print("🔵 File Importer Result")
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                print("  ❌ No URL in result")
                setStatus("No file selected", color: .red)
                return
            }
            
            let ext = url.pathExtension.lowercased()
            print("  📁 Selected: \(url.lastPathComponent)")
            print("  📝 Extension: '\(ext)'")
            
            guard ["kml", "kmz"].contains(ext) else {
                print("  ❌ Invalid extension")
                setStatus("Invalid file - need .kml or .kmz", color: .red)
                viewModel.errorMessage = "Please select a KML or KMZ file"
                return
            }
            
            print("  ✅ Valid file - importing")
            setStatus("Importing \(url.lastPathComponent)...", color: .blue)
            Task {
                await importKML(from: url)
            }
            
        case .failure(let error):
            print("  ❌ Import failed: \(error)")
            setStatus("Import failed: \(error.localizedDescription)", color: .red)
            viewModel.errorMessage = error.localizedDescription
        }
    }
    private func importKML(from url: URL) async {
        print("🟢 importKML: \(url.lastPathComponent)")
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                await MainActor.run {
                    setStatus("File not found", color: .red)
                }
                return
            }
            
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            
            if fileSize == 0 {
                await MainActor.run {
                    setStatus("File is empty", color: .red)
                }
                return
            }
            
            // Check if we have a property selected
            if viewModel.selectedProperty != nil {
                await viewModel.importKML(from: url)
            } else {
                await viewModel.importKMLGlobally(from: url)
            }
            
            await MainActor.run {
                setStatus("✓ KML imported successfully", color: .green)
            }
            
        } catch {
            await MainActor.run {
                setStatus("Import error: \(error.localizedDescription)", color: .red)
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
    private func importKMLold(from url: URL) async {
        print("🟢 importKML: \(url.lastPathComponent)")
        
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Check file exists and is readable
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("  ❌ File doesn't exist at path")
                await MainActor.run {
                    setStatus("File not found", color: .red)
                }
                return
            }
            
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            print("  📊 File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("  ⚠️ File is empty")
                await MainActor.run {
                    setStatus("File is empty", color: .red)
                }
                return
            }
            
            // Actually import via viewModel
            await viewModel.importKML(from: url)
            
            print("  ✅ Import completed")
            await MainActor.run {
                setStatus("✓ KML imported successfully", color: .green)
            }
            
        } catch {
            print("  ❌ Error: \(error)")
            await MainActor.run {
                setStatus("Import error: \(error.localizedDescription)", color: .red)
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

