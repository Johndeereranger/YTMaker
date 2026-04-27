//
//  KMLViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//
// This was close but drag and drop didn't work
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct KMLViewer: View {
//    @State private var fileName: String = ""
//    @State private var isDragging = false
//    @State private var debugInfo: String = ""
//    
//    // Parsed KML Data
//    @State private var totalPlacemarks: Int = 0
//    @State private var dateRange: String = "N/A"
//    @State private var creatorEmail: String = "N/A"
//    @State private var coordinateBounds: String = "N/A"
//    @State private var altitudeRange: String = "N/A"
//    @State private var placemarkNames: String = "N/A"
//    @State private var showingDocumentPicker = false
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("KML Parser")
//                .font(.title)
//                .padding(.top)
//            
//            // Drop Zone
//            ZStack {
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(isDragging ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 12)
//                            .stroke(isDragging ? Color.blue : Color.gray,
//                                   style: StrokeStyle(lineWidth: 2, dash: [10]))
//                    )
//                
//                VStack(spacing: 10) {
//                    Image(systemName: fileName.isEmpty ? "map.circle" : "checkmark.circle.fill")
//                        .font(.system(size: 50))
//                        .foregroundColor(fileName.isEmpty ? .gray : .green)
//                    
//                    Text(fileName.isEmpty ? "Drop KML File Here" : fileName)
//                        .font(.headline)
//                        .foregroundColor(fileName.isEmpty ? .gray : .primary)
//                    
//                    if fileName.isEmpty {
//                        Text("or")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                        
//                        Button("Browse Files") {
//                            browseForKML()
//                        }
//                        .buttonStyle(.bordered)
//                    }
//                }
//            }
//            .frame(height: 250)
//            .padding()
//            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
//                handleDrop(providers: providers)
//            }
//            
//            // KML Data Display
//            if !fileName.isEmpty {
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 12) {
//                        Divider()
//                        
//                        DataRow(label: "Total Pins", value: "\(totalPlacemarks)")
//                        DataRow(label: "Creator", value: creatorEmail)
//                        DataRow(label: "Date Range", value: dateRange)
//                        DataRow(label: "Pin Names", value: placemarkNames)
//                        DataRow(label: "Coordinate Bounds", value: coordinateBounds)
//                        DataRow(label: "Altitude Range", value: altitudeRange)
//                        
//                        if !debugInfo.isEmpty {
//                            VStack(alignment: .leading, spacing: 8) {
//                                Divider()
//                                Text("Debug Info")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                                    .padding(.top, 8)
//                                
//                                Text(debugInfo)
//                                    .font(.caption)
//                                    .foregroundColor(.orange)
//                                    .textSelection(.enabled)
//                                
//                                Button("Copy Debug Info") {
//                                    #if os(iOS)
//                                    UIPasteboard.general.string = debugInfo
//                                    #elseif os(macOS)
//                                    NSPasteboard.general.clearContents()
//                                    NSPasteboard.general.setString(debugInfo, forType: .string)
//                                    #endif
//                                }
//                                .buttonStyle(.bordered)
//                                .controlSize(.small)
//                            }
//                        }
//                    }
//                    .padding()
//                    .background(Color.gray.opacity(0.05))
//                    .cornerRadius(8)
//                    .padding(.horizontal)
//                }
//            }
//            
//            Spacer()
//        }
//        .frame(minWidth: 500, minHeight: 400)
//        .sheet(isPresented: $showingDocumentPicker) {
//            DocumentPicker { url in
//                fileName = url.lastPathComponent
//                parseKMLFile(at: url)
//            }
//        }
//    }
//    
//    func handleDrop(providers: [NSItemProvider]) -> Bool {
//        guard let provider = providers.first else { return false }
//        
//        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
//            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
//                guard let data = item as? Data,
//                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
//                    return
//                }
//                
//                guard url.pathExtension.lowercased() == "kml" else { return }
//                
//                DispatchQueue.main.async {
//                    self.fileName = url.lastPathComponent
//                    self.parseKMLFile(at: url)
//                }
//            }
//            return true
//        }
//        
//        return false
//    }
//    
//    func browseForKML() {
//        #if os(macOS)
//        let panel = NSOpenPanel()
//        panel.allowedContentTypes = [UTType(filenameExtension: "kml")!]
//        panel.allowsMultipleSelection = false
//        panel.canChooseDirectories = false
//        panel.canChooseFiles = true
//        
//        if panel.runModal() == .OK, let url = panel.url {
//            fileName = url.lastPathComponent
//            parseKMLFile(at: url)
//        }
//        #elseif os(iOS)
//        showingDocumentPicker = true
//        #endif
//    }
//    
//    func parseKMLFile(at url: URL) {
//        do {
//            let data = try Data(contentsOf: url)
//            let parser = KMLParser2()
//            parser.parse(data: data)
//            
//            // Update UI with parsed data
//            totalPlacemarks = parser.placemarks.count
//            creatorEmail = parser.creatorEmail ?? "Unknown"
//            
//            // Calculate date range
//            if let earliest = parser.earliestDate, let latest = parser.latestDate {
//                let formatter = DateFormatter()
//                formatter.dateStyle = .medium
//                dateRange = "\(formatter.string(from: earliest)) to \(formatter.string(from: latest))"
//            }
//            
//            // Calculate coordinate bounds
//            if !parser.placemarks.isEmpty {
//                let lats = parser.placemarks.map { $0.latitude }
//                let lons = parser.placemarks.map { $0.longitude }
//                let alts = parser.placemarks.map { $0.altitude }
//                
//                let minLat = lats.min() ?? 0
//                let maxLat = lats.max() ?? 0
//                let minLon = lons.min() ?? 0
//                let maxLon = lons.max() ?? 0
//                let minAlt = alts.min() ?? 0
//                let maxAlt = alts.max() ?? 0
//                
//                coordinateBounds = String(format: "Lat: %.5f to %.5f\nLon: %.5f to %.5f",
//                                        minLat, maxLat, minLon, maxLon)
//                altitudeRange = String(format: "%.1fm to %.1fm", minAlt, maxAlt)
//                
//                // Show first few pin names
//                let nameList = parser.placemarks.prefix(5).map { $0.name }.joined(separator: ", ")
//                if parser.placemarks.count > 5 {
//                    placemarkNames = "\(nameList)... (\(parser.placemarks.count) total)"
//                } else {
//                    placemarkNames = nameList
//                }
//            }
//            
//            debugInfo = "Successfully parsed \(parser.placemarks.count) placemarks"
//            
//        } catch {
//            debugInfo = "Error parsing KML: \(error.localizedDescription)"
//        }
//    }
//}
//
//// Helper View for Data Rows
//struct DataRow: View {
//    let label: String
//    let value: String
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(label)
//                .font(.system(.caption, design: .monospaced))
//                .foregroundColor(.secondary)
//            Text(value)
//                .font(.system(.body, design: .monospaced))
//                .fontWeight(.medium)
//        }
//        .padding(.vertical, 4)
//    }
//}
//
//// MARK: - KML Parser
//class KMLParser2: NSObject, XMLParserDelegate {
//    var placemarks: [Placemark] = []
//    var creatorEmail: String?
//    var earliestDate: Date?
//    var latestDate: Date?
//    
//    // Current parsing state
//    private var currentElement = ""
//    private var currentName = ""
//    private var currentDescription = ""
//    private var currentCoordinates = ""
//    
//    struct Placemark {
//        let name: String
//        let description: String
//        let latitude: Double
//        let longitude: Double
//        let altitude: Double
//        let createdDate: Date?
//    }
//    
//    func parse(data: Data) {
//        let parser = XMLParser(data: data)
//        parser.delegate = self
//        parser.parse()
//    }
//    
//    // XMLParserDelegate methods
//    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
//        currentElement = elementName
//        
//        if elementName == "Placemark" {
//            currentName = ""
//            currentDescription = ""
//            currentCoordinates = ""
//        }
//    }
//    
//    func parser(_ parser: XMLParser, foundCharacters string: String) {
//        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !trimmed.isEmpty else { return }
//        
//        switch currentElement {
//        case "n":
//            currentName += trimmed
//        case "description":
//            currentDescription += trimmed
//        case "coordinates":
//            currentCoordinates += trimmed
//        default:
//            break
//        }
//    }
//    
//    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
//        if elementName == "Placemark" {
//            // Parse coordinates
//            let coords = parseCoordinates(currentCoordinates)
//            
//            // Parse date and email from description
//            let (date, email) = parseDescription(currentDescription)
//            
//            if let coords = coords {
//                let placemark = Placemark(
//                    name: currentName,
//                    description: currentDescription,
//                    latitude: coords.latitude,
//                    longitude: coords.longitude,
//                    altitude: coords.altitude,
//                    createdDate: date
//                )
//                placemarks.append(placemark)
//                
//                // Track email
//                if creatorEmail == nil, let email = email {
//                    creatorEmail = email
//                }
//                
//                // Track date range
//                if let date = date {
//                    if earliestDate == nil || date < earliestDate! {
//                        earliestDate = date
//                    }
//                    if latestDate == nil || date > latestDate! {
//                        latestDate = date
//                    }
//                }
//            }
//        }
//    }
//    
//    private func parseCoordinates(_ coordString: String) -> (longitude: Double, latitude: Double, altitude: Double)? {
//        let components = coordString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
//        guard components.count >= 2 else { return nil }
//        
//        guard let lon = Double(components[0]),
//              let lat = Double(components[1]) else { return nil }
//        
//        let alt = components.count > 2 ? (Double(components[2]) ?? 0) : 0
//        
//        return (lon, lat, alt)
//    }
//    
//    private func parseDescription(_ description: String) -> (date: Date?, email: String?) {
//        // Parse: "Created by smith.byronj@gmail.com on 2025-10-17 08:19:12"
//        var date: Date?
//        var email: String?
//        
//        // Extract email
//        if let emailRange = description.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
//            email = String(description[emailRange])
//        }
//        
//        // Extract date
//        if let dateRange = description.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, options: .regularExpression) {
//            let dateString = String(description[dateRange])
//            let formatter = DateFormatter()
//            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
//            date = formatter.date(from: dateString)
//        }
//        
//        return (date, email)
//    }
//}
//
//// MARK: - iOS Document Picker
//#if os(iOS)
//import UIKit
//
//struct DocumentPicker: UIViewControllerRepresentable {
//    let onPick: (URL) -> Void
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "kml")!])
//        picker.delegate = context.coordinator
//        picker.allowsMultipleSelection = false
//        return picker
//    }
//    
//    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(onPick: onPick)
//    }
//    
//    class Coordinator: NSObject, UIDocumentPickerDelegate {
//        let onPick: (URL) -> Void
//        
//        init(onPick: @escaping (URL) -> Void) {
//            self.onPick = onPick
//        }
//        
//        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
//            guard let url = urls.first else { return }
//            onPick(url)
//        }
//    }
//}
//#endif
//
//// Preview
//#Preview {
//    KMLViewer()
//}
import SwiftUI
import UniformTypeIdentifiers

