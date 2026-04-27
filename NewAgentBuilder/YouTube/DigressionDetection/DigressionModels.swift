import SwiftUI

// MARK: - DigressionType

enum DigressionType: String, Codable, CaseIterable, Identifiable {
    case personalAside
    case sponsorRead
    case metaCommentary
    case tangent
    case moralCorrection
    case selfPromotion
    case foreshadowingPlant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalAside: return "Personal Aside"
        case .sponsorRead: return "Sponsor Read"
        case .metaCommentary: return "Meta Commentary"
        case .tangent: return "Tangent"
        case .moralCorrection: return "Moral Correction"
        case .selfPromotion: return "Self-Promotion"
        case .foreshadowingPlant: return "Foreshadowing Plant"
        }
    }

    var color: Color {
        switch self {
        case .personalAside: return .blue
        case .sponsorRead: return .yellow
        case .metaCommentary: return .purple
        case .tangent: return .orange
        case .moralCorrection: return .red
        case .selfPromotion: return .green
        case .foreshadowingPlant: return .cyan
        }
    }

    /// Maximum sentences to scan before forcing exit
    var maxScan: Int {
        switch self {
        case .personalAside: return 8
        case .sponsorRead: return 20
        case .metaCommentary: return 6
        case .tangent: return 5
        case .moralCorrection: return 5
        case .selfPromotion: return 5
        case .foreshadowingPlant: return 2
        }
    }

    /// Minimum sentences for a valid digression of this type
    var minLength: Int {
        switch self {
        case .personalAside: return 2
        case .sponsorRead: return 2
        case .metaCommentary: return 2
        case .tangent: return 2
        case .moralCorrection: return 2
        case .selfPromotion: return 2
        case .foreshadowingPlant: return 1
        }
    }

    var entrySignalDescription: String {
        switch self {
        case .personalAside: return "First-person shift from third-person narrative + trigger phrase (\"wait a minute\", \"so I actually\")"
        case .sponsorRead: return "Sponsor content flag or \"sponsored by\" / \"brought to you by\" pattern"
        case .metaCommentary: return "Second-person address mid-video + meta phrase (\"how are you liking\", \"let me know\")"
        case .tangent: return "Stance shift to questioning after asserting + associative trigger (\"I wonder if\", \"speaking of which\")"
        case .moralCorrection: return "Evaluative phrase match (\"but don't be fooled\", \"let's be clear\", \"make no mistake\")"
        case .selfPromotion: return "CTA flag (non-sponsor) mid-video + creator project reference"
        case .foreshadowingPlant: return "Forward reference phrase (\"remember this\", \"we'll come back to\")"
        }
    }

    var exitSignalDescription: String {
        switch self {
        case .personalAside: return "\"Anyway\" + dismissal, or return to third-person, or maxScan"
        case .sponsorRead: return "Sponsor content flag flips false"
        case .metaCommentary: return "CTA + return marker, or perspective shift away, or maxScan"
        case .tangent: return "\"Anyway\" / self-correction, or return to asserting + third-person, or maxScan"
        case .moralCorrection: return "Return to asserting + third-person after evaluative sentences, or maxScan"
        case .selfPromotion: return "CTA ends + return marker, or maxScan"
        case .foreshadowingPlant: return "Auto-close after 1-2 sentences"
        }
    }

    /// Detection priority — lower number = checked first
    var priority: Int {
        switch self {
        case .sponsorRead: return 0
        case .personalAside: return 1
        case .metaCommentary: return 2
        case .tangent: return 3
        case .moralCorrection: return 4
        case .selfPromotion: return 5
        case .foreshadowingPlant: return 6
        }
    }

    /// All types sorted by detection priority
    static var byPriority: [DigressionType] {
        allCases.sorted { $0.priority < $1.priority }
    }
}

// MARK: - DigressionDetectionMethod

enum DigressionDetectionMethod: String, Codable {
    case deterministic
    case llm
    case hybrid

    var displayName: String {
        switch self {
        case .deterministic: return "Deterministic"
        case .llm: return "LLM"
        case .hybrid: return "Hybrid"
        }
    }
}

// MARK: - DetectionMode

enum DetectionMode: String, Codable, CaseIterable {
    case rulesFirst    // Deterministic rules, then optional LLM escalation
    case llmFirst      // LLM full-transcript, then rules validation

