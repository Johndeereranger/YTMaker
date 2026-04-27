//
//  MoveClassifierService.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Classifies raw TransformPresets into semantic EditorialMoves.
//
//  Key insight: A single FCPXML transform can contain MULTIPLE moves.
//  For example, a 5-minute clip might have 5 zoom punches at different
//  times - all stored as keyframes in ONE transform element.
//
//  This classifier:
//  1. Segments transforms into individual keyframe-to-keyframe moves
//  2. Normalizes similar patterns (0.4s and 0.7s are "same" duration)
//  3. Deduplicates into canonical presets with occurrence counts
//

import Foundation
import CoreMedia

// MARK: - Move Segment

/// A single segment extracted from a transform (keyframe N to keyframe N+1)
struct MoveSegment: Hashable {
    let startTime: Double
    let endTime: Double
    var duration: Double { endTime - startTime }

    // Scale
    let startScale: Double?
    let endScale: Double?
    var scaleChange: Double? {
        guard let s = startScale, let e = endScale else { return nil }
        return e - s
    }

    // Position
    let startPosX: Double?
    let startPosY: Double?
    let endPosX: Double?
    let endPosY: Double?
    var positionDeltaX: Double? {
        guard let s = startPosX, let e = endPosX else { return nil }
        return e - s
    }
    var positionDeltaY: Double? {
        guard let s = startPosY, let e = endPosY else { return nil }
        return e - s
    }

    // Rotation
    let startRotation: Double?
    let endRotation: Double?
    var rotationChange: Double? {
        guard let s = startRotation, let e = endRotation else { return nil }
        return e - s
    }

    /// Is this segment actually animating (not static)?
    var isAnimated: Bool {
        // Check scale change
        if let change = scaleChange, abs(change) >= 1.0 {
            return true
        }
        // Check position change
        if let dx = positionDeltaX, let dy = positionDeltaY {
            let distance = sqrt(dx * dx + dy * dy)
            if distance >= 5.0 {
                return true
            }
        }
        // Check rotation change
        if let change = rotationChange, abs(change) >= 0.5 {
            return true
        }
        return false
    }

    // Hashable - only hash stored properties, not computed
    func hash(into hasher: inout Hasher) {
        hasher.combine(startTime)
        hasher.combine(endTime)
        hasher.combine(startScale)
        hasher.combine(endScale)
        hasher.combine(startPosX)
        hasher.combine(startPosY)
        hasher.combine(endPosX)
        hasher.combine(endPosY)
        hasher.combine(startRotation)
        hasher.combine(endRotation)
    }
}

// MARK: - Canonical Move

/// A normalized, deduplicated move pattern
struct CanonicalMove: Identifiable {
    let id = UUID()

    // Normalized values (rounded for grouping)
    let baseScale: Double?      // Starting scale (e.g., 115)
    let targetScale: Double?    // Ending scale (e.g., 140)
    let durationBucket: DurationBucket

    // Position (normalized)
    let positionDirection: PositionDirection?
    let positionMagnitude: PositionMagnitude?

    // Rotation (normalized)
    let rotationDirection: RotationDirection?
    let rotationMagnitude: RotationMagnitude?

    // Classification
    let pattern: MovePattern
    let category: MoveCategory

    // Stats
    var occurrenceCount: Int
    var rawSegments: [MoveSegment]  // Keep raw data for reference
}

extension CanonicalMove: Hashable {
    func hash(into hasher: inout Hasher) {
        // Only hash canonical properties, not id or rawSegments
        hasher.combine(baseScale)
        hasher.combine(targetScale)
        hasher.combine(durationBucket)
        hasher.combine(positionDirection)
        hasher.combine(positionMagnitude)
        hasher.combine(rotationDirection)
        hasher.combine(rotationMagnitude)
        hasher.combine(pattern)
    }

    static func == (lhs: CanonicalMove, rhs: CanonicalMove) -> Bool {
        lhs.baseScale == rhs.baseScale &&
        lhs.targetScale == rhs.targetScale &&
        lhs.durationBucket == rhs.durationBucket &&
        lhs.positionDirection == rhs.positionDirection &&
        lhs.positionMagnitude == rhs.positionMagnitude &&
        lhs.rotationDirection == rhs.rotationDirection &&
        lhs.rotationMagnitude == rhs.rotationMagnitude &&
        lhs.pattern == rhs.pattern
    }