struct KMLViewer: View {
    @State private var fileName: String = ""
    @State private var isDragging = false
    @State private var debugInfo: String = ""
    
    // Parsed KML Data
    @State private var totalPlacemarks: Int = 0
    @State private var dateRange: String = "N/A"
    @State private var creatorEmail: String = "N/A"
    @State private var coordinateBounds: String = "N/A"
    @State private var altitudeRange: String = "N/A"
    @State private var placemarkNames: String = "N/A"
    @State private var showingDocumentPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("KML Parser")
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
                    Image(systemName: fileName.isEmpty ? "map.circle" : "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(fileName.isEmpty ? .gray : .green)
                    
                    Text(fileName.isEmpty ? "Drop KML File Here" : fileName)
                        .font(.headline)
                        .foregroundColor(fileName.isEmpty ? .gray : .primary)
                    
                    if fileName.isEmpty {
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Browse Files") {
                            browseForKML()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(height: 250)
            .padding()
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
            
            // KML Data Display
            if !fileName.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        DataRow(label: "Total Pins", value: "\(totalPlacemarks)")
                        DataRow(label: "Creator", value: creatorEmail)
                        DataRow(label: "Date Range", value: dateRange)
                        DataRow(label: "Pin Names", value: placemarkNames)
                        DataRow(label: "Coordinate Bounds", value: coordinateBounds)
                        DataRow(label: "Altitude Range", value: altitudeRange)
                        
                        if !debugInfo.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                Text("Debug Info")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                
                                Text(debugInfo)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .textSelection(.enabled)
                                
                                Button("Copy Debug Info") {
                                    #if os(iOS)
                                    UIPasteboard.general.string = debugInfo
                                    #elseif os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(debugInfo, forType: .string)
                                    #endif
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
                }
            }
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in
                fileName = url.lastPathComponent
                parseKMLFileFromURL(url)
            }
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        
        var handled = false
        
