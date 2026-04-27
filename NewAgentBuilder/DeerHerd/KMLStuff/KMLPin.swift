//
//  KMLPin.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - KMLPin.swift (Enhanced)
import Foundation
import CoreLocation

struct KMLPin: Identifiable, Codable, Hashable {
    let id: String
    var sessionId: String?
    var propertyId: String?
    var coordinate: CLLocationCoordinate2D
    var altitude: Double
    var color: String // "blue", "red", "green", etc
    var styleUrl: String // "#dji_style_blue"
    var name: String
    var createdDate: Date
    var creatorEmail: String?
    var matchedPhotoIds: [String] // Photos matched to this pin
    var observationId: String? // If converted to observation
    var isIncludedInCalculations: Bool
    
    // For Codable
    enum CodingKeys: String, CodingKey {
        case id, sessionId, propertyId, altitude, color, styleUrl, name
        case createdDate, creatorEmail, matchedPhotoIds, observationId
        case latitude, longitude
        case isIncludedInCalculations
    }
    
    init(id: String = UUID().uuidString,
         sessionId: String? = nil,
         propertyId: String? = nil,
         coordinate: CLLocationCoordinate2D,
         altitude: Double,
         color: String,
         styleUrl: String,
         name: String,
         createdDate: Date,
         creatorEmail: String? = nil,
         matchedPhotoIds: [String] = [],
         observationId: String? = nil,
         isIncludedInCalculations: Bool = true) {
        self.id = id
        self.sessionId = sessionId
        self.propertyId = propertyId
        self.coordinate = coordinate
        self.altitude = altitude
        self.color = color
        self.styleUrl = styleUrl
        self.name = name
        self.createdDate = createdDate
        self.creatorEmail = creatorEmail
        self.matchedPhotoIds = matchedPhotoIds
        self.observationId = observationId
        self.isIncludedInCalculations = isIncludedInCalculations
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(propertyId, forKey: .propertyId)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(color, forKey: .color)
        try container.encode(styleUrl, forKey: .styleUrl)
        try container.encode(name, forKey: .name)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encodeIfPresent(creatorEmail, forKey: .creatorEmail)
        try container.encode(matchedPhotoIds, forKey: .matchedPhotoIds)
        try container.encodeIfPresent(observationId, forKey: .observationId)
        try container.encode(isIncludedInCalculations, forKey: .isIncludedInCalculations)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        propertyId = try container.decodeIfPresent(String.self, forKey: .propertyId)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        altitude = try container.decode(Double.self, forKey: .altitude)
        color = try container.decode(String.self, forKey: .color)
        styleUrl = try container.decode(String.self, forKey: .styleUrl)
        name = try container.decode(String.self, forKey: .name)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        creatorEmail = try container.decodeIfPresent(String.self, forKey: .creatorEmail)
        matchedPhotoIds = try container.decode([String].self, forKey: .matchedPhotoIds)
        observationId = try container.decodeIfPresent(String.self, forKey: .observationId)
        isIncludedInCalculations = try container.decodeIfPresent(Bool.self, forKey: .isIncludedInCalculations) ?? true
    }
}
