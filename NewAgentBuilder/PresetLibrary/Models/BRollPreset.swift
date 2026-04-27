//
//  BRollPreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  B-Roll preset: video overlays placed on lane 1+.
//  Stores patterns for B-roll insertion (timing, transform, etc.)
//

import Foundation
import CoreMedia

// MARK: - B-Roll Preset

/// A reusable B-roll insertion pattern
struct BRollPreset: EditPreset, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    var sourceFile: String?
    var tags: [String]
    var isFavorite: Bool

    var editType: EditType { .bRoll }

    // MARK: - B-Roll Properties

    /// Media reference info (how to find/identify the B-roll source)
    var mediaReference: MediaReference?

    /// Source in-point (where to start in the source clip)
    var sourceIn: RationalTime?

    /// Default duration
    var defaultDuration: RationalTime?

    /// Transform to apply (optional - for Ken Burns, repositioning, etc.)
    var transform: TransformPreset?

    /// Lane to place on (1 = first overlay lane)
    var lane: Int

    /// Audio behavior
    var audioBehavior: BRollAudioBehavior

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        sourceFile: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        mediaReference: MediaReference? = nil,
        sourceIn: RationalTime? = nil,
        defaultDuration: RationalTime? = nil,
        transform: TransformPreset? = nil,
        lane: Int = 1,
        audioBehavior: BRollAudioBehavior = .mute
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceFile = sourceFile
        self.tags = tags
        self.isFavorite = isFavorite
        self.mediaReference = mediaReference
        self.sourceIn = sourceIn
        self.defaultDuration = defaultDuration
        self.transform = transform
        self.lane = lane
        self.audioBehavior = audioBehavior
    }
}

// MARK: - Media Reference

/// How to reference B-roll media
struct MediaReference: Codable, Hashable {
    /// Original filename
    var fileName: String

    /// Relative path (if applicable)
    var relativePath: String?

    /// Thumbnail data (for preview)
    var thumbnailData: Data?

    /// Asset format reference (from FCPXML)
    var formatRef: String?

    /// Frame rate info
    var frameRate: Double?

    /// Original duration
    var duration: RationalTime?

    init(
        fileName: String,
        relativePath: String? = nil,
        thumbnailData: Data? = nil,
        formatRef: String? = nil,
        frameRate: Double? = nil,
        duration: RationalTime? = nil
    ) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.thumbnailData = thumbnailData
        self.formatRef = formatRef
        self.frameRate = frameRate
        self.duration = duration
    }
}

// MARK: - B-Roll Audio Behavior

/// How to handle B-roll audio
enum BRollAudioBehavior: String, Codable, CaseIterable {
    case mute           // No audio from B-roll
    case replace        // B-roll audio replaces A-roll
    case mix            // Mix B-roll audio with A-roll
    case ducked         // Duck A-roll audio when B-roll plays

    var displayName: String {
        switch self {
        case .mute: return "Mute B-Roll Audio"
        case .replace: return "Replace with B-Roll Audio"
        case .mix: return "Mix Audio"
        case .ducked: return "Duck Main Audio"
        }
    }
}

// MARK: - FCPXML Generation

extension BRollPreset {

    /// Generate FCPXML asset-clip element
    /// - Parameters:
    ///   - offset: Timeline position
    ///   - duration: How long to show (overrides defaultDuration)
    ///   - assetRef: Resource reference ID for the media asset
    ///   - formatRef: Resource reference ID for the format
    func toFCPXML(
        offset: RationalTime,
        duration: RationalTime,
        assetRef: String,
        formatRef: String
    ) -> String {
        let sourceStart = sourceIn ?? .zero
        let clipName = mediaReference?.fileName ?? name

        var xml = """
        <asset-clip ref="\(assetRef)" lane="\(lane)" offset="\(offset.time.toFCPXMLString())"
                    name="\(escapeXML(clipName))" start="\(sourceStart.time.toFCPXMLString())" duration="\(duration.time.toFCPXMLString())"
                    format="\(formatRef)" tcFormat="NDF"
        """

        // Audio role based on behavior
        switch audioBehavior {
        case .mute:
            xml += " audioRole=\"\""
        case .replace, .mix, .ducked:
            xml += " audioRole=\"dialogue\""
        }

        xml += ">\n"

        // Add transform if present
        if let transform = transform {
            xml += transform.toFCPXML(startTime: offset)
            xml += "\n"
        }

        xml += "</asset-clip>"

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
