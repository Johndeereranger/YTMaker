//
//  PropertyListViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - PropertyListViewModel.swift
import Foundation
import Combine

@MainActor
class PropertyListViewModel: ObservableObject {
    @Published var properties: [Property] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    private var currentOperatorId: String = "default-operator" // TODO: Get from auth
    
    func loadProperties() async {
        isLoading = true
        errorMessage = nil
        
        do {
            properties = try await firebaseManager.fetchProperties(for: currentOperatorId)
            print("✅ Loaded \(properties.count) properties")
        } catch {
            errorMessage = "Failed to load properties: \(error.localizedDescription)"
            print("❌ Error loading properties: \(error)")
        }
        
        isLoading = false
    }
    
    func createProperty(name: String, state: String, clientEmail: String?, notes: String?) async {
        let property = Property(
            operatorId: currentOperatorId,
            name: name,
            state: state,
            clientEmail: clientEmail,
            notes: notes
        )
        
        do {
            try await firebaseManager.createProperty(property)
            await loadProperties()
            print("✅ Created property: \(name)")
        } catch {
            errorMessage = "Failed to create property: \(error.localizedDescription)"
            print("❌ Error creating property: \(error)")
        }
    }
    
    func deleteProperty(_ property: Property) async {
        do {
            try await firebaseManager.deleteProperty(property.id)
            await loadProperties()
            print("✅ Deleted property: \(property.name)")
        } catch {
            errorMessage = "Failed to delete property: \(error.localizedDescription)"
            print("❌ Error deleting property: \(error)")
        }
    }
}

