//
//  AreaComparisonView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/4/25.
//


// MARK: - AreaComparisonView.swift
// Visual comparison of all area calculation methods

import SwiftUI
import MapKit

struct AreaComparisonView: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMethod: SurveyedArea.CalculationMethod?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary card
                    summaryCard
                    
                    // Visual comparison grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(viewModel.surveyedAreas, id: \.method) { area in
                            MethodCard(
                                area: area,
                                isSelected: area.method == viewModel.selectedAreaMethod,
                                onSelect: {
                                    viewModel.selectedAreaMethod = area.method
                                    viewModel.calculateSurveyedArea(method: area.method)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Detailed comparison table
                    comparisonTable
                }
                .padding(.vertical)
            }
            .navigationTitle("Area Calculation Methods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare Methods")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatItem(
                    label: "Points",
                    value: "\(viewModel.filteredPins.count + viewModel.filteredObservations.count)",
                    icon: "mappin.circle.fill"
                )
                
                StatItem(
                    label: "Pins",
                    value: "\(viewModel.filteredPins.count)",
                    icon: "mappin"
                )
                
                StatItem(
                    label: "Deer",
                    value: "\(viewModel.filteredObservations.count)",
                    icon: "flag.fill"
                )
            }
            
            if let current = viewModel.currentSurveyedArea {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current Selection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(current.method.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f acres", current.areaInAcres))
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(String(format: "%.1f deer/sq mi", viewModel.deerPerSquareMileSurveyed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Comparison Table
    
    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Comparison")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Method")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Acres")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 70, alignment: .trailing)
                    
                    Text("Density")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                
                // Rows
                ForEach(viewModel.surveyedAreas.sorted(by: { $0.areaInAcres > $1.areaInAcres }), id: \.method) { area in
                    let density = calculateDensity(area: area)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(area.method.rawValue)
                                .font(.subheadline)
                            
                            if area.method == viewModel.selectedAreaMethod {
                                Text("Active")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(String(format: "%.1f", area.areaInAcres))
                            .font(.subheadline)
                            .frame(width: 70, alignment: .trailing)
                        
                        Text(String(format: "%.1f", density))
                            .font(.subheadline)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(area.method == viewModel.selectedAreaMethod ? Color.blue.opacity(0.05) : Color.clear)
                    
                    if area.method != viewModel.surveyedAreas.last?.method {
                        Divider()
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding(.horizontal)
            
            // Insights
            insightsSection
        }
    }
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📊 Insights")
                .font(.headline)
            
            if !viewModel.surveyedAreas.isEmpty {
                let areas = viewModel.surveyedAreas.map { $0.areaInAcres }
                let min = areas.min() ?? 0
                let max = areas.max() ?? 0
                let avg = areas.reduce(0, +) / Double(areas.count)
                
                InsightRow(
                    icon: "arrow.up.arrow.down",
                    text: "Area range: \(String(format: "%.1f - %.1f acres", min, max))"
                )
                
                InsightRow(
                    icon: "chart.bar",
                    text: "Average: \(String(format: "%.1f acres", avg))"
                )
                
                let diff = max - min
                let percent = min > 0 ? (diff / min) * 100 : 0
                InsightRow(
                    icon: "percent",
                    text: "Variance: \(String(format: "%.0f%%", percent))"
                )
                
                Divider()
                
                Text(methodRecommendation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var methodRecommendation: String {
        let pointCount = viewModel.filteredPins.count + viewModel.filteredObservations.count
        
        if pointCount < 10 {
            return "💡 With few points, Bounding Box or Convex Hull work well."
        } else if pointCount < 50 {
            return "💡 Convex Hull is recommended for balanced accuracy and simplicity."
        } else {
            return "💡 With many points, Concave Hull or Buffer Union give most accurate coverage."
        }
    }
    
    private func calculateDensity(area: SurveyedArea) -> Double {
        let squareMiles = area.areaInSquareMeters / 2_589_988.0
        guard squareMiles > 0 else { return 0 }
        return Double(viewModel.visibleObservationCount) / squareMiles
    }
}

// MARK: - Supporting Views

struct MethodCard: View {
    let area: SurveyedArea
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Icon and selection indicator
                HStack {
                    Image(systemName: methodIcon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .gray)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                Text(area.method.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(String(format: "%.1f acres", area.areaInAcres))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(String(format: "%.0f sq m", area.areaInSquareMeters))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(methodDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var methodIcon: String {
        switch area.method {
        case .boundingBox: return "square"
        case .convexHull: return "hexagon"
        case .concaveHull: return "star"
        case .bufferUnion: return "circle.grid.cross"
        }
    }
    
    private var methodDescription: String {
        switch area.method {
        case .boundingBox:
            return "Simple rectangle"
        case .convexHull:
            return "Standard boundary"
        case .concaveHull:
            return "Tight boundary"
        case .bufferUnion:
            return "Coverage zones"
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct InsightRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
        }
    }
}

// MARK: - Add to DeerMapView toolbar

/*
 Add this button to your topToolbar in DeerMapView:
 
 Button(action: { showAreaComparison = true }) {
     Image(systemName: "square.on.square.dashed")
         .font(.title2)
         .foregroundColor(.white)
         .padding(8)
         .background(Color.orange)
         .clipShape(Circle())
         .shadow(radius: 4)
 }
 
 And add this to your view:
 
 @State private var showAreaComparison = false
 
 .sheet(isPresented: $showAreaComparison) {
     AreaComparisonView(viewModel: viewModel)
 }
*/