//
//  FilterCategory.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/6/25.
//


import SwiftUI

// MARK: - Filter Categories and Options
enum FilterCategory: String, CaseIterable {
    case people = "people"
    case emotion = "emotion"
    case action = "action"
    case objects = "objects"
    case setting = "setting"
    case interaction = "interaction"
    case spiritual = "spiritual"
    case special = "special"
    
    var displayName: String {
        switch self {
        case .people: return "People"
        case .emotion: return "Emotion"
        case .action: return "Action"
        case .objects: return "Objects"
        case .setting: return "Setting"
        case .interaction: return "Interaction"
        case .spiritual: return "Spiritual"
        case .special: return "Special"
        }
    }
    
    var options: [String] {
        switch self {
        case .people: return ["people1", "people2", "people3", "people4", "people5"]
        case .emotion: return ["angry", "anxious", "happy", "neutral", "sad"]
        case .action: return ["celebrating", "communicating", "falling", "fighting", "interacting", "moving", "praying", "static", "swimming", "thinking", "walking", "working"]
        case .objects: return ["abstract", "animal", "clock", "clothing", "container", "document", "door", "food", "furniture", "medical", "mirror", "money", "nature", "religious", "sign", "symbol", "technology", "tool", "vehicle", "weapon"]
        case .setting: return ["abstract", "indoor", "outdoor", "religious", "workplace"]
        case .interaction: return ["conflicted", "cooperative", "family", "hierarchical", "solo"]
        case .spiritual: return ["no", "yes"]
        case .special: return ["celebration", "communication", "contemplation", "movement", "symbols"]
        }
    }
}

// MARK: - Extended ImagePrompt for filtering
// Replace your ImagePrompt extension with this:

// Replace your ImagePrompt extension with this:

extension ImagePrompt {
    var parsedTags: [String: Any] {
        // Strip markdown code block formatting
        var cleanJSON = promptTags
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse JSON: \(cleanJSON)")
            return [:]
        }
        return json
    }
    
    func hasTag(category: FilterCategory, value: String) -> Bool {
        let categoryKey = category.rawValue
        
        guard let tagValue = parsedTags[categoryKey] else {
            return false
        }
        
        // Handle string values (people, emotion, action, setting, interaction, spiritual)
        if let stringValue = tagValue as? String {
            return stringValue == value
        }
        
        // Handle array values (objects, special)
        if let arrayValue = tagValue as? [String] {
            return arrayValue.contains(value)
        }
        
        return false
    }
}

struct ImagePromptSelectorSheet: View {
    let onSelect: (ImagePrompt) -> Void

