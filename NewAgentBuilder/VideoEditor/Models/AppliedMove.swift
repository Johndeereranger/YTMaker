//
//  AppliedMove.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Represents a move applied at a specific point in the video timeline.
//
//  KEY CONCEPT: Moves are STATE TRANSITIONS, not temporary effects.
//  - A "Zoom In Medium" at 0:10 transitions TO 127% and STAYS there
//  - A "Zoom Out" at 0:30 transitions back TO 100%
//  - Position moves work the same - move left, STAY left until moved right
//

import Foundation
import CoreMedia
import SwiftUI

// MARK: - Move Type

/// The type of state change this move performs
enum MoveType: String, Codable, Hashable {
    case zoomIn         // Transition to a higher zoom level
    case zoomOut        // Transition to a lower zoom level (usually base)
    case positionLeft   // Shift frame left (subject moves right in frame)
    case positionRight  // Shift frame right
    case positionUp     // Shift frame up
    case positionDown   // Shift frame down
    case positionCenter // Return to center position
}

// MARK: - Applied Move

/// A move placed at a specific point in the video timeline.
/// The move is a TRANSITION - it changes state and that state persists.
struct AppliedMove: Identifiable, Codable, Hashable {
    let id: UUID

    /// Reference to the MovePreset that defines this move's behavior
    var movePresetId: UUID

    /// What type of move this is
    var moveType: MoveType

    /// The point in the timeline where this move starts
    var startTime: CodableCMTime

    /// Duration of the transition (how long to animate to the new state)
    var durationOverride: CodableCMTime?

    /// The duration from the preset (cached for convenience)
    var presetDurationSeconds: Double

    // MARK: - Target State (what we're transitioning TO)

    /// For zoom moves: the target zoom level (e.g., .medium = 127%, .punch = 140%)
    var targetZoomLevel: ZoomLevel?

    /// For position moves: how much to offset X (negative = left, positive = right)
    /// Value is in percentage of frame width (e.g., -5 = shift 5% left)
    var targetPositionX: Double?

    /// For position moves: how much to offset Y (negative = up, positive = down)
    var targetPositionY: Double?

    // MARK: - Computed Properties

    var startSeconds: Double {
        startTime.seconds
    }

    var durationSeconds: Double {
        durationOverride?.seconds ?? presetDurationSeconds
    }

    var endTime: CodableCMTime {
        startTime + CodableCMTime(seconds: durationSeconds)
    }

    var endSeconds: Double {
        endTime.seconds
    }

    /// Whether this is a zoom-type move
    var isZoomMove: Bool {
        moveType == .zoomIn || moveType == .zoomOut
    }

    /// Whether this is a position-type move
    var isPositionMove: Bool {
        switch moveType {
        case .positionLeft, .positionRight, .positionUp, .positionDown, .positionCenter:
            return true
        default:
            return false
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        movePresetId: UUID,
        moveType: MoveType = .zoomIn,
        startTime: CodableCMTime,
        durationOverride: CodableCMTime? = nil,
        presetDurationSeconds: Double = 0.5,
        targetZoomLevel: ZoomLevel? = nil,
        targetPositionX: Double? = nil,
        targetPositionY: Double? = nil
    ) {
        self.id = id
        self.movePresetId = movePresetId
        self.moveType = moveType
        self.startTime = startTime
        self.durationOverride = durationOverride
        self.presetDurationSeconds = presetDurationSeconds
        self.targetZoomLevel = targetZoomLevel
        self.targetPositionX = targetPositionX
        self.targetPositionY = targetPositionY
    }

    // MARK: - Backward Compatible Decoding

    private enum CodingKeys: String, CodingKey {
        case id, movePresetId, moveType, startTime, durationOverride
        case presetDurationSeconds, targetZoomLevel, targetPositionX, targetPositionY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        movePresetId = try container.decode(UUID.self, forKey: .movePresetId)
        startTime = try container.decode(CodableCMTime.self, forKey: .startTime)
        durationOverride = try container.decodeIfPresent(CodableCMTime.self, forKey: .durationOverride)
        presetDurationSeconds = try container.decode(Double.self, forKey: .presetDurationSeconds)

        // New fields with defaults for backward compatibility
        moveType = try container.decodeIfPresent(MoveType.self, forKey: .moveType) ?? .zoomIn
        targetZoomLevel = try container.decodeIfPresent(ZoomLevel.self, forKey: .targetZoomLevel) ?? .medium
        targetPositionX = try container.decodeIfPresent(Double.self, forKey: .targetPositionX)
        targetPositionY = try container.decodeIfPresent(Double.self, forKey: .targetPositionY)
    }

    /// Create from a preset at a specific time
    static func from(_ preset: MovePreset, at time: CodableCMTime) -> AppliedMove {
        // Determine move type and targets from the preset definition
        let (moveType, zoomLevel, posX, posY) = extractMoveDetails(from: preset)

        return AppliedMove(
            movePresetId: preset.id,
            moveType: moveType,
            startTime: time,
            presetDurationSeconds: preset.duration.seconds,
            targetZoomLevel: zoomLevel,
            targetPositionX: posX,
            targetPositionY: posY
        )
    }

    /// Extract move details from a preset
    private static func extractMoveDetails(from preset: MovePreset) -> (MoveType, ZoomLevel?, Double?, Double?) {
        switch preset.definition {
        case .zoomPunch:
            return (.zoomIn, .punch, nil, nil)
        case .zoomIn:
            return (.zoomIn, .medium, nil, nil)
        case .zoomOut, .zoomReset:
            return (.zoomOut, .base, nil, nil)
        case .reframeLeft:
            return (.positionLeft, nil, -5.0, nil)  // 5% left
        case .reframeRight:
            return (.positionRight, nil, 5.0, nil)  // 5% right
        case .reframeUp:
            return (.positionUp, nil, nil, -5.0)    // 5% up
        case .reframeDown:
            return (.positionDown, nil, nil, 5.0)   // 5% down
        default:
            return (.zoomIn, .medium, nil, nil)
        }
    }
}

// MARK: - Applied Move Collection Extensions

extension Array where Element == AppliedMove {
    /// Sort by start time
    var sortedByTime: [AppliedMove] {
        sorted { $0.startSeconds < $1.startSeconds }
    }