    var displayName: String {
        switch self {
        case .rulesFirst: return "Rules First"
        case .llmFirst: return "LLM First"
        }
    }
}

// MARK: - RulesVerdict

enum RulesVerdict: String, Codable {
    case confirmed    // telemetry signals match this digression type
    case neutral      // no signals either way
    case contradicted // telemetry signals conflict with this type

    var symbol: String {
        switch self {
        case .confirmed: return "checkmark.circle.fill"
        case .neutral: return "minus.circle"
        case .contradicted: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .confirmed: return .green
        case .neutral: return .secondary
        case .contradicted: return .orange
        }
    }
}

// MARK: - ValidatedDigression

struct ValidatedDigression: Identifiable {
    let id: UUID
    let annotation: DigressionAnnotation
    let verdict: RulesVerdict
    let checks: [GateCheck]
    let contradictionReason: String?

    struct GateCheck: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    init(
        annotation: DigressionAnnotation,
        verdict: RulesVerdict,
        checks: [GateCheck],
        contradictionReason: String? = nil
    ) {
        self.id = annotation.id
        self.annotation = annotation
        self.verdict = verdict
        self.checks = checks
        self.contradictionReason = contradictionReason
    }
}

// MARK: - DigressionAnnotation

struct DigressionAnnotation: Codable, Identifiable, Hashable {
    let id: UUID

    // Location (0-indexed, matching SentenceTelemetry.sentenceIndex)
    let startSentence: Int
    let endSentence: Int  // inclusive
    let entryMarker: String
    let exitMarker: String

    // Classification
    let type: DigressionType
    var confidence: Double  // 0.0–1.0
    let detectionMethod: DigressionDetectionMethod

    // Context (nullable — populated by LLM enrichment, NOT deterministic pass)
    var surroundingNarrativeThread: String?
    var briefContent: String?

    // Mechanical
    var sentenceCount: Int { endSentence - startSentence + 1 }
    let hasCTA: Bool
    let perspectiveShift: Bool
    let stanceShift: Bool

    // Foreshadowing-specific (nullable)
    var foreshadowingPayoffSentence: Int?
    var foreshadowingDistance: Int?

    init(
        startSentence: Int,
        endSentence: Int,
        entryMarker: String,
        exitMarker: String,
        type: DigressionType,
        confidence: Double,
        detectionMethod: DigressionDetectionMethod,
        surroundingNarrativeThread: String? = nil,
        briefContent: String? = nil,
        hasCTA: Bool,
        perspectiveShift: Bool,
        stanceShift: Bool,
        foreshadowingPayoffSentence: Int? = nil,
        foreshadowingDistance: Int? = nil
    ) {
        self.id = UUID()
        self.startSentence = startSentence
        self.endSentence = endSentence
        self.entryMarker = entryMarker
        self.exitMarker = exitMarker
        self.type = type
        self.confidence = confidence
        self.detectionMethod = detectionMethod
        self.surroundingNarrativeThread = surroundingNarrativeThread
        self.briefContent = briefContent
        self.hasCTA = hasCTA
        self.perspectiveShift = perspectiveShift
        self.stanceShift = stanceShift
        self.foreshadowingPayoffSentence = foreshadowingPayoffSentence
        self.foreshadowingDistance = foreshadowingDistance
    }

    // MARK: Hashable

    static func == (lhs: DigressionAnnotation, rhs: DigressionAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Range of sentence indices covered by this digression
    var sentenceRange: ClosedRange<Int> {
        startSentence...endSentence
    }

    /// Whether this digression contains a specific sentence index
    func contains(sentenceIndex: Int) -> Bool {
        sentenceRange.contains(sentenceIndex)
    }
}

// MARK: - DigressionDetectionResult

struct DigressionDetectionResult: Codable, Identifiable {
    let id: UUID
    let videoId: String
    let createdAt: Date
    let digressions: [DigressionAnnotation]
    let cleanSentenceIndices: [Int]
    let totalSentences: Int
    let config: DigressionDetectionConfig

    init(
        videoId: String,
        digressions: [DigressionAnnotation],
        cleanSentenceIndices: [Int],
        totalSentences: Int,
        config: DigressionDetectionConfig
    ) {
        self.id = UUID()
        self.videoId = videoId
        self.createdAt = Date()
        self.digressions = digressions
        self.cleanSentenceIndices = cleanSentenceIndices
        self.totalSentences = totalSentences
        self.config = config
    }

    // MARK: Computed Stats

    var digressionCount: Int { digressions.count }

    var digressedSentenceCount: Int {
        totalSentences - cleanSentenceIndices.count
    }

    var coveragePercent: Double {
        guard totalSentences > 0 else { return 0 }
        return Double(digressedSentenceCount) / Double(totalSentences) * 100.0
    }

    var typeDistribution: [DigressionType: Int] {
        var dist: [DigressionType: Int] = [:]
        for d in digressions {
            dist[d.type, default: 0] += 1
        }
        return dist
    }

    var deterministicCount: Int {
        digressions.filter { $0.detectionMethod == .deterministic }.count
    }

    var llmCount: Int {
        digressions.filter { $0.detectionMethod == .llm }.count
    }

    var hybridCount: Int {
        digressions.filter { $0.detectionMethod == .hybrid }.count
    }

    var averageConfidence: Double {
        guard !digressions.isEmpty else { return 0 }
        return digressions.map(\.confidence).reduce(0, +) / Double(digressions.count)
    }
}

// MARK: - DigressionDetectionConfig

struct DigressionDetectionConfig: Codable {
    var enableLLMEscalation: Bool
    var temperature: Double
    var maxConcurrentLLMCalls: Int
    var enabledTypes: Set<DigressionType>
    var minConfidenceThreshold: Double
    var boundaryBoostEnabled: Bool
    var boundaryBoostAmount: Double
    var detectionMode: DetectionMode

    static let `default` = DigressionDetectionConfig(
        enableLLMEscalation: false,
        temperature: 0.3,
        maxConcurrentLLMCalls: 5,
        enabledTypes: Set(DigressionType.allCases),
        minConfidenceThreshold: 0.0,
        boundaryBoostEnabled: true,
        boundaryBoostAmount: 0.2,
        detectionMode: .rulesFirst
    )

    // Custom decoder to handle saved data that doesn't include detectionMode
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableLLMEscalation = try container.decode(Bool.self, forKey: .enableLLMEscalation)
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxConcurrentLLMCalls = try container.decode(Int.self, forKey: .maxConcurrentLLMCalls)
        enabledTypes = try container.decode(Set<DigressionType>.self, forKey: .enabledTypes)
        minConfidenceThreshold = try container.decode(Double.self, forKey: .minConfidenceThreshold)
        boundaryBoostEnabled = try container.decode(Bool.self, forKey: .boundaryBoostEnabled)
        boundaryBoostAmount = try container.decode(Double.self, forKey: .boundaryBoostAmount)
        detectionMode = (try? container.decode(DetectionMode.self, forKey: .detectionMode)) ?? .rulesFirst
    }

    init(
        enableLLMEscalation: Bool,
        temperature: Double,
        maxConcurrentLLMCalls: Int,
        enabledTypes: Set<DigressionType>,
        minConfidenceThreshold: Double,
        boundaryBoostEnabled: Bool,
        boundaryBoostAmount: Double,
        detectionMode: DetectionMode = .rulesFirst
    ) {
        self.enableLLMEscalation = enableLLMEscalation
        self.temperature = temperature
        self.maxConcurrentLLMCalls = maxConcurrentLLMCalls
        self.enabledTypes = enabledTypes
        self.minConfidenceThreshold = minConfidenceThreshold
        self.boundaryBoostEnabled = boundaryBoostEnabled
        self.boundaryBoostAmount = boundaryBoostAmount
        self.detectionMode = detectionMode
    }
}

// MARK: - DigressionFidelityRunResult

struct DigressionFidelityRunResult: Codable, Identifiable {
    let id: UUID
    let runNumber: Int
    let temperature: Double
    let enabledLLMEscalation: Bool
    let digressions: [DigressionAnnotation]
    let cleanSentenceIndices: [Int]
    let totalSentences: Int
    let createdAt: Date
    let detectionMode: DetectionMode?

    init(
        runNumber: Int,
        temperature: Double,
        enabledLLMEscalation: Bool,
        digressions: [DigressionAnnotation],
        cleanSentenceIndices: [Int],
        totalSentences: Int,
        detectionMode: DetectionMode? = nil
    ) {
        self.id = UUID()
        self.runNumber = runNumber
        self.temperature = temperature
        self.enabledLLMEscalation = enabledLLMEscalation
        self.digressions = digressions
        self.cleanSentenceIndices = cleanSentenceIndices
        self.totalSentences = totalSentences
        self.createdAt = Date()
        self.detectionMode = detectionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        runNumber = try container.decode(Int.self, forKey: .runNumber)
        temperature = try container.decode(Double.self, forKey: .temperature)
        enabledLLMEscalation = try container.decode(Bool.self, forKey: .enabledLLMEscalation)
        digressions = try container.decode([DigressionAnnotation].self, forKey: .digressions)
        cleanSentenceIndices = try container.decode([Int].self, forKey: .cleanSentenceIndices)
        totalSentences = try container.decode(Int.self, forKey: .totalSentences)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        detectionMode = try? container.decode(DetectionMode.self, forKey: .detectionMode)
    }

    var digressionCount: Int { digressions.count }

    var typeDistribution: [DigressionType: Int] {
        var dist: [DigressionType: Int] = [:]
        for d in digressions {
            dist[d.type, default: 0] += 1
        }
        return dist
    }
}

// MARK: - CrossRunDigressionComparison

struct CrossRunDigressionComparison: Identifiable {
    let id: Int  // sentence index
    let sentenceIndex: Int
    let sentenceText: String
    let runsDetected: Int      // how many runs flagged this sentence as digression
    let totalRuns: Int
    let typesFound: Set<DigressionType>

    /// Fraction of runs that agree this sentence is a digression
    var consistency: Double {
        guard totalRuns > 0 else { return 0 }
        return Double(runsDetected) / Double(totalRuns)
    }

    /// All runs agree this is a digression
    var isUnanimous: Bool {
        runsDetected == totalRuns && totalRuns > 0
    }

    /// All runs agree this is NOT a digression
    var isUnanimouslyClean: Bool {
        runsDetected == 0
    }

    /// Runs disagree on whether this is a digression
    var isDivergent: Bool {
        runsDetected > 0 && runsDetected < totalRuns
    }

    /// Whether the type classification is consistent across runs
    var typeConsistent: Bool {
        typesFound.count <= 1
    }

    var consistencyLabel: String {
        if isUnanimous { return "Unanimous Digression" }
        if isUnanimouslyClean { return "Unanimous Clean" }
        return "Divergent (\(runsDetected)/\(totalRuns))"
    }

    var consistencyColor: Color {
        if isUnanimouslyClean { return .green }
        if isUnanimous { return .blue }
        if consistency >= 0.5 { return .orange }
        return .yellow
    }
}

// MARK: - CrossRunDigressionRegion

/// A cluster of overlapping digressions across multiple runs, shown as one row in the summary.
struct CrossRunDigressionRegion: Identifiable {
    let id = UUID()
    let mergedStart: Int
    let mergedEnd: Int
    let primaryType: DigressionType
    let typesFound: Set<DigressionType>
    let runsDetected: Int
    let totalRuns: Int
    let perRunAnnotation: [Int: DigressionAnnotation]  // runNumber → annotation
    let briefContent: String?

    var rangeLabel: String { "s\(mergedStart)-s\(mergedEnd)" }
    var sentenceCount: Int { mergedEnd - mergedStart + 1 }

    var consistency: Double {
        guard totalRuns > 0 else { return 0 }
        return Double(runsDetected) / Double(totalRuns)
    }

    var isUnanimous: Bool { runsDetected == totalRuns && totalRuns > 0 }
    var isDivergent: Bool { runsDetected > 0 && runsDetected < totalRuns }

    /// Build regions by clustering overlapping digressions across runs
    static func buildRegions(from runs: [DigressionFidelityRunResult]) -> [CrossRunDigressionRegion] {
        guard !runs.isEmpty else { return [] }
        let totalRuns = runs.count

        // Collect all (runNumber, annotation) pairs
        var allAnnotations: [(runNumber: Int, annotation: DigressionAnnotation)] = []
        for run in runs {
            for d in run.digressions {
                allAnnotations.append((run.runNumber, d))
            }
        }
        guard !allAnnotations.isEmpty else { return [] }

        // Sort by start sentence
        allAnnotations.sort { $0.annotation.startSentence < $1.annotation.startSentence }

        // Cluster overlapping annotations into regions using union-find style merging
        var clusters: [[(runNumber: Int, annotation: DigressionAnnotation)]] = []

        for item in allAnnotations {
            let itemRange = item.annotation.startSentence...item.annotation.endSentence
            // Find a cluster whose merged range overlaps this annotation
            if let clusterIdx = clusters.firstIndex(where: { cluster in
                let clusterStart = cluster.map(\.annotation.startSentence).min()!
                let clusterEnd = cluster.map(\.annotation.endSentence).max()!
                return (clusterStart...clusterEnd).overlaps(itemRange)
            }) {
                clusters[clusterIdx].append(item)
            } else {
                clusters.append([item])
            }
        }

        // Convert clusters to regions
        return clusters.map { cluster in
            let start = cluster.map(\.annotation.startSentence).min()!
            let end = cluster.map(\.annotation.endSentence).max()!

            // Count types to find primary
            var typeCounts: [DigressionType: Int] = [:]
            var typesFound = Set<DigressionType>()
            var perRun: [Int: DigressionAnnotation] = [:]
            var brief: String?

            // Track unique run numbers (a run only counts once per region)
            var runsInRegion = Set<Int>()

            for item in cluster {
                typeCounts[item.annotation.type, default: 0] += 1
                typesFound.insert(item.annotation.type)
                runsInRegion.insert(item.runNumber)
                // Keep the first annotation per run
                if perRun[item.runNumber] == nil {
                    perRun[item.runNumber] = item.annotation
                }
                if brief == nil, let b = item.annotation.briefContent, !b.isEmpty {
                    brief = b
                }
            }

            let primaryType = typeCounts.max(by: { $0.value < $1.value })?.key ?? cluster.first!.annotation.type

            return CrossRunDigressionRegion(
                mergedStart: start,
                mergedEnd: end,
                primaryType: primaryType,
                typesFound: typesFound,
                runsDetected: runsInRegion.count,
                totalRuns: totalRuns,
                perRunAnnotation: perRun,
                briefContent: brief
            )
        }.sorted { $0.mergedStart < $1.mergedStart }
    }
}

// MARK: - DigressionFidelityStorage

struct DigressionFidelityStorage: Codable {
    let videoId: String
    var runs: [DigressionFidelityRunResult]
    var lastUpdated: Date

    init(videoId: String, runs: [DigressionFidelityRunResult] = []) {
        self.videoId = videoId
        self.runs = runs
        self.lastUpdated = Date()
    }

    mutating func addRun(_ run: DigressionFidelityRunResult) {
        runs.append(run)
        lastUpdated = Date()
    }

    mutating func clearRuns() {
        runs.removeAll()
        lastUpdated = Date()
    }

    // MARK: UserDefaults Persistence

    static func key(for videoId: String) -> String {
        "digression_fidelity_\(videoId)"
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: videoId))
    }

    static func load(videoId: String) -> DigressionFidelityStorage? {
        guard let data = UserDefaults.standard.data(forKey: key(for: videoId)) else { return nil }
        return try? JSONDecoder().decode(DigressionFidelityStorage.self, from: data)
    }

    // MARK: Cross-Run Analysis

    func buildCrossRunComparison(sentences: [SentenceTelemetry]) -> [CrossRunDigressionComparison] {
        guard !runs.isEmpty else { return [] }

        return sentences.map { sentence in
            let idx = sentence.sentenceIndex
            var detectedCount = 0
            var typesFound = Set<DigressionType>()

            for run in runs {
                for digression in run.digressions {
                    if digression.contains(sentenceIndex: idx) {
                        detectedCount += 1
                        typesFound.insert(digression.type)
                        break  // count each run once per sentence
                    }
                }
            }

            return CrossRunDigressionComparison(
                id: idx,
                sentenceIndex: idx,
                sentenceText: sentence.text,
                runsDetected: detectedCount,
                totalRuns: runs.count,
                typesFound: typesFound
            )
        }
    }

    /// Per-type consistency: what percentage of runs agree on the presence of each type
    func typeConsistency() -> [DigressionType: Double] {
        guard runs.count >= 2 else { return [:] }

        var result: [DigressionType: Double] = [:]
        for type in DigressionType.allCases {
            let countsPerRun = runs.map { run in
                run.digressions.filter { $0.type == type }.count
            }
            let mode = countsPerRun.sorted().count > 0 ?
                countsPerRun.sorted()[countsPerRun.count / 2] : 0
            let agreeing = countsPerRun.filter { $0 == mode }.count
            result[type] = Double(agreeing) / Double(runs.count)
        }
        return result
    }
}
