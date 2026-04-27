//
//  ImportViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//



// MARK: - ImportViewModel.swift (COMPLETE REBUILD - Flexible Flow)
import Foundation
import SwiftUI
import CoreLocation

@MainActor
class ImportViewModel: ObservableObject {
    
    static let instance = ImportViewModel()
    
    
    @Published var selectedProperty: Property?
    @Published var importedPhotos: [Photo] = []
    @Published var kmlPins: [KMLPin] = []
    @Published var observations: [DeerObservation] = [] // Final observations
    @Published var colorMappings: [String: DeerClassification] = [:]
    @Published var isProcessing = false
    @Published var currentStep: ImportStep = .selectProperty
    @Published var errorMessage: String?
    @Published var uploadProgress: Double = 0
    @Published var processingMessage: String = ""
    @Published var hasLoadedUnassignedPins = false
    
    // Matching results
    @Published var matchedPairs: [(photoGroup: [Photo], pin: KMLPin)] = []
    @Published var unmatchedPhotos: [Photo] = []
    @Published var unmatchedPins: [KMLPin] = []
    @Published var skippedDuplicateCount: Int = 0

    // Add this line
    var coordinateDistanceCalculator: CoordinateUtilities { CoordinateUtilities.shared }
    
    enum ImportStep {
        case selectProperty
        case importPhotos
        case reviewPhotos
        case optionalKML
        case colorMapping
        case matchKML
        case complete
    }
    
    private init() {}
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    private let xmpParser = XMPMetadataParser.shared
    private let kmlParser = KMLParser.shared
    private let coordUtils = CoordinateUtilities.shared
     var currentSession: FlightSession?
    
    // MARK: - 1. Photo Import (Can happen first or after KML)
    // MARK: - ImportViewModel.swift (COMPLETE FIXED importPhotos)
    // MARK: - ImportViewModel.swift (UPDATED importPhotos with better file structure)

    // REPLACE the importPhotos method with this:

    func importPhotos(from urls: [URL]) async {
        guard let property = selectedProperty else { return }
        if !hasLoadedUnassignedPins && kmlPins.isEmpty {
             await loadUnassignedPinsForMatching()
         }
        isProcessing = true
        errorMessage = nil
        uploadProgress = 0
        
        
        // Create or use existing session
        if currentSession == nil {
            let session = FlightSession(
                propertyId: property.id,
                date: Date(),
                timeOfDay: FlightSession.TimeOfDay.from(date: Date()),
                colorMappings: colorMappings
            )
            currentSession = session
            
            do {
                try await firebaseManager.createFlightSession(session)
                print("✅ Created session: \(session.id)")
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
                isProcessing = false
                return
            }
        }
        
        guard let session = currentSession else { return }
        
        // FETCH ALL EXISTING PHOTOS FOR THIS PROPERTY (efficient - 1 query)
        processingMessage = "Checking for existing photos..."
        let existingPhotos: [Photo]
        do {
            existingPhotos = try await firebaseManager.fetchAllPhotosForProperty(property.id)
            print("📸 Loaded \(existingPhotos.count) existing photos for duplicate check")
        } catch {
            print("⚠️ Failed to load existing photos: \(error)")
            existingPhotos = []
        }
        
        // Build lookup set by filename (instant lookups)
        let existingFilenames = Set(existingPhotos.compactMap { $0.metadata["filename"] })
        print("📸 Existing filenames: \(existingFilenames.count)")
        
        // Get first photo's timestamp to create folder name
        var folderName: String?
        if let firstUrl = urls.first,
           let metadata = xmpParser.parseMetadata(from: firstUrl) {
            // Format: YYYYMMDD only (date without time)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"  // ← Changed from "yyyyMMdd_HHmmss"
            folderName = formatter.string(from: metadata.timestamp)
        }
        
        let storageFolderName = folderName ?? UUID().uuidString
        print("📁 Using folder name: \(storageFolderName)")
        
        // Process photos
        let totalPhotos = urls.count
        var processedCount = 0
        var newPhotos: [Photo] = []
        var skippedCount = 0
        
        for url in urls {
            let filename = url.lastPathComponent
            
            // Check if already imported (instant local check)
            if existingFilenames.contains(filename) {
                print("⏭️ Skipping duplicate photo: \(filename)")
                skippedCount += 1
                processedCount += 1
                uploadProgress = Double(processedCount) / Double(totalPhotos)
                continue
            }
            
            guard url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" else {
                processedCount += 1
                continue
            }
            
            guard let metadata = xmpParser.parseMetadata(from: url) else {
                print("⚠️ Skipping photo with no metadata: \(filename)")
                processedCount += 1
                continue
            }
            
            // Upload photo
            guard let imageData = try? Data(contentsOf: url) else {
                processedCount += 1
                continue
            }
            
            let thumbnail = createThumbnail(from: imageData)
            let photoId = UUID().uuidString // Still need unique ID for Firestore doc
            
            do {
                processingMessage = "Uploading \(filename)..."
                
                // Upload with folder name and original filename
                let fullUrl = try await firebaseManager.uploadPhoto(
                    imageData,
                    folderName: storageFolderName,
                    filename: filename
                )
                
                var thumbnailUrl: String?
                if let thumbData = thumbnail {
                    thumbnailUrl = try await firebaseManager.uploadThumbnail(
                        thumbData,
                        folderName: storageFolderName,
                        filename: filename
                    )
                }
                
                // Add filename to metadata
                var enhancedMetadata = metadata.allMetadata
                enhancedMetadata["filename"] = filename
                
                let targetLat = metadata.lrfTargetLat ?? metadata.gpsLat
                let targetLon = metadata.lrfTargetLon ?? metadata.gpsLon
                
                if metadata.lrfTargetLat == nil || metadata.lrfTargetLon == nil {
                    print("⚠️ No LRF target found for \(filename), using drone position")
                }

                let photo = Photo(
                    id: photoId,
                    sessionId: session.id,
                    propertyId: property.id,
                    firebaseStorageUrl: fullUrl,
                    thumbnailUrl: thumbnailUrl,
                    gpsLat: targetLat,
                    gpsLon: targetLon,
                    timestamp: metadata.timestamp,
                    altitude: metadata.altitude,
                    cameraMake: metadata.cameraMake,
                    cameraModel: metadata.cameraModel,
                    metadata: enhancedMetadata
                )
                
                try await firebaseManager.createPhoto(photo)
                newPhotos.append(photo)
                
                processedCount += 1
                uploadProgress = Double(processedCount) / Double(totalPhotos)
                
            } catch {
                print("❌ Failed to upload photo \(filename): \(error)")
                processedCount += 1
            }
        }
        
