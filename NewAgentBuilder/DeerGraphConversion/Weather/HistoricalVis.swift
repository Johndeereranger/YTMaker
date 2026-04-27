//
//  HistoricalVis.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/5/25.
//



import Foundation


public struct HistoricalVis: Codable, Hashable, Equatable {
    enum CodingKeys: String, CodingKey { case tzoffset, resolvedAddress, address, stations, queryCost, days, timezone, longitude, latitude }
    var tzoffset: Int?
    var resolvedAddress: String?
    var address: String?
    var stations: [String: Station?]?
    var queryCost: Int?
    var days: [Days?] = []
    var timezone: String?
    var longitude: Double?
    var latitude: Double?

    public struct Station: Codable, Hashable, Equatable {
        enum CodingKeys: String, CodingKey { case contribution, distance, id, quality, latitude, name, longitude, useCount }
        var contribution: Double?
        var distance: Int?
        var id: String?
        var quality: Int?
        var latitude: Double?
        var name: String?
        var longitude: Double?
        var useCount: Double?
    }
    public struct Days: Codable, Hashable, Equatable {
        enum CodingKeys: String, CodingKey {
            case precip, temp, tempmax, icon, humidity, sunrise, feelslike, visibility, description, snow, feelslikemin, hours, winddir, pressure, conditions, feelslikemax, sunriseEpoch, precipcover, uvindex, source, solarenergy, sunsetEpoch, cloudcover, snowdepth, sunset, datetime, dew, solarradiation, windspeed, stations, tempmin, moonphase, datetimeEpoch, windgust,preciptype
        }
        
        var precip: Double?
        var temp: Double?
        var tempmax: Double?
        var icon: String?
        var humidity: Double?
        var sunrise: String?
        var feelslike: Double?
        var visibility: Double?
        var description: String?
        var snow: Double?
        var feelslikemin: Double?
        var hours: [DaysHours]?  // Make `hours` optional to handle missing cases.
        var winddir: Double?
        var pressure: Double?
        var conditions: String?
        var feelslikemax: Double?
        var sunriseEpoch: Int?
        var precipcover: Double?
        var uvindex: Int?
        var source: String?
        var solarenergy: Double?
        var sunsetEpoch: Int?
        var cloudcover: Double?
        var snowdepth: Double?
        var sunset: String?
        var datetime: String?
        var dew: Double?
        var solarradiation: Double?
        var windspeed: Double?
        var stations: [String?]?
        var tempmin: Double?
        var moonphase: Double?
        var datetimeEpoch: Int?
        var windgust: Double?
        var preciptype: [String]?
    }


    public struct DaysOriginal: Codable, Hashable, Equatable {
        enum CodingKeys: String, CodingKey { case precip, temp, tempmax, icon, humidity, sunrise, feelslike, visibility, description, snow, feelslikemin, hours, winddir, pressure, conditions, feelslikemax, sunriseEpoch, precipcover, uvindex, source, solarenergy, sunsetEpoch, cloudcover, snowdepth, sunset, datetime, dew, solarradiation, windspeed, stations, tempmin, moonphase, datetimeEpoch }
        var precip: Double?
        var temp: Double?
        var tempmax: Double?
        var icon: String?
        var humidity: Double?
        var sunrise: String?
        var feelslike: Double?
        var visibility: Double?
        var description: String?
        var snow: Double?
        var feelslikemin: Double?
        var hours: [DaysHours?] = []
        var winddir: Double?
        var pressure: Double?
        var conditions: String?
        var feelslikemax: Double?
        var sunriseEpoch: Int?
        var precipcover: Double?
        var uvindex: Int?
        var source: String?
        var solarenergy: Double?
        var sunsetEpoch: Int?
        var cloudcover: Double?
        var snowdepth: Double?
        var sunset: String?
        var datetime: String?
        var dew: Double?
        var solarradiation: Double?
        var windspeed: Double?
        var stations: [String?] = []
        var tempmin: Double?
        var moonphase: Double?
        var datetimeEpoch: Int?
    }
    
    public struct DaysHours: Codable, Hashable, Equatable {
        enum CodingKeys: String, CodingKey { case stations, conditions, temp, uvindex, datetime, source, winddir, datetimeEpoch, pressure, humidity, icon, precip, snow, visibility, dew, snowdepth, feelslike, cloudcover, windspeed }
        var stations: [String]? = []
        var conditions: String?
        var temp: Double?
        var uvindex: Double?
        var datetime: String?
        var source: String?
        var winddir: Double?
        var datetimeEpoch: Int?
        var pressure: Double?
        var humidity: Double?
        var icon: String?
        var precip: Double?
        var snow: Double?
        var visibility: Double?
        var dew: Double?
        var snowdepth: Double?
        var feelslike: Double?
        var cloudcover: Double?
        var windspeed: Double?
    }
}
