//
//  NewImportWizardView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/28/25.
//
//
//
// MARK: - NewImportWizard.swift
// Completely new import flow for KML + Photo matching
// Preserves old KMLMatchResultsView - uses entirely new names
import SwiftUI
import MapKit
import UniformTypeIdentifiers

// MARK: - New Import Wizard Entry Point
struct NewImportWizardView: View {
    @StateObject private var wizardViewModel = ImportWizardViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                switch wizardViewModel.currentStep {
                case .kmlImport:
                    KMLImportStepView(viewModel: wizardViewModel)
                case .photoSelection:
                    PhotoFolderSelectionView(viewModel: wizardViewModel)
                case .propertyMatching:
                    PropertyMatchingStepView(viewModel: wizardViewModel)
                case .confirmation:
                    ImportConfirmationView(viewModel: wizardViewModel)
                }
            }
            .navigationTitle(wizardViewModel.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Import Wizard View Model
@MainActor
class ImportWizardViewModel: ObservableObject {
    enum ImportStep {
        case kmlImport
        case photoSelection
        case propertyMatching
        case confirmation
        
        var title: String {
            switch self {
            case .kmlImport: return "Import KML"
            case .photoSelection: return "Select Photos"
            case .propertyMatching: return "Match to Property"
            case .confirmation: return "Review & Save"
            }
        }
    }
    
    @Published var currentStep: ImportStep = .kmlImport
    
    // KML data
    @Published var importedPins: [KMLPin] = []
    @Published var kmlFileName: String = ""
    @Published var kmlImportDate: Date?
    
    // Photo data - organized by folder
    @Published var selectedPhotoFolders: [PhotoFolder] = []
    
    // Matching results - per property
    @Published var selectedProperty: Property?
    @Published var matchResultsByFolder: [String: FolderMatchResult] = [:]
    
    // Options
    @Published var importMode: ImportMode = .matchedOnly
    @Published var isProcessing = false
    
    enum ImportMode {
        case matchedOnly  // Only save matched pairs to property
        case allPins      // Save all pins + matches (unmatched available for future matching)
    }
    
    func moveToNextStep() {
        switch currentStep {
        case .kmlImport:
            currentStep = .photoSelection
        case .photoSelection:
            currentStep = .propertyMatching
        case .propertyMatching:
            currentStep = .confirmation
        case .confirmation:
            break
        }
    }
    
    func moveToPreviousStep() {
        switch currentStep {
        case .kmlImport:
            break
        case .photoSelection:
            currentStep = .kmlImport
        case .propertyMatching:
            currentStep = .photoSelection
        case .confirmation:
            currentStep = .propertyMatching
        }
    }
    
    func importKML(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        await MainActor.run {
            self.kmlFileName = url.lastPathComponent
            self.kmlImportDate = Date()
            // TODO: Parse KML and set importedPins
        }
    }
    
    // MARK: - Matching Logic
    func performMatching(for property: Property) {
        // TODO: Implement actual matching logic
        // This will match KML pins to photos within selected folders
        // Filter pins by property boundaries
        // Match based on time + distance thresholds
    }
    
    func saveToDatabase() async {
        // TODO: Implement save logic
        // Based on importMode:
        // - matchedOnly: Save only matched pairs as observations
        // - allPins: Save all pins to global pool + matched pairs as observations
    }
}

// MARK: - Photo Folder Model
struct PhotoFolder: Identifiable {
    let id = UUID()
    let folderName: String
    let timestamp: Date
    let photos: [Photo]
    
    var photoCount: Int {
        photos.count
    }
    
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "\(folderName) - \(formatter.string(from: timestamp))"
    }
}

// MARK: - Folder Match Result
struct FolderMatchResult {
    let folder: PhotoFolder
    var matchedPairs: [(photo: Photo, pin: KMLPin)] = []
    var unmatchedPhotos: [Photo] = []
    var unmatchedPins: [KMLPin] = []
    
    var photoGroupCount: Int {
        let groups = Dictionary(grouping: unmatchedPhotos) { photo in
            if let filename = photo.metadata["filename"] {
                return filename
                    .replacingOccurrences(of: "_T.JPG", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "_V.JPG", with: "", options: .caseInsensitive)
            }
            return photo.id
        }
        return groups.count
    }
}

