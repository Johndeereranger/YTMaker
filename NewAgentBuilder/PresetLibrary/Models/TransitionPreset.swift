//
//  TransitionPreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Transition preset: cross dissolve, wipes, spins, etc.
//  These are effects applied at cut points between clips.
//

import Foundation
import CoreMedia

// MARK: - Transition Preset

/// A reusable transition effect preset
struct TransitionPreset: EditPreset, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    var sourceFile: String?
    var tags: [String]
    var isFavorite: Bool

    var editType: EditType { .transition }

    // MARK: - Transition Properties

    /// FCP effect name (e.g., "Cross Dissolve", "Spin")
    var effectName: String

    /// FCP effect UID for exact matching
    var effectUID: String?

    /// Default duration
    var defaultDuration: RationalTime

    /// Effect-specific parameters
    var parameters: [TransitionParameter]

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        sourceFile: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        effectName: String,
        effectUID: String? = nil,
        defaultDuration: RationalTime,
        parameters: [TransitionParameter] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceFile = sourceFile
        self.tags = tags
        self.isFavorite = isFavorite
        self.effectName = effectName
        self.effectUID = effectUID
        self.defaultDuration = defaultDuration
        self.parameters = parameters
    }
}

// MARK: - Transition Parameter

/// A parameter for a transition effect
struct TransitionParameter: Codable, Hashable {
    let name: String
    let key: String
    let value: String

    init(name: String, key: String, value: String) {
        self.name = name
        self.key = key
        self.value = value
    }
}

// MARK: - Common Transition Presets

extension TransitionPreset {

    /// Standard cross dissolve
    static func crossDissolve(duration: RationalTime) -> TransitionPreset {
        TransitionPreset(
            name: "Cross Dissolve",
            description: "Standard video cross dissolve",
            tags: ["dissolve", "basic", "smooth"],
            effectName: "Cross Dissolve",
            defaultDuration: duration,
            parameters: [
                TransitionParameter(name: "Look", key: "1", value: "11 (Video)"),
                TransitionParameter(name: "Amount", key: "2", value: "50"),
                TransitionParameter(name: "Ease", key: "50", value: "2 (In & Out)"),
                TransitionParameter(name: "Ease Amount", key: "51", value: "0")
            ]
        )
    }

    /// Quick cut (no transition, just a hard cut marker)
    static var hardCut: TransitionPreset {
        TransitionPreset(
            name: "Hard Cut",
            description: "No transition - hard cut",
            tags: ["cut", "hard", "instant"],
            effectName: "None",
            defaultDuration: .zero,
            parameters: []
        )
    }

    /// Fade to black
    static func fadeToBlack(duration: RationalTime) -> TransitionPreset {
        TransitionPreset(
            name: "Fade to Black",
            description: "Fade out to black",
            tags: ["fade", "black", "ending"],
            effectName: "Fade to Color",
            defaultDuration: duration,
            parameters: [
                TransitionParameter(name: "Color", key: "1", value: "0 0 0 1")
            ]
        )
    }

    /// Fade from black
    static func fadeFromBlack(duration: RationalTime) -> TransitionPreset {
        TransitionPreset(
            name: "Fade from Black",
            description: "Fade in from black",
            tags: ["fade", "black", "opening"],
            effectName: "Fade to Color",
            defaultDuration: duration,
            parameters: [
                TransitionParameter(name: "Color", key: "1", value: "0 0 0 1")
            ]
        )
    }
}

// MARK: - FCPXML Generation

extension TransitionPreset {

    /// Generate FCPXML transition element
    /// - Parameters:
    ///   - offset: Timeline position for the transition
    ///   - filterRef: Resource reference ID for the filter effect
    func toFCPXML(offset: RationalTime, filterRef: String) -> String {
        var xml = """
        <transition name="\(effectName)" offset="\(offset.time.toFCPXMLString())" duration="\(defaultDuration.time.toFCPXMLString())">
            <filter-video ref="\(filterRef)" name="\(effectName)">

        """

        for param in parameters {
            xml += "            <param name=\"\(param.name)\" key=\"\(param.key)\" value=\"\(escapeXML(param.value))\"/>\n"
        }

        xml += """
            </filter-video>
        </transition>
        """

        return xml
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
