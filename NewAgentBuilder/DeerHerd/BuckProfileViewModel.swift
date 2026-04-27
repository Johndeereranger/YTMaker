//
//  BuckProfileViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//

//
//// MARK: - MapViewModel.swift
//import Foundation
//import Combine
//import CoreLocation
//import MapKit
//
//@MainActor
//class MapViewModel: ObservableObject {
//    @Published var property: Property
//    @Published var observations: [DeerObservation] = []
//    @Published var sessions: [FlightSession] = []
//    @Published var buckProfiles: [BuckProfile] = []
//    @Published var isLoading = false
//    @Published var errorMessage: String?
//    
//    // Filter states
//    @Published var displayMode: DisplayMode = .coloredPins
//    @Published var showBoundary = true
//    @Published var dateFilter: DateFilter = .allTime
//    @Published var customDateRange: DateRange?
//    @Published var timeOfDayFilter: TimeOfDayFilter = .all
//    @Published var classificationFilter: ClassificationFilter = .all
//    @Published var selectedBuckProfile: BuckProfile?
//    @Published var selectedSessionIds: Set<String> = []
//    
//    // Calculated stats
//    @Published var deerPerSquareMile: Double = 0
//    @Published var buckToDoRatio: String = "0:0"
//    @Published var visibleObservationCount: Int = 0
//    
//    // Add to @Published properties
//    @Published var isEditingBoundary = false
//    @Published var tempBoundaryVertices: [CLLocationCoordinate2D] = []
//    
//    enum DisplayMode {
//        case photoThumbnails
//        case coloredPins
//    }
//    
//    enum DateFilter: CaseIterable {
//        case today, yesterday, thisWeek, thisMonth, thisYear, allTime, custom, sessions
//        
//        var displayName: String {
//            switch self {
//            case .today: return "Today"
//            case .yesterday: return "Yesterday"
//            case .thisWeek: return "This Week"
//            case .thisMonth: return "This Month"
//            case .thisYear: return "This Year"
//            case .allTime: return "All Time"
//            case .custom: return "Custom Range"
//            case .sessions: return "Select Sessions"
//            }
//        }
//    }
//    
//    enum TimeOfDayFilter: CaseIterable {
//        case all, morning, afternoon
//        
//        var displayName: String {
//            switch self {
//            case .all: return "All Day"
//            case .morning: return "Morning"
//            case .afternoon: return "Afternoon"
//            }
//        }
//    }
//    
//    enum ClassificationFilter: CaseIterable {
//        case all, bucksOnly, doesOnly
//        
//        var displayName: String {
//            switch self {
//            case .all: return "All Deer"
//            case .bucksOnly: return "Bucks Only"
//            case .doesOnly: return "Does Only"
//            }
//        }
//    }
//    
//    struct DateRange {
//        var start: Date
//        var end: Date
//    }
//    
//    private let firebaseManager = DeerHerdFirebaseManager.shared
//    private let coordUtils = CoordinateUtilities.shared
//    
//    init(property: Property) {
//        self.property = property
//    }
//    
//    var filteredObservations: [DeerObservation] {
//        var filtered = observations
//        
//        // Date filter
//        filtered = filtered.filter { observation in
//            switch dateFilter {
//            case .today:
//                return Calendar.current.isDateInToday(observation.timestamp)
//            case .yesterday:
//                return Calendar.current.isDateInYesterday(observation.timestamp)
//            case .thisWeek:
//                let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
//                return observation.timestamp >= weekAgo
//            case .thisMonth:
//                let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
//                return observation.timestamp >= monthAgo
//            case .thisYear:
//                let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
//                return observation.timestamp >= yearAgo
//            case .allTime:
//                return true
//            case .custom:
//                if let range = customDateRange {
//                    return observation.timestamp >= range.start && observation.timestamp <= range.end
//                }
//                return true
//            case .sessions:
//                return selectedSessionIds.isEmpty || selectedSessionIds.contains(observation.sessionId)
//            }
//        }
//        
//        // Time of day filter
//        if timeOfDayFilter != .all {
//            filtered = filtered.filter { observation in
//                let hour = Calendar.current.component(.hour, from: observation.timestamp)
//                switch timeOfDayFilter {
//                case .morning:
//                    return hour < 12
//                case .afternoon:
//                    return hour >= 12
//                case .all:
//                    return true
//                }
//            }
//        }
//        
//        // Classification filter
//        switch classificationFilter {
//        case .bucksOnly:
//            filtered = filtered.filter { $0.classification.isBuck }
//        case .doesOnly:
//            filtered = filtered.filter { !$0.classification.isBuck }
//        case .all:
//            break
//        }
//        
//        // Buck profile filter
//        if let profile = selectedBuckProfile {
//            filtered = filtered.filter { $0.buckProfileId == profile.id }
//        }
//        
//        return filtered
//    }
//    
//    func loadData() async {
//        isLoading = true
//        errorMessage = nil
//        
//        do {
//            // Load observations
//            observations = try await firebaseManager.fetchObservations(for: property.id)
//            
//            // Load sessions
//            sessions = try await firebaseManager.fetchFlightSessions(for: property.id)
//            
//            // Load buck profiles
//            buckProfiles = try await firebaseManager.fetchBuckProfiles(for: property.id)
//            
//            // Calculate stats
//            calculateStats()
//            
//            print("✅ Loaded \(observations.count) observations, \(sessions.count) sessions")
//        } catch {
//            errorMessage = "Failed to load data: \(error.localizedDescription)"
//            print("❌ Error loading map data: \(error)")
//        }
//        
//        isLoading = false
//    }
//    
//    func calculateStats() {
//        let filtered = filteredObservations
//        visibleObservationCount = filtered.count
//        
//        // Calculate area
//        var area: Double = 0
//        if let boundary = property.boundaryKML {
//            area = boundary.calculatedAcres / 640.0 // Convert to square miles
//        } else if !filtered.isEmpty {
//            // Use convex hull of observation points
//            let coords = filtered.map { $0.coordinate }
//            let acres = coordUtils.calculateConvexHullArea(of: coords)
//            area = acres / 640.0
//        }
//        
//        // Deer per square mile
//        if area > 0 {
//            deerPerSquareMile = Double(filtered.count) / area
//        } else {
//            deerPerSquareMile = 0
//        }
//        
//        // Buck:Doe ratio
//        let bucks = filtered.filter { $0.classification.isBuck }.count
//        let does = filtered.filter { !$0.classification.isBuck }.count
//        
//        if does > 0 {
//            let ratio = Double(bucks) / Double(does)
//            buckToDoRatio = String(format: "%.1f:1", ratio)
//        } else if bucks > 0 {
//            buckToDoRatio = "\(bucks):0"
//        } else {
//            buckToDoRatio = "0:0"
//        }
//    }
//    
//    func deleteObservation(_ observation: DeerObservation) async {
//        do {
//            try await firebaseManager.deleteObservation(observation.id)
//            await loadData()
//            print("✅ Deleted observation")
//        } catch {
//            errorMessage = "Failed to delete observation: \(error.localizedDescription)"
//        }
//    }
//    
//    func updateObservation(_ observation: DeerObservation) async {
//        do {
//            try await firebaseManager.updateObservation(observation)
//            await loadData()
//            print("✅ Updated observation")
//        } catch {
//            errorMessage = "Failed to update observation: \(error.localizedDescription)"
//        }
//    }
//    
//    func getObservationsNear(location: CLLocationCoordinate2D, within meters: Double = 10) -> [DeerObservation] {
//        return observations.filter { obs in
//            coordUtils.distance(from: location, to: obs.coordinate) <= meters
//        }
//    }
//    
//    // Add these methods
//    func startEditingBoundary() {
//        tempBoundaryVertices = property.boundaryKML?.coordinates ?? []
//        isEditingBoundary = true
//    }
//
//    func addBoundaryVertex(at coordinate: CLLocationCoordinate2D) {
//        tempBoundaryVertices.append(coordinate)
//    }
//
//    func saveBoundary() async {
//        let acres = 3.0// coordUtils.calculatePolygonArea(coordinates: tempBoundaryVertices)
//        property.boundaryKML = PropertyBoundary(coordinates: tempBoundaryVertices, calculatedAcres: acres)
//        try? await firebaseManager.updateProperty(property)
//        isEditingBoundary = false
//        calculateStats()
//    }
//
//    func cancelBoundaryEdit() {
//        tempBoundaryVertices.removeAll()
//        isEditingBoundary = false
//    }
//}

