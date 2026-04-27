//
//  MapViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/2/25.
//


// MARK: - MapViewModel.swift (Updated for Pin Management)
import Foundation
import MapKit
import SwiftUI

@MainActor
class MapViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var surveyedAreas: [SurveyedArea] = []
    @Published var selectedAreaMethod: SurveyedArea.CalculationMethod = .convexHull
    @Published var showSurveyBoundary = false
    @Published var currentSurveyedArea: SurveyedArea?
    // Data
    @Published var property: Property?
    @Published var kmlPins: [KMLPin] = []
    @Published var observations: [DeerObservation] = []
    @Published var sessions: [FlightSession] = []
    @Published var buckProfiles: [BuckProfile] = []
    
    // Filters
    @Published var pinFilter: PinFilter = .session("")
    @Published var dateFilter: DateFilter = .allTime
    @Published var timeOfDayFilter: TimeOfDayFilter = .all
    @Published var classificationFilter: ClassificationFilter = .all
    @Published var selectedBuckProfile: BuckProfile?
    @Published var showBoundary = true
    
    // Display
    @Published var displayMode: DisplayMode = .coloredPins
    @Published var isEditingBoundary = false
    
    // State
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Session selection for multi-session filter
    @Published var selectedSessionIds: Set<String> = []
    @Published var customDateRange: DateRange?
    
    // Stats
    @Published var visibleObservationCount = 0
    @Published var deerPerSquareMile: Double = 0
    @Published var buckToDoRatio = "0:0"
    
    @Published var selectedColors: Set<String> = []
    @Published var matchStatusFilter: MatchStatusFilter = .all
    
    @Published var showNearbyUnassignedPins = false
    @Published var showNearbyUnknownDeer = false
    private let nearbyRadius: Double = 1609.0
    
    @Published var contentTypeFilter: ContentTypeFilter = .all
    @Published var showUnassignedPins: Bool = false
    @Published var showUnknownDeer: Bool = false
    @Published var selectedDates: Set<Date> = []
    
    @Published var timeRangeFilter: TimeRangeFilter = .allDay
    @Published var customStartHour: Int = 0
    @Published var customEndHour: Int = 23
    
    @Published var calculationFilter: CalculationFilter = .all

    enum MatchStatusFilter: String, CaseIterable {
        case all = "All Pins"
        case matched = "Has Photos"
        case unmatched = "No Photos"
    }
    
    
    // MARK: - Enums
    
    enum ContentTypeFilter: String, CaseIterable {
        case all = "All"
        case pinsOnly = "Pins Only"
        case observationsOnly = "Observations Only"
    }
    
    enum PinFilter: Equatable {
        case session(String)        // Show pins from specific session
        case unassigned            // Show all pins with propertyId = nil
        case property(String)      // Show pins for specific property
        case all                   // Show all pins
        
        var displayName: String {
            switch self {
            case .session: return "Just Imported"
            case .unassigned: return "Unassigned"
            case .property: return "Property Pins"
            case .all: return "All Pins"
            }
        }
    }
    enum CalculationFilter: String, CaseIterable {
        case all = "All"
        case includedOnly = "Included Only"
        case excludedOnly = "Excluded Only"
    }
    
    enum DisplayMode {
        case photoThumbnails
        case coloredPins
    }
    
    enum DateFilter: CaseIterable {
        case allTime
        case today
        case last7Days
        case last30Days
        case thisYear
        case custom
        case sessions
        
        var displayName: String {
            switch self {
            case .allTime: return "All Time"
            case .today: return "Today"
            case .last7Days: return "Last 7 Days"
            case .last30Days: return "Last 30 Days"
            case .thisYear: return "This Year"
            case .custom: return "Custom"
            case .sessions: return "Sessions"
            }
        }
    }
    
    enum TimeOfDayFilter: CaseIterable {
        case all, morning, afternoon, evening
        
        var displayName: String {
            switch self {
            case .all: return "All Day"
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .evening: return "Evening"
            }
        }
    }
    
    enum ClassificationFilter: CaseIterable {
        case all, bucks, does, bedded
        
        var displayName: String {
            switch self {
            case .all: return "All"
            case .bucks: return "Bucks"
            case .does: return "Does"
            case .bedded: return "Bedded"
            }
        }
    }
    
    struct DateRange {
        let start: Date
        let end: Date
    }
    
    // MARK: - Dependencies
    
    private let firebaseManager = DeerHerdFirebaseManager.shared
    
    // MARK: - Init
    
    init(property: Property? = nil, sessionId: String? = nil) {
        self.property = property
        
        if let sessionId = sessionId {
            print("Init in MapViewModel with sessionId")
            // Session view: just show imported pins
            self.pinFilter = .session(sessionId)
            
        } else if let property = property {
            print("Init in MapViewModel with property")
            // Property view: show property + nearby context
            self.pinFilter = .property(property.id)
            self.showNearbyUnassignedPins = true  // ← ADD THIS
            self.showNearbyUnknownDeer = true     // ← ADD THIS
            
        } else {
            print("Init in MapViewModel with NO PARAMS")
            // All pins view: show everything
            self.pinFilter = .unassigned
        }
    }
    
    // MARK: - Computed Properties
  //MARK: - FILTERED PINS

    var filteredPins: [KMLPin] {
        // HIDE PINS if observations-only mode
        guard contentTypeFilter != .observationsOnly else {
            return []
        }
        
        // START: Maximum set of pins
        var pins = kmlPins
        
        // FILTER 1: Property Assignment
        if let property = property {
            // In property view: start with property pins only
            pins = pins.filter { $0.propertyId == property.id }
        } else {
            // In non-property view: apply pinFilter
            switch pinFilter {
            case .session(let sessionId):
                pins = pins.filter { $0.sessionId == sessionId }
            case .unassigned:
                pins = pins.filter { $0.propertyId == nil }
            case .property(let propertyId):
                pins = pins.filter { $0.propertyId == propertyId }
            case .all:
                break // Keep all pins
            }
        }
        
        // FILTER 2: Add Nearby Unassigned (expansion, not reduction)
        if showNearbyUnassignedPins, let property = property, let center = propertyCenter {
            let nearbyUnassigned = kmlPins.filter { pin in
                guard pin.propertyId == nil else { return false }
                let distance = CoordinateUtilities.shared.distance(from: center, to: pin.coordinate)
                return distance <= nearbyRadius
            }
            pins.append(contentsOf: nearbyUnassigned)
        }
        
        // FILTER 3: Unassigned Pins Toggle
        if showUnassignedPins {
            // If toggle is ON, ONLY show unassigned pins
            pins = pins.filter { $0.propertyId == nil }
        }
        
        // FILTER 4: Match Status (are pins matched to photos?)
        if let property = property {
            // In property view: NEVER show matched pins (they appear as observations)
            pins = pins.filter { $0.matchedPhotoIds.isEmpty }
        } else {
            // In non-property view: respect the matchStatusFilter toggle
            switch matchStatusFilter {
            case .all:
                break // Keep all
            case .matched:
                pins = pins.filter { !$0.matchedPhotoIds.isEmpty }
            case .unmatched:
                pins = pins.filter { $0.matchedPhotoIds.isEmpty }
            }
        }
        
        // FILTER 5: Color Filter
        if !selectedColors.isEmpty {
            pins = pins.filter { selectedColors.contains($0.color) }
        }
        
        switch calculationFilter {
        case .all:
            break // Keep all
        case .includedOnly:
            pins = pins.filter { $0.isIncludedInCalculations }
        case .excludedOnly:
            pins = pins.filter { !$0.isIncludedInCalculations }
        }
        
        // FILTER 6: Date Filter
        pins = applyDateFilter(to: pins)
        
        // FILTER 7: Time of Day Filter (NEW)
        pins = applyTimeOfDayFilterToPins(pins)
        
        return pins
    }
    var filteredObservations: [DeerObservation] {
        // HIDE OBSERVATIONS if pins-only mode
        guard contentTypeFilter != .pinsOnly else {
            return []
        }
        
        var obs = observations
        
        // PROPERTY VIEW SPECIAL LOGIC
        if let property = property {
            // Start with property observations (exclude unknown by default)
            obs = obs.filter {
                $0.propertyId == property.id && $0.classification != .unknown
            }
            
            // Optionally add nearby unknown deer
            if showNearbyUnknownDeer, let center = propertyCenter {
                let nearbyUnknown = observations.filter { observation in
                    guard observation.classification == .unknown else { return false }
                    let obsCoord = CLLocationCoordinate2D(latitude: observation.gpsLat, longitude: observation.gpsLon)
                    let distance = CoordinateUtilities.shared.distance(from: center, to: obsCoord)
                    return distance <= nearbyRadius
                }
                obs.append(contentsOf: nearbyUnknown)
            }
        }
        // NON-PROPERTY VIEW: No special filtering needed, use all observations
        
        // FILTER: Unknown Deer Toggle
        if showUnknownDeer {
            // If toggle is ON, ONLY show unknown deer (color = "black" or classification = .unknown)
            obs = obs.filter { observation in
                observation.color == "black" || observation.classification == .unknown
            }
        }
        
        // FILTER: Color Filter (applies to observations too)
        if !selectedColors.isEmpty {
            obs = obs.filter { selectedColors.contains($0.color) }
        }
        
        // Apply date filter (all views)
        obs = applyDateFilter(to: obs)
        
        // Apply time of day (all views)
        obs = applyTimeOfDayFilter(to: obs)
        
        switch calculationFilter {
        case .all:
            break
        case .includedOnly:
            obs = obs.filter { $0.isIncludedInCalculations }
        case .excludedOnly:
            obs = obs.filter { !$0.isIncludedInCalculations }
        }
        
        // Buck profile (all views)
        if let profile = selectedBuckProfile {
            obs = obs.filter { $0.buckProfileId == profile.id }
        }
        
        return obs
    }

    var filteredObservationsPrev: [DeerObservation] {
        var obs = observations
        
        // PROPERTY VIEW SPECIAL LOGIC
        if let property = property {
            // Start with property observations (exclude unknown by default)
            obs = obs.filter {
                $0.propertyId == property.id && $0.classification != .unknown
            }
            
            // Optionally add nearby unknown deer
            if showNearbyUnknownDeer, let center = propertyCenter {
                let nearbyUnknown = observations.filter { observation in
                    guard observation.classification == .unknown else { return false }
                    let obsCoord = CLLocationCoordinate2D(latitude: observation.gpsLat, longitude: observation.gpsLon)
                    let distance = CoordinateUtilities.shared.distance(from: center, to: obsCoord)
                    return distance <= nearbyRadius
                }
                obs.append(contentsOf: nearbyUnknown)
            }
        }
        // NON-PROPERTY VIEW: No special filtering needed, use all observations
        
        // Apply date filter (all views)
        obs = applyDateFilter(to: obs)
        
        // Apply time of day (all views)
        obs = applyTimeOfDayFilter(to: obs)
        
        // Buck profile (all views)
        if let profile = selectedBuckProfile {
            obs = obs.filter { $0.buckProfileId == profile.id }
        }
        
        return obs
    }
    // MARK: - Data Loading
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            kmlPins = try await firebaseManager.fetchAllKMLPins()
            print("✅ Loaded \(kmlPins.count) total pins")
            
            // Load observations if we have a property
            if let property = property {
                
                observations = try await firebaseManager.fetchObservations(for: property.id)
                sessions = try await firebaseManager.fetchFlightSessions(for: property.id)
                buckProfiles = try await firebaseManager.fetchBuckProfiles(for: property.id)
                print("✅ Loaded \(observations.count) observations, \(sessions.count) sessions")
            }
            
            calculateStats()
            calculateAllSurveyedAreas()
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to load data: \(error)")
        }
        
        isLoading = false
    }
    
    private func fetchAllUnassignedPins() async throws -> [KMLPin] {
        return try await firebaseManager.fetchAllUnassignedPins()
    }
    
    // MARK: - Filters
    
    private func applyDateFilter<T>(to items: [T]) -> [T] where T: HasTimestamp {
        switch dateFilter {
        case .allTime:
            return items
            
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return items.filter { $0.timestamp >= start }
            
        case .last7Days:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return items.filter { $0.timestamp >= start }
            
        case .last30Days:
            let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return items.filter { $0.timestamp >= start }
            
        case .thisYear:
            let start = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date())))!
            return items.filter { $0.timestamp >= start }
            
        case .custom:
            guard let range = customDateRange else { return items }
            return items.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
            
        case .sessions:
            guard !selectedSessionIds.isEmpty else { return items }
            if let obs = items as? [DeerObservation] {
                return obs.filter { selectedSessionIds.contains($0.sessionId) } as! [T]
            }
            if let pins = items as? [KMLPin] {
                return pins.filter { pin in
                    guard let sessionId = pin.sessionId else { return false }
                    return selectedSessionIds.contains(sessionId)
                } as! [T]
            }
            return items
        }
    }

    
