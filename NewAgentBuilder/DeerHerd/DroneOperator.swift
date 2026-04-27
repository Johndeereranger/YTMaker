//
//  DroneOperator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - DroneOperator.swift
import Foundation

struct DroneOperator: Identifiable, Codable, Hashable {
    let id: String
    var email: String
    var name: String
    var createdAt: Date
    
    init(id: String = UUID().uuidString,
         email: String,
         name: String,
         createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - Property.swift
import Foundation
import CoreLocation

struct Property: Identifiable, Codable, Hashable {
    let id: String
    var operatorId: String
    var name: String
    var state: String
    var clientEmail: String?
    var boundaryKML: PropertyBoundary?
    var totalAcres: Double?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString,
         operatorId: String,
         name: String,
         state: String,
         clientEmail: String? = nil,
         boundaryKML: PropertyBoundary? = nil,
         totalAcres: Double? = nil,
         notes: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.operatorId = operatorId
        self.name = name
        self.state = state
        self.clientEmail = clientEmail
        self.boundaryKML = boundaryKML
        self.totalAcres = totalAcres
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct PropertyBoundary: Codable, Hashable {
    var coordinates: [CLLocationCoordinate2D]
    var calculatedAcres: Double
    
    enum CodingKeys: String, CodingKey {
        case coordinates, calculatedAcres
    }
    
    init(coordinates: [CLLocationCoordinate2D], calculatedAcres: Double) {
        self.coordinates = coordinates
        self.calculatedAcres = calculatedAcres
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let coordArray = coordinates.map { ["lat": $0.latitude, "lon": $0.longitude] }
        try container.encode(coordArray, forKey: .coordinates)
        try container.encode(calculatedAcres, forKey: .calculatedAcres)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordArray = try container.decode([[String: Double]].self, forKey: .coordinates)
        self.coordinates = coordArray.compactMap { dict in
            guard let lat = dict["lat"], let lon = dict["lon"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        self.calculatedAcres = try container.decode(Double.self, forKey: .calculatedAcres)
    }
}

// MARK: - FlightSession.swift
import Foundation

struct FlightSession: Identifiable, Codable, Hashable {
    let id: String
    var propertyId: String
    var date: Date
    var timeOfDay: TimeOfDay
    var colorMappings: [String: DeerClassification] // "red": .buck, etc.
    var createdAt: Date
    
    enum TimeOfDay: String, Codable {
        case morning
        case afternoon
        
        static func from(date: Date) -> TimeOfDay {
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 12 ? .morning : .afternoon
        }
    }
    
    init(id: String = UUID().uuidString,
         propertyId: String,
         date: Date,
         timeOfDay: TimeOfDay,
         colorMappings: [String: DeerClassification],
         createdAt: Date = Date()) {
        self.id = id
        self.propertyId = propertyId
        self.date = date
        self.timeOfDay = timeOfDay
        self.colorMappings = colorMappings
        self.createdAt = createdAt
    }
}

// MARK: - DeerObservation.swift
struct DeerObservation: Identifiable, Codable, Hashable {
    let id: String
    var sessionId: String
    var propertyId: String
    var gpsLat: Double
    var gpsLon: Double
    var classification: DeerClassification
    var color: String // original KML color, "black" if no match
    var timestamp: Date
    var buckProfileId: String?
    var photos: [Photo]
    
    // NEW: Classification tracking
    var classificationSource: ClassificationSource? = .unknown
    var matchedPinId: String? = nil
    var isIncludedInCalculations: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: gpsLat, longitude: gpsLon)
    }
    
    init(id: String = UUID().uuidString,
         sessionId: String,
         propertyId: String,
         gpsLat: Double,
         gpsLon: Double,
         classification: DeerClassification,
         color: String,
         timestamp: Date,
         buckProfileId: String? = nil,
         photos: [Photo] = [],
         classificationSource: ClassificationSource? = .unknown,
         matchedPinId: String? = nil,
         isIncludedInCalculations: Bool = true) {
        self.id = id
        self.sessionId = sessionId
        self.propertyId = propertyId
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.classification = classification
        self.color = color
        self.timestamp = timestamp
        self.buckProfileId = buckProfileId
        self.photos = photos
        self.classificationSource = classificationSource
        self.matchedPinId = matchedPinId
        self.isIncludedInCalculations = isIncludedInCalculations
    }
}

enum ClassificationSource: String, Codable {
    case pinMatch = "pin_match"        // Matched to KML pin
    case manual = "manual"             // User manually classified
    case unknown = "unknown"           // No classification yet
}


extension DeerObservation {
    /// Returns the primary (visible) photo for display
    var primaryPhoto: Photo? {
        return visiblePhoto ?? photos.first
    }
    
    /// Returns the visible/color photo if exists
    var visiblePhoto: Photo? {
        return photos.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_V.") || filename.contains("_v.")
            }
            return false
        }
    }
    
    /// Returns the thermal photo if exists
    var thermalPhoto: Photo? {
        return photos.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_T.") || filename.contains("_t.")
            }
            return false
        }
    }
    
    /// Returns true if this observation has both thermal and visible photos
    var hasBothPhotoTypes: Bool {
        return visiblePhoto != nil && thermalPhoto != nil
    }
}

enum DeerClassification: String, Codable, CaseIterable {
    case buck = "Buck"
    case doe = "Doe"
    case beddedBuck = "Bedded Buck"
    case beddedDoe = "Bedded Doe"
    case matureBuck = "Mature Buck"
    case matureBeddedBuck = "Mature Bedded Buck"
    case coyote = "Coyote"
    case fox = "Fox"
    case unknown = "Unknown"
    
    
    var isBuck: Bool {
        switch self {
        case .buck, .beddedBuck, .matureBuck, .matureBeddedBuck:
            return true
            
        default :
            return false
        }
    }
    
    var isMatureBuck: Bool {
        switch self {
        case .matureBuck, .matureBeddedBuck:
            return true
        default :
            return false
        }
    }
    
   var isBedded: Bool {
        switch self {
        case .beddedBuck, .beddedDoe, .matureBeddedBuck:
            return true
        default :
            return false
        }
    }
}

// MARK: - Photo.swift
import Foundation

struct Photo: Identifiable, Codable, Hashable {
    let id: String
    var observationId: String?
    var sessionId: String
    var propertyId: String
    var firebaseStorageUrl: String?
    var thumbnailUrl: String?
    var gpsLat: Double
    var gpsLon: Double
    var timestamp: Date
    var altitude: Double?
    var cameraMake: String?
    var cameraModel: String?
    var metadata: [String: String]
    
    init(id: String = UUID().uuidString,
         observationId: String? = nil,
         sessionId: String,
         propertyId: String,
         firebaseStorageUrl: String? = nil,
         thumbnailUrl: String? = nil,
         gpsLat: Double,
         gpsLon: Double,
         timestamp: Date,
         altitude: Double? = nil,
         cameraMake: String? = nil,
         cameraModel: String? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.observationId = observationId
        self.sessionId = sessionId
        self.propertyId = propertyId
        self.firebaseStorageUrl = firebaseStorageUrl
        self.thumbnailUrl = thumbnailUrl
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.timestamp = timestamp
        self.altitude = altitude
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.metadata = metadata
    }
}

// MARK: - BuckProfile.swift
import Foundation

struct BuckProfile: Identifiable, Codable, Hashable {
    let id: String
    var propertyId: String
    var name: String
    var ageEstimate: String?
    var status: BuckStatus
    var notes: String?
    var firstSeenDate: Date?
    var lastSeenDate: Date?
    var linkedObservationIds: [String]
    var createdAt: Date
    var updatedAt: Date
    
    enum BuckStatus: String, Codable, CaseIterable {
        case live = "Live"
        case harvested = "Harvested"
        case unknown = "Unknown"
    }
    
    init(id: String = UUID().uuidString,
         propertyId: String,
         name: String,
         ageEstimate: String? = nil,
         status: BuckStatus = .live,
         notes: String? = nil,
         firstSeenDate: Date? = nil,
         lastSeenDate: Date? = nil,
         linkedObservationIds: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.propertyId = propertyId
        self.name = name
        self.ageEstimate = ageEstimate
        self.status = status
        self.notes = notes
        self.firstSeenDate = firstSeenDate
        self.lastSeenDate = lastSeenDate
        self.linkedObservationIds = linkedObservationIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - KMLPin.swift (for parsing)
import Foundation
import CoreLocation

//struct KMLPin: Hashable {
//    let coordinate: CLLocationCoordinate2D
//    let color: String
//    let name: String?
//}