    /// Human-readable name
    var name: String {
        switch pattern {
        case .zoomPunch:
            if let base = baseScale, let target = targetScale {
                return "Zoom Punch \(Int(base))%→\(Int(target))%"
            }
            return "Zoom Punch"

        case .zoomIn:
            if let base = baseScale, let target = targetScale {
                return "Zoom In \(Int(base))%→\(Int(target))%"
            }
            return "Zoom In"

        case .zoomOut:
            if let base = baseScale, let target = targetScale {
                return "Zoom Out \(Int(base))%→\(Int(target))%"
            }
            return "Zoom Out"

        case .kenBurns:
            if let base = baseScale, let target = targetScale {
                return "Ken Burns \(Int(base))%→\(Int(target))%"
            }
            return "Ken Burns"

        case .reframeLeft:
            if let mag = positionMagnitude {
                return "Reframe Left \(mag.displayName)"
            }
            return "Reframe Left"

        case .reframeRight:
            if let mag = positionMagnitude {
                return "Reframe Right \(mag.displayName)"
            }
            return "Reframe Right"

        case .reframeUp:
            if let mag = positionMagnitude {
                return "Reframe Up \(mag.displayName)"
            }
            return "Reframe Up"

        case .reframeDown:
            if let mag = positionMagnitude {
                return "Reframe Down \(mag.displayName)"
            }
            return "Reframe Down"

        case .positionDrift:
            if let mag = positionMagnitude {
                return "Position Drift \(mag.displayName)"
            }
            return "Position Drift"

        default:
            return pattern.displayName
        }
    }

    var scaleChange: Double? {
        guard let base = baseScale, let target = targetScale else { return nil }
        return target - base
    }

    /// Average duration from all occurrences
    var averageDuration: Double {
        guard !rawSegments.isEmpty else { return 0 }
        return rawSegments.map { $0.duration }.reduce(0, +) / Double(rawSegments.count)
    }
}

// MARK: - Normalization Enums

enum DurationBucket: String, Codable, Hashable {
    case instant    // < 0.1s
    case quick      // 0.1 - 0.5s
    case medium     // 0.5 - 1.5s
    case slow       // 1.5 - 3s
    case verySlow   // > 3s

    static func from(_ seconds: Double) -> DurationBucket {
        switch seconds {
        case ..<0.1: return .instant
        case 0.1..<0.5: return .quick
        case 0.5..<1.5: return .medium
        case 1.5..<3.0: return .slow
        default: return .verySlow
        }
    }

    var displayName: String {
        switch self {
        case .instant: return "instant"
        case .quick: return "~0.3s"
        case .medium: return "~0.7s"
        case .slow: return "~2s"
        case .verySlow: return "3s+"
        }
    }
}

// Position/Rotation types are now in MovePreset.swift

// MARK: - Classification Result V2

struct MoveClassificationResultV2 {
    /// Canonical moves (deduplicated)
    var canonicalMoves: [CanonicalMove]

    /// Stats
    var originalTransformCount: Int
    var totalSegmentsExtracted: Int
    var animatedSegments: Int
    var staticSegmentsFiltered: Int

    var summary: String {
        """
        Original transforms: \(originalTransformCount)
        Segments extracted: \(totalSegmentsExtracted)
        Animated segments: \(animatedSegments)
        Static filtered: \(staticSegmentsFiltered)
        → Canonical moves: \(canonicalMoves.count)
        → Total occurrences: \(canonicalMoves.reduce(0) { $0 + $1.occurrenceCount })
        """
    }
}

// MARK: - Move Classifier Service

class MoveClassifierService {
    static let shared = MoveClassifierService()

    private init() {}

    // MARK: - Main Classification (V2 - Segment Based)

    func classifyV2(_ transforms: [TransformPreset], sourceFile: String? = nil) -> MoveClassificationResultV2 {
        var allSegments: [MoveSegment] = []

        print("[V2] Step 1: Extracting segments from \(transforms.count) transforms...")

        // Step 1: Extract all segments from all transforms
        for (index, transform) in transforms.enumerated() {
            if index % 50 == 0 {
                print("[V2]   Processing transform \(index)/\(transforms.count)")
            }
            let segments = extractSegments(from: transform)
            allSegments.append(contentsOf: segments)
        }

        let totalSegments = allSegments.count
        print("[V2] Step 1 complete: \(totalSegments) segments extracted")

        // Step 2: Filter to only animated segments
        print("[V2] Step 2: Filtering animated segments...")
        let animatedSegments = allSegments.filter { $0.isAnimated }
        let staticCount = totalSegments - animatedSegments.count
        print("[V2] Step 2 complete: \(animatedSegments.count) animated, \(staticCount) static")

        // Step 3: Classify each segment
        print("[V2] Step 3: Grouping by canonical key...")
        var segmentsByPattern: [String: [MoveSegment]] = [:]

        for segment in animatedSegments {
            let key = canonicalKey(for: segment)
            segmentsByPattern[key, default: []].append(segment)
        }
        print("[V2] Step 3 complete: \(segmentsByPattern.count) unique patterns")

        // Step 4: Build canonical moves
        print("[V2] Step 4: Building canonical moves...")
        var canonicalMoves: [CanonicalMove] = []

        for (_, segments) in segmentsByPattern {
            if let canonical = buildCanonicalMove(from: segments) {
                canonicalMoves.append(canonical)
            }
        }

        // Sort by occurrence count
        canonicalMoves.sort { $0.occurrenceCount > $1.occurrenceCount }

        print("[V2] Classification complete: \(canonicalMoves.count) canonical moves")

        return MoveClassificationResultV2(
            canonicalMoves: canonicalMoves,
            originalTransformCount: transforms.count,
            totalSegmentsExtracted: totalSegments,
            animatedSegments: animatedSegments.count,
            staticSegmentsFiltered: staticCount
        )
    }

    // MARK: - Segment Extraction

    private func extractSegments(from transform: TransformPreset) -> [MoveSegment] {
        var segments: [MoveSegment] = []

        // Get all unique timestamps from all keyframe types
        var allTimes: Set<Double> = []

        if let scale = transform.scale {
            for kf in scale.keyframes {
                allTimes.insert(kf.time.seconds)
            }
        }
        if let position = transform.position {
            for kf in position.keyframes {
                allTimes.insert(kf.time.seconds)
            }
        }
        if let rotation = transform.rotation {
            for kf in rotation.keyframes {
                allTimes.insert(kf.time.seconds)
            }
        }

        // Sort times
        let sortedTimes = allTimes.sorted()

        // Need at least 2 timestamps to create a segment
        guard sortedTimes.count >= 2 else {
            return segments
        }

        // Build segments between consecutive times
        for i in 0..<(sortedTimes.count - 1) {
            let startTime = sortedTimes[i]
            let endTime = sortedTimes[i + 1]

            // Get values at each time
            let segment = MoveSegment(
                startTime: startTime,
                endTime: endTime,
                startScale: scaleValue(at: startTime, in: transform),
                endScale: scaleValue(at: endTime, in: transform),
                startPosX: positionX(at: startTime, in: transform),
                startPosY: positionY(at: startTime, in: transform),
                endPosX: positionX(at: endTime, in: transform),
                endPosY: positionY(at: endTime, in: transform),
                startRotation: rotationValue(at: startTime, in: transform),
                endRotation: rotationValue(at: endTime, in: transform)
            )

            segments.append(segment)
        }

        return segments
    }

    // MARK: - Value Interpolation

    private func scaleValue(at time: Double, in transform: TransformPreset) -> Double? {
        guard let scale = transform.scale else { return nil }
        return interpolateValue(at: time, keyframes: scale.keyframes.map { ($0.time.seconds, $0.value) })
    }

    private func positionX(at time: Double, in transform: TransformPreset) -> Double? {
        guard let position = transform.position else { return nil }
        return interpolateValue(at: time, keyframes: position.keyframes.map { ($0.time.seconds, $0.value.x) })
    }

    private func positionY(at time: Double, in transform: TransformPreset) -> Double? {
        guard let position = transform.position else { return nil }
        return interpolateValue(at: time, keyframes: position.keyframes.map { ($0.time.seconds, $0.value.y) })
    }

    private func rotationValue(at time: Double, in transform: TransformPreset) -> Double? {
        guard let rotation = transform.rotation else { return nil }
        return interpolateValue(at: time, keyframes: rotation.keyframes.map { ($0.time.seconds, $0.value) })
    }

    private func interpolateValue(at time: Double, keyframes: [(Double, Double)]) -> Double? {
        guard !keyframes.isEmpty else { return nil }

        // Find the keyframe at or just before this time
        var lastKF: (Double, Double)?
        var nextKF: (Double, Double)?

        for kf in keyframes {
            if kf.0 <= time {
                lastKF = kf
            }
            if kf.0 >= time && nextKF == nil {
                nextKF = kf
            }
        }

        // Exact match or before first keyframe
        if let last = lastKF, last.0 == time {
            return last.1
        }
        if let next = nextKF, next.0 == time {
            return next.1
        }

        // Interpolate between keyframes
        if let last = lastKF, let next = nextKF, last.0 != next.0 {
            let t = (time - last.0) / (next.0 - last.0)
            return last.1 + t * (next.1 - last.1)
        }

        // Use closest available
        return lastKF?.1 ?? nextKF?.1
    }