// MARK: - BuckProfileViewModel.swift
import Foundation
import Combine

@MainActor
class BuckProfileViewModel: ObservableObject {
    @Published var property: Property
    @Published var buckProfiles: [BuckProfile] = []
    @Published var observations: [DeerObservation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    
    init(property: Property) {
        self.property = property
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            buckProfiles = try await firebaseManager.fetchBuckProfiles(for: property.id)
            observations = try await firebaseManager.fetchObservations(for: property.id)
            print("✅ Loaded \(buckProfiles.count) buck profiles")
        } catch {
            errorMessage = "Failed to load buck profiles: \(error.localizedDescription)"
            print("❌ Error loading buck profiles: \(error)")
        }
        
        isLoading = false
    }
    
    func createBuckProfile(name: String, ageEstimate: String?, status: BuckProfile.BuckStatus, notes: String?) async {
        let profile = BuckProfile(
            propertyId: property.id,
            name: name,
            ageEstimate: ageEstimate,
            status: status,
            notes: notes
        )
        
        do {
            try await firebaseManager.createBuckProfile(profile)
            await loadData()
            print("✅ Created buck profile: \(name)")
        } catch {
            errorMessage = "Failed to create buck profile: \(error.localizedDescription)"
            print("❌ Error creating buck profile: \(error)")
        }
    }
    
