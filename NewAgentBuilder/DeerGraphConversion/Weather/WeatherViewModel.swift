//
//  WeatherViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/5/25.
//



import Foundation
import CoreLocation

class WeatherViewModelOld: ObservableObject {
    @Published var weatherData: [String: [HistoricalVis]] = [:]
    @Published var isLoading = false
    
    private let weatherManager = HistoricalWeatherManager.instance
    
    func fetchHistoricalWeather() {
        isLoading = true
        
        let property: CLLocation = CLLocation(latitude: 40.0, longitude: -89.2)
        
        Task {
            do {
                var fetchCount = 0
                let years = [2015]
                let months = [(10, "October"), (11, "November")]
                            let totalFetches = years.count * months.count
                // Loop through years and months to fetch data for October and November
//                for year in [2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021, 2022, 2023, 2024] {
                    for year in years {
                    //let months = [(10, "October"), (11, "November")]
                    for (month, monthName) in months {
                        let startDate = getDate(year: year, month: month, day: 1)
                        let endDate = getDate(year: year, month: month, day: month == 10 ? 31 : 30)
                        
                        let weather = try await weatherManager.getHistoricalAt(latitude: property.coordinate.latitude, longitude: property.coordinate.longitude, startDate: startDate, endDate: endDate)
                        let key = "Chestnut - \(monthName) \(year)"
                        
                        DispatchQueue.main.async {
                            self.weatherData[key] = weather
                            self.storeWeatherData(weather)
                            
                            fetchCount += 1
                            if fetchCount == totalFetches {
                                self.isLoading = false
                            }
//                            if year == 2024 && month == 11 {
//                                self.isLoading = false // Stop loading once all data is fetched
//                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false // Stop loading in case of an error
                    print("Error fetching historical weather: \(error)")
                }
            }
        }
    }
    
    private func getDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
    func highAndLow(for date: Date) -> String {
          return HighLowManager.shared.highAndLowDescription(for: date)
      }
    
    // Function to store high/low data after fetching it
    private func storeWeatherData(_ weatherData: [HistoricalVis]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in weatherData {
            for day in entry.days {
                if let day = day, let datetimeString = day.datetime, let date = dateFormatter.date(from: datetimeString) {
                    let hiTemp = Int(day.tempmax ?? 0)
                    let loTemp = Int(day.tempmin ?? 0)
                   // HighLowManager.shared.storeHighLow(for: date, high: hiTemp, low: loTemp)
                }
            }
        }
    }
}


import Foundation
import CoreLocation

class WeatherViewModel: ObservableObject {
    @Published var weatherData: [String: [HistoricalVis]] = [:]
    @Published var isLoading = false
    
    private let weatherManager = HistoricalWeatherManager.instance
    
    func fetchHistoricalWeather() {
        isLoading = true
        
        let property: CLLocation = CLLocation(latitude: 40.0, longitude: -89.2)
        
        Task {
            do {
                var fetchCount = 0
                let years = 
                [2005,2006,2007,2008,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021, 2022, 2023, 2024]
                let months = [(10, "October"), (11, "November")]
                let totalFetches = years.count * months.count
                
                for year in years {
                    for (month, monthName) in months {
                        let startDate = getDate(year: year, month: month, day: 1)
                        let endDate = getDate(year: year, month: month, day: month == 10 ? 31 : 30)
                        
                        let weather = try await weatherManager.getHistoricalAt(latitude: property.coordinate.latitude, longitude: property.coordinate.longitude, startDate: startDate, endDate: endDate)
                        let key = "Chestnut - \(monthName) \(year)"
                        
                        DispatchQueue.main.async {
                            self.weatherData[key] = weather
                            self.storeWeatherData(weather)
                            
                            fetchCount += 1
                            if fetchCount == totalFetches {
                                self.isLoading = false
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("Error fetching historical weather: \(error)")
                }
            }
        }
    }
    
    private func getDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
    
    // MARK: - Data Retrieval Methods
    
    func highAndLow(for date: Date) -> String {
        return HighLowManager.shared.highAndLowDescription(for: date)
    }
    
    // Get complete weather data for a date
    func getWeatherData(for date: Date) -> HighLowManager.DailyWeatherData? {
        return HighLowManager.shared.getWeatherData(for: date)
    }
    
    // Individual property getters (optional convenience methods)
    func windspeed(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.windspeed
    }
    
    func windgust(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.windgust
    }
    
    func conditions(for date: Date) -> String? {
        return HighLowManager.shared.getWeatherData(for: date)?.conditions
    }
    
    func moonphase(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.moonphase
    }
    
    func humidity(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.humidity
    }
    
    func precip(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.precip
    }
    
    func preciptype(for date: Date) -> [String]? {
        return HighLowManager.shared.getWeatherData(for: date)?.preciptype
    }
    
    func snow(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.snow
    }
    
    func cloudcover(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.cloudcover
    }
    
    func visibility(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.visibility
    }
    
    func winddir(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.winddir
    }
    
    func pressure(for date: Date) -> Double? {
        return HighLowManager.shared.getWeatherData(for: date)?.pressure
    }
    
    func description(for date: Date) -> String? {
        return HighLowManager.shared.getWeatherData(for: date)?.description
    }
    
    // MARK: - November 1-17 Helpers

    // Get dates for Nov 1-17 for a specific year
    private func getNov17Dates(year: Int) -> [Date] {
        let calendar = Calendar.current
        return (1...17).compactMap { day in
            calendar.date(from: DateComponents(year: year, month: 11, day: day))
        }
    }

    // Get all Nov 1-17 dates across all years
    private func getAllNov17Dates() -> [Date] {
        var allDates: [Date] = []
        for year in 2005...2024 {
            allDates.append(contentsOf: getNov17Dates(year: year))
        }
        return allDates
    }
    
    // MARK: - Data Storage
    
    // Updated function to store complete weather data after fetching it
    private func storeWeatherData(_ weatherData: [HistoricalVis]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in weatherData {
            for day in entry.days {
                if let day = day,
                   let datetimeString = day.datetime,
                   let date = dateFormatter.date(from: datetimeString) {
                    
                    let dailyData = HighLowManager.DailyWeatherData(
                        high: Int(day.tempmax ?? 0),
                        low: Int(day.tempmin ?? 0),
                        windspeed: day.windspeed,
                        windgust: day.windgust,
                        conditions: day.conditions,
                        moonphase: day.moonphase,
                        humidity: day.humidity,
                        precip: day.precip,
                        preciptype: day.preciptype,
                        snow: day.snow,
                        cloudcover: day.cloudcover,
                        visibility: day.visibility,
                        winddir: day.winddir,
                        pressure: day.pressure,
                        description: day.description
                    )
                    
                    HighLowManager.shared.storeWeatherData(for: date, data: dailyData)
                }
            }
        }
    }
}
