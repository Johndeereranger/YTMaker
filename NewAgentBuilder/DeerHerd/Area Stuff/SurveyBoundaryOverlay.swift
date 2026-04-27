//
//  SurveyBoundaryOverlay.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/4/25.
//


// MARK: - AreaCalculationIntegration.swift
// Integration code for MapViewModel and UI components

import SwiftUI
import MapKit

// MARK: - MapViewModel Extensions

extension MapViewModel {
    
    // Add these published properties to MapViewModel:
    /*
    @Published var surveyedAreas: [SurveyedArea] = []
    @Published var selectedAreaMethod: SurveyedArea.CalculationMethod = .convexHull
    @Published var showSurveyBoundary = false
    @Published var currentSurveyedArea: SurveyedArea?
    */
    
    
    enum TimeRangeFilter: String, CaseIterable {
        case allDay = "All Day"
        case morning = "Morning (5am-11am)"
        case afternoon = "Afternoon (11am-5pm)"
        case custom = "Custom Range"
        
        var timeRange: (start: Int, end: Int)? {
            switch self {
            case .allDay: return nil
            case .morning: return (1, 12)
            case .afternoon: return (12, 23)
            case .custom: return nil // use customStartHour/customEndHour
            }
        }
    }


    
    /// Calculate surveyed area using all methods
    func calculateAllSurveyedAreas() {
        surveyedAreas = AreaCalculator.calculateAllMethods(
            pins: filteredPins,
            observations: filteredObservations
        )
        
        // Set current area to selected method
        currentSurveyedArea = surveyedAreas.first { $0.method == selectedAreaMethod }
        
        print("📐 Calculated surveyed areas:")
        for area in surveyedAreas {
            print("   \(area.description)")
        }
    }
    
    /// Calculate surveyed area using specific method
    func calculateSurveyedArea(method: SurveyedArea.CalculationMethod) {
        currentSurveyedArea = AreaCalculator.calculate(
            pins: filteredPins,
            observations: filteredObservations,
            method: method
        )
        
        if let area = currentSurveyedArea {
            print("📐 \(area.description)")
        }
    }
    
    /// Updated density calculation using surveyed area
    var deerPerSquareMileSurveyed: Double {
        guard let area = currentSurveyedArea, area.areaInSquareMeters > 0 else {
            return deerPerSquareMile // Fall back to property area
        }
        
        let squareMiles = area.areaInSquareMeters / 2_589_988.0 // sq m to sq mi
        return Double(visibleObservationCount) / squareMiles
    }
    
    var surveyedAcres: Double {
        currentSurveyedArea?.areaInAcres ?? 0
    }
}

// MARK: - SurveyBoundaryOverlay (Map Component)

struct SurveyBoundaryOverlay: MapContent {
    let area: SurveyedArea
    
    var body: some MapContent {
        MapPolygon(coordinates: area.boundaryCoordinates)
            .foregroundStyle(Color.orange.opacity(0.15))
            .stroke(Color.orange, lineWidth: 2)
    }
}

// MARK: - AreaCalculationPanel (Stats Panel Addition)

struct AreaCalculationPanel: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var showMethodPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Surveyed Area")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    if let area = viewModel.currentSurveyedArea {
                        Text(String(format: "%.1f acres", area.areaInAcres))
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(area.method.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Calculating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                //Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Density")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text(String(format: "%.1f", viewModel.deerPerSquareMileSurveyed))
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("deer/sq mi")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Toggle and method picker
            HStack {
                Toggle("Show Boundary", isOn: $viewModel.showSurveyBoundary)
                    .font(.caption)
                
                Button(action: { showMethodPicker = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
        .fixedSize(horizontal: true, vertical: false)
        .sheet(isPresented: $showMethodPicker) {
            AreaMethodPicker(viewModel: viewModel)
        }
    }
}

// MARK: - AreaMethodPicker Sheet

struct AreaMethodPicker: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Select the method for calculating surveyed area. Each handles gaps and boundaries differently.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Calculation Methods") {
                    ForEach(viewModel.surveyedAreas, id: \.method) { area in
                        Button(action: {
                            viewModel.selectedAreaMethod = area.method
                            viewModel.calculateSurveyedArea(method: area.method)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(area.method.rawValue)
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    if area.method == viewModel.selectedAreaMethod {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Text(String(format: "%.1f acres (%.0f sq m)", area.areaInAcres, area.areaInSquareMeters))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(methodDescription(area.method))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Comparison") {
                    if viewModel.surveyedAreas.count >= 2 {
                        let min = viewModel.surveyedAreas.map { $0.areaInAcres }.min() ?? 0
                        let max = viewModel.surveyedAreas.map { $0.areaInAcres }.max() ?? 0
                        let diff = max - min
                        let percent = min > 0 ? (diff / min) * 100 : 0
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Range: \(String(format: "%.1f", min)) - \(String(format: "%.1f", max)) acres")
                                .font(.caption)
                            Text("Difference: \(String(format: "%.1f acres (%.0f%%)", diff, percent))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Area Calculation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func methodDescription(_ method: SurveyedArea.CalculationMethod) -> String {
        switch method {
        case .boundingBox:
            return "Simple rectangle around all points. Fastest, but includes empty spaces."
        case .convexHull:
            return "Smallest convex shape around all points. Standard GIS approach."
        case .concaveHull:
            return "Tighter boundary that can curve inward. Better for scattered points."
        case .bufferUnion:
            return "Coverage area within 50m of each point. Most accurate for actual surveyed area."
        }
    }
}

// MARK: - Integration Instructions

/*
 HOW TO INTEGRATE INTO YOUR APP:
 
 1. Add to MapViewModel (around line 20):
 
    @Published var surveyedAreas: [SurveyedArea] = []
    @Published var selectedAreaMethod: SurveyedArea.CalculationMethod = .convexHull
    @Published var showSurveyBoundary = false
    @Published var currentSurveyedArea: SurveyedArea?
 
 2. Update MapViewModel.loadData() to calculate areas (add at end):
 
    calculateAllSurveyedAreas()
 
 3. Update onChange handlers in DeerMapView to recalculate (add):
 
    .onChange(of: viewModel.pinFilter) { _, _ in
        Task {
            await viewModel.loadData()
            viewModel.calculateAllSurveyedAreas()  // ← ADD THIS
        }
    }
    
    .onChange(of: viewModel.dateFilter) { _, _ in
        viewModel.calculateStats()
        viewModel.calculateAllSurveyedAreas()  // ← ADD THIS
    }
 
 4. Add survey boundary to map in DeerMapView.mapView:
 
    Map(position: $cameraPosition) {
        boundaryContent
        
        // ADD THIS:
        if viewModel.showSurveyBoundary, let area = viewModel.currentSurveyedArea {
            SurveyBoundaryOverlay(area: area)
        }
        
        pinsContent
        observationsContent
    }
 
 5. Replace or add to bottom panel in DeerMapView (around line 150):
 
    VStack(spacing: 12) {
        // Existing panels...
        
        // ADD THIS:
        HStack {
            AreaCalculationPanel(viewModel: viewModel)
            Spacer()
        }
    }
    .padding()
 
 6. Update StatsPanel to use surveyed density (optional):
 
    Text("Deer/sq mi: \(String(format: "%.1f", viewModel.deerPerSquareMileSurveyed))")
        .font(.caption)
*/
