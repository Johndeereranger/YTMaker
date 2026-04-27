//
//  MonthTempHarvestView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/9/25.
//


import SwiftUI

struct MonthTempHarvestView: View {
    @StateObject private var harvestVM = HarvestAnalysisViewModel()
    
    @State private var selectedYear = 2024
    @State private var selectedMonth = 10
    @State private var harvestScale: Double = 1.0
    @State private var tempScale: Double = 1.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Temperature & Harvest Analysis")
                    .font(.largeTitle)
                    .bold()
                
                // Controls
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Year:")
                        Picker("Year", selection: $selectedYear) {
                            ForEach(2005...2024, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                        .frame(width: 120)
                        
                        Text("Month:")
                        Picker("Month", selection: $selectedMonth) {
                            Text("October").tag(10)
                            Text("November").tag(11)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    HStack {
                        Text("Harvest Scale:")
                        Slider(value: $harvestScale, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1fx", harvestScale))
                            .frame(width: 50)
                    }
                    
                    HStack {
                        Text("Temperature Scale:")
                        Slider(value: $tempScale, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1fx", tempScale))
                            .frame(width: 50)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // The Chart
                MonthChart(
                    year: selectedYear,
                    month: selectedMonth,
                    harvestScale: harvestScale,
                    tempScale: tempScale,
                    harvestVM: harvestVM
                )
                .frame(height: 400)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                
                // Data Table
                DataTable(year: selectedYear, month: selectedMonth, harvestVM: harvestVM)
            }
            .padding()
        }
        .onAppear {
            harvestVM.loadAllYears()
        }
    }
}

struct MonthChart: View {
    let year: Int
    let month: Int
    let harvestScale: Double
    let tempScale: Double
    @ObservedObject var harvestVM: HarvestAnalysisViewModel
    
    private var chartData: [(day: Int, harvest: Int, lowTemp: Int)] {
        var data: [(day: Int, harvest: Int, lowTemp: Int)] = []
        let daysInMonth = month == 10 ? 31 : 30
        
        for day in 1...daysInMonth {
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                  let weather = HighLowManager.shared.getWeatherData(for: date) else {
                continue
            }
            
            let dateResults = harvestVM.dateComparison(month: month, day: day)
            let harvest = dateResults.first(where: { $0.year == year })?.value ?? 0
            
            data.append((day: day, harvest: harvest, lowTemp: weather.low))
        }
        
        return data
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ChartBackground()
                ChartGridLines(geometry: geometry)
                HarvestLine(data: chartData, geometry: geometry, scale: harvestScale)
                TempLine(data: chartData, geometry: geometry, scale: tempScale)
                ChartLabels(data: chartData, geometry: geometry)
                ChartLegend(geometry: geometry)
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ChartBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color(.systemBackground))
    }
}

struct ChartGridLines: View {
    let geometry: GeometryProxy
    
    var body: some View {
        let padding: CGFloat = 60
        let chartHeight = geometry.size.height - (padding * 2)
        
        ForEach(0..<6) { i in
            let y = padding + (chartHeight / 5) * CGFloat(i)
            Path { path in
                path.move(to: CGPoint(x: padding, y: y))
                path.addLine(to: CGPoint(x: geometry.size.width - padding, y: y))
            }
            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
    }
}

struct HarvestLine: View {
    let data: [(day: Int, harvest: Int, lowTemp: Int)]
    let geometry: GeometryProxy
    let scale: Double
    
    var body: some View {
        let padding: CGFloat = 60
        let chartWidth = geometry.size.width - (padding * 2)
        let chartHeight = geometry.size.height - (padding * 2)
        let maxHarvest = data.map { $0.harvest }.max() ?? 1
        
        Path { path in
            for (index, item) in data.enumerated() {
                let x = padding + (chartWidth / CGFloat(data.count - 1)) * CGFloat(index)
                let scaledHeight = (CGFloat(item.harvest) / CGFloat(maxHarvest)) * chartHeight * scale
                let y = padding + chartHeight - scaledHeight
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Color.green, lineWidth: 3)
    }
}

struct TempLine: View {
    let data: [(day: Int, harvest: Int, lowTemp: Int)]
    let geometry: GeometryProxy
    let scale: Double
    
    var body: some View {
        let padding: CGFloat = 60
        let chartWidth = geometry.size.width - (padding * 2)
        let chartHeight = geometry.size.height - (padding * 2)
        let minTemp = data.map { $0.lowTemp }.min() ?? 0
        let maxTemp = data.map { $0.lowTemp }.max() ?? 100
        let tempRange = maxTemp - minTemp
        
        Path { path in
            for (index, item) in data.enumerated() {
                let x = padding + (chartWidth / CGFloat(data.count - 1)) * CGFloat(index)
                let normalizedTemp = CGFloat(item.lowTemp - minTemp) / CGFloat(tempRange)
                let y = padding + chartHeight - (normalizedTemp * chartHeight * scale)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Color.blue, lineWidth: 3)
    }
}

struct ChartLabels: View {
    let data: [(day: Int, harvest: Int, lowTemp: Int)]
    let geometry: GeometryProxy
    
    var body: some View {
        let padding: CGFloat = 60
        let chartWidth = geometry.size.width - (padding * 2)
        
        ForEach(Array(data.enumerated()), id: \.offset) { index, item in
            if index % 3 == 0 {
                let x = padding + (chartWidth / CGFloat(data.count - 1)) * CGFloat(index)
                Text("\(item.day)")
                    .font(.system(size: 12))
                    .position(x: x, y: geometry.size.height - 25)
            }
        }
    }
}

struct ChartLegend: View {
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Text("Harvest").font(.caption)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 10, height: 10)
                Text("Low Temp").font(.caption)
            }
        }
        .padding(8)
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(8)
        .position(x: geometry.size.width / 2, y: 25)
    }
}
// MARK: - Data Table
import SwiftUI

struct DataTable: View {
    let year: Int
    let month: Int
    @ObservedObject var harvestVM: HarvestAnalysisViewModel
    