    func updateBuckProfile(_ profile: BuckProfile) async {
        do {
            try await firebaseManager.updateBuckProfile(profile)
            await loadData()
            print("✅ Updated buck profile: \(profile.name)")
        } catch {
            errorMessage = "Failed to update buck profile: \(error.localizedDescription)"
        }
    }
    
    func deleteBuckProfile(_ profile: BuckProfile) async {
        do {
            try await firebaseManager.deleteBuckProfile(profile.id)
            await loadData()
            print("✅ Deleted buck profile: \(profile.name)")
        } catch {
            errorMessage = "Failed to delete buck profile: \(error.localizedDescription)"
        }
    }
    
    func linkObservation(_ observationId: String, to profile: BuckProfile) async {
        var updated = profile
        if !updated.linkedObservationIds.contains(observationId) {
            updated.linkedObservationIds.append(observationId)
            
            // Update first/last seen dates
            if let obs = observations.first(where: { $0.id == observationId }) {
                if updated.firstSeenDate == nil || obs.timestamp < updated.firstSeenDate! {
                    updated.firstSeenDate = obs.timestamp
                }
                if updated.lastSeenDate == nil || obs.timestamp > updated.lastSeenDate! {
                    updated.lastSeenDate = obs.timestamp
                }
            }
            
            await updateBuckProfile(updated)
            
            // Update observation with buckProfileId
            if var obs = observations.first(where: { $0.id == observationId }) {
                obs.buckProfileId = profile.id
                try? await firebaseManager.updateObservation(obs)
            }
        }
    }
    
    func unlinkObservation(_ observationId: String, from profile: BuckProfile) async {
        var updated = profile
        updated.linkedObservationIds.removeAll { $0 == observationId }
        
        // Recalculate first/last seen dates
        let linkedObs = observations.filter { updated.linkedObservationIds.contains($0.id) }
        updated.firstSeenDate = linkedObs.map { $0.timestamp }.min()
        updated.lastSeenDate = linkedObs.map { $0.timestamp }.max()
        
        await updateBuckProfile(updated)
        
        // Remove buckProfileId from observation
        if var obs = observations.first(where: { $0.id == observationId }) {
            obs.buckProfileId = nil
            try? await firebaseManager.updateObservation(obs)
        }
    }
    
    func getObservations(for profile: BuckProfile) -> [DeerObservation] {
        return observations.filter { profile.linkedObservationIds.contains($0.id) }
    }
    
    func getUnassignedBuckObservations() -> [DeerObservation] {
        return observations.filter { $0.classification.isBuck && $0.buckProfileId == nil }
    }
}

// MARK: - ReportViewModel.swift
import Foundation
import PDFKit

@MainActor
class ReportViewModel: ObservableObject {
    @Published var property: Property
    @Published var observations: [DeerObservation] = []
    @Published var buckProfiles: [BuckProfile] = []
    @Published var sessions: [FlightSession] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var generatedPDFURL: URL?
    
    var dateRange: MapViewModel.DateRange?
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    private let coordUtils = CoordinateUtilities.shared
    
    init(property: Property, dateRange: MapViewModel.DateRange? = nil) {
        self.property = property
        self.dateRange = dateRange
    }
    
