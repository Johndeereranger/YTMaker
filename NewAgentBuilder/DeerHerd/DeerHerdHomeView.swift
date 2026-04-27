//
//  DeerHerdHomeView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - DeerHerdHomeView.swift
import SwiftUI

struct DeerHerdHomeView: View {
    @EnvironmentObject var nav: NavigationViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🦌 Deer Herd Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Manage properties, analyze deer populations, and track individual bucks")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                Button(action: {
                    nav.push(.propertyList)
                }) {
                    HStack {
                        Image(systemName: "map.fill")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Properties")
                                .font(.headline)
                            Text("View and manage properties")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    nav.push(.deerSettings)
                }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Settings")
                                .font(.headline)
                            Text("Configure defaults")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top, 40)
    }
}

// MARK: - PropertyListView.swift
import SwiftUI
// MARK: - PropertyListView.swift (Updated with Tools Section)
import SwiftUI

struct PropertyListView: View {
    @StateObject private var viewModel: PropertyListViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showCreateSheet = false
    @State private var showDuplicateCleanup = false
    @State private var isCleaningDuplicates = false
    @State private var cleanupMessage = ""


    init(operatorId: String = "default-operator") {
        _viewModel = StateObject(wrappedValue: PropertyListViewModel())
    }
    
    var body: some View {
        List {
            // SECTION 1: Tools
            Section {
                // Import Pins
                Button(action: {
//                    Task {
//                            try? await DeerHerdFirebaseManager.shared.fixGlobalPins()
//                        }
                    nav.push(.kmlImport)
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                            .foregroundColor(.blue)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Pins")
                                .font(.body)
                            Text("Import KML file with deer locations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                
                Button("🗑️ Delete ALL Photos (DANGER)") {
                    Task {
                        do {
                            try await DeerHerdFirebaseManager.shared.deleteAllPhotos()
                            print("✅ All photos deleted!")
                        } catch {
                            print("❌ Delete failed: \(error)")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                // View All Pins
                Button(action: {
                    nav.push(.allPinsMapView)
                }) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.green)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View All Pins")
                                .font(.body)
                            Text("Browse and manage imported pins")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                             showDuplicateCleanup = true
                         }) {
                             Label("Clean Up Duplicate Pins", systemImage: "trash.circle")
                         }
                         .foregroundColor(.orange)
                
                // View All Photos (future)
                Button(action: {
                    // TODO: Implement photo browser
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.purple)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View All Photos")
                                .font(.body)
                            Text("Browse imported drone photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .disabled(true) // Enable when implemented
                .opacity(0.5)
                
            } header: {
                Text("Tools")
                    .font(.headline)
            }
            
            // SECTION 2: Properties
            Section {
                ForEach(viewModel.properties) { property in
                    PropertyRowView(property: property)
                        .onTapGesture {
                            nav.push(.propertyDetail(property))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteProperty(property)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Properties")
                        .font(.headline)
                    Spacer()
                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("Deer Herd")
        .sheet(isPresented: $showCreateSheet) {
            PropertyCreateView(onCreate: { name, state, clientEmail, notes in
                Task {
                    await viewModel.createProperty(name: name, state: state, clientEmail: clientEmail, notes: notes)
                    showCreateSheet = false
                }
            })
        }
        .task {
            await viewModel.loadProperties()
        }
        .sheet(isPresented: $showDuplicateCleanup) {
                  DuplicateCleanupView(isPresented: $showDuplicateCleanup)
              }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading properties...")
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}
struct PropertyListViewOld: View {
    @StateObject private var viewModel: PropertyListViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showCreateSheet = false
    
    init(operatorId: String = "default-operator") {
        _viewModel = StateObject(wrappedValue: PropertyListViewModel())
    }
    
    var body: some View {
        List {
            ForEach(viewModel.properties) { property in
                PropertyRowView(property: property)
                    .onTapGesture {
                        nav.push(.propertyDetail(property))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteProperty(property)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                   Button(action: {
                       nav.push(.kmlImport)
                   }) {
                       Label("Import Pins", systemImage: "mappin")
                   }
               }
               
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button(action: { showCreateSheet = true }) {
                       Image(systemName: "plus")
                   }
               }
        }
        .sheet(isPresented: $showCreateSheet) {
            PropertyCreateView(onCreate: { name, state, clientEmail, notes in
                Task {
                    await viewModel.createProperty(name: name, state: state, clientEmail: clientEmail, notes: notes)
                    showCreateSheet = false
                }
            })
        }
        .task {
            await viewModel.loadProperties()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading properties...")
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}

struct PropertyRowView: View {
    let property: Property
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(property.name)
                    .font(.headline)
                Spacer()
                Text(property.state)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let acres = property.totalAcres {
                Text("\(String(format: "%.1f", acres)) acres")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = property.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PropertyCreateView.swift
import SwiftUI

struct PropertyCreateView: View {
    @Environment(\.dismiss) var dismiss
    let onCreate: (String, String, String?, String?) -> Void
    
    @State private var name = ""
    @State private var state = ""
    @State private var clientEmail = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Property Information") {
                    TextField("Property Name", text: $name)
                    TextField("State", text: $state)
                }
                
                Section("Client (Optional)") {
                    TextField("Client Email", text: $clientEmail)
                }
                
                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("New Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(
                            name,
                            state,
                            clientEmail.isEmpty ? nil : clientEmail,
                            notes.isEmpty ? nil : notes
                        )
                    }
                    .disabled(name.isEmpty || state.isEmpty)
                }
            }
        }
    }
}

// MARK: - PropertyDetailView.swift
import SwiftUI
// MARK: - PropertyDetailView.swift (UPDATED)
import SwiftUI

// MARK: - PropertyDetailView.swift (COMPLETE)
import SwiftUI

struct PropertyDetailView: View {
    let property: Property
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showNuclearResetConfirmation = false
    @State private var isNuking = false
    @State private var nukeError: String?
    
    var body: some View {
        List {
            Section("Actions") {
                // EXISTING BUTTONS
                Button(action: {
                    nav.push(.importPhotos(property))
                }) {
                    Label("Import Flight Data (Legacy)", systemImage: "arrow.down.doc.fill")
                }
                
                Button(action: {
                    nav.push(.newImportWizard)
                }) {
                    Label("Import Wizard", systemImage: "arrow.down.doc.fill")
                }
                
                // NEW: Photo import with auto-matching
                Button(action: {
                    nav.push(.propertyPhotoImportFlow(property))
                }) {
                    Label("Import Photos", systemImage: "photo.badge.plus")
                }
                .foregroundColor(.blue)
                
                // NEW: Review unmatched (placeholder for now)
                Button(action: {
                    // TODO: Navigate to manual matching screen
                    print("⚠️ Review Unmatched - Not implemented yet")
                }) {
                    Label("Review Unmatched", systemImage: "questionmark.square.dashed")
                }
                .foregroundColor(.orange)
                
                Divider()
                
                Button(action: {
                    nav.push(.mapView(property))
                }) {
                    Label("View Map", systemImage: "map.fill")
                }
                
                Button(action: {
                    nav.push(.buckProfileList(property))
                }) {
                    Label("Buck Profiles", systemImage: "person.2.fill")
                }
                
                Button(action: {
                    nav.push(.deerReport(property))
                }) {
                    Label("Generate Report", systemImage: "doc.text.fill")
                }
            }
            
            Section("Property Info") {
                LabeledContent("Name", value: property.name)
                LabeledContent("State", value: property.state)
                
                if let acres = property.totalAcres {
                    LabeledContent("Acres", value: String(format: "%.1f", acres))
                }
                
                if let clientEmail = property.clientEmail {
                    LabeledContent("Client", value: clientEmail)
                }
                
                if let notes = property.notes, !notes.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(notes)
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Danger Zone")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    
                    Text("Permanently delete all data for this property. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showNuclearResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Property Data")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .navigationTitle(property.name)
        .alert("Delete All Property Data?", isPresented: $showNuclearResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                Task {
                    await performNuclearReset()
                }
            }
        } message: {
            Text("This will permanently delete:\n• All pins\n• All photos (including storage)\n• All observations\n• All sessions\n• All buck profiles\n• Property boundary\n\nThe property itself will remain but will be empty.\n\nThis cannot be undone.")
        }
        .alert("Error", isPresented: .constant(nukeError != nil)) {
            Button("OK") {
                nukeError = nil
            }
        } message: {
            if let error = nukeError {
                Text(error)
            }
        }
        .overlay {
            if isNuking {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Deleting all property data...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                }
            }
        }
    }
    
    // MARK: - Nuclear Reset
    
    private func performNuclearReset() async {
        isNuking = true
        
        do {
            try await DeerHerdFirebaseManager.shared.nukePropertyData(property.id)
            
            // Success - dismiss back to property list
            await MainActor.run {
                nav.pop()
            }
        } catch {
            nukeError = "Failed to delete property data: \(error.localizedDescription)"
        }
        
        isNuking = false
    }
}
struct PropertyDetailViewOld: View {
    let property: Property
    @EnvironmentObject var nav: NavigationViewModel
    
    var body: some View {
        List {
            Section("Actions") {
                Button(action: {
                    nav.push(.importPhotos(property))
                }) {
                    Label("Import Flight Data OLD", systemImage: "arrow.down.doc.fill")
                }
                Button(action: {
                    nav.push(.newImportWizard)
                }) {
                    Label(" Import Wizzard ", systemImage: "arrow.down.doc.fill")
                }
                
                Button(action: {
                    nav.push(.mapView(property))
                }) {
                    Label("View Map", systemImage: "map.fill")
                }
                
                Button(action: {
                    nav.push(.buckProfileList(property))
                }) {
                    Label("Buck Profiles", systemImage: "person.2.fill")
                }
                
                Button(action: {
                    nav.push(.deerReport(property))
                }) {
                    Label("Generate Report", systemImage: "doc.text.fill")
                }
            }
            
            Section("Property Info") {
                LabeledContent("Name", value: property.name)
                LabeledContent("State", value: property.state)
                
                if let acres = property.totalAcres {
                    LabeledContent("Acres", value: String(format: "%.1f", acres))
                }
                
                if let clientEmail = property.clientEmail {
                    LabeledContent("Client", value: clientEmail)
                }
                
                if let notes = property.notes, !notes.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(notes)
                    }
                }
            }
        }
        .navigationTitle(property.name)
    }
}
//
//// MARK: - ImportFlowView.swift
//import SwiftUI
//
//struct ImportFlowView: View {
//    let property: Property
//    @StateObject private var viewModel: ImportViewModel
//    @EnvironmentObject var nav: NavigationViewModel
//    @Environment(\.dismiss) var dismiss
//    
//    init(property: Property) {
//        self.property = property
//        _viewModel = StateObject(wrappedValue: ImportViewModel())
//    }
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                switch viewModel.currentStep {
//                case .selectProperty:
//                    Text("Select Property") // Not used since property is passed in
//                case .importPhotos:
//                    ImportPhotosView(viewModel: viewModel)
//                case .importKML:
//                    ImportKMLView(viewModel: viewModel)
//                case .colorMapping:
//                    ColorMappingView(viewModel: viewModel)
//                case .reviewMatches:
//                    MatchReviewView(viewModel: viewModel)
//                case .complete:
//                    ImportCompleteView(viewModel: viewModel, property: property)
//                }
//            }
//            .navigationTitle("Import Flight Data")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//        .onAppear {
//            viewModel.selectedProperty = property
//            viewModel.currentStep = .importPhotos
//        }
//    }
//}
//
//// MARK: - ImportPhotosView.swift
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct ImportPhotosView: View {
//    @ObservedObject var viewModel: ImportViewModel
//    @State private var isFileImporterPresented = false
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            Image(systemName: "photo.on.rectangle.angled")
//                .font(.system(size: 80))
//                .foregroundColor(.blue)
//            
//            Text("Import Photos")
//                .font(.title)
//                .fontWeight(.bold)
//            
//            Text("Select JPG photos from your drone flight")
//                .multilineTextAlignment(.center)
//                .foregroundColor(.secondary)
//            
//            if viewModel.isProcessing {
//                VStack {
//                    ProgressView(value: viewModel.uploadProgress) {
//                        Text("Uploading photos...")
//                    }
//                    .padding(.horizontal, 40)
//                    
//                    Text("\(Int(viewModel.uploadProgress * 100))%")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//            } else {
//                Button(action: {
//                    isFileImporterPresented = true
//                }) {
//                    Label("Select Photos", systemImage: "folder")
//                        .frame(maxWidth: .infinity)
//                        .padding()
//                        .background(Color.blue)
//                        .foregroundColor(.white)
//                        .cornerRadius(12)
//                }
//                .padding(.horizontal, 40)
//            }
//            
//            if !viewModel.importedPhotos.isEmpty {
//                VStack {
//                    Text("Imported \(viewModel.importedPhotos.count) photos")
//                        .font(.headline)
//                    
//                    Button("Next: Import KML") {
//                        viewModel.currentStep = .importKML
//                    }
//                    .buttonStyle(.borderedProminent)
//                }
//            }
//            
//            Spacer()
//        }
//        .padding()
//        .fileImporter(
//            isPresented: $isFileImporterPresented,
//            allowedContentTypes: [UTType.jpeg, UTType.jpg],
//            allowsMultipleSelection: true
//        ) { result in
//            switch result {
//            case .success(let urls):
//                Task {
//                    await viewModel.importPhotos(from: urls)
//                }
//            case .failure(let error):
//                viewModel.errorMessage = error.localizedDescription
//            }
//        }
//    }
//}
//
//// MARK: - ImportKMLView.swift
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct ImportKMLView: View {
//    @ObservedObject var viewModel: ImportViewModel
//    @State private var isFileImporterPresented = false
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            Image(systemName: "map")
//                .font(.system(size: 80))
//                .foregroundColor(.green)
//            
//            Text("Import KML")
//                .font(.title)
//                .fontWeight(.bold)
//            
//            Text("Select the KML file with deer location pins")
//                .multilineTextAlignment(.center)
//                .foregroundColor(.secondary)
//            
//            if viewModel.isProcessing {
//                ProgressView("Processing KML...")
//            } else {
//                Button(action: {
//                    isFileImporterPresented = true
//                }) {
//                    Label("Select KML File", systemImage: "doc")
//                        .frame(maxWidth: .infinity)
//                        .padding()
//                        .background(Color.green)
//                        .foregroundColor(.white)
//                        .cornerRadius(12)
//                }
//                .padding(.horizontal, 40)
//            }
//            
//            if !viewModel.kmlPins.isEmpty {
//                VStack {
//                    Text("Found \(viewModel.kmlPins.count) pins")
//                        .font(.headline)
//                    
//                    Button("Next: Configure Colors") {
//                        viewModel.currentStep = .colorMapping
//                    }
//                    .buttonStyle(.borderedProminent)
//                }
//            }
//            
//            Spacer()
//        }
//        .padding()
//        .fileImporter(
//            isPresented: $isFileImporterPresented,
//            allowedContentTypes: [UTType.kml, UTType.xml],
//            allowsMultipleSelection: false
//        ) { result in
//            switch result {
//            case .success(let urls):
//                if let url = urls.first {
//                    Task {
//                        await viewModel.importKML(from: url)
//                    }
//                }
//            case .failure(let error):
//                viewModel.errorMessage = error.localizedDescription
//            }
//        }
//    }
//}

// MARK: - ColorMappingView.swift
//import SwiftUI
//
//struct ColorMappingView: View {
//    @ObservedObject var viewModel: ImportViewModel
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("Assign Pin Colors")
//                .font(.title)
//                .fontWeight(.bold)
//            
//            Text("What does each pin color represent?")
//                .foregroundColor(.secondary)
//            
//            List {
////                ForEach(Array(viewModel.colorMappings.keys.sorted()), id: \.self) { color in
//                ForEach(viewModel.colorMappings.keys.sorted(), id: \.self) { color in
//                    HStack {
//                        Circle()
//                            .fill(colorForName(color))
//                            .frame(width: 30, height: 30)
//                        
//                        Text(color.capitalized)
//                            .font(.headline)
//                        
//                        Spacer()
//                        
//                        Picker("", selection: Binding(
//                            get: { viewModel.colorMappings[color] ?? .buck },
//                            set: { viewModel.updateColorMapping(color, to: $0) }
//                        )) {
//                            ForEach(DeerClassification.allCases, id: \.self) { classification in
//                                Text(classification.rawValue).tag(classification)
//                            }
//                        }
//                        .pickerStyle(.menu)
//                    }
//                }
//            }
//            
//            Button("Confirm & Match") {
//                Task {
//                    await viewModel.confirmColorMappingsAndMatch()
//                }
//            }
//            .buttonStyle(.borderedProminent)
//            .disabled(viewModel.isProcessing)
//            
//            if viewModel.isProcessing {
//                ProgressView("Matching photos to pins...")
//            }
//        }
//        .padding()
//    }
//    
//    private func colorForName(_ name: String) -> Color {
//        switch name.lowercased() {
//        case "red": return .red
//        case "blue": return .blue
//        case "yellow": return .yellow
//        case "green": return .green
//        case "purple": return .purple
//        default: return .gray
//        }
//    }
//}

//
//// MARK: - MatchReviewView.swift
//import SwiftUI
//
//struct MatchReviewView: View {
//    @ObservedObject var viewModel: ImportViewModel
//    
//    var body: some View {
//        VStack {
//            Text("Review Matches")
//                .font(.title)
//                .fontWeight(.bold)
//                .padding()
//            
//            List {
//                Section("✅ Matched (\(viewModel.matchedObservations.count))") {
//                    ForEach(viewModel.matchedObservations) { obs in
//                        HStack {
//                            Text(obs.classification.rawValue)
//                            Spacer()
//                            Text("\(obs.photos.count) photo(s)")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//                
//                if !viewModel.unmatchedPins.isEmpty {
//                    Section("⚠️ Pins Without Photos (\(viewModel.unmatchedPins.count))") {
//                        ForEach(Array(viewModel.unmatchedPins.enumerated()), id: \.offset) { index, pin in
//                            Text("Pin at \(String(format: "%.5f, %.5f", pin.coordinate.latitude, pin.coordinate.longitude))")
//                        }
//                    }
//                }
//                
//                if !viewModel.unmatchedPhotos.isEmpty {
//                    Section("⚠️ Photos Without Pins (\(viewModel.unmatchedPhotos.count))") {
//                        ForEach(viewModel.unmatchedPhotos) { photo in
//                            HStack {
//                                Text("Photo at \(String(format: "%.5f, %.5f", photo.gpsLat, photo.gpsLon))")
//                                Spacer()
//                                Menu("Assign") {
//                                    ForEach(DeerClassification.allCases, id: \.self) { classification in
//                                        Button(classification.rawValue) {
//                                            viewModel.assignClassificationToPhoto(photo, classification: classification)
//                                        }
//                                    }
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//            
//            Button("Complete Import") {
//                Task {
//                    await viewModel.completeImport()
//                }
//            }
//            .buttonStyle(.borderedProminent)
//            .padding()
//            .disabled(viewModel.isProcessing)
//            
//            if viewModel.isProcessing {
//                ProgressView("Saving observations...")
//            }
//        }
//    }
//}

// MARK: - ImportCompleteView.swift
import SwiftUI

struct ImportCompleteView: View {
    @ObservedObject var viewModel: ImportViewModel
    let property: Property
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Import Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Created \(viewModel.observations.count) deer observations")
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                Button(action: {
                    dismiss()
                    nav.push(.mapView(property))
                }) {
                    Label("View on Map", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}
