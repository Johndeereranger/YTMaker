//
//  AlignmentViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//


import SwiftUI

// MARK: - Alignment Viewer
struct AlignmentViewer: View {
    let video: YouTubeVideo
    @State private var alignment: AlignmentData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading analysis...")
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let alignment = alignment {
                alignmentContent(alignment)
            } else {
                ContentUnavailableView(
                    "No Analysis Yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Run structure analysis first")
                )
            }
        }
        .navigationTitle("Structure Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAlignment()
        }
    }
    
    @ViewBuilder
    private func alignmentContent(_ alignment: AlignmentData) -> some View {
        List {
            // Validation Status
            Section("Analysis Status") {
                HStack {
                    Image(systemName: statusIcon(alignment.validationStatus))
                        .foregroundColor(statusColor(alignment.validationStatus))
                    Text(alignment.validationStatus.rawValue.capitalized)
                    Spacer()
                    Text(alignment.extractionDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let issues = alignment.validationIssues, !issues.isEmpty {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(issue.severity == .error ? .red : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.type.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(issue.message)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            
            // Sections
            Section("Sections (\(alignment.sections.count))") {
                ForEach(alignment.sections) { section in
                    NavigationLink(destination: SectionDetailView(section: section, video: video)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                RoleBadge(role: section.role)
                                Spacer()
                                Text(formatSectionRange(section))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(section.goal)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // Logic Spine
            Section("Logic Spine") {
                ForEach(Array(alignment.logicSpine.chain.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue))
                        
                        Text(step)
                            .font(.subheadline)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    if index < alignment.logicSpine.chain.count - 1 {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 24)
                            
                            if let link = alignment.logicSpine.causalLinks.first(where: { 
                                $0.from == alignment.sections[index].id 
                            }) {
                                Text(link.connection)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            
            // Bridge Points
            if !alignment.bridgePoints.isEmpty {
                Section("Bridge Points (\(alignment.bridgePoints.count))") {
                    ForEach(alignment.bridgePoints) { point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(point.text)
                                .font(.subheadline)
                            
                            HStack {
                                Text("Bridges:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(point.belongsTo, id: \.self) { sectionId in
                                    if let section = alignment.sections.first(where: { $0.id == sectionId }) {
                                        RoleBadge(role: section.role)
                                            .font(.caption2)
                                    }
                                }
                                Spacer()
                                Text("@\(formatSeconds(point.timestamp))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private func loadAlignment() async {
        isLoading = true
        errorMessage = nil
        
        do {
            alignment = try await CreatorAnalysisFirebase.shared.loadAlignmentDoc(
                videoId: video.videoId,
                channelId: video.channelId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func statusIcon(_ status: ValidationStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .needsReview: return "exclamationmark.circle.fill"
        }
    }
    
    private func statusColor(_ status: ValidationStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .passed: return .green
        case .failed: return .red
        case .needsReview: return .orange
        }
    }
    
    private func formatTimeRange(_ range: TimeRange) -> String {
        "\(formatSeconds(range.start)) - \(formatSeconds(range.end))"
    }

    private func formatSectionRange(_ section: SectionData) -> String {
        // Prefer computed time from word indexes
        if let timeRange = section.estimatedTimeRange(for: video) {
            return "\(formatSeconds(timeRange.start)) - \(formatSeconds(timeRange.end))"
        }
        // Fall back to stored time range (legacy)
        if let timeRange = section.timeRange {
            return "\(formatSeconds(timeRange.start)) - \(formatSeconds(timeRange.end))"
        }
        // Show word range if available
        if let start = section.startWordIndex, let end = section.endWordIndex {
            return "words \(start)-\(end)"
        }
        return "—"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Role Badge
struct RoleBadge: View {
    let role: String
    
    var body: some View {
        Text(role)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(roleColor.opacity(0.2))
            .foregroundColor(roleColor)
            .cornerRadius(4)
    }
    
    private var roleColor: Color {
        switch role {
        case "HOOK": return .purple
        case "SETUP": return .blue
        case "EVIDENCE": return .green
        case "TURN": return .orange
        case "PAYOFF": return .pink
        case "CTA": return .red
        case "SPONSORSHIP": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Section Detail View
struct SectionDetailView: View {
    let section: SectionData
    let video: YouTubeVideo

    var body: some View {
        List {
            Section("Section Info") {
                LabeledContent("Role", value: section.role)

                // Show word boundaries if available (new format)
                if let startWord = section.startWordIndex, let endWord = section.endWordIndex {
                    LabeledContent("Word Range", value: "\(startWord) - \(endWord)")
                    LabeledContent("Word Count", value: "\(endWord - startWord + 1)")
                }

                // Show time range (computed or legacy)
                if let timeRange = section.estimatedTimeRange(for: video) {
                    LabeledContent("Estimated Time", value: "\(formatSeconds(timeRange.start)) - \(formatSeconds(timeRange.end))")
                    LabeledContent("Duration", value: "\(timeRange.end - timeRange.start) seconds")
                } else if let timeRange = section.timeRange {
                    LabeledContent("Time Range", value: "\(formatSeconds(timeRange.start)) - \(formatSeconds(timeRange.end))")
                    LabeledContent("Duration", value: "\(timeRange.end - timeRange.start) seconds")
                }

                // Show analysis format indicator
                if section.hasWordBoundaries {
                    LabeledContent("Format", value: "Word-based (new)")
                } else if section.timeRange != nil {
                    LabeledContent("Format", value: "Time-based (legacy)")
                }
            }

            Section("Goal") {
                Text(section.goal)
                    .font(.body)
            }

            Section("Logic Spine Step") {
                Text(section.logicSpineStep)
                    .font(.body)
            }
        }
        .navigationTitle(section.role)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}