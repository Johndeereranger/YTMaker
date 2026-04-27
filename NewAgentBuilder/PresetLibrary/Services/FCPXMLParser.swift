//
//  FCPXMLParser.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Parses FCPXML files and extracts edits that can be saved as presets.
//  Targeting FCPXML version 1.13 (Final Cut Pro 10.6+)
//

import Foundation
import CoreMedia

// MARK: - FCPXML Parser

class FCPXMLParser {
    static let shared = FCPXMLParser()

    private init() {}

    // MARK: - Parse FCPXML

    /// Parse an FCPXML file and extract all edits
    /// - Parameter url: URL to the .fcpxml file
    /// - Returns: Parsed result containing all extracted edits
    func parse(url: URL) throws -> FCPXMLParseResult {
        let data = try Data(contentsOf: url)
        return try parse(data: data, sourceFile: url.lastPathComponent)
    }

    /// Parse FCPXML data
    /// - Parameters:
    ///   - data: Raw XML data
    ///   - sourceFile: Original filename (for preset metadata)
    /// - Returns: Parsed result containing all extracted edits
    func parse(data: Data, sourceFile: String? = nil) throws -> FCPXMLParseResult {
        let parser = XMLParser(data: data)
        let delegate = FCPXMLParserDelegate(sourceFile: sourceFile)
        parser.delegate = delegate

        guard parser.parse() else {
            if let error = parser.parserError {
                throw FCPXMLParseError.xmlParsingFailed(error.localizedDescription)
            }
            throw FCPXMLParseError.xmlParsingFailed("Unknown parsing error")
        }

        return delegate.result
    }
}

// MARK: - Parse Result

/// Result of parsing an FCPXML file
struct FCPXMLParseResult {
    /// FCPXML version
    var version: String?

    /// Project name
    var projectName: String?

    /// Source filename
    var sourceFile: String?

    /// Extracted transform presets
    var transforms: [TransformPreset] = []

    /// Extracted text overlay presets
    var textOverlays: [TextOverlayPreset] = []

    /// Extracted transition presets
    var transitions: [TransitionPreset] = []

    /// Extracted B-roll presets
    var bRolls: [BRollPreset] = []

    /// Resources defined in the FCPXML
    var resources: [String: FCPXMLResource] = [:]

    /// Total number of extracted presets
    var totalPresets: Int {
        transforms.count + textOverlays.count + transitions.count + bRolls.count
    }

    /// All presets as a flat array
    var allPresets: [any EditPreset] {
        var all: [any EditPreset] = []
        all.append(contentsOf: transforms)
        all.append(contentsOf: textOverlays)
        all.append(contentsOf: transitions)
        all.append(contentsOf: bRolls)
        return all
    }
}

// MARK: - FCPXML Resource

/// A resource defined in the FCPXML <resources> section
struct FCPXMLResource {
    var id: String
    var name: String?
    var type: ResourceType
    var uid: String?
    var src: String?

    enum ResourceType: String {
        case effect
        case format
        case asset
        case media
        case unknown
    }
}

// MARK: - Parse Errors

enum FCPXMLParseError: LocalizedError {
    case fileNotFound
    case xmlParsingFailed(String)
    case invalidFormat
    case unsupportedVersion(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "FCPXML file not found"
        case .xmlParsingFailed(let message):
            return "Failed to parse FCPXML: \(message)"
        case .invalidFormat:
            return "Invalid FCPXML format"
        case .unsupportedVersion(let version):
            return "Unsupported FCPXML version: \(version)"
        }
    }
}

// MARK: - XML Parser Delegate

private class FCPXMLParserDelegate: NSObject, XMLParserDelegate {
    var result = FCPXMLParseResult()
    private let sourceFile: String?

    // Parser state
    private var elementStack: [String] = []
    private var currentText = ""

    // Current element being parsed
    private var currentResource: FCPXMLResource?
    private var currentTransform: TransformParseState?
    private var currentTitle: TitleParseState?
    private var currentTransition: TransitionParseState?
    private var currentAssetClip: AssetClipParseState?

    // Keyframe parsing
    private var currentKeyframes: [KeyframeParseState] = []
    private var currentParamName: String?

