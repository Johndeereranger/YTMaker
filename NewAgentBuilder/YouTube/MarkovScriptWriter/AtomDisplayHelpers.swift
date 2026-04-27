//
//  AtomDisplayHelpers.swift
//  NewAgentBuilder
//
//  Shared display utilities for atom/slot types.
//  Extracted from SkeletonLabView and StructureWorkbenchView
//  so every view renders atoms with identical colors and abbreviations.
//

import SwiftUI

enum AtomDisplayHelpers {

    static func color(for slotType: String) -> Color {
        switch slotType {
        case "geographic_location":   return Color(hue: 0.55, saturation: 0.6, brightness: 0.8)
        case "visual_detail":         return Color(hue: 0.75, saturation: 0.5, brightness: 0.8)
        case "quantitative_claim":    return Color(hue: 0.08, saturation: 0.7, brightness: 0.9)
        case "temporal_marker":       return Color(hue: 0.15, saturation: 0.6, brightness: 0.9)
        case "actor_reference":       return Color(hue: 0.60, saturation: 0.5, brightness: 0.7)
        case "contradiction":         return Color(hue: 0.0, saturation: 0.6, brightness: 0.85)
        case "sensory_detail":        return Color(hue: 0.45, saturation: 0.5, brightness: 0.8)
        case "rhetorical_question":   return Color(hue: 0.85, saturation: 0.5, brightness: 0.8)
        case "evaluative_claim":      return Color(hue: 0.12, saturation: 0.5, brightness: 0.85)
        case "pivot_phrase":          return Color(hue: 0.95, saturation: 0.6, brightness: 0.8)
        case "direct_address":        return Color(hue: 0.30, saturation: 0.6, brightness: 0.75)
        case "narrative_action":      return Color(hue: 0.35, saturation: 0.6, brightness: 0.8)
        case "abstract_framing":      return Color(hue: 0.70, saturation: 0.4, brightness: 0.7)
        case "comparison":            return Color(hue: 0.50, saturation: 0.5, brightness: 0.75)
        case "empty_connector":       return Color(hue: 0.0, saturation: 0.0, brightness: 0.6)
        case "factual_relay":         return Color(hue: 0.58, saturation: 0.4, brightness: 0.85)
        case "reaction_beat":         return Color(hue: 0.05, saturation: 0.7, brightness: 0.85)
        case "visual_anchor":         return Color(hue: 0.42, saturation: 0.55, brightness: 0.75)
        case "other":                 return Color(hue: 0.0, saturation: 0.0, brightness: 0.5)
        default:                      return .secondary
        }
    }

    static func abbreviate(_ atom: String) -> String {
        let parts = atom.split(separator: "_")
        if parts.count >= 2 {
            return "\(parts[0].prefix(3))_\(parts[1].prefix(3))"
        }
        return String(atom.prefix(7))
    }
}
