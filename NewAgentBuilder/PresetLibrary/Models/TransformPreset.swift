//
//  TransformPreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Transform preset: position shifts, scale changes, rotations.
//  These are motion effects applied to clips in FCP.
//

import Foundation
import CoreMedia

// MARK: - Transform Preset

/// A reusable transform animation preset
struct TransformPreset: EditPreset, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    var sourceFile: String?
    var tags: [String]
    var isFavorite: Bool

    var editType: EditType { .transform }

    // MARK: - Transform Properties

    /// Position animation (optional - nil means no position change)
    var position: KeyframeAnimation<Point2D>?

    /// Scale animation (optional - nil means no scale change)
    /// Value is percentage: 100 = 100% = no change
    var scale: KeyframeAnimation<Double>?

    /// Rotation animation (optional - nil means no rotation)
    /// Value is degrees
    var rotation: KeyframeAnimation<Double>?

    /// Which edge of the edit is anchored
    var anchorEdge: AnchorEdge

    /// Default duration for this transform (can be overridden)
    var defaultDuration: RationalTime?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        sourceFile: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        position: KeyframeAnimation<Point2D>? = nil,
        scale: KeyframeAnimation<Double>? = nil,
        rotation: KeyframeAnimation<Double>? = nil,
        anchorEdge: AnchorEdge = .end,
        defaultDuration: RationalTime? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceFile = sourceFile
        self.tags = tags
        self.isFavorite = isFavorite
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.anchorEdge = anchorEdge
        self.defaultDuration = defaultDuration
    }
}

// MARK: - Common Transform Presets

extension TransformPreset {

    /// Shift left to recenter off-center framing
    static func shiftLeft(pixels: Double, duration: RationalTime) -> TransformPreset {
        TransformPreset(
            name: "Shift Left \(Int(pixels))px",
            description: "Shift frame left to correct off-center framing",
            tags: ["reframe", "position"],
            position: KeyframeAnimation(
                from: .zero,
                to: Point2D(x: -pixels, y: 0),
                duration: duration
            ),
            anchorEdge: .end
        )
    }

    /// Shift right to recenter off-center framing
    static func shiftRight(pixels: Double, duration: RationalTime) -> TransformPreset {
        TransformPreset(
            name: "Shift Right \(Int(pixels))px",
            description: "Shift frame right to correct off-center framing",
            tags: ["reframe", "position"],
            position: KeyframeAnimation(
                from: .zero,
                to: Point2D(x: pixels, y: 0),
                duration: duration
            ),
            anchorEdge: .end
        )
    }

    /// Subtle zoom in for emphasis
    static func zoomIn(percentage: Double, duration: RationalTime) -> TransformPreset {
        TransformPreset(
            name: "Zoom In \(Int(percentage))%",
            description: "Subtle zoom in for emphasis",
            tags: ["zoom", "emphasis"],
            scale: KeyframeAnimation(
                from: 100,
                to: 100 + percentage,
                duration: duration
            ),
            anchorEdge: .start
        )
    }

    /// Ken Burns style slow zoom
    static func kenBurns(startScale: Double, endScale: Double, duration: RationalTime) -> TransformPreset {
        TransformPreset(
            name: "Ken Burns",
            description: "Slow cinematic zoom",
            tags: ["ken burns", "cinematic", "slow"],
            scale: KeyframeAnimation(
                from: startScale,
                to: endScale,
                duration: duration
            ),
            anchorEdge: .start
        )
    }
}

// MARK: - FCPXML Generation

extension TransformPreset {

    /// Generate FCPXML adjust-transform element
    func toFCPXML(startTime: RationalTime) -> String {
        var xml = "<adjust-transform>\n"

        // Position
        if let position = position, let start = position.startValue, let end = position.endValue {
            xml += "    <param name=\"position\">\n"
            xml += "        <keyframeAnimation>\n"
            for keyframe in position.keyframes {
                let time = startTime + keyframe.time
                xml += "            <keyframe time=\"\(time.time.toFCPXMLString())\" value=\"\(keyframe.value.toFCPXMLString())\"/>\n"
            }
            xml += "        </keyframeAnimation>\n"
            xml += "    </param>\n"
        }

        // Scale
        if let scale = scale {
            xml += "    <param name=\"scale\">\n"
            xml += "        <keyframeAnimation>\n"
            for keyframe in scale.keyframes {
                let time = startTime + keyframe.time
                // FCP uses "x y" format for scale, same value for both
                let scaleValue = keyframe.value / 100.0  // Convert percentage to decimal
                xml += "            <keyframe time=\"\(time.time.toFCPXMLString())\" value=\"\(scaleValue) \(scaleValue)\"/>\n"
            }
            xml += "        </keyframeAnimation>\n"
            xml += "    </param>\n"
        }

        // Rotation
        if let rotation = rotation {
            xml += "    <param name=\"rotation\">\n"
            xml += "        <keyframeAnimation>\n"
            for keyframe in rotation.keyframes {
                let time = startTime + keyframe.time
                xml += "            <keyframe time=\"\(time.time.toFCPXMLString())\" value=\"\(keyframe.value)\"/>\n"
            }
            xml += "        </keyframeAnimation>\n"
            xml += "    </param>\n"
        }

        xml += "</adjust-transform>"
        return xml
    }
}