    // MARK: - Canonical Key Generation

    /// Generate a key that groups similar segments together
    private func canonicalKey(for segment: MoveSegment) -> String {
        var parts: [String] = []

        // Scale component
        if let startScale = segment.startScale, let endScale = segment.endScale {
            let normalizedStart = normalizeScale(startScale)
            let normalizedEnd = normalizeScale(endScale)
            parts.append("s:\(normalizedStart)->\(normalizedEnd)")
        }

        // Position component
        if let dx = segment.positionDeltaX, let dy = segment.positionDeltaY {
            let distance = sqrt(dx * dx + dy * dy)
            if distance >= 5 {
                let direction = positionDirection(dx: dx, dy: dy)
                let magnitude = PositionMagnitude.from(distance)
                parts.append("p:\(direction.rawValue):\(magnitude.rawValue)")
            }
        }

        // Rotation component
        if let change = segment.rotationChange, abs(change) >= 0.5 {
            let direction: RotationDirection = change > 0 ? .clockwise : .counterClockwise
            let magnitude = RotationMagnitude.from(change)
            parts.append("r:\(direction.rawValue):\(magnitude.rawValue)")
        }

        // Duration bucket
        let durationBucket = DurationBucket.from(segment.duration)
        parts.append("d:\(durationBucket.rawValue)")

        return parts.joined(separator: "|")
    }

    /// Normalize scale to nearest 5% for grouping
    private func normalizeScale(_ scale: Double) -> Int {
        return Int((scale / 5).rounded()) * 5
    }

    private func positionDirection(dx: Double, dy: Double) -> PositionDirection {
        let absDx = abs(dx)
        let absDy = abs(dy)

        if absDx > absDy * 2 {
            return dx < 0 ? .left : .right
        } else if absDy > absDx * 2 {
            return dy < 0 ? .up : .down
        } else {
            return .diagonal
        }
    }

    // MARK: - Build Canonical Move

    private func buildCanonicalMove(from segments: [MoveSegment]) -> CanonicalMove? {
        guard let first = segments.first else { return nil }

        // Use first segment as representative
        let baseScale = first.startScale.map { normalizeScale($0) }.map { Double($0) }
        let targetScale = first.endScale.map { normalizeScale($0) }.map { Double($0) }
        let durationBucket = DurationBucket.from(first.duration)

        // Position
        var posDir: PositionDirection?
        var posMag: PositionMagnitude?
        if let dx = first.positionDeltaX, let dy = first.positionDeltaY {
            let distance = sqrt(dx * dx + dy * dy)
            if distance >= 5 {
                posDir = positionDirection(dx: dx, dy: dy)
                posMag = PositionMagnitude.from(distance)
            }
        }

        // Rotation
        var rotDir: RotationDirection?
        var rotMag: RotationMagnitude?
        if let change = first.rotationChange, abs(change) >= 0.5 {
            rotDir = change > 0 ? .clockwise : .counterClockwise
            rotMag = RotationMagnitude.from(change)
        }

        // Classify pattern
        let pattern = classifySegmentPattern(first)
        let category = categoryFor(pattern)

        return CanonicalMove(
            baseScale: baseScale,
            targetScale: targetScale,
            durationBucket: durationBucket,
            positionDirection: posDir,
            positionMagnitude: posMag,
            rotationDirection: rotDir,
            rotationMagnitude: rotMag,
            pattern: pattern,
            category: category,
            occurrenceCount: segments.count,
            rawSegments: segments
        )
    }

