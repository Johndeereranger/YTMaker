//
//  DeerImageUploadViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/4/25.
//

import SwiftUI

class DeerImageUploadViewModelOld: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var debugImage: UIImage?
    @Published var barValues: [DayBarData] = []

    func analyzeImage() {
        guard let selectedImage else { return }
        let analyzer = ImageGraphAnalyzer(image: selectedImage)
        let result = analyzer.analyze()
        self.barValues = result.data
        self.debugImage = result.debugImage
    }
}

class DeerImageUploadViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var debugImage: UIImage?
    @Published var barValues: [DayBarData] = []
    
    @Published var year: Int = Calendar.current.component(.year, from: Date())
    @Published var yTickValues: [Int] = []
    @Published var detectedTickCount: Int = 0
    
    private let userDefaults = UserDefaults.standard
    private let storageKeyPrefix = "HarvestData_"

    func loadImage(_ image: UIImage) {
        selectedImage = image
        
        // Phase 1: Just detect ticks to know how many inputs we need
        let analyzer = ImageGraphAnalyzer(image: image)
        let tickCount = analyzer.detectTickCount()
        detectedTickCount = tickCount
        yTickValues = (0..<tickCount).map { $0 * 500 }
       // yTickValues = Array(repeating: 0, count: tickCount)
    }

    func analyzeImage() {
         guard let selectedImage else { return }
         let analyzer = ImageGraphAnalyzer(image: selectedImage)
         let result = analyzer.analyze(year: year, tickValues: yTickValues)
         self.barValues = result.data
         self.debugImage = result.debugImage
         
         // Auto-save after analysis
         saveData()
     }
    func loadData(for year: Int) {
           let key = storageKeyPrefix + String(year)
           
           guard let data = userDefaults.data(forKey: key),
                 let decoded = try? JSONDecoder().decode([DayBarData].self, from: data) else {
               print("⚠️ No data found for year \(year)")
               return
           }
           
           self.barValues = decoded
           print("✅ Loaded \(decoded.count) days for year \(year)")
       }
    func saveData() {
        guard !barValues.isEmpty else { return }
        let key = storageKeyPrefix + String(year)
        
        if let encoded = try? JSONEncoder().encode(barValues) {
            userDefaults.set(encoded, forKey: key)
            print("✅ Saved \(barValues.count) days for year \(year)")
        }
    }
}

//struct DayBarData: Identifiable {
//    var id: Int { day }
//    let day: Int
//    let date: String
//    let value: Int
//    let pixelLocation: CGPoint
//}

struct DayBarData: Identifiable, Codable {
    var id: Int { day }
    let day: Int
    let date: String
    let value: Int
    let pixelLocation: CGPoint
    
    // Need to handle CGPoint encoding
    enum CodingKeys: String, CodingKey {
        case day, date, value, pixelLocationX, pixelLocationY
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(date, forKey: .date)
        try container.encode(value, forKey: .value)
        try container.encode(pixelLocation.x, forKey: .pixelLocationX)
        try container.encode(pixelLocation.y, forKey: .pixelLocationY)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Int.self, forKey: .day)
        date = try container.decode(String.self, forKey: .date)
        value = try container.decode(Int.self, forKey: .value)
        let x = try container.decode(CGFloat.self, forKey: .pixelLocationX)
        let y = try container.decode(CGFloat.self, forKey: .pixelLocationY)
        pixelLocation = CGPoint(x: x, y: y)
    }
    
    init(day: Int, date: String, value: Int, pixelLocation: CGPoint) {
        self.day = day
        self.date = date
        self.value = value
        self.pixelLocation = pixelLocation
    }
}


import SwiftUI
import CoreGraphics
import UIKit

class ImageGraphAnalyzer {
    private let originalImage: UIImage
    private let cgImage: CGImage

    init(image: UIImage) {
        self.originalImage = image
        guard let cgImage = image.cgImage else {
            fatalError("❌ Failed to convert UIImage to CGImage")
        }
        self.cgImage = cgImage
    }
    func detectTickCount() -> Int {
        let pixelData = PixelData(image: cgImage)
        guard let origin = locateOrigin(in: pixelData) else { return 0 }
        let (yTickPoints, _) = detectYTicks(in: pixelData, from: origin, verbose: false)
        return yTickPoints.count
    }
    func analyze(year: Int, tickValues: [Int]) -> (data: [DayBarData], debugImage: UIImage) {
        let pixelData = PixelData(image: cgImage)
        guard let origin = locateOrigin(in: pixelData) else {
            return ([], originalImage)
        }
        
        var overlay = DebugOverlay()
        overlay.origin = origin
        
        let (yTickPoints, axisX) = detectYTicks(in: pixelData, from: origin, verbose: false)
        overlay.yTicks = yTickPoints
        overlay.yAxisColumn = axisX
        
        let barTops = detectBarTopsUsingGapColumn(in: pixelData, from: origin, gapX: axisX, verbose: false)
        overlay.barTops = barTops.map { $0.top }
        overlay.barBottoms = barTops.map { $0.bottom }
        
        // Convert bars to data
        let dayBarData = barTops.enumerated().map { index, bar in
            let day = index + 1
            let value = calculateBarValue(barTop: bar.top, yTicks: yTickPoints, tickValues: tickValues)
            let date = dateString(year: year, day: day)
            return DayBarData(day: day, date: date, value: value, pixelLocation: bar.top)
        }
        
        let debugImage = drawDebugDots(on: cgImage, overlay: overlay)
        return (dayBarData, debugImage)
    }

    private func calculateBarValue(barTop: CGPoint, yTicks: [CGPoint], tickValues: [Int]) -> Int {
        guard yTicks.count == tickValues.count, yTicks.count >= 2 else { return 0 }
        
        let barTopY = barTop.y
        
        // Ticks are ordered bottom-to-top (increasing Y values)
        for i in 0..<(yTicks.count - 1) {
            let lowerTick = yTicks[i]      // Lower Y = lower value
            let upperTick = yTicks[i + 1]  // Higher Y = higher value
            
            if barTopY >= lowerTick.y && barTopY <= upperTick.y {
                let tickRange = upperTick.y - lowerTick.y
                let barPosition = barTopY - lowerTick.y
                let valueRange = CGFloat(tickValues[i + 1] - tickValues[i])
                let interpolated = CGFloat(tickValues[i]) + (barPosition / tickRange) * valueRange
                return Int(round(interpolated))
            }
        }
        
        // Handle edge cases
        if barTopY < yTicks.first!.y { return tickValues.first! }
        if barTopY > yTicks.last!.y { return tickValues.last! }
        return 0
    }

    private func dateString(year: Int, day: Int) -> String {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: year, month: 10, day: 1))!
        let targetDate = calendar.date(byAdding: .day, value: day - 1, to: startDate)!
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: targetDate)
    }

    func analyze() -> (data: [DayBarData], debugImage: UIImage) {
        let pixelData = PixelData(image: cgImage)
        guard let origin = locateOrigin(in: pixelData) else {
            return ([], originalImage)
        }
        print("✅ Origin calculated at: \(origin.x), \(origin.y)")
        
       
        var overlay = DebugOverlay()
        overlay.origin = origin
        let (yTickPoints, axisX) = detectYTicks(in: pixelData, from: origin, verbose: false)
        overlay.yTicks = yTickPoints
        overlay.yAxisColumn = axisX
           overlay.yAxisColumn = axisX
        let (barTops) = detectBarTopsUsingGapColumn(in: pixelData, from: origin, gapX: axisX, verbose: true)
        overlay.barTops = barTops.map { $0.top }
        overlay.barBottoms = barTops.map { $0.bottom }
        //overlay.barScanY = barScanY
        //overlay.barTops = barTops
        // overlay.barTops.append(...) later
        // overlay.yTicks.append(...) later

        let debugImage = drawDebugDots(on: cgImage, overlay: overlay)
        return ([], debugImage)
    }
   
    
    private func drawDebugDots(
        on cgImage: CGImage,
        overlay: DebugOverlay
    ) -> UIImage {
        let width = cgImage.width
        let height = cgImage.height
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))

        return renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

//            // 🔴 Bar tops
//            ctx.setFillColor(UIColor.red.cgColor)
//            for point in overlay.barTops {
//                ctx.fillEllipse(in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
//            }
            
            let barCount = min(overlay.barTops.count, overlay.barBottoms.count)
             for i in 0..<barCount {
                 let top = overlay.barTops[i]
                 let bottom = overlay.barBottoms[i]

                 let color = i % 2 == 0 ? UIColor.red : UIColor.green
                 ctx.setFillColor(color.cgColor)

                 ctx.fillEllipse(in: CGRect(x: top.x - 5, y: top.y - 5, width: 10, height: 10))      // top
                 ctx.fillEllipse(in: CGRect(x: bottom.x - 3, y: bottom.y - 3, width: 6, height: 6))   // bottom (slightly smaller)
             }

            // 🔵 Y ticks
            ctx.setFillColor(UIColor.red.cgColor)
            for point in overlay.yTicks {
                ctx.fillEllipse(in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            }

            // 🟢 Origin
            if let origin = overlay.origin {
                ctx.setFillColor(UIColor.green.cgColor)
                ctx.fillEllipse(in: CGRect(x: origin.x - 6, y: origin.y - 6, width: 12, height: 12))
            }
            // 🟥 Horizontal line at barScanY for visual debug
            if let scanY = overlay.barScanY {
                let width = Int(context.format.bounds.width)
                ctx.setStrokeColor(UIColor.red.cgColor)
                ctx.setLineWidth(1.0)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: scanY))
                ctx.addLine(to: CGPoint(x: width, y: scanY)) // ✅ fix: cast removed
                ctx.strokePath()
            }

        }
    }


    private func isBlack(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let threshold: CGFloat = 0.3
        return red < threshold && green < threshold && blue < threshold
    }

    func locateOrigin(in pixelData: PixelData) -> CGPoint? {
        let width = pixelData.width
        let height = pixelData.height
        let maxAxisSearchX = 600        // Only search first 50 vertical columns
        let verticalSampleHeight = height// min(250, height) // How far up to check for Y-axis
        let horizontalSampleWidth = width //min(2500, width) // How far right to check for X-axis

        var bestAxisX: Int? = nil
        var bestVerticalScore = 0

        // 🔍 STEP 1: Find best vertical line (Y-axis) in first N columns
        for x in 0..<maxAxisSearchX {
            var blackCount = 0
            for y in 0..<verticalSampleHeight {
                if isBlack(pixelData.colorAt(x: x, y: y)) {
                    blackCount += 1
                }
            }
            print("x=\(x) → vertical black count: \(blackCount)")
            if blackCount > bestVerticalScore {
                bestVerticalScore = blackCount
                bestAxisX = x
            }
        }

        guard let axisX = bestAxisX else {
            print("❌ Could not find vertical Y-axis line")
            return nil
        }

        // 🔍 STEP 2: At that X, find best horizontal line (X-axis baseline)
        var bestAxisY: Int? = nil
        var bestHorizontalScore = 0

        for y in 0..<verticalSampleHeight {
            var blackCount = 0
            for dx in 0..<horizontalSampleWidth {
                if isBlack(pixelData.colorAt(x: axisX + dx, y: y)) {
                    blackCount += 1
                }
            }
            if blackCount > bestHorizontalScore {
                bestHorizontalScore = blackCount
                bestAxisY = y
            }
        }
        print("✅ Found vertical axis at x=\(axisX) with blackCount=\(bestVerticalScore)")
       // print("✅ Found horizontal axis at y=\(axisY) with blackCount=\(bestHorizontalScore)")
        guard let axisY = bestAxisY else {
            print("❌ Could not find horizontal X-axis line")
            return nil
        }

        print("✅ Origin found at pixel: (\(axisX), \(axisY))")
        return CGPoint(x: axisX, y: axisY)
    }
    func detectYTicks(in pixelData: PixelData, from origin: CGPoint, verbose: Bool = true) -> (ticks: [CGPoint], axisX: Int) {
        let startX = Int(origin.x)
        let originY = Int(origin.y)

        // Step left from origin to find the first white column
        var whiteX = startX
        while whiteX >= 0 {
            let color = pixelData.colorAt(x: whiteX, y: originY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            if white > 0.9 { break }
            whiteX -= 1
        }

        let gapX = (whiteX + startX) / 2
        print("📍 Y-axis GAP column selected at: \(gapX) (midpoint between white: \(whiteX) and origin: \(startX))")

        var tickPositions: [CGPoint] = []
        var isInBlackDash = false

        // SCAN ENTIRE COLUMN (bottom to top)
        for y in stride(from: 0, to: pixelData.height, by: 1) {
            let color = pixelData.colorAt(x: gapX, y: y)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            let isBlack = white < 0.2

            if verbose {
                let status = isBlack ? (isInBlackDash ? "🟣 still in black" : "🟢 ENTER tick") : "⚪️ white"
                print("📏 y=\(y) → white=\(String(format: "%.2f", white)) → \(status)")
            }

            if isBlack {
                if !isInBlackDash {
                    tickPositions.append(CGPoint(x: gapX, y: y))
                    isInBlackDash = true
                }
            } else {
                isInBlackDash = false
            }
        }

        print("📍 Detected \(tickPositions.count) Y-axis ticks at rows: \(tickPositions.map { Int($0.y) })")
        return (ticks: tickPositions, axisX: gapX)
    }

    
   

    
    func detectBarTopsUsingGapColumnWorks(
        in pixelData: PixelData,
        from origin: CGPoint,
        gapX: Int,
        verbose: Bool = false
    ) -> [(top: CGPoint, bottom: CGPoint)] {
        var barPoints: [(top: CGPoint, bottom: CGPoint)] = []
        
        // STEP 1: Find barScanY (first white row after origin)
        var barScanY = Int(origin.y)
        while barScanY < pixelData.height {
            let color = pixelData.colorAt(x: gapX, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            if white > 0.95 { break }
            barScanY += 1
        }
        
        print("🧭 Found barScanY at y=\(barScanY)")
        
        // DEBUG: Always print horizontal scan line
        print("📊 Horizontal scan at y=\(barScanY)")
        var scanLineOutput = ""
        for x in Int(origin.x)..<pixelData.width {
            let color = pixelData.colorAt(x: x, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            
            if white < 0.2 {
                scanLineOutput += "█"  // Black
            } else if white < 0.85 {
                scanLineOutput += "░"  // Blue/light (BAR)
            } else {
                scanLineOutput += " "  // White
            }
        }
        print(scanLineOutput)
        
        // DEBUG: Print actual white values for first 50 pixels
        print("📊 Detailed color values at y=\(barScanY):")
        for x in Int(origin.x)..<min(Int(origin.x) + 50, pixelData.width) {
            let color = pixelData.colorAt(x: x, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            let symbol = white < 0.2 ? "█" : (white < 0.85 ? "░" : " ")
            print("  x=\(x): white=\(String(format: "%.2f", white)) [\(symbol)]")
        }
        
        // STEP 2: Scan horizontally to find BLUE bars (not black separators!)
        let maxX = pixelData.width
        var currentX = Int(origin.x)
        
        var inBar = false
        var barStartX = 0
        
        while currentX < maxX {
            let color = pixelData.colorAt(x: currentX, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            
            //let isBar = white >= 0.2 && white < 0.85  // Blue/light blue = bar
            let isBar = white >= 0.85 && white < 0.90
            
            if isBar {
                if !inBar {
                    // Entering a new bar
                    barStartX = currentX
                    inBar = true
                    
                    if verbose {
                        print("🔵 Bar started at x=\(barStartX)")
                    }
                }
            } else {
                if inBar {
                    // Exiting a bar
                    let barEndX = currentX - 1
                    let barWidth = barEndX - barStartX + 1
                    let midX = (barStartX + barEndX) / 2
                    
                    if verbose {
                        print("🔍 Bar ended: start=\(barStartX), end=\(barEndX), width=\(barWidth), midX=\(midX)")
                    }
                    
                    // Only process if bar is reasonable size
                    if barWidth >= 2 {
                        // STEP 3: Scan UPWARD (increasing Y) to find where bar ends
                        var topY = barScanY + 1
                        var foundTop = false
                        
                        while topY < pixelData.height {
                            let colorAbove = pixelData.colorAt(x: midX, y: topY)
                            var whiteAbove: CGFloat = 0
                            colorAbove.getWhite(&whiteAbove, alpha: nil)
                            
                            // If we hit white background (>= 0.85), this is the top
                            if whiteAbove >= 0.95 {
                                foundTop = true
                                topY -= 1  // Move back to last non-white pixel
                                break
                            }
                            topY += 1
                        }
                        
                        if foundTop {
                            let top = CGPoint(x: midX, y: topY)
                            let bottom = CGPoint(x: midX, y: barScanY)
                            barPoints.append((top: top, bottom: bottom))
                            
                            print("✓ Bar detected: midX=\(midX), topY=\(topY), bottomY=\(barScanY), height=\(topY - barScanY)")
                        } else {
                            if verbose {
                                print("⚠️ Could not find bar top for bar at midX=\(midX)")
                            }
                        }
                    } else {
                        if verbose {
                            print("⊗ Bar too narrow (\(barWidth)px), skipping")
                        }
                    }
                    
                    inBar = false
                }
            }
            
            currentX += 1
        }
        
        print("✅ Detected \(barPoints.count) bars")
        return barPoints
    }
    func detectBarTopsUsingGapColumn(
        in pixelData: PixelData,
        from origin: CGPoint,
        gapX: Int,
        verbose: Bool = false
    ) -> [(top: CGPoint, bottom: CGPoint)] {
        var barPoints: [(top: CGPoint, bottom: CGPoint)] = []
        
        // STEP 1: Find barScanY (first white row after origin)
        var barScanY = Int(origin.y)
        while barScanY < pixelData.height {
            let color = pixelData.colorAt(x: gapX, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            if white > 0.95 { break }
            barScanY += 1
        }
        
        print("🧭 Found barScanY at y=\(barScanY)")
        
        // STEP 2: Scan horizontally to find white bar centers
        let maxX = pixelData.width
        var currentX = Int(origin.x)
        var inBar = false
        var barStartX = 0
        
        while currentX < maxX {
            let color = pixelData.colorAt(x: currentX, y: barScanY)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            
            let isBar = white >= 0.85 && white < 0.90
            
            if isBar {
                if !inBar {
                    barStartX = currentX
                    inBar = true
                }
            } else {
                if inBar {
                    let barEndX = currentX - 1
                    let barWidth = barEndX - barStartX + 1
                    let midX = (barStartX + barEndX) / 2
                    
                    if barWidth >= 2 {
                        var topY = barScanY + 1
                        var foundTop = false
                        
                        while topY < pixelData.height {
                            let colorAbove = pixelData.colorAt(x: midX, y: topY)
                            var whiteAbove: CGFloat = 0
                            colorAbove.getWhite(&whiteAbove, alpha: nil)
                            
                            if whiteAbove >= 0.95 {
                                foundTop = true
                                topY -= 1
                                break
                            }
                            topY += 1
                        }
                        
                        if foundTop {
                            let top = CGPoint(x: midX, y: topY)
                            let bottom = CGPoint(x: midX, y: barScanY)
                            barPoints.append((top: top, bottom: bottom))
                        }
                    }
                    
                    inBar = false
                }
            }
            
            currentX += 1
        }
        
        // STEP 3: Fill in missing bars (zero data days)
        if barPoints.count > 10 {
            // Calculate average spacing between bars
            var spacings: [Int] = []
            for i in 1..<min(40, barPoints.count) {
                let spacing = Int(barPoints[i].bottom.x - barPoints[i-1].bottom.x)
                spacings.append(spacing)
            }
            let avgSpacing = spacings.reduce(0, +) / spacings.count
            let gapThreshold = avgSpacing + (avgSpacing / 2) // 1.5x average spacing
            
            print("📏 Average bar spacing: \(avgSpacing)px, gap threshold: \(gapThreshold)px")
            
            // Find and fill gaps
            var filledBarPoints: [(top: CGPoint, bottom: CGPoint)] = []
            filledBarPoints.append(barPoints[0])
            
            for i in 1..<barPoints.count {
                let prevX = Int(barPoints[i-1].bottom.x)
                let currX = Int(barPoints[i].bottom.x)
                let gap = currX - prevX
                
                if gap > gapThreshold {
                    // Missing bars detected
                    let missingCount = gap / avgSpacing - 1
                    print("⚠️ Gap detected between x=\(prevX) and x=\(currX): \(gap)px → inserting \(missingCount) zero bars")
                    
                    for j in 1...missingCount {
                        let interpolatedX = prevX + (avgSpacing * j)
                        let zeroBar = (
                            top: CGPoint(x: interpolatedX, y: barScanY),
                            bottom: CGPoint(x: interpolatedX, y: barScanY)
                        )
                        filledBarPoints.append(zeroBar)
                    }
                }
                
                filledBarPoints.append(barPoints[i])
            }
            
            print("✅ Detected \(barPoints.count) bars, filled to \(filledBarPoints.count) bars")
            return filledBarPoints
        }
        
        print("✅ Detected \(barPoints.count) bars")
        return barPoints
    }
   

    private func findNextBlackLine(in pixelData: PixelData, startingAt x: Int, y: Int) -> Int? {
        for x in x..<pixelData.width {
            let color = pixelData.colorAt(x: x, y: y)
            var white: CGFloat = 0
            color.getWhite(&white, alpha: nil)
            if white < 0.2 {
                return x
            }
        }
        return nil
    }
}


import UIKit
import CoreGraphics

struct PixelData {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let data: UnsafePointer<UInt8>

    init(image: CGImage) {
        self.width = image.width
        self.height = image.height
        let bytesPerPixel = 4
        self.bytesPerRow = bytesPerPixel * width

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // allocate buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)

        let ctx = CGContext(data: buffer,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: bitmapInfo)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        self.data = UnsafePointer(buffer)
    }

    func colorAt(x: Int, y: Int) -> UIColor {
        // UIKit’s (0,0) is top-left, CoreGraphics’ is bottom-left
        // Here y=0 means bottom of image
        let offset = ((height - y - 1) * width + x) * 4
        let r = CGFloat(data[offset]) / 255.0
        let g = CGFloat(data[offset + 1]) / 255.0
        let b = CGFloat(data[offset + 2]) / 255.0
        let a = CGFloat(data[offset + 3]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}


struct DebugOverlay {
    var origin: CGPoint?
    var barTops: [CGPoint] = []
    var barBottoms: [CGPoint] = []
    var yTicks: [CGPoint] = []
    var yAxisColumn: Int?
    var barScanY: Int?
    // Add more fields later if needed
}