    var body: some View {
        ImagePromptSelectorView { selectedPrompt in
            onSelect(selectedPrompt)
        }
        .frame(minWidth: 1000, minHeight: 1000)
        .presentationDetents([.fraction(0.9), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Image Prompt Selector View
struct ImagePromptSelectorView: View {
    let onSelect: (ImagePrompt) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedPrompt: ImagePrompt?
    @State private var selectedFilters: [FilterCategory: String] = [:]
    @State private var displayMode: DisplayMode = .horizontal
    @State private var searchText = ""
    @State private var prompts: [ImagePrompt] = []
    //let prompts: [ImagePrompt]
    
    enum DisplayMode: String, CaseIterable {
        case grid = "Grid"
        case horizontal = "Scroll"
        
        var icon: String {
            switch self {
            case .grid: return "grid"
            case .horizontal: return "rectangle.stack"
            }
        }
    }
    
    // Computed property for filtered prompts
    private var filteredPrompts: [ImagePrompt] {
        var filtered = prompts.filter { !$0.isHidden }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { prompt in
                prompt.prompt.localizedCaseInsensitiveContains(searchText) ||
                prompt.detailedPrompt.localizedCaseInsensitiveContains(searchText) ||
                prompt.promptTags.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply category filters
        for (category, selectedValue) in selectedFilters {
            if !selectedValue.isEmpty {
                filtered = filtered.filter { prompt in
                    prompt.hasTag(category: category, value: selectedValue)
                }
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    searchBar
                    useImageButton
                }
                
                // Filter Section
                filterSection
                
                // Main Content
                VStack(spacing: 16) {
                    // Large Preview Image
                    selectedImageView
                    
                
                    
                    // Display Mode Toggle
                    displayModeToggle
                    
                    // Image Collection
                    imageCollection
                }
                .padding()
            }
            .navigationTitle("Select Image Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                    do {
                        prompts = try await ImagePromptManager.instance.forceRefreshPrompts()
                        
                        // ✅ Only run this after prompts have loaded
                        if selectedPrompt == nil && !filteredPrompts.isEmpty {
                            selectedPrompt = filteredPrompts.first
                        }
                    } catch {
                        print("❌ Failed to load prompts: \(error)")
                    }
                }
        }
        .onChange(of: filteredPrompts) { newPrompts in
            // Update selected prompt if current selection is filtered out
            if let current = selectedPrompt, !newPrompts.contains(where: { $0.id == current.id }) {
                selectedPrompt = newPrompts.first
            } else if selectedPrompt == nil && !newPrompts.isEmpty {
                selectedPrompt = newPrompts.first
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search prompts...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Filter Section
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilterCategory.allCases, id: \.self) { category in
                    FilterPicker(
                        category: category,
                        selectedValue: Binding(
                            get: { selectedFilters[category] ?? "" },
                            set: { newValue in
                                if newValue.isEmpty {
                                    selectedFilters.removeValue(forKey: category)
                                } else {
                                    selectedFilters[category] = newValue
                                }
                            }
                        )
                    )
                }
                
                // Clear all filters button
                if !selectedFilters.isEmpty {
                    Button(action: { selectedFilters.removeAll() }) {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Selected Image View
    private var selectedImageView: some View {
        Group {
            if let selectedPrompt = selectedPrompt {
                HStack(spacing: 12) {
                    CachedImageView(
                        name: selectedPrompt.id,
                        remotePath: selectedPrompt.url,
                        cornerRadius: 12,
                        maxWidth: .infinity,
                        maxHeight: 550
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedPrompt.prompt)
                            .font(.headline)
                            .lineLimit(2)
                        
                        if !selectedPrompt.detailedPrompt.isEmpty {
                            Text(selectedPrompt.detailedPrompt)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        
                        if !selectedPrompt.promptTags.isEmpty {
                            Text(selectedPrompt.allTagsString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 250)
                    .overlay(
                        VStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.largeTitle)
                            Text("Select an image from below")
                                .font(.headline)
                        }
                        .foregroundColor(.gray)
                    )
            }
        }
    }
    
    // MARK: - Use Image Button
    private var useImageButton: some View {
        Button(action: {
            if let selected = selectedPrompt {
               
                onSelect(selected)
                dismiss()
            }
        }) {
            Text("Use This Image")
                .font(.headline)
                .frame(maxWidth: 200)
                .padding()
                .background(selectedPrompt != nil ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(selectedPrompt == nil)
    }
    
    // MARK: - Display Mode Toggle
    private var displayModeToggle: some View {
        Picker("Display Mode", selection: $displayMode) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    // MARK: - Image Collection
    private var imageCollection: some View {
        Group {
            if displayMode == .horizontal {
                gridView
            } else {
                horizontalScrollView
            }
        }
    }
    
    // MARK: - Grid View
    private var gridView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filteredPrompts) { prompt in
                    thumbnailView(prompt)
                }
            }
        }
        .frame(maxHeight: 300)
    }
    
    // MARK: - Horizontal Scroll View
    private var horizontalScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(filteredPrompts) { prompt in
                    thumbnailView(prompt)
                        .frame(width: 100)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 120)
    }
    
    // MARK: - Thumbnail View
    private func thumbnailView(_ prompt: ImagePrompt) -> some View {
        CachedImageView(
            name: prompt.id,
            remotePath: prompt.url,
            cornerRadius: 8,
            maxWidth: displayMode == .grid ? nil : 100,
            maxHeight: 100
        )
        .frame(width: displayMode == .grid ? nil : 100, height: 100)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedPrompt?.id == prompt.id ? Color.blue : Color.clear, lineWidth: 3)
        )
        .onTapGesture {
            selectedPrompt = prompt
        }
//        AsyncImage(url: URL(string: prompt.url)) { phase in
//            switch phase {
//            case .success(let image):
//                image
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(width: displayMode == .grid ? nil : 100, height: displayMode == .grid ? 100 : 100)
//                    .clipped()
//                    .cornerRadius(8)
//            case .failure:
//                Color.gray
//                    .frame(width: displayMode == .grid ? nil : 100, height: 100)
//                    .cornerRadius(8)
//                    .overlay(
//                        Image(systemName: "photo")
//                            .foregroundColor(.white)
//                    )
//            case .empty:
//                Color.gray.opacity(0.3)
//                    .frame(width: displayMode == .grid ? nil : 100, height: 100)
//                    .cornerRadius(8)
//                    .overlay(ProgressView())
//            @unknown default:
//                EmptyView()
//            }
   
    }
}

// MARK: - Filter Picker
struct FilterPicker: View {
    let category: FilterCategory
    @Binding var selectedValue: String
    
    var body: some View {
        Menu {
            Button("None", role: .destructive) {
                selectedValue = ""
            }
            
            ForEach(category.options, id: \.self) { option in
                Button(option) {
                    selectedValue = option
                }
            }
        } label: {
            HStack {
                Text(category.displayName)
                    .font(.caption.weight(.medium))
                
                if !selectedValue.isEmpty {
                    Text(selectedValue)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedValue.isEmpty ? Color(.systemBackground) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedValue.isEmpty ? Color.gray.opacity(0.3) : Color.blue, lineWidth: 1)
            )
        }
    }
}