    func loadData() async {
        do {
            observations = try await firebaseManager.fetchObservations(for: property.id)
            buckProfiles = try await firebaseManager.fetchBuckProfiles(for: property.id)
            sessions = try await firebaseManager.fetchFlightSessions(for: property.id)
            
            // Filter by date range if set
            if let range = dateRange {
                observations = observations.filter { obs in
                    obs.timestamp >= range.start && obs.timestamp <= range.end
                }
            }
            
            print("✅ Loaded report data: \(observations.count) observations, \(buckProfiles.count) profiles")
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
    
    func generateReport() async -> URL? {
        isGenerating = true
        
        await loadData()
        
        // Create PDF
        let pdfMetaData = [
            kCGPDFContextCreator: "Deer Herd Analysis",
            kCGPDFContextTitle: "\(property.name) Report"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // 8.5" x 11"
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            // Page 1: Summary
            context.beginPage()
            drawSummaryPage(in: pageRect)
            
            // Page 2+: Buck Profiles
            for profile in buckProfiles {
                if !profile.linkedObservationIds.isEmpty {
                    context.beginPage()
                    drawBuckProfilePage(profile, in: pageRect)
                }
            }
            
            // Last page: Unassigned bucks
            let unassignedBucks = observations.filter { $0.classification.isBuck && $0.buckProfileId == nil }
            if !unassignedBucks.isEmpty {
                context.beginPage()
                drawUnassignedBucksPage(unassignedBucks, in: pageRect)
            }
        }
        
        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(property.name)_Report_\(Date().timeIntervalSince1970).pdf")
        
        do {
            try data.write(to: tempURL)
            generatedPDFURL = tempURL
            print("✅ Generated PDF report at: \(tempURL)")
        } catch {
            errorMessage = "Failed to save PDF: \(error.localizedDescription)"
            print("❌ Error saving PDF: \(error)")
        }
        
        isGenerating = false
        return generatedPDFURL
    }
    
    private func drawSummaryPage(in rect: CGRect) {
        var yOffset: CGFloat = 50
        
        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24)
        ]
        let title = "\(property.name) Deer Herd Analysis"
        title.draw(at: CGPoint(x: 50, y: yOffset), withAttributes: titleAttributes)
        yOffset += 40
        
        // Property info
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12)
        ]
        
        "State: \(property.state)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        yOffset += 20
        
        if let range = dateRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            "Date Range: \(formatter.string(from: range.start)) - \(formatter.string(from: range.end))".draw(
                at: CGPoint(x: 50, y: yOffset),
                withAttributes: bodyAttributes
            )
        } else {
            "Date Range: All Time".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        }
        yOffset += 20
        
        "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
        yOffset += 40
        
        // Stats
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16)
        ]
        
        "Summary Statistics".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: headerAttributes)
        yOffset += 30
        
        // Calculate stats
        let totalDeer = observations.count
        let bucks = observations.filter { $0.classification.isBuck }.count
        let does = observations.filter { !$0.classification.isBuck }.count
        
        var area: Double = 0
        if let boundary = property.boundaryKML {
            area = boundary.calculatedAcres / 640.0
        } else if !observations.isEmpty {
            let coords = observations.map { $0.coordinate }
            let acres = coordUtils.calculateConvexHullArea(of: coords)
            area = acres / 640.0
        }
        
        let deerPerSqMi = area > 0 ? Double(totalDeer) / area : 0
        let buckDoRatio = does > 0 ? Double(bucks) / Double(does) : 0
        
        if let acres = property.totalAcres {
            "Total Acres: \(String(format: "%.1f", acres))".draw(
                at: CGPoint(x: 50, y: yOffset),
                withAttributes: bodyAttributes
            )
            yOffset += 20
        }
        
        "Total Observations: \(totalDeer)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        yOffset += 20
        
        "Bucks: \(bucks) | Does: \(does)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        yOffset += 20
        
        "Buck:Doe Ratio: \(String(format: "%.1f:1", buckDoRatio))".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
        yOffset += 20
        
        "Deer per Square Mile: \(String(format: "%.1f", deerPerSqMi))".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
        yOffset += 40
        
        // Buck profiles summary
        "Buck Profiles: \(buckProfiles.count)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: headerAttributes)
        yOffset += 30
        
        for profile in buckProfiles.prefix(10) {
            let obsCount = profile.linkedObservationIds.count
            let statusEmoji = profile.status == .live ? "🟢" : profile.status == .harvested ? "🔴" : "⚪️"
            let line = "\(statusEmoji) \(profile.name) - Age: \(profile.ageEstimate ?? "Unknown") - Observations: \(obsCount)"
            line.draw(at: CGPoint(x: 70, y: yOffset), withAttributes: bodyAttributes)
            yOffset += 18
        }
        
        // Note about map
        yOffset += 20
        "(Map visualization would be rendered here)".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
    }
    
    private func drawBuckProfilePage(_ profile: BuckProfile, in rect: CGRect) {
        var yOffset: CGFloat = 50
        
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12)
        ]
        
        // Buck name
        profile.name.draw(at: CGPoint(x: 50, y: yOffset), withAttributes: titleAttributes)
        yOffset += 35
        
        // Details
        "Age Estimate: \(profile.ageEstimate ?? "Unknown")".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
        yOffset += 20
        
        "Status: \(profile.status.rawValue)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        yOffset += 20
        
        if let first = profile.firstSeenDate {
            "First Seen: \(DateFormatter.localizedString(from: first, dateStyle: .medium, timeStyle: .none))".draw(
                at: CGPoint(x: 50, y: yOffset),
                withAttributes: bodyAttributes
            )
            yOffset += 20
        }
        
        if let last = profile.lastSeenDate {
            "Last Seen: \(DateFormatter.localizedString(from: last, dateStyle: .medium, timeStyle: .none))".draw(
                at: CGPoint(x: 50, y: yOffset),
                withAttributes: bodyAttributes
            )
            yOffset += 20
        }
        
        "Total Observations: \(profile.linkedObservationIds.count)".draw(
            at: CGPoint(x: 50, y: yOffset),
            withAttributes: bodyAttributes
        )
        yOffset += 30
        
        if let notes = profile.notes, !notes.isEmpty {
            "Notes: \(notes)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
            yOffset += 30
        }
        
        // Photos section
        "(Photos would be rendered here)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
    }
    
    private func drawUnassignedBucksPage(_ bucks: [DeerObservation], in rect: CGRect) {
        var yOffset: CGFloat = 50
        
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12)
        ]
        
        "Unidentified Bucks".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: titleAttributes)
        yOffset += 35
        
        "Total: \(bucks.count)".draw(at: CGPoint(x: 50, y: yOffset), withAttributes: bodyAttributes)
        yOffset += 30
        
        for (index, buck) in bucks.enumerated().prefix(20) {
            "Buck #\(index + 1) - \(buck.classification.rawValue) - \(DateFormatter.localizedString(from: buck.timestamp, dateStyle: .short, timeStyle: .short))".draw(
                at: CGPoint(x: 50, y: yOffset),
                withAttributes: bodyAttributes
            )
            yOffset += 20
        }
    }
}