// MARK: - Step 1: KML Import
struct KMLImportStepView: View {
    @ObservedObject var viewModel: ImportWizardViewModel
    @State private var showFilePicker = false
    @State private var isProcessingKML = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Label("Step 1: Import KML File", systemImage: "1.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Select your KML file containing deer observation pins. All pins will be imported and can be matched to photos in the next steps.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            // KML Status
            if viewModel.importedPins.isEmpty {
                // No KML imported yet
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No KML file selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showFilePicker = true }) {
                        Label("Choose KML File", systemImage: "folder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
            } else {
                // KML imported - show summary
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    VStack(spacing: 8) {
                        Text("KML Imported Successfully")
                            .font(.headline)
                        
                        Text(viewModel.kmlFileName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Pin summary
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(viewModel.importedPins.count)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Pins Found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let date = viewModel.kmlImportDate {
                            VStack {
                                Text(date, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Date Range")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Color breakdown (optional)
                    if !viewModel.importedPins.isEmpty {
                        PinColorBreakdown(pins: viewModel.importedPins)
                    }
                    
                    // Change KML button
                    Button(action: { showFilePicker = true }) {
                        Label("Choose Different KML", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
            
            // Navigation
            if !viewModel.importedPins.isEmpty {
                Button(action: {
                    viewModel.moveToNextStep()
                }) {
                    HStack {
                        Text("Next: Select Photos")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
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
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "kml")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.importKML(from: url)
                }
            case .failure(let error):
                print("❌ KML import failed: \(error)")
            }
        }
    }
}

struct PinColorBreakdown: View {
    let pins: [KMLPin]
    
    private var colorCounts: [(color: String, count: Int)] {
        let grouped = Dictionary(grouping: pins) { $0.color }
        return grouped.map { (color: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin Colors")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(colorCounts, id: \.color) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorFor(item.color))
                            .frame(width: 12, height: 12)
                        Text("\(item.count)")
                            .font(.caption2)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func colorFor(_ color: String) -> Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}

// MARK: - Step 2: Photo Folder Selection
struct PhotoFolderSelectionView: View {
    @ObservedObject var viewModel: ImportWizardViewModel
    @State private var showFolderPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Label("Step 2: Select Photo Folders", systemImage: "2.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Choose one or more photo folders from your drone flights. Each folder should contain thermal (_T) and visual (_V) photo pairs.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding()
            
            // Selected folders list
            if viewModel.selectedPhotoFolders.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No photo folders selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("You can select multiple folders if you have multiple flights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: { showFolderPicker = true }) {
                        Label("Add Photo Folders", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.selectedPhotoFolders) { folder in
                            FolderSummaryCard(folder: folder) {
                                // Remove folder
                                viewModel.selectedPhotoFolders.removeAll { $0.id == folder.id }
                            }
                        }
                    }
                    .padding()
                }
                
                Button(action: { showFolderPicker = true }) {
                    Label("Add More Folders", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding()
            }
            
            // Navigation
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.moveToPreviousStep()
                }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    viewModel.moveToNextStep()
                }) {
                    HStack {
                        Text("Next: Match to Property")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedPhotoFolders.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.selectedPhotoFolders.isEmpty)
            }
            .padding()
        }
        .sheet(isPresented: $showFolderPicker) {
            // TODO: Implement folder picker
            // This should allow selecting multiple folders
            Text("Folder Picker Coming Soon")
        }
    }
}

struct FolderSummaryCard: View {
    let folder: PhotoFolder
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.folderName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(folder.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(folder.photoCount) photos")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Step 3: Property Matching
struct PropertyMatchingStepView: View {
    @ObservedObject var viewModel: ImportWizardViewModel
    @State private var showPropertyPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Label("Step 3: Match to Property", systemImage: "3.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Select which property these observations belong to. We'll match KML pins to photos and show you the results.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding()
            
            // Property Selection
            if let property = viewModel.selectedProperty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Property")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(property.name)
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        showPropertyPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Button(action: { showPropertyPicker = true }) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Select Property")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            Divider().padding(.vertical)
            
            // Import Mode Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Import Strategy")
                    .font(.headline)
                    .padding(.horizontal)
                
                Text("How should we handle pins that don't match photos?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    ImportModeCard(
                        mode: .matchedOnly,
                        isSelected: viewModel.importMode == .matchedOnly,
                        title: "Matched Only",
                        description: "Only save KML pins that match photos in the selected folders",
                        icon: "checkmark.circle.fill"
                    ) {
                        viewModel.importMode = .matchedOnly
                    }
                    
                    ImportModeCard(
                        mode: .allPins,
                        isSelected: viewModel.importMode == .allPins,
                        title: "All Pins",
                        description: "Save all KML pins. Unmatched pins can be matched to photos later",
                        icon: "pin.circle.fill"
                    ) {
                        viewModel.importMode = .allPins
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Navigation
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.moveToPreviousStep()
                }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    performMatching()
                }) {
                    HStack {
                        Text("Review Matches")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedProperty == nil ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.selectedProperty == nil)
            }
            .padding()
        }
        .sheet(isPresented: $showPropertyPicker) {
            // TODO: Implement property picker
            // Should show list of existing properties
            Text("Property Picker Coming Soon")
        }
    }
    
    private func performMatching() {
        // Perform matching logic here
        if let property = viewModel.selectedProperty {
            viewModel.performMatching(for: property)
        }
        viewModel.moveToNextStep()
    }
}

struct ImportModeCard: View {
    let mode: ImportWizardViewModel.ImportMode
    let isSelected: Bool
    let title: String
    let description: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Confirmation
struct ImportConfirmationView: View {
    @ObservedObject var viewModel: ImportWizardViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Step 4: Review & Save", systemImage: "4.circle.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    Text("Review the matching results before saving observations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Import Summary
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import Summary")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if let property = viewModel.selectedProperty {
                        SummaryRow(
                            icon: "map.fill",
                            title: "Property",
                            value: property.name,
                            color: .green
                        )
                    }
                    
                    SummaryRow(
                        icon: "pin.circle.fill",
                        title: "Total KML Pins",
                        value: "\(viewModel.importedPins.count)",
                        color: .blue
                    )
                    
                    SummaryRow(
                        icon: "folder.fill",
                        title: "Photo Folders",
                        value: "\(viewModel.selectedPhotoFolders.count)",
                        color: .orange
                    )
                    
                    SummaryRow(
                        icon: "photo.fill",
                        title: "Total Photos",
                        value: "\(totalPhotos)",
                        color: .purple
                    )
                }
                
                Divider().padding(.vertical)
                
                // Match results per folder
                VStack(alignment: .leading, spacing: 12) {
                    Text("Matching Results")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(viewModel.selectedPhotoFolders) { folder in
                        if let result = viewModel.matchResultsByFolder[folder.id.uuidString] {
                            FolderMatchSummaryCard(folder: folder, result: result)
                        }
                    }
                }
                
                // Mode reminder
                HStack(spacing: 12) {
                    Image(systemName: viewModel.importMode == .matchedOnly ? "checkmark.circle.fill" : "pin.circle.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.importMode == .matchedOnly ? "Matched Only Mode" : "All Pins Mode")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(viewModel.importMode == .matchedOnly ?
                            "Only matched pins will be saved" :
                            "All pins will be saved for future matching")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await saveObservations()
                        }
                    }) {
                        if viewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Save Observations")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(viewModel.isProcessing)
                    
                    Button("Go Back to Edit") {
                        viewModel.moveToPreviousStep()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    private var totalPhotos: Int {
        viewModel.selectedPhotoFolders.reduce(0) { $0 + $1.photoCount }
    }
    
    private func saveObservations() async {
        viewModel.isProcessing = true
        await viewModel.saveToDatabase()
        viewModel.isProcessing = false
        dismiss()
    }
}

struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
    }
}

struct FolderMatchSummaryCard: View {
    let folder: PhotoFolder
    let result: FolderMatchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(folder.folderName)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                Label("\(result.matchedPairs.count)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Label("\(result.photoGroupCount)", systemImage: "photo.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Label("\(result.unmatchedPins.count)", systemImage: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    NewImportWizardView()
}
