//
//  CSVExporter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//
import Foundation
import SwiftUI

class CSVExporter {
    private let harvestViewModel: HarvestAnalysisViewModel
    private let weatherManager: HighLowManager
    
    init(harvestViewModel: HarvestAnalysisViewModel, weatherManager: HighLowManager = .shared) {
        self.harvestViewModel = harvestViewModel
        self.weatherManager = weatherManager
    }
    
    // CSV Escaping Helper (fixes comma/quote issues)
    private func escapeCSV(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
    func generateCSV() -> String? {
        let calendar = Calendar.current
        var allDates: Set<Date> = Set()
        
        // ✅ FIX: Collect harvest dates (normalize to midnight to prevent duplicates)
        for (year, dayBars) in harvestViewModel.allYearData {
            for dayBar in dayBars {
                if let date = parseDateFromHarvest(year: year, dateString: dayBar.date) {
                    allDates.insert(calendar.startOfDay(for: date))  // ← CHANGED: Added startOfDay
                }
            }
        }
        
        // ✅ FIX: Add weather dates (normalize to midnight)
        for weatherDate in weatherManager.getAll().keys {
            allDates.insert(calendar.startOfDay(for: weatherDate))  // ← CHANGED: Added startOfDay
        }
        
        guard !allDates.isEmpty else { return nil }
        
        let sortedDates = allDates.sorted().filter { date in
            let components = Calendar.current.dateComponents([.month, .day], from: date)
            guard let month = components.month, let day = components.day else { return false }
            
            // October 1 through November 17
            if month == 10 {
                return day >= 1  // All of October from the 1st onward
            } else if month == 11 {
                return day <= 17  // November 1-17 only
            }
            return false
        }
        
        // Headers (55+ columns; adjust if struct updated)
        let headers = [
            // Indicators
            "Date", "Month", "Day", "Year", "DayOfWeek", "DayNumber",
            // Harvest
            "HarvestValue",
            // Weather Raw (existing + placeholders for new after struct update)
            "HighTemp", "LowTemp", "Temp", "TempMax", "FeelsLike", "FeelsLikeMin", "FeelsLikeMax",
            "WindSpeed", "WindGust", "WindDir", "Conditions", "Icon", "MoonPhase", "Humidity",
            "Dew", "Dewpoint", "Precip", "PrecipCover", "PrecipType", "Snow", "SnowDepth",
            "CloudCover", "Visibility", "Pressure", "SolarRadiation", "SolarEnergy", "UVIndex",
            "Sunrise", "Sunset", "Description",
            // Changes
            "24hLowTempChange", "48hLowTempChange", "72hLowTempChange",
            "24hHighTempChange", "48hHighTempChange", "72hHighTempChange",
            "24hWindSpeedChange", "48hWindSpeedChange", "72hWindSpeedChange",
            "24hPressureChange", "48hPressureChange", "72hPressureChange",
            "24hWindDirChange", "48hWindDirChange", "72hWindDirChange",
            "24hPrecipChange", "48hPrecipChange", "72hPrecipChange",
            "24hHumidityChange", "48hHumidityChange", "72hHumidityChange",
            "PressureDirection24h", "PressureDirection48h", "PressureDirection72h",
            // Flags
            "IsColdFront24h", "IsColdFront48h", "IsHighWind24h", "IsHeavyPrecip24h"
        ]
        
        var csvLines: [String] = [headers.joined(separator: ",")]
        
        for date in sortedDates {
            var row: [String] = []
            
            // Indicators
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let fullDateStr = formatDate(date)
            let month = components.month ?? 0
            let day = components.day ?? 0
            let year = components.year ?? 0
            let dayOfWeek = components.weekday.map { weekdayToString($0) } ?? ""
            let dayNumber = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            row.append(contentsOf: [fullDateStr, "\(month)", "\(day)", "\(year)", dayOfWeek, "\(dayNumber)"])
            
            // Harvest
            let harvestValue = getHarvestValue(for: date) ?? 0
            row.append("\(harvestValue)")
            
            // Weather Raw (use escape for strings)
            if let weather = weatherManager.getWeatherData(for: date) {
                row.append("\(weather.high)")
                row.append("\(weather.low)")
                row.append(weather.temp.map { "\($0)" } ?? "")
                row.append(weather.tempmax.map { "\($0)" } ?? "")
                row.append(weather.feelslike.map { "\($0)" } ?? "")
                row.append(weather.feelslikemin.map { "\($0)" } ?? "")
                row.append(weather.feelslikemax.map { "\($0)" } ?? "")
                row.append(weather.windspeed.map { "\($0)" } ?? "")
                row.append(weather.windgust.map { "\($0)" } ?? "")
                row.append(weather.winddir.map { "\($0)" } ?? "")
                row.append(escapeCSV(weather.conditions ?? ""))
                row.append(escapeCSV(weather.icon ?? ""))
                row.append(weather.moonphase.map { "\($0)" } ?? "")
                row.append(weather.humidity.map { "\($0)" } ?? "")
                row.append(weather.dew.map { "\($0)" } ?? "")
                row.append(weather.dewpoint.map { "\($0)" } ?? "")
                row.append(weather.precip.map { "\($0)" } ?? "")
                row.append(weather.precipcover.map { "\($0)" } ?? "")
                row.append(weather.preciptype?.joined(separator: ";") ?? "")
                row.append(weather.snow.map { "\($0)" } ?? "")
                row.append(weather.snowdepth.map { "\($0)" } ?? "")
                row.append(weather.cloudcover.map { "\($0)" } ?? "")
                row.append(weather.visibility.map { "\($0)" } ?? "")
                row.append(weather.pressure.map { "\($0)" } ?? "")
                row.append(weather.solarradiation.map { "\($0)" } ?? "")
                row.append(weather.solarenergy.map { "\($0)" } ?? "")
                row.append(weather.uvindex.map { "\($0)" } ?? "")
                row.append(weather.sunrise ?? "")
                row.append(weather.sunset ?? "")
                row.append(escapeCSV(weather.description ?? ""))
            } else {
                row.append(contentsOf: Array(repeating: "", count: 30))
            }
            
            // Changes & Flags
            let changes = calculateWeatherChanges(for: date)
            
            // Temperature changes
            let tempChanges = [
                changes.low24 ?? "", changes.low48 ?? "", changes.low72 ?? "",
                changes.high24 ?? "", changes.high48 ?? "", changes.high72 ?? ""
            ]
            
            // Weather parameter changes
            let weatherChanges = [
                changes.wind24 ?? "", changes.wind48 ?? "", changes.wind72 ?? "",
                changes.pressure24 ?? "", changes.pressure48 ?? "", changes.pressure72 ?? ""
            ]
            
            // Direction and precipitation changes
            let directionChanges = [
                changes.windDir24 ?? "", changes.windDir48 ?? "", changes.windDir72 ?? "",
                changes.precip24 ?? "", changes.precip48 ?? "", changes.precip72 ?? ""
            ]
            
            // Humidity and pressure directions
            let humidityAndDirections = [
                changes.humidity24 ?? "", changes.humidity48 ?? "", changes.humidity72 ?? "",
                changes.pressureDir24, changes.pressureDir48, changes.pressureDir72
            ]
            
            // Flags
            let flags = [
                "\(changes.isColdFront24 ? 1 : 0)", "\(changes.isColdFront48 ? 1 : 0)",
                "\(changes.isHighWind24 ? 1 : 0)", "\(changes.isHeavyPrecip24 ? 1 : 0)"
            ]
            
            // Combine all change arrays
            row.append(contentsOf: tempChanges)
            row.append(contentsOf: weatherChanges)
            row.append(contentsOf: directionChanges)
            row.append(contentsOf: humidityAndDirections)
            row.append(contentsOf: flags)
            
            csvLines.append(row.map { $0 }.joined(separator: ","))
        }
        
        return csvLines.joined(separator: "\n")
    }
    
    func generateCSV2() -> String? {
        var allDates: Set<Date> = Set()
        
        for (year, dayBars) in harvestViewModel.allYearData {
            for dayBar in dayBars {
                if let date = parseDateFromHarvest(year: year, dateString: dayBar.date) {
                    allDates.insert(date)
                }
            }
        }
        
        allDates.formUnion(weatherManager.getAll().keys)
        
        guard !allDates.isEmpty else { return nil }
        
        let sortedDates = allDates.sorted().filter { date in
            let components = Calendar.current.dateComponents([.month, .day], from: date)
            guard let month = components.month, let day = components.day else { return false }
            
            // October 1 through November 17
            if month == 10 {
                return day >= 1  // All of October from the 1st onward
            } else if month == 11 {
                return day <= 17  // November 1-17 only
            }
            return false
        }
        
        // Headers (55+ columns; adjust if struct updated)
        let headers = [
            // Indicators
            "Date", "Month", "Day", "Year", "DayOfWeek", "DayNumber",
            // Harvest
            "HarvestValue",
            // Weather Raw (existing + placeholders for new after struct update)
            "HighTemp", "LowTemp", "Temp", "TempMax", "FeelsLike", "FeelsLikeMin", "FeelsLikeMax",
            "WindSpeed", "WindGust", "WindDir", "Conditions", "Icon", "MoonPhase", "Humidity",
            "Dew", "Dewpoint", "Precip", "PrecipCover", "PrecipType", "Snow", "SnowDepth",
            "CloudCover", "Visibility", "Pressure", "SolarRadiation", "SolarEnergy", "UVIndex",
            "Sunrise", "Sunset", "Description",
            // Changes
            "24hLowTempChange", "48hLowTempChange", "72hLowTempChange",
            "24hHighTempChange", "48hHighTempChange", "72hHighTempChange",
            "24hWindSpeedChange", "48hWindSpeedChange", "72hWindSpeedChange",
            "24hPressureChange", "48hPressureChange", "72hPressureChange",
            "24hWindDirChange", "48hWindDirChange", "72hWindDirChange",
            "24hPrecipChange", "48hPrecipChange", "72hPrecipChange",
            "24hHumidityChange", "48hHumidityChange", "72hHumidityChange",
            "PressureDirection24h", "PressureDirection48h", "PressureDirection72h",
            // Flags
            "IsColdFront24h", "IsColdFront48h", "IsHighWind24h", "IsHeavyPrecip24h"
        ]
        
        var csvLines: [String] = [headers.joined(separator: ",")]
        let calendar = Calendar.current
        
        for date in sortedDates {
            var row: [String] = []
            
            // Indicators
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let fullDateStr = formatDate(date)
            let month = components.month ?? 0
            let day = components.day ?? 0
            let year = components.year ?? 0
            let dayOfWeek = components.weekday.map { weekdayToString($0) } ?? ""
            let dayNumber = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            row.append(contentsOf: [fullDateStr, "\(month)", "\(day)", "\(year)", dayOfWeek, "\(dayNumber)"])
            
            // Harvest
            let harvestValue = getHarvestValue(for: date) ?? 0
            row.append("\(harvestValue)")
            
            // Weather Raw (use escape for strings)
            if let weather = weatherManager.getWeatherData(for: date) {
                row.append("\(weather.high)")
                row.append("\(weather.low)")
                row.append(weather.temp.map { "\($0)" } ?? "")
                row.append(weather.tempmax.map { "\($0)" } ?? "")
                row.append(weather.feelslike.map { "\($0)" } ?? "")
                row.append(weather.feelslikemin.map { "\($0)" } ?? "")
                row.append(weather.feelslikemax.map { "\($0)" } ?? "")
                row.append(weather.windspeed.map { "\($0)" } ?? "")
                row.append(weather.windgust.map { "\($0)" } ?? "")
                row.append(weather.winddir.map { "\($0)" } ?? "")
                row.append(escapeCSV(weather.conditions ?? ""))
                row.append(escapeCSV(weather.icon ?? ""))
                row.append(weather.moonphase.map { "\($0)" } ?? "")
                row.append(weather.humidity.map { "\($0)" } ?? "")
                row.append(weather.dew.map { "\($0)" } ?? "")
                row.append(weather.dewpoint.map { "\($0)" } ?? "")
                row.append(weather.precip.map { "\($0)" } ?? "")
                row.append(weather.precipcover.map { "\($0)" } ?? "")
                row.append(weather.preciptype?.joined(separator: ";") ?? "")
                row.append(weather.snow.map { "\($0)" } ?? "")
                row.append(weather.snowdepth.map { "\($0)" } ?? "")
                row.append(weather.cloudcover.map { "\($0)" } ?? "")
                row.append(weather.visibility.map { "\($0)" } ?? "")
                row.append(weather.pressure.map { "\($0)" } ?? "")
                row.append(weather.solarradiation.map { "\($0)" } ?? "")
                row.append(weather.solarenergy.map { "\($0)" } ?? "")
                row.append(weather.uvindex.map { "\($0)" } ?? "")
                row.append(weather.sunrise ?? "")
                row.append(weather.sunset ?? "")
                row.append(escapeCSV(weather.description ?? ""))
            } else {
                row.append(contentsOf: Array(repeating: "", count: 30))  // Matches weather columns (30 after update)
            }
            
            // Changes & Flags - Break up large array to help compiler
            let changes = calculateWeatherChanges(for: date)
            
            // Temperature changes
            let tempChanges = [
                changes.low24 ?? "", changes.low48 ?? "", changes.low72 ?? "",
                changes.high24 ?? "", changes.high48 ?? "", changes.high72 ?? ""
            ]
            
            // Weather parameter changes
            let weatherChanges = [
                changes.wind24 ?? "", changes.wind48 ?? "", changes.wind72 ?? "",
                changes.pressure24 ?? "", changes.pressure48 ?? "", changes.pressure72 ?? ""
            ]
            
            // Direction and precipitation changes
            let directionChanges = [
                changes.windDir24 ?? "", changes.windDir48 ?? "", changes.windDir72 ?? "",
                changes.precip24 ?? "", changes.precip48 ?? "", changes.precip72 ?? ""
            ]
            
            // Humidity and pressure directions
            let humidityAndDirections = [
                changes.humidity24 ?? "", changes.humidity48 ?? "", changes.humidity72 ?? "",
                changes.pressureDir24, changes.pressureDir48, changes.pressureDir72
            ]
            
            // Flags
            let flags = [
                "\(changes.isColdFront24 ? 1 : 0)", "\(changes.isColdFront48 ? 1 : 0)",
                "\(changes.isHighWind24 ? 1 : 0)", "\(changes.isHeavyPrecip24 ? 1 : 0)"
            ]
            
            // Combine all change arrays
            row.append(contentsOf: tempChanges)
            row.append(contentsOf: weatherChanges)
            row.append(contentsOf: directionChanges)
            row.append(contentsOf: humidityAndDirections)
            row.append(contentsOf: flags)
            
            csvLines.append(row.map { $0 }.joined(separator: ","))  // Already escaped where needed
        }
        
        return csvLines.joined(separator: "\n")
    }
    
    // MARK: Helpers
    private func parseDateFromHarvest(year: Int, dateString: String) -> Date? {
        let parts = dateString.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: parts[0], day: parts[1]))
    }
    
    private func getHarvestValue(for date: Date) -> Int? {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        
        // Try both formats: "M/D" and "M/DD"
        let format1 = "\(month)/\(day)"           // "11/1"
        let format2 = String(format: "%d/%02d", month, day)  // "11/01"
        
        return harvestViewModel.allYearData[year]?.first {
            $0.date == format1 || $0.date == format2
        }?.value
    }
    
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    private func formatDate(_ date: Date) -> String { dateFormatter.string(from: date) }
    
    private func weekdayToString(_ weekday: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday - 1]
    }
    
    // Updated Changes Struct
    private struct WeatherChanges {
        let low24: String?, low48: String?, low72: String?
        let high24: String?, high48: String?, high72: String?
        let wind24: String?, wind48: String?, wind72: String?
        let pressure24: String?, pressure48: String?, pressure72: String?
        let windDir24: String?, windDir48: String?, windDir72: String?
        let precip24: String?, precip48: String?, precip72: String?
        let humidity24: String?, humidity48: String?, humidity72: String?
        let pressureDir24: String, pressureDir48: String, pressureDir72: String
        let isColdFront24: Bool, isColdFront48: Bool
        let isHighWind24: Bool
        let isHeavyPrecip24: Bool
    }
    
    private func calculateWeatherChanges(for date: Date) -> WeatherChanges {
        let prev1 = Calendar.current.date(byAdding: .day, value: -1, to: date)
        let prev2 = Calendar.current.date(byAdding: .day, value: -2, to: date)
        let prev3 = Calendar.current.date(byAdding: .day, value: -3, to: date)
        
        let current = weatherManager.getWeatherData(for: date)
        let prev1Data = prev1.flatMap { weatherManager.getWeatherData(for: $0) }
        let prev2Data = prev2.flatMap { weatherManager.getWeatherData(for: $0) }
        let prev3Data = prev3.flatMap { weatherManager.getWeatherData(for: $0) }
        
        // Separate change funcs for Int/Double
        func changeInt(current: Int?, prev: Int?) -> String? {
            guard let c = current, let p = prev else { return nil }
            return String(format: "%.2f", Double(c - p))
        }
        
        func changeDouble(current: Double?, prev: Double?) -> String? {
            guard let c = current, let p = prev else { return nil }
            return String(format: "%.2f", c - p)
        }
        
        func direction(change: String?) -> String {
            guard let delta = change.flatMap(Double.init), delta != 0 else { return "Stable" }
            return delta > 0 ? "Rise" : "Fall"
        }
        
        let low24 = changeInt(current: current?.low, prev: prev1Data?.low)
        let low48 = changeInt(current: current?.low, prev: prev2Data?.low)
        let low72 = changeInt(current: current?.low, prev: prev3Data?.low)
        
        let high24 = changeInt(current: current?.high, prev: prev1Data?.high)
        let high48 = changeInt(current: current?.high, prev: prev2Data?.high)
        let high72 = changeInt(current: current?.high, prev: prev3Data?.high)
        
        let wind24 = changeDouble(current: current?.windspeed, prev: prev1Data?.windspeed)
        let wind48 = changeDouble(current: current?.windspeed, prev: prev2Data?.windspeed)
        let wind72 = changeDouble(current: current?.windspeed, prev: prev3Data?.windspeed)
        
        let pressure24 = changeDouble(current: current?.pressure, prev: prev1Data?.pressure)
        let pressure48 = changeDouble(current: current?.pressure, prev: prev2Data?.pressure)
        let pressure72 = changeDouble(current: current?.pressure, prev: prev3Data?.pressure)
        
        let windDir24 = changeDouble(current: current?.winddir, prev: prev1Data?.winddir)
        let windDir48 = changeDouble(current: current?.winddir, prev: prev2Data?.winddir)
        let windDir72 = changeDouble(current: current?.winddir, prev: prev3Data?.winddir)
        
        let precip24 = changeDouble(current: current?.precip, prev: prev1Data?.precip)
        let precip48 = changeDouble(current: current?.precip, prev: prev2Data?.precip)
        let precip72 = changeDouble(current: current?.precip, prev: prev3Data?.precip)
        
        let humidity24 = changeDouble(current: current?.humidity, prev: prev1Data?.humidity)
        let humidity48 = changeDouble(current: current?.humidity, prev: prev2Data?.humidity)
        let humidity72 = changeDouble(current: current?.humidity, prev: prev3Data?.humidity)
        
        // Flags
        let isColdFront24 = (low24.flatMap(Double.init) ?? 0) < -10.0
        let isColdFront48 = (low48.flatMap(Double.init) ?? 0) < -10.0
        let isHighWind24 = (current?.windspeed ?? 0) > 20
        let isHeavyPrecip24 = (current?.precip ?? 0) > 1.0
        
        return WeatherChanges(
            low24: low24, low48: low48, low72: low72,
            high24: high24, high48: high48, high72: high72,
            wind24: wind24, wind48: wind48, wind72: wind72,
            pressure24: pressure24, pressure48: pressure48, pressure72: pressure72,
            windDir24: windDir24, windDir48: windDir48, windDir72: windDir72,
            precip24: precip24, precip48: precip48, precip72: precip72,
            humidity24: humidity24, humidity48: humidity48, humidity72: humidity72,
            pressureDir24: direction(change: pressure24),
            pressureDir48: direction(change: pressure48),
            pressureDir72: direction(change: pressure72),
            isColdFront24: isColdFront24, isColdFront48: isColdFront48,
            isHighWind24: isHighWind24, isHeavyPrecip24: isHeavyPrecip24
        )
    }
    
    // Export with timestamp
    func exportCSVToFile() -> URL? {
        guard let csvString = generateCSV() else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "HarvestWeatherAnalysis_\(timestamp).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error writing CSV: \(error)")
            return nil
        }
    }
}
