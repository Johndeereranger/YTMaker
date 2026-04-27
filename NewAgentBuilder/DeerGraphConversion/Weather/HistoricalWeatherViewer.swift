//
//  HistoricalWeatherViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/7/25.
//


import SwiftUI

struct HistoricalWeatherViewer: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var selectedYear = 2024
    @State private var selectedMonth = 10
    @State private var selectedDay = 1
    @State private var compareYear1 = 2023
    @State private var compareYear2 = 2024
    @State private var selectedSingleYear = 2024
    @State private var selectedDetailDate = Date()
    
    @State private var showCalendar = false
    @State private var showTrends = false
    @State private var showComparison = false
    @State private var showStatistics = false
    @State private var showDetails = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header
                Text("Weather History")
                    .font(.largeTitle)
                    .bold()
                
                // Load Data Button
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Fetch Historical Weather") {
                            viewModel.fetchHistoricalWeather()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.leading)
                        }
                    }
                    
                    Text("October & November 2005-2024")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                if !viewModel.weatherData.isEmpty {
                    
                    Divider()
                    
                    // SECTION 1: Calendar View
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation {
                                showCalendar.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text("Calendar View")
                                    .font(.title2)
                                    .bold()
                                Spacer()
                                Image(systemName: showCalendar ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)
                        
                        if showCalendar {
                            VStack(spacing: 16) {
                                // Year and Month Picker
                                HStack {
                                    Picker("Year", selection: $selectedYear) {
                                        ForEach(2005...2024, id: \.self) { year in
                                            Text("\(year)").tag(year)
                                        }
                                    }
                                    .frame(width: 120)
                                    
                                    Picker("Month", selection: $selectedMonth) {
                                        Text("October").tag(10)
                                        Text("November").tag(11)
                                    }
                                    .pickerStyle(.segmented)
                                }
                                
                                // Calendar Grid
                                CalendarGridView(
                                    year: selectedYear,
                                    month: selectedMonth,
                                    viewModel: viewModel
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // SECTION 2: Trends & Patterns
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation {
                                showTrends.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                Text("Trends & Patterns")
                                    .font(.title2)
                                    .bold()
                                Spacer()
                                Image(systemName: showTrends ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)
                        
                        if showTrends {
                            VStack(spacing: 20) {
                                // Average temps by day across all years
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("20-Year Temperature Averages")
                                        .font(.headline)
                                    
                                    Picker("Month", selection: $selectedMonth) {
                                        Text("October").tag(10)
                                        Text("November").tag(11)
                                    }
                                    .pickerStyle(.segmented)
                                    
                                    let avgData = calculateDailyAverages(month: selectedMonth)
                                    let maxHigh = avgData.map(\.avgHigh).max() ?? 100
                                    let minLow = avgData.map(\.avgLow).min() ?? 0
                                    
                                    ScrollView(.horizontal, showsIndicators: true) {
                                        HStack(alignment: .bottom, spacing: 2) {
                                            ForEach(avgData, id: \.day) { item in
                                                VStack(spacing: 2) {
                                                    Text(String(format: "%.0f", item.avgHigh))
                                                        .font(.system(size: 8))
                                                        .foregroundColor(.red)
                                                    
                                                    VStack(spacing: 0) {
                                                        Rectangle()
                                                            .fill(Color.red.opacity(0.6))
                                                            .frame(width: 15, height: CGFloat(item.avgHigh - item.avgLow) * 100.0 / CGFloat(maxHigh - minLow))
                                                    }
                                                    
                                                    Text(String(format: "%.0f", item.avgLow))
                                                        .font(.system(size: 8))
                                                        .foregroundColor(.blue)
                                                    
                                                    if item.day % 5 == 1 {
                                                        Text("\(item.day)")
                                                            .font(.system(size: 8))
                                                    }
                                                }
                                            }
                                        }
                                        .padding()
                                    }
                                    .frame(height: 200)
                                }
                                
                                // Year-over-year totals
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Average Monthly Temperature by Year")
                                        .font(.headline)
                                    
                                    let yearlyAvgs = calculateYearlyAverages(month: selectedMonth)
                                    let maxAvg = yearlyAvgs.map(\.avgTemp).max() ?? 100
                                    
                                    ForEach(yearlyAvgs, id: \.year) { item in
                                        HStack(spacing: 12) {
                                            Text(String(item.year))
                                                .frame(width: 60, alignment: .leading)
                                                .bold()
                                            
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.orange.opacity(0.3))
                                                        .frame(width: geo.size.width * CGFloat(item.avgTemp) / CGFloat(maxAvg))
                                                    
                                                    Text(String(format: "%.1f°", item.avgTemp))
                                                        .padding(.leading, 8)
                                                        .font(.caption)
                                                }
                                            }
                                            .frame(height: 30)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // SECTION 3: Year Comparison
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation {
                                showComparison.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.split.2x1")
                                Text("Compare Years")
                                    .font(.title2)
                                    .bold()
                                Spacer()
                                Image(systemName: showComparison ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)
                        
                        if showComparison {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack {
                                        Text("Year 1")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Picker("Year 1", selection: $compareYear1) {
                                            ForEach(2005...2024, id: \.self) { year in
                                                Text("\(year)").tag(year)
                                            }
                                        }
                                        .frame(width: 100)
                                    }
                                    
                                    Text("vs")
                                        .foregroundColor(.secondary)
                                    
                                    VStack {
                                        Text("Year 2")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Picker("Year 2", selection: $compareYear2) {
                                            ForEach(2005...2024, id: \.self) { year in
                                                Text("\(year)").tag(year)
                                            }
                                        }
                                        .frame(width: 100)
                                    }
                                }
                                
                                Picker("Month", selection: $selectedMonth) {
                                    Text("October").tag(10)
                                    Text("November").tag(11)
                                }
                                .pickerStyle(.segmented)
                                
                                // Comparison Metrics
                                VStack(spacing: 12) {
                                    ComparisonRow(
                                        label: "Avg High",
                                        value1: getYearAvgHigh(year: compareYear1, month: selectedMonth),
                                        value2: getYearAvgHigh(year: compareYear2, month: selectedMonth),
                                        unit: "°"
                                    )
                                    
                                    ComparisonRow(
                                        label: "Avg Low",
                                        value1: getYearAvgLow(year: compareYear1, month: selectedMonth),
                                        value2: getYearAvgLow(year: compareYear2, month: selectedMonth),
                                        unit: "°"
                                    )
                                    
                                    ComparisonRow(
                                        label: "Total Precip",
                                        value1: getYearTotalPrecip(year: compareYear1, month: selectedMonth),
                                        value2: getYearTotalPrecip(year: compareYear2, month: selectedMonth),
                                        unit: " in"
                                    )
                                    
                                    ComparisonRow(
                                        label: "Avg Wind",
                                        value1: getYearAvgWind(year: compareYear1, month: selectedMonth),
                                        value2: getYearAvgWind(year: compareYear2, month: selectedMonth),
                                        unit: " mph"
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // SECTION 4: Statistics
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation {
                                showStatistics.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "number")
                                Text("All-Time Statistics")
                                    .font(.title2)
                                    .bold()
                                Spacer()
                                Image(systemName: showStatistics ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)
                        
                        if showStatistics {
                            VStack(spacing: 16) {
                                Picker("Month", selection: $selectedMonth) {
                                    Text("October").tag(10)
                                    Text("November").tag(11)
                                }
                                .pickerStyle(.segmented)
                                
                                // Temperature Stats
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Temperature Records")
                                        .font(.headline)
                                    
                                    StatRow(label: "Highest Ever", value: getHighestTemp(month: selectedMonth), icon: "arrow.up", color: .red)
                                    StatRow(label: "Lowest Ever", value: getLowestTemp(month: selectedMonth), icon: "arrow.down", color: .blue)
                                    StatRow(label: "Avg High", value: getOverallAvgHigh(month: selectedMonth), icon: "thermometer.sun", color: .orange)
                                    StatRow(label: "Avg Low", value: getOverallAvgLow(month: selectedMonth), icon: "thermometer.snowflake", color: .cyan)
                                }
                                .padding()
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(8)
                                
                                // Precipitation Stats
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Precipitation Records")
                                        .font(.headline)
                                    
                                    StatRow(label: "Total (20 years)", value: getTotalPrecip(month: selectedMonth), icon: "drop.fill", color: .blue)
                                    StatRow(label: "Rainiest Year", value: getRainiestYear(month: selectedMonth), icon: "cloud.rain.fill", color: .indigo)
                                    StatRow(label: "Days with Rain", value: getDaysWithRain(month: selectedMonth), icon: "calendar", color: .teal)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(8)
                                
                                // Wind & Other
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Other Conditions")
                                        .font(.headline)
                                    
                                    StatRow(label: "Avg Wind Speed", value: getAvgWind(month: selectedMonth), icon: "wind", color: .gray)
                                    StatRow(label: "Avg Humidity", value: getAvgHumidity(month: selectedMonth), icon: "humidity", color: .mint)
                                    StatRow(label: "Avg Cloud Cover", value: getAvgCloudCover(month: selectedMonth), icon: "cloud", color: .gray)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    Divider()
                    
                    // SECTION 5: Single Date Details
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation {
                                showDetails.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Specific Date Lookup")
                                    .font(.title2)
                                    .bold()
                                Spacer()
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            }
                        }
                        .foregroundColor(.primary)
                        
                        if showDetails {
                            VStack(spacing: 16) {
                                // Date Picker
                                HStack {
                                    Picker("Month", selection: $selectedMonth) {
                                        Text("Oct").tag(10)
                                        Text("Nov").tag(11)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 150)
                                    
                                    Picker("Day", selection: $selectedDay) {
                                        ForEach(1...(selectedMonth == 10 ? 31 : 30), id: \.self) { day in
                                            Text("\(day)").tag(day)
                                        }
                                    }
                                    .frame(width: 80)
                                }
                                
                                // Show data for this date across all years
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("This Date Across All Years")
                                        .font(.headline)
                                    
                                    let dateData = getDateAcrossYears(month: selectedMonth, day: selectedDay)
                                    
                                    if dateData.isEmpty {
                                        Text("No data for this date")
                                            .foregroundColor(.secondary)
                                    } else {
                                        ScrollView {
                                            ForEach(dateData, id: \.year) { item in
                                                HStack {
                                                    Text(String(item.year))
                                                        .frame(width: 60, alignment: .leading)
                                                        .bold()
                                                    
                                                    Text("High: \(item.high)°")
                                                        .frame(width: 80, alignment: .leading)
                                                        .foregroundColor(.red)
                                                    
                                                    Text("Low: \(item.low)°")
                                                        .frame(width: 80, alignment: .leading)
                                                        .foregroundColor(.blue)
                                                    
                                                    if let conditions = item.conditions {
                                                        Text(conditions)
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .padding(.vertical, 4)
                                            }
                                        }
                                        .frame(maxHeight: 300)
                                    }
                                }
                            }
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
    
    // MARK: - Helper Functions
    
    private func getDatesForMonth(year: Int, month: Int) -> [Date] {
        let calendar = Calendar.current
        let daysInMonth = month == 10 ? 31 : 30
        return (1...daysInMonth).compactMap { day in
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
    }
    
    private func getAllDatesForMonth(month: Int) -> [Date] {
        var allDates: [Date] = []
        for year in 2005...2024 {
            allDates.append(contentsOf: getDatesForMonth(year: year, month: month))
        }
        return allDates
    }
    
    struct DailyAverage {
        let day: Int
        let avgHigh: Double
        let avgLow: Double
    }
    
    private func calculateDailyAverages(month: Int) -> [DailyAverage] {
        let daysInMonth = month == 10 ? 31 : 30
        var results: [DailyAverage] = []
        
        for day in 1...daysInMonth {
            var highs: [Int] = []
            var lows: [Int] = []
            
            for year in 2005...2024 {
                if let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                   let data = viewModel.getWeatherData(for: date) {
                    highs.append(data.high)
                    lows.append(data.low)
                }
            }
            
            if !highs.isEmpty {
                let avgHigh = Double(highs.reduce(0, +)) / Double(highs.count)
                let avgLow = Double(lows.reduce(0, +)) / Double(lows.count)
                results.append(DailyAverage(day: day, avgHigh: avgHigh, avgLow: avgLow))
            }
        }
        
        return results
    }
    
    struct YearlyAverage {
        let year: Int
        let avgTemp: Double
    }
    
    private func calculateYearlyAverages(month: Int) -> [YearlyAverage] {
        var results: [YearlyAverage] = []
        
        for year in 2005...2024 {
            let dates = getDatesForMonth(year: year, month: month)
            var temps: [Double] = []
            
            for date in dates {
                if let data = viewModel.getWeatherData(for: date) {
                    temps.append(Double(data.high + data.low) / 2.0)
                }
            }
            
            if !temps.isEmpty {
                let avg = temps.reduce(0, +) / Double(temps.count)
                results.append(YearlyAverage(year: year, avgTemp: avg))
            }
        }
        
        return results
    }
    
    private func getYearAvgHigh(year: Int, month: Int) -> String {
        let dates = getDatesForMonth(year: year, month: month)
        let highs = dates.compactMap { viewModel.getWeatherData(for: $0)?.high }
        guard !highs.isEmpty else { return "—" }
        let avg = Double(highs.reduce(0, +)) / Double(highs.count)
        return String(format: "%.1f", avg)
    }
    
    private func getYearAvgLow(year: Int, month: Int) -> String {
        let dates = getDatesForMonth(year: year, month: month)
        let lows = dates.compactMap { viewModel.getWeatherData(for: $0)?.low }
        guard !lows.isEmpty else { return "—" }
        let avg = Double(lows.reduce(0, +)) / Double(lows.count)
        return String(format: "%.1f", avg)
    }
    
    private func getYearTotalPrecip(year: Int, month: Int) -> String {
        let dates = getDatesForMonth(year: year, month: month)
        let precips = dates.compactMap { viewModel.getWeatherData(for: $0)?.precip }
        let total = precips.reduce(0, +)
        return String(format: "%.2f", total)
    }
    
    private func getYearAvgWind(year: Int, month: Int) -> String {
        let dates = getDatesForMonth(year: year, month: month)
        let winds = dates.compactMap { viewModel.getWeatherData(for: $0)?.windspeed }
        guard !winds.isEmpty else { return "—" }
        let avg = winds.reduce(0, +) / Double(winds.count)
        return String(format: "%.1f", avg)
    }
    
    private func getHighestTemp(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let temps = dates.compactMap { viewModel.getWeatherData(for: $0)?.high }
        guard let max = temps.max() else { return "—" }
        return "\(max)°"
    }
    
    private func getLowestTemp(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let temps = dates.compactMap { viewModel.getWeatherData(for: $0)?.low }
        guard let min = temps.min() else { return "—" }
        return "\(min)°"
    }
    
    private func getOverallAvgHigh(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let highs = dates.compactMap { viewModel.getWeatherData(for: $0)?.high }
        guard !highs.isEmpty else { return "—" }
        let avg = Double(highs.reduce(0, +)) / Double(highs.count)
        return String(format: "%.1f°", avg)
    }
    
    private func getOverallAvgLow(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let lows = dates.compactMap { viewModel.getWeatherData(for: $0)?.low }
        guard !lows.isEmpty else { return "—" }
        let avg = Double(lows.reduce(0, +)) / Double(lows.count)
        return String(format: "%.1f°", avg)
    }
    
    private func getTotalPrecip(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let precips = dates.compactMap { viewModel.getWeatherData(for: $0)?.precip }
        let total = precips.reduce(0, +)
        return String(format: "%.2f in", total)
    }
    
    private func getRainiestYear(month: Int) -> String {
        var yearTotals: [Int: Double] = [:]
        for year in 2005...2024 {
            let dates = getDatesForMonth(year: year, month: month)
            let total = dates.compactMap { viewModel.getWeatherData(for: $0)?.precip }.reduce(0, +)
            yearTotals[year] = total
        }
        guard let rainiest = yearTotals.max(by: { $0.value < $1.value }) else { return "—" }
        return "\(rainiest.key)"
    }
    
    private func getDaysWithRain(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let rainyDays = dates.filter {
            if let precip = viewModel.getWeatherData(for: $0)?.precip {
                return precip > 0
            }
            return false
        }
        return "\(rainyDays.count)"
    }
    
    private func getAvgWind(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let winds = dates.compactMap { viewModel.getWeatherData(for: $0)?.windspeed }
        guard !winds.isEmpty else { return "—" }
        let avg = winds.reduce(0, +) / Double(winds.count)
        return String(format: "%.1f mph", avg)
    }
    
    private func getAvgHumidity(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let humidities = dates.compactMap { viewModel.getWeatherData(for: $0)?.humidity }
        guard !humidities.isEmpty else { return "—" }
        let avg = humidities.reduce(0, +) / Double(humidities.count)
        return String(format: "%.1f%%", avg)
    }
    
    private func getAvgCloudCover(month: Int) -> String {
        let dates = getAllDatesForMonth(month: month)
        let clouds = dates.compactMap { viewModel.getWeatherData(for: $0)?.cloudcover }
        guard !clouds.isEmpty else { return "—" }
        let avg = clouds.reduce(0, +) / Double(clouds.count)
        return String(format: "%.1f%%", avg)
    }
    
    struct DateYearData {
        let year: Int
        let high: Int
        let low: Int
        let conditions: String?
    }
    
    private func getDateAcrossYears(month: Int, day: Int) -> [DateYearData] {
        var results: [DateYearData] = []
        
        for year in 2005...2024 {
            if let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
               let data = viewModel.getWeatherData(for: date) {
                results.append(DateYearData(
                    year: year,
                    high: data.high,
                    low: data.low,
                    conditions: data.conditions
                ))
            }
        }
        
        return results
    }
}

// MARK: - Supporting Views

struct CalendarGridView: View {
    let year: Int
    let month: Int
    @ObservedObject var viewModel: WeatherViewModel
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            // Day headers
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            // Calendar days
            ForEach(getDaysInMonth(), id: \.self) { date in
                if let date = date {
                    VStack(spacing: 2) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        if let data = viewModel.getWeatherData(for: date) {
                            Text("\(data.high)°")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text("\(data.low)°")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    Color.clear
                }
            }
        }
    }
    
    private func getDaysInMonth() -> [Date?] {
        var days: [Date?] = []
        let calendar = Calendar.current
        
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return days
        }
        
        let weekday = calendar.component(.weekday, from: firstDay)
        
        // Add empty spaces for days before month starts
        for _ in 1..<weekday {
            days.append(nil)
        }
        
        let daysInMonth = month == 10 ? 31 : 30
        for day in 1...daysInMonth {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                days.append(date)
            }
        }
        
        return days
    }
}

struct ComparisonRow: View {
    let label: String
    let value1: String
    let value2: String
    let unit: String
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundColor(.secondary)
            
            Text("\(value1)\(unit)")
                .frame(width: 80, alignment: .trailing)
                .fontWeight(.semibold)
            
            Image(systemName: "arrow.left.arrow.right")
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            Text("\(value2)\(unit)")
                .frame(width: 80, alignment: .leading)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }
}