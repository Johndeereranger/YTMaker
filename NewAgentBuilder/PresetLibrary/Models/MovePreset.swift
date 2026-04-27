//
//  MovePreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Three-layer architecture for editorial moves:
//
//  1. MoveDefinition - Pure intent, no numbers (except timing)
//     "Zoom Punch" = quick scale increase for emphasis
//
//  2. ProjectStyle - Per-video framing with NAMED zoom levels
//     BASE=115%, MEDIUM=127%, PUNCH=140% for THIS video
//
//  3. MovePreset - The button that combines definition + style
//
//  Key insight: Moves reference NAMED levels, not raw percentages.
//  "Zoom Punch" = BASE → PUNCH (whatever those mean for this video)
//

import Foundation

// MARK: - Zoom Level (Named, Semantic)

/// Named zoom levels - these are SEMANTIC, not percentages.
/// The actual % values come from ProjectStyle.
enum ZoomLevel: String, Codable, CaseIterable, Hashable {
    case wide       // Pulled back, context shot
    case base       // Default talking head
    case medium     // Slight emphasis
    case punch      // Strong emphasis
    case extreme    // Maximum zoom

    var displayName: String {
        switch self {
        case .wide: return "Wide"
        case .base: return "Base"
        case .medium: return "Medium"
        case .punch: return "Punch"
        case .extreme: return "Extreme"
        }
    }

    /// Order for sorting (wide=0, base=1, etc.)
    var order: Int {
        switch self {
        case .wide: return 0
        case .base: return 1
        case .medium: return 2
        case .punch: return 3
        case .extreme: return 4
        }
    }
}

// MARK: - Project Style

/// Per-video framing style with NAMED zoom levels.
/// Maps semantic names (BASE, PUNCH) to actual percentages for THIS video.
struct ProjectStyle: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String

    /// Map each zoom level to actual percentage for this video
    /// e.g., [.base: 115, .punch: 140]
    var zoomLevels: [ZoomLevel: Double]

    /// Get the percentage for a zoom level, with fallback
    func percentage(for level: ZoomLevel) -> Double {
        zoomLevels[level] ?? defaultPercentage(for: level)
    }

    /// Default percentages if not specified
    private func defaultPercentage(for level: ZoomLevel) -> Double {
        switch level {
        case .wide: return 100
        case .base: return 115
        case .medium: return 127
        case .punch: return 140
        case .extreme: return 160
        }
    }

    /// Description of the style
    var description: String {
        let base = Int(percentage(for: .base))
        let punch = Int(percentage(for: .punch))
        return "BASE: \(base)% → PUNCH: \(punch)%"
    }

    /// All defined levels, sorted by zoom amount
    var definedLevels: [ZoomLevel] {
        zoomLevels.keys.sorted { $0.order < $1.order }
    }

    // MARK: - Factory Presets

    /// Default style (common talking head setup)
    static var `default`: ProjectStyle {
        ProjectStyle(
            id: UUID(),
            name: "Default",
            zoomLevels: [
                .wide: 100,
                .base: 115,
                .medium: 127,
                .punch: 140,
                .extreme: 160
            ]
        )
    }

    /// Tight framing (close camera, needs more zoom to punch)
    static var tightFraming: ProjectStyle {
        ProjectStyle(
            id: UUID(),
            name: "Tight Framing",
            zoomLevels: [
                .wide: 100,
                .base: 115,
                .medium: 130,
                .punch: 145,
                .extreme: 170
            ]
        )
    }

    /// Wide framing (further camera, less zoom needed)
    static var wideFraming: ProjectStyle {
        ProjectStyle(
            id: UUID(),
            name: "Wide Framing",
            zoomLevels: [
                .wide: 90,
                .base: 100,
                .medium: 112,
                .punch: 125,
                .extreme: 145
            ]
        )
    }

    /// Create from detected base and emphasis scales
    static func detected(base: Double, emphasis: Double, projectName: String = "Detected") -> ProjectStyle {
        // Calculate other levels based on the base→emphasis delta
        let delta = emphasis - base
        return ProjectStyle(
            id: UUID(),
            name: projectName,
            zoomLevels: [
                .wide: base - delta * 0.6,      // Pull back from base
                .base: base,
                .medium: base + delta * 0.5,    // Halfway to punch
                .punch: emphasis,
                .extreme: emphasis + delta * 0.5 // Beyond punch
            ]
        )
    }
}

// MARK: - Position & Rotation Types

/// Direction of position movement
enum PositionDirection: String, Codable, Hashable, CaseIterable {
    case left, right, up, down, diagonal
}

/// Magnitude of position movement
enum PositionMagnitude: String, Codable, Hashable, CaseIterable {
    case small      // < 20px
    case medium     // 20-50px
    case large      // > 50px

    static func from(_ pixels: Double) -> PositionMagnitude {
        switch abs(pixels) {
        case ..<20: return .small
        case 20..<50: return .medium
        default: return .large
        }
    }

    var displayName: String {
        switch self {
        case .small: return "~10px"
        case .medium: return "~35px"
        case .large: return "50px+"
        }
    }
}

/// Direction of rotation
enum RotationDirection: String, Codable, Hashable, CaseIterable {
    case clockwise, counterClockwise
}

/// Magnitude of rotation
enum RotationMagnitude: String, Codable, Hashable, CaseIterable {
    case subtle     // < 5°
    case moderate   // 5-15°
    case dramatic   // > 15°

    static func from(_ degrees: Double) -> RotationMagnitude {
        switch abs(degrees) {
        case ..<5: return .subtle
        case 5..<15: return .moderate
        default: return .dramatic
        }
    }
}

// MARK: - Move Definition

/// Pure editorial intent - no scale/position numbers here.
/// These are UNIVERSAL across all projects.
enum MoveDefinition: String, Codable, CaseIterable, Hashable {

    // Scale moves (the INTENT, not the numbers)
    case zoomPunch          // Quick punch in for emphasis
    case zoomIn             // Gradual move closer
    case zoomOut            // Gradual move back
    case zoomReset          // Return to base framing
    case kenBurns           // Slow ambient drift (distinct from zoom - ambient, not emphatic)

    // Position moves
    case reframeLeft
    case reframeRight
    case reframeUp
    case reframeDown
    case positionDrift      // Slow ambient position change

    // Rotation moves
    case tiltLeft
    case tiltRight
    case dutchAngle         // Dramatic tilt

    // Compound
    case zoomAndPan         // Scale + position together

    var displayName: String {
        switch self {
        case .zoomPunch: return "Zoom Punch"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .zoomReset: return "Zoom Reset"
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
        }
    }

    var icon: String {
        switch self {
        case .zoomPunch: return "bolt.fill"
        case .zoomIn, .zoomOut, .zoomReset: return "magnifyingglass"
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
        }
    }

    var category: MoveCategory {
        switch self {
        case .zoomPunch, .zoomIn, .zoomOut, .zoomReset, .kenBurns:
            return .scale
        case .reframeLeft, .reframeRight, .reframeUp, .reframeDown, .positionDrift:
            return .position
        case .tiltLeft, .tiltRight, .dutchAngle:
            return .rotation
        case .zoomAndPan:
            return .compound
        }
    }

    /// Is this an ambient/background move (Ken Burns, drift) vs emphatic (punch)?
    var isAmbient: Bool {
        switch self {
        case .kenBurns, .positionDrift:
            return true
        default:
            return false
        }
    }

    /// Does this move need project-specific scale context?
    /// TRUE = values depend on video framing (zoom punch, reframe)
    /// FALSE = self-contained, absolute values (Ken Burns on image)
    var needsProjectContext: Bool {
        switch self {
        case .zoomPunch, .zoomIn, .zoomOut, .zoomReset:
            return true  // Scale depends on video framing
        case .reframeLeft, .reframeRight, .reframeUp, .reframeDown:
            return true  // Distance depends on framing
        case .kenBurns, .positionDrift, .dutchAngle, .tiltLeft, .tiltRight, .zoomAndPan:
            return false // Self-contained, absolute values
        }
    }

    // MARK: - Zoom Level Transitions (for project-style moves)

    /// Which zoom level this move starts FROM
    /// Only relevant for scale moves that use project style
    var fromLevel: ZoomLevel? {
        switch self {
        case .zoomPunch: return .base
        case .zoomIn: return .base
        case .zoomOut: return .punch
        case .zoomReset: return .punch
        default: return nil
        }
    }

    /// Which zoom level this move goes TO
    var toLevel: ZoomLevel? {
        switch self {
        case .zoomPunch: return .punch
        case .zoomIn: return .medium  // Gradual, stops at medium
        case .zoomOut: return .base
        case .zoomReset: return .base
        default: return nil
        }
    }
}

// MARK: - Duration Preset

/// Universal timing options - these DON'T change per project
enum DurationPreset: String, Codable, CaseIterable, Hashable {
    case instant    // ~0.03s - snap cut feel
    case quick      // ~0.3s  - punchy
    case medium     // ~0.5s  - standard
    case slow       // ~1.0s  - deliberate
    case verySlow   // ~2.0s  - dramatic
    case ambient    // 5.0s+  - Ken Burns territory

    var seconds: Double {
        switch self {
        case .instant: return 0.03
        case .quick: return 0.3
        case .medium: return 0.5
        case .slow: return 1.0
        case .verySlow: return 2.0
        case .ambient: return 5.0
        }
    }

    var displayName: String {
        switch self {
        case .instant: return "Instant"
        case .quick: return "Quick (~0.3s)"
        case .medium: return "Medium (~0.5s)"
        case .slow: return "Slow (~1s)"
        case .verySlow: return "Very Slow (~2s)"
        case .ambient: return "Ambient (5s+)"
        }
    }
}

// MARK: - Project Scale Context (Legacy, for backward compatibility)

/// Per-project framing settings.
/// These numbers depend on how the video was shot (camera distance, framing).
/// The SAME video will use the SAME values throughout.
///
/// NOTE: This is the legacy format. Use ProjectStyle for new code.
struct ProjectScaleContext: Codable, Hashable, Identifiable {
    let id: UUID

    /// Project/video name this context belongs to
    var projectName: String

    // MARK: - Scale Levels (percentages)

    /// Default "talking head" framing - where you return to
    /// e.g., 115% for a close camera, 100% for a wider shot
    var baseScale: Double

    /// "Punched in" emphasis level
    /// e.g., 140% when base is 115%, or 130% when base is 100%
    var emphasisScale: Double

    /// "Pulled back" wide framing (optional)
    var wideScale: Double?

    /// Maximum zoom level (for extreme emphasis)
    var maxScale: Double?

    // MARK: - Computed

    /// The zoom punch delta for this project
    var punchDelta: Double {
        emphasisScale - baseScale
    }

    /// Description of the scale setup
    var scaleDescription: String {
        "Base: \(Int(baseScale))% → Emphasis: \(Int(emphasisScale))%"
    }

    /// Convert to the new ProjectStyle format
    func toStyle() -> ProjectStyle {
        ProjectStyle.detected(
            base: baseScale,
            emphasis: emphasisScale,
            projectName: projectName
        )
    }

    // MARK: - Factory

    /// Default context (common talking head setup)
    static var `default`: ProjectScaleContext {
        ProjectScaleContext(
            id: UUID(),
            projectName: "Default",
            baseScale: 115,
            emphasisScale: 140,
            wideScale: 100,
            maxScale: 160
        )
    }

    /// Create from detected base and emphasis scales
    static func detected(base: Double, emphasis: Double, projectName: String = "Detected") -> ProjectScaleContext {
        ProjectScaleContext(
            id: UUID(),
            projectName: projectName,
            baseScale: base,
            emphasisScale: emphasis,
            wideScale: base - (emphasis - base) * 0.6,
            maxScale: emphasis + 20
        )
    }
}

// MARK: - Move Variant

/// Specific parameter combination learned from classification.
/// Multiple variants can exist for the same MoveDefinition.
struct MoveVariant: Identifiable, Codable, Hashable {
    let id: UUID

    /// Which move this is a variant of
    var definition: MoveDefinition

    /// Duration for this variant
    var duration: DurationPreset

    /// Exact duration in seconds (learned from source)
    var exactDuration: Double?

    // Position specifics (for reframe moves)
    var positionDirection: PositionDirection?
    var positionMagnitude: PositionMagnitude?

    // Rotation specifics
    var rotationDirection: RotationDirection?
    var rotationMagnitude: RotationMagnitude?

    /// How many times this variant appeared in source
    var occurrenceCount: Int

    /// Average duration from source material
    var averageSourceDuration: Double?

    /// Human-readable name for this variant
    var displayName: String {
        var name = definition.displayName
        if duration != .medium {
            name += " (\(duration.displayName))"
        }
        if let dir = positionDirection, let mag = positionMagnitude {
            name += " \(dir.rawValue) \(mag.displayName)"
        }
        return name
    }
}

// MARK: - Move Preset (The Button)

/// The thing the user actually clicks.
/// Combines a MoveDefinition with project context to produce actual keyframes.
struct MovePreset: Identifiable, Codable, Hashable {
    let id: UUID

    /// Display name for the button
    var name: String

    /// The editorial intent
    var definition: MoveDefinition

    /// Preferred timing
    var duration: DurationPreset

    /// Allow user to adjust duration?
    var durationFlexible: Bool

    /// Easing
    var easeIn: Bool
    var easeOut: Bool

    // MARK: - Position/Rotation (for non-scale moves)

    /// For reframe moves - which direction
    var positionDirection: PositionDirection?
    var positionMagnitude: PositionMagnitude?

    /// For rotation moves
    var rotationDirection: RotationDirection?
    var rotationMagnitude: RotationMagnitude?

    // MARK: - Absolute Values (for self-contained moves)

    /// For self-contained moves (Ken Burns, etc.) - absolute scale values
    /// Only used when definition.needsProjectContext == false
    var absoluteScaleFrom: Double?
    var absoluteScaleTo: Double?

    /// Absolute position offset in pixels (for self-contained position moves)
    var absolutePositionX: Double?
    var absolutePositionY: Double?

    /// Absolute rotation in degrees
    var absoluteRotation: Double?

    // MARK: - Raw Data (for visibility/debugging)

    /// Actual average duration in seconds from classification
    /// Use this to identify trash (e.g., 70s = B-roll tracking, not a real move)
    var averageDurationSeconds: Double?

    // MARK: - Metadata

    /// How confident are we this is a real pattern (from classification)
    var confidence: Int  // sourceOccurrences

    /// User tags
    var tags: [String]

    /// Favorite
    var isFavorite: Bool

    /// Source file this was learned from
    var sourceFile: String?

    /// Creation date
    let createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        definition: MoveDefinition,
        duration: DurationPreset = .medium,
        durationFlexible: Bool = true,
        easeIn: Bool = false,
        easeOut: Bool = true,
        positionDirection: PositionDirection? = nil,
        positionMagnitude: PositionMagnitude? = nil,
        rotationDirection: RotationDirection? = nil,
        rotationMagnitude: RotationMagnitude? = nil,
        absoluteScaleFrom: Double? = nil,
        absoluteScaleTo: Double? = nil,
        absolutePositionX: Double? = nil,
        absolutePositionY: Double? = nil,
        absoluteRotation: Double? = nil,
        averageDurationSeconds: Double? = nil,
        confidence: Int = 0,
        tags: [String] = [],
        isFavorite: Bool = false,
        sourceFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.definition = definition
        self.duration = duration
        self.durationFlexible = durationFlexible
        self.easeIn = easeIn
        self.easeOut = easeOut
        self.positionDirection = positionDirection
        self.positionMagnitude = positionMagnitude
        self.rotationDirection = rotationDirection
        self.rotationMagnitude = rotationMagnitude
        self.absoluteScaleFrom = absoluteScaleFrom
        self.absoluteScaleTo = absoluteScaleTo
        self.absolutePositionX = absolutePositionX
        self.absolutePositionY = absolutePositionY
        self.absoluteRotation = absoluteRotation
        self.averageDurationSeconds = averageDurationSeconds
        self.confidence = confidence
        self.tags = tags
        self.isFavorite = isFavorite
        self.sourceFile = sourceFile
        self.createdAt = Date()
    }

    // MARK: - Application

    /// Generate actual scale values using ProjectStyle (preferred).
    /// - For self-contained moves: uses absoluteScaleFrom/To
    /// - For project-style moves: uses named zoom levels
    func scaleValues(using style: ProjectStyle) -> (from: Double, to: Double)? {
        // Self-contained moves use absolute values
        if !definition.needsProjectContext {
            if let from = absoluteScaleFrom, let to = absoluteScaleTo {
                return (from, to)
            }
            // Default Ken Burns values if not specified
            if definition == .kenBurns {
                return (100, 115)  // Standard Ken Burns: 100% → 115%
            }
            return nil
        }

        // Project-style moves use named zoom levels
        guard let fromLevel = definition.fromLevel,
              let toLevel = definition.toLevel else {
            return nil
        }

        return (style.percentage(for: fromLevel), style.percentage(for: toLevel))
    }

    /// Generate actual scale values using legacy ProjectScaleContext.
    /// - For self-contained moves: uses absoluteScaleFrom/To
    /// - For context-dependent moves: uses project context
    func scaleValues(using context: ProjectScaleContext? = nil) -> (from: Double, to: Double)? {

        // Self-contained moves use absolute values
        if !definition.needsProjectContext {
            if let from = absoluteScaleFrom, let to = absoluteScaleTo {
                return (from, to)
            }
            // Default Ken Burns values if not specified
            if definition == .kenBurns {
                return (100, 115)  // Standard Ken Burns: 100% → 115%
            }
            return nil
        }

        // Context-dependent moves need project context
        guard let context = context else {
            return nil  // Can't apply without context
        }

        switch definition {
        case .zoomPunch:
            return (context.baseScale, context.emphasisScale)
        case .zoomIn:
            return (context.baseScale, context.emphasisScale)
        case .zoomOut:
            return (context.emphasisScale, context.baseScale)
        case .zoomReset:
            return (context.emphasisScale, context.baseScale)
        default:
            return nil  // Position/rotation moves don't use scale
        }
    }

    /// Generate position offset values
    func positionValues(using context: ProjectScaleContext? = nil) -> (x: Double, y: Double)? {
        // Self-contained moves use absolute values
        if !definition.needsProjectContext {
            if let x = absolutePositionX, let y = absolutePositionY {
                return (x, y)
            }
            return nil
        }

        // Context-dependent reframes - use magnitude as guide
        // The actual pixels would depend on resolution, but magnitude gives intent
        guard let magnitude = positionMagnitude else { return nil }

        let pixels: Double
        switch magnitude {
        case .small: pixels = 10
        case .medium: pixels = 35
        case .large: pixels = 60
        }

        switch definition {
        case .reframeLeft: return (-pixels, 0)
        case .reframeRight: return (pixels, 0)
        case .reframeUp: return (0, -pixels)
        case .reframeDown: return (0, pixels)
        default: return nil
        }
    }

    /// Generate rotation value in degrees
    func rotationValue() -> Double? {
        if let absolute = absoluteRotation {
            return absolute
        }

        guard let magnitude = rotationMagnitude else { return nil }

        let degrees: Double
        switch magnitude {
        case .subtle: degrees = 3
        case .moderate: degrees = 10
        case .dramatic: degrees = 20
        }

        switch definition {
        case .tiltLeft: return -degrees
        case .tiltRight: return degrees
        case .dutchAngle: return degrees
        default: return nil
        }
    }
}

// MARK: - Built-in Presets

extension MovePreset {

    // MARK: - Context-Dependent (need ProjectScaleContext)

    /// Zoom Punch - needs project context for scale values
    static var zoomPunch: MovePreset {
        MovePreset(
            name: "Zoom Punch",
            definition: .zoomPunch,
            duration: .medium,
            durationFlexible: true,
            easeOut: true,
            tags: ["emphasis", "energy"]
            // NO absolute values - uses project's baseScale → emphasisScale
        )
    }

    static var zoomPunchQuick: MovePreset {
        MovePreset(
            name: "Zoom Punch (Quick)",
            definition: .zoomPunch,
            duration: .quick,
            durationFlexible: true,
            easeOut: true,
            tags: ["emphasis", "energy", "fast"]
        )
    }

    /// Reframe - needs project context for distance
    static var reframeLeft: MovePreset {
        MovePreset(
            name: "Reframe Left",
            definition: .reframeLeft,
            duration: .quick,
            positionDirection: .left,
            positionMagnitude: .medium,
            tags: ["reframe"]
            // NO absolute values - magnitude interpreted based on framing
        )
    }

    // MARK: - Self-Contained (absolute values, same on any video)

    /// Ken Burns - self-contained, always 100% → 115% over ~5s
    static var kenBurnsIn: MovePreset {
        MovePreset(
            name: "Ken Burns In",
            definition: .kenBurns,
            duration: .ambient,
            durationFlexible: true,
            easeIn: true,
            easeOut: true,
            absoluteScaleFrom: 100,  // Always starts at 100%
            absoluteScaleTo: 115,    // Always ends at 115%
            tags: ["ambient", "cinematic", "b-roll", "image"]
        )
    }

    /// Ken Burns Out - self-contained, always 115% → 100%
    static var kenBurnsOut: MovePreset {
        MovePreset(
            name: "Ken Burns Out",
            definition: .kenBurns,
            duration: .ambient,
            durationFlexible: true,
            easeIn: true,
            easeOut: true,
            absoluteScaleFrom: 115,
            absoluteScaleTo: 100,
            tags: ["ambient", "cinematic", "b-roll", "image"]
        )
    }

    /// Dutch Angle - self-contained, always ~15° rotation
    static var dutchAngle: MovePreset {
        MovePreset(
            name: "Dutch Angle",
            definition: .dutchAngle,
            duration: .slow,
            durationFlexible: true,
            easeIn: true,
            easeOut: true,
            absoluteRotation: 15,  // Always 15 degrees
            tags: ["dramatic", "rotation"]
        )
    }

    /// Slow drift - self-contained ambient motion
    static var positionDrift: MovePreset {
        MovePreset(
            name: "Position Drift",
            definition: .positionDrift,
            duration: .ambient,
            durationFlexible: true,
            easeIn: true,
            easeOut: true,
            absolutePositionX: 20,  // Slow drift 20px right
            absolutePositionY: 10,  // and 10px down
            tags: ["ambient", "subtle"]
        )
    }
}

// MARK: - Move Library

/// Collection of presets + project style
struct MoveLibrary: Codable {
    var presets: [MovePreset]

    /// Legacy: ProjectScaleContext (for backward compatibility)
    var projectContext: ProjectScaleContext?

    /// New: ProjectStyle with named zoom levels (computed from projectContext)
    var projectStyle: ProjectStyle? {
        projectContext?.toStyle()
    }

    var count: Int { presets.count }

    func byCategory() -> [MoveCategory: [MovePreset]] {
        Dictionary(grouping: presets, by: { $0.definition.category })
    }

    func byDefinition() -> [MoveDefinition: [MovePreset]] {
        Dictionary(grouping: presets, by: { $0.definition })
    }

    var favorites: [MovePreset] {
        presets.filter { $0.isFavorite }
    }
}
