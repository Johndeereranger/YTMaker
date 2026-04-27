//
//  TextOverlayPreset.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Text overlay preset: titles, lower thirds, captions.
//  Stores styling that can be applied to different text content.
//

import Foundation
import CoreMedia

// MARK: - Text Overlay Preset

/// A reusable text/title style preset
struct TextOverlayPreset: EditPreset, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    var sourceFile: String?
    var tags: [String]
    var isFavorite: Bool

    var editType: EditType { .textOverlay }

    // MARK: - Text Style Properties

    /// FCP effect reference (e.g., "Basic Title", "Lower Third")
    var templateName: String

    /// FCP effect UID (for exact matching)
    var templateUID: String?

    /// Font family name
    var fontFamily: String

    /// Font face (Regular, Bold, Italic, etc.)
    var fontFace: String

    /// Font size in points
    var fontSize: Double

    /// Text color
    var fontColor: RGBAColor

    /// Text alignment
    var alignment: TextAlignment

    /// Stroke/outline color (optional)
    var strokeColor: RGBAColor?

    /// Stroke width (optional)
    var strokeWidth: Double?

    /// Drop shadow enabled
    var dropShadow: Bool

    /// Position override (optional - nil uses template default)
    var position: Point2D?

    /// Default duration for this text
    var defaultDuration: RationalTime?

    /// Lane to place text on (1 = first overlay lane)
    var lane: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        sourceFile: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        templateName: String = "Basic Title",
        templateUID: String? = nil,
        fontFamily: String = "Helvetica",
        fontFace: String = "Regular",
        fontSize: Double = 63,
        fontColor: RGBAColor = .white,
        alignment: TextAlignment = .center,
        strokeColor: RGBAColor? = nil,
        strokeWidth: Double? = nil,
        dropShadow: Bool = false,
        position: Point2D? = nil,
        defaultDuration: RationalTime? = nil,
        lane: Int = 2
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceFile = sourceFile
        self.tags = tags
        self.isFavorite = isFavorite
        self.templateName = templateName
        self.templateUID = templateUID
        self.fontFamily = fontFamily
        self.fontFace = fontFace
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.alignment = alignment
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.dropShadow = dropShadow
        self.position = position
        self.defaultDuration = defaultDuration
        self.lane = lane
    }
}

// MARK: - Text Alignment

enum TextAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right

    var fcpxmlValue: String {
        rawValue
    }
}

// MARK: - Common Text Presets

extension TextOverlayPreset {

    /// Simple white centered title
    static var basicTitle: TextOverlayPreset {
        TextOverlayPreset(
            name: "Basic White Title",
            description: "Simple centered white title",
            tags: ["basic", "white", "centered"],
            templateName: "Basic Title",
            fontFamily: "Helvetica",
            fontFace: "Bold",
            fontSize: 72,
            fontColor: .white,
            alignment: .center
        )
    }

    /// Lower third name tag style
    static var lowerThird: TextOverlayPreset {
        TextOverlayPreset(
            name: "Lower Third",
            description: "Name tag style lower third",
            tags: ["lower third", "name"],
            templateName: "Lower Third",
            fontFamily: "Helvetica Neue",
            fontFace: "Medium",
            fontSize: 48,
            fontColor: .white,
            alignment: .left,
            position: Point2D(x: -400, y: -300),
            lane: 2
        )
    }

    /// Subtitle/caption style
    static var subtitle: TextOverlayPreset {
        TextOverlayPreset(
            name: "Subtitle",
            description: "Bottom-centered subtitle",
            tags: ["subtitle", "caption"],
            templateName: "Basic Title",
            fontFamily: "Helvetica Neue",
            fontFace: "Regular",
            fontSize: 42,
            fontColor: .white,
            alignment: .center,
            strokeColor: .black,
            strokeWidth: 2,
            dropShadow: true,
            position: Point2D(x: 0, y: -400)
        )
    }
}

// MARK: - FCPXML Generation

extension TextOverlayPreset {

    /// Generate FCPXML title element
    /// - Parameters:
    ///   - text: The actual text content
    ///   - offset: Timeline position
    ///   - duration: How long to show
    ///   - effectRef: Resource reference ID for the title effect
    ///   - styleRef: Text style reference ID
    func toFCPXML(
        text: String,
        offset: RationalTime,
        duration: RationalTime,
        effectRef: String,
        styleRef: String
    ) -> String {
        var xml = """
        <title ref="\(effectRef)" lane="\(lane)" offset="\(offset.time.toFCPXMLString())" name="\(name)" start="3600s" duration="\(duration.time.toFCPXMLString())">
            <text>
                <text-style ref="\(styleRef)">\(escapeXML(text))</text-style>
            </text>
            <text-style-def id="\(styleRef)">
                <text-style font="\(fontFamily)" fontSize="\(fontSize)" fontFace="\(fontFace)"
                            fontColor="\(fontColor.toFCPXMLString())" alignment="\(alignment.fcpxmlValue)"
        """

        if let strokeColor = strokeColor, let strokeWidth = strokeWidth {
            xml += " strokeColor=\"\(strokeColor.toFCPXMLString())\" strokeWidth=\"\(strokeWidth)\""
        }

        xml += "/>\n"
        xml += "            </text-style-def>\n"
        xml += "        </title>"

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