        importedPhotos.append(contentsOf: newPhotos)
        
        isProcessing = false
        processingMessage = ""
        
        print("✅ Imported \(newPhotos.count) new photos to folder: \(storageFolderName)")
        if skippedCount > 0 {
            print("⏭️ Skipped \(skippedCount) duplicate photos")
        }
        skippedDuplicateCount = skippedCount
        // If we already have KML, trigger matching
        if !kmlPins.isEmpty {
            await matchPhotosAndPins()
        } else {
            currentStep = .reviewPhotos
        }
    }

    func confirmColorMappingsGlobally() async {
        guard var session = currentSession else { return }
        
        session.colorMappings = colorMappings
        currentSession = session
        
        do {
            try await firebaseManager.createFlightSession(session)
            print("✅ Saved color mappings for global pins")
            currentStep = .complete
        } catch {
            errorMessage = "Failed to save color mappings: \(error.localizedDescription)"
        }
    }
   
    
    private func groupPhotosByFilename(_ photos: [Photo]) -> [[Photo]] {
        // Parse DJI filenames and group by sequence number
        var sequenceGroups: [String: [Photo]] = [:]
        var nonDJIPhotos: [Photo] = []
        
        for photo in photos {
            guard let filename = photo.metadata["filename"],
                  let sequence = extractDJISequenceNumber(from: filename) else {
                // Not a DJI filename - treat as single photo
                nonDJIPhotos.append(photo)
                continue
            }
            
            if sequenceGroups[sequence] == nil {
                sequenceGroups[sequence] = []
            }
            sequenceGroups[sequence]?.append(photo)
        }
        
        // Validate groups - photos should be within 2 seconds of each other
        var validGroups: [[Photo]] = []
        
        for (_, photosInGroup) in sequenceGroups {
            if photosInGroup.count > 1 {
                // Verify timestamps are within 2 seconds (thermal/visible pairs)
                let timestamps = photosInGroup.map { $0.timestamp }
                let minTime = timestamps.min()!
                let maxTime = timestamps.max()!
                
                if maxTime.timeIntervalSince(minTime) <= 2.0 {
                    // Valid group - thermal and visible taken within 2 seconds
                    validGroups.append(photosInGroup)
                } else {
                    // Time gap too large - treat as separate photos (shouldn't happen with DJI)
                    photosInGroup.forEach { validGroups.append([$0]) }
                }
            } else {
                // Single photo in this sequence number
                validGroups.append(photosInGroup)
            }
        }
        
        // Add non-DJI photos as single groups
        nonDJIPhotos.forEach { validGroups.append([$0]) }
        
        return validGroups
    }

    private func extractDJISequenceNumber(from filename: String) -> String? {
        // DJI_20251203201351_0011_V.JPG -> extract "0011"
        // DJI_20251203201352_0011_T.JPG -> extract "0011"
        let components = filename.components(separatedBy: "_")
        guard components.count >= 3,
              components[0] == "DJI" else {
            return nil
        }
        return components[2] // The sequence number (0011)
    }
    
    func loadUnassignedPinsForMatching() async {
        isProcessing = true
        processingMessage = "Loading pins for matching..."
        
        do {
            let unassignedPins = try await firebaseManager.fetchUnassignedPins()
            
            // Cache pins locally
            kmlPins = unassignedPins
            hasLoadedUnassignedPins = true
            
            // Load default color mappings
            let uniqueColors = Set(unassignedPins.map { $0.color })
            loadDefaultColorMappings(for: Array(uniqueColors))
            
            print("✅ Loaded \(unassignedPins.count) unassigned pins for matching")
            print("📅 Pin dates range: \(unassignedPins.map { $0.createdDate }.min() ?? Date()) to \(unassignedPins.map { $0.createdDate }.max() ?? Date())")
            
        } catch {
            print("⚠️ Failed to load unassigned pins: \(error)")
            // Continue anyway - photos can still be imported without pins
        }
        
        isProcessing = false
        processingMessage = ""
    }
    
    // MARK: - 2. KML Import (Can happen first or after photos)
    
    func importKML(from url: URL) async {
        guard let property = selectedProperty else { return }
        
        isProcessing = true
        errorMessage = nil
        processingMessage = "Parsing KML..."
        
        // Parse KML
        guard let parsedPins = kmlParser.parse(kmlURL: url), !parsedPins.isEmpty else {
            errorMessage = "Failed to parse KML file or no pins found"
            isProcessing = false
            processingMessage = ""
            return
        }
        
        // Create or use existing session
        if currentSession == nil {
            let session = FlightSession(
                propertyId: property.id,
                date: parsedPins.first?.createdDate ?? Date(),
                timeOfDay: FlightSession.TimeOfDay.from(date: parsedPins.first?.createdDate ?? Date()),
                colorMappings: [:]
            )
            currentSession = session
            
            do {
                try await firebaseManager.createFlightSession(session)
                print("✅ Created session from KML: \(session.id)")
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
                isProcessing = false
                processingMessage = ""
                return
            }
        }
        
        guard let session = currentSession else { return }
        
        // Associate pins with session and property
        var enhancedPins: [KMLPin] = []
        for var pin in parsedPins {
            pin.sessionId = session.id
            pin.propertyId = property.id
            enhancedPins.append(pin)
            
            // Save to Firebase
            do {
                try await firebaseManager.createKMLPin(pin)
            } catch {
                print("❌ Failed to save KML pin: \(error)")
            }
        }
        
        kmlPins = enhancedPins
        
        // Extract unique colors and set up default mappings
        let uniqueColors = Set(enhancedPins.map { $0.color })
        loadDefaultColorMappings(for: Array(uniqueColors))
        
        isProcessing = false
        processingMessage = ""
        
        print("✅ Imported \(enhancedPins.count) KML pins")
        
        // If we already have photos, trigger matching
        if !importedPhotos.isEmpty {
            currentStep = .colorMapping // User needs to confirm mappings first
        } else {
            currentStep = .colorMapping
        }
    }
    
    private func loadDefaultColorMappings(for colors: [String]) {
        for color in colors {
            if colorMappings[color] == nil {
                // Set defaults
                switch color {
                case "red": colorMappings[color] = .buck
                case "blue": colorMappings[color] = .doe
                case "yellow": colorMappings[color] = .beddedBuck
                case "green": colorMappings[color] = .beddedDoe
                case "purple": colorMappings[color] = .matureBuck
                default: colorMappings[color] = .buck
                }
            }
        }
        
        // Update session with mappings
        if var session = currentSession {
            session.colorMappings = colorMappings
            currentSession = session
            
            Task {
                try? await firebaseManager.createFlightSession(session)
            }
        }
    }
    
    // MARK: - 3. Color Mapping Confirmation
    
    func confirmColorMappings() async {
        guard var session = currentSession else { return }
        
        // Update session with confirmed mappings
        session.colorMappings = colorMappings
        currentSession = session
        
        do {
            try await firebaseManager.createFlightSession(session)
            print("✅ Saved color mappings")
            
            // Now do the matching
            if !importedPhotos.isEmpty {
                await matchPhotosAndPins()
            } else {
                // KML only - create observations from pins
                await createObservationsFromPinsOnly()
            }
            
        } catch {
            errorMessage = "Failed to save color mappings: \(error.localizedDescription)"
        }
    }
    //MARK: - MATCH PHOTO And Pins
    
    private func matchPhotosAndPins() async {
        isProcessing = true
        processingMessage = "Matching photos to KML pins..."
        let matchDistanceThreshold: Double = 10.0
        let matchTimeThreshold: Double = 120.0
        
        let photoGroups = groupPhotosByFilename(importedPhotos)
        
        print("=== MATCHING DEBUG START ===")
        print("Photo groups: \(photoGroups.count) (from \(importedPhotos.count) individual photos)")
        print("Total pins available: \(kmlPins.count)")
        
        // GET DATE RANGE OF IMPORTED PHOTOS
        let photoDates = photoGroups.compactMap { $0.first?.timestamp }
        guard let minPhotoDate = photoDates.min(), let maxPhotoDate = photoDates.max() else {
            print("❌ No photos to match")
            return
        }
        
        // Filter pins: only unmatched pins within 24 hours of photo dates
        let unmatchedPinsForMatching = kmlPins.filter { pin in
            guard pin.matchedPhotoIds.isEmpty else { return false }
            let hoursDiff = abs(pin.createdDate.timeIntervalSince(minPhotoDate)) / 3600
            return hoursDiff <= 24 || abs(pin.createdDate.timeIntervalSince(maxPhotoDate)) / 3600 <= 24
        }
        
        print("Unmatched pins (available for matching): \(unmatchedPinsForMatching.count)")
        print("Photo date range: \(minPhotoDate.formatted()) to \(maxPhotoDate.formatted())")
        
        // Print only relevant pins (within 24 hours of photos)
        print("\n--- RELEVANT PINS (within 24 hours of photos) ---")
        for pin in unmatchedPinsForMatching.prefix(20) {
            let time = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .none, timeStyle: .medium)
            let date = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .short, timeStyle: .none)
            print("PIN  | \(pin.name.padding(toLength: 20, withPad: " ", startingAt: 0)) | \(date) \(time) | lat: \(pin.coordinate.latitude.formatted(.number.precision(.fractionLength(6)))) lon: \(pin.coordinate.longitude.formatted(.number.precision(.fractionLength(6))))")
        }
        if unmatchedPinsForMatching.count > 20 {
            print("  ... and \(unmatchedPinsForMatching.count - 20) more pins")
        }
        
        // Print ALL photo groups
        print("\n--- ALL PHOTO GROUPS ---")
        for group in photoGroups {
            guard let first = group.first, let filename = first.metadata["filename"] else { continue }
            let time = DateFormatter.localizedString(from: first.timestamp, dateStyle: .none, timeStyle: .medium)
            let date = DateFormatter.localizedString(from: first.timestamp, dateStyle: .short, timeStyle: .none)
            let photoCount = group.count > 1 ? " (\(group.count) photos)" : ""
            print("PHOTO| \(filename.padding(toLength: 35, withPad: " ", startingAt: 0)) | \(date) \(time) | lat: \(first.gpsLat.formatted(.number.precision(.fractionLength(6)))) lon: \(first.gpsLon.formatted(.number.precision(.fractionLength(6))))\(photoCount)")
        }
        
       // var matched: [(photo: Photo, pin: KMLPin)] = []
        var matched: [(photoGroup: [Photo], pin: KMLPin)] = []
        var usedGroupIndices = Set<Int>()
        var usedPinIds = Set<String>()
        
        print("\n--- MATCHING PROCESS (same-day pins only) ---")
        for pin in unmatchedPinsForMatching {
            let pinDate = Calendar.current.startOfDay(for: pin.createdDate)
            
            // Only check photo groups on the SAME DAY
            let sameDayGroups = photoGroups.enumerated().filter { index, group in
                guard !usedGroupIndices.contains(index) else { return false }
                guard let firstPhoto = group.first else { return false }
                let photoDate = Calendar.current.startOfDay(for: firstPhoto.timestamp)
                return pinDate == photoDate
            }
            
            // Skip if no photos on same day
            if sameDayGroups.isEmpty { continue }
            
            let pinTime = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .none, timeStyle: .medium)
            let pinDateStr = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .short, timeStyle: .none)
            
            var candidates: [(groupIndex: Int, firstPhoto: Photo, distance: Double, timeDiff: Double)] = []
            
            print("\n🔍 Checking Pin: \(pin.name) @ \(pinDateStr) \(pinTime)")
            
            for (index, group) in sameDayGroups {
                let firstPhoto = group[0]
                let filename = firstPhoto.metadata["filename"] ?? "???"
                
                // Calculate time diff
                let timeDiff = abs(firstPhoto.timestamp.timeIntervalSince(pin.createdDate))
                
                // FILTER: Within 2 minutes
                if timeDiff > matchTimeThreshold {
                    print("  ❌ \(filename) - Time diff too large (Δt: \(Int(timeDiff))s)")
                    continue
                }
                
                let distance = coordUtils.distance(
                    from: pin.coordinate,
                    to: CLLocationCoordinate2D(
                        latitude: firstPhoto.metadata["lrfTargetLat"] as? Double ?? firstPhoto.gpsLat,
                        longitude: firstPhoto.metadata["lrfTargetLon"] as? Double ?? firstPhoto.gpsLon
                    )
                )
                
                // FILTER: Within distance threshold
                if distance > matchDistanceThreshold {
                    print("  ❌ \(filename) - Distance too large (\(String(format: "%.2fm", distance)))")
                    continue
                }
                
                // This photo is a candidate!
                print("  ✅ \(filename) - CANDIDATE (\(String(format: "%.2fm", distance)), Δt: \(Int(timeDiff))s)")
                candidates.append((index, firstPhoto, distance, timeDiff))
            }
            
            if let best = candidates.min(by: { $0.distance < $1.distance }) {
                let filename = best.firstPhoto.metadata["filename"] ?? "???"
                print("  🎯 BEST MATCH: \(filename) @ \(String(format: "%.2fm", best.distance)), Δt: \(Int(best.timeDiff))s")
                
                // Get the full photo group and sort so visible comes first
                var photoGroup = photoGroups[best.groupIndex]
                photoGroup.sort { photo1, photo2 in
                    let filename1 = photo1.metadata["filename"] ?? ""
                    let filename2 = photo2.metadata["filename"] ?? ""
                    
                    // Visible (_V) comes before Thermal (_T)
                    let isVisible1 = filename1.contains("_V.") || filename1.contains("_v.")
                    let isVisible2 = filename2.contains("_V.") || filename2.contains("_v.")
                    
                    if isVisible1 && !isVisible2 { return true }  // V before T
                    if !isVisible1 && isVisible2 { return false } // T after V
                    return false // Keep original order if both same type
                }
                
                matched.append((photoGroup: photoGroup, pin: pin))  // Store the GROUP
                usedGroupIndices.insert(best.groupIndex)
                usedPinIds.insert(pin.id)
            } else {
                print("  ⛔ NO MATCH (no photos within time/distance thresholds)")
            }
        }
        
        let unmatchedGroups = photoGroups.enumerated()
            .filter { !usedGroupIndices.contains($0.offset) }
            .map { $0.element }
        
        matchedPairs = matched
        unmatchedPhotos = unmatchedGroups.flatMap { $0 }
        unmatchedPins = kmlPins.filter { !usedPinIds.contains($0.id) }
        
