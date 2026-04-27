//
//  HighLowManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/5/25.
//




import Foundation
class HighLowManager {
    static let shared = HighLowManager()
    private var weatherData: [Date: DailyWeatherData] = [:]

    // Expanded struct to store all daily weather data
//    struct DailyWeatherData: Codable {
//        let high: Int
//        let low: Int
//        let windspeed: Double?
//        let windgust: Double?
//        let conditions: String?
//        let moonphase: Double?
//        let humidity: Double?
//        let precip: Double?
//        let preciptype: [String]?
//        let snow: Double?
//        let cloudcover: Double?
//        let visibility: Double?
//        let winddir: Double?
//        let pressure: Double?
//        let description: String?
//        // Optional: Add these if they become available in your API
//        // let windgust: Double?
//        // let preciptype: [String]?
//    }
    struct DailyWeatherData: Codable {
            let high: Int
            let low: Int
            let windspeed: Double?
            let windgust: Double?
            let conditions: String?
            let moonphase: Double?
            let humidity: Double?
            let precip: Double?
            let preciptype: [String]?
            let snow: Double?
            let cloudcover: Double?
            let visibility: Double?
            let winddir: Double?
            let pressure: Double?
            let description: String?
            
            // NEW: Expanded from HistoricalVis.Days and requirements
            let temp: Double?
            let tempmax: Double?
            let icon: String?
            let sunrise: String?
            let feelslike: Double?
            let feelslikemin: Double?
            let feelslikemax: Double?
            let snowdepth: Double?
            let dew: Double?
            let solarradiation: Double?
            let uvindex: Int?
            let solarenergy: Double?
            let sunset: String?
            let precipcover: Double?
            let dewpoint: Double?  // Optional: Calculate if not in API (approx formula: dew = temp - ((100 - humidity)/5))
            
            // Init for coding
            init(high: Int, low: Int, windspeed: Double? = nil, windgust: Double? = nil, conditions: String? = nil,
                 moonphase: Double? = nil, humidity: Double? = nil, precip: Double? = nil, preciptype: [String]? = nil,
                 snow: Double? = nil, cloudcover: Double? = nil, visibility: Double? = nil, winddir: Double? = nil,
                 pressure: Double? = nil, description: String? = nil, temp: Double? = nil, tempmax: Double? = nil,
                 icon: String? = nil, sunrise: String? = nil, feelslike: Double? = nil, feelslikemin: Double? = nil,
                 feelslikemax: Double? = nil, snowdepth: Double? = nil, dew: Double? = nil, solarradiation: Double? = nil,
                 uvindex: Int? = nil, solarenergy: Double? = nil, sunset: String? = nil, precipcover: Double? = nil,
                 dewpoint: Double? = nil) {
                self.high = high
                self.low = low
                self.windspeed = windspeed
                self.windgust = windgust
                self.conditions = conditions
                self.moonphase = moonphase
                self.humidity = humidity
                self.precip = precip
                self.preciptype = preciptype
                self.snow = snow
                self.cloudcover = cloudcover
                self.visibility = visibility
                self.winddir = winddir
                self.pressure = pressure
                self.description = description
                self.temp = temp
                self.tempmax = tempmax
                self.icon = icon
                self.sunrise = sunrise
                self.feelslike = feelslike
                self.feelslikemin = feelslikemin
                self.feelslikemax = feelslikemax
                self.snowdepth = snowdepth
                self.dew = dew
                self.solarradiation = solarradiation
                self.uvindex = uvindex
                self.solarenergy = solarenergy
                self.sunset = sunset
                self.precipcover = precipcover
                self.dewpoint = dewpoint
            }
            
            // Update encoding/decoding if needed for Codable compliance
            // Add CodingKeys if any mismatches
        }

    private init() {
        loadFromUserDefaults()
    }

    // Method to store complete weather data for a given date
    func storeWeatherData(for date: Date, data: DailyWeatherData) {
        weatherData[date] = data
        saveToUserDefaults()
    }

    // Method to retrieve weather data for a given date
    func getWeatherData(for date: Date) -> DailyWeatherData? {
        return weatherData[date]
    }

    // Convenience method to get just high/low (for backwards compatibility)
    func getHighLow(for date: Date) -> (high: Int, low: Int)? {
        guard let data = weatherData[date] else { return nil }
        return (high: data.high, low: data.low)
    }

    // Method to get a high/low description for a given date
    func highAndLowDescription(for date: Date) -> String {
        guard let data = weatherData[date] else {
            return "No data"
        }
        return "\(data.high)°,\(data.low)°"
    }

    // Save data to UserDefaults
    private func saveToUserDefaults() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(weatherData) {
            UserDefaults.standard.set(encoded, forKey: "weatherData")
        }
    }
    
    // Allows access to full dictionary without exposing mutability
    func getAll() -> [Date: DailyWeatherData] {
        return weatherData
    }

    // Load data from UserDefaults
    private func loadFromUserDefaults() {
        if let savedData = UserDefaults.standard.data(forKey: "weatherData") {
            let decoder = JSONDecoder()
            if let decodedData = try? decoder.decode([Date: DailyWeatherData].self, from: savedData) {
                weatherData = decodedData
            }
        }
    }
}