//    private func applyClassificationFilter(to observations: [DeerObservation]) -> [DeerObservation] {
//        switch classificationFilter {
//        case .all:
//            return observations
//        case .bucks:
//            return observations.filter { $0.classification.isBuck }
//        case .does:
//            return observations.filter { !$0.classification.isBuck && !$0.classification.isBedded }
//        case .bedded:
//            return observations.filter { $0.classification.isBedded }
//        }
//    }
    
    // MARK: - Stats
    
    func calculateStats() {
        let includedObservations = filteredObservations.filter { $0.isIncludedInCalculations }
           visibleObservationCount = includedObservations.count
        
        // Calculate density
        if let property = property, let acres = property.totalAcres, acres > 0 {
            let squareMiles = acres / 640.0
            deerPerSquareMile = Double(visibleObservationCount) / squareMiles
        }
        
        // Calculate buck:doe ratio
        let bucks = filteredObservations.filter { $0.classification.isBuck }.count
        let does = filteredObservations.filter { !$0.classification.isBuck }.count
        buckToDoRatio = "\(bucks):\(does)"
    }
    
    // MARK: - Pin Actions
    
    func deletePin(_ pin: KMLPin) async {
        do {
            try await firebaseManager.deleteKMLPin(pin.id)
            kmlPins.removeAll { $0.id == pin.id }
            print("✅ Deleted pin: \(pin.name)")
        } catch {
            errorMessage = "Failed to delete pin: \(error.localizedDescription)"
            print("❌ Failed to delete pin: \(error)")
        }
    }
    
    func assignPinToProperty(_ pin: KMLPin, property: Property) async {
        var updated = pin
        updated.propertyId = property.id
        
        do {
            try await firebaseManager.updateKMLPin(updated)
            
            // Update local array
            if let index = kmlPins.firstIndex(where: { $0.id == pin.id }) {
                kmlPins[index] = updated
            }
            
            print("✅ Assigned pin to property: \(property.name)")
        } catch {
            errorMessage = "Failed to assign pin: \(error.localizedDescription)"
            print("❌ Failed to assign pin: \(error)")
        }
    }
    
    var propertyCenter: CLLocationCoordinate2D? {
        guard let property = property else {
            print("🎯 propertyCenter: No property")
            return nil
        }
        
        // Option 1: Use boundary center
        if let boundary = property.boundaryKML, !boundary.coordinates.isEmpty {
            let center = boundary.coordinates[boundary.coordinates.count / 2]
            print("🎯 propertyCenter: Using boundary center: \(center)")
            return center
        }
        
        // Option 2: Use center of property pins
        let propertyPins = kmlPins.filter { $0.propertyId == property.id }
        print("🎯 propertyCenter: Found \(propertyPins.count) property pins (out of \(kmlPins.count) total)")
        if !propertyPins.isEmpty {
            let avgLat = propertyPins.map { $0.coordinate.latitude }.reduce(0, +) / Double(propertyPins.count)
            let avgLon = propertyPins.map { $0.coordinate.longitude }.reduce(0, +) / Double(propertyPins.count)
            let center = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            print("🎯 propertyCenter: Using pins center: \(center)")
            return center
        }
        
        // Option 3: Use center of property observations
        let propertyObs = observations.filter { $0.propertyId == property.id }
        print("🎯 propertyCenter: Found \(propertyObs.count) property observations (out of \(observations.count) total)")
        if !propertyObs.isEmpty {
            let avgLat = propertyObs.map { $0.gpsLat }.reduce(0, +) / Double(propertyObs.count)
            let avgLon = propertyObs.map { $0.gpsLon }.reduce(0, +) / Double(propertyObs.count)
            let center = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            print("🎯 propertyCenter: Using observations center: \(center)")
            return center
        }
        
        print("🎯 propertyCenter: No boundary, no pins, no observations - returning nil")
        return nil
    }
    
    // MARK: - Observation Actions (Keep existing methods)
    
    func updateObservation(_ observation: DeerObservation) async {
        do {
            try await firebaseManager.updateObservation(observation)
            if let index = observations.firstIndex(where: { $0.id == observation.id }) {
                    var updatedObservations = observations
                    updatedObservations[index] = observation
                    observations = updatedObservations  // Reassign entire array
                }
            calculateStats()
        } catch {
            errorMessage = "Failed to update observation: \(error.localizedDescription)"
        }
    }
    
    func deleteObservation(_ observation: DeerObservation) async {
        do {
            try await firebaseManager.deleteObservation(observation.id)
            //observations.removeAll { $0.id == observation.id }
            observations = observations.filter { $0.id != observation.id }
            calculateStats()
        } catch {
            errorMessage = "Failed to delete observation: \(error.localizedDescription)"
        }
    }
    
    func getObservationsNear(location: CLLocationCoordinate2D, within meters: Double) -> [DeerObservation] {
        observations.filter { observation in
            let distance = CoordinateUtilities.shared.distance(
                from: location,
                to: observation.coordinate
            )
            return distance <= meters
        }
    }
    
    // MARK: - Boundary Editing
    
    func startEditingBoundary() {
        isEditingBoundary = true
    }
    
    func cancelBoundaryEdit() {
        isEditingBoundary = false
    }
    
    func addBoundaryVertex(at coordinate: CLLocationCoordinate2D) {
        // TODO: Implement boundary editing
    }
    
    func saveBoundary() async {
        // TODO: Implement boundary saving
        isEditingBoundary = false
    }
    
    private func applyTimeOfDayFilterToPins(_ pins: [KMLPin]) -> [KMLPin] {
        // If allDay, return everything
        guard timeRangeFilter != .allDay else {
            return pins
        }
        
        // Get the hour range
        let (startHour, endHour) = timeRangeFilter == .custom
            ? (customStartHour, customEndHour)
            : timeRangeFilter.timeRange!
        
        return pins.filter { pin in
            let hour = Calendar.current.component(.hour, from: pin.createdDate)
            
            // Handle ranges that don't wrap midnight
            if startHour <= endHour {
                return hour >= startHour && hour <= endHour
            } else {
                // Handle overnight range (e.g., 22-5)
                return hour >= startHour || hour <= endHour
            }
        }
    }
    private func applyTimeOfDayFilter(to observations: [DeerObservation]) -> [DeerObservation] {
        // If allDay, return everything
        guard timeRangeFilter != .allDay else {
            return observations
        }
        
        // Get the hour range
        let (startHour, endHour) = timeRangeFilter == .custom
            ? (customStartHour, customEndHour)
            : timeRangeFilter.timeRange!
        
        return observations.filter { observation in
            let hour = Calendar.current.component(.hour, from: observation.timestamp)
            
            // Handle ranges that don't wrap midnight
            if startHour <= endHour {
                return hour >= startHour && hour <= endHour
            } else {
                // Handle overnight range (e.g., 22-5)
                return hour >= startHour || hour <= endHour
            }
        }
    }
    
    func togglePinCalculationStatus(_ pin: KMLPin) async {
        var updated = pin
        updated.isIncludedInCalculations.toggle()
        
        do {
            try await firebaseManager.updateKMLPin(updated)
            if let index = kmlPins.firstIndex(where: { $0.id == pin.id }) {
                kmlPins[index] = updated
            }
            calculateStats()
            calculateAllSurveyedAreas()
            print("✅ Toggled pin calculation status: \(updated.isIncludedInCalculations)")
        } catch {
            errorMessage = "Failed to update pin: \(error.localizedDescription)"
        }
    }

    func toggleObservationCalculationStatus(_ observation: DeerObservation) async {
        var updated = observation
        updated.isIncludedInCalculations.toggle()
        
        do {
            try await firebaseManager.updateObservation(updated)
            if let index = observations.firstIndex(where: { $0.id == observation.id }) {
                observations[index] = updated
            }
            calculateStats()
            calculateAllSurveyedAreas()
            print("✅ Toggled observation calculation status: \(updated.isIncludedInCalculations)")
        } catch {
            errorMessage = "Failed to update observation: \(error.localizedDescription)"
        }
    }
    
    
    // Helper to get unique colors from loaded pins
    var availableColors: [String] {
        var colors = Set<String>()
        
        // Add pin colors
        colors.formUnion(kmlPins.map { $0.color })
        
        // Add observation colors (NEW)
        colors.formUnion(observations.map { $0.color }.filter { $0 != "black" })
        
        return Array(colors).sorted()
    }

    // Helper to count active filters
    var activeFilterCount: Int {
        var count = 0
        if !selectedColors.isEmpty { count += 1 }
        if matchStatusFilter != .all { count += 1 }
        if pinFilter != .session("") && pinFilter != .all { count += 1 }
        if dateFilter != .allTime { count += 1 }
        if contentTypeFilter != .all { count += 1 }  // NEW
        if showUnassignedPins { count += 1 }         // NEW
        if showUnknownDeer { count += 1 }
        if timeRangeFilter != .allDay { count += 1 }  // NEW
        if !selectedDates.isEmpty { count += 1 }  // NEW
        if calculationFilter != .all { count += 1 }
        return count
    }

    // Reset all filters
    func resetFilters() {
        selectedColors.removeAll()
        matchStatusFilter = .all
        dateFilter = .allTime
        contentTypeFilter = .all        // NEW
        showUnassignedPins = false      // NEW
        showUnknownDeer = false         // NEW
        timeRangeFilter = .allDay      // NEW
        customStartHour = 0            // NEW
        customEndHour = 23             // NEW
        calculationFilter = .all
        selectedDates.removeAll()
        // Keep pinFilter as is (session-specific)
    }
}

// MARK: - Protocol for Date Filtering

protocol HasTimestamp {
    var timestamp: Date { get }
}

extension DeerObservation: HasTimestamp {}
extension KMLPin: HasTimestamp {
    var timestamp: Date { createdDate }
}
