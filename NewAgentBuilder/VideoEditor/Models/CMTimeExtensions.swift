//
//  CMTimeExtensions.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  CMTime extensions for Codable support and convenience methods.
//  CMTime is Apple's rational time type - used throughout this app for frame-accurate timing.
//

import Foundation
import CoreMedia

// MARK: - Codable Wrapper

/// Wrapper for CMTime that provides Codable conformance.
/// We use a wrapper instead of extending CMTime directly to avoid conflicts
/// if Apple adds Codable to CMTime in the future.
struct CodableCMTime: Codable, Hashable {
    var time: CMTime

    init(_ time: CMTime) {
        self.time = time
    }

    init(value: CMTimeValue, timescale: CMTimeScale) {
        self.time = CMTime(value: value, timescale: timescale)
    }

    init(seconds: Double, preferredTimescale: CMTimeScale = 600) {
        self.time = CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
    }

    static var zero: CodableCMTime {
        CodableCMTime(.zero)
    }

    // Codable
    enum CodingKeys: String, CodingKey {
        case value
        case timescale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(CMTimeValue.self, forKey: .value)
        let timescale = try container.decode(CMTimeScale.self, forKey: .timescale)
        self.time = CMTime(value: value, timescale: timescale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time.value, forKey: .value)
        try container.encode(time.timescale, forKey: .timescale)
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(time.value)
        hasher.combine(time.timescale)
    }

    static func == (lhs: CodableCMTime, rhs: CodableCMTime) -> Bool {
        lhs.time == rhs.time
    }

    // Convenience accessors
    var seconds: Double { time.seconds }
    var value: CMTimeValue { time.value }
    var timescale: CMTimeScale { time.timescale }
}

// MARK: - CodableCMTime Comparable

extension CodableCMTime: Comparable {
    static func < (lhs: CodableCMTime, rhs: CodableCMTime) -> Bool {
        lhs.time < rhs.time
    }
}

// MARK: - CodableCMTime Arithmetic

extension CodableCMTime {
    static func + (lhs: CodableCMTime, rhs: CodableCMTime) -> CodableCMTime {
        CodableCMTime(lhs.time + rhs.time)
    }

    static func - (lhs: CodableCMTime, rhs: CodableCMTime) -> CodableCMTime {
        CodableCMTime(lhs.time - rhs.time)
    }
}

// MARK: - Convenience Initializers

extension CMTime {

    /// Create CMTime from seconds with a standard timescale (600 = good for 24/30/60fps)
    /// - Parameter seconds: Time in seconds
    /// - Returns: CMTime with 600 timescale (allows frame-accurate representation for common framerates)
    static func from(seconds: Double) -> CMTime {
        // 600 is divisible by 24, 30, and 60 - common framerates
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Create CMTime from a rational string like "13100/6000s" (FCPXML format)
    /// - Parameter fcpxmlString: Rational time string from FCPXML
    /// - Returns: CMTime, or nil if parsing fails
    static func from(fcpxmlString: String) -> CMTime? {
        // Remove trailing 's' if present
        var str = fcpxmlString.trimmingCharacters(in: .whitespaces)
        if str.hasSuffix("s") {
            str = String(str.dropLast())
        }

        // Check for rational format: "numerator/denominator"
        if str.contains("/") {
            let parts = str.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Int64(parts[0]),
                  let denominator = Int32(parts[1]) else {
                return nil
            }
            return CMTime(value: numerator, timescale: denominator)
        }

        // Plain number - treat as seconds
        if let seconds = Double(str) {
            return CMTime.from(seconds: seconds)
        }

        return nil
    }

    /// Convert to FCPXML rational string format: "numerator/denominators"
    func toFCPXMLString() -> String {
        if timescale == 1 {
            return "\(value)s"
        }
        return "\(value)/\(timescale)s"
    }
}

// MARK: - Common Timescales

extension CMTime {

    /// Standard timescales for common frame rates
    struct Timescales {
        /// 600 - Good general purpose (divisible by 24, 30, 60)
        static let standard: CMTimeScale = 600

        /// 6000 - FCPXML uses this for 60fps
        static let fcpxml60fps: CMTimeScale = 6000

        /// 30000 - FCPXML uses this for 30fps with sub-frame precision
        static let fcpxml30fps: CMTimeScale = 30000

        /// 2500 - FCPXML uses this for 25fps (PAL)
        static let fcpxml25fps: CMTimeScale = 2500
    }
}

// MARK: - Duration Formatting

extension CMTime {

    /// Format as human-readable string: "1:23.456" (minutes:seconds.milliseconds)
    func formattedString() -> String {
        let totalSeconds = self.seconds
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        let ms = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }

    /// Format as seconds with decimal: "83.456s"
    func formattedSeconds() -> String {
        return String(format: "%.3fs", self.seconds)
    }
}

// MARK: - Arithmetic Helpers

extension CMTime {

    /// Clamp time to a range
    func clamped(to range: CMTimeRange) -> CMTime {
        if self < range.start {
            return range.start
        }
        if self > range.end {
            return range.end
        }
        return self
    }

    /// Clamp time between min and max
    func clamped(min: CMTime, max: CMTime) -> CMTime {
        if self < min { return min }
        if self > max { return max }
        return self
    }
}