        for provider in providers {
            // Try file URL first (when dragging from Finder/Files)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {return}
                        print (url.pathExtension.lowercased())
                    
                    if url.pathExtension.lowercased() == "kml" {
                        
                        DispatchQueue.main.async {
                            self.fileName = url.lastPathComponent
                            self.parseKMLFileFromURL(url)
                        }
                    } else {
                        print("Not working path Extension")
                    }
                }
                handled = true
            } else {
                print("provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) is false")
            }
        }
        
        return handled
    }
    
    func parseKMLFileFromURL(_ url: URL) {
        print(#function)
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            let parser = KMLParser2()
            parser.parse(data: data)
            updateUIWithParsedData(parser)
        } catch {
            debugInfo = "Error: \(error.localizedDescription)"
        }
    }
    
    func browseForKML() {
        print("browseForKML() called")          // 1. Did the button even fire?

        #if os(macOS)
        print("→ macOS path taken")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "kml")!.identifier]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a KML file"

        let response = panel.runModal()
        print("NSOpenPanel response: \(response == .OK ? "OK" : "Cancelled or failed")")

        guard response == .OK, let url = panel.url else {
            print("No URL selected or cancelled")
            return
        }

        print("Selected file: \(url.path) (security-scoped: \(url.startAccessingSecurityScopedResource()))")
        fileName = url.lastPathComponent
        parseKMLFileFromURL(url)

        #elseif os(iOS)
        print("→ iOS path taken – showingDocumentPicker = true")
        showingDocumentPicker = true
        #endif
    }
    
    func updateUIWithParsedData(_ parser: KMLParser2) {
        // Update UI with parsed data
        totalPlacemarks = parser.placemarks.count
        creatorEmail = parser.creatorEmail ?? "Unknown"
        
        // Calculate date range
        if let earliest = parser.earliestDate, let latest = parser.latestDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            dateRange = "\(formatter.string(from: earliest)) to \(formatter.string(from: latest))"
        }
        
        // Calculate coordinate bounds
        if !parser.placemarks.isEmpty {
            let lats = parser.placemarks.map { $0.latitude }
            let lons = parser.placemarks.map { $0.longitude }
            let alts = parser.placemarks.map { $0.altitude }
            
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0
            let minAlt = alts.min() ?? 0
            let maxAlt = alts.max() ?? 0
            
            coordinateBounds = String(format: "Lat: %.5f to %.5f\nLon: %.5f to %.5f",
                                    minLat, maxLat, minLon, maxLon)
            altitudeRange = String(format: "%.1fm to %.1fm", minAlt, maxAlt)
            
            // Show first few pin names
            let nameList = parser.placemarks.prefix(5).map { $0.name }.joined(separator: ", ")
            if parser.placemarks.count > 5 {
                placemarkNames = "\(nameList)... (\(parser.placemarks.count) total)"
            } else {
                placemarkNames = nameList
            }
        }
        
        debugInfo = "Successfully parsed \(parser.placemarks.count) placemarks"
    }
}

