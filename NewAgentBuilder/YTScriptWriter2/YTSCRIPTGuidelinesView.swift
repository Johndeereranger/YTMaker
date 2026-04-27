//
//  YTSCRIPTGuidelinesView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

//
//import SwiftUI
//
//struct YTSCRIPTGuidelinesView: View {
//    @Bindable var script: YTSCRIPT
//    @State private var selectedCategory: GuidelineCategory = .structure
//    @State private var searchText = ""
//    
//    var filteredGuidelines: [ScriptGuideline] {
//        ScriptGuidelinesDatabase.guidelines
//            .filter { $0.category == selectedCategory }
//            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.summary.localizedCaseInsensitiveContains(searchText) }
//    }
//    
//    var body: some View {
//        HStack(spacing: 0) {
//            // Sidebar
//            categoryPickerView
//                .frame(width: 220)
//            
//            Divider()
//            
//            // Main content
//            ScrollView {
//                VStack(alignment: .leading, spacing: 16) {
//                    headerSection
//                    
//                    ForEach(filteredGuidelines) { guideline in
//                        GuidelineCard(
//                            guideline: guideline,
//                            script: script
//                        )
//                    }
//                }
//                .padding()
//            }
//        }
//        .navigationTitle("Writing Guidelines")
//    }
//    
//    private var headerSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            HStack {
//                Text(selectedCategory.rawValue)
//                    .font(.title2)
//                    .bold()
//                
//                Spacer()
//                
//                Text("\(filteredGuidelines.count) guidelines")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }
//            
//            TextField("Search guidelines...", text: $searchText)
//                .textFieldStyle(.roundedBorder)
//        }
//    }
//    
//    private var categoryPickerView: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Categories")
//                    .font(.headline)
//                    .padding(.horizontal)
//                    .padding(.top)
//                
//                ForEach(GuidelineCategory.allCases, id: \.self) { category in
//                    Button {
//                        selectedCategory = category
//                        searchText = ""
//                    } label: {
//                        HStack {
//                            Text(category.rawValue)
//                                .font(.subheadline)
//                                .foregroundColor(selectedCategory == category ? .white : .primary)
//                            Spacer()
//                            Text("\(count(for: category))")
//                                .font(.caption)
//                                .foregroundColor(selectedCategory == category ? .white.opacity(0.8) : .secondary)
//                        }
//                        .padding(.horizontal, 12)
//                        .padding(.vertical, 8)
//                        .background(selectedCategory == category ? Color.accentColor : Color.clear)
//                        .cornerRadius(8)
//                    }
//                    .buttonStyle(.plain)
//                    .padding(.horizontal, 8)
//                }
//            }
//            .padding(.bottom)
//        }
//        .background(Color(.secondarySystemBackground))
//    }
//    
//    private func count(for category: GuidelineCategory) -> Int {
//        ScriptGuidelinesDatabase.guidelines.filter { $0.category == category }.count
//    }
//}
//
//struct GuidelineCard: View {
//    let guideline: ScriptGuideline
//    let script: YTSCRIPT
//    
//    @State private var isExpanded = false
//    @State private var copiedButton: String? = nil
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            // Header - always visible
//            Button {
//                withAnimation {
//                    isExpanded.toggle()
//                }
//            } label: {
//                HStack(alignment: .top) {
//                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
//                        .font(.title3)
//                        .foregroundColor(.accentColor)
//                    
//                    VStack(alignment: .leading, spacing: 4) {
//                        Text(guideline.title)
//                            .font(.headline)
//                            .foregroundColor(.primary)
//                        
//                        Text(guideline.summary)
//                            .font(.subheadline)
//                            .foregroundStyle(.secondary)
//                            .multilineTextAlignment(.leading)
//                    }
//                    
//                    Spacer()
//                }
//            }
//            .buttonStyle(.plain)
//            
//            if isExpanded {
//                Divider()
//                
//                // Explanation
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Full Explanation")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                    
//                    Text(guideline.explanation)
//                        .font(.body)
//                        .padding()
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .background(Color(.tertiarySystemBackground))
//                        .cornerRadius(8)
//                }
//                
//                Divider()
//                
//                // Action buttons
//                Text("Quick Actions")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//                
//                VStack(spacing: 8) {
//                    promptButton(
//                        label: "Check Script",
//                        icon: "checkmark.circle",
//                        prompt: guideline.checkPrompt,
//                        buttonId: "check",
//                        color: .blue
//                    )
//                    
//                    promptButton(
//                        label: "Fix Script",
//                        icon: "wrench.and.screwdriver",
//                        prompt: guideline.fixPrompt,
//                        buttonId: "fix",
//                        color: .orange
//                    )
//                    
//                    promptButton(
//                        label: "Get Suggestions",
//                        icon: "lightbulb",
//                        prompt: guideline.suggestionsPrompt,
//                        buttonId: "suggest",
//                        color: .purple
//                    )
//                }
//            }
//        }
//        .padding()
//        .background(Color(.secondarySystemBackground))
//        .cornerRadius(12)
//    }
//    
//    private func promptButton(label: String, icon: String, prompt: String, buttonId: String, color: Color) -> some View {
//        Button {
//            copyPrompt(prompt, id: buttonId)
//        } label: {
//            HStack {
//                Image(systemName: icon)
//                    .foregroundColor(color)
//                
//                Text(copiedButton == buttonId ? "Copied!" : label)
//                    .foregroundColor(.primary)
//                
//                Spacer()
//                
//                if copiedButton == buttonId {
//                    Image(systemName: "checkmark")
//                        .foregroundColor(.green)
//                } else {
//                    Image(systemName: "doc.on.doc")
//                        .foregroundStyle(.secondary)
//                }
//            }
//            .padding()
//            .background(copiedButton == buttonId ? Color.green.opacity(0.15) : Color(.tertiarySystemBackground))
//            .cornerRadius(8)
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(copiedButton == buttonId ? Color.green : Color.clear, lineWidth: 1)
//            )
//        }
//        .buttonStyle(.plain)
//    }
//    
//    private func copyPrompt(_ template: String, id: String) {
//        // Get full script text
//        let fullScript = getFullScriptText()
//        
//        // Replace {{SCRIPT}} placeholder
//        let prompt = template.replacingOccurrences(of: "{{SCRIPT}}", with: fullScript)
//        
//        // Copy to clipboard
//        #if os(iOS)
//        UIPasteboard.general.string = prompt
//        #else
//        NSPasteboard.general.clearContents()
//        NSPasteboard.general.setString(prompt, forType: .string)
//        #endif
//        
//        // Show feedback
//        withAnimation {
//            copiedButton = id
//        }
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//            withAnimation {
//                copiedButton = nil
//            }
//        }
//    }
//    
//    private func getFullScriptText() -> String {
//        var text = ""
//        let activeSections = script.outlineSections
//            .filter { !$0.isArchived }
//            .sorted(by: { $0.orderIndex < $1.orderIndex })
//        
//        var globalIndex = 1
//        for section in activeSections {
//            text += "\(section.name)\n\n"
//            if section.currentVersionIndex >= 0,
//               section.currentVersionIndex < section.sectionVersions.count {
//                let currentVersion = section.sectionVersions[section.currentVersionIndex]
//                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
//                    text += "S\(globalIndex): \(sentence.text)\n"
//                    globalIndex += 1
//                }
//            }
//            text += "\n"
//        }
//        return text
//    }
//}


