//
//  DeerHerdFirebaseManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - DeerHerdFirebaseManager.swift
import Foundation
import FirebaseFirestore
import FirebaseStorage
import CoreLocation

class DeerHerdFirebaseManager {
    static let shared = DeerHerdFirebaseManager()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Properties
    
    func fetchProperties(for operatorId: String) async throws -> [Property] {
        let snapshot = try await db.collection("properties")
            .whereField("operatorId", isEqualTo: operatorId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Property.self)
        }
    }
    
    func fetchProperty(_ id: String) async throws -> Property? {
        let doc = try await db.collection("properties").document(id).getDocument()
        return try? doc.data(as: Property.self)
    }
    
    func createProperty(_ property: Property) async throws {
        try db.collection("properties").document(property.id).setData(from: property)
    }
    
    func updateProperty(_ property: Property) async throws {
        var updated = property
        updated.updatedAt = Date()
        try db.collection("properties").document(property.id).setData(from: updated)
    }
    
    func deleteProperty(_ id: String) async throws {
        // Delete all related data
        try await deleteFlightSessions(for: id)
        try await deleteObservations(for: id)
        try await deleteBuckProfiles(for: id)
        try await deletePins(for: id)
        try await db.collection("properties").document(id).delete()
    }
    func deletePins(for propertyId: String) async throws {
        print("🗑️ Deleting pins for property: \(propertyId)")
        
        let snapshot = try await db.collection("kmlPins")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        print("  Found \(snapshot.documents.count) pins to delete")
        
        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
        
        print("  ✅ Deleted \(snapshot.documents.count) pins")
    }
    
    // MARK: - Flight Sessions
    
    func fetchFlightSessions(for propertyId: String) async throws -> [FlightSession] {
        let snapshot = try await db.collection("flightSessions")
            .whereField("propertyId", isEqualTo: propertyId)
            .order(by: "date", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: FlightSession.self)
        }
    }
    
    func createFlightSession(_ session: FlightSession) async throws {
        try db.collection("flightSessions").document(session.id).setData(from: session)
    }
    
    func deleteFlightSessions(for propertyId: String) async throws {
        let snapshot = try await db.collection("flightSessions")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
    }
    
    // MARK: - Deer Observations
    
    func fetchObservations(for propertyId: String) async throws -> [DeerObservation] {
        let snapshot = try await db.collection("deerObservations")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: DeerObservation.self)
        }
    }
    
    func fetchObservations(for sessionId: String, propertyId: String) async throws -> [DeerObservation] {
        let snapshot = try await db.collection("deerObservations")
            .whereField("sessionId", isEqualTo: sessionId)
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: DeerObservation.self)
        }
    }
    // MARK: - DeerHerdFirebaseManager.swift (ADD THIS METHOD)

    // ADD this method to DeerHerdFirebaseManager class:

    func fetchUnassignedPins() async throws -> [KMLPin] {
        let snapshot = try await db.collection("kmlPins")
            .getDocuments()
        
        let allPins = snapshot.documents.compactMap { try? $0.data(as: KMLPin.self) }
        
        // Filter for unassigned pins only (propertyId == nil)
        let unassignedPins = allPins.filter { $0.propertyId == nil }
        
        print("📍 Fetched \(unassignedPins.count) unassigned pins (out of \(allPins.count) total)")
        
        return unassignedPins
    }

    // Also ADD this method to update pin after matching:

    func updateKMLPin(_ pin: KMLPin) async throws {
        try db.collection("kmlPins")
            .document(pin.id)
            .setData(from: pin, merge: true)
    }
    
    
    func createObservation(_ observation: DeerObservation) async throws {
        try db.collection("deerObservations").document(observation.id).setData(from: observation)
    }
    
    func updateObservation(_ observation: DeerObservation) async throws {
        try db.collection("deerObservations").document(observation.id).setData(from: observation)
    }
    
    func deleteObservation(_ id: String) async throws {
        try await db.collection("deerObservations").document(id).delete()
    }
    
    func deleteObservations(for propertyId: String) async throws {
        let snapshot = try await db.collection("deerObservations")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
    }
    
    // MARK: - Photos
    