    init(sourceFile: String?) {
        self.sourceFile = sourceFile
        self.result.sourceFile = sourceFile
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "fcpxml":
            result.version = attributes["version"]

        case "project":
            result.projectName = attributes["name"]

        // Resources
        case "effect":
            currentResource = FCPXMLResource(
                id: attributes["id"] ?? "",
                name: attributes["name"],
                type: .effect,
                uid: attributes["uid"]
            )

        case "format":
            currentResource = FCPXMLResource(
                id: attributes["id"] ?? "",
                name: attributes["name"],
                type: .format
            )

        case "asset":
            currentResource = FCPXMLResource(
                id: attributes["id"] ?? "",
                name: attributes["name"],
                type: .asset,
                src: attributes["src"]
            )

        // Transforms
        case "adjust-transform":
            currentTransform = TransformParseState()

        case "param":
            currentParamName = attributes["name"]

        case "keyframe":
            if let timeStr = attributes["time"],
               let time = CMTime.from(fcpxmlString: timeStr),
               let value = attributes["value"] {
                currentKeyframes.append(KeyframeParseState(time: time, value: value))
            }

        // Titles
        case "title":
            currentTitle = TitleParseState(
                ref: attributes["ref"],
                lane: Int(attributes["lane"] ?? "2") ?? 2,
                offset: attributes["offset"],
                duration: attributes["duration"],
                name: attributes["name"]
            )

        case "text-style":
            if currentTitle != nil {
                currentTitle?.textStyleRef = attributes["ref"]
            }

        case "text-style-def":
            currentTitle?.styleDefId = attributes["id"]

        // Transitions
        case "transition":
            currentTransition = TransitionParseState(
                name: attributes["name"],
                offset: attributes["offset"],
                duration: attributes["duration"]
            )

        case "filter-video":
            if currentTransition != nil {
                currentTransition?.filterRef = attributes["ref"]
                currentTransition?.filterName = attributes["name"]
            }

        // Asset clips (B-roll)
        case "asset-clip":
            if let lane = attributes["lane"], Int(lane) ?? 0 > 0 {
                // Only capture clips on overlay lanes (lane > 0)
                currentAssetClip = AssetClipParseState(
                    ref: attributes["ref"],
                    lane: Int(lane) ?? 1,
                    offset: attributes["offset"],
                    start: attributes["start"],
                    duration: attributes["duration"],
                    name: attributes["name"],
                    format: attributes["format"]
                )
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { elementStack.removeLast() }

        switch elementName {
        // Resources
        case "effect", "format", "asset":
            if let resource = currentResource {
                result.resources[resource.id] = resource
            }
            currentResource = nil

        // Transform keyframe animation complete
        case "keyframeAnimation":
            if let paramName = currentParamName, currentTransform != nil {
                switch paramName.lowercased() {
                case "position":
                    currentTransform?.positionKeyframes = currentKeyframes
                case "scale":
                    currentTransform?.scaleKeyframes = currentKeyframes
                case "rotation":
                    currentTransform?.rotationKeyframes = currentKeyframes
                default:
                    break
                }
            }
            currentKeyframes = []

        case "param":
            // For transition parameters
            if let transition = currentTransition, let paramName = currentParamName {
                transition.parameters.append(TransitionParameter(
                    name: paramName,
                    key: "", // Would need to parse from attributes
                    value: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            currentParamName = nil

        // Transform complete
        case "adjust-transform":
            if let state = currentTransform {
                let preset = buildTransformPreset(from: state)
                result.transforms.append(preset)
            }
            currentTransform = nil

        // Title text content
        case "text-style":
            if currentTitle != nil {
                currentTitle?.textContent = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        // Title style attributes
        case "text-style-def":
            // Style attributes are in the nested text-style element - would need deeper parsing
            break

        // Title complete
        case "title":
            if let state = currentTitle {
                let preset = buildTextOverlayPreset(from: state)
                result.textOverlays.append(preset)
            }
            currentTitle = nil

        // Transition complete
        case "transition":
            if let state = currentTransition {
                let preset = buildTransitionPreset(from: state)
                result.transitions.append(preset)
            }
            currentTransition = nil

        // Asset clip (B-roll) complete
        case "asset-clip":
            if let state = currentAssetClip {
                let preset = buildBRollPreset(from: state)
                result.bRolls.append(preset)
            }
            currentAssetClip = nil

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    // MARK: - Build Presets

    private func buildTransformPreset(from state: TransformParseState) -> TransformPreset {
        var position: KeyframeAnimation<Point2D>?
        var scale: KeyframeAnimation<Double>?
        var rotation: KeyframeAnimation<Double>?

        // Build position animation
        if !state.positionKeyframes.isEmpty {
            let keyframes = state.positionKeyframes.compactMap { kf -> Keyframe<Point2D>? in
                guard let point = Point2D(fcpxmlString: kf.value) else { return nil }
                return Keyframe(time: CodableCMTime(kf.time), value: point)
            }
            if !keyframes.isEmpty {
                position = KeyframeAnimation(keyframes: keyframes)
            }
        }

        // Build scale animation
        if !state.scaleKeyframes.isEmpty {
            let keyframes = state.scaleKeyframes.compactMap { kf -> Keyframe<Double>? in
                // Scale is "x y" format, use first value
                let parts = kf.value.split(separator: " ")
                guard let first = parts.first, let value = Double(first) else { return nil }
                return Keyframe(time: CodableCMTime(kf.time), value: value * 100) // Convert to percentage
            }
            if !keyframes.isEmpty {
                scale = KeyframeAnimation(keyframes: keyframes)
            }
        }

        // Build rotation animation
        if !state.rotationKeyframes.isEmpty {
            let keyframes = state.rotationKeyframes.compactMap { kf -> Keyframe<Double>? in
                guard let value = Double(kf.value) else { return nil }
                return Keyframe(time: CodableCMTime(kf.time), value: value)
            }
            if !keyframes.isEmpty {
                rotation = KeyframeAnimation(keyframes: keyframes)
            }
        }

        return TransformPreset(
            name: "Transform from \(sourceFile ?? "FCPXML")",
            sourceFile: sourceFile,
            tags: ["imported"],
            position: position,
            scale: scale,
            rotation: rotation
        )
    }

    private func buildTextOverlayPreset(from state: TitleParseState) -> TextOverlayPreset {
        var duration: RationalTime?
        if let durationStr = state.duration, let time = CMTime.from(fcpxmlString: durationStr) {
            duration = CodableCMTime(time)
        }

        return TextOverlayPreset(
            name: state.name ?? "Text from \(sourceFile ?? "FCPXML")",
            sourceFile: sourceFile,
            tags: ["imported"],
            templateName: result.resources[state.ref ?? ""]?.name ?? "Unknown",
            templateUID: result.resources[state.ref ?? ""]?.uid,
            defaultDuration: duration,
            lane: state.lane
        )
    }

    private func buildTransitionPreset(from state: TransitionParseState) -> TransitionPreset {
        var duration: RationalTime = .zero
        if let durationStr = state.duration, let time = CMTime.from(fcpxmlString: durationStr) {
            duration = CodableCMTime(time)
        }

        return TransitionPreset(
            name: state.name ?? "Transition from \(sourceFile ?? "FCPXML")",
            sourceFile: sourceFile,
            tags: ["imported"],
            effectName: state.filterName ?? state.name ?? "Unknown",
            effectUID: result.resources[state.filterRef ?? ""]?.uid,
            defaultDuration: duration,
            parameters: state.parameters
        )
    }

    private func buildBRollPreset(from state: AssetClipParseState) -> BRollPreset {
        var sourceIn: RationalTime?
        var duration: RationalTime?

        if let startStr = state.start, let time = CMTime.from(fcpxmlString: startStr) {
            sourceIn = CodableCMTime(time)
        }
        if let durationStr = state.duration, let time = CMTime.from(fcpxmlString: durationStr) {
            duration = CodableCMTime(time)
        }

        let resource = result.resources[state.ref ?? ""]
        let mediaRef = MediaReference(
            fileName: state.name ?? resource?.name ?? "Unknown",
            formatRef: state.format
        )

        return BRollPreset(
            name: state.name ?? "B-Roll from \(sourceFile ?? "FCPXML")",
            sourceFile: sourceFile,
            tags: ["imported"],
            mediaReference: mediaRef,
            sourceIn: sourceIn,
            defaultDuration: duration,
            lane: state.lane
        )
    }
}

// MARK: - Parse State Types

private struct KeyframeParseState {
    let time: CMTime
    let value: String
}

private class TransformParseState {
    var positionKeyframes: [KeyframeParseState] = []
    var scaleKeyframes: [KeyframeParseState] = []
    var rotationKeyframes: [KeyframeParseState] = []
}

private class TitleParseState {
    var ref: String?
    var lane: Int
    var offset: String?
    var duration: String?
    var name: String?
    var textStyleRef: String?
    var styleDefId: String?
    var textContent: String?

    init(ref: String?, lane: Int, offset: String?, duration: String?, name: String?) {
        self.ref = ref
        self.lane = lane
        self.offset = offset
        self.duration = duration
        self.name = name
    }
}

private class TransitionParseState {
    var name: String?
    var offset: String?
    var duration: String?
    var filterRef: String?
    var filterName: String?
    var parameters: [TransitionParameter] = []

    init(name: String?, offset: String?, duration: String?) {
        self.name = name
        self.offset = offset
        self.duration = duration
    }
}

private class AssetClipParseState {
    var ref: String?
    var lane: Int
    var offset: String?
    var start: String?
    var duration: String?
    var name: String?
    var format: String?

    init(ref: String?, lane: Int, offset: String?, start: String?, duration: String?, name: String?, format: String?) {
        self.ref = ref
        self.lane = lane
        self.offset = offset
        self.start = start
        self.duration = duration
        self.name = name
        self.format = format
    }
}
