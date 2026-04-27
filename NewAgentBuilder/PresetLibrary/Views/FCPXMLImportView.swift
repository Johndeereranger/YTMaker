//
//  FCPXMLImportView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  View for importing and parsing FCPXML files with video preview.
//

import SwiftUI
import AVKit
import UniformTypeIdentifiers
import CoreMedia
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FCPXMLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FCPXMLImportViewModel()

    let onImport: (FCPXMLParseResult) -> Void

    /// UTTypes that can contain FCPXML data
    /// Note: .fcpxmld is a bundle/package, .fcpxml is a single XML file
    static var fcpxmlTypes: [UTType] {
        var types: [UTType] = [.xml, .package, .folder, .bundle, .item]
        // Add Final Cut Pro's FCPXML type if available
        if let fcpxmlType = UTType("com.apple.finalcutpro.xml") {
            types.insert(fcpxmlType, at: 0)
        }
        // FCPXMLD bundle type
        if let fcpxmldType = UTType("com.apple.finalcutpro.xmld") {
            types.insert(fcpxmldType, at: 0)
        }
        return types
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.importState {
                case .selectFiles:
                    selectFilesView
                case .parsing:
                    parsingView
                case .reviewEdits:
                    reviewEditsView
                }
            }
            .navigationTitle("Import FCPXML")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if viewModel.importState == .reviewEdits {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import (\(viewModel.selectedCount))") {
                            if let result = viewModel.getSelectedResult() {
                                onImport(result)
                                dismiss()
                            }
                        }
                        .disabled(viewModel.selectedCount == 0)
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Select Files View

    private var selectFilesView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("Import FCPXML")
                    .font(.headline)

                Text("Select your FCPXML file and the source video to preview edits during import.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            VStack(spacing: 16) {
                // FCPXML File
                FileSelectionRow(
                    title: "FCPXML File",
                    fileName: viewModel.fcpxmlURL?.lastPathComponent,
                    icon: "doc.text",
                    action: { viewModel.showFCPXMLPicker = true }
                )
                .fileImporter(
                    isPresented: $viewModel.showFCPXMLPicker,
                    allowedContentTypes: FCPXMLImportView.fcpxmlTypes,
                    allowsMultipleSelection: false
                ) { result in
                    viewModel.handleFCPXMLSelection(result)
                }

                // Source Video
                FileSelectionRow(
                    title: "Source Video (for preview)",
                    fileName: viewModel.videoURL?.lastPathComponent,
                    icon: "film",
                    action: { viewModel.showVideoPicker = true }
                )
                .fileImporter(
                    isPresented: $viewModel.showVideoPicker,
                    allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi],
                    allowsMultipleSelection: false
                ) { result in
                    viewModel.handleVideoSelection(result)
                }
            }
            .padding(.horizontal)

            // Parse button
            Button {
                viewModel.parseFiles()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Parse FCPXML")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(viewModel.fcpxmlURL != nil ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.fcpxmlURL == nil)
            .padding(.horizontal)

            Spacer()

            // Help text
            helpSection
        }
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to export FCPXML from Final Cut Pro:")
                .font(.caption)
                .fontWeight(.semibold)

            Text("1. Select your project in the browser")
            Text("2. File → Export XML...")
            Text("3. Choose a location and save")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Parsing View

    private var parsingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Parsing FCPXML...")
                .font(.headline)
            Text("Extracting transforms, titles, transitions, and B-roll clips...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Review Edits View

    private var reviewEditsView: some View {
        VStack(spacing: 0) {
            // Summary header
            summaryHeader

            Divider()

            // Edit list
            List {
                ForEach($viewModel.editItems) { $item in
                    EditReviewRow(
                        item: $item,
                        videoURL: viewModel.videoURL,
                        onPreview: { viewModel.previewEdit(item) }
                    )
                }
            }
            .listStyle(.plain)

            // Video preview (if active)
            if viewModel.showingPreview, let player = viewModel.previewPlayer {
                Divider()
                videoPreviewSection(player: player)
            }
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Review Edits")
                        .font(.headline)
                    if let name = viewModel.parseResult?.projectName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("\(viewModel.selectedCount) selected")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text("of \(viewModel.editItems.count) edits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Breakdown by type
            if let result = viewModel.parseResult {
                HStack(spacing: 16) {
                    debugCountBadge("Transforms", count: result.transforms.count, color: .purple)
                    debugCountBadge("Text", count: result.textOverlays.count, color: .orange)
                    debugCountBadge("Transitions", count: result.transitions.count, color: .green)
                    debugCountBadge("B-Roll", count: result.bRolls.count, color: .blue)
                }
                .font(.caption2)
            }

            // Debug copy buttons
            HStack(spacing: 12) {
                Button {
                    viewModel.copyRawXML()
                } label: {
                    Label("Copy Raw XML", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.copyParsedResults()
                } label: {
                    Label("Copy Parsed JSON", systemImage: "list.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.copyDebugSummary()
                } label: {
                    Label("Copy Debug Info", systemImage: "ladybug")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            // Move Classification button
            Button {
                viewModel.classifyMoves()
            } label: {
                HStack {
                    if viewModel.isClassifying {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                        Text("Classifying...")
                    } else {
                        Image(systemName: "wand.and.stars")
                        Text("Classify Moves")
                    }
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(viewModel.isClassifying ? Color.gray : Color.purple)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isClassifying)
            .sheet(isPresented: $viewModel.showingMoveClassification) {
                if let classResult = viewModel.moveClassificationResult {
                    MoveClassificationResultsView(
                        result: classResult,
                        sourceFile: viewModel.parseResult?.sourceFile
                    )
                }
            }
        }
        .padding()
    }

    private func debugCountBadge(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func videoPreviewSection(player: AVPlayer) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Preview")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    viewModel.closePreview()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            VideoPlayer(player: player)
                .frame(height: 200)
                .cornerRadius(8)
                .padding(.horizontal)

            if let item = viewModel.previewingItem {
                Text("\(item.editType.displayName) • \(formatTime(item.startTime)) - \(formatTime(item.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
    }

    private func formatTime(_ time: Double?) -> String {
        guard let time = time else { return "--:--" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, ms)
    }

}

// MARK: - File Selection Row

struct FileSelectionRow: View {
    let title: String
    let fileName: String?
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline)
                    if let fileName = fileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Not selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Review Row

struct EditReviewRow: View {
    @Binding var item: EditReviewItem
    let videoURL: URL?
    let onPreview: () -> Void

    var body: some View {
        HStack {
            // Checkbox
            Button {
                item.isSelected.toggle()
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isSelected ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())

            // Icon
            Image(systemName: item.editType.icon)
                .foregroundColor(.blue)
                .frame(width: 30)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $item.name)
                    .font(.headline)

                Text(item.editType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let start = item.startTime, let end = item.endTime {
                    Text("\(formatTime(start)) - \(formatTime(end))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Preview button
            if videoURL != nil && item.startTime != nil {
                Button {
                    onPreview()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Edit Review Item

struct EditReviewItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    let editType: EditType
    var isSelected: Bool
    let startTime: Double?  // In seconds
    let endTime: Double?    // In seconds

    init(id: UUID, name: String, editType: EditType, startTime: Double? = nil, endTime: Double? = nil) {
        self.id = id
        self.name = name
        self.editType = editType
        self.isSelected = true  // Default to selected
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Import State

enum FCPXMLImportState {
    case selectFiles
    case parsing
    case reviewEdits
}

// MARK: - View Model

@MainActor
class FCPXMLImportViewModel: ObservableObject {
    @Published var importState: FCPXMLImportState = .selectFiles
    @Published var showFCPXMLPicker = false
    @Published var showVideoPicker = false
    @Published var fcpxmlURL: URL?
    @Published var videoURL: URL?
    @Published var parseResult: FCPXMLParseResult?
    @Published var editItems: [EditReviewItem] = []
    @Published var showingError = false
    @Published var errorMessage: String?

    // Preview
    @Published var showingPreview = false
    @Published var previewPlayer: AVPlayer?
    @Published var previewingItem: EditReviewItem?

    // Move Classification (V2 - Segment Based)
    @Published var moveClassificationResult: MoveClassificationResultV2?
    @Published var showingMoveClassification = false

    private let parser = FCPXMLParser.shared
    private let moveClassifier = MoveClassifierService.shared

    var selectedCount: Int {
        editItems.filter { $0.isSelected }.count
    }

    // MARK: - File Selection

    func handleFCPXMLSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()

            // Check if it's an .fcpxmld bundle - find the XML inside
            if url.pathExtension == "fcpxmld" {
                // FCPXMLD bundles contain the XML file with same name
                let bundleName = url.deletingPathExtension().lastPathComponent
                let xmlPath = url.appendingPathComponent("\(bundleName).fcpxml")
                if FileManager.default.fileExists(atPath: xmlPath.path) {
                    fcpxmlURL = xmlPath
                } else {
                    // Try to find any .fcpxml file in the bundle
                    if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
                       let fcpxmlFile = contents.first(where: { $0.pathExtension == "fcpxml" }) {
                        fcpxmlURL = fcpxmlFile
                    } else {
                        errorMessage = "Could not find FCPXML file inside the bundle"
                        showingError = true
                    }
                }
            } else {
                fcpxmlURL = url
            }
        case .failure(let error):
            errorMessage = "Failed to select FCPXML: \(error.localizedDescription)"
            showingError = true
        }
    }

    func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                videoURL = url
            }
        case .failure(let error):
            errorMessage = "Failed to select video: \(error.localizedDescription)"
            showingError = true
        }
    }

    // MARK: - Parsing

    func parseFiles() {
        guard let fcpxmlURL = fcpxmlURL else { return }

        importState = .parsing

        Task {
            do {
                let result = try parser.parse(url: fcpxmlURL)
                await MainActor.run {
                    self.parseResult = result
                    self.buildEditItems(from: result)
                    self.importState = .reviewEdits
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to parse FCPXML: \(error.localizedDescription)"
                    self.showingError = true
                    self.importState = .selectFiles
                }
            }
        }
    }

    private func buildEditItems(from result: FCPXMLParseResult) {
        editItems = []

        // Transforms
        for preset in result.transforms {
            // Try to get time from keyframes
            var startTime: Double?
            var endTime: Double?

            if let posKeyframes = preset.position?.keyframes {
                startTime = posKeyframes.first?.time.seconds
                endTime = posKeyframes.last?.time.seconds
            } else if let scaleKeyframes = preset.scale?.keyframes {
                startTime = scaleKeyframes.first?.time.seconds
                endTime = scaleKeyframes.last?.time.seconds
            } else if let rotKeyframes = preset.rotation?.keyframes {
                startTime = rotKeyframes.first?.time.seconds
                endTime = rotKeyframes.last?.time.seconds
            }

            let item = EditReviewItem(
                id: preset.id,
                name: preset.name,
                editType: .transform,
                startTime: startTime,
                endTime: endTime
            )
            editItems.append(item)
        }

        // Text Overlays
        for preset in result.textOverlays {
            let duration: Double? = preset.defaultDuration?.seconds
            let item = EditReviewItem(
                id: preset.id,
                name: preset.name,
                editType: .textOverlay,
                startTime: nil,
                endTime: duration
            )
            editItems.append(item)
        }

        // Transitions
        for preset in result.transitions {
            let duration: Double = preset.defaultDuration.seconds
            let item = EditReviewItem(
                id: preset.id,
                name: preset.name,
                editType: .transition,
                startTime: nil,
                endTime: duration
            )
            editItems.append(item)
        }

        // B-Roll
        for preset in result.bRolls {
            let start: Double? = preset.sourceIn?.seconds
            let duration: Double? = preset.defaultDuration?.seconds
            let end: Double? = if let s = start, let d = duration { s + d } else if let d = duration { d } else { nil }
            let item = EditReviewItem(
                id: preset.id,
                name: preset.name,
                editType: .bRoll,
                startTime: start,
                endTime: end
            )
            editItems.append(item)
        }
    }

    // MARK: - Preview

    func previewEdit(_ item: EditReviewItem) {
        guard let videoURL = videoURL, let startTime = item.startTime else { return }

        // Calculate preview range: ±1 second
        let previewStart = max(0, startTime - 1.0)

        let player = AVPlayer(url: videoURL)
        player.seek(to: CMTime(seconds: previewStart, preferredTimescale: 600))
        player.play()

        previewPlayer = player
        previewingItem = item
        showingPreview = true
    }

    func closePreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewingItem = nil
        showingPreview = false
    }

    // MARK: - Get Selected Result

    func getSelectedResult() -> FCPXMLParseResult? {
        guard var result = parseResult else { return nil }

        let selectedIds = Set(editItems.filter { $0.isSelected }.map { $0.id })

        // Update names from edited items
        let nameMap = Dictionary(uniqueKeysWithValues: editItems.map { ($0.id, $0.name) })

        result.transforms = result.transforms.filter { selectedIds.contains($0.id) }.map { preset in
            var updated = preset
            if let name = nameMap[preset.id] {
                updated.name = name
            }
            return updated
        }

        result.textOverlays = result.textOverlays.filter { selectedIds.contains($0.id) }.map { preset in
            var updated = preset
            if let name = nameMap[preset.id] {
                updated.name = name
            }
            return updated
        }

        result.transitions = result.transitions.filter { selectedIds.contains($0.id) }.map { preset in
            var updated = preset
            if let name = nameMap[preset.id] {
                updated.name = name
            }
            return updated
        }

        result.bRolls = result.bRolls.filter { selectedIds.contains($0.id) }.map { preset in
            var updated = preset
            if let name = nameMap[preset.id] {
                updated.name = name
            }
            return updated
        }

        return result
    }

    // MARK: - Debug Copy Functions

    func copyRawXML() {
        guard let url = fcpxmlURL else {
            errorMessage = "No FCPXML file loaded"
            showingError = true
            return
        }

        do {
            let xmlString = try String(contentsOf: url, encoding: .utf8)
            #if os(iOS)
            UIPasteboard.general.string = xmlString
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(xmlString, forType: .string)
            #endif
            print("Copied \(xmlString.count) characters of raw XML")
        } catch {
            errorMessage = "Failed to read XML: \(error.localizedDescription)"
            showingError = true
        }
    }

    func copyParsedResults() {
        guard let result = parseResult else {
            errorMessage = "No parsed results"
            showingError = true
            return
        }

        var output = "=== FCPXML PARSE RESULTS ===\n"
        output += "Project: \(result.projectName ?? "Unknown")\n"
        output += "Source: \(result.sourceFile ?? "Unknown")\n"
        output += "Version: \(result.version ?? "Unknown")\n\n"

        output += "=== TRANSFORMS (\(result.transforms.count)) ===\n"
        for (i, t) in result.transforms.enumerated() {
            output += "\n[\(i)] \(t.name)\n"
            output += "  ID: \(t.id)\n"
            if let pos = t.position {
                output += "  Position keyframes: \(pos.keyframes.count)\n"
                for kf in pos.keyframes {
                    output += "    - time: \(kf.time.seconds)s, value: (\(kf.value.x), \(kf.value.y))\n"
                }
            }
            if let scale = t.scale {
                output += "  Scale keyframes: \(scale.keyframes.count)\n"
                for kf in scale.keyframes {
                    output += "    - time: \(kf.time.seconds)s, value: \(kf.value)%\n"
                }
            }
            if let rot = t.rotation {
                output += "  Rotation keyframes: \(rot.keyframes.count)\n"
                for kf in rot.keyframes {
                    output += "    - time: \(kf.time.seconds)s, value: \(kf.value)°\n"
                }
            }
        }

        output += "\n=== TEXT OVERLAYS (\(result.textOverlays.count)) ===\n"
        for (i, t) in result.textOverlays.enumerated() {
            output += "\n[\(i)] \(t.name)\n"
            output += "  ID: \(t.id)\n"
            output += "  Template: \(t.templateName)\n"
            output += "  Lane: \(t.lane)\n"
            if let dur = t.defaultDuration {
                output += "  Duration: \(dur.seconds)s\n"
            }
        }

        output += "\n=== TRANSITIONS (\(result.transitions.count)) ===\n"
        for (i, t) in result.transitions.enumerated() {
            output += "\n[\(i)] \(t.name)\n"
            output += "  ID: \(t.id)\n"
            output += "  Effect: \(t.effectName)\n"
            output += "  Duration: \(t.defaultDuration.seconds)s\n"
            output += "  Parameters: \(t.parameters.count)\n"
        }

        output += "\n=== B-ROLL (\(result.bRolls.count)) ===\n"
        for (i, b) in result.bRolls.enumerated() {
            output += "\n[\(i)] \(b.name)\n"
            output += "  ID: \(b.id)\n"
            output += "  Lane: \(b.lane)\n"
            if let media = b.mediaReference {
                output += "  Media: \(media.fileName)\n"
            }
            if let dur = b.defaultDuration {
                output += "  Duration: \(dur.seconds)s\n"
            }
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("Copied parsed results (\(output.count) characters)")
    }

    func copyDebugSummary() {
        guard let result = parseResult else {
            errorMessage = "No parsed results"
            showingError = true
            return
        }

        var output = "=== DEBUG SUMMARY ===\n\n"
        output += "FCPXML URL: \(fcpxmlURL?.path ?? "nil")\n"
        output += "Video URL: \(videoURL?.path ?? "nil")\n\n"

        output += "COUNTS:\n"
        output += "  Transforms: \(result.transforms.count)\n"
        output += "  Text Overlays: \(result.textOverlays.count)\n"
        output += "  Transitions: \(result.transitions.count)\n"
        output += "  B-Roll: \(result.bRolls.count)\n"
        output += "  TOTAL: \(result.totalPresets)\n\n"

        output += "RESOURCES FOUND: \(result.resources.count)\n"
        for (id, res) in result.resources.prefix(20) {
            output += "  [\(id)] \(res.name ?? "unnamed") (\(res.type.rawValue))\n"
        }
        if result.resources.count > 20 {
            output += "  ... and \(result.resources.count - 20) more\n"
        }

        output += "\nEDIT ITEMS IN UI: \(editItems.count)\n"
        output += "  Selected: \(selectedCount)\n"

        // Sample of first few items
        output += "\nFIRST 10 EDIT ITEMS:\n"
        for (i, item) in editItems.prefix(10).enumerated() {
            output += "  [\(i)] \(item.editType.displayName): \(item.name)\n"
            if let start = item.startTime {
                output += "       Start: \(start)s\n"
            }
            if let end = item.endTime {
                output += "       End: \(end)s\n"
            }
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("Copied debug summary")
    }

    // MARK: - Move Classification (V2 - Segment Based)

    @Published var isClassifying = false

    func classifyMoves() {
        guard let result = parseResult else {
            errorMessage = "No parsed results to classify"
            showingError = true
            return
        }

        guard !isClassifying else { return }
        isClassifying = true

        print("=== STARTING MOVE CLASSIFICATION (V2) ===")
        print("Input: \(result.transforms.count) transforms")

        // Run classification on background thread to avoid blocking UI
        Task.detached { [weak self] in
            guard let self = self else { return }

            let classifier = MoveClassifierService.shared
            let classResult = classifier.classifyV2(
                result.transforms,
                sourceFile: result.sourceFile
            )

            // Update UI on main thread
            await MainActor.run {
                self.moveClassificationResult = classResult
                self.showingMoveClassification = true
                self.isClassifying = false

                // Print full debug output to console
                print("=== CLASSIFICATION COMPLETE ===")
                print(classResult.summary)
                print("")
                print("=== FULL DEBUG OUTPUT ===")
                let debugOutput = classifier.debugDescription(classResult)
                print(debugOutput)
                print("=== END DEBUG OUTPUT ===")
            }
        }
    }

    func copyMoveClassification() {
        guard let result = moveClassificationResult else {
            errorMessage = "No classification results to copy"
            showingError = true
            return
        }

        let output = moveClassifier.debugDescription(result)

        if output.isEmpty {
            errorMessage = "Classification output is empty"
            showingError = true
            return
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif

        // Print to console as backup
        print("=== MOVE CLASSIFICATION COPIED ===")
        print(output)
        print("=== END ===")

        // Show confirmation
        errorMessage = "Copied \(output.count) characters to clipboard!\n\nCanonical Moves: \(result.canonicalMoves.count)\nTotal Occurrences: \(result.canonicalMoves.reduce(0) { $0 + $1.occurrenceCount })\nSegments Extracted: \(result.totalSegmentsExtracted)\nAnimated: \(result.animatedSegments)"
        showingError = true
    }
}