//// MARK: - ImportViewModel.swift
//import Foundation
//import SwiftUI
//import CoreLocation
//
//@MainActor
//class ImportViewModel: ObservableObject {
//    @Published var selectedProperty: Property?
//    @Published var importedPhotos: [Photo] = []
//    @Published var kmlPins: [KMLPin] = []
//    @Published var colorMappings: [String: DeerClassification] = [:]
//    @Published var unmatchedPins: [KMLPin] = []
//    @Published var unmatchedPhotos: [Photo] = []
//    @Published var matchedObservations: [DeerObservation] = []
//    @Published var isProcessing = false
//    @Published var currentStep: ImportStep = .selectProperty
//    @Published var errorMessage: String?
//    @Published var uploadProgress: Double = 0
//    
//    enum ImportStep {
//        case selectProperty
//        case importPhotos
//        case importKML
//        case colorMapping
//        case reviewMatches
//        case complete
//    }
//    
//    private let firebaseManager = DeerHerdFirebaseManager.shared
//    private let xmpParser = XMPMetadataParser.shared
//    private let kmlParser = KMLParser.shared
//    private let coordUtils = CoordinateUtilities.shared
//    private var currentSession: FlightSession?
//    
//    // MARK: - Photo Import
//    
//    func importPhotos(from urls: [URL]) async {
//        guard let property = selectedProperty else { return }
//        
//        isProcessing = true
//        errorMessage = nil
//        importedPhotos = []
//        uploadProgress = 0
//        
//        // Create flight session
//        let session = FlightSession(
//            propertyId: property.id,
//            date: Date(),
//            timeOfDay: FlightSession.TimeOfDay.from(date: Date()),
//            colorMappings: [:]
//        )
//        currentSession = session
//        
//        do {
//            try await firebaseManager.createFlightSession(session)
//        } catch {
//            errorMessage = "Failed to create session: \(error.localizedDescription)"
//            isProcessing = false
//            return
//        }
//        
//        // Process photos
//        let totalPhotos = urls.count
//        for (index, url) in urls.enumerated() {
//            // Skip non-JPG files
//            guard url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" else {
//                continue
//            }
//            
//            guard let metadata = xmpParser.parseMetadata(from: url) else {
//                print("⚠️ Skipping photo with no metadata: \(url.lastPathComponent)")
//                continue
//            }
//            
//            // Check if photo is far from property center (if we have previous observations)
//            if !importedPhotos.isEmpty {
//                let avgLat = importedPhotos.map { $0.gpsLat }.reduce(0, +) / Double(importedPhotos.count)
//                let avgLon = importedPhotos.map { $0.gpsLon }.reduce(0, +) / Double(importedPhotos.count)
//                let propertyCenter = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
//                let photoCoord = CLLocationCoordinate2D(latitude: metadata.gpsLat, longitude: metadata.gpsLon)
//                let distance = coordUtils.distance(from: propertyCenter, to: photoCoord)
//                
//                if distance > 8046.72 { // 5 miles in meters
//                    print("⚠️ Photo is >5 miles from property center")
//                    // TODO: Show alert to user
//                }
//            }
//            
//            // Upload photo
//            guard let imageData = try? Data(contentsOf: url) else {
//                continue
//            }
//            
//            // Create thumbnail
//            let thumbnail = createThumbnail(from: imageData)
//            
//            let photoId = UUID().uuidString
//            
//            do {
//                // Upload full image
//                let fullUrl = try await firebaseManager.uploadPhoto(
//                    imageData,
//                    propertyId: property.id,
//                    sessionId: session.id,
//                    photoId: photoId
//                )
//                
//                // Upload thumbnail
//                var thumbnailUrl: String?
//                if let thumbData = thumbnail {
//                    thumbnailUrl = try await firebaseManager.uploadThumbnail(
//                        thumbData,
//                        propertyId: property.id,
//                        sessionId: session.id,
//                        photoId: photoId
//                    )
//                }
//                
//                // Create photo record
//                let photo = Photo(
//                    id: photoId,
//                    sessionId: session.id,
//                    propertyId: property.id,
//                    firebaseStorageUrl: fullUrl,
//                    thumbnailUrl: thumbnailUrl,
//                    gpsLat: metadata.gpsLat,
//                    gpsLon: metadata.gpsLon,
//                    timestamp: metadata.timestamp,
//                    altitude: metadata.altitude,
//                    cameraMake: metadata.cameraMake,
//                    cameraModel: metadata.cameraModel,
//                    metadata: metadata.allMetadata
//                )
//                
//                try await firebaseManager.createPhoto(photo)
//                importedPhotos.append(photo)
//                
//            } catch {
//                print("❌ Failed to upload photo: \(error)")
//            }
//            
//            uploadProgress = Double(index + 1) / Double(totalPhotos)
//        }
//        
//        isProcessing = false
//        currentStep = .importKML
//        print("✅ Imported \(importedPhotos.count) photos")
//    }
//    
//    private func createThumbnail(from imageData: Data, maxSize: CGFloat = 200) -> Data? {
//        #if os(iOS)
//        guard let image = UIImage(data: imageData) else { return nil }
//        let size = image.size
//        let ratio = min(maxSize / size.width, maxSize / size.height)
//        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
//        
//        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
//        image.draw(in: CGRect(origin: .zero, size: newSize))
//        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        
//        return thumbnail?.jpegData(compressionQuality: 0.7)
//        #else
//        return nil // macOS implementation needed
//        #endif
//    }
//    
//    // MARK: - KML Import
//    
//    func importKML(from url: URL) async {
//        isProcessing = true
//        errorMessage = nil
//        
//        // Parse KML
//        guard let pins = kmlParser.parse(kmlURL: url), !pins.isEmpty else {
//            errorMessage = "Failed to parse KML file or no pins found"
//            isProcessing = false
//            return
//        }
//        
//        kmlPins = pins
//        print("✅ Parsed \(pins.count) pins from KML")
//        
//        // Extract unique colors
//        let uniqueColors = Set(pins.map { $0.color })
//        
//        // Load default mappings from UserDefaults
//        loadDefaultColorMappings(for: Array(uniqueColors))
//        
//        isProcessing = false
//        currentStep = .colorMapping
//    }
//    
//    private func loadDefaultColorMappings(for colors: [String]) {
//        colorMappings = [:]
//        for color in colors {
//            if let saved = UserDefaults.standard.string(forKey: "colorMapping_\(color)"),
//               let classification = DeerClassification(rawValue: saved) {
//                colorMappings[color] = classification
//            } else {
//                // Default mappings
//                switch color {
//                case "red": colorMappings[color] = .buck
//                case "blue": colorMappings[color] = .doe
//                case "yellow": colorMappings[color] = .beddedBuck
//                case "green": colorMappings[color] = .beddedDoe
//                case "purple": colorMappings[color] = .matureBuck
//                default: colorMappings[color] = .buck
//                }
//            }
//        }
//    }
//    
//    func updateColorMapping(_ color: String, to classification: DeerClassification) {
//        colorMappings[color] = classification
//    }
//    
//    func confirmColorMappings() async {
//        guard let session = currentSession else { return }
//        
//        // Update session with color mappings
//        var updatedSession = session
//        updatedSession.colorMappings = colorMappings
//        
//        do {
//            try await firebaseManager.createFlightSession(updatedSession)
//            currentSession = updatedSession
//            
//            // Move to matching step
//            await performAutoMatching()
//            
//        } catch {
//            errorMessage = "Failed to save color mappings: \(error.localizedDescription)"
//        }
//    }
//    
//    // MARK: - Auto-Matching
//    
//    func performAutoMatching() async {
//        guard let property = selectedProperty,
//              let session = currentSession else { return }
//        
//        isProcessing = true
//        matchedObservations = []
//        unmatchedPins = []
//        unmatchedPhotos = []
//        
//        var usedPhotos = Set<String>()
//        var usedPins = Set<Int>()
//        
//        let matchThreshold: Double = 10.0 // 10 feet = ~3 meters
//        
//        // Try to match each pin to nearby photos
//        for (pinIndex, pin) in kmlPins.enumerated() {
//            let nearbyPhotos = importedPhotos.filter { photo in
//                !usedPhotos.contains(photo.id) &&
//                coordUtils.distance(
//                    from: pin.coordinate,
//                    to: CLLocationCoordinate2D(latitude: photo.gpsLat, longitude: photo.gpsLon)
//                ) <= matchThreshold
//            }
//            
//            if nearbyPhotos.count == 1, let photo = nearbyPhotos.first {
//                // Perfect match!
//                let classification = colorMappings[pin.color] ?? .buck
//                let observation = DeerObservation(
//                    sessionId: session.id,
//                    propertyId: property.id,
//                    gpsLat: pin.coordinate.latitude,
//                    gpsLon: pin.coordinate.longitude,
//                    classification: classification,
//                    color: pin.color,
//                    timestamp: photo.timestamp,
//                    photos: [photo]
//                )
//                matchedObservations.append(observation)
//                usedPhotos.insert(photo.id)
//                usedPins.insert(pinIndex)
//            }
//            // If multiple photos nearby, leave for manual review
//        }
//        
//        // Collect unmatched items
//        unmatchedPins = kmlPins.enumerated().filter { !usedPins.contains($0.offset) }.map { $0.element }
//        unmatchedPhotos = importedPhotos.filter { !usedPhotos.contains($0.id) }
//        
//        print("✅ Auto-matched \(matchedObservations.count) observations")
//        print("⚠️ \(unmatchedPins.count) pins and \(unmatchedPhotos.count) photos need review")
//        
//        isProcessing = false
//        currentStep = .reviewMatches
//    }
//    
//    func manuallyLinkPhoto(_ photo: Photo, to pin: KMLPin) {
//        guard let property = selectedProperty,
//              let session = currentSession,
//              let classification = colorMappings[pin.color] else { return }
//        
//        let observation = DeerObservation(
//            sessionId: session.id,
//            propertyId: property.id,
//            gpsLat: pin.coordinate.latitude,
//            gpsLon: pin.coordinate.longitude,
//            classification: classification,
//            color: pin.color,
//            timestamp: photo.timestamp,
//            photos: [photo]
//        )
//        
//        matchedObservations.append(observation)
//        unmatchedPins.removeAll { $0.coordinate.latitude == pin.coordinate.latitude && $0.coordinate.longitude == pin.coordinate.longitude }
//        unmatchedPhotos.removeAll { $0.id == photo.id }
//    }
//    
//    func assignClassificationToPhoto(_ photo: Photo, classification: DeerClassification) {
//        guard let property = selectedProperty,
//              let session = currentSession else { return }
//        
//        // Create observation with photo's GPS location
//        let observation = DeerObservation(
//            sessionId: session.id,
//            propertyId: property.id,
//            gpsLat: photo.gpsLat,
//            gpsLon: photo.gpsLon,
//            classification: classification,
//            color: "manual",
//            timestamp: photo.timestamp,
//            photos: [photo]
//        )
//        
//        matchedObservations.append(observation)
//        unmatchedPhotos.removeAll { $0.id == photo.id }
//    }
//    
//    func completeImport() async {
//        isProcessing = true
//        
//        // Save all matched observations to Firebase
//        for observation in matchedObservations {
//            do {
//                try await firebaseManager.createObservation(observation)
//            } catch {
//                print("❌ Failed to save observation: \(error)")
//            }
//        }
//        
//        isProcessing = false
//        currentStep = .complete
//        print("✅ Import complete! Created \(matchedObservations.count) observations")
//    }
//    
//    func reset() {
//        selectedProperty = nil
//        importedPhotos = []
//        kmlPins = []
//        colorMappings = [:]
//        unmatchedPins = []
//        unmatchedPhotos = []
//        matchedObservations = []
//        currentStep = .selectProperty
//        currentSession = nil
//        uploadProgress = 0
//    }
//}
