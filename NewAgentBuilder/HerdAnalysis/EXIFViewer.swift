//
//  EXIFViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/23/25.
//
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
struct EXIFViewer: View {
    @State private var targetLon: String = "N/A"
    @State private var targetLat: String = "N/A"
    @State private var isDragging = false
    @State private var fileName: String = ""
    @State private var debugInfo: String = ""
   
    var body: some View {
        VStack(spacing: 20) {
            Text("EXIF Viewer")
                .font(.title)
                .padding(.top)
           
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDragging ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDragging ? Color.blue : Color.gray,
                                   style: StrokeStyle(lineWidth: 2, dash: [10]))
                    )
               
                VStack(spacing: 10) {
                    Image(systemName: fileName.isEmpty ? "photo.badge.arrow.down" : "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(fileName.isEmpty ? .gray : .green)
                   
                    Text(fileName.isEmpty ? "Drop JPG Image Here" : fileName)
                        .font(.headline)
                        .foregroundColor(fileName.isEmpty ? .gray : .primary)
                }
            }
            .frame(height: 250)
            .padding()
            .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
           
            // LRF Data Display
            VStack(alignment: .leading, spacing: 12) {
                Divider()
               
                HStack {
                    Text("LRF Target Lon")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(targetLon)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
               
                HStack {
                    Text("LRF Target Lat")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(targetLat)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
               
                if !debugInfo.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(debugInfo)
                            .font(.caption)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                        
                        Button("Copy Debug Info") {
                            UIPasteboard.general.string = debugInfo
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
           
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
   
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
       
        for provider in providers {
            // Try file URL first (when dragging from Finder)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url,
                          ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return }
                   
                    DispatchQueue.main.async {
                        self.fileName = url.lastPathComponent
                        self.extractLRFDataFromURL(url)
                    }
                }
                handled = true
            }
           
            // Try image data (when dragging from other apps)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data = data else { return }
                   
                    // Write to temp file so we can read with CGImageSource
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("temp_\(UUID().uuidString).jpg")
                   
                    do {
                        try data.write(to: tempURL)
                        DispatchQueue.main.async {
                            self.fileName = "Dropped Image"
                            self.extractLRFDataFromURL(tempURL)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.debugInfo = "Error writing temp file"
                        }
                    }
                }
                handled = true
            }
        }
       
        return handled
    }
   
    func extractLRFDataFromURL(_ url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            debugInfo = "Failed to read image properties"
            return
        }
       
        // Expanded debug info
        var debugLines: [String] = []
        debugLines.append("Top-level keys: \(properties.keys.joined(separator: ", "))")
        
        // Show what's in each dictionary
        for (key, value) in properties {
            if let dict = value as? [String: Any] {
                debugLines.append("\n\(key) contains: \(dict.keys.joined(separator: ", "))")
            }
        }
        
        // TRY TO GET RAW XMP METADATA
        if let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil) {
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
            if let tags = tags {
                debugLines.append("\n\n📋 RAW XMP TAGS (\(tags.count) found):")
                for tag in tags {
                    if let name = CGImageMetadataTagCopyName(tag) as? String,
                       let value = CGImageMetadataTagCopyValue(tag) {
                        let valueStr = "\(value)"
                        debugLines.append("\n  \(name) = \(valueStr.prefix(100))")
                        
                        // Check if this is our LRF data
                        if name.contains("LRF") && name.contains("Lon") {
                            targetLon = valueStr
                        }
                        if name.contains("LRF") && name.contains("Lat") {
                            targetLat = valueStr
                        }
                    }
                }
            }
        }
       
        // Method 1: Look in EXIF MakerNote (where DJI often stores data)
        if let exif = properties["{Exif}"] as? [String: Any] {
            searchInDictionary(exif, name: "EXIF")
        }
       
        // Method 2: Look in IPTC
        if let iptc = properties["{IPTC}"] as? [String: Any] {
            searchInDictionary(iptc, name: "IPTC")
        }
       
        // Method 3: Try XMP if it exists
        if let xmp = properties["{XMP}"] as? String {
            debugLines.append("\n\nFound XMP string (length: \(xmp.count))")
            debugLines.append("\nXMP Content: \(xmp.prefix(500))...")
            extractCoordinates(from: xmp)
        } else {
            debugLines.append("\n\n⚠️ NO {XMP} key found in properties")
        }
       
        // Method 4: Search all top-level dictionaries
        for (key, value) in properties {
            if let dict = value as? [String: Any] {
                searchInDictionary(dict, name: key)
            }
        }
       
        if targetLon == "N/A" && targetLat == "N/A" {
            debugLines.append("\n❌ No laser data found")
        } else if targetLon != "N/A" && targetLat != "N/A" {
            debugLines.append("\n✓ Found both coordinates")
        } else {
            debugLines.append("\n⚠️ Found only one coordinate")
        }
        
        debugInfo = debugLines.joined(separator: "\n")
    }
   
    func searchInDictionary(_ dict: [String: Any], name: String) {
        for (key, value) in dict {
            // Look for LRF Target Lon (the ACTUAL key name)
            if key.contains("LRF") && (key.contains("Lon") || key.contains("Longitude")) {
                if let lon = value as? String {
                    targetLon = lon
                } else if let lon = value as? NSNumber {
                    targetLon = lon.stringValue
                }
            }
           
            // Look for LRF Target Lat (the ACTUAL key name)
            if key.contains("LRF") && (key.contains("Lat") || key.contains("Latitude")) {
                if let lat = value as? String {
                    targetLat = lat
                } else if let lat = value as? NSNumber {
                    targetLat = lat.stringValue
                }
            }
           
            // If value is a nested dictionary, search recursively
            if let nestedDict = value as? [String: Any] {
                searchInDictionary(nestedDict, name: "\(name).\(key)")
            }
           
            // If value is a string that looks like XML/XMP, parse it
            if let stringVal = value as? String, stringVal.contains("LRF") {
                extractCoordinates(from: stringVal)
            }
        }
    }
   
    func extractCoordinates(from xmpString: String) {
        // Look for LRF Target Lon (the ACTUAL XMP tag names)
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
                targetLon = String(xmpString[range])
                break
            }
        }
       
        // Look for LRF Target Lat (the ACTUAL XMP tag names)
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
                targetLat = String(xmpString[range])
                break
            }
        }
    }
}
