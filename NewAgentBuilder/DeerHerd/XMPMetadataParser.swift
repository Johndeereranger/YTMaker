//
//  XMPMetadataParser.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - XMPMetadataParser.swift
import Foundation
import ImageIO
import CoreLocation

// MARK: - XMPMetadataParser.swift (Updated with working EXIF code)
import Foundation
import ImageIO
import CoreLocation

class XMPMetadataParser {
    static let shared = XMPMetadataParser()
    private init() {}
    
    struct PhotoMetadata {
        let gpsLat: Double
        let gpsLon: Double
        let timestamp: Date
        let altitude: Double?
        let cameraMake: String?
        let cameraModel: String?
        let lrfTargetLat: Double?  // NEW: Laser rangefinder target
        let lrfTargetLon: Double?  // NEW: Laser rangefinder target
        let allMetadata: [String: String]
    }
    
    func parseMetadata(from imageURL: URL) -> PhotoMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            print("❌ Failed to read image properties")
            return nil
        }
        
        // GPS Data
        guard let gpsInfo = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gpsInfo[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gpsInfo[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gpsInfo[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gpsInfo[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            print("❌ No GPS data found in image")
            return nil
        }
        
        let latitude = latRef == "S" ? -lat : lat
        let longitude = lonRef == "W" ? -lon : lon
        
        // Timestamp
        var timestamp = Date()
        if let exifInfo = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let dateString = exifInfo[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            timestamp = formatter.date(from: dateString) ?? Date()
        }
        
        // Altitude
        let altitude = gpsInfo[kCGImagePropertyGPSAltitude as String] as? Double
        
        // Camera info
        let tiffInfo = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let cameraMake = tiffInfo?[kCGImagePropertyTIFFMake as String] as? String
        let cameraModel = tiffInfo?[kCGImagePropertyTIFFModel as String] as? String
        
        // LRF Target coordinates (using your working code)
        var lrfTargetLat: Double?
        var lrfTargetLon: Double?
        
        // Try to get RAW XMP METADATA
        if let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil) {
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
            if let tags = tags {
                for tag in tags {
                    if let name = CGImageMetadataTagCopyName(tag) as? String,
                       let value = CGImageMetadataTagCopyValue(tag) {
                        let valueStr = "\(value)"
                        
                        // Check if this is our LRF data
                        if name.contains("LRF") && name.contains("Lon") {
                            lrfTargetLon = Double(valueStr)
                        }
                        if name.contains("LRF") && name.contains("Lat") {
                            lrfTargetLat = Double(valueStr)
                        }
                    }
                }
            }
        }
        
        // Try XMP string parsing
        if let xmp = properties["{XMP}"] as? String {
            let (lat, lon) = extractLRFCoordinates(from: xmp)
            if lrfTargetLat == nil { lrfTargetLat = lat }
            if lrfTargetLon == nil { lrfTargetLon = lon }
        }
        
        // Flatten all metadata for storage
        var allMetadata: [String: String] = [:]
        for (key, value) in properties {
            if let stringValue = value as? String {
                allMetadata[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                allMetadata[key] = numberValue.stringValue
            }
        }
        
        return PhotoMetadata(
            gpsLat: latitude,
            gpsLon: longitude,
            timestamp: timestamp,
            altitude: altitude,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lrfTargetLat: lrfTargetLat,
            lrfTargetLon: lrfTargetLon,
            allMetadata: allMetadata
        )
    }
    
    private func extractLRFCoordinates(from xmpString: String) -> (lat: Double?, lon: Double?) {
        var lat: Double?
        var lon: Double?
        
        // Look for LRF Target Lon
        let lonPatterns = [
            "LRFTargetLon=\"([^\"]+)\"",
            "LRF Target Lon=\"([^\"]+)\"",
            "drone-dji:LRFTargetLon=\"([^\"]+)\"",
            "dji:LRFTargetLon=\"([^\"]+)\""
        ]
        
        for pattern in lonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: xmpString) {
                lon = Double(String(xmpString[range]))
                break
            }
        }
        
        // Look for LRF Target Lat
        let latPatterns = [
            "LRFTargetLat=\"([^\"]+)\"",
            "LRF Target Lat=\"([^\"]+)\"",
            "drone-dji:LRFTargetLat=\"([^\"]+)\"",
            "dji:LRFTargetLat=\"([^\"]+)\""
        ]
        
        for pattern in latPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: xmpString, options: [], range: NSRange(xmpString.startIndex..., in: xmpString)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: xmpString) {
                lat = Double(String(xmpString[range]))
                break
            }
        }
        
        return (lat, lon)
    }
}

// MARK: - CoordinateUtilities.swift
import Foundation
import CoreLocation

class CoordinateUtilities {
    static let shared = CoordinateUtilities()
    private init() {}
    
    func distance(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2) // meters
    }
    
    func calculateArea(of coordinates: [CLLocationCoordinate2D]) -> Double {
        // Calculate area using Shoelace formula
        guard coordinates.count >= 3 else { return 0 }
        
        var area: Double = 0
        for i in 0..<coordinates.count {
            let j = (i + 1) % coordinates.count
            area += coordinates[i].longitude * coordinates[j].latitude
            area -= coordinates[j].longitude * coordinates[i].latitude
        }
        area = abs(area) / 2.0
        
        // Convert to acres (very rough approximation)
        // 1 degree ≈ 69 miles ≈ 4,486,400 sq feet
        // 1 acre = 43,560 sq feet
        let sqDegrees = area
        let sqMiles = sqDegrees * 69 * 69
        let acres = sqMiles * 640 // 640 acres per square mile
        
        return acres
    }
    
    func calculateConvexHullArea(of coordinates: [CLLocationCoordinate2D]) -> Double {
        // Simplified: calculate bounding box area as approximation
        guard !coordinates.isEmpty else { return 0 }
        
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        let corners = [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
        ]
        
        return calculateArea(of: corners)
    }
}