//    func uploadPhoto(_ imageData: Data, propertyId: String, sessionId: String, photoId: String) async throws -> String {
//        let path = "photos/\(propertyId)/\(sessionId)/\(photoId).jpg"
//        let ref = storage.reference().child(path)
//        
//        let metadata = StorageMetadata()
//        metadata.contentType = "image/jpeg"
//        
//        _ = try await ref.putDataAsync(imageData, metadata: metadata)
//        let url = try await ref.downloadURL()
//        return url.absoluteString
//    }
    
    func uploadPhoto(_ imageData: Data, folderName: String, filename: String) async throws -> String {
        // Storage path: photos/{folderName}/{filename}
        let path = "photos/\(folderName)/\(filename)"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        
        return downloadURL.absoluteString
    }
    func uploadThumbnail(_ imageData: Data, folderName: String, filename: String) async throws -> String {
        // Create thumbnail filename: DJI_20251123082018_0002_T.JPG -> DJI_20251123082018_0002_T_thumb.JPG
        let thumbFilename = filename.replacingOccurrences(of: ".JPG", with: "_thumb.JPG")
                                    .replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
        
        // Storage path: photos/{folderName}/{thumbFilename}
        let path = "photos/\(folderName)/\(thumbFilename)"
        let ref = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        
        return downloadURL.absoluteString
    }
    
//    func uploadThumbnail(_ imageData: Data, propertyId: String, sessionId: String, photoId: String) async throws -> String {
//        let path = "photos/\(propertyId)/\(sessionId)/thumbnails/\(photoId)_thumb.jpg"
//        let ref = storage.reference().child(path)
//        
//        let metadata = StorageMetadata()
//        metadata.contentType = "image/jpeg"
//        
//        _ = try await ref.putDataAsync(imageData, metadata: metadata)
//        let url = try await ref.downloadURL()
//        return url.absoluteString
//    }
    
    func createPhoto(_ photo: Photo) async throws {
        try db.collection("photos").document(photo.id).setData(from: photo)
    }
    
    func updatePhoto(_ photo: Photo) async throws {
        try db.collection("photos").document(photo.id).setData(from: photo)
    }
    
    func deletePhoto(_ id: String) async throws {
        try await db.collection("photos").document(id).delete()
    }
    
    // MARK: - Buck Profiles
    
    func fetchBuckProfiles(for propertyId: String) async throws -> [BuckProfile] {
        let snapshot = try await db.collection("buckProfiles")
            .whereField("propertyId", isEqualTo: propertyId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: BuckProfile.self)
        }
    }
    
    func fetchBuckProfile(_ id: String) async throws -> BuckProfile? {
        let doc = try await db.collection("buckProfiles").document(id).getDocument()
        return try? doc.data(as: BuckProfile.self)
    }
    
    func createBuckProfile(_ profile: BuckProfile) async throws {
        try db.collection("buckProfiles").document(profile.id).setData(from: profile)
    }
    
    func updateBuckProfile(_ profile: BuckProfile) async throws {
        var updated = profile
        updated.updatedAt = Date()
        try db.collection("buckProfiles").document(profile.id).setData(from: updated)
    }
    
    func deleteBuckProfile(_ id: String) async throws {
        try await db.collection("buckProfiles").document(id).delete()
    }
    
    func deleteBuckProfiles(for propertyId: String) async throws {
        let snapshot = try await db.collection("buckProfiles")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
    }
    
    // MARK: - Drone Operator
    
    func fetchOperator(_ id: String) async throws -> DroneOperator? {
        let doc = try await db.collection("droneOperators").document(id).getDocument()
        return try? doc.data(as: DroneOperator.self)
    }
    
    func createOperator(_ operator: DroneOperator) async throws {
        try db.collection("droneOperators").document(`operator`.id).setData(from: `operator`)
    }
    
    //KML Methods:
    func fetchKMLPins(for sessionId: String) async throws -> [KMLPin] {
            let snapshot = try await db.collection("kmlPins")
                .whereField("sessionId", isEqualTo: sessionId)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                try? doc.data(as: KMLPin.self)
            }
        }
        
