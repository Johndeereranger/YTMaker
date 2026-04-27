//
//  WeekDayChunk.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/22/25.
//


import Foundation

struct WeekDayChunk: Identifiable, Codable, Equatable {
    let id = UUID()
    let week: Int
    let day: Int
    let title: String
    let html: String
}

// MARK: - HTMLProcessor (formerly HTMLWeekProcessor)

class HTMLProcessor {
    static let instance = HTMLProcessor()
    var campCode: String?
    private init() {}

    private var cachedChunks: [WeekDayChunk] = []

    // Called once after the full HTML is dropped/pasted
    func preprocess(html: String, week: Int) {
        cachedChunks = splitByPageEnd(html: html, week: week)
    }

    // Access individual day chunk (used in switch logic)
    func chunk(forDay day: Int) -> String? {
        let data = cachedChunks.first(where: { $0.day == day })?.html
        print(#function, data)
        return data
    }

    // Internal logic to split based on "Page End"
    private func splitByPageEnd(html: String, week: Int) -> [WeekDayChunk] {
//        let regex = try! NSRegularExpression(pattern: #"-{10,} *Page End *-{10,}"#, options: .caseInsensitive)
//        let fullRange = NSRange(html.startIndex..., in: html)
//        let matches = regex.matches(in: html, options: [], range: fullRange)
//        guard !matches.isEmpty else { return [] }
        let regex = try! NSRegularExpression(pattern: #"-+\s*Page\s+End\s*-+"#, options: .caseInsensitive)
        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: fullRange)
        guard !matches.isEmpty else { return [] }
        
        let campCases = extractCampVerses(from: html, week: week)
        print(campCases)
        campCode = campCases
        print("KEY CAMP CODE -", campCode)
        for i in 0 ... 10 {
            print("----------------------------------- ------------------------------------ -------------------------------------")
        }
        var chunks: [String] = []
        var lastIndex = html.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let chunk = String(html[lastIndex..<matchRange.lowerBound])
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(chunk)
            }
            lastIndex = matchRange.upperBound
        }