//        print("\n=== FINAL RESULTS ===")
//        print("Matched: \(matchedPairs.count) pins to photo groups")
//        print("Unmatched photo groups: \(unmatchedGroups.count)")
//        print("Unmatched pins: \(unmatchedPins.count)")
        
        print("\n=== FINAL RESULTS ===")
        print("Matched: \(matchedPairs.count) pins to photo groups")
        print("Unmatched photo groups: \(unmatchedGroups.count)")
        print("Unmatched pins: \(unmatchedPins.count)")

        if !matchedPairs.isEmpty {
            print("\n--- MATCHED PAIRS ---")
            for pair in matchedPairs {
                // FIX: pair.photoGroup is an array now, get first photo
                let filename = pair.photoGroup.first?.metadata["filename"] ?? "???"
                let photoCount = pair.photoGroup.count > 1 ? " (\(pair.photoGroup.count) photos)" : ""
                print("  ✅ \(pair.pin.name) ↔ \(filename)\(photoCount)")
            }
        }

        if !unmatchedPhotos.isEmpty {
            print("\n--- UNMATCHED PHOTOS ---")
            for photo in unmatchedPhotos {
                let filename = photo.metadata["filename"] ?? "???"
                print("  ⚠️ \(filename)")
            }
        }

        print("=== END ===\n")
        
