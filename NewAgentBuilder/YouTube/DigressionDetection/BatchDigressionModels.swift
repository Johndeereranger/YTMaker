import SwiftUI

// MARK: - ConfidenceTier

enum ConfidenceTier: String, CaseIterable, Identifiable {
    case high   // 3/3 = 100%
    case medium // 2/3 = 66%
    case low    // 1/3 = 33%

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: return "100% (3/3)"
        case .medium: return "66% (2/3)"
        case .low: return "33% (1/3)"
        }
    }

    var shortLabel: String {
        switch self {
        case .high: return "100%"
        case .medium: return "66%"
        case .low: return "33%"
        }
    }

    var fraction: String {
        switch self {
        case .high: return "3/3"
        case .medium: return "2/3"
        case .low: return "1/3"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .yellow
        }
    }

    static func from(runsDetected: Int, totalRuns: Int) -> ConfidenceTier {
        guard totalRuns > 0 else { return .low }
        let ratio = Double(runsDetected) / Double(totalRuns)
        if ratio >= 1.0 { return .high }
        if ratio >= 0.6 { return .medium }
        return .low
    }
}

// MARK: - BatchDigressionVideoResult (Firebase Document)

struct BatchDigressionVideoResult: Codable, Identifiable {
    let id: String             // "{channelId}_{videoId}"
    let channelId: String
    let videoId: String
    let videoTitle: String
    var runs: [DigressionFidelityRunResult]  // 0-3 runs
    let totalSentences: Int
    var completedAt: Date?
    let config: DigressionDetectionConfig

    var completedRunCount: Int { runs.count }
    var isComplete: Bool { runs.count >= 3 }

    static func docId(channelId: String, videoId: String) -> String {
        "\(channelId)_\(videoId)"
    }

    init(
        channelId: String,
        videoId: String,
        videoTitle: String,
        runs: [DigressionFidelityRunResult] = [],
        totalSentences: Int,
        completedAt: Date? = nil,
        config: DigressionDetectionConfig
    ) {
        self.id = Self.docId(channelId: channelId, videoId: videoId)
        self.channelId = channelId
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.runs = runs
        self.totalSentences = totalSentences
        self.completedAt = completedAt
        self.config = config
    }
}

// MARK: - AggregatedDigression

struct AggregatedDigression: Identifiable {
    let id = UUID()
    let videoId: String
    let videoTitle: String
    let region: CrossRunDigressionRegion
    let confidenceTier: ConfidenceTier
    let rulesVerdict: RulesVerdict
    let validatedDigressions: [ValidatedDigression]
    let contextBefore: [SentenceTelemetry]       // up to 10 before
    let digressionSentences: [SentenceTelemetry]  // the digression range
    let contextAfter: [SentenceTelemetry]         // up to 10 after
    let allSentences: [SentenceTelemetry]         // full video for transcript nav
}

// Hashable/Equatable by id for navigation
extension AggregatedDigression: Hashable, Equatable {
    static func == (lhs: AggregatedDigression, rhs: AggregatedDigression) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - GlobalDigressionAggregate

struct GlobalDigressionAggregate {
    let allDigressions: [AggregatedDigression]
    let videoCount: Int
    let videosComplete: Int

    var totalDigressions: Int { allDigressions.count }

    var highConfidenceCount: Int {
        allDigressions.filter { $0.confidenceTier == .high }.count
    }

    var mediumConfidenceCount: Int {
        allDigressions.filter { $0.confidenceTier == .medium }.count
    }

    var lowConfidenceCount: Int {
        allDigressions.filter { $0.confidenceTier == .low }.count
    }

    var typeDistribution: [DigressionType: Int] {
        var dist: [DigressionType: Int] = [:]
        for d in allDigressions {
            dist[d.region.primaryType, default: 0] += 1
        }
        return dist
    }

    func filtered(
        tier: ConfidenceTier?,
        type: DigressionType?,
        verdict: RulesVerdict?,
        minSentenceCount: Int = 1
    ) -> [AggregatedDigression] {
        allDigressions.filter { d in
            if let tier, d.confidenceTier != tier { return false }
            if let type, d.region.primaryType != type { return false }
            if let verdict, d.rulesVerdict != verdict { return false }
            if d.region.sentenceCount < minSentenceCount { return false }
            return true
        }
    }

    func groupedByVideo(
        tier: ConfidenceTier?,
        type: DigressionType?,
        verdict: RulesVerdict?,
        minSentenceCount: Int = 1
    ) -> [(videoTitle: String, videoId: String, digressions: [AggregatedDigression])] {
        let items = filtered(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)
        let grouped = Dictionary(grouping: items) { $0.videoId }
        return grouped.map { (videoId, digressions) in
            let title = digressions.first?.videoTitle ?? videoId
            return (videoTitle: title, videoId: videoId, digressions: digressions.sorted { $0.region.mergedStart < $1.region.mergedStart })
        }
        .sorted { $0.videoTitle.localizedCaseInsensitiveCompare($1.videoTitle) == .orderedAscending }
    }
}

// MARK: - GateCheck Extension for Sentence References

extension ValidatedDigression.GateCheck {
    /// Compute which sentence indices this gate check references, given the digression range
    func relevantSentenceIndices(digressionStart: Int, digressionEnd: Int) -> [Int] {
        let nameLC = name.lowercased()

        // Entry-related checks reference the start sentence
        if nameLC.contains("entry") || nameLC.contains("atentry") {
            return [digressionStart]
        }

        // "Previous" checks reference the sentence before entry
        if nameLC.contains("previous") {
            return [max(0, digressionStart - 1)]
        }

        // Majority/range checks reference the full digression range
        if nameLC.contains("majority") || nameLC.contains("inrange") || nameLC.contains("length") {
            return Array(digressionStart...digressionEnd)
        }

        // Position checks reference the start
        if nameLC.contains("position") || nameLC.contains("midvideo") {
            return [digressionStart]
        }

        // CTA checks reference the full range
        if nameLC.contains("cta") {
            return Array(digressionStart...digressionEnd)
        }

        // Sponsor checks reference the full range
        if nameLC.contains("sponsor") {
            return Array(digressionStart...digressionEnd)
        }

        // Default: reference the first sentence of the digression
        return [digressionStart]
    }
}