//        func fetchKMLPins(for propertyId: String, allSessions: Bool = false) async throws -> [KMLPin] {
//            let snapshot = try await db.collection("kmlPins")
//                .whereField("propertyId", isEqualTo: propertyId)
//                .getDocuments()
//            
//            return snapshot.documents.compactMap { doc in
//                try? doc.data(as: KMLPin.self)
//            }
//        }
    
    func fetchKMLPins(for propertyId: String, allSessions: Bool = false) async throws -> [KMLPin] {
        print("🔍 Fetching pins for propertyId: \(propertyId)")
        
        let snapshot = try await db.collection("kmlPins")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        let pins = snapshot.documents.compactMap { doc in
            try? doc.data(as: KMLPin.self)
        }
        
        print("📍 Fetched \(pins.count) pins for property")
        print("📍 Sample propertyIds: \(pins.prefix(3).map { $0.propertyId ?? "nil" })")
        
        return pins
    }
        
        func createKMLPin(_ pin: KMLPin) async throws {
            try db.collection("kmlPins").document(pin.id).setData(from: pin)
        }
        
//        func updateKMLPin(_ pin: KMLPin) async throws {
//            try db.collection("kmlPins").document(pin.id).setData(from: pin)
//        }
        
        func deleteKMLPin(_ id: String) async throws {
            try await db.collection("kmlPins").document(id).delete()
        }
        
        func deleteKMLPins(for sessionId: String) async throws {
            let snapshot = try await db.collection("kmlPins")
                .whereField("sessionId", isEqualTo: sessionId)
                .getDocuments()
            
            for doc in snapshot.documents {
                try await doc.reference.delete()
            }
        }
        
        func deleteKMLPins(for propertyId: String, allSessions: Bool = true) async throws {
            let snapshot = try await db.collection("kmlPins")
                .whereField("propertyId", isEqualTo: propertyId)
                .getDocuments()
            
            for doc in snapshot.documents {
                try await doc.reference.delete()
            }
        }
