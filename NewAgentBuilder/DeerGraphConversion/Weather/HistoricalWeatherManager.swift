//
//  HistoricalWeatherManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/5/25.
//


import Foundation

class HistoricalWeatherManager{
    static let instance = HistoricalWeatherManager()
    static let visualWeatherID = "&key=5QNFKJH9GZNP4VEK6MKH68Q5M"
    static let sessionManager: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30 // seconds
        configuration.timeoutIntervalForResource = 30 // seconds
        return URLSession(configuration: configuration)
    }()
    
    //https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/32.2,-81.2/1601510400/1609372800?key=YOUR_API_KEY
    //https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/32.2,-81.2/2020-10-01/2020-12-31?key=5QNFKJH9GZNP4VEK6MKH68Q5M&options=useobs,useremote&contentType=json
    

    
    func getHistoricalAt(latitude: Double, longitude: Double, startDate: Date, endDate: Date) async throws -> [HistoricalVis] {
        let currentLat = Helper.truncateDigitsAfterDecimal(number: latitude, afterDecimalDigits: 3)
        let currentLong = Helper.truncateDigitsAfterDecimal(number: longitude, afterDecimalDigits: 3)
        let start = getDateString(startDate)
        let end = getDateString(endDate)
        
        let startString = "/\(start)"
        let endString = "/\(end)?"
        let baseWeatherURL = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        let localLoc = "\(currentLat),\(currentLong)"
        
        let infoToGet = "&options=useobs,useremote"
        let dataType = "&contentType=json"
        let weatherURLtoSend = "\(baseWeatherURL)\(localLoc)\(startString)\(endString)\(infoToGet)\(dataType)\(HistoricalWeatherManager.visualWeatherID)"
        print("URL: \(weatherURLtoSend)")
        
        guard let fullURL = URL(string: weatherURLtoSend) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: fullURL)
        
        // Debugging prints for checking data
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Received JSON: \(jsonString)")
        } else {
            print("Failed to convert data to String.")
        }
        
        do {
            let decoder = JSONDecoder()
                   
                   // Step 1: Decode to a generic dictionary first to handle root-level validation
                   let rootObject = try JSONSerialization.jsonObject(with: data, options: [])
                   
                   guard let rootDictionary = rootObject as? [String: Any] else {
                       print("Failed to convert root level to dictionary.")
                       throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Failed to convert root level to dictionary."))
                   }
                   print("Successfully decoded root level to dictionary.")
                   
                   // Step 2: Extract and decode `stations` if it exists
                   if let stationsObject = rootDictionary["stations"] {
                       if let stationsArray = stationsObject as? [Any] {
                           print("Expected stations to be a dictionary, but found an array instead: \(stationsArray)")
                       } else if let stationsDict = stationsObject as? [String: Any] {
                           print("stations decoded successfully as dictionary with keys: \(stationsDict.keys)")
                       } else {
                           print("Unexpected type for stations.")
                       }
                   } else {
                       print("stations key not found.")
                   }
                   
                   // Step 3: Extract and decode individual properties
                   if let queryCost = rootDictionary["queryCost"] as? Int {
                       print("queryCost: \(queryCost)")
                   }
                   
                   if let latitude = rootDictionary["latitude"] as? Double {
                       print("latitude: \(latitude)")
                   }
                   
            if let daysArray = rootDictionary["days"] as? [[String: Any]] {
                print("days count: \(daysArray.count)")
                
                // Step 4: Decode `days` into `Days` structs
                var decodedDays: [HistoricalVis.Days] = []
                for (index, dayDict) in daysArray.enumerated() {
                    let dayData = try JSONSerialization.data(withJSONObject: dayDict, options: [])
                    do {
                        let day = try decoder.decode(HistoricalVis.Days.self, from: dayData)
                        decodedDays.append(day)
                        print("Successfully decoded day at index \(index): \(day)")
                    } catch let DecodingError.keyNotFound(key, context) {
                        print("Key '\(key.stringValue)' not found when decoding day at index \(index).")
                        print("Context: \(context.debugDescription)")
                    } catch let DecodingError.typeMismatch(type, context) {
                        print("Type mismatch for type '\(type)' when decoding day at index \(index).")
                        print("Context: \(context.debugDescription)")
                    } catch let DecodingError.valueNotFound(value, context) {
                        print("Value '\(value)' not found when decoding day at index \(index).")
                        print("Context: \(context.debugDescription)")
                    } catch {
                        print("Failed to decode day at index \(index): \(error.localizedDescription)")
                    }
                }
                
                // Assign decoded days back to `HistoricalVis`
                if !decodedDays.isEmpty {
                    print("Successfully decoded all available days.")
                } else {
                    print("No valid days were decoded.")
                }
            } else {
                print("days array not found or invalid.")
            }

                   
                   // Step 5: Now decode the full object if all parts are correct
                   let historicalVis = try decoder.decode(HistoricalVis.self, from: data)
                   print("Successfully decoded HistoricalVis root")
                   return [historicalVis]
        }catch let DecodingError.typeMismatch(type, context) {
            print("Type mismatch error: Expected type \(type)\nContext: \(context.debugDescription)")
            print("Coding Path: \(context.codingPath)")
            throw DecodingError.typeMismatch(type, context)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key not found: \(key.stringValue)\nContext: \(context.debugDescription)")
            throw DecodingError.keyNotFound(key, context)
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value not found: \(value)\nContext: \(context.debugDescription)")
            throw DecodingError.valueNotFound(value, context)
        } catch let DecodingError.dataCorrupted(context) {
            print("Data corrupted: \(context.debugDescription)")
            throw DecodingError.dataCorrupted(context)
        } catch {
            print("Unknown error: \(error.localizedDescription)")
            throw error
        }
    }

    
    func getDateString(_ input: Date) -> String{
        let df = DateFormatter()
        df.dateFormat = "YYYY-MM-dd"
        return df.string(from: input)
    }
    
    
}

class Helper {
    static func truncateDigitsAfterDecimal(number: Double, afterDecimalDigits: Int) -> Double {
          if afterDecimalDigits < 1 || afterDecimalDigits > 512 {return 0.0}
          return Double(String(format: "%.\(afterDecimalDigits)f", number))!
      }

}