//        if !unmatchedPins.isEmpty {
//            print("\n--- UNMATCHED PINS ---")
//            print
//            for pin in unmatchedPins {
//                print("  ⚠️ Unmatched pin")
//            }
//        }
        
        print("=== END ===\n")
        
        isProcessing = false
        processingMessage = ""
        currentStep = .matchKML
        await createObservationsAndSave()
    }
//    private func matchPhotosAndPinsPrev() async {
//        isProcessing = true
//        processingMessage = "Matching photos to KML pins..."
//        let matchDistanceThreshold: Double = 10.0  // meters
//        let matchTimeThreshold: Double = 120.0     // seconds (2 minutes)
//        
//        let photoGroups = groupPhotosByFilename(importedPhotos)
//        
//        print("=== MATCHING DEBUG START ===")
//        print("Photo groups: \(photoGroups.count) (from \(importedPhotos.count) individual photos)")
//        print("Total pins available: \(kmlPins.count)")
//        
//        // Filter pins: only unmatched pins
//        let unmatchedPinsForMatching = kmlPins.filter { $0.matchedPhotoIds.isEmpty }
//        print("Unmatched pins (available for matching): \(unmatchedPinsForMatching.count)")
//        
//        // Print ALL pins with full details
//        print("\n--- ALL PINS ---")
//        for pin in kmlPins {
//            let time = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .none, timeStyle: .medium)
//            let date = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .short, timeStyle: .none)
//            let matched = pin.matchedPhotoIds.isEmpty ? "" : " [ALREADY MATCHED]"
//            print("PIN  | \(pin.name.padding(toLength: 20, withPad: " ", startingAt: 0)) | \(date) \(time) | lat: \(pin.coordinate.latitude.formatted(.number.precision(.fractionLength(6)))) lon: \(pin.coordinate.longitude.formatted(.number.precision(.fractionLength(6))))\(matched)")
//        }
//        
//        // Print ALL photo groups with full details
//        print("\n--- ALL PHOTO GROUPS ---")
//        for group in photoGroups {
//            guard let first = group.first, let filename = first.metadata["filename"] else { continue }
//            let time = DateFormatter.localizedString(from: first.timestamp, dateStyle: .none, timeStyle: .medium)
//            let date = DateFormatter.localizedString(from: first.timestamp, dateStyle: .short, timeStyle: .none)
//            let photoCount = group.count > 1 ? " (\(group.count) photos)" : ""
//            print("PHOTO| \(filename.padding(toLength: 35, withPad: " ", startingAt: 0)) | \(date) \(time) | lat: \(first.gpsLat.formatted(.number.precision(.fractionLength(6)))) lon: \(first.gpsLon.formatted(.number.precision(.fractionLength(6))))\(photoCount)")
//        }
//        
//        var matched: [(photo: Photo, pin: KMLPin)] = []
//        var usedGroupIndices = Set<Int>()
//        var usedPinIds = Set<String>()
//        
//        print("\n--- MATCHING PROCESS ---")
//        for pin in unmatchedPinsForMatching {
//            let pinDate = Calendar.current.startOfDay(for: pin.createdDate)
//            let pinTime = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .none, timeStyle: .medium)
//            let pinDateStr = DateFormatter.localizedString(from: pin.createdDate, dateStyle: .short, timeStyle: .none)
//            
//            var candidates: [(groupIndex: Int, firstPhoto: Photo, distance: Double, timeDiff: Double)] = []
//            
//            print("\n🔍 Checking Pin: \(pin.name) @ \(pinDateStr) \(pinTime)")
//            
//            for (index, group) in photoGroups.enumerated() where !usedGroupIndices.contains(index) {
//                let firstPhoto = group[0]
//                let photoDate = Calendar.current.startOfDay(for: firstPhoto.timestamp)
//                let photoDateStr = DateFormatter.localizedString(from: firstPhoto.timestamp, dateStyle: .short, timeStyle: .none)
//                let filename = firstPhoto.metadata["filename"] ?? "???"
//                
//                // FILTER 1: Same calendar day
//                if pinDate != photoDate {
//                    print("  ❌ \(filename) - Different date (pin: \(pinDateStr), photo: \(photoDateStr))")
//                    continue
//                }
//                
//                // Calculate time diff
//                let timeDiff = abs(firstPhoto.timestamp.timeIntervalSince(pin.createdDate))
//                
//                // FILTER 2: Within 2 minutes (120 seconds)
//                if timeDiff > matchTimeThreshold {
//                    print("  ❌ \(filename) - Time diff too large (Δt: \(Int(timeDiff))s > \(Int(matchTimeThreshold))s)")
//                    continue
//                }
//                
//                let distance = coordUtils.distance(
//                    from: pin.coordinate,
//                    to: CLLocationCoordinate2D(
//                        latitude: firstPhoto.metadata["lrfTargetLat"] as? Double ?? firstPhoto.gpsLat,
//                        longitude: firstPhoto.metadata["lrfTargetLon"] as? Double ?? firstPhoto.gpsLon
//                    )
//                )
//       
//                
//                // FILTER 3: Within distance threshold
//                if distance > matchDistanceThreshold {
//                    print("  ❌ \(filename) - Distance too large (\(String(format: "%.2fm", distance)) > \(String(format: "%.2fm", matchDistanceThreshold)))")
//                    continue
//                }
//                
//                // This photo is a candidate!
//                print("  ✅ \(filename) - CANDIDATE (\(String(format: "%.2fm", distance)), Δt: \(Int(timeDiff))s)")
//                candidates.append((index, firstPhoto, distance, timeDiff))
//            }
//            
//            // Take closest match by distance
//            if let best = candidates.min(by: { $0.distance < $1.distance }) {
//                let filename = best.firstPhoto.metadata["filename"] ?? "???"
//                print("  🎯 BEST MATCH: \(filename) @ \(String(format: "%.2fm", best.distance)), Δt: \(Int(best.timeDiff))s")
//                matched.append((photo: best.firstPhoto, pin: pin))
//                usedGroupIndices.insert(best.groupIndex)
//                usedPinIds.insert(pin.id)
//            } else {
//                print("  ⛔ NO MATCH (no photos within date/time/distance thresholds)")
//            }
//        }
//        
//        let unmatchedGroups = photoGroups.enumerated()
//            .filter { !usedGroupIndices.contains($0.offset) }
//            .map { $0.element }
//        
//        matchedPairs = matched
//        unmatchedPhotos = unmatchedGroups.flatMap { $0 }
//        unmatchedPins = kmlPins.filter { !usedPinIds.contains($0.id) }
//        
//        print("\n=== FINAL RESULTS ===")
//        print("Matched: \(matchedPairs.count) pins to photo groups")
//        print("Unmatched photo groups: \(unmatchedGroups.count)")
//        print("Unmatched pins: \(unmatchedPins.count)")
//        
//        if !matchedPairs.isEmpty {
//            print("\n--- MATCHED PAIRS ---")
//            for pair in matchedPairs {
//                let filename = pair.photo.metadata["filename"] ?? "???"
//                print("  ✅ \(pair.pin.name) ↔ \(filename)")
//            }
//        }
//        
//        if !unmatchedPhotos.isEmpty {
//            print("\n--- UNMATCHED PHOTOS ---")
//            for photo in unmatchedPhotos {
//                let filename = photo.metadata["filename"] ?? "???"
//                print("  ⚠️ \(filename)")
//            }
//        }
//        
////        if !unmatchedPins.isEmpty {
////            print("\n--- UNMATCHED PINS ---")
////            print
////            for pin in unmatchedPins {
////                print("  ⚠️ Unmatched pin")
////            }
////        }
//        
//        print("=== END ===\n")
//        
//        isProcessing = false
//        processingMessage = ""
//        currentStep = .matchKML
//        await createObservationsAndSave()
//    }
//  
    // MARK: - 5. Create Observations
    // MARK: - ImportViewModel.swift (FIXED createObservationsAndSave)

    // REPLACE the entire createObservationsAndSave() method with this:
    func completeImport() async {
        currentStep = .complete
    }
    func createObservationsAndSave() async {
        guard let session = currentSession else { return }
        guard let propertyId = selectedProperty?.id else { return }
        
        isProcessing = true
        processingMessage = "Creating observations..."
        
        observations = []
        
        // 1. MATCHED PAIRS: Already grouped photos + KML classification
        for (photoGroup, pin) in matchedPairs {
            let classification = colorMappings[pin.color] ?? .buck
            let firstPhoto = photoGroup[0]  // This is now guaranteed to be visible photo (sorted earlier)
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: propertyId,
                gpsLat: firstPhoto.gpsLat,
                gpsLon: firstPhoto.gpsLon,
                classification: classification,
                color: pin.color,
                timestamp: firstPhoto.timestamp,
                photos: photoGroup,  // Already has both thermal + visible!
                classificationSource: .pinMatch,
                matchedPinId: pin.id
            )
            observations.append(obs)
            
            // Update pin with property assignment and matched photo IDs
            var updatedPin = pin
            updatedPin.propertyId = propertyId
            for photo in photoGroup {
                if !updatedPin.matchedPhotoIds.contains(photo.id) {
                    updatedPin.matchedPhotoIds.append(photo.id)
                }
            }
            
            // Save updated pin
            do {
                try await firebaseManager.updateKMLPin(updatedPin)
                print("✅ Updated pin \(pin.name) with propertyId and matched photos")
            } catch {
                print("⚠️ Failed to update pin: \(error)")
            }
        }
        
        // 2. UNMATCHED PHOTOS: Unknown classification
        let unmatchedPhotoGroups = groupPhotosByFilename(unmatchedPhotos)
        
        for photoGroup in unmatchedPhotoGroups {
            let firstPhoto = photoGroup[0]
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: propertyId,
                gpsLat: firstPhoto.gpsLat,
                gpsLon: firstPhoto.gpsLon,
                classification: .unknown,
                color: "black",
                timestamp: firstPhoto.timestamp,
                photos: photoGroup,
                classificationSource: .unknown,
                matchedPinId: nil
            )
            observations.append(obs)
        }
        
        // 3. UNMATCHED PINS: Do NOT create observations
        // These pins remain unassigned (propertyId = nil) in the global pool
        // They can be matched to future photo imports
        print("ℹ️ \(unmatchedPins.count) pins remain unmatched (available for future imports)")
        
        // Save all observations
        for obs in observations {
            do {
                try await firebaseManager.createObservation(obs)
            } catch {
                print("❌ Failed to save observation: \(error)")
            }
        }
        
        isProcessing = false
        processingMessage = ""
        currentStep = .matchKML
        
        print("✅ Created \(observations.count) observations:")
        print("  Pin-matched: \(observations.filter { $0.classificationSource == .pinMatch }.count)")
        print("  Unknown: \(observations.filter { $0.classificationSource == .unknown }.count)")
        print("  With photos: \(observations.filter { !$0.photos.isEmpty }.count)")
        print("  Multi-photo obs: \(observations.filter { $0.photos.count > 1 }.count)")
    }
    func createObservationsAndSavew() async {
        guard let session = currentSession else { return }
        guard let propertyId = selectedProperty?.id else { return }
        
        isProcessing = true
        processingMessage = "Creating observations..."
        
        observations = []
        
        // 1. MATCHED PAIRS: Already grouped photos + KML classification
        for (photoGroup, pin) in matchedPairs {
            let classification = colorMappings[pin.color] ?? .buck
            let firstPhoto = photoGroup[0]  // This is now guaranteed to be visible photo (sorted earlier)
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: propertyId,
                gpsLat: firstPhoto.gpsLat,
                gpsLon: firstPhoto.gpsLon,
                classification: classification,
                color: pin.color,
                timestamp: firstPhoto.timestamp,
                photos: photoGroup,  // Already has both thermal + visible!
                classificationSource: .pinMatch,
                matchedPinId: pin.id
            )
            observations.append(obs)
            
            // Update pin with property assignment and matched photo IDs
            var updatedPin = pin
            updatedPin.propertyId = propertyId
            for photo in photoGroup {
                if !updatedPin.matchedPhotoIds.contains(photo.id) {
                    updatedPin.matchedPhotoIds.append(photo.id)
                }
            }
            
            // Save updated pin
            do {
                try await firebaseManager.updateKMLPin(updatedPin)
                print("✅ Updated pin \(pin.name) with propertyId and matched photos")
            } catch {
                print("⚠️ Failed to update pin: \(error)")
            }
        }
        
        // 2. UNMATCHED PHOTOS: Unknown classification
        let unmatchedPhotoGroups = groupPhotosByFilename(unmatchedPhotos)
        
        for photoGroup in unmatchedPhotoGroups {
            let firstPhoto = photoGroup[0]
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: propertyId,
                gpsLat: firstPhoto.gpsLat,
                gpsLon: firstPhoto.gpsLon,
                classification: .unknown,
                color: "black",
                timestamp: firstPhoto.timestamp,
                photos: photoGroup,
                classificationSource: .unknown,
                matchedPinId: nil
            )
            observations.append(obs)
        }
        
        // 3. UNMATCHED PINS: Do NOT create observations
        // These pins remain unassigned (propertyId = nil) in the global pool
        // They can be matched to future photo imports
        print("ℹ️ \(unmatchedPins.count) pins remain unmatched (available for future imports)")
        
        // Save all observations
        for obs in observations {
            do {
                try await firebaseManager.createObservation(obs)
            } catch {
                print("❌ Failed to save observation: \(error)")
            }
        }
        
        isProcessing = false
        processingMessage = ""
        currentStep = .matchKML
        
        print("✅ Created \(observations.count) observations:")
        print("  Pin-matched: \(observations.filter { $0.classificationSource == .pinMatch }.count)")
        print("  Unknown: \(observations.filter { $0.classificationSource == .unknown }.count)")
        print("  With photos: \(observations.filter { !$0.photos.isEmpty }.count)")
        print("  Multi-photo obs: \(observations.filter { $0.photos.count > 1 }.count)")
    }
   

   
    
    // KML-only flow
    private func createObservationsFromPinsOnly() async {
        guard let session = currentSession else { return }
        
        isProcessing = true
        processingMessage = "Creating observations from KML..."
        
        observations = []
        
        for pin in kmlPins {
            let classification = colorMappings[pin.color] ?? .buck
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: session.propertyId,
                gpsLat: pin.coordinate.latitude,
                gpsLon: pin.coordinate.longitude,
                classification: classification,
                color: pin.color,
                timestamp: pin.createdDate,
                photos: []  // No photos
            )
            observations.append(obs)
            
            do {
                try await firebaseManager.createObservation(obs)
            } catch {
                print("❌ Failed to save observation: \(error)")
            }
        }
        
        isProcessing = false
        processingMessage = ""
        currentStep = .complete
        
        print("✅ Created \(observations.count) observations from KML only")
    }
   
    // MARK: - ImportViewModel.swift (ADD DEBUG METHOD)

    // ADD this method to ImportViewModel:

    func debugPinImport(from url: URL, nearCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 34.970775865456154, longitude: -81.81541785906941)) async {
        print("\n" + String(repeating: "=", count: 80))
        print("🐛 DEBUG PIN IMPORT START")
        print(String(repeating: "=", count: 80))
        
        // Parse KML
        guard let parsedPins = kmlParser.parse(kmlURL: url), !parsedPins.isEmpty else {
            print("❌ Failed to parse KML or empty")
            return
        }
        
        print("\n📍 PARSED \(parsedPins.count) PINS FROM KML:")
        for (i, pin) in parsedPins.enumerated().prefix(10) {
            let distance = coordUtils.distance(
                from: nearCoordinate,
                to: pin.coordinate
            )
            print("  [\(i+1)] \(pin.name)")
            print("      Lat: \(pin.coordinate.latitude)")
            print("      Lon: \(pin.coordinate.longitude)")
            print("      Date: \(pin.createdDate)")
            print("      Color: \(pin.color)")
            print("      Distance from debug point: \(String(format: "%.0f", distance))m")
        }
        if parsedPins.count > 10 {
            print("  ... and \(parsedPins.count - 10) more")
        }
        
        // Fetch ALL pins from Firebase
        print("\n📥 FETCHING ALL PINS FROM FIREBASE...")
        let allExistingPins: [KMLPin]
        do {
            allExistingPins = try await firebaseManager.fetchAllKMLPins()
            print("✅ Found \(allExistingPins.count) total pins in Firebase")
        } catch {
            print("❌ Failed to fetch pins: \(error)")
            return
        }
        
        // Filter nearby pins
        let nearbyExisting = allExistingPins.filter { pin in
            let distance = coordUtils.distance(from: nearCoordinate, to: pin.coordinate)
            return distance <= 1609 // 1 mile
        }
        
        print("\n📍 EXISTING PINS NEAR DEBUG POINT (within 1 mile): \(nearbyExisting.count)")
        for (i, pin) in nearbyExisting.enumerated().prefix(10) {
            let distance = coordUtils.distance(from: nearCoordinate, to: pin.coordinate)
            print("  [\(i+1)] \(pin.name)")
            print("      ID: \(pin.id)")
            print("      PropertyId: \(pin.propertyId ?? "nil")")
            print("      SessionId: \(pin.sessionId ?? "nil")")
            print("      Lat: \(pin.coordinate.latitude)")
            print("      Lon: \(pin.coordinate.longitude)")
            print("      Date: \(pin.createdDate)")
            print("      Color: \(pin.color)")
            print("      Matched photos: \(pin.matchedPhotoIds.count)")
            print("      Distance: \(String(format: "%.0f", distance))m")
        }
        
        // Check for duplicates - CHECK ALL 400 PINS
        print("\n🔍 CHECKING ALL \(parsedPins.count) PINS FOR DUPLICATES:")
        var duplicateCount = 0
        var newCount = 0
        var nearbyChecked = 0
        
        // First, get all pins near debug point from KML
        let nearbyKMLPins = parsedPins.filter { pin in
            let distance = coordUtils.distance(from: nearCoordinate, to: pin.coordinate)
            return distance <= 1609
        }
        
        print("  Found \(nearbyKMLPins.count) pins within 1 mile in KML")
        print("\n  Checking each one:")
        
        for pin in nearbyKMLPins {
            let distance = coordUtils.distance(from: nearCoordinate, to: pin.coordinate)
            nearbyChecked += 1
            
            let key = "\(pin.coordinate.latitude)_\(pin.coordinate.longitude)_\(pin.createdDate.timeIntervalSince1970)_\(pin.name)_\(pin.color)"
            
            // Check if exists
            var found = false
            var matchedPin: KMLPin?
            for existing in allExistingPins {
                let existingKey = "\(existing.coordinate.latitude)_\(existing.coordinate.longitude)_\(existing.createdDate.timeIntervalSince1970)_\(existing.name)_\(existing.color)"
                
                if key == existingKey {
                    found = true
                    matchedPin = existing
                    break
                }
            }
            
            if found, let matched = matchedPin {
                duplicateCount += 1
                print("  [\(nearbyChecked)] ❌ DUPLICATE: \(pin.name.isEmpty ? "no-name" : pin.name)")
                print("      KML    → \(String(format: "%.6f", pin.coordinate.latitude)), \(String(format: "%.6f", pin.coordinate.longitude))")
                print("      KML    → Date: \(pin.createdDate), Color: \(pin.color)")
                print("      Firebase → ID: \(matched.id)")
                print("      Firebase → PropertyId: \(matched.propertyId ?? "nil")")
                print("      Firebase → SessionId: \(matched.sessionId ?? "nil")")
                print("      Firebase → Matched photos: \(matched.matchedPhotoIds.count)")
                print("      Distance from debug: \(String(format: "%.0f", distance))m")
            } else {
                newCount += 1
                print("  [\(nearbyChecked)] ✅ NEW: \(pin.name.isEmpty ? "no-name" : pin.name)")
                print("      KML → \(String(format: "%.6f", pin.coordinate.latitude)), \(String(format: "%.6f", pin.coordinate.longitude))")
                print("      KML → Date: \(pin.createdDate), Color: \(pin.color)")
                print("      Distance from debug: \(String(format: "%.0f", distance))m")
            }
        }
        
        print("\n📊 SUMMARY:")
        print("  Total in KML: \(parsedPins.count)")
        print("  Near debug point in KML: \(parsedPins.filter { coordUtils.distance(from: nearCoordinate, to: $0.coordinate) <= 1609 }.count)")
        print("  Total in Firebase: \(allExistingPins.count)")
        print("  Near debug point in Firebase: \(nearbyExisting.count)")
        print("  Duplicates found: \(duplicateCount)")
        print("  New pins: \(newCount)")
        
        // Check unassigned
        let unassigned = allExistingPins.filter { $0.propertyId == nil }
        print("\n📍 UNASSIGNED PINS: \(unassigned.count)")
        let nearbyUnassigned = unassigned.filter {
            coordUtils.distance(from: nearCoordinate, to: $0.coordinate) <= 1609
        }
        print("  Near debug point: \(nearbyUnassigned.count)")
        for (i, pin) in nearbyUnassigned.prefix(5).enumerated() {
            print("  [\(i+1)] \(pin.name) - Matched photos: \(pin.matchedPhotoIds.count)")
        }
        
        print("\n" + String(repeating: "=", count: 80))
        print("🐛 DEBUG PIN IMPORT END")
        print(String(repeating: "=", count: 80) + "\n")
    }
    func importKMLGlobally(from url: URL) async {
        isProcessing = true
        errorMessage = nil
        processingMessage = "Parsing KML..."
        await debugPinImport(from: url)
        guard let parsedPins = kmlParser.parse(kmlURL: url), !parsedPins.isEmpty else {
            errorMessage = "Failed to parse KML file or no pins found"
            isProcessing = false
            processingMessage = ""
            return
        }
        
        let session = FlightSession(
            propertyId: "global",
            date: parsedPins.first?.createdDate ?? Date(),
            timeOfDay: FlightSession.TimeOfDay.from(date: parsedPins.first?.createdDate ?? Date()),
            colorMappings: [:]
        )
        currentSession = session
        
        do {
            try await firebaseManager.createFlightSession(session)
            print("✅ Created global session: \(session.id)")
        } catch {
            errorMessage = "Failed to create session: \(error.localizedDescription)"
            isProcessing = false
            processingMessage = ""
            return
        }
        
        // FETCH ALL EXISTING PINS ONCE (efficient!)
        processingMessage = "Loading existing pins..."
        let allExistingPins: [KMLPin]
        do {
            allExistingPins = try await firebaseManager.fetchAllKMLPins()
            print("📍 Loaded \(allExistingPins.count) existing pins for duplicate check")
        } catch {
            print("⚠️ Failed to load existing pins: \(error)")
            allExistingPins = []
        }
        
        // Build lookup set (instant checks)
        var existingPinKeys = Set<String>()
        for pin in allExistingPins {
            let key = "\(pin.coordinate.latitude)_\(pin.coordinate.longitude)_\(pin.createdDate.timeIntervalSince1970)"
            existingPinKeys.insert(key)
        }
        
        // Check for duplicates (local, instant!)
        var enhancedPins: [KMLPin] = []
        var skippedCount = 0
        let totalPins = parsedPins.count
        
        processingMessage = "Checking for duplicates..."
        
        for (index, var pin) in parsedPins.enumerated() {
            if index % 50 == 0 {
                processingMessage = "Checking pin \(index + 1) of \(totalPins)..."
            }
            
            // Create key for this pin
            let key = "\(pin.coordinate.latitude)_\(pin.coordinate.longitude)_\(pin.createdDate.timeIntervalSince1970)"
            
            // Check if exists (instant local lookup!)
            if existingPinKeys.contains(key) {
                print("⏭️ Skipping duplicate pin: \(pin.name)")
                skippedCount += 1
                continue
            }
            
            // Pin is new - import it
            pin.sessionId = session.id
            pin.propertyId = nil
            enhancedPins.append(pin)
            
            do {
                try await firebaseManager.createKMLPin(pin)
                print("✅ Imported pin: \(pin.name)")
            } catch {
                print("❌ Failed to save KML pin: \(error)")
            }
        }
        
        kmlPins = enhancedPins
        
        let uniqueColors = Set(enhancedPins.map { $0.color })
        loadDefaultColorMappings(for: Array(uniqueColors))
        
        isProcessing = false
        processingMessage = ""
        
        // Show import summary
        print("✅ Imported \(enhancedPins.count) new pins")
        if skippedCount > 0 {
            print("⏭️ Skipped \(skippedCount) duplicate pins")
        }
        
        currentStep = .colorMapping
    }
   
    func savePhotosWithoutKML() async {
        guard let session = currentSession else { return }
        
        isProcessing = true
        processingMessage = "Saving photos as observations..."
        
        observations = []
        
        // Group photos by filename (thermal + visible pairs)
        let photoGroups = groupPhotosByFilename(importedPhotos)
        
        for photoGroup in photoGroups {
            let firstPhoto = photoGroup[0]
            
            let obs = DeerObservation(
                sessionId: session.id,
                propertyId: session.propertyId,
                gpsLat: firstPhoto.gpsLat,
                gpsLon: firstPhoto.gpsLon,
                classification: .unknown,         // NEW
                color: "black",                   // NEW
                timestamp: firstPhoto.timestamp,
                photos: photoGroup,
                classificationSource: .unknown,   // NEW
                matchedPinId: nil
            )
            observations.append(obs)
            
            do {
                try await firebaseManager.createObservation(obs)
            } catch {
                print("❌ Failed to save observation: \(error)")
            }
        }
        
        isProcessing = false
        processingMessage = ""
        currentStep = .complete
        
        print("✅ Saved \(observations.count) observations without KML (all unknown classification)")
        print("  Multi-photo obs: \(observations.filter { $0.photos.count > 1 }.count)")
    }
 
    
    // MARK: - Helpers
    
    private func createThumbnail(from imageData: Data, maxSize: CGFloat = 200) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail?.jpegData(compressionQuality: 0.7)
        #else
        return nil
        #endif
    }
    
    func reset() {
        selectedProperty = nil
        importedPhotos = []
        kmlPins = []
        observations = []
        colorMappings = [:]
        matchedPairs = []
        unmatchedPhotos = []
        unmatchedPins = []
        currentStep = .selectProperty
        currentSession = nil
        uploadProgress = 0
        processingMessage = ""
    }
}