//    func fetchAllUnassignedPins() async throws -> [KMLPin] {
//        let snapshot = try await db.collection("kmlPins")
//            .whereField("propertyId", isEqualTo: NSNull())
//            .getDocuments()
//        return snapshot.documents.compactMap { try? $0.data(as: KMLPin.self) }
//    }
    func fetchAllUnassignedPins() async throws -> [KMLPin] {
        // Fetch ALL pins and filter locally (Firebase null queries are unreliable)
        let snapshot = try await db.collection("kmlPins").getDocuments()
        
        let allPins = snapshot.documents.compactMap { doc in
            try? doc.data(as: KMLPin.self)
        }
        
        print("🔍 Total pins in Firebase: \(allPins.count)")
        let unassigned = allPins.filter { $0.propertyId == nil }
        print("🔍 Unassigned pins: \(unassigned.count)")
        
        return unassigned
    }
    
    // MARK: - DeerHerdFirebaseManager.swift (ADD THESE METHODS)

    // ADD to DeerHerdFirebaseManager class:

    /// Check if a pin already exists in Firebase (exact match on key fields)
   func pinExists(_ pin: KMLPin) async throws -> Bool {
    let snapshot = try await db.collection("kmlPins")
        .getDocuments()  // Get ALL pins
    
    for doc in snapshot.documents {
        if let existing = try? doc.data(as: KMLPin.self),
           existing.coordinate.latitude == pin.coordinate.latitude,
           existing.coordinate.longitude == pin.coordinate.longitude,
           existing.createdDate == pin.createdDate,
           existing.name == pin.name,
           existing.color == pin.color {
            return true  // Duplicate found (regardless of propertyId)
        }
    }
    return false
}
    
    func fetchAllKMLPins() async throws -> [KMLPin] {
        let snapshot = try await db.collection("kmlPins").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: KMLPin.self) }
    }
    
    func fetchAllPhotosForProperty(_ propertyId: String) async throws -> [Photo] {
        let snapshot = try await db.collection("photos")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: Photo.self) }
    }
    // MARK: - FirebaseManager (ONE-TIME FIX METHOD)

    // ADD this method to DeerHerdFirebaseManager:

    // MARK: - FirebaseManager (CORRECTED ONE-TIME FIX METHOD)

    // REPLACE the fixGlobalPins method with this:

    func fixGlobalPins() async throws {
        print("\n🔧 FIXING GLOBAL PINS - ONE TIME FIX")
        print(String(repeating: "=", count: 60))
        
        // Fetch all pins
        let snapshot = try await db.collection("kmlPins").getDocuments()
        
        var globalPins: [KMLPin] = []
        
        for doc in snapshot.documents {
            if let pin = try? doc.data(as: KMLPin.self),
               pin.propertyId == "global" {
                globalPins.append(pin)
            }
        }
        
        print("📍 Found \(globalPins.count) pins with propertyId = 'global'")
        
        guard !globalPins.isEmpty else {
            print("✅ No global pins to fix!")
            return
        }
        
        // Reset each one to nil
        var fixedCount = 0
        var failedCount = 0
        
        for pin in globalPins {
            var updatedPin = pin
            updatedPin.propertyId = nil
            
            do {
                // Update directly in Firestore
                try await db.collection("kmlPins").document(pin.id).updateData([
                    "propertyId": NSNull()  // ← Use NSNull() for nil in Firestore
                ])
                fixedCount += 1
                print("✅ [\(fixedCount)/\(globalPins.count)] Reset pin \(pin.id)")
            } catch {
                failedCount += 1
                print("❌ Failed to update pin \(pin.id): \(error)")
            }
        }
        
        print("\n✅ FIXED \(fixedCount) pins")
        if failedCount > 0 {
            print("❌ Failed to fix \(failedCount) pins")
        }
        print("   All pins with 'global' now have propertyId = nil")
        print(String(repeating: "=", count: 60))
        
        let snapshot2 = try await db.collection("kmlPins").getDocuments()
        
        var globalPins2: [KMLPin] = []
        
        for doc in snapshot2.documents {
            if let pin = try? doc.data(as: KMLPin.self),
               pin.propertyId == "global" {
                globalPins.append(pin)
            }
        }
        
        print("📍 Found \(globalPins2.count) pins with propertyId = 'global'")
    }
    
    // MARK: - FirebaseManager (DELETE ALL PHOTOS METHOD)

    // ADD this method to DeerHerdFirebaseManager:

    func deleteAllPhotos() async throws {
        print("\n🗑️ DELETING ALL PHOTOS - DANGER ZONE")
        print(String(repeating: "=", count: 60))
        
        // Fetch all photos from Firestore
        let snapshot = try await db.collection("photos").getDocuments()
        
        let totalPhotos = snapshot.documents.count
        print("📸 Found \(totalPhotos) photos to delete")
        
        guard totalPhotos > 0 else {
            print("✅ No photos to delete!")
            return
        }
        
        var deletedDocs = 0
        var deletedFiles = 0
        var failedDocs = 0
        var failedFiles = 0
        
        for doc in snapshot.documents {
            guard let photo = try? doc.data(as: Photo.self) else {
                print("⚠️ Couldn't parse photo doc: \(doc.documentID)")
                continue
            }
            
            // Delete from Firestore
            do {
                try await doc.reference.delete()
                deletedDocs += 1
                print("✅ [\(deletedDocs)/\(totalPhotos)] Deleted Firestore doc: \(doc.documentID)")
            } catch {
                failedDocs += 1
                print("❌ Failed to delete Firestore doc \(doc.documentID): \(error)")
            }
            
            // Delete full-size photo from Storage
            if let fullUrl = photo.firebaseStorageUrl {
                do {
                    try await deleteStorageFile(from: fullUrl)
                    deletedFiles += 1
                    print("  🗑️ Deleted storage file: full image")
                } catch {
                    failedFiles += 1
                    print("  ⚠️ Failed to delete full image: \(error)")
                }
            }
            
            // Delete thumbnail from Storage
            if let thumbUrl = photo.thumbnailUrl {
                do {
                    try await deleteStorageFile(from: thumbUrl)
                    deletedFiles += 1
                    print("  🗑️ Deleted storage file: thumbnail")
                } catch {
                    failedFiles += 1
                    print("  ⚠️ Failed to delete thumbnail: \(error)")
                }
            }
        }
        
        print("\n✅ DELETION COMPLETE")
        print("   Firestore docs deleted: \(deletedDocs)")
        print("   Storage files deleted: \(deletedFiles)")
        if failedDocs > 0 {
            print("   ❌ Failed Firestore deletions: \(failedDocs)")
        }
        if failedFiles > 0 {
            print("   ❌ Failed Storage deletions: \(failedFiles)")
        }
        print(String(repeating: "=", count: 60))
    }

    // Helper to delete storage file from URL
    private func deleteStorageFile(from urlString: String) async throws {
        // Extract path from Firebase Storage URL
        // Format: https://firebasestorage.googleapis.com/v0/b/bucket/o/path%2Fto%2Ffile.jpg?token=...
        
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encodedPath = components.path.split(separator: "/").last else {
            throw NSError(domain: "StorageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid storage URL"])
        }
        
        // Decode the path (e.g., "photos%2Fproperty%2Ffile.jpg" → "photos/property/file.jpg")
        let decodedPath = String(encodedPath).removingPercentEncoding ?? String(encodedPath)
        
        // Delete from Storage
        let ref = storage.reference().child(decodedPath)
        try await ref.delete()
    }
//    func pinExists(_ pin: KMLPin) async throws -> Bool {
//        let snapshot = try await db.collection("kmlPins")
//            .whereField("coordinate.latitude", isEqualTo: pin.coordinate.latitude)
//            .whereField("coordinate.longitude", isEqualTo: pin.coordinate.longitude)
//            .getDocuments()
//        
//        // Check for exact match on all key fields
//        for doc in snapshot.documents {
//            if let existingPin = try? doc.data(as: KMLPin.self),
//               existingPin.coordinate.latitude == pin.coordinate.latitude,
//               existingPin.coordinate.longitude == pin.coordinate.longitude,
//               existingPin.createdDate == pin.createdDate,
//               existingPin.name == pin.name,
//               existingPin.color == pin.color,
//               existingPin.creatorEmail == pin.creatorEmail {
//                return true
//            }
//        }
//        
//        return false
//    }

    /// Find all duplicate pins in Firebase
    func findDuplicatePins() async throws -> [[KMLPin]] {
        let snapshot = try await db.collection("kmlPins").getDocuments()
        let allPins = snapshot.documents.compactMap { try? $0.data(as: KMLPin.self) }
        
        // Group pins by key fields
        var groups: [String: [KMLPin]] = [:]
        
        for pin in allPins {
            // Create key from all identifying fields
            let key = "\(pin.coordinate.latitude)_\(pin.coordinate.longitude)_\(pin.createdDate.timeIntervalSince1970)_\(pin.name)_\(pin.color)_\(pin.creatorEmail ?? "none")"
            
            if groups[key] == nil {
                groups[key] = []
            }
            groups[key]?.append(pin)
        }
        
        // Return only groups with duplicates (2+ pins)
        let duplicates = groups.values.filter { $0.count > 1 }
        
        print("🔍 Found \(duplicates.count) sets of duplicates")
        for (index, group) in duplicates.enumerated() {
            print("  Set \(index + 1): \(group.count) copies of '\(group[0].name)'")
        }
        
        return Array(duplicates)
    }
    // MARK: - DeerHerdFirebaseManager.swift (ADD THIS METHOD)

    // ADD to DeerHerdFirebaseManager class:

    /// Nuclear reset: Delete ALL data for a property (pins, photos, observations, sessions, profiles)
    /// Keeps the property record itself, but empties all content
    func nukePropertyData(_ propertyId: String) async throws {
        print("☢️ NUCLEAR RESET: Starting for property \(propertyId)")
        
        var deletedCounts = (pins: 0, photos: 0, observations: 0, sessions: 0, profiles: 0, storageFiles: 0)
        
        // 1. Delete all pins
        let pinsSnapshot = try await db.collection("kmlPins")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in pinsSnapshot.documents {
            try await doc.reference.delete()
            deletedCounts.pins += 1
        }
        print("☢️ Deleted \(deletedCounts.pins) pins")
        
        // 2. Delete all photos (records + storage files)
        let photosSnapshot = try await db.collection("photos")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in photosSnapshot.documents {
            if let photo = try? doc.data(as: Photo.self) {
                // Delete storage files
                if let storageUrl = photo.firebaseStorageUrl {
                    try? await deleteStorageFile(from: storageUrl)
                    deletedCounts.storageFiles += 1
                }
                if let thumbnailUrl = photo.thumbnailUrl {
                    try? await deleteStorageFile(from: thumbnailUrl)
                    deletedCounts.storageFiles += 1
                }
            }
            
            try await doc.reference.delete()
            deletedCounts.photos += 1
        }
        print("☢️ Deleted \(deletedCounts.photos) photos and \(deletedCounts.storageFiles) storage files")
        
        // 3. Delete all observations
        let observationsSnapshot = try await db.collection("deerObservations")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in observationsSnapshot.documents {
            try await doc.reference.delete()
            deletedCounts.observations += 1
        }
        print("☢️ Deleted \(deletedCounts.observations) observations")
        
        // 4. Delete all sessions
        let sessionsSnapshot = try await db.collection("flightSessions")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in sessionsSnapshot.documents {
            try await doc.reference.delete()
            deletedCounts.sessions += 1
        }
        print("☢️ Deleted \(deletedCounts.sessions) sessions")
        
        // 5. Delete all buck profiles
        let profilesSnapshot = try await db.collection("buckProfiles")
            .whereField("propertyId", isEqualTo: propertyId)
            .getDocuments()
        
        for doc in profilesSnapshot.documents {
            try await doc.reference.delete()
            deletedCounts.profiles += 1
        }
        print("☢️ Deleted \(deletedCounts.profiles) buck profiles")
        
        // 6. Clear property boundary (keep property record)
        let propertyRef = db.collection("properties").document(propertyId)
        try await propertyRef.updateData([
            "boundaryKML": FieldValue.delete()
        ])
        print("☢️ Cleared property boundary")
        
        print("☢️ NUCLEAR RESET COMPLETE:")
        print("   Pins: \(deletedCounts.pins)")
        print("   Photos: \(deletedCounts.photos)")
        print("   Storage Files: \(deletedCounts.storageFiles)")
        print("   Observations: \(deletedCounts.observations)")
        print("   Sessions: \(deletedCounts.sessions)")
        print("   Buck Profiles: \(deletedCounts.profiles)")
        try await propertyRef.delete()
        print ("Now deleted the property record")
    }

    /// Helper to delete a storage file from Firebase Storage