// MARK: - DeerSettingsViewModel.swift
import Foundation

@MainActor
class DeerSettingsViewModel: ObservableObject {
    @Published var defaultColorMappings: [String: DeerClassification] = [:]
    @Published var autoMatchDistance: Double = 10.0 // feet
    
    private let defaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        // Load default color mappings
        let colors = ["red", "blue", "yellow", "green", "purple"]
        for color in colors {
            if let saved = defaults.string(forKey: "colorMapping_\(color)"),
               let classification = DeerClassification(rawValue: saved) {
                defaultColorMappings[color] = classification
            } else {
                // Set defaults
                switch color {
                case "red": defaultColorMappings[color] = .buck
                case "blue": defaultColorMappings[color] = .doe
                case "yellow": defaultColorMappings[color] = .beddedBuck
                case "green": defaultColorMappings[color] = .beddedDoe
                case "purple": defaultColorMappings[color] = .matureBuck
                default: defaultColorMappings[color] = .buck
                }
            }
        }
        
        // Load auto-match distance
        if defaults.object(forKey: "autoMatchDistance") != nil {
            autoMatchDistance = defaults.double(forKey: "autoMatchDistance")
        }
    }
    
    func saveSettings() {
        // Save color mappings
        for (color, classification) in defaultColorMappings {
            defaults.set(classification.rawValue, forKey: "colorMapping_\(color)")
        }
        
        // Save auto-match distance
        defaults.set(autoMatchDistance, forKey: "autoMatchDistance")
        
        print("✅ Saved settings")
    }
    
    func updateColorMapping(_ color: String, to classification: DeerClassification) {
        defaultColorMappings[color] = classification
    }
}