// Helper View for Data Rows
struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - KML Parser
class KMLParser2: NSObject, XMLParserDelegate {
    var placemarks: [Placemark] = []
    var creatorEmail: String?
    var earliestDate: Date?
    var latestDate: Date?
    
    // Current parsing state
    private var currentElement = ""
    private var currentName = ""
    private var currentDescription = ""
    private var currentCoordinates = ""
    
    struct Placemark {
        let name: String
        let description: String
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let createdDate: Date?
    }
    
    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    
    // XMLParserDelegate methods
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "Placemark" {
            currentName = ""
            currentDescription = ""
            currentCoordinates = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch currentElement {
        case "n":
            currentName += trimmed
        case "description":
            currentDescription += trimmed
        case "coordinates":
            currentCoordinates += trimmed
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Placemark" {
            // Parse coordinates
            let coords = parseCoordinates(currentCoordinates)
            
            // Parse date and email from description
            let (date, email) = parseDescription(currentDescription)
            
            if let coords = coords {
                let placemark = Placemark(
                    name: currentName,
                    description: currentDescription,
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                    altitude: coords.altitude,
                    createdDate: date
                )
                placemarks.append(placemark)
                
                // Track email
                if creatorEmail == nil, let email = email {
                    creatorEmail = email
                }
                
                // Track date range
                if let date = date {
                    if earliestDate == nil || date < earliestDate! {
                        earliestDate = date
                    }
                    if latestDate == nil || date > latestDate! {
                        latestDate = date
                    }
                }
            }
        }
    }
    
    private func parseCoordinates(_ coordString: String) -> (longitude: Double, latitude: Double, altitude: Double)? {
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
}

// MARK: - iOS Document Picker
#if os(iOS)
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "kml")!])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Security-scoped resource access handled by caller
            onPick(url)
        }
    }
}
#endif

// Preview
#Preview {
    KMLViewer()
}
