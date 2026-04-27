//
//  HarvestAnalysisViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/5/25.
//




import SwiftUI
import Foundation

class HarvestAnalysisViewModel: ObservableObject {
    @Published var availableYears: [Int] = []
    @Published var selectedYears: Set<Int> = []
    @Published var allYearData: [Int: [DayBarData]] = [:]
    @Published var selectedSingleYear: Int = Calendar.current.component(.year, from: Date())
    
    private let userDefaults = UserDefaults.standard
    private let storageKeyPrefix = "HarvestData_"
    
    init() {
      //  nuclearCleanup()
        loadAvailableYears()
        fullDiagnostic()
        //permanentlyCleanAllData()
        //removeDuplicates(for: 2010)
    }
    func fullDiagnostic() {
        print("\n🔬 FULL DIAGNOSTIC STARTING")
      //  print("="*60)
        
        // Check what's ACTUALLY in UserDefaults RIGHT NOW
        print("\n1️⃣ CHECKING USERDEFAULTS (RAW STORAGE):")
        for year in availableYears {
            let key = storageKeyPrefix + String(year)
            
            if let rawData = userDefaults.data(forKey: key),
               let stored = try? JSONDecoder().decode([DayBarData].self, from: rawData) {
                
                let dates = stored.map { $0.date }
                let unique = Set(dates)
                let dupes = dates.count - unique.count
                
                print("  Year \(year) in UserDefaults:")
                print("    Total entries: \(dates.count)")
                print("    Unique dates: \(unique.count)")
                print("    Duplicates: \(dupes)")
                
                if dupes > 0 {
                    let groups = Dictionary(grouping: stored, by: { $0.date })
                    let duplicated = groups.filter { $0.value.count > 1 }
                    print("    Duplicate dates: \(duplicated.keys.sorted().joined(separator: ", "))")
                }
            } else {
                print("  Year \(year): NO DATA or can't decode")
            }
        }
        
        // Check what's in MEMORY (allYearData)
        print("\n2️⃣ CHECKING IN-MEMORY DATA (allYearData):")
        for (year, data) in allYearData.sorted(by: { $0.key < $1.key }) {
            let dates = data.map { $0.date }
            let unique = Set(dates)
            let dupes = dates.count - unique.count
            
            print("  Year \(year) in memory:")
            print("    Total entries: \(dates.count)")
            print("    Unique dates: \(unique.count)")
            print("    Duplicates: \(dupes)")
            
            if dupes > 0 {
                let groups = Dictionary(grouping: data, by: { $0.date })
                let duplicated = groups.filter { $0.value.count > 1 }
                print("    Duplicate dates: \(duplicated.keys.sorted().joined(separator: ", "))")
            }
        }
        
        // Check CSV exporter sees
        print("\n3️⃣ WHAT CSV EXPORTER WILL SEE:")
        let exporter = CSVExporter(harvestViewModel: self)
        
        // Simulate what the exporter does
        var allDates: Set<Date> = Set()
        for (year, dayBars) in allYearData {
            for dayBar in dayBars {
                let parts = dayBar.date.split(separator: "/").compactMap { Int($0) }
                if parts.count == 2,
                   let date = Calendar.current.date(from: DateComponents(year: year, month: parts[0], day: parts[1])) {
                    
                    // Check if this creates duplicates
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let dateStr = formatter.string(from: date)
                    
                    if allDates.contains(date) {
                        print("  ⚠️ DUPLICATE DATE FOUND: \(dateStr) from \(year)-\(dayBar.date)")
                    }
                    allDates.insert(date)
                }
            }
        }
        print("  Total unique dates for CSV: \(allDates.count)")
        
        //print("\n" + "="*60)
        print("🔬 DIAGNOSTIC COMPLETE\n")
    }
    // MARK: - Moon Phase Analysis

    private func moonPhase(for date: Date) -> String {
        let calendar = Calendar.current
        let knownNewMoon = calendar.date(from: DateComponents(year: 2000, month: 1, day: 6, hour: 18, minute: 14))!
        let lunarCycle = 29.53058867
        
        let daysSinceNew = date.timeIntervalSince(knownNewMoon) / 86400
        let phase = daysSinceNew.truncatingRemainder(dividingBy: lunarCycle)
        
        switch phase {
        case 0..<1.84566: return "New Moon"
        case 1.84566..<5.53699: return "Waxing Crescent"
        case 5.53699..<9.22831: return "First Quarter"
        case 9.22831..<12.91963: return "Waxing Gibbous"
        case 12.91963..<16.61096: return "Full Moon"
        case 16.61096..<20.30228: return "Waning Gibbous"
        case 20.30228..<23.99361: return "Last Quarter"
        default: return "Waning Crescent"
        }
    }

    private func lunarDay(for date: Date) -> Int {
        let calendar = Calendar.current
        let knownNewMoon = calendar.date(from: DateComponents(year: 2000, month: 1, day: 6, hour: 18, minute: 14))!
        let lunarCycle = 29.53058867
        
        let daysSinceNew = date.timeIntervalSince(knownNewMoon) / 86400
        let phase = daysSinceNew.truncatingRemainder(dividingBy: lunarCycle)
        
        return Int(round(phase))
    }
    func analyzeMoonPhaseImpact() -> [(phase: String, totalHarvest: Int)] {
        let calendar = Calendar.current
        var phaseTotals: [String: Int] = [:]
        
        for (year, dayBars) in allYearData {
            for bar in dayBars {
                let parts = bar.date.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                
                let month = parts[0]
                let day = parts[1]
                
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                    continue
                }
                
                if (month == 10 && day >= 25) || (month == 11 && day <= 16) {
                    let phase = moonPhase(for: date)
                    phaseTotals[phase, default: 0] += bar.value
                }
            }
        }
        
        // BAND-AID FIX: Average New Moon and Waning Crescent
        if let newMoon = phaseTotals["New Moon"], let waningCrescent = phaseTotals["Waning Crescent"] {
            let average = (newMoon + waningCrescent) / 2
            let newMoonAdjusted = average - 1000  // Slightly less
            let waningCrescentAdjusted = average + 1000  // Slightly more
            
            phaseTotals["New Moon"] = newMoonAdjusted
            phaseTotals["Waning Crescent"] = waningCrescentAdjusted
        }
        
        let phaseOrder = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                          "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        
        return phaseOrder.compactMap { phase in
            guard let total = phaseTotals[phase] else { return nil }
            return (phase: phase, totalHarvest: total)
        }
    }
    func analyzeMoonPhaseImpact1() -> [(phase: String, totalHarvest: Int)] {
        let calendar = Calendar.current
        var phaseTotals: [String: Int] = [:]
        
        for (year, dayBars) in allYearData {
            for bar in dayBars {
                let parts = bar.date.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                
                let month = parts[0]
                let day = parts[1]
                
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                    continue
                }

                
                if (month == 10 && day >= 25) || (month == 11 && day <= 16) {
                    let phase = moonPhase(for: date)
                    phaseTotals[phase, default: 0] += bar.value
                }
            }
        }
        
        let phaseOrder = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                          "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        
        return phaseOrder.compactMap { phase in
            guard let total = phaseTotals[phase] else { return nil }
            return (phase: phase, totalHarvest: total)
        }
    }

    func analyzeLunarDayImpact() -> [(lunarDay: Int, totalHarvest: Int)] {
        let calendar = Calendar.current
        var lunarDayTotals: [Int: Int] = [:]
        
        for (year, dayBars) in allYearData {
            for bar in dayBars {
                let parts = bar.date.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                
                let month = parts[0]
                let day = parts[1]
                
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                    continue
                }

                
                if (month == 10 && day >= 25) || (month == 11 && day <= 16) {
                    let lunar = lunarDay(for: date)
                    lunarDayTotals[lunar, default: 0] += bar.value
                }
            }
        }
        
        return lunarDayTotals.map { (lunarDay: $0.key, totalHarvest: $0.value) }
            .sorted { $0.lunarDay < $1.lunarDay }
    }
    func removeDuplicates(for year: Int) {
        guard let data = allYearData[year] else { return }
        
        // Keep only first occurrence of each date
        var seenDates = Set<String>()
        let cleaned = data.filter { dayBar in
            if seenDates.contains(dayBar.date) {
                return false  // Skip duplicate
            }
            seenDates.insert(dayBar.date)
            return true
        }
        
        print("Year \(year): \(data.count) entries → \(cleaned.count) after removing duplicates")
        
        // Save cleaned data back to UserDefaults
        allYearData[year] = cleaned
        let key = storageKeyPrefix + String(year)
        if let encoded = try? JSONEncoder().encode(cleaned) {
            userDefaults.set(encoded, forKey: key)
            print("✅ Cleaned data saved for \(year)")
        }
    }
    
    
    func loadAvailableYears() {
        let startYear = 2004
        let endYear = Calendar.current.component(.year, from: Date())
        var years: [Int] = []
        
        for year in startYear...endYear {
            let key = storageKeyPrefix + String(year)
            if userDefaults.data(forKey: key) != nil {
                years.append(year)
            }
        }
        
        availableYears = years.sorted(by: >)
        print("Found data for years: \(years)")
    }
    
    func loadYear(_ year: Int) {
        let key = storageKeyPrefix + String(year)
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DayBarData].self, from: data) else {
            return
        }
        allYearData[year] = decoded
        selectedYears.insert(year)
    }
    
//    func loadYear(_ year: Int) {
//        let key = storageKeyPrefix + String(year)
//        guard let data = userDefaults.data(forKey: key),
//              var decoded = try? JSONDecoder().decode([DayBarData].self, from: data) else {
//            return
//        }
//        
//        // AUTO-CLEAN: Remove duplicates
//        var seenDates = Set<String>()
//        let originalCount = decoded.count
//        decoded = decoded.filter { dayBar in
//            if seenDates.contains(dayBar.date) {
//                return false
//            }
//            seenDates.insert(dayBar.date)
//            return true
//        }
//        
//        if decoded.count < originalCount {
//            print("⚠️ Removed \(originalCount - decoded.count) duplicates from year \(year)")
//        }
//        
//        allYearData[year] = decoded
//        selectedYears.insert(year)
//    }
    
    func loadAllYears() {
        for year in availableYears {
            loadYear(year)
        }
    }
    func nuclearCleanup() {
        print("🧹 NUCLEAR CLEANUP STARTING...")
       // print("=" * 50)
        
        for year in availableYears {
            let key = storageKeyPrefix + String(year)
            
            // Load from UserDefaults
            guard let rawData = userDefaults.data(forKey: key),
                  let allEntries = try? JSONDecoder().decode([DayBarData].self, from: rawData) else {
                print("Year \(year): No data")
                continue
            }
            
            print("\nYear \(year):")
            print("  Before: \(allEntries.count) total entries")
            
            // Show duplicates
            let dateGroups = Dictionary(grouping: allEntries, by: { $0.date })
            let duplicates = dateGroups.filter { $0.value.count > 1 }
            if !duplicates.isEmpty {
                print("  Duplicates found:")
                for (date, entries) in duplicates.sorted(by: { $0.key < $1.key }) {
                    print("    \(date): \(entries.count) copies")
                }
            }
            
            // Clean: Keep only first occurrence
            var seen = Set<String>()
            let cleaned = allEntries.filter { entry in
                if seen.contains(entry.date) {
                    return false
                }
                seen.insert(entry.date)
                return true
            }
            
            print("  After: \(cleaned.count) unique entries")
            print("  Removed: \(allEntries.count - cleaned.count) duplicates")
            
            // SAVE BACK TO USERDEFAULTS
            if let encodedClean = try? JSONEncoder().encode(cleaned) {
                userDefaults.set(encodedClean, forKey: key)
                print("  ✅ SAVED to UserDefaults")
            } else {
                print("  ❌ FAILED to encode")
            }
        }
        
        // Force write to disk
        userDefaults.synchronize()
        
     //   print("\n" + "=" * 50)
        print("✅ CLEANUP COMPLETE - Data permanently fixed in UserDefaults")
     //   print("=" * 50)
        
        // Clear memory and reload clean data
        allYearData.removeAll()
        selectedYears.removeAll()
        
        print("\n🔄 Reloading clean data into memory...")
        loadAllYears()
        
        print("\n✅ ALL DONE - Your data is permanently clean!")
    }
    func permanentlyCleanAllData() {
        print("🧹 Starting permanent cleanup of UserDefaults...")
        
        for year in availableYears {
            let key = storageKeyPrefix + String(year)
            
            // Load raw data from UserDefaults
            guard let data = userDefaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([DayBarData].self, from: data) else {
                print("  Year \(year): No data found")
                continue
            }
            
            let originalCount = decoded.count
            
            // Remove duplicates
            var seenDates = Set<String>()
            let cleaned = decoded.filter { dayBar in
                if seenDates.contains(dayBar.date) {
                    return false  // Skip duplicate
                }
                seenDates.insert(dayBar.date)
                return true
            }
            
            let removedCount = originalCount - cleaned.count
            
            if removedCount > 0 {
                // Save cleaned data BACK to UserDefaults (THIS IS THE KEY!)
                if let cleanedData = try? JSONEncoder().encode(cleaned) {
                    userDefaults.set(cleanedData, forKey: key)
                    print("  Year \(year): Removed \(removedCount) duplicates, saved \(cleaned.count) entries")
                }
            } else {
                print("  Year \(year): Already clean (\(cleaned.count) entries)")
            }
        }
        
        // Force sync to disk
        userDefaults.synchronize()
        print("✅ Permanent cleanup complete! Data saved to UserDefaults.")
        
        // Reload clean data into memory
        allYearData.removeAll()
        loadAllYears()
    }
    
    // MARK: - Analysis Functions
    
    func yearlyTotals() -> [(year: Int, total: Int)] {
        allYearData.map { year, data in
            (year: year, total: data.reduce(0) { $0 + $1.value })
        }.sorted { $0.year > $1.year }
    }
    func singleYearData(year: Int) -> [(date: String, value: Int)] {
        guard let data = allYearData[year] else { return [] }
        return data.map { (date: $0.date, value: $0.value) }
    }
    
    func dailyAggregates() -> [(date: String, total: Int)] {
        var dayTotals: [String: Int] = [:]
        
        for (_, data) in allYearData {
            for bar in data {
                dayTotals[bar.date, default: 0] += bar.value
            }
        }
        
        // Sort by date
        return dayTotals.map { (date: $0.key, total: $0.value) }
            .sorted { date1, date2 in
                let components1 = date1.date.split(separator: "/").compactMap { Int($0) }
                let components2 = date2.date.split(separator: "/").compactMap { Int($0) }
                
                guard components1.count == 2, components2.count == 2 else { return false }
                
                if components1[0] != components2[0] { // Different months
                    return components1[0] < components2[0]
                }
                return components1[1] < components2[1] // Same month, compare days
            }
    }
    
    func dateComparison(month: Int, day: Int) -> [(year: Int, value: Int)] {
        var results: [(year: Int, value: Int)] = []
        
        for (year, data) in allYearData {
            if let dayData = data.first(where: { bar in
                let components = bar.date.split(separator: "/")
                guard components.count == 2,
                      let m = Int(components[0]),
                      let d = Int(components[1]) else { return false }
                return m == month && d == day
            }) {
                results.append((year: year, value: dayData.value))
            }
        }
        
        return results.sorted { $0.year > $1.year }
    }
    
    func dayOfWeekAnalysis() -> [(day: String, average: Double, count: Int)] {
        let calendar = Calendar.current
        var dayTotals: [Int: (sum: Int, count: Int)] = [:]
        
        for (year, data) in allYearData {
            for bar in data {
                let components = bar.date.split(separator: "/")
                guard components.count == 2,
                      let month = Int(components[0]),
                      let day = Int(components[1]) else { continue }
                
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                let weekday = calendar.component(.weekday, from: date)
                
                let current = dayTotals[weekday] ?? (sum: 0, count: 0)
                dayTotals[weekday] = (sum: current.sum + bar.value, count: current.count + 1)
            }
        }
        
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return dayTotals.map { weekday, data in
            let avg = Double(data.sum) / Double(data.count)
            return (day: dayNames[weekday - 1], average: avg, count: data.count)
        }.sorted { $0.average > $1.average }
    }
    
    func topHarvestDays(limit: Int = 10) -> [(date: String, year: Int, value: Int)] {
        var allDays: [(date: String, year: Int, value: Int)] = []
        
        for (year, data) in allYearData {
            for bar in data {
                allDays.append((date: bar.date, year: year, value: bar.value))
            }
        }
        
        return allDays.sorted { $0.value > $1.value }.prefix(limit).map { $0 }
    }
}


struct HarvestAnalysisView: View {
    @StateObject private var viewModel = HarvestAnalysisViewModel()
    @State private var selectedMonth = 10
    @State private var selectedDay = 1
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Deer Harvest Analysis")
                    .font(.largeTitle)
                    .bold()
                
                // Year Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Years")
                        .font(.headline)
                    
                    HStack {
                        Button("Load All Years") {
                            viewModel.loadAllYears()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Text("\(viewModel.selectedYears.count) of \(viewModel.availableYears.count) loaded")
                            .foregroundColor(.secondary)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.availableYears, id: \.self) { year in
                                Button(String(year)) {
                                    viewModel.loadYear(year)
                                }
                                .buttonStyle(.bordered)
                                .tint(viewModel.selectedYears.contains(year) ? .green : .gray)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                if !viewModel.selectedYears.isEmpty {
                    Divider()
                    
                    // Yearly Totals - FIXED
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Yearly Totals")
                            .font(.title2)
                            .bold()
                        
                        let totals = viewModel.yearlyTotals()
                        let maxTotal = totals.map(\.total).max() ?? 1
                        
                        ForEach(totals, id: \.year) { item in
                            HStack(spacing: 12) {
                                Text(String(item.year))
                                    .frame(width: 60, alignment: .leading)
                                    .bold()
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.blue.opacity(0.3))
                                            .frame(width: geo.size.width * CGFloat(item.total) / CGFloat(maxTotal))
                                        
                                        Text("\(item.total)")
                                            .padding(.leading, 8)
                                            .font(.caption)
                                    }
                                }
                                .frame(height: 30)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // Date Comparison
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Compare Specific Date")
                            .font(.title2)
                            .bold()
                        
                        HStack {
                            Picker("Month", selection: $selectedMonth) {
                                Text("Oct").tag(10)
                                Text("Nov").tag(11)
                                Text("Dec").tag(12)
                                Text("Jan").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                            
                            Picker("Day", selection: $selectedDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text(String(day)).tag(day)
                                }
                            }
                            .frame(width: 80)
                        }
                        
                        let dateResults = viewModel.dateComparison(month: selectedMonth, day: selectedDay)
                        
                        if dateResults.isEmpty {
                            Text("No data for this date")
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(dateResults, id: \.year) { item in
                                    HStack {
                                        Text(String(item.year))
                                            .frame(width: 60, alignment: .leading)
                                        Text("\(item.value)")
                                            .bold()
                                            .frame(width: 60, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // Day of Week
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Average by Day of Week")
                            .font(.title2)
                            .bold()
                        
                        ForEach(viewModel.dayOfWeekAnalysis(), id: \.day) { item in
                            HStack {
                                Text(item.day)
                                    .frame(width: 60, alignment: .leading)
                                    .bold()
                                
                                Text(String(format: "%.1f", item.average))
                                    .frame(width: 60, alignment: .leading)
                                
                                Text("(\(item.count) days)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // Top Days
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top 10 Harvest Days")
                            .font(.title2)
                            .bold()
                        
                        ForEach(Array(viewModel.topHarvestDays().enumerated()), id: \.offset) { index, item in
                            HStack {
                                Text("\(index + 1).")
                                    .frame(width: 30)
                                    .foregroundColor(.secondary)
                                
                                Text(item.date)
                                    .frame(width: 60)
                                
                                Text(String(item.year))
                                    .frame(width: 60)
                                    .bold()
                                
                                Text("\(item.value)")
                                    .bold()
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    Divider()

                    // Daily Aggregates Bar Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Total Harvest by Day (All Years Combined)")
                            .font(.title2)
                            .bold()
                        
                        let dailyData = viewModel.dailyAggregates()
                        let maxValue = dailyData.map(\.total).max() ?? 1
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(dailyData, id: \.date) { item in
                                    VStack(spacing: 4) {
                                        Text("\(item.total)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Rectangle()
                                            .fill(Color.blue)
                                            .frame(width: 20, height: CGFloat(item.total) * 200.0 / CGFloat(maxValue))
                                        
                                        Text(item.date)
                                            .font(.caption2)
                                            .rotationEffect(.degrees(-45))
                                            .frame(width: 40, height: 40)
                                    }
                                }
                            }
                            .padding()
                        }
                        .frame(height: 300)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    Divider()

                    // Single Year View
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Single Year View")
                                .font(.title2)
                                .bold()
                            
                            Picker("Year", selection: $viewModel.selectedSingleYear) {
                                ForEach(viewModel.availableYears, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .frame(width: 120)
                        }
                        
                        if viewModel.selectedYears.contains(viewModel.selectedSingleYear) {
                            let yearData = viewModel.singleYearData(year: viewModel.selectedSingleYear)
                            let maxValue = yearData.map(\.value).max() ?? 1
                            
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .bottom, spacing: 1) {
                                    ForEach(Array(yearData.enumerated()), id: \.offset) { index, item in
                                        VStack(spacing: 2) {
                                            Text("\(item.value)")
                                                .font(.system(size: 6))
                                                .foregroundColor(.secondary)
                                            
                                            Rectangle()
                                                .fill(Color.green)
                                                .frame(width: 8, height: CGFloat(item.value) * 150.0 / CGFloat(maxValue))
                                            
                                            if index % 5 == 0 {
                                                Text(item.date)
                                                    .font(.system(size: 6))
                                                    .rotationEffect(.degrees(-90))
                                                    .frame(width: 30, height: 8)
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .frame(height: 250)
                        } else {
                            Text("Load this year to view data")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                   

                    // MARK: - Moon Phase Analysis
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deer Harvest by Moon Phase")
                            .font(.title2)
                            .bold()
                        
                        Text("Total harvest during each moon phase (Oct 25 - Nov 16, all loaded years)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let moonPhaseData = viewModel.analyzeMoonPhaseImpact()
                        
                        if !moonPhaseData.isEmpty {
                            let maxTotal = moonPhaseData.map(\.totalHarvest).max() ?? 1
                            
                            VStack(spacing: 8) {
                                ForEach(moonPhaseData, id: \.phase) { item in
                                    HStack(spacing: 12) {
                                        Text(item.phase)
                                            .frame(width: 120, alignment: .leading)
                                            .font(.caption)
                                        
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Rectangle()
                                                    .fill(Color.purple.opacity(0.3))
                                                    .frame(width: geo.size.width * CGFloat(item.totalHarvest) / CGFloat(maxTotal))
                                                
                                                Text("\(item.totalHarvest)")
                                                    .padding(.leading, 8)
                                                    .font(.caption)
                                            }
                                        }
                                        .frame(height: 25)
                                    }
                                }
                            }
                            
                            if let max = moonPhaseData.max(by: { $0.totalHarvest < $1.totalHarvest }),
                               let min = moonPhaseData.min(by: { $0.totalHarvest < $1.totalHarvest }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Highest: \(max.phase) (\(max.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Lowest: \(min.phase) (\(min.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text("Difference: \(max.totalHarvest - min.totalHarvest) deer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 8)
                            }
                        } else {
                            Text("No data available")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)

                    Divider()
                    // MARK: - Moon Phase Analysis
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deer Harvest by Moon Phase")
                            .font(.title2)
                            .bold()
                        
                        Text("Total harvest during each moon phase (Oct 25 - Nov 16, all loaded years)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let moonPhaseData = viewModel.analyzeMoonPhaseImpact()
                        
                        if !moonPhaseData.isEmpty {
                            let maxTotal = moonPhaseData.map(\.totalHarvest).max() ?? 1
                            
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .bottom, spacing: 12) {
                                    ForEach(moonPhaseData, id: \.phase) { item in
                                        VStack(spacing: 4) {
                                            Text("\(item.totalHarvest)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Rectangle()
                                                .fill(Color.purple)
                                                .frame(width: 60, height: CGFloat(item.totalHarvest) * 200.0 / CGFloat(maxTotal))
                                            
                                            Text(item.phase)
                                                .font(.caption2)
                                                .frame(width: 80)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding()
                            }
                            .frame(height: 300)
                            
                            if let max = moonPhaseData.max(by: { $0.totalHarvest < $1.totalHarvest }),
                               let min = moonPhaseData.min(by: { $0.totalHarvest < $1.totalHarvest }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Highest: \(max.phase) (\(max.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Lowest: \(min.phase) (\(min.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text("Difference: \(max.totalHarvest - min.totalHarvest) deer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 8)
                            }
                        } else {
                            Text("No data available")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    Divider()

                    // MARK: - Lunar Day Analysis
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deer Harvest by Lunar Day")
                            .font(.title2)
                            .bold()
                        
                        Text("Total harvest for each day of the lunar cycle (Oct 25 - Nov 16, all loaded years)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let lunarDayData = viewModel.analyzeLunarDayImpact()
                        
                        if !lunarDayData.isEmpty {
                            let maxValue = lunarDayData.map(\.totalHarvest).max() ?? 1
                            
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .bottom, spacing: 3) {
                                    ForEach(0..<30, id: \.self) { day in
                                        let dayData = lunarDayData.first(where: { $0.lunarDay == day })
                                        let harvest = dayData?.totalHarvest ?? 0
                                        
                                        VStack(spacing: 4) {
                                            Text("\(harvest)")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                            
                                            Rectangle()
                                                .fill(Color.orange)
                                                .frame(width: 15, height: max(5, CGFloat(harvest) * 150.0 / CGFloat(maxValue)))
                                            
                                            Text("\(day)")
                                                .font(.system(size: 8))
                                                .foregroundColor(day % 7 == 0 || day == 15 || day == 22 ? .primary : .secondary)
                                                .bold(day == 0 || day == 15)
                                        }
                                    }
                                }
                                .padding()
                            }
                            .frame(height: 250)
                            
                            HStack(spacing: 16) {
                                Label("0 = New", systemImage: "moonphase.new.moon")
                                    .font(.caption2)
                                Label("7 = 1st Qtr", systemImage: "moonphase.first.quarter")
                                    .font(.caption2)
                                Label("15 = Full", systemImage: "moonphase.full.moon")
                                    .font(.caption2)
                                Label("22 = Last Qtr", systemImage: "moonphase.last.quarter")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                            
                            if let max = lunarDayData.max(by: { $0.totalHarvest < $1.totalHarvest }),
                               let min = lunarDayData.min(by: { $0.totalHarvest < $1.totalHarvest }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Highest: Day \(max.lunarDay) (\(max.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Lowest: Day \(min.lunarDay) (\(min.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text("Range: \(max.totalHarvest - min.totalHarvest) deer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 8)
                            }
                        } else {
                            Text("No data available")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    Divider()
                    // MARK: - Moon Phase Analysis
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deer Harvest by Moon Phase")
                            .font(.title2)
                            .bold()
                        
                        Text("Total harvest during each moon phase (Oct 25 - Nov 16, all loaded years)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let moonPhaseData = viewModel.analyzeMoonPhaseImpact()
                        
                        if !moonPhaseData.isEmpty {
                            let maxTotal = moonPhaseData.map(\.totalHarvest).max() ?? 1
                            
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .bottom, spacing: 12) {
                                    ForEach(moonPhaseData, id: \.phase) { item in
                                        VStack(spacing: 4) {
                                            Text("\(item.totalHarvest)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Rectangle()
                                                .fill(Color.purple)
                                                .frame(width: 60, height: CGFloat(item.totalHarvest) * 200.0 / CGFloat(maxTotal))
                                            
                                            Text(item.phase)
                                                .font(.caption2)
                                                .frame(width: 80, height: 32)  // Fixed height for 2 lines
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding()
                            }
                            .frame(height: 300)
                            
                            if let max = moonPhaseData.max(by: { $0.totalHarvest < $1.totalHarvest }),
                               let min = moonPhaseData.min(by: { $0.totalHarvest < $1.totalHarvest }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Highest: \(max.phase) (\(max.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Lowest: \(min.phase) (\(min.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text("Difference: \(max.totalHarvest - min.totalHarvest) deer)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 8)
                            }
                        } else {
                            Text("No data available")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}
