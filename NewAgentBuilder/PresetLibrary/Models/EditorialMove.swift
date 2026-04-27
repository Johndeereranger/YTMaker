//
//  EditorialMove.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Editorial Move: A semantic abstraction above raw keyframes.
//  While TransformPreset stores raw keyframe data, EditorialMove
//  captures the INTENT - "Zoom Punch", "Ken Burns", "Reframe Left", etc.
//

import Foundation
import CoreMedia

// MARK: - Move Category

/// High-level category of the move
enum MoveCategory: String, Codable, CaseIterable {
    case scale       // Zooms, punches
    case position    // Reframes, shifts
    case rotation    // Tilts, spins
    case compound    // Multiple properties animated together

    var displayName: String {
        switch self {
        case .scale: return "Scale"
        case .position: return "Position"
        case .rotation: return "Rotation"
        case .compound: return "Compound"
        }
    }
}

// MARK: - Move Pattern

/// Recognized signature patterns
enum MovePattern: String, Codable, CaseIterable {
    // Scale patterns
    case zoomPunch           // Quick zoom in (e.g., 115% → 140% in <1s)
    case zoomIn              // Gradual zoom in
    case zoomOut             // Gradual zoom out
    case zoomHold            // Scale changes then holds
    case kenBurns            // Slow cinematic zoom (typically >3s)

    // Position patterns
    case reframeLeft         // Shift left to reframe
    case reframeRight        // Shift right to reframe
    case reframeUp           // Shift up
    case reframeDown         // Shift down
    case positionDrift       // Slow position movement

    // Rotation patterns
    case tiltLeft            // Rotate counter-clockwise
    case tiltRight           // Rotate clockwise
    case dutchAngle          // Dramatic tilt

    // Compound patterns
    case zoomAndPan          // Zoom + position together
    case customCompound      // Multi-property but no recognized pattern

    // Unknown
    case unknown             // Couldn't classify

    var displayName: String {
        switch self {
        case .zoomPunch: return "Zoom Punch"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .zoomHold: return "Zoom & Hold"
        case .kenBurns: return "Ken Burns"
        case .reframeLeft: return "Reframe Left"
        case .reframeRight: return "Reframe Right"
        case .reframeUp: return "Reframe Up"
        case .reframeDown: return "Reframe Down"
        case .positionDrift: return "Position Drift"
        case .tiltLeft: return "Tilt Left"
        case .tiltRight: return "Tilt Right"
        case .dutchAngle: return "Dutch Angle"
        case .zoomAndPan: return "Zoom & Pan"
        case .customCompound: return "Custom Compound"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .zoomPunch: return "bolt.fill"
        case .zoomIn, .zoomOut, .zoomHold: return "magnifyingglass"
        case .kenBurns: return "film"
        case .reframeLeft: return "arrow.left"
        case .reframeRight: return "arrow.right"
        case .reframeUp: return "arrow.up"
        case .reframeDown: return "arrow.down"
        case .positionDrift: return "wind"
        case .tiltLeft: return "rotate.left"
        case .tiltRight: return "rotate.right"
        case .dutchAngle: return "rectangle.portrait.rotate"
        case .zoomAndPan: return "viewfinder"
        case .customCompound: return "square.stack.3d.up"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Move Signature

/// The quantitative signature of a move - used for pattern matching
struct MoveSignature: Codable {
    // Scale values (percentage, e.g., 100 = normal, 140 = 140%)
    var startScale: Double?
    var endScale: Double?
    var scaleChange: Double? {
        guard let start = startScale, let end = endScale else { return nil }
        return end - start
    }

    // Position values (pixels from center) - stored as x,y pairs
    var startPositionX: Double?
    var startPositionY: Double?
    var endPositionX: Double?
    var endPositionY: Double?

    var positionDeltaX: Double? {
        guard let start = startPositionX, let end = endPositionX else { return nil }
        return end - start
    }

    var positionDeltaY: Double? {
        guard let start = startPositionY, let end = endPositionY else { return nil }
        return end - start
    }

    // Rotation values (degrees)
    var startRotation: Double?
    var endRotation: Double?
    var rotationChange: Double? {
        guard let start = startRotation, let end = endRotation else { return nil }
        return end - start
    }

    // Timing
    var durationSeconds: Double

    /// Check if this signature matches the "Zoom Punch" pattern
    /// Criteria: ~25% scale increase in under 1 second
    var isZoomPunch: Bool {
        guard let change = scaleChange else { return false }
        return change >= 20 && change <= 50 && durationSeconds < 1.0
    }

    /// Check if this is a Ken Burns style slow zoom
    /// Criteria: Any scale change over 3+ seconds
    var isKenBurns: Bool {
        guard let change = scaleChange, abs(change) > 5 else { return false }
        return durationSeconds >= 3.0
    }

    /// Check if this is a simple zoom in
    var isZoomIn: Bool {
        guard let change = scaleChange else { return false }
        return change > 0 && !isZoomPunch && !isKenBurns
    }

    /// Check if this is a simple zoom out
    var isZoomOut: Bool {
        guard let change = scaleChange else { return false }
        return change < 0 && !isKenBurns
    }

    /// Check if position has significant movement (more than 10 pixels)
    var hasPositionMovement: Bool {
        guard let dx = positionDeltaX, let dy = positionDeltaY else { return false }
        let distance = sqrt(dx * dx + dy * dy)
        return distance > 10
    }

    /// Check if primarily moving left
    var isReframeLeft: Bool {
        guard let dx = positionDeltaX else { return false }
        return dx < -10
    }

    /// Check if primarily moving right
    var isReframeRight: Bool {
        guard let dx = positionDeltaX else { return false }
        return dx > 10
    }

    /// Check if rotation is significant
    var hasRotation: Bool {
        guard let change = rotationChange else { return false }
        return abs(change) > 1 // More than 1 degree
    }
}

extension MoveSignature: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(startScale)
        hasher.combine(endScale)
        hasher.combine(startPositionX)
        hasher.combine(startPositionY)
        hasher.combine(endPositionX)
        hasher.combine(endPositionY)
        hasher.combine(startRotation)
        hasher.combine(endRotation)
        hasher.combine(durationSeconds)
    }

    static func == (lhs: MoveSignature, rhs: MoveSignature) -> Bool {
        lhs.startScale == rhs.startScale &&
        lhs.endScale == rhs.endScale &&
        lhs.startPositionX == rhs.startPositionX &&
        lhs.startPositionY == rhs.startPositionY &&
        lhs.endPositionX == rhs.endPositionX &&
        lhs.endPositionY == rhs.endPositionY &&
        lhs.startRotation == rhs.startRotation &&
        lhs.endRotation == rhs.endRotation &&
        lhs.durationSeconds == rhs.durationSeconds
    }
}

// MARK: - Editorial Move

/// A semantic editorial move - the abstraction above raw keyframes
struct EditorialMove: Identifiable, Codable, Hashable {
    let id: UUID

