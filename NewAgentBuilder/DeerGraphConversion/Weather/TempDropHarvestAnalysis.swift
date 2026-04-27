//
//  TempDropHarvestAnalysis.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/9/25.
//


import SwiftUI

struct TempDropHarvestAnalysis: View {
    @StateObject private var harvestVM = HarvestAnalysisViewModel()
    @State private var selectedTempDrop: Int = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Temperature Drop & Harvest")
                    .font(.largeTitle)
                    .bold()
                
                Text("October 2015-2024")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Summary Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text("Average Harvest by Temperature Drop")
                        .font(.headline)
                    
                    Text("Shows how harvest correlates with temperature changes from previous day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TempDropChart(data: calculateAverages())
                        .frame(height: 300)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                
                // Temperature Drop Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Temperature Drop to View Raw Data")
                        .font(.headline)
                    
                    let availableDrops = getAvailableDrops().sorted()
                    
                    Picker("Temperature Drop", selection: $selectedTempDrop) {
                        ForEach(availableDrops, id: \.self) { drop in
                            Text(formatTempDrop(drop)).tag(drop)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Selected: \(formatTempDrop(selectedTempDrop))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Raw Data Table
                RawDataTable(
                    tempDrop: selectedTempDrop,
                    instances: getInstancesForDrop(selectedTempDrop),
                    harvestVM: harvestVM
                )
            }
            .padding()
        }
        .onAppear {
            harvestVM.loadAllYears()
        }
    }
    
    // MARK: - Data Structures
    
    struct TempDropData {
        let tempDrop: Int
        let avgHarvest: Double
        let count: Int
    }
    
    struct Instance {
        let year: Int
        let date: String
        let day: Int
        let lowTemp: Int
        let tempChange: Int
        let previousLow: Int
        let harvest: Int
    }
    
    // MARK: - Calculate Averages
    
    private func calculateAverages() -> [TempDropData] {
        var dropToHarvests: [Int: [Int]] = [:] // tempDrop: [harvests]
        
        let years = Array(2015...2024)
        
        for year in years {
            for day in 2...31 { // Start at day 2 since we need previous day
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day)),
                      let prevDate = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day - 1)),
                      let todayWeather = HighLowManager.shared.getWeatherData(for: date),
                      let yesterdayWeather = HighLowManager.shared.getWeatherData(for: prevDate) else {
                    continue
                }
                
                let tempDrop = yesterdayWeather.low - todayWeather.low
                
                let dateResults = harvestVM.dateComparison(month: 10, day: day)
                let harvest = dateResults.first(where: { $0.year == year })?.value ?? 0
                
                if dropToHarvests[tempDrop] == nil {
                    dropToHarvests[tempDrop] = []
                }
                dropToHarvests[tempDrop]?.append(harvest)
            }
        }
        
        // Calculate averages
        var results: [TempDropData] = []
        for (drop, harvests) in dropToHarvests {
            let avg = Double(harvests.reduce(0, +)) / Double(harvests.count)
            results.append(TempDropData(tempDrop: drop, avgHarvest: avg, count: harvests.count))
        }
        
        return results.sorted { $0.tempDrop < $1.tempDrop }
    }
    
    private func getAvailableDrops() -> [Int] {
        let data = calculateAverages()
        return data.map { $0.tempDrop }
    }
    
    private func getInstancesForDrop(_ drop: Int) -> [Instance] {
        var instances: [Instance] = []
        
        let years = Array(2015...2024)
        
        for year in years {
            for day in 2...31 {
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day)),
                      let prevDate = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day - 1)),
                      let todayWeather = HighLowManager.shared.getWeatherData(for: date),
                      let yesterdayWeather = HighLowManager.shared.getWeatherData(for: prevDate) else {
                    continue
                }
                
                let tempChange = yesterdayWeather.low - todayWeather.low
                
                if tempChange == drop {
                    let dateResults = harvestVM.dateComparison(month: 10, day: day)
                    let harvest = dateResults.first(where: { $0.year == year })?.value ?? 0
                    
                    instances.append(Instance(
                        year: year,
                        date: "Oct \(day)",
                        day: day,
                        lowTemp: todayWeather.low,
                        tempChange: tempChange,
                        previousLow: yesterdayWeather.low,
                        harvest: harvest
                    ))
                }
            }
        }
        
        return instances.sorted { ($0.year, $0.day) < ($1.year, $1.day) }
    }
    
    private func formatTempDrop(_ drop: Int) -> String {
        if drop > 0 {
            return "+\(drop)° (warmer)"
        } else if drop < 0 {
            return "\(drop)° (colder)"
        } else {
            return "0° (no change)"
        }
    }
}

// MARK: - Temperature Drop Chart

struct TempDropChart: View {
    let data: [TempDropHarvestAnalysis.TempDropData]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let padding: CGFloat = 60
            let chartWidth = width - (padding * 2)
            let chartHeight = height - (padding * 2)
            
            let maxHarvest = data.map { $0.avgHarvest }.max() ?? 1
            let minDrop = data.map { $0.tempDrop }.min() ?? -20
            let maxDrop = data.map { $0.tempDrop }.max() ?? 20
            let dropRange = maxDrop - minDrop
            
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(.systemBackground))
                
                // Zero line (no temp change)
                if dropRange > 0 {
                    let zeroX = padding + chartWidth * CGFloat(-minDrop) / CGFloat(dropRange)
                    Path { path in
                        path.move(to: CGPoint(x: zeroX, y: padding))
                        path.addLine(to: CGPoint(x: zeroX, y: height - padding))
                    }
                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    
                    Text("No Change")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: zeroX, y: padding - 10)
                }
                
                // Bars
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    let x = padding + chartWidth * CGFloat(item.tempDrop - minDrop) / CGFloat(dropRange)
                    let barHeight = (item.avgHarvest / maxHarvest) * chartHeight
                    let barWidth: CGFloat = max(8, chartWidth / CGFloat(data.count) * 0.8)
                    
                    Rectangle()
                        .fill(item.tempDrop < 0 ? Color.blue : (item.tempDrop > 0 ? Color.red : Color.gray))
                        .frame(width: barWidth, height: barHeight)
                        .position(x: x, y: padding + chartHeight - (barHeight / 2))
                    
                    // Value label on top of bar
                    Text(String(format: "%.1f", item.avgHarvest))
                        .font(.system(size: 8))
                        .position(x: x, y: padding + chartHeight - barHeight - 10)
                    
                    // Count label
                    Text("n=\(item.count)")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                        .position(x: x, y: height - padding + 30)
                }
                
                // X-axis labels
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    if index % 2 == 0 || data.count < 15 {
                        let x = padding + chartWidth * CGFloat(item.tempDrop - minDrop) / CGFloat(dropRange)
                        
                        Text("\(item.tempDrop)°")
                            .font(.system(size: 10))
                            .position(x: x, y: height - padding + 15)
                    }
                }
                
                // Y-axis labels
                ForEach(0..<6) { i in
                    let value = Int(maxHarvest * (1.0 - Double(i) / 5.0))
                    let y = padding + (chartHeight / 5) * CGFloat(i)
                    
                    Text("\(value)")
                        .font(.system(size: 10))
                        .position(x: 30, y: y)
                    
                    // Grid line
                    Path { path in
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: width - padding, y: y))
                    }
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                }
                
                // Axis labels
                Text("Temperature Change (°F)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .position(x: width / 2, y: height - 10)
                
                Text("Average Harvest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(-90))
                    .position(x: 10, y: height / 2)
                
                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                        Text("Colder")
                            .font(.caption2)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 12, height: 12)
                        Text("Same")
                            .font(.caption2)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("Warmer")
                            .font(.caption2)
                    }
                }
                .padding(8)
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(8)
                .position(x: width / 2, y: 20)
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Raw Data Table

struct RawDataTable: View {
    let tempDrop: Int
    let instances: [TempDropHarvestAnalysis.Instance]
    @ObservedObject var harvestVM: HarvestAnalysisViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Raw Data")
                    .font(.headline)
                Spacer()
                Text("\(instances.count) instances")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if instances.isEmpty {
                Text("No data for this temperature drop")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Header
                HStack(spacing: 8) {
                    Text("Year")
                        .frame(width: 50, alignment: .leading)
                    Text("Date")
                        .frame(width: 60, alignment: .leading)
                    Text("Low")
                        .frame(width: 50, alignment: .leading)
                    Text("Change")
                        .frame(width: 60, alignment: .leading)
                    Text("Prev Low")
                        .frame(width: 60, alignment: .leading)
                    Text("Harvest")
                        .frame(width: 60, alignment: .leading)
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                
                Divider()
                
                // Data rows
                ScrollView {
                    ForEach(instances, id: \.year) { instance in
                        HStack(spacing: 8) {
                            Text("\(instance.year)")
                                .frame(width: 50, alignment: .leading)
                            Text(instance.date)
                                .frame(width: 60, alignment: .leading)
                            Text("\(instance.lowTemp)°")
                                .frame(width: 50, alignment: .leading)
                                .foregroundColor(.blue)
                            Text("\(instance.tempChange > 0 ? "+" : "")\(instance.tempChange)°")
                                .frame(width: 60, alignment: .leading)
                                .foregroundColor(instance.tempChange < 0 ? .blue : (instance.tempChange > 0 ? .red : .gray))
                            Text("\(instance.previousLow)°")
                                .frame(width: 60, alignment: .leading)
                                .foregroundColor(.secondary)
                            Text("\(instance.harvest)")
                                .frame(width: 60, alignment: .leading)
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}