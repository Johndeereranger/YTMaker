//
//  EditPreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Base protocol and common types for all edit presets.
//  Presets are reusable edit patterns extracted from FCPXML files.
//

import Foundation
import CoreMedia

// MARK: - Edit Preset Protocol

/// Base protocol for all edit presets
protocol EditPreset: Identifiable, Codable {
    var id: UUID { get }
    var name: String { get set }
    var description: String? { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var sourceFile: String? { get }  // Original FCPXML filename
    var tags: [String] { get set }
    var isFavorite: Bool { get set }

    /// The type of edit this preset represents
    var editType: EditType { get }
}

// MARK: - Edit Types

/// Categories of edits we support
enum EditType: String, Codable, CaseIterable {
    case transform      // Position, scale, rotation animations
    case textOverlay    // Titles, lower thirds, captions
    case transition     // Cross dissolve, wipe, etc.
    case bRoll          // Video overlay patterns

    var displayName: String {
        switch self {
        case .transform: return "Transform"
        case .textOverlay: return "Text Overlay"
        case .transition: return "Transition"
        case .bRoll: return "B-Roll"
        }
    }

    var icon: String {
        switch self {
        case .transform: return "arrow.up.left.and.arrow.down.right"
        case .textOverlay: return "textformat"
        case .transition: return "rectangle.2.swap"
        case .bRoll: return "film.stack"
        }
    }
}

// MARK: - Anchor Types

/// How an edit attaches to the timeline
enum AnchorType: String, Codable, CaseIterable {
    case phrase          // Start of a transcript phrase
    case phraseEnd       // End of a transcript phrase
    case word            // Specific word in transcript
    case cutPoint        // A cut/edit boundary
    case previousEditEnd // Chains to wherever the last edit ended
    case absolute        // Specific timecode (not relative)

    var displayName: String {
        switch self {
        case .phrase: return "Phrase Start"
        case .phraseEnd: return "Phrase End"
        case .word: return "Word"
        case .cutPoint: return "Cut Point"
        case .previousEditEnd: return "After Previous Edit"
        case .absolute: return "Absolute Time"
        }
    }
}

// MARK: - Anchor Edge

/// Which end of the edit is "locked" to the anchor point
enum AnchorEdge: String, Codable {
    case start  // The start value is locked to edit begin
    case end    // The end value is locked to edit end
}

// MARK: - Duration Type

/// How duration is determined
enum DurationType: String, Codable {
    case explicit   // Preset specifies exact duration
    case inherited  // Duration matches the underlying element (phrase, word, etc.)
    case flexible   // User can adjust after application
}

// MARK: - Rational Time

/// Wrapper for storing CMTime in presets (uses CodableCMTime from VideoEditor)
/// Re-exported here for convenience in PresetLibrary
typealias RationalTime = CodableCMTime

// MARK: - Point

/// 2D point for positions (matches FCPXML format)
struct Point2D: Codable, Hashable {
    var x: Double
    var y: Double

    static var zero: Point2D { Point2D(x: 0, y: 0) }

    /// Parse from FCPXML format: "x y" (space-separated)
    init?(fcpxmlString: String) {
        let parts = fcpxmlString.split(separator: " ")
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]) else {
            return nil
        }
        self.x = x
        self.y = y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Convert to FCPXML format: "x y"
    func toFCPXMLString() -> String {
        "\(x) \(y)"
    }
}

// MARK: - Color

/// RGBA color (matches FCPXML format: values 0-1)
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static var white: RGBAColor { RGBAColor(red: 1, green: 1, blue: 1, alpha: 1) }
    static var black: RGBAColor { RGBAColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// Parse from FCPXML format: "r g b a" (space-separated, 0-1)
    init?(fcpxmlString: String) {
        let parts = fcpxmlString.split(separator: " ")
        guard parts.count == 4,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]),
              let a = Double(parts[3]) else {
            return nil
        }
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Convert to FCPXML format: "r g b a"
    func toFCPXMLString() -> String {
        "\(red) \(green) \(blue) \(alpha)"
    }
}

// MARK: - Keyframe

/// A single keyframe in an animation
struct Keyframe<T: Codable & Hashable>: Codable, Hashable {
    let time: RationalTime
    let value: T

    init(time: RationalTime, value: T) {
        self.time = time
        self.value = value
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(time)
        hasher.combine(value)
    }

    static func == (lhs: Keyframe<T>, rhs: Keyframe<T>) -> Bool {
        lhs.time == rhs.time && lhs.value == rhs.value
    }
}

// MARK: - Keyframe Animation

/// An animation defined by keyframes
struct KeyframeAnimation<T: Codable & Hashable>: Codable, Hashable {
    var keyframes: [Keyframe<T>]

    var startValue: T? { keyframes.first?.value }
    var endValue: T? { keyframes.last?.value }

    var duration: RationalTime? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        return last.time - first.time
    }

    init(keyframes: [Keyframe<T>]) {
        self.keyframes = keyframes
    }

    /// Create a simple two-point animation
    init(from startValue: T, to endValue: T, duration: RationalTime) {
        self.keyframes = [
            Keyframe(time: .zero, value: startValue),
            Keyframe(time: duration, value: endValue)
        ]
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyframes)
    }

    static func == (lhs: KeyframeAnimation<T>, rhs: KeyframeAnimation<T>) -> Bool {
        lhs.keyframes == rhs.keyframes
    }
}