    /// Get only zoom moves, sorted by time
    var zoomMoves: [AppliedMove] {
        filter { $0.isZoomMove }.sortedByTime
    }

    /// Get only position moves, sorted by time
    var positionMoves: [AppliedMove] {
        filter { $0.isPositionMove }.sortedByTime
    }

    /// Find moves within a time range
    func moves(in range: ClosedRange<Double>) -> [AppliedMove] {
        filter { range.contains($0.startSeconds) }
    }

    /// Find the move closest to a time
    func closest(to time: Double) -> AppliedMove? {
        min(by: { abs($0.startSeconds - time) < abs($1.startSeconds - time) })
    }
}

// MARK: - Video State at Time

/// Represents the complete video transform state at a point in time
struct VideoTransformState {
    var zoomLevel: ZoomLevel = .base
    var zoomScale: CGFloat = 1.0  // Actual scale value (e.g., 1.27 for 127%)
    var positionX: CGFloat = 0    // X offset in percentage
    var positionY: CGFloat = 0    // Y offset in percentage

    /// Calculate state at a given time based on all applied moves
    static func at(
        time: Double,
        moves: [AppliedMove],
        projectStyle: ProjectStyle = .default
    ) -> VideoTransformState {
        var state = VideoTransformState()

        // Track previous zoom for interpolation
        var previousZoomScale: CGFloat = CGFloat(projectStyle.percentage(for: .base) / 100.0)
        var previousPosX: CGFloat = 0
        var previousPosY: CGFloat = 0

        let sortedMoves = moves.sortedByTime

        for move in sortedMoves {
            // If this move hasn't started yet, we're done
            if time < move.startSeconds {
                break
            }

            if move.isZoomMove {
                let targetLevel = move.targetZoomLevel ?? .base
                let targetScale = CGFloat(projectStyle.percentage(for: targetLevel) / 100.0)

                if time >= move.endSeconds {
                    // Move is complete - we're at the target state
                    state.zoomLevel = targetLevel
                    state.zoomScale = targetScale
                    previousZoomScale = targetScale
                } else {
                    // Move is in progress - interpolate
                    let progress = (time - move.startSeconds) / move.durationSeconds
                    let easedProgress = easeOutQuad(CGFloat(progress))
                    state.zoomLevel = targetLevel
                    state.zoomScale = previousZoomScale + (targetScale - previousZoomScale) * easedProgress
                }
            }

            if move.isPositionMove {
                let targetX = CGFloat(move.targetPositionX ?? 0)
                let targetY = CGFloat(move.targetPositionY ?? 0)

                // For position center, target is 0,0
                let finalTargetX = move.moveType == .positionCenter ? 0 : (previousPosX + targetX)
                let finalTargetY = move.moveType == .positionCenter ? 0 : (previousPosY + targetY)

                if time >= move.endSeconds {
                    // Move is complete
                    state.positionX = finalTargetX
                    state.positionY = finalTargetY
                    previousPosX = finalTargetX
                    previousPosY = finalTargetY
                } else {
                    // Move in progress - interpolate
                    let progress = (time - move.startSeconds) / move.durationSeconds
                    let easedProgress = easeOutQuad(CGFloat(progress))
                    state.positionX = previousPosX + (finalTargetX - previousPosX) * easedProgress
                    state.positionY = previousPosY + (finalTargetY - previousPosY) * easedProgress
                }
            }
        }

        return state
    }

    /// Ease out quadratic
    private static func easeOutQuad(_ t: CGFloat) -> CGFloat {
        return 1 - (1 - t) * (1 - t)
    }
}