    private var tableData: [(day: Int, dayOfWeek: String, harvest: Int, harvestDiff: Int, avgHarvest: Double, high: Int, low: Int)] {
        var data: [(day: Int, dayOfWeek: String, harvest: Int, harvestDiff: Int, avgHarvest: Double, high: Int, low: Int)] = []
        let daysInMonth = month == 10 ? 31 : 30
        
        for day in 1...daysInMonth {
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                  let weather = HighLowManager.shared.getWeatherData(for: date) else {
                continue
            }
            
            // Get harvest for this year
            let dateResults = harvestVM.dateComparison(month: month, day: day)
            let harvest = dateResults.first(where: { $0.year == year })?.value ?? 0
            
            // Calculate average harvest for all other years for this date
            let otherYearsHarvests = dateResults.filter { $0.year != year }.map { $0.value }
            let avgHarvest = otherYearsHarvests.isEmpty ? 0 : Double(otherYearsHarvests.reduce(0, +)) / Double(otherYearsHarvests.count)
            let harvestDiff = harvest - Int(avgHarvest)
            
            // Get day of week
            let dayOfWeek = getDayOfWeek(date: date)
            
            data.append((
                day: day,
                dayOfWeek: dayOfWeek,
                harvest: harvest,
                harvestDiff: harvestDiff,
                avgHarvest: avgHarvest,
                high: weather.high,
                low: weather.low
            ))
        }
        
        return data
    }
    
    private func getDayOfWeek(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func getDiffColor(_ diff: Int, avg: Double) -> Color {
        // "Massive" = more than 30% above average
        let threshold = avg * 0.3
        if Double(diff) > threshold {
            return .green
        } else {
            return .primary
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Data")
                .font(.headline)
            
            // Header
            HStack(spacing: 8) {
                Text("Day")
                    .frame(width: 40, alignment: .leading)
                    .bold()
                Text("DoW")
                    .frame(width: 45, alignment: .leading)
                    .bold()
                Text("Harvest")
                    .frame(width: 60, alignment: .leading)
                    .bold()
                Text("vs Avg")
                    .frame(width: 60, alignment: .leading)
                    .bold()
                Text("High")
                    .frame(width: 50, alignment: .leading)
                    .bold()
                Text("Low")
                    .frame(width: 50, alignment: .leading)
                    .bold()
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Divider()
            
            // Data rows
            ForEach(tableData, id: \.day) { data in
                HStack(spacing: 8) {
                    Text("\(data.day)")
                        .frame(width: 40, alignment: .leading)
                    
                    Text(data.dayOfWeek)
                        .frame(width: 45, alignment: .leading)
                        .foregroundColor(data.dayOfWeek == "Sat" || data.dayOfWeek == "Sun" ? .orange : .secondary)
                    
                    Text("\(data.harvest)")
                        .frame(width: 60, alignment: .leading)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 2) {
                        Text("\(data.harvestDiff >= 0 ? "+" : "")\(data.harvestDiff)")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundColor(getDiffColor(data.harvestDiff, avg: data.avgHarvest))
                            .fontWeight(getDiffColor(data.harvestDiff, avg: data.avgHarvest) == .green ? .bold : .regular)
                    }
                    .frame(width: 60, alignment: .leading)
                    
                    Text("\(data.high)°")
                        .frame(width: 50, alignment: .leading)
                        .foregroundColor(.red)
                    
                    Text("\(data.low)°")
                        .frame(width: 50, alignment: .leading)
                        .foregroundColor(.blue)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}
