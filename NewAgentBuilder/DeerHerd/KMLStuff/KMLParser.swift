//
//  KMLParser.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - KMLParser (Complete & Fixed)
import Foundation
import CoreLocation

class KMLParser: NSObject, XMLParserDelegate {
    static let shared = KMLParser()
    private override init() {}
    
    // Results
    private var pins: [KMLPin] = []
    
    // Style definitions
    private var styles: [String: String] = [:] // styleId -> color name
    
    // Current parsing state
    private var currentElement = ""
    private var currentText = ""
    
    // Current placemark data
    private var currentName = ""
    private var currentDescription = ""
    private var currentStyleUrl = ""
    private var currentCoordinates = ""
    
    func parse(kmlData: Data) -> [KMLPin] {
        pins = []
        styles = [:]
        resetCurrentPlacemark()
        
        let parser = XMLParser(data: kmlData)
        parser.delegate = self
        parser.parse()
        
        print("✅ KMLParser: Parsed \(pins.count) pins")
        print("  Styles found: \(styles)")
        
        return pins
    }
    
    func parse(kmlURL: URL) -> [KMLPin]? {
        // Handle security-scoped resources
        let accessing = kmlURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                kmlURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let data = try? Data(contentsOf: kmlURL) else {
            print("❌ KMLParser: Failed to read file at \(kmlURL)")
            return nil
        }
        
        return parse(kmlData: data)
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        if elementName == "Style" {
            // Track style ID for mapping
            if let id = attributeDict["id"] {
                // We'll get the color in a nested element
                currentStyleUrl = id
            }
        }
        
        if elementName == "Placemark" {
            resetCurrentPlacemark()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "n":
            // DJI uses <n> for name, not <name>
            currentName = trimmed
            
        case "description":
            currentDescription = trimmed
            
        case "styleUrl":
            currentStyleUrl = trimmed
            
        case "coordinates":
            currentCoordinates = trimmed
            
        case "color":
            // Color definition in Style section
            if !currentStyleUrl.isEmpty {
                let colorName = mapColorHexToName(trimmed)
                styles[currentStyleUrl] = colorName
                print("  Style: \(currentStyleUrl) = \(colorName)")
            }
            
        case "Placemark":
            // Complete placemark - build KMLPin
            if let pin = buildPin() {
                pins.append(pin)
            }
            resetCurrentPlacemark()
            
        default:
            break
        }
        
        currentText = ""
    }
    
    // MARK: - Build Pin
    
    private func buildPin() -> KMLPin? {
        // Parse coordinates
        guard let coords = parseCoordinates(currentCoordinates) else {
            print("⚠️ Skipping pin '\(currentName)' - no valid coordinates")
            return nil
        }
        
        // Parse description for timestamp and email
        let (date, email) = parseDescription(currentDescription)
        
        // Map styleUrl to color name
        let color = colorFromStyleUrl(currentStyleUrl)
        
        let pin = KMLPin(
            coordinate: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lon),
            altitude: coords.alt,
            color: color,
            styleUrl: currentStyleUrl,
            name: currentName,
            createdDate: date ?? Date(),
            creatorEmail: email
        )
        
        return pin
    }
    
    // MARK: - Parsing Helpers
    
    private func parseCoordinates(_ coordString: String) -> (lon: Double, lat: Double, alt: Double)? {
        let components = coordString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard components.count >= 2 else { return nil }
        
        guard let lon = Double(components[0]),
              let lat = Double(components[1]) else { return nil }
        
        let alt = components.count > 2 ? (Double(components[2]) ?? 0) : 0
        
        return (lon, lat, alt)
    }
    
    private func parseDescription(_ description: String) -> (date: Date?, email: String?) {
        // Parse: "Created by smith.byronj@gmail.com on 2025-10-17 08:19:12"
        var date: Date?
        var email: String?
        
        // Extract email
        if let emailRange = description.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            email = String(description[emailRange])
        }
        
        // Extract date
        if let dateRange = description.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, options: .regularExpression) {
            let dateString = String(description[dateRange])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            date = formatter.date(from: dateString)
        }
        
        return (date, email)
    }
    
    private func colorFromStyleUrl(_ styleUrl: String) -> String {
        // Remove # prefix
        let styleId = styleUrl.replacingOccurrences(of: "#", with: "")
        
        // Check if we have a mapped color from Style definitions
        if let mappedColor = styles[styleId] {
            return mappedColor
        }
        
        // Fallback: extract from styleUrl itself (e.g., "dji_style_blue" -> "blue")
        if styleId.contains("_blue") { return "blue" }
        if styleId.contains("_red") { return "red" }
        if styleId.contains("_green") { return "green" }
        if styleId.contains("_yellow") { return "yellow" }
        if styleId.contains("_purple") { return "purple" }
        
        return "unknown"
    }
    
    private func mapColorHexToName(_ hex: String) -> String {
        // DJI KML colors are in ARGB format: #AARRGGBB
        // Common mappings from your KML:
        let colorMap: [String: String] = [
            "FFF08C2D": "blue",    // #FFF08C2D
            "FF6BBE19": "green",   // #FF6BBE19
            "FF00BBFF": "yellow",  // #FF00BBFF
            "FFE020B6": "purple",  // #FFE020B6
            "FF393CE2": "red"      // #FF393CE2
        ]
        
        // Remove # prefix if present
        let cleanHex = hex.replacingOccurrences(of: "#", with: "").uppercased()
        
        return colorMap[cleanHex] ?? "unknown"
    }
    
    private func resetCurrentPlacemark() {
        currentName = ""
        currentDescription = ""
        currentStyleUrl = ""
        currentCoordinates = ""
    }
}