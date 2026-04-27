//
//  ColdFrontAnalysisView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/9/25.
//


import SwiftUI
import SwiftUI

// MARK: - Embeddable Content (NO ScrollView)
struct ColdFrontContent: View {
    @ObservedObject var harvestVM: HarvestAnalysisViewModel
    @Binding var coldFrontThreshold: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Measure the first significant October cold front and its impact on harvest")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Threshold Control
            HStack {
                Text("Cold Front Threshold:")
                Stepper(value: $coldFrontThreshold, in: 5...20, step: 1) {
                    Text("\(Int(coldFrontThreshold))° drop")
                        .bold()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            
            Text("Detects first October day where high temp drops by at least this amount from previous day")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Year by Year Analysis
            ForEach(2005...2024, id: \.self) { year in
                if let analysis = analyzeColdFront(year: year, threshold: coldFrontThreshold) {
                    YearColdFrontCard(analysis: analysis)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(year)")
                            .font(.headline)
                        Text("No cold front detected meeting \(Int(coldFrontThreshold))° threshold")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Data Structures
    
    struct ColdFrontAnalysis {
        let year: Int
        let frontDate: Date
        let frontDay: Int
        let tempDrop: Double
        let baseline: Double
        let day0: DayImpact
        let day1: DayImpact
        let day2: DayImpact
        let pattern: String
    }
    
    struct DayImpact {
        let date: Date
        let harvest: Int
        let vsBaseline: Int
        let vsBaselinePercent: Int
        let historicalAvg: Double
        let vsHistorical: Int
        let vsHistoricalPercent: Int
    }
    
    // MARK: - Analysis Function
    
    private func analyzeColdFront(year: Int, threshold: Double) -> ColdFrontAnalysis? {
        // Scan October for first significant temp drop
        for day in 2...30 {
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day)),
                  let prevDate = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day - 1)),
                  let todayWeather = HighLowManager.shared.getWeatherData(for: date),
                  let yesterdayWeather = HighLowManager.shared.getWeatherData(for: prevDate) else {
                continue
            }
            
            let tempDrop = Double(yesterdayWeather.high - todayWeather.high)
            
            if tempDrop >= threshold {
                // Found the cold front - now analyze it
                
                // Calculate baseline (3 days before)
                let baseline = calculateBaseline(date: date, year: year)
                
                // Analyze each day
                let day0 = analyzeDayImpact(date: date, year: year, baseline: baseline)
                guard let nextDate1 = Calendar.current.date(byAdding: .day, value: 1, to: date) else { continue }
                let day1 = analyzeDayImpact(date: nextDate1, year: year, baseline: baseline)
                guard let nextDate2 = Calendar.current.date(byAdding: .day, value: 2, to: date) else { continue }
                let day2 = analyzeDayImpact(date: nextDate2, year: year, baseline: baseline)
                
                // Determine pattern
                let pattern = determinePattern(day0: day0, day1: day1, day2: day2, baseline: baseline)
                
                return ColdFrontAnalysis(
                    year: year,
                    frontDate: date,
                    frontDay: day,
                    tempDrop: tempDrop,
                    baseline: baseline,
                    day0: day0,
                    day1: day1,
                    day2: day2,
                    pattern: pattern
                )
            }
        }
        
        return nil
    }
    
    private func calculateBaseline(date: Date, year: Int) -> Double {
        var total = 0
        var count = 0
        
        // Get 3 days before
        for i in 1...3 {
            guard let priorDate = Calendar.current.date(byAdding: .day, value: -i, to: date) else { continue }
            let components = Calendar.current.dateComponents([.month, .day], from: priorDate)
            
            if let month = components.month, let day = components.day {
                let dateResults = harvestVM.dateComparison(month: month, day: day)
                if let yearData = dateResults.first(where: { $0.year == year }) {
                    total += yearData.value
                    count += 1
                }
            }
        }
        
        return count > 0 ? Double(total) / Double(count) : 0
    }
    
    private func analyzeDayImpact(date: Date, year: Int, baseline: Double) -> DayImpact {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        
        guard let month = components.month, let day = components.day else {
            return DayImpact(date: date, harvest: 0, vsBaseline: 0, vsBaselinePercent: 0, historicalAvg: 0, vsHistorical: 0, vsHistoricalPercent: 0)
        }
        
        // Get harvest for this specific year
        let dateResults = harvestVM.dateComparison(month: month, day: day)
        let harvest = dateResults.first(where: { $0.year == year })?.value ?? 0
        
        // Calculate vs baseline
        let vsBaseline = harvest - Int(baseline)
        let vsBaselinePercent = baseline > 0 ? Int((Double(vsBaseline) / baseline) * 100) : 0
        
        // Calculate historical average for this specific date
        let historicalAvg = dateResults.isEmpty ? 0 : Double(dateResults.reduce(0) { $0 + $1.value }) / Double(dateResults.count)
        let vsHistorical = harvest - Int(historicalAvg)
        let vsHistoricalPercent = historicalAvg > 0 ? Int((Double(vsHistorical) / historicalAvg) * 100) : 0
        
        return DayImpact(
            date: date,
            harvest: harvest,
            vsBaseline: vsBaseline,
            vsBaselinePercent: vsBaselinePercent,
            historicalAvg: historicalAvg,
            vsHistorical: vsHistorical,
            vsHistoricalPercent: vsHistoricalPercent
        )
    }
    
    private func determinePattern(day0: DayImpact, day1: DayImpact, day2: DayImpact, baseline: Double) -> String {
        let threshold = baseline * 0.15 // 15% above baseline counts as elevated
        
        let day0Elevated = Double(day0.harvest) > baseline + threshold
        let day1Elevated = Double(day1.harvest) > baseline + threshold
        let day2Elevated = Double(day2.harvest) > baseline + threshold
        
        if day0Elevated && day1Elevated && day2Elevated {
            return "Strong 3-day spike"
        } else if day0Elevated && day1Elevated {
            return "Strong 2-day spike"
        } else if day1Elevated && day2Elevated {
            return "Delayed 2-day spike"
        } else if day0Elevated {
            return "1-day spike (immediate)"
        } else if day1Elevated {
            return "1-day spike (next day)"
        } else if day2Elevated {
            return "1-day spike (day 2)"
        } else {
            return "No significant spike"
        }
    }
}

// MARK: - Year Card View

struct YearColdFrontCard: View {
    let analysis: ColdFrontContent.ColdFrontAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("\(analysis.year)")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Oct \(analysis.frontDay)")
                        .font(.headline)
                    Text("\(Int(analysis.tempDrop))° drop")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Baseline
            HStack {
                Text("Baseline (Oct \(analysis.frontDay-3)-\(analysis.frontDay-1)):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f deer/day", analysis.baseline))
                    .fontWeight(.semibold)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            
            Divider()
            
            // Day 0
            DayImpactRow(
                label: "Oct \(analysis.frontDay) (Day 0)",
                impact: analysis.day0,
                baseline: analysis.baseline
            )
            
            // Day 1
            DayImpactRow(
                label: "Oct \(analysis.frontDay + 1) (Day +1)",
                impact: analysis.day1,
                baseline: analysis.baseline
            )
            
            // Day 2
            DayImpactRow(
                label: "Oct \(analysis.frontDay + 2) (Day +2)",
                impact: analysis.day2,
                baseline: analysis.baseline
            )
            
            Divider()
            
            // Pattern Summary
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.green)
                Text("Pattern:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(analysis.pattern)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(6)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Day Impact Row

struct DayImpactRow: View {
    let label: String
    let impact: ColdFrontContent.DayImpact
    let baseline: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .bold()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Harvest:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(impact.harvest) deer")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("vs Baseline:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(impact.vsBaseline >= 0 ? "+" : "")\(impact.vsBaseline) (\(impact.vsBaselinePercent >= 0 ? "+" : "")\(impact.vsBaselinePercent)%)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(getColor(impact.vsBaseline))
                    }
                    
                    HStack {
                        Text("vs Historical:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(impact.vsHistorical >= 0 ? "+" : "")\(impact.vsHistorical) (\(impact.vsHistoricalPercent >= 0 ? "+" : "")\(impact.vsHistoricalPercent)%)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(getColor(impact.vsHistorical))
                    }
                }
                
                Spacer()
                
                Image(systemName: getIcon(impact.vsBaseline))
                    .font(.title2)
                    .foregroundColor(getColor(impact.vsBaseline))
            }
        }
        .padding()
        .background(getBackgroundColor(impact.vsBaseline, baseline: baseline))
        .cornerRadius(6)
    }
    
    private func getColor(_ value: Int) -> Color {
        if value > Int(baseline * 0.15) {
            return .green
        } else if value < -Int(baseline * 0.15) {
            return .red
        } else {
            return .orange
        }
    }
    
    private func getIcon(_ value: Int) -> String {
        if value > Int(baseline * 0.15) {
            return "arrow.up.circle.fill"
        } else if value < -Int(baseline * 0.15) {
            return "arrow.down.circle.fill"
        } else {
            return "arrow.right.circle.fill"
        }
    }
    
    private func getBackgroundColor(_ value: Int, baseline: Double) -> Color {
        if value > Int(baseline * 0.15) {
            return Color.green.opacity(0.1)
        } else if value < -Int(baseline * 0.15) {
            return Color.red.opacity(0.1)
        } else {
            return Color.orange.opacity(0.1)
        }
    }
}
