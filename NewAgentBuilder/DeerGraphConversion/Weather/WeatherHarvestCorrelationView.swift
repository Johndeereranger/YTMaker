//
//  WeatherHarvestCorrelationView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/9/25.
//

import SwiftUI



struct WeatherHarvestCorrelationView: View {
    @StateObject private var harvestVM = HarvestAnalysisViewModel()
    
    @State private var showColdFront = false
    @State private var showRutIntensity = false
    @State private var showMoonPhase = false
    @State private var showGeneralCorrelations = false
    
    @State private var selectedYear = 2024
    @State private var coldFrontThreshold = 10.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Weather-Harvest Correlations")
                    .font(.largeTitle)
                    .bold()
                
                Divider()
                
                // SECTION 1: October Cold Front Analysis
                // SECTION 1: October Cold Front Analysis
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation {
                            showColdFront.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "thermometer.snowflake")
                            Text("October Cold Front Impact")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: showColdFront ? "chevron.up" : "chevron.down")
                        }
                    }
                    .foregroundColor(.primary)
                    
                    if showColdFront {
                        ColdFrontContent(harvestVM: harvestVM, coldFrontThreshold: $coldFrontThreshold)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                
                // SECTION 2: Rut Intensity (Oct 25 - Nov 17)
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation {
                            showRutIntensity.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                            Text("Rut Intensity Analysis")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: showRutIntensity ? "chevron.up" : "chevron.down")
                        }
                    }
                    .foregroundColor(.primary)
                    
                    if showRutIntensity {
                        VStack(spacing: 16) {
                            Text("Oct 25 - Nov 17 | Testing: Colder weather = more harvest")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Year", selection: $selectedYear) {
                                ForEach(2005...2024, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            
                            // Temperature vs Harvest overlay chart
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Temperature & Harvest Overlay")
                                    .font(.headline)
                                
                                let rutData = getRutPeriodData(year: selectedYear)
                                
                                ScrollView(.horizontal, showsIndicators: true) {
                                    HStack(alignment: .bottom, spacing: 3) {
                                        ForEach(rutData, id: \.date) { item in
                                            VStack(spacing: 2) {
                                                // Harvest bar
                                                Rectangle()
                                                    .fill(Color.green.opacity(0.6))
                                                    .frame(width: 15, height: CGFloat(item.harvest) * 2)
                                                
                                                // Temperature indicator
                                                Circle()
                                                    .fill(item.avgTemp < 40 ? Color.blue : Color.orange)
                                                    .frame(width: 8, height: 8)
                                                
                                                Text(item.dateLabel)
                                                    .font(.system(size: 6))
                                                    .rotationEffect(.degrees(-45))
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .frame(height: 250)
                            }
                            
                            // Peak and Lull Detection
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Peak & Lull Detection")
                                    .font(.headline)
                                
                                if let peak = findRutPeak(year: selectedYear) {
                                    HStack {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Peak: \(peak.dateStr)")
                                        Spacer()
                                        Text("\(peak.harvest) deer")
                                            .bold()
                                        Text("Temp: \(Int(peak.temp))°")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color.green.opacity(0.05))
                                    .cornerRadius(8)
                                }
                                
                                if let lull = findRutLull(year: selectedYear) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundColor(.orange)
                                        Text("Lull: \(lull.dateStr)")
                                        Spacer()
                                        Text("\(lull.harvest) deer")
                                            .bold()
                                        Text("Temp: \(Int(lull.temp))°")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color.orange.opacity(0.05))
                                    .cornerRadius(8)
                                }
                            }
                            
                            // Temperature correlation
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Does Cold = More Harvest?")
                                    .font(.headline)
                                
                                let correlation = calculateTempHarvestCorrelation(year: selectedYear)
                                
                                HStack {
                                    Text("Correlation:")
                                    Spacer()
                                    Text(String(format: "%.2f", correlation))
                                        .bold()
                                        .foregroundColor(correlation < -0.3 ? .green : .orange)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                                
                                Text("Negative = colder means more harvest\nPositive = warmer means more harvest")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                
                // SECTION 3: Moon Phase Analysis
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation {
                            showMoonPhase.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                            Text("Moon Phase Impact")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: showMoonPhase ? "chevron.up" : "chevron.down")
                        }
                    }
                    .foregroundColor(.primary)
                    
                    if showMoonPhase {
                        VStack(spacing: 16) {
                            // October Moon vs Harvest
                            VStack(alignment: .leading, spacing: 8) {
                                Text("October: Lunar Day vs Harvest")
                                    .font(.headline)
                                
                                Text("Does moon phase correlate with harvest in October?")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                let octoberMoonData = getMoonHarvestData(month: 10)
                                
                                ScrollView(.horizontal, showsIndicators: true) {
                                    HStack(alignment: .bottom, spacing: 2) {
                                        ForEach(octoberMoonData, id: \.lunarDay) { item in
                                            VStack {
                                                Text("\(item.avgHarvest)")
                                                    .font(.system(size: 8))
                                                
                                                Rectangle()
                                                    .fill(Color.purple.opacity(0.6))
                                                    .frame(width: 12, height: CGFloat(item.avgHarvest) * 3)
                                                
                                                Text("L\(item.lunarDay)")
                                                    .font(.system(size: 7))
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .frame(height: 200)
                            }
                            
                            // November Rut Moon Analysis
                            VStack(alignment: .leading, spacing: 8) {
                                Text("November Rut: Moon Influence")
                                    .font(.headline)
                                
                                Text("Does moon phase shift the peak or intensify the rut?")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                let rutMoonAnalysis = analyzeRutByMoonPhase()
                                
                                ForEach(rutMoonAnalysis, id: \.phase) { item in
                                    HStack {
                                        Text(item.phase)
                                            .frame(width: 100, alignment: .leading)
                                        
                                        Text("Avg: \(String(format: "%.1f", item.avgHarvest))")
                                            .frame(width: 80)
                                        
                                        Text("Peak shift: \(item.peakShift) days")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            
                            // Moon correlation summary
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Finding")
                                    .font(.headline)
                                
                                Text("Moon phase correlation: [Analysis]")
                                    .padding()
                                    .background(Color.purple.opacity(0.05))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                
                // SECTION 4: General Weather Correlations
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation {
                            showGeneralCorrelations.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "wind")
                            Text("Weather Factor Correlations")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: showGeneralCorrelations ? "chevron.up" : "chevron.down")
                        }
                    }
                    .foregroundColor(.primary)
                    
                    if showGeneralCorrelations {
                        VStack(spacing: 16) {
                            Text("How different weather factors correlate with harvest")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Year", selection: $selectedYear) {
                                ForEach(2005...2024, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            
                            let correlations = calculateAllCorrelations(year: selectedYear)
                            
                            VStack(spacing: 8) {
                                CorrelationRow(
                                    factor: "Wind Speed",
                                    correlation: correlations.windSpeed,
                                    interpretation: getInterpretation(correlations.windSpeed)
                                )
                                
                                CorrelationRow(
                                    factor: "High Temp",
                                    correlation: correlations.highTemp,
                                    interpretation: getInterpretation(correlations.highTemp)
                                )
                                
                                CorrelationRow(
                                    factor: "Low Temp",
                                    correlation: correlations.lowTemp,
                                    interpretation: getInterpretation(correlations.lowTemp)
                                )
                                
                                CorrelationRow(
                                    factor: "Avg Temp",
                                    correlation: correlations.avgTemp,
                                    interpretation: getInterpretation(correlations.avgTemp)
                                )
                                
                                CorrelationRow(
                                    factor: "Pressure",
                                    correlation: correlations.pressure,
                                    interpretation: getInterpretation(correlations.pressure)
                                )
                                
                                CorrelationRow(
                                    factor: "Humidity",
                                    correlation: correlations.humidity,
                                    interpretation: getInterpretation(correlations.humidity)
                                )
                                
                                CorrelationRow(
                                    factor: "Precipitation",
                                    correlation: correlations.precip,
                                    interpretation: getInterpretation(correlations.precip)
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
            harvestVM.loadAllYears()
        }
    }
    
    // MARK: - Helper Functions
    
    struct ColdFrontData {
        let day: Int
        let tempDrop: Double
        let harvestIncrease: Int
    }
    
    private func detectColdFront(year: Int, threshold: Double) -> ColdFrontData? {
        // Scan October for first significant temp drop
        for day in 1...30 {
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day)),
                  let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date),
                  let todayWeather = HighLowManager.shared.getWeatherData(for: date),
                  let tomorrowWeather = HighLowManager.shared.getWeatherData(for: nextDate) else {
                continue
            }
            
            let tempDrop = Double(todayWeather.high - tomorrowWeather.high)
            
            if tempDrop >= threshold {
                // Calculate harvest increase in next 3 days
                let harvestIncrease = calculateHarvestSpike(startDate: nextDate)
                return ColdFrontData(day: day, tempDrop: tempDrop, harvestIncrease: harvestIncrease)
            }
        }
        return nil
    }
    
    private func calculateHarvestSpike(startDate: Date) -> Int {
        // Get harvest for 3 days after cold front
        var total = 0
        for i in 0...2 {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: startDate) {
                // Get harvest data for this date from harvest VM
                let components = Calendar.current.dateComponents([.month, .day], from: date)
                if let month = components.month, let day = components.day {
                    let dateResults = harvestVM.dateComparison(month: month, day: day)
                    total += dateResults.reduce(0) { $0 + $1.value }
                }
            }
        }
        return total
    }
    
    struct RutDayData {
        let date: Date
        let dateLabel: String
        let avgTemp: Double
        let harvest: Int
    }
    
    private func getRutPeriodData(year: Int) -> [RutDayData] {
        var results: [RutDayData] = []
        
        // Oct 25 - Nov 17
        let startDate = Calendar.current.date(from: DateComponents(year: year, month: 10, day: 25))!
        
        for dayOffset in 0...23 { // 24 days total
            if let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: startDate),
               let weather = HighLowManager.shared.getWeatherData(for: date) {
                
                let avgTemp = Double(weather.high + weather.low) / 2.0
                
                // Get harvest for this date
                let components = Calendar.current.dateComponents([.month, .day], from: date)
                var harvest = 0
                if let month = components.month, let day = components.day {
                    let dateResults = harvestVM.dateComparison(month: month, day: day)
                    if let yearData = dateResults.first(where: { $0.year == year }) {
                        harvest = yearData.value
                    }
                }
                
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d"
                
                results.append(RutDayData(
                    date: date,
                    dateLabel: formatter.string(from: date),
                    avgTemp: avgTemp,
                    harvest: harvest
                ))
            }
        }
        
        return results
    }
    
    struct PeakLullData {
        let dateStr: String
        let harvest: Int
        let temp: Double
    }
    
    private func findRutPeak(year: Int) -> PeakLullData? {
        let rutData = getRutPeriodData(year: year)
        guard let peak = rutData.max(by: { $0.harvest < $1.harvest }) else { return nil }
        
        return PeakLullData(
            dateStr: peak.dateLabel,
            harvest: peak.harvest,
            temp: peak.avgTemp
        )
    }
    
    private func findRutLull(year: Int) -> PeakLullData? {
        // Find lull around Nov 8-11
        let rutData = getRutPeriodData(year: year)
        let nov8to11 = rutData.filter { day in
            let components = Calendar.current.dateComponents([.month, .day], from: day.date)
            return components.month == 11 && (8...11).contains(components.day!)
        }
        
        guard let lull = nov8to11.min(by: { $0.harvest < $1.harvest }) else { return nil }
        
        return PeakLullData(
            dateStr: lull.dateLabel,
            harvest: lull.harvest,
            temp: lull.avgTemp
        )
    }
    
    private func calculateTempHarvestCorrelation(year: Int) -> Double {
        let rutData = getRutPeriodData(year: year)
        
        // Calculate Pearson correlation between temp and harvest
        let temps = rutData.map { $0.avgTemp }
        let harvests = rutData.map { Double($0.harvest) }
        
        guard temps.count > 1 else { return 0 }
        
        let tempMean = temps.reduce(0, +) / Double(temps.count)
        let harvestMean = harvests.reduce(0, +) / Double(harvests.count)
        
        var numerator = 0.0
        var tempSumSq = 0.0
        var harvestSumSq = 0.0
        
        for i in 0..<temps.count {
            let tempDiff = temps[i] - tempMean
            let harvestDiff = harvests[i] - harvestMean
            numerator += tempDiff * harvestDiff
            tempSumSq += tempDiff * tempDiff
            harvestSumSq += harvestDiff * harvestDiff
        }
        
        let denominator = sqrt(tempSumSq * harvestSumSq)
        
        return denominator == 0 ? 0 : numerator / denominator
    }
    
    struct MoonHarvestData {
        let lunarDay: Int
        let avgHarvest: Int
    }
    
    private func getMoonHarvestData(month: Int) -> [MoonHarvestData] {
        var moonData: [Int: [Int]] = [:] // lunarDay: [harvests]
        
        // Collect harvest data by moon phase for October
        for year in 2005...2024 {
            for day in 1...31 {
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                      let weather = HighLowManager.shared.getWeatherData(for: date),
                      let moonphase = weather.moonphase else {
                    continue
                }
                
                // Convert moonphase (0-1) to lunar day (0-29)
                let lunarDay = Int(moonphase * 29.53)
                
                // Get harvest for this date
                let dateResults = harvestVM.dateComparison(month: month, day: day)
                if let yearData = dateResults.first(where: { $0.year == year }) {
                    if moonData[lunarDay] == nil {
                        moonData[lunarDay] = []
                    }
                    moonData[lunarDay]?.append(yearData.value)
                }
            }
        }
        
        // Calculate averages
        var results: [MoonHarvestData] = []
        for lunarDay in 0...29 {
            if let harvests = moonData[lunarDay], !harvests.isEmpty {
                let avg = harvests.reduce(0, +) / harvests.count
                results.append(MoonHarvestData(lunarDay: lunarDay, avgHarvest: avg))
            } else {
                results.append(MoonHarvestData(lunarDay: lunarDay, avgHarvest: 0))
            }
        }
        
        return results
    }
    
    struct RutMoonAnalysis {
        let phase: String
        let avgHarvest: Double
        let peakShift: Int
    }
    
    private func analyzeRutByMoonPhase() -> [RutMoonAnalysis] {
        var phaseData: [String: [Int]] = [
            "New Moon": [],
            "First Quarter": [],
            "Full Moon": [],
            "Last Quarter": []
        ]
        
        // Collect harvest during rut period by moon phase
        for year in 2005...2024 {
            for day in 25...31 { // Oct 25-31
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: 10, day: day)),
                      let weather = HighLowManager.shared.getWeatherData(for: date),
                      let moonphase = weather.moonphase else {
                    continue
                }
                
                let phase = getMoonPhaseName(moonphase)
                let dateResults = harvestVM.dateComparison(month: 10, day: day)
                if let yearData = dateResults.first(where: { $0.year == year }) {
                    phaseData[phase]?.append(yearData.value)
                }
            }
            
            for day in 1...17 { // Nov 1-17
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: 11, day: day)),
                      let weather = HighLowManager.shared.getWeatherData(for: date),
                      let moonphase = weather.moonphase else {
                    continue
                }
                
                let phase = getMoonPhaseName(moonphase)
                let dateResults = harvestVM.dateComparison(month: 11, day: day)
                if let yearData = dateResults.first(where: { $0.year == year }) {
                    phaseData[phase]?.append(yearData.value)
                }
            }
        }
        
        // Calculate averages
        var results: [RutMoonAnalysis] = []
        for (phase, harvests) in phaseData {
            let avg = harvests.isEmpty ? 0 : Double(harvests.reduce(0, +)) / Double(harvests.count)
            results.append(RutMoonAnalysis(phase: phase, avgHarvest: avg, peakShift: 0)) // peakShift calculation TBD
        }
        
        return results.sorted { $0.phase < $1.phase }
    }
    
    private func getMoonPhaseName(_ phase: Double) -> String {
        switch phase {
        case 0..<0.125, 0.875...1.0: return "New Moon"
        case 0.125..<0.375: return "First Quarter"
        case 0.375..<0.625: return "Full Moon"
        case 0.625..<0.875: return "Last Quarter"
        default: return "New Moon"
        }
    }
    
    struct WeatherCorrelations {
        let windSpeed: Double
        let highTemp: Double
        let lowTemp: Double
        let avgTemp: Double
        let pressure: Double
        let humidity: Double
        let precip: Double
    }
    
    private func calculateAllCorrelations(year: Int) -> WeatherCorrelations {
        var temps: [Double] = []
        var highs: [Double] = []
        var lows: [Double] = []
        var winds: [Double] = []
        var pressures: [Double] = []
        var humidities: [Double] = []
        var precips: [Double] = []
        var harvests: [Double] = []
        
        // Collect data for Oct-Nov
        for month in 10...11 {
            let days = month == 10 ? 31 : 30
            for day in 1...days {
                guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                      let weather = HighLowManager.shared.getWeatherData(for: date) else {
                    continue
                }
                
                let dateResults = harvestVM.dateComparison(month: month, day: day)
                guard let yearData = dateResults.first(where: { $0.year == year }) else {
                    continue
                }
                
                temps.append(Double(weather.high + weather.low) / 2.0)
                highs.append(Double(weather.high))
                lows.append(Double(weather.low))
                if let wind = weather.windspeed { winds.append(wind) }
                if let pressure = weather.pressure { pressures.append(pressure) }
                if let humidity = weather.humidity { humidities.append(humidity) }
                if let precip = weather.precip { precips.append(precip) }
                harvests.append(Double(yearData.value))
            }
        }
        
        return WeatherCorrelations(
            windSpeed: calculateCorrelation(winds, harvests),
            highTemp: calculateCorrelation(highs, harvests),
            lowTemp: calculateCorrelation(lows, harvests),
            avgTemp: calculateCorrelation(temps, harvests),
            pressure: calculateCorrelation(pressures, harvests),
            humidity: calculateCorrelation(humidities, harvests),
            precip: calculateCorrelation(precips, harvests)
        )
    }
    
    private func calculateCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count && x.count > 1 else { return 0 }
        
        let xMean = x.reduce(0, +) / Double(x.count)
        let yMean = y.reduce(0, +) / Double(y.count)
        
        var numerator = 0.0
        var xSumSq = 0.0
        var ySumSq = 0.0
        
        for i in 0..<x.count {
            let xDiff = x[i] - xMean
            let yDiff = y[i] - yMean
            numerator += xDiff * yDiff
            xSumSq += xDiff * xDiff
            ySumSq += yDiff * yDiff
        }
        
        let denominator = sqrt(xSumSq * ySumSq)
        
        return denominator == 0 ? 0 : numerator / denominator
    }
    
    private func getInterpretation(_ value: Double) -> String {
        if abs(value) < 0.2 {
            return "Weak"
        } else if abs(value) < 0.4 {
            return "Moderate"
        } else {
            return "Strong"
        }
    }
}

// MARK: - Supporting Views

struct CorrelationRow: View {
    let factor: String
    let correlation: Double
    let interpretation: String
    
    var body: some View {
        HStack {
            Text(factor)
                .frame(width: 120, alignment: .leading)
            
            Text(String(format: "%.2f", correlation))
                .frame(width: 60)
                .fontWeight(.semibold)
                .foregroundColor(correlationColor)
            
            Text(interpretation)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Image(systemName: correlation < 0 ? "arrow.down" : "arrow.up")
                .foregroundColor(correlationColor)
        }
        .padding(.vertical, 4)
    }
    
    private var correlationColor: Color {
        if abs(correlation) < 0.2 {
            return .gray
        } else if abs(correlation) < 0.4 {
            return .orange
        } else {
            return correlation < 0 ? .blue : .red
        }
    }
}
