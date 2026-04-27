//
//  CollapsibleSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//


import SwiftUI

// MARK: - Collapsible Section (View Only)
struct CollapsibleSection2<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let count: String?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    if let count = count {
                        Text("• \(count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Collapsible Editable Section
// MARK: - Collapsible Editable Section
struct CollapsibleEditableSection2<AdditionalButtons: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @Binding var text: String
    let placeholder: String
    let onSave: () async -> Void
    var backgroundColor: Color = Color.gray.opacity(0.1)
    let additionalButtons: () -> AdditionalButtons  // ← Changed to closure, no default
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    if !text.isEmpty {
                        Text("• Set")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Action Buttons
                    HStack {
                        if !text.isEmpty && !isEditing {
                            CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                        }
                        
                        if !isEditing {
                            Button(action: {
                                editingText = text
                                isEditing = true
                            }) {
                                Label(text.isEmpty ? "Add" : "Edit", systemImage: text.isEmpty ? "plus.circle" : "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        additionalButtons()  // ← Call the closure
                        
                        Spacer()
                    }
                    
                    // Content Area
                    if isEditing {
                        // Edit Mode
                        VStack(spacing: 8) {
                            TextEditor(text: $editingText)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                            
                            HStack {
                                Button("Cancel") {
                                    isEditing = false
                                    editingText = ""
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Save") {
                                    Task {
                                        isSaving = true
                                        text = editingText
                                        await onSave()
                                        isEditing = false
                                        isSaving = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSaving)
                            }
                        }
                    } else {
                        // View Mode
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            ScrollView {
                                Text(text)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .padding()
                            .background(backgroundColor)
                            .cornerRadius(8)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}



import SwiftUI

// MARK: - Collapsible Section (View Only)
struct CollapsibleSection<Content: View, TrailingContent: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let count: String?
    @ViewBuilder let content: () -> Content
    let trailingContent: (() -> TrailingContent)?

    init(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        count: String?,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.count = count
        self.content = content
        self.trailingContent = trailingContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(.blue)
                        Text(title)
                            .font(.headline)
                        if let count = count {
                            Text("• \(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                            .imageScale(.small)
                    }
                }
                .buttonStyle(.plain)

                if let trailingContent {
                    trailingContent()
                }
            }

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// Default initializer — no trailing content (existing call sites unchanged)
extension CollapsibleSection where TrailingContent == EmptyView {
    init(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        count: String?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.count = count
        self.content = content
        self.trailingContent = nil
    }
}

// MARK: - Collapsible Editable Section
struct CollapsibleEditableSection<AdditionalButtons: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @Binding var text: String
    let placeholder: String
    let onSave: () async -> Void
    var backgroundColor: Color = Color.gray.opacity(0.1)
    let additionalButtons: () -> AdditionalButtons
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    if !text.isEmpty {
                        Text("• Set")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Action Buttons
                    HStack {
                        if !text.isEmpty && !isEditing {
                            CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                        }
                        
                        if !isEditing {
                            // ✅ Paste Button
                            Button(action: { pasteFromClipboard() }) {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                editingText = text
                                isEditing = true
                            }) {
                                Label(text.isEmpty ? "Add" : "Edit", systemImage: text.isEmpty ? "plus.circle" : "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        additionalButtons()
                        
                        Spacer()
                    }
                    
                    // Content Area
                    if isEditing {
                        // Edit Mode
                        VStack(spacing: 8) {
                            TextEditor(text: $editingText)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                            
                            HStack {
                                Button("Cancel") {
                                    isEditing = false
                                    editingText = ""
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Save") {
                                    Task {
                                        isSaving = true
                                        text = editingText
                                        await onSave()
                                        isEditing = false
                                        isSaving = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSaving)
                            }
                        }
                    } else {
                        // View Mode
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            ScrollView {
                                Text(text)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .padding()
                            .background(backgroundColor)
                            .cornerRadius(8)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // ✅ Paste from clipboard
    private func pasteFromClipboard() {
        #if os(iOS)
        if let clipboardText = UIPasteboard.general.string {
            editingText = clipboardText
            isEditing = true
        }
        #elseif os(macOS)
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            editingText = clipboardText
            isEditing = true
        }
        #endif
    }
}

// MARK: - Rambling Question Model

struct RamblingQuestion: Identifiable {
    let id: UUID
    let text: String
    let priorityColor: Color
    var subtitle: String?       // e.g. whatsMissing
    var detail: String?         // e.g. whyItMatters
    var locationLabel: String?  // e.g. beat location
    var sourceLabel: String?    // e.g. "G1"
    var typeBadge: String?      // e.g. "Structural"
    var actionBadge: String?    // e.g. "RESHAPE"
}

// MARK: - Collapsible Rambling Section (Text Editor + Question Panel)

/// A collapsible section that combines a tappable question list with a live text editor.
/// Unlike `CollapsibleEditableSection`, there is NO view/edit split — the TextEditor
/// is always visible when expanded, bound directly to `text`. This avoids the stale-state
/// bug where question taps would overwrite in-progress edits.
struct CollapsibleRamblingSection: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @Binding var text: String
    let placeholder: String
    let onSave: () async -> Void

    // Question panel
    let questions: [RamblingQuestion]
    @Binding var usedQuestionIds: Set<UUID>
    let onInsertQuestion: (RamblingQuestion) -> Void

    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    if !text.isEmpty {
                        Text("• Set")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if !questions.isEmpty {
                        Text("• \(questions.count) questions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Action Buttons
                    HStack {
                        if !text.isEmpty {
                            CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                        }

                        Button(action: { pasteFromClipboard() }) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                isSaving = true
                                await onSave()
                                isSaving = false
                            }
                        } label: {
                            Label(isSaving ? "Saving..." : "Save", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !text.isEmpty {
                            let wc = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                            Text("\(wc) words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Question Panel
                    if !questions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(questions) { question in
                                        let isUsed = usedQuestionIds.contains(question.id)
                                        Button {
                                            onInsertQuestion(question)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                // Question text with priority dot
                                                HStack(alignment: .top, spacing: 8) {
                                                    Circle()
                                                        .fill(question.priorityColor)
                                                        .frame(width: 8, height: 8)
                                                        .padding(.top, 4)
                                                    Text(question.text)
                                                        .font(.callout)
                                                        .multilineTextAlignment(.leading)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }

                                                // What's missing
                                                if let subtitle = question.subtitle, !subtitle.isEmpty {
                                                    Text(subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.leading)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                        .padding(.leading, 16)
                                                }

                                                // Why it matters
                                                if let detail = question.detail, !detail.isEmpty {
                                                    Text(detail)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary.opacity(0.8))
                                                        .multilineTextAlignment(.leading)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                        .padding(.leading, 16)
                                                }

                                                // Badges row
                                                let badges = [question.sourceLabel, question.typeBadge, question.actionBadge, question.locationLabel].compactMap { $0 }
                                                if !badges.isEmpty {
                                                    HStack(spacing: 4) {
                                                        ForEach(badges, id: \.self) { badge in
                                                            Text(badge)
                                                                .font(.caption2.weight(.medium))
                                                                .padding(.horizontal, 5)
                                                                .padding(.vertical, 2)
                                                                .background(Color.secondary.opacity(0.12))
                                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                        }
                                                    }
                                                    .padding(.leading, 16)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(isUsed ? Color.gray.opacity(0.12) : Color.blue.opacity(0.08))
                                            .foregroundColor(isUsed ? .secondary : .primary)
                                            .cornerRadius(8)
                                        }
                                        .disabled(isUsed)
                                    }
                                }
                            }
                            .frame(maxHeight: 400)

                            HStack {
                                Text("\(usedQuestionIds.count)/\(questions.count) used")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }

                        Divider()
                    }

                    // Live TextEditor — always visible, bound directly to text
                    TextEditor(text: $text)
                        .frame(minHeight: 300)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            Group {
                                if text.isEmpty {
                                    Text(placeholder)
                                        .font(.body)
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .italic()
                                        .padding(.leading, 12)
                                        .padding(.top, 16)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let clipboardText = UIPasteboard.general.string {
            text = clipboardText
        }
        #elseif os(macOS)
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            text = clipboardText
        }
        #endif
    }
}

// MARK: - Simple Editable Text Field (Single Line or Short)
struct EditableTextFieldSection: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    let onSave: () async -> Void
    var multiline: Bool = false
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                if !text.isEmpty && !isEditing {
                    CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                }
                
                if !isEditing {
                    // ✅ Paste Button
                    Button(action: { pasteFromClipboard() }) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        editingText = text
                        isEditing = true
                    }) {
                        Label(text.isEmpty ? "Add" : "Edit", systemImage: text.isEmpty ? "plus.circle" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if isEditing {
                VStack(spacing: 8) {
                    if multiline {
                        TextEditor(text: $editingText)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                    } else {
                        TextField(placeholder, text: $editingText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            editingText = ""
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Save") {
                            Task {
                                isSaving = true
                                text = editingText
                                await onSave()
                                isEditing = false
                                isSaving = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            } else if !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // ✅ Paste from clipboard
    private func pasteFromClipboard() {
        #if os(iOS)
        if let clipboardText = UIPasteboard.general.string {
            editingText = clipboardText
            isEditing = true
        }
        #elseif os(macOS)
        if let clipboardText = NSPasteboard.general.string(forType: .string) {
            editingText = clipboardText
            isEditing = true
        }
        #endif
    }
}
struct CollapsibleEditableSection1<AdditionalButtons: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @Binding var text: String
    let placeholder: String
    let onSave: () async -> Void
    var backgroundColor: Color = Color.gray.opacity(0.1)
    var additionalButtons: AdditionalButtons = EmptyView() as! AdditionalButtons
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isSaving = false
    
    init(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        text: Binding<String>,
        placeholder: String,
        onSave: @escaping () async -> Void,
        backgroundColor: Color = Color.gray.opacity(0.1),
        @ViewBuilder additionalButtons: () -> AdditionalButtons = { EmptyView() as! AdditionalButtons }
    ) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self._text = text
        self.placeholder = placeholder
        self.onSave = onSave
        self.backgroundColor = backgroundColor
        self.additionalButtons = additionalButtons()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    if !text.isEmpty {
                        Text("• Set")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .imageScale(.small)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Action Buttons
                    HStack {
                        if !text.isEmpty && !isEditing {
                            CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                        }
                        
                        if !isEditing {
                            Button(action: {
                                editingText = text
                                isEditing = true
                            }) {
                                Label(text.isEmpty ? "Add" : "Edit", systemImage: text.isEmpty ? "plus.circle" : "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        additionalButtons
                        
                        Spacer()
                    }
                    
                    // Content Area
                    if isEditing {
                        // Edit Mode
                        VStack(spacing: 8) {
                            TextEditor(text: $editingText)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                            
                            HStack {
                                Button("Cancel") {
                                    isEditing = false
                                    editingText = ""
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Save") {
                                    Task {
                                        isSaving = true
                                        text = editingText
                                        await onSave()
                                        isEditing = false
                                        isSaving = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSaving)
                            }
                        }
                    } else {
                        // View Mode
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            ScrollView {
                                Text(text)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .padding()
                            .background(backgroundColor)
                            .cornerRadius(8)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Simple Editable Text Field (Single Line or Short)
struct EditableTextFieldSection2: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    let onSave: () async -> Void
    var multiline: Bool = false
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                if !text.isEmpty && !isEditing {
                    CopyButton(label: "Copy", valueToCopy: text, font: .caption)
                }
                
                if !isEditing {
                    Button(action: {
                        editingText = text
                        isEditing = true
                    }) {
                        Label(text.isEmpty ? "Add" : "Edit", systemImage: text.isEmpty ? "plus.circle" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if isEditing {
                VStack(spacing: 8) {
                    if multiline {
                        TextEditor(text: $editingText)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                    } else {
                        TextField(placeholder, text: $editingText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            editingText = ""
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Save") {
                            Task {
                                isSaving = true
                                text = editingText
                                await onSave()
                                isEditing = false
                                isSaving = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            } else if !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
            } else {
                Text(placeholder)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Copy Button Helper
struct CopyButtonOld: View {
    let label: String
    let valueToCopy: String
    let font: Font
    @State private var showCheckmark = false
    
    var body: some View {
        Button(action: copyToClipboard) {
            HStack(spacing: 4) {
                if showCheckmark {
                    Image(systemName: "checkmark")
                } else {
                    Image(systemName: "doc.on.doc")
                }
                Text(label)
            }
            .font(font)
        }
        .buttonStyle(.bordered)
    }
    
    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = valueToCopy
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(valueToCopy, forType: .string)
        #endif
        
        withAnimation {
            showCheckmark = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCheckmark = false
            }
        }
    }
}

// MARK: - Stat Badge (Existing Helper)
struct StatBadge: View {
    let icon: String
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
