//
//  Script.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//

import SwiftUI
import Combine

// ============================================================================
// MARK: - ADD THESE CASES TO YOUR AppNavigation ENUM
// ============================================================================

/*
Add these to your existing AppNavigation enum:

case scriptHome
case newScript
case scriptEditor(YTScript)
case pointEditor(YTScript, Point)
case fullScriptView(YTScript)
case scriptSettings
*/

// ============================================================================
// MARK: - MODELS (Future-Proof for SwiftData)
// ============================================================================

// MARK: - YTScript (YouTube Script)
class YTScript: Identifiable, Codable, ObservableObject {
    var id: UUID
    @Published var title: String
    @Published var status: ScriptStatus
    var numPoints: Int
    var voiceStyleName: String
    
    @Published var hook: Hook?
    @Published var points: [Point]
    @Published var outro: Outro?
    
    var dateCreated: Date
    @Published var dateModified: Date
    
    var totalWordCount: Int {
        (hook?.wordCount ?? 0) +
        points.reduce(0) { $0 + $1.wordCount } +
        (outro?.wordCount ?? 0)
    }
    
    var estimatedDuration: String {
        let wpm = UserDefaults.standard.integer(forKey: "scriptWPM")
        let wpmValue = wpm > 0 ? Double(wpm) : 175.0
        let minutes = Double(totalWordCount) / wpmValue
        let mins = Int(minutes)
        let secs = Int((minutes - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }
    
    init(id: UUID = UUID(),
         title: String,
         status: ScriptStatus = .draft,
         numPoints: Int,
         voiceStyleName: String = "Default",
         hook: Hook? = nil,
         points: [Point] = [],
         outro: Outro? = nil,
         dateCreated: Date = Date(),
         dateModified: Date = Date()) {
        self.id = id
        self.title = title
        self.status = status
        self.numPoints = numPoints
        self.voiceStyleName = voiceStyleName
        self.hook = hook
        self.points = points
        self.outro = outro
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, status, numPoints, voiceStyleName
        case hook, points, outro, dateCreated, dateModified
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(ScriptStatus.self, forKey: .status)
        numPoints = try container.decode(Int.self, forKey: .numPoints)
        voiceStyleName = try container.decode(String.self, forKey: .voiceStyleName)
        hook = try container.decodeIfPresent(Hook.self, forKey: .hook)
        points = try container.decode([Point].self, forKey: .points)
        outro = try container.decodeIfPresent(Outro.self, forKey: .outro)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(numPoints, forKey: .numPoints)
        try container.encode(voiceStyleName, forKey: .voiceStyleName)
        try container.encodeIfPresent(hook, forKey: .hook)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(outro, forKey: .outro)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(dateModified, forKey: .dateModified)
    }
}

extension YTScript: Hashable {
    static func == (lhs: YTScript, rhs: YTScript) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ScriptStatus
enum ScriptStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case ready = "Ready"
    case filmed = "Filmed"
    
    var color: Color {
        switch self {
        case .draft: return .orange
        case .ready: return .green
        case .filmed: return .blue
        }
    }
}

// MARK: - Hook
class Hook: Identifiable, Codable, ObservableObject {
    var id: UUID
    @Published var variations: [String]
    @Published var selectedIndex: Int
    
    var wordCount: Int {
        guard !variations.isEmpty, selectedIndex < variations.count else { return 0 }
        return variations[selectedIndex].split(separator: " ").count
    }
    
    init(id: UUID = UUID(),
         variations: [String] = [],
         selectedIndex: Int = 0) {
        self.id = id
        self.variations = variations
        self.selectedIndex = selectedIndex
    }
    
    enum CodingKeys: String, CodingKey {
        case id, variations, selectedIndex
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        variations = try container.decode([String].self, forKey: .variations)
        selectedIndex = try container.decode(Int.self, forKey: .selectedIndex)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(variations, forKey: .variations)
        try container.encode(selectedIndex, forKey: .selectedIndex)
    }
}

// MARK: - Point
class Point: Identifiable, Codable, ObservableObject {
    var id: UUID
    @Published var orderIndex: Int
    @Published var title: String
    @Published var rawNotes: String
    @Published var sentences: [Sentence]
    
    var wordCount: Int {
        sentences.reduce(0) { $0 + $1.wordCount }
    }
    
    var estimatedDuration: String {
        let wpm = UserDefaults.standard.integer(forKey: "scriptWPM")
        let wpmValue = wpm > 0 ? Double(wpm) : 175.0
        let minutes = Double(wordCount) / wpmValue
        let mins = Int(minutes)
        let secs = Int((minutes - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }
    
    init(id: UUID = UUID(),
         orderIndex: Int,
         title: String = "",
         rawNotes: String = "",
         sentences: [Sentence] = []) {
        self.id = id
        self.orderIndex = orderIndex
        self.title = title
        self.rawNotes = rawNotes
        self.sentences = sentences
    }
    
    enum CodingKeys: String, CodingKey {
        case id, orderIndex, title, rawNotes, sentences
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        title = try container.decode(String.self, forKey: .title)
        rawNotes = try container.decode(String.self, forKey: .rawNotes)
        sentences = try container.decode([Sentence].self, forKey: .sentences)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(title, forKey: .title)
        try container.encode(rawNotes, forKey: .rawNotes)
        try container.encode(sentences, forKey: .sentences)
    }
}

extension Point: Hashable {
    static func == (lhs: Point, rhs: Point) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Sentence
class Sentence: Identifiable, Codable, ObservableObject {
    var id: UUID
    @Published var orderIndex: Int
    @Published var text: String
    @Published var flags: [SentenceFlag]
    
    var wordCount: Int {
        text.split(separator: " ").count
    }
    
    init(id: UUID = UUID(),
         orderIndex: Int,
         text: String,
         flags: [SentenceFlag] = []) {
        self.id = id
        self.orderIndex = orderIndex
        self.text = text
        self.flags = flags
    }
    
    enum CodingKeys: String, CodingKey {
        case id, orderIndex, text, flags
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        text = try container.decode(String.self, forKey: .text)
        flags = try container.decode([SentenceFlag].self, forKey: .flags)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(text, forKey: .text)
        try container.encode(flags, forKey: .flags)
    }
}

// MARK: - SentenceFlag
enum SentenceFlag: String, Codable, CaseIterable {
    case duplicate = "Duplicate"
    case conceptualRepetition = "Repetition"
    case lie = "Factual Error"
    case hookWrongPlace = "Hook Placement"
    case tooLong = "Too Long"
    case segwayDuplication = "Segway Duplicate"
    
    var icon: String {
        switch self {
        case .duplicate: return "arrow.triangle.2.circlepath"
        case .conceptualRepetition: return "repeat"
        case .lie: return "exclamationmark.triangle.fill"
        case .hookWrongPlace: return "hook.circle"
        case .tooLong: return "text.alignleft"
        case .segwayDuplication: return "arrow.right.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .lie: return .red
        case .duplicate, .conceptualRepetition, .segwayDuplication: return .orange
        case .hookWrongPlace, .tooLong: return .yellow
        }
    }
}

// MARK: - Outro
class Outro: Identifiable, Codable, ObservableObject {
    var id: UUID
    @Published var text: String
    
    var wordCount: Int {
        text.split(separator: " ").count
    }
    
    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
    
    enum CodingKeys: String, CodingKey {
        case id, text
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
    }
}



// ============================================================================
// MARK: - VIEWS
// ============================================================================


// MARK: - Script Row View
struct ScriptRowView: View {
    @ObservedObject var script: YTScript
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(script.status.color)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(script.title)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Text("\(script.totalWordCount) words")
                    Text("•")
                    Text(script.estimatedDuration)
                    Text("•")
                    Text(script.dateModified, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Script View
struct NewScriptView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var store = ScriptStore.instance
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var numPoints = 5
    @State private var voiceStyle = "Default"
    @State private var pastedData = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Video Details") {
                    TextField("Title", text: $title)
                    
                    Picker("Number of Points", selection: $numPoints) {
                        ForEach(3...7, id: \.self) { num in
                            Text("\(num) Points").tag(num)
                        }
                    }
                    
                    Picker("Voice Style", selection: $voiceStyle) {
                        Text("Default").tag("Default")
                        Text("Mark Rober").tag("Mark Rober")
                    }
                }
                
                Section("Research/Notes (Optional)") {
                    TextEditor(text: $pastedData)
                        .frame(height: 120)
                }
            }
            .navigationTitle("New Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createScript()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    func createScript() {
        let script = YTScript(
            title: title,
            numPoints: numPoints,
            voiceStyleName: voiceStyle
        )
        
        for i in 0..<numPoints {
            let point = Point(orderIndex: i, title: "Point \(i + 1)")
            script.points.append(point)
        }
        
        store.createScript(script)
        dismiss()
        
        // Navigate to the new script
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            nav.push(.scriptEditor(script))
        }
    }
}

//// MARK: - Script Editor View (Outline + Points)
//struct ScriptEditorView: View {
//    @EnvironmentObject var nav: NavigationViewModel
//    @StateObject private var store = ScriptStore.instance
//    @ObservedObject var script: YTScript
//    
//    var body: some View {
//        List {
//            // Hook Section
//            Section {
//                if let hook = script.hook {
//                    ForEach(hook.variations.indices, id: \.self) { index in
//                        HStack {
//                            Text(hook.variations[index])
//                                .font(.body)
//                            Spacer()
//                            if index == hook.selectedIndex {
//                                Image(systemName: "checkmark.circle.fill")
//                                    .foregroundStyle(.green)
//                            }
//                        }
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            hook.selectedIndex = index
//                            store.updateScript(script)
//                        }
//                    }
//                } else {
//                    Button {
//                        // Generate hook
//                        generateMockHook()
//                    } label: {
//                        Label("Generate Hook", systemImage: "sparkles")
//                    }
//                }
//            } header: {
//                Text("Hook")
//            }
//            
//            // Points Section
//            Section {
//                ForEach(script.points) { point in
//                    Button {
//                        nav.push(.pointEditor(script, point))
//                    } label: {
//                        HStack {
//                            Text("\(point.orderIndex + 1).")
//                                .font(.headline)
//                                .foregroundStyle(.secondary)
//                                .frame(width: 30, alignment: .leading)
//                            
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(point.title)
//                                    .font(.headline)
//                                
//                                if point.wordCount > 0 {
//                                    Text("\(point.wordCount) words • \(point.estimatedDuration)")
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }
//                            }
//                            
//                            Spacer()
//                            
//                            Image(systemName: "chevron.right")
//                                .font(.caption)
//                                .foregroundStyle(.tertiary)
//                        }
//                    }
//                    .buttonStyle(.plain)
//                }
//                .onMove { from, to in
//                    script.points.move(fromOffsets: from, toOffset: to)
//                    for (index, point) in script.points.enumerated() {
//                        point.orderIndex = index
//                    }
//                    store.updateScript(script)
//                }
//            } header: {
//                Text("Points")
//            }
//            
//            // Outro Section
//            Section {
//                if let outro = script.outro {
//                    Text(outro.text)
//                } else {
//                    Button {
//                        generateMockOutro()
//                    } label: {
//                        Label("Generate Outro", systemImage: "sparkles")
//                    }
//                }
//            } header: {
//                Text("Outro")
//            }
//            
//            // Stats Section
//            Section {
//                HStack {
//                    Text("Total Word Count")
//                    Spacer()
//                    Text("\(script.totalWordCount)")
//                        .foregroundStyle(.secondary)
//                }
//                
//                HStack {
//                    Text("Estimated Duration")
//                    Spacer()
//                    Text(script.estimatedDuration)
//                        .foregroundStyle(.secondary)
//                }
//                
//                Picker("Status", selection: $script.status) {
//                    ForEach(ScriptStatus.allCases, id: \.self) { status in
//                        Text(status.rawValue).tag(status)
//                    }
//                }
//                .onChange(of: script.status) { _, _ in
//                    store.updateScript(script)
//                }
//            } header: {
//                Text("Script Stats")
//            }
//            
//            // Actions
//            Section {
//                Button {
//                    nav.push(.fullScriptView(script))
//                } label: {
//                    Label("View Full Script", systemImage: "doc.text")
//                }
//                
//                Button {
//                    copyFullScript()
//                } label: {
//                    Label("Copy Full Script", systemImage: "doc.on.clipboard")
//                }
//            }
//        }
//        .navigationTitle(script.title)
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                EditButton()
//            }
//        }
//    }
//    
//    func generateMockHook() {
//        script.hook = Hook(
//            variations: [
//                "Hook variation 1 for \(script.title)",
//                "Hook variation 2 for \(script.title)",
//                "Hook variation 3 for \(script.title)"
//            ],
//            selectedIndex: 0
//        )
//        store.updateScript(script)
//    }
//    
//    func generateMockOutro() {
//        script.outro = Outro(text: "Thanks for watching! Don't forget to subscribe for more content.")
//        store.updateScript(script)
//    }
//    
//    func copyFullScript() {
//        var fullText = ""
//        
//        if let hook = script.hook {
//            fullText += "HOOK:\n"
//            fullText += hook.variations[hook.selectedIndex]
//            fullText += "\n\n"
//        }
//        
//        for point in script.points {
//            fullText += "\(point.title.uppercased()):\n"
//            for sentence in point.sentences {
//                fullText += sentence.text + " "
//            }
//            fullText += "\n\n"
//        }
//        
//        if let outro = script.outro {
//            fullText += "OUTRO:\n"
//            fullText += outro.text
//        }
//        
//        UIPasteboard.general.string = fullText
//    }
//}


// MARK: - Sentence Row View
struct SentenceRowView: View {
    @ObservedObject var sentence: Sentence
    let onTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("S\(sentence.orderIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            
            Text(sentence.text)
                .font(.body)
            
            Spacer()
            
            if !sentence.flags.isEmpty {
                VStack(spacing: 4) {
                    ForEach(sentence.flags, id: \.self) { flag in
                        Image(systemName: flag.icon)
                            .foregroundStyle(flag.color)
                            .font(.caption)
                    }
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
//
//// MARK: - Sentence Editor Sheet
//struct SentenceEditorSheet: View {
//    @ObservedObject var sentence: Sentence
//    let onSave: () -> Void
//    @Environment(\.dismiss) private var dismiss
//    
//    @State private var editedText: String
//    
//    init(sentence: Sentence, onSave: @escaping () -> Void) {
//        self.sentence = sentence
//        self.onSave = onSave
//        _editedText = State(initialValue: sentence.text)
//    }
//    
//    var body: some View {
//        NavigationStack {
//            Form {
//                Section("Sentence Text") {
//                    TextEditor(text: $editedText)
//                        .frame(minHeight: 100)
//                }
//                
//                Section("Flags") {
//                    ForEach(SentenceFlag.allCases, id: \.self) { flag in
//                        Toggle(flag.rawValue, isOn: Binding(
//                            get: { sentence.flags.contains(flag) },
//                            set: { isOn in
//                                if isOn {
//                                    if !sentence.flags.contains(flag) {
//                                        sentence.flags.append(flag)
//                                    }
//                                } else {
//                                    sentence.flags.removeAll { $0 == flag }
//                                }
//                            }
//                        ))
//                    }
//                }
//                
//                Section {
//                    Button("Regenerate This Sentence") {
//                        // Mock regeneration
//                        editedText = "This is a regenerated sentence."
//                    }
//                    
//                    Button("Copy Fix Prompt") {
//                        let prompt = """
//                        Current sentence: \(sentence.text)
//                        
//                        Task: Rewrite ONLY this sentence to fix any issues while maintaining flow.
//                        """
//                        UIPasteboard.general.string = prompt
//                    }
//                    
//                    Button(role: .destructive) {
//                        sentence.text = ""
//                        sentence.flags.removeAll()
//                        onSave()
//                        dismiss()
//                    } label: {
//                        Text("Delete Sentence")
//                    }
//                }
//            }
//            .navigationTitle("Edit Sentence")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") { dismiss() }
//                }
//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Save") {
//                        sentence.text = editedText
//                        onSave()
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}

// MARK: - Full Script View
struct FullScriptView: View {
    @ObservedObject var script: YTScript
    
    var fullScriptText: String {
        var text = ""
        
        if let hook = script.hook {
            text += "HOOK:\n"
            text += hook.variations[hook.selectedIndex]
            text += "\n\n"
        }
        
        for point in script.points {
            text += "\(point.title.uppercased()):\n"
            for sentence in point.sentences {
                text += sentence.text + " "
            }
            text += "\n\n"
        }
        
        if let outro = script.outro {
            text += "OUTRO:\n"
            text += outro.text
        }
        
        return text
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Stats
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(script.totalWordCount)")
                            .font(.title2)
                            .bold()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Est. Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(script.estimatedDuration)
                            .font(.title2)
                            .bold()
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                // Full Script
                Text(fullScriptText)
                    .font(.body)
                    .textSelection(.enabled)
                
                // Copy Button
                Button {
                    UIPasteboard.general.string = fullScriptText
                } label: {
                    Label("Copy Full Script", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Full Script")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Script Settings View
struct ScriptSettingsView: View {
    @AppStorage("scriptWPM") private var wpm: Int = 175
    
    var body: some View {
        Form {
            Section {
                Stepper("Words Per Minute: \(wpm)", value: $wpm, in: 100...250, step: 5)
            } header: {
                Text("Speaking Speed")
            } footer: {
                Text("Used to calculate estimated video duration. Default is 175 WPM.")
            }
        }
        .navigationTitle("Script Settings")
    }
}