    private func classifySegmentPattern(_ segment: MoveSegment) -> MovePattern {
        let hasScale = segment.scaleChange.map { abs($0) >= 1.0 } ?? false
        let hasPosition = {
            guard let dx = segment.positionDeltaX, let dy = segment.positionDeltaY else { return false }
            return sqrt(dx * dx + dy * dy) >= 5.0
        }()
        let hasRotation = segment.rotationChange.map { abs($0) >= 0.5 } ?? false

        // Compound
        if hasScale && hasPosition {
            return .zoomAndPan
        }
        if (hasScale && hasRotation) || (hasPosition && hasRotation) {
            return .customCompound
        }

        // Scale patterns
        if hasScale {
            let change = segment.scaleChange!
            let duration = segment.duration

            // Zoom punch: 20-50% change in < 1 second
            if change > 0 && change >= 20 && change <= 60 && duration < 1.0 {
                return .zoomPunch
            }

            // Ken Burns: slow zoom (> 3 seconds)
            if duration >= 3.0 {
                return .kenBurns
            }

            if change > 0 {
                return .zoomIn
            } else {
                return .zoomOut
            }
        }

        // Position patterns
        if hasPosition {
            let dx = segment.positionDeltaX!
            let dy = segment.positionDeltaY!

            if abs(dx) > abs(dy) * 1.5 {
                return dx < 0 ? .reframeLeft : .reframeRight
            } else if abs(dy) > abs(dx) * 1.5 {
                return dy < 0 ? .reframeUp : .reframeDown
            }
            return .positionDrift
        }

        // Rotation patterns
        if hasRotation {
            let change = segment.rotationChange!
            if abs(change) > 15 {
                return .dutchAngle
            }
            return change < 0 ? .tiltLeft : .tiltRight
        }

        return .unknown
    }

    private func categoryFor(_ pattern: MovePattern) -> MoveCategory {
        switch pattern {
        case .zoomPunch, .zoomIn, .zoomOut, .zoomHold, .kenBurns:
            return .scale
        case .reframeLeft, .reframeRight, .reframeUp, .reframeDown, .positionDrift:
            return .position
        case .tiltLeft, .tiltRight, .dutchAngle:
            return .rotation
        case .zoomAndPan, .customCompound, .unknown:
            return .compound
        }
    }

    // MARK: - Legacy Classification (V1)

    func classify(_ transforms: [TransformPreset], sourceFile: String? = nil) -> MoveClassificationResult {
        // Keep the old implementation for backwards compatibility
        // ... (original implementation)

        // For now, just return empty result - V2 is the new approach
        return MoveClassificationResult(
            moves: [],
            filteredEmptyCount: 0,
            filteredStaticCount: 0,
            unclassifiedCount: 0,
            originalCount: transforms.count
        )
    }

    // MARK: - Debug Output

    func debugDescription(_ result: MoveClassificationResultV2) -> String {
        var output = """
        ═══════════════════════════════════════════════════════════
        MOVE CLASSIFICATION RESULTS (V2 - Segment Based)
        ═══════════════════════════════════════════════════════════

        SUMMARY:
        --------
        Original transforms: \(result.originalTransformCount)
        Segments extracted:  \(result.totalSegmentsExtracted)
        Animated segments:   \(result.animatedSegments)
        Static filtered:     \(result.staticSegmentsFiltered)
        → Canonical moves:   \(result.canonicalMoves.count)
        → Total occurrences: \(result.canonicalMoves.reduce(0) { $0 + $1.occurrenceCount })

        """

        // Group by pattern
        output += """

        BY PATTERN:
        -----------

        """

        let byPattern = Dictionary(grouping: result.canonicalMoves, by: { $0.pattern })
        for pattern in MovePattern.allCases {
            if let moves = byPattern[pattern], !moves.isEmpty {
                let totalOccurrences = moves.reduce(0) { $0 + $1.occurrenceCount }
                output += "\(pattern.displayName): \(moves.count) unique, \(totalOccurrences) occurrences\n"
            }
        }

        // Detail each canonical move
        output += """

        CANONICAL MOVES:
        ----------------

        """

        for (index, move) in result.canonicalMoves.enumerated() {
            output += """
            \(index + 1). \(move.name)
               Pattern: \(move.pattern.displayName)
               Duration: \(move.durationBucket.displayName)
               Occurrences: \(move.occurrenceCount)

            """

            if let base = move.baseScale, let target = move.targetScale {
                output += "   Scale: \(Int(base))% → \(Int(target))%\n"
            }

            if let dir = move.positionDirection, let mag = move.positionMagnitude {
                output += "   Position: \(dir.rawValue) \(mag.displayName)\n"
            }

            if let dir = move.rotationDirection, let mag = move.rotationMagnitude {
                output += "   Rotation: \(dir.rawValue) \(mag.rawValue)\n"
            }

            output += "   Avg duration: \(String(format: "%.2f", move.averageDuration))s\n"
            output += "\n"
        }

        return output
    }
}