import SwiftUI

struct YTSCRIPTGuidelinesView: View {
    @Bindable var script: YTSCRIPT
    @State private var selectedCategory: GuidelineCategory = .all
    @State private var searchText = ""
    
    var filteredGuidelines: [ScriptGuideline] {
        let guidelines = ScriptGuidelinesDatabase.guidelines
        
        // Filter by category
        let categoryFiltered = selectedCategory == .all
            ? guidelines
            : guidelines.filter { $0.category == selectedCategory }
        
        // Filter by search
        return categoryFiltered.filter {
            searchText.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and category picker
            headerSection
                .padding()
                .background(Color(.secondarySystemBackground))
            
            Divider()
            
            // Guidelines list
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredGuidelines) { guideline in
                        GuidelineCard(
                            guideline: guideline,
                            script: script
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Writing Guidelines")
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Search
            TextField("Search guidelines...", text: $searchText)
                .textFieldStyle(.roundedBorder)
            
            // Category picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GuidelineCategory.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                            searchText = ""
                        } label: {
                            HStack(spacing: 4) {
                                Text(category.rawValue)
                                    .font(.subheadline)
                                
                                if category != .all {
                                    Text("\(count(for: category))")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(selectedCategory == category ? Color.white.opacity(0.3) : Color.primary.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? Color.accentColor : Color(.tertiarySystemBackground))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func count(for category: GuidelineCategory) -> Int {
        guard category != .all else { return ScriptGuidelinesDatabase.guidelines.count }
        return ScriptGuidelinesDatabase.guidelines.filter { $0.category == category }.count
    }
}
//
//struct GuidelineCard: View {
//    let guideline: ScriptGuideline
//    let script: YTSCRIPT
//    
//    @State private var isExpanded = false
//    @State private var copiedButton: String? = nil
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            // Title and category badge
//            HStack(alignment: .top) {
//                VStack(alignment: .leading, spacing: 4) {
//                    Text(guideline.title)
//                        .font(.headline)
//                    
//                    Text(guideline.summary)
//                        .font(.subheadline)
//                        .foregroundStyle(.secondary)
//                }
//                
//                Spacer()
//                
//                Text(guideline.category.rawValue)
//                    .font(.caption2)
//                    .padding(.horizontal, 8)
//                    .padding(.vertical, 4)
//                    .background(Color.accentColor.opacity(0.2))
//                    .foregroundColor(.accentColor)
//                    .cornerRadius(6)
//            }
//            
//            // Quick action buttons - ALWAYS VISIBLE
//            VStack(spacing: 8) {
//                promptButton(
//                    label: "Check Script",
//                    icon: "checkmark.circle",
//                    prompt: guideline.checkPrompt,
//                    buttonId: "check",
//                    color: .blue
//                )
//                
//                promptButton(
//                    label: "Fix Script",
//                    icon: "wrench.and.screwdriver",
//                    prompt: guideline.fixPrompt,
//                    buttonId: "fix",
//                    color: .orange
//                )
//                
//                promptButton(
//                    label: "Get Suggestions",
//                    icon: "lightbulb",
//                    prompt: guideline.suggestionsPrompt,
//                    buttonId: "suggest",
//                    color: .purple
//                )
//            }
//            
//            // Expand for full explanation - OPTIONAL
//            Button {
//                withAnimation {
//                    isExpanded.toggle()
//                }
//            } label: {
//                HStack {
//                    Text(isExpanded ? "Hide Full Explanation" : "Show Full Explanation")
//                        .font(.caption)
//                        .foregroundColor(.accentColor)
//                    
//                    Spacer()
//                    
//                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
//                        .font(.caption)
//                        .foregroundColor(.accentColor)
//                }
//            }
//            .buttonStyle(.plain)
//            
//            if isExpanded {
//                Text(guideline.explanation)
//                    .font(.body)
//                    .padding()
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .background(Color(.tertiarySystemBackground))
//                    .cornerRadius(8)
//            }
//        }
//        .padding()
//        .background(Color(.secondarySystemBackground))
//        .cornerRadius(12)
//    }
//    
//    private func promptButton(label: String, icon: String, prompt: String, buttonId: String, color: Color) -> some View {
//        Button {
//            copyPrompt(prompt, id: buttonId)
//        } label: {
//            HStack {
//                Image(systemName: icon)
//                    .foregroundColor(color)
//                    .frame(width: 20)
//                
//                Text(copiedButton == buttonId ? "Copied!" : label)
//                    .font(.subheadline)
//                    .foregroundColor(.primary)
//                
//                Spacer()
//                
//                if copiedButton == buttonId {
//                    Image(systemName: "checkmark")
//                        .foregroundColor(.green)
//                } else {
//                    Image(systemName: "doc.on.doc")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                }
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 10)
//            .background(copiedButton == buttonId ? Color.green.opacity(0.15) : Color(.tertiarySystemBackground))
//            .cornerRadius(8)
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(copiedButton == buttonId ? Color.green : Color.clear, lineWidth: 1)
//            )
//        }
//        .buttonStyle(.plain)
//    }
//    
//    private func copyPrompt(_ template: String, id: String) {
//        // Get full script text with line numbers
//        let fullScript = getFullScriptText()
//        
//        // Replace {{SCRIPT}} placeholder
//        let prompt = template.replacingOccurrences(of: "{{SCRIPT}}", with: fullScript)
//        
//        // Copy to clipboard
//        #if os(iOS)
//        UIPasteboard.general.string = prompt
//        #else
//        NSPasteboard.general.clearContents()
//        NSPasteboard.general.setString(prompt, forType: .string)
//        #endif
//        
//        // Show feedback
//        withAnimation {
//            copiedButton = id
//        }
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//            withAnimation {
//                copiedButton = nil
//            }
//        }
//    }
//    
//    private func getFullScriptText() -> String {
//        var text = ""
//        let activeSections = script.outlineSections
//            .filter { !$0.isArchived }
//            .sorted(by: { $0.orderIndex < $1.orderIndex })
//        
//        var globalIndex = 1
//        for section in activeSections {
//            text += "\(section.name)\n\n"
//            if section.currentVersionIndex >= 0,
//               section.currentVersionIndex < section.sectionVersions.count {
//                let currentVersion = section.sectionVersions[section.currentVersionIndex]
//                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
//                    text += "S\(globalIndex): \(sentence.text)\n"
//                    globalIndex += 1
//                }
//            }
//            text += "\n"
//        }
//        return text
//    }
//}


struct GuidelineCard: View {
    let guideline: ScriptGuideline
    let script: YTSCRIPT
    
    @State private var isExpanded = false
    @State private var copiedButton: String? = nil
    @Environment(\.horizontalSizeClass) var sizeClass
    
    var isCompact: Bool {
        sizeClass == .compact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCompact {
                // iPhone: Stack vertically
                verticalLayout
            } else {
                // iPad: Horizontal layout
                horizontalLayout
            }
            
            // Expand for full explanation - OPTIONAL
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Hide Explanation" : "Show Explanation")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(guideline.explanation)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // iPad layout - buttons on right side
    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left side: Title and summary
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(guideline.title)
                        .font(.headline)
                    
                    Text(guideline.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
                
                Text(guideline.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Right side: Compact buttons
            HStack(spacing: 8) {
                compactButton(
                    icon: "checkmark.circle",
                    prompt: guideline.checkPrompt,
                    buttonId: "check",
                    color: .blue
                )
                
                compactButton(
                    icon: "wrench.and.screwdriver",
                    prompt: guideline.fixPrompt,
                    buttonId: "fix",
                    color: .orange
                )
                
                compactButton(
                    icon: "lightbulb",
                    prompt: guideline.suggestionsPrompt,
                    buttonId: "suggest",
                    color: .purple
                )
            }
        }
    }
    
    // iPhone layout - buttons below title
    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and category
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(guideline.title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(guideline.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
                
                Text(guideline.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Buttons in horizontal row
            HStack(spacing: 8) {
                compactButton(
                    icon: "checkmark.circle",
                    prompt: guideline.checkPrompt,
                    buttonId: "check",
                    color: .blue
                )
                
                compactButton(
                    icon: "wrench.and.screwdriver",
                    prompt: guideline.fixPrompt,
                    buttonId: "fix",
                    color: .orange
                )
                
                compactButton(
                    icon: "lightbulb",
                    prompt: guideline.suggestionsPrompt,
                    buttonId: "suggest",
                    color: .purple
                )
            }
        }
    }
    
    // Compact icon-only button
    private func compactButton(icon: String, prompt: String, buttonId: String, color: Color) -> some View {
        Button {
            copyPrompt(prompt, id: buttonId)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: copiedButton == buttonId ? "checkmark" : icon)
                    .font(.title3)
                    .foregroundColor(copiedButton == buttonId ? .green : color)
                    .frame(height: 24)
                
                Text(buttonId == "check" ? "Check" : buttonId == "fix" ? "Fix" : "Suggest")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(copiedButton == buttonId ? Color.green.opacity(0.15) : Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(copiedButton == buttonId ? Color.green : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func copyPrompt(_ template: String, id: String) {
        let fullScript = getFullScriptText()
        let prompt = template.replacingOccurrences(of: "{{SCRIPT}}", with: fullScript)
        
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        
        withAnimation {
            copiedButton = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedButton = nil
            }
        }
    }
    
    private func getFullScriptText() -> String {
        var text = ""
        let activeSections = script.outlineSections
            .filter { !$0.isArchived }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
        
        var globalIndex = 1
        for section in activeSections {
            text += "\(section.name)\n\n"
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    text += "S\(globalIndex): \(sentence.text)\n"
                    globalIndex += 1
                }
            }
            text += "\n"
        }
        return text
    }
}