        let tail = String(html[lastIndex...])
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(tail)
        }
        print("About to Print Chunks")
        for (index, chunk) in chunks.enumerated() {
            print("CHUNK \(index): \(chunk)")
            print(" ------------------------------------------- END OF CHUNK \(index) ----------------------------------------")
        }
        print("Finished Printing Chunks")

        return chunks.enumerated().map { (index, chunk) in
            let day = index
            let title = extractTitle(from: chunk) ?? "Untitled"
            return WeekDayChunk(week: week, day: day, title: title, html: chunk)
        }
    }
    
    func extractCampVerses(from fullHTML: String, week: Int) -> String {
        let campPattern = #"CAMP in"#
        let regex = try! NSRegularExpression(pattern: campPattern, options: [.caseInsensitive])
        let nsRange = NSRange(fullHTML.startIndex..., in: fullHTML)
        let matches = regex.matches(in: fullHTML, options: [], range: nsRange)
        
        var result = ""
        var currentDay = 1
        
        for match in matches {
            let campStartLocation = match.range.location
            guard let campIndex = fullHTML.index(fullHTML.startIndex, offsetBy: campStartLocation, limitedBy: fullHTML.endIndex) else { continue }
            
            // From the 'C' in CAMP, go LEFT until we find '>'
            var leftBound = campIndex
            while leftBound > fullHTML.startIndex {
                leftBound = fullHTML.index(before: leftBound)
                if fullHTML[leftBound] == ">" {
                    leftBound = fullHTML.index(after: leftBound) // Move past the '>'
                    break
                }
            }
            
            // From the 'C' in CAMP, go RIGHT until we find '<'
            var rightBound = campIndex
            while rightBound < fullHTML.endIndex {
                if fullHTML[rightBound] == "<" {
                    break
                }
                rightBound = fullHTML.index(after: rightBound)
            }
            
            // Extract content between the bounds
            guard leftBound < rightBound else { continue }
            let rawContent = String(fullHTML[leftBound..<rightBound])
            
            // Extract the biblical reference from the content
            if let reference = extractReferenceFromContent(rawContent) {
                result += "case (\(week),\(currentDay)):\n"
                result += "    return \"\(reference)\"\n"
                currentDay += 1
            }
        }
        
        return result
    }

    private func extractReferenceFromContent(_ content: String) -> String? {
        // Clean the content and extract the reference
        var cleaned = content
        
        // Remove HTML and clean up
        cleaned = cleaned.replacingOccurrences(of: "CAMP in ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "&ndash;", with: "–")
        cleaned = cleaned.replacingOccurrences(of: "&mdash;", with: "—")
        cleaned = cleaned.replacingOccurrences(of: "&rsquo;", with: "'")
     //   cleaned = cleaned.replacingOccurrences(of: "&ldquo;", with: """)
//cleaned = cleaned.replacingOccurrences(of: "&rdquo;", with: """)
        cleaned = cleaned.replacingOccurrences(of: "&ldquo;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&rdquo;", with: "\"")
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation - should contain numbers and colons for verse references
        if cleaned.contains(":") && cleaned.rangeOfCharacter(from: .decimalDigits) != nil {
            return cleaned
        }
        
        return nil
    }


    private func extractTitle(from htmlChunk: String) -> String? {
        let pattern = #"WEEK\s+\d+,\s+DAY\s+\d+:?\s*(.*?)<"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: htmlChunk, options: [], range: NSRange(htmlChunk.startIndex..., in: htmlChunk)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: htmlChunk) else { return nil }
        return String(htmlChunk[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasChunks(for stepID: UUID) -> Bool {
        return stepIdToDayMap[stepID] != nil
    }
    // Entrypoint used in runSmartPromptStep
    func injectChunk(for stepID: UUID, finalInput: String, userInput: String) -> String {
        print("Step \(stepID), stepIdToDayMap: \(stepIdToDayMap)")
        guard let mappedDay = stepIdToDayMap[stepID] else {
            return finalInput // passthrough
        }

        if mappedDay == 0 {
            if let detectedWeek = extractWeek(from: userInput) {
                HTMLProcessor.instance.preprocess(html: userInput, week: detectedWeek)
            } else {
                print("⚠️ Could not detect week from HTML input. Defaulting to week 1.")
                HTMLProcessor.instance.preprocess(html: userInput, week: 1)
            }
            print("CHUNK FOR DAY 0: \(chunk(forDay: 0) ?? ""))")
            return chunk(forDay: 0) ?? "No Chuck for Day "
        }

        // Day 1–6: fetch cached data and inject
        if let chunk = chunk(forDay: mappedDay) {
            return mergePrompt("Prompt", with: chunk)
        }

        // Fallback: no cached chunk found
        return finalInput
    }
    
    static func extractCampVerses(from fullHTML: String, week: Int) {
        let pattern = #"CAMP in ([A-Za-z0-9\s]+(?:\d{1,2}:\d{1,2}(?:[-–]\d{1,2})?(?: and [A-Za-z0-9\s]+(?:\d{1,2}:\d{1,2}(?:[-–]\d{1,2})?)?)?)?)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

        let nsRange = NSRange(fullHTML.startIndex..., in: fullHTML)
        let matches = regex.matches(in: fullHTML, options: [], range: nsRange)

        var currentDay = 0

        for match in matches {
            guard let range = Range(match.range(at: 1), in: fullHTML) else { continue }
            let reference = fullHTML[range].trimmingCharacters(in: .whitespacesAndNewlines)

            print("case (\(week),\(currentDay)):")
            print("    return \"\(reference)\"")
            currentDay += 1
        }
    }

    private let stepIdToDayMap: [UUID: Int] = [
        UUID(uuidString: "8D76D0D4-FDF4-459C-8533-15BD85A6A828")!: 0,
        UUID(uuidString: "AD555653-0309-458D-89DA-13CAF4329CF8")!: 1,
        UUID(uuidString: "73F74BDF-D3EF-468C-8B51-ED9B3EF01D76")!: 2,
        UUID(uuidString: "3BB9B841-A21A-482C-B36E-25DE4DD220F6")!: 3,
        UUID(uuidString: "48F2F68F-9C41-4943-B562-E108B460D4EC")!: 4,
        UUID(uuidString: "1A40A4F1-2C69-4899-A41D-1E9E4D8B07C4")!: 5,
        UUID(uuidString: "D70242AD-702E-41C9-BE07-DEE1D809E7B3")!: 6
    ]
    
    private func mergePrompt(_ input: String, with data: String?) -> String {
        guard let data = data, !data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return input
        }

        return """
        \(input)

        ---
        REFERENCE DATA:
        \(data)
        """
    }
    
    private func extractWeek(from htmlChunk: String) -> Int? {
        let pattern = #"WEEK\s+(\d+),\s+DAY\s+\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: htmlChunk, options: [], range: NSRange(htmlChunk.startIndex..., in: htmlChunk)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: htmlChunk) else { return nil }
        return Int(htmlChunk[range])
    }
}