//    private func deleteStorageFile(from urlString: String) async throws {
//        guard let url = URL(string: urlString) else { return }
//        
//        // Extract storage path from URL
//        // URL format: https://firebasestorage.googleapis.com/v0/b/bucket/o/path%2Fto%2Ffile.jpg?token=...
//        let path = url.path
//            .replacingOccurrences(of: "/v0/b/", with: "")
//            .components(separatedBy: "/o/")
//            .last?
//            .components(separatedBy: "?")
//            .first?
//            .removingPercentEncoding ?? ""
//        
//        guard !path.isEmpty else { return }
//        
//        let ref = storage.reference().child(path)
//        try await ref.delete()
//    }
    /// Delete duplicate pins, keeping the best one in each set
    /// Prefers pins with matchedPhotoIds, then newest by ID
    func deleteDuplicatePins() async throws -> Int {
        let duplicateSets = try await findDuplicatePins()
        var deletedCount = 0
        
        for group in duplicateSets {
            // Sort by: hasMatchedPhotos first (prefer pins with matches), then by id (prefer newer)
            let sorted = group.sorted { pin1, pin2 in
                let has1 = !pin1.matchedPhotoIds.isEmpty
                let has2 = !pin2.matchedPhotoIds.isEmpty
                
                if has1 != has2 {
                    return !has1 // pin2 is better if it has matches
                }
                return pin1.id < pin2.id // Both same match status, prefer newer
            }
            
            let toKeep = sorted.last! // Best one (has matches if any, and newest)
            let toDelete = sorted.dropLast()
            
            print("✅ Keeping: \(toKeep.name) (id: \(toKeep.id)) [matched photos: \(toKeep.matchedPhotoIds.count)]")
            
            for pin in toDelete {
                try await db.collection("kmlPins").document(pin.id).delete()
                deletedCount += 1
                print("🗑️ Deleted duplicate pin: \(pin.name) (id: \(pin.id))")
            }
        }
        
        print("✅ Deleted \(deletedCount) duplicate pins")
        return deletedCount
    }
}