    /// Human-readable name (e.g., "Zoom Punch 115→140%")
    var name: String

    /// The pattern this move matches
    var pattern: MovePattern

    /// High-level category
    var category: MoveCategory

    /// Quantitative signature for matching
    var signature: MoveSignature

    /// Original transform preset this was derived from
    var sourceTransformId: UUID?

    /// Source FCPXML file
    var sourceFile: String?

    /// How many times this exact move appeared in the source
    var occurrenceCount: Int

    /// User-provided tags
    var tags: [String]

    /// Is this a favorite
    var isFavorite: Bool

    /// When was this move first seen
    let createdAt: Date

    /// Last update time
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        pattern: MovePattern,
        category: MoveCategory,
        signature: MoveSignature,
        sourceTransformId: UUID? = nil,
        sourceFile: String? = nil,
        occurrenceCount: Int = 1,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.category = category
        self.signature = signature
        self.sourceTransformId = sourceTransformId
        self.sourceFile = sourceFile
        self.occurrenceCount = occurrenceCount
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Classification Result

/// Result of classifying raw transforms into editorial moves
struct MoveClassificationResult {
    /// Moves that were successfully classified
    var moves: [EditorialMove]

    /// Transforms that were filtered out (no keyframes)
    var filteredEmptyCount: Int

    /// Transforms that were filtered out (static, no change)
    var filteredStaticCount: Int

    /// Transforms that couldn't be classified
    var unclassifiedCount: Int

    /// Original transform count
    var originalCount: Int

    /// Summary for display
    var summary: String {
        """
        Original: \(originalCount) transforms
        Filtered (empty): \(filteredEmptyCount)
        Filtered (static): \(filteredStaticCount)
        Unclassified: \(unclassifiedCount)
        Classified: \(moves.count) moves
        """
    }

    /// Moves grouped by pattern
    var movesByPattern: [MovePattern: [EditorialMove]] {
        Dictionary(grouping: moves, by: { $0.pattern })
    }

    /// Moves grouped by category
    var movesByCategory: [MoveCategory: [EditorialMove]] {
        Dictionary(grouping: moves, by: { $0.category })
    }
}
