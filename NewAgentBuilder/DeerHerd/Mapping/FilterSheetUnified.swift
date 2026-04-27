//
//  FilterSheetUnified.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/4/25.
//


// MARK: - FilterSheetUnified.swift
// Unified filter sheet for both pins and observations
// Replaces FilterSheetPins in DeerMapView.swift

import SwiftUI

struct FilterSheetUnified: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // SECTION 1: Content Type (What to show)
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Show Content")
                            .font(.headline)
                        
                        Picker("", selection: $viewModel.contentTypeFilter) {
                            Text("All").tag(MapViewModel.ContentTypeFilter.all)
                            Text("Pins Only").tag(MapViewModel.ContentTypeFilter.pinsOnly)
                            Text("Observations Only").tag(MapViewModel.ContentTypeFilter.observationsOnly)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Content Type")
                }
                
                // SECTION 2: Unmatched Content (Key for manual matching)
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Find Unmatched Content")
                            .font(.headline)
                        
                        // Toggle for unassigned pins
                        Toggle(isOn: $viewModel.showUnassignedPins) {
                            HStack {
                                Image(systemName: "mappin.slash")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unassigned Pins")
                                        .font(.subheadline)
                                    Text("Pins not linked to a property")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Toggle for unknown deer
                        Toggle(isOn: $viewModel.showUnknownDeer) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unknown Deer")
                                        .font(.subheadline)
                                    Text("Observations without pin match")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Info about what these do
                        if viewModel.showUnassignedPins || viewModel.showUnknownDeer {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Use these to manually match pins to deer observations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                } header: {
                    Text("Unmatched Content")
                }
                
                // SECTION 3: Color Filter
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Filter by Color")
                                .font(.headline)
                            Spacer()
                            if !viewModel.selectedColors.isEmpty {
                                Button("Clear") {
                                    viewModel.selectedColors.removeAll()
                                }
                                .font(.caption)
                            }
                        }
                        
                        if viewModel.availableColors.isEmpty {
                            Text("No colors available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(viewModel.availableColors, id: \.self) { color in
                                    ColorChip(
                                        color: color,
                                        isSelected: viewModel.selectedColors.contains(color),
                                        action: {
                                            if viewModel.selectedColors.contains(color) {
                                                viewModel.selectedColors.remove(color)
                                            } else {
                                                viewModel.selectedColors.insert(color)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    Text("Color")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Calculation Status")
                            .font(.headline)
                        
                        Picker("", selection: $viewModel.calculationFilter) {
                            ForEach(MapViewModel.CalculationFilter.allCases, id: \.self) { filter in
                                HStack {
                                    Image(systemName: iconForCalculationFilter(filter))
                                    Text(filter.rawValue)
                                }
                                .tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        // Show stats
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Included: \(includedCount)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text("Excluded: \(excludedCount)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Total: \(totalCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Survey Calculations")
                }
                

                // SECTION 4: Date Range
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Date Range")
                            .font(.headline)
                        
                        Picker("", selection: $viewModel.dateFilter) {
                            ForEach(MapViewModel.DateFilter.allCases.filter { $0 != .custom && $0 != .sessions }, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                            Text("Select Dates").tag(MapViewModel.DateFilter.custom)
                        }
                        .pickerStyle(.menu)
                        
                        // Show available dates if "Select Dates" is chosen
                        if viewModel.dateFilter == .custom {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Available Dates")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    if !viewModel.selectedDates.isEmpty {
                                        Button("Clear") {
                                            viewModel.selectedDates.removeAll()
                                        }
                                        .font(.caption)
                                    }
                                }
                                
                                if availableDates.isEmpty {
                                    Text("No dates available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 4)
                                } else {
                                    ScrollView {
                                        VStack(spacing: 4) {
                                            ForEach(availableDates, id: \.self) { date in
                                                DateSelectionRow(
                                                    date: date,
                                                    count: countForDate(date),
                                                    isSelected: viewModel.selectedDates.contains(date),
                                                    action: {
                                                        if viewModel.selectedDates.contains(date) {
                                                            viewModel.selectedDates.remove(date)
                                                        } else {
                                                            viewModel.selectedDates.insert(date)
                                                        }
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 200)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                } header: {
                    Text("Date Range")
                }
                // MARK: - TIME OF DAY
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Time of Day")
                            .font(.headline)
                        
                        // Histogram showing distribution
                        if !hourlyDistribution.isEmpty {
                            HourlyDistributionChart(distribution: hourlyDistribution)
                                .frame(height: 80)
                                .padding(.vertical, 8)
                        }
                        
                        Picker("", selection: $viewModel.timeRangeFilter) {
                            ForEach(MapViewModel.TimeRangeFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        // Custom time range pickers
                        if viewModel.timeRangeFilter == .custom {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Start:")
                                        .frame(width: 50, alignment: .leading)
                                    Picker("Start Hour", selection: $viewModel.customStartHour) {
                                        ForEach(0..<24) { hour in
                                            Text(formatHour(hour)).tag(hour)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                }
                                
                                HStack {
                                    Text("End:")
                                        .frame(width: 50, alignment: .leading)
                                    Picker("End Hour", selection: $viewModel.customEndHour) {
                                        ForEach(0..<24) { hour in
                                            Text(formatHour(hour)).tag(hour)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                } header: {
                    Text("Time of Day")
                }
                // MARK: - RESULTS Summary
                // SECTION 5: Results Summary
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // Pins count
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.blue)
                            Text("\(viewModel.filteredPins.count) pins")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if viewModel.contentTypeFilter != .pinsOnly {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Image(systemName: "flag.fill")
                                    .foregroundColor(.red)
                                Text("\(viewModel.filteredObservations.count) deer")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        // Total available
                        Text("of \(viewModel.kmlPins.count) total pins, \(viewModel.observations.count) total deer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Active filters count
                        if viewModel.activeFilterCount > 0 {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.orange)
                                Text("\(viewModel.activeFilterCount) active filter(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Unmatched counts (if those filters are on)
                        if viewModel.showUnassignedPins || viewModel.showUnknownDeer {
                            Divider()
                                .padding(.vertical, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if viewModel.showUnassignedPins {
                                    HStack {
                                        Image(systemName: "mappin.slash")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Text("\(unassignedPinsCount) unassigned pins")
                                            .font(.caption)
                                    }
                                }
                                
                                if viewModel.showUnknownDeer {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                            .foregroundColor(.purple)
                                            .font(.caption)
                                        Text("\(unknownDeerCount) unknown deer")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Results")
                }
            }
            .navigationTitle("Filter Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.activeFilterCount > 0 {
                        Button("Reset All") {
                            viewModel.resetFilters()
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }


 
    }
    
    // MARK: - Computed Properties
    // MARK: - Date Helpers
    private var includedCount: Int {
        viewModel.kmlPins.filter { $0.isIncludedInCalculations }.count +
        viewModel.observations.filter { $0.isIncludedInCalculations }.count
    }

    private var excludedCount: Int {
        viewModel.kmlPins.filter { !$0.isIncludedInCalculations }.count +
        viewModel.observations.filter { !$0.isIncludedInCalculations }.count
    }

    private var totalCount: Int {
        viewModel.kmlPins.count + viewModel.observations.count
    }

    private func iconForCalculationFilter(_ filter: MapViewModel.CalculationFilter) -> String {
        switch filter {
        case .all: return "circle.grid.cross"
        case .includedOnly: return "checkmark.circle"
        case .excludedOnly: return "xmark.circle"
        }
    }
    // MARK: - Time Helpers
    private var hourlyDistribution: [Int: Int] {
        var distribution: [Int: Int] = [:]
        
        // Count observations by hour
        for obs in viewModel.observations {
            let hour = Calendar.current.component(.hour, from: obs.timestamp)
            distribution[hour, default: 0] += 1
        }
        
        // Count pins by hour
        for pin in viewModel.kmlPins {
            let hour = Calendar.current.component(.hour, from: pin.createdDate)
            distribution[hour, default: 0] += 1
        }
        
        return distribution
    }
    private func formatHour(_ hour: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(period)"
    }

    private var availableDates: [Date] {
        // Get unique dates from both pins and observations
        let pinDates = viewModel.kmlPins.map { Calendar.current.startOfDay(for: $0.createdDate) }
        let obsDates = viewModel.observations.map { Calendar.current.startOfDay(for: $0.timestamp) }
        
        let allDates = Set(pinDates + obsDates)
        return allDates.sorted(by: >) // Most recent first
    }

    private func countForDate(_ date: Date) -> Int {
        let pins = viewModel.kmlPins.filter { Calendar.current.isDate($0.createdDate, inSameDayAs: date) }.count
        let obs = viewModel.observations.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }.count
        return pins + obs
    }
    
    private var unassignedPinsCount: Int {
        viewModel.kmlPins.filter { $0.propertyId == nil }.count
    }
    
    private var unknownDeerCount: Int {
        viewModel.observations.filter { $0.color == "black" || $0.classification == .unknown }.count
    }
}
struct DateSelectionRow: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Text("\(count) items")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Views (reuse from original)



//struct ColorChip: View {
//    let color: String
//    let isSelected: Bool
//    let action: () -> Void
//    
//    var body: some View {
//        Button(action: action) {
//            HStack(spacing: 6) {
//                Circle()
//                    .fill(colorForString(color))
//                    .frame(width: 16, height: 16)
//                
//                Text(color.capitalized)
//                    .font(.subheadline)
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
//            .cornerRadius(16)
//            .overlay(
//                RoundedRectangle(cornerRadius: 16)
//                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
//            )
//        }
//        .buttonStyle(.plain)
//    }
//    
//    private func colorForString(_ colorName: String) -> Color {
//        switch colorName.lowercased() {
//        case "red": return .red
//        case "blue": return .blue
//        case "green": return .green
//        case "yellow": return .yellow
//        case "purple": return .purple
//        case "black": return .black
//        default: return .gray
//        }
//    }
//}
