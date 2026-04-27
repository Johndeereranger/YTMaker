//
//  PreA0Models.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import Foundation

// MARK: - Phase 0 Result (Structural DNA - stored on video)

struct Phase0Result: Codable, Hashable, Equatable {
    // Legacy fields (kept for backward compatibility)
    let pivotCount: Int
    let retentionStrategy: String
    let argumentType: String
    let sectionDensity: String
    let transitionMarkers: [String]
    let evidenceTypes: [String]
    let coreQuestion: String
    let narrativeDevice: String
    let majorTransitions: [Phase0Transition]
    let reasoning: String
    let analyzedAt: Date
    let format: String?

    // NEW: Execution Trace (the template-focused extraction)
    let executionTrace: ExecutionTrace?
}

struct Phase0Transition: Codable, Hashable, Equatable {
    let approximateLocation: String?
    let approximatePercent: Int?
    let transitionType: String
    let description: String?
    let fromTo: String?

    var locationDisplay: String {
        if let percent = approximatePercent {
            return "\(percent)%"
        } else if let loc = approximateLocation {
            return loc
        }
        return "unknown"
    }

    var descriptionDisplay: String {
        fromTo ?? description ?? ""
    }
}

// MARK: - Execution Trace (Template-Focused Structural DNA)

/// Describes what LITERALLY HAPPENS in the video's structure.
/// Designed for template compatibility testing - "If I use this trace to write another video, where would it break?"
struct ExecutionTrace: Codable, Hashable, Equatable {
    let opening: OpeningWindow
    let pivots: [PivotMoment]
    let evidenceFlow: [String]      // Evidence types in ORDER they appear
    let escalation: String          // Single description of how stakes/mystery/complexity builds
    let resolution: String          // What literally happens in final 2-3 minutes
    let narratorRole: String        // Character? Detached analyst? On-location explorer? Personal confessor?
}

/// The first 60-90 seconds - what hooks the viewer
struct OpeningWindow: Hashable, Equatable {
    let durationSeconds: Int             // How long before the first pivot? (new format)
    let whatHappens: String              // Literal description of what viewer sees/hears
    let hookType: String                 // "question" | "frustration" | "mystery" | "promise"

    // For backward compatibility with old data that used approximateDurationPercent
    var approximateDurationPercent: Int { durationSeconds }
}

extension OpeningWindow: Codable {
    enum CodingKeys: String, CodingKey {
        case durationSeconds
        case approximateDurationPercent  // Old format
        case whatHappens
        case hookType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first, fall back to old format
        if let seconds = try? container.decode(Int.self, forKey: .durationSeconds) {
            self.durationSeconds = seconds
        } else if let percent = try? container.decode(Int.self, forKey: .approximateDurationPercent) {
            // Old format stored percentage, convert to rough seconds estimate (assume 10 min video)
            self.durationSeconds = percent * 6  // ~10 min = 600 seconds, so 10% = 60 seconds
        } else {
            self.durationSeconds = 60  // Default fallback
        }

        self.whatHappens = try container.decode(String.self, forKey: .whatHappens)
        self.hookType = try container.decode(String.self, forKey: .hookType)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(whatHappens, forKey: .whatHappens)
        try container.encode(hookType, forKey: .hookType)
    }
}

/// A moment where the viewer's mental model is forced to shift
struct PivotMoment: Codable, Hashable, Equatable {
    let pivotNumber: Int
    let timestampPercent: Int            // Approximate % through video (0-100)
    let triggerMoment: String            // Quote or paraphrase the actual moment
    let assumptionChallenged: String     // What the video explicitly contradicts (grounded, not inferred)
}

// MARK: - Break Categories (for clustering compatibility)

/// Reasons why two videos might NOT be template-compatible
enum TemplateBreakCategory: String, Codable, CaseIterable {
    case openingMismatch = "opening-mismatch"           // Opening architecture doesn't transfer
    case narratorMismatch = "narrator-mismatch"         // Creator's relationship to material is incompatible
    case evidenceFlowMismatch = "evidence-flow-mismatch" // Proof accumulation sequence doesn't fit
    case pivotMechanicsMismatch = "pivot-mechanics-mismatch" // Turns are triggered by incompatible mechanisms
    case escalationMismatch = "escalation-mismatch"     // How stakes/complexity builds is structurally different
    case resolutionMismatch = "resolution-mismatch"     // Closing architecture doesn't transfer
    case none = "none"                                  // No structural break — compatible

    var description: String {
        switch self {
        case .openingMismatch: return "Opening architecture doesn't transfer"
        case .narratorMismatch: return "Creator's relationship to material is incompatible"
        case .evidenceFlowMismatch: return "Proof accumulation sequence doesn't fit"
        case .pivotMechanicsMismatch: return "Turns are triggered by incompatible mechanisms"
        case .escalationMismatch: return "How stakes/complexity builds is structurally different"
        case .resolutionMismatch: return "Closing architecture doesn't transfer"
        case .none: return "No structural break — compatible"
        }
    }
}

// MARK: - Video Metadata (Ephemeral - NOT saved to Firebase)

/// Lightweight video info fetched from YouTube API for browsing/clustering
/// This is NOT saved to Firebase - only used during Pre-A0 selection workflow
struct BrowseVideoMetadata: Identifiable, Hashable {
    let videoId: String
    let title: String
    let description: String
    let thumbnailUrl: String
    let duration: String
    let publishedAt: Date
    let viewCount: Int

    var id: String { videoId }

    /// Convert from full YouTubeVideo (for videos already in our database)
    init(from video: YouTubeVideo) {
        self.videoId = video.videoId
        self.title = video.title
        self.description = video.description
        self.thumbnailUrl = video.thumbnailUrl
        self.duration = video.duration
        self.publishedAt = video.publishedAt
        self.viewCount = video.stats.viewCount
    }

    /// Create from YouTube API response data
    init(videoId: String, title: String, description: String, thumbnailUrl: String, duration: String, publishedAt: Date, viewCount: Int) {
        self.videoId = videoId
        self.title = title
        self.description = description
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.publishedAt = publishedAt
        self.viewCount = viewCount
    }
}

// MARK: - Title Cluster (Ephemeral - for Pre-A0 UI)

/// A group of videos clustered by content theme
/// Used during Pre-A0 workflow to help select representative videos
struct TitleCluster: Identifiable {
    let id: UUID = UUID()
    let theme: String                    // "Historical Deep Dives"
    let description: String              // "Videos exploring historical events and their origins"
    var videos: [BrowseVideoMetadata]          // All videos in this cluster
    var existingVideoIds: Set<String>    // Video IDs already in our Firebase
    var selectedVideoIds: Set<String>    // User's selections (new videos to import)
    let suggestedCount: Int              // How many videos to pick from this cluster

    var existingCount: Int { existingVideoIds.count }
    var selectedCount: Int { selectedVideoIds.count }
    var totalSelected: Int { existingCount + selectedCount }
    var totalVideos: Int { videos.count }

    /// Videos not yet in our database
    var newVideos: [BrowseVideoMetadata] {
        videos.filter { !existingVideoIds.contains($0.videoId) }
    }

    /// Videos already imported
    var existingVideos: [BrowseVideoMetadata] {
        videos.filter { existingVideoIds.contains($0.videoId) }
    }
}

// MARK: - Style Taxonomy (Stored per creator in Firebase)

struct StyleTaxonomy: Codable, Identifiable {
    var id: String { channelId }
    let channelId: String
    var templates: [StyleTemplate]
    var videoCount: Int              // How many videos were used to build this
    var minimumVideos: Int = 15      // Configurable threshold
    var createdAt: Date
    var updatedAt: Date

    // From aggregation result
    var creatorOrientation: CreatorOrientation? = nil // Phase 1 results - overall creator approach
    var sharedPatterns: [String] = []       // Patterns shared across all types (creator's signature moves)
    var creatorSignature: String = ""       // Summary of what makes this creator unique
}

// MARK: - Style Template (Individual template within taxonomy)

struct StyleTemplate: Codable, Identifiable, Hashable {
    let id: String                          // "harris_historical_investigation"
    var name: String                        // "Historical Investigation"
    var description: String
    var videoIds: [String]                  // Which videos belong to this cluster

    // Centroid characteristics (what defines this cluster)
    var expectedPivotMin: Int
    var expectedPivotMax: Int
    var retentionStrategy: String
    var argumentType: String
    var sectionDensity: String
    var commonTransitionMarkers: [String]
    var commonEvidenceTypes: [String]

    // A1a injection parameters
    var expectedSectionsMin: Int
    var expectedSectionsMax: Int
    var turnSignals: [String]
    var customInstructions: String?

    // A1a custom prompt (the key field for template-specific analysis)
    var a1aSystemPrompt: String?            // Custom A1a prompt for this template
    var a1aLastTestedAt: Date?              // When the prompt was last fidelity tested
    var a1aStabilityScore: Double?          // 0.0-1.0, how stable the prompt is across runs

    // From aggregation (human-readable context)
    var coreQuestion: String?               // "How did this system come to be?"
    var narrativeArc: String?               // "Chronological 'how did we get here' building to modern implications"

    var videoCount: Int { videoIds.count }

    var expectedPivotRange: ClosedRange<Int> {
        expectedPivotMin...expectedPivotMax
    }

    var expectedSectionsRange: ClosedRange<Int> {
        expectedSectionsMin...expectedSectionsMax
    }

    var hasA1aPrompt: Bool { a1aSystemPrompt != nil && !a1aSystemPrompt!.isEmpty }
    var hasBeenTested: Bool { a1aLastTestedAt != nil }
}

// MARK: - Video Purpose Enum (for display/filtering UI)

enum VideoPurpose: String, CaseIterable, Identifiable {
    case taxonomyBuilding = "Taxonomy Building"
    case scriptAnalysis = "Script Analysis"
    case researchData = "Research Data"
    case ideaGeneration = "Idea Generation"
    case thumbnailStudy = "Thumbnail Study"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .taxonomyBuilding: return "rectangle.3.group"
        case .scriptAnalysis: return "doc.text.magnifyingglass"
        case .researchData: return "books.vertical"
        case .ideaGeneration: return "lightbulb"
        case .thumbnailStudy: return "photo"
        }
    }

    var description: String {
        switch self {
        case .taxonomyBuilding: return "Videos used to build creator style taxonomy"
        case .scriptAnalysis: return "Videos for detailed script breakdown analysis"
        case .researchData: return "Videos as research references for topics"
        case .ideaGeneration: return "Videos for inspiration and new ideas"
        case .thumbnailStudy: return "Videos for thumbnail/title analysis"
        }
    }
}

// MARK: - Creator Orientation (Phase 1 of aggregation)

/// Overall creator style captured in Phase 1 of aggregation
struct CreatorOrientation: Codable, Hashable {
    let primaryEvidenceSources: String  // What does this creator rely on for credibility
    let emotionalTrajectory: String     // What emotional experience do videos create
    let creatorPositioning: String      // How does the creator relate to material/audience
    let resolutionPattern: String       // How do videos typically end
}

// MARK: - Content Type Cluster (from Phase 0 aggregation)

/// Viewer transformation - what changes from before to after watching
struct ViewerTransformation: Codable, Hashable {
    let before: String
    let after: String
}

/// Signature moves - recurring patterns in this content type
struct SignatureMoves: Codable, Hashable {
    let openingPattern: String
    let pivotMechanism: String
    let endingPattern: String
}

/// Result from aggregating Phase 0 analyses - human-readable content type
struct ContentTypeCluster: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String                    // "Historical Investigation"
    let coreQuestion: String            // "How did this system come to be?"
    let description: String             // Longer description of what defines this type
    let evidenceTypes: [String]         // Common evidence types used
    let narrativeArc: String            // How these videos typically flow
    var videoIds: [String]              // Video IDs assigned to this cluster

    // Aggregated Phase 0 characteristics (ranges)
    let typicalPivotMin: Int
    let typicalPivotMax: Int
    let dominantRetentionStrategy: String
    let dominantArgumentType: String
    let dominantSectionDensity: String

    // Intent Features (new)
    let viewerTransformation: ViewerTransformation?
    let emotionalArc: String?           // What feeling builds throughout
    let creatorRole: String?            // How creator positions themselves in this type

    // Signature Moves (new)
    let signatureMoves: SignatureMoves?

    var videoCount: Int { videoIds.count }

    init(
        name: String,
        coreQuestion: String,
        description: String,
        evidenceTypes: [String],
        narrativeArc: String,
        videoIds: [String],
        typicalPivotMin: Int,
        typicalPivotMax: Int,
        dominantRetentionStrategy: String,
        dominantArgumentType: String,
        dominantSectionDensity: String,
        viewerTransformation: ViewerTransformation? = nil,
        emotionalArc: String? = nil,
        creatorRole: String? = nil,
        signatureMoves: SignatureMoves? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.coreQuestion = coreQuestion
        self.description = description
        self.evidenceTypes = evidenceTypes
        self.narrativeArc = narrativeArc
        self.videoIds = videoIds
        self.typicalPivotMin = typicalPivotMin
        self.typicalPivotMax = typicalPivotMax
        self.dominantRetentionStrategy = dominantRetentionStrategy
        self.dominantArgumentType = dominantArgumentType
        self.dominantSectionDensity = dominantSectionDensity
        self.viewerTransformation = viewerTransformation
        self.emotionalArc = emotionalArc
        self.creatorRole = creatorRole
        self.signatureMoves = signatureMoves
    }
}

/// Result from the aggregation LLM call (legacy format)
struct TaxonomyAggregationResult: Codable {
    let creatorOrientation: CreatorOrientation?
    let clusters: [ContentTypeCluster]
    let sharedPatterns: [String]
    let creatorSignature: String
}

// MARK: - Style Library (New Template-Focused Clustering)

/// A style library is a group of videos that are TEMPLATE-COMPATIBLE.
/// If you use any video in this library as a structural template, the output should feel similar.
struct StyleLibrary: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String                    // Short name describing the EXECUTION APPROACH
    let stylePresetTag: String          // kebab-case-tag for programmatic use
    let whatThisTrains: String          // What new video can an AI write after studying this?

    // The replicable structural recipe
    let executionRecipe: ExecutionRecipe

    // Training set info
    let trainingSet: TrainingSet

    // Usage guidance for AI generation
    let usageGuidance: UsageGuidance

    var videoCount: Int { trainingSet.videoIds.count }

    init(
        name: String,
        stylePresetTag: String,
        whatThisTrains: String,
        executionRecipe: ExecutionRecipe,
        trainingSet: TrainingSet,
        usageGuidance: UsageGuidance
    ) {
        self.id = UUID()
        self.name = name
        self.stylePresetTag = stylePresetTag
        self.whatThisTrains = whatThisTrains
        self.executionRecipe = executionRecipe
        self.trainingSet = trainingSet
        self.usageGuidance = usageGuidance
    }
}

/// The structural recipe that defines a style library
struct ExecutionRecipe: Codable, Hashable {
    let opening: String                 // What happens in first 60-90 seconds?
    let pivotPattern: String            // How many pivots, what triggers them?
    let evidenceFlow: String            // How does proof accumulate?
    let escalation: String              // How do stakes build?
    let resolution: String              // How does it close?
}

/// Information about which videos belong to this library and why
struct TrainingSet: Codable, Hashable {
    let videoIds: [String]
    let whyTheseBelongTogether: String  // Structural survivability explanation
    let notesForAI: String              // What's key to replicating this style?
}

/// Guidance for when to use this style library
struct UsageGuidance: Codable, Hashable {
    let bestUseCaseForGeneration: String  // What video idea fits this style?
    let referencePriority: String         // "high" | "medium" | "niche"
}

/// Boundary decision for videos that were difficult to assign
struct BoundaryDecision: Codable, Hashable {
    let videoId: String
    let assignedTo: String              // stylePresetTag
    let consideredFor: [String]         // Other tags considered
    let decisionReason: String          // Why this cluster
    let wouldBreakAt: String            // Break category if used for rejected cluster
}

/// Result from the new style library clustering
struct StyleLibraryAggregationResult: Codable {
    let styleLibraries: [StyleLibrary]
    let boundaryDecisions: [BoundaryDecision]
}

// MARK: - Pre-A0 Workflow State

enum PreA0Step: Int, CaseIterable {
    case fetching = 0
    case clustering = 1
    case selecting = 2
    case importing = 3

    var title: String {
        switch self {
        case .fetching: return "Fetch"
        case .clustering: return "Cluster"
        case .selecting: return "Select"
        case .importing: return "Import"
        }
    }

    var description: String {
        switch self {
        case .fetching: return "Fetching video metadata from YouTube..."
        case .clustering: return "Clustering videos by content theme..."
        case .selecting: return "Select representative videos from each cluster"
        case .importing: return "Importing selected videos..."
        }
    }
}

// MARK: - Locked Taxonomy (User-Created, Template-Focused)

/// A locked taxonomy is created externally by the user and pasted into the app.
/// It defines structural templates for per-video classification.
/// Unlike auto-generated taxonomies, locked taxonomies are:
/// - Created through external chat sessions using fidelity debug output
/// - Template-focused (execution recipes, not category labels)
/// - Used for per-video classification after being locked
struct LockedTaxonomy: Codable, Identifiable {
    var id: String { channelId }
    let channelId: String
    var templates: [LockedTemplate]
    let createdAt: Date
    var updatedAt: Date
    var lockedAt: Date?          // When the taxonomy was locked (nil = draft)
    var isLocked: Bool { lockedAt != nil }

    var templateCount: Int { templates.count }
    var totalExemplarCount: Int { templates.reduce(0) { $0 + $1.exemplarVideoIds.count } }
}

/// A single template within a locked taxonomy
/// Used for CLASSIFICATION only (routing videos to the right template)
/// NOTE: executionRecipe is NOT stored here - it gets extracted by A3 after
/// running exemplars through A1a/A1b. The recipe is an OUTPUT, not an INPUT.
struct LockedTemplate: Codable, Identifiable, Hashable {
    let id: String                          // "mystery-investigation", "explainer-thread", etc.
    var name: String                        // Human-readable name
    var description: String                 // 2-3 sentences describing this template

    // Classification criteria - what signals indicate this template
    var classificationCriteria: ClassificationCriteria

    // Exemplar videos - videos that exemplify this template
    // These get run through A1a/A1b, then A3 extracts the execution recipe
    var exemplarVideoIds: [String]

    // A1a Prompt Engineering - template-specific extraction prompts
    var a1aSystemPrompt: String?            // Custom A1a prompt for this template
    var a1aLastTestedAt: Date?              // When the prompt was last fidelity tested
    var a1aStabilityScore: Double?          // 0.0-1.0, how stable the prompt is across runs

    // Role vocabulary - creator-specific or template-specific role definitions
    var roleVocabulary: [String]?           // Allowed roles for sections (e.g., "hook", "pivot", "reveal")

    var exemplarCount: Int { exemplarVideoIds.count }
    var hasA1aPrompt: Bool { a1aSystemPrompt != nil && !a1aSystemPrompt!.isEmpty }
    var hasBeenTested: Bool { a1aLastTestedAt != nil }
}

/// Criteria for classifying a video into a template
struct ClassificationCriteria: Codable, Hashable {
    var requiredSignals: [String]           // Signals that MUST be present
    var antiSignals: [String]               // Signals that MUST NOT be present
}

// MARK: - Taxonomy Paste Validation

/// Result of validating a pasted taxonomy JSON
enum TaxonomyValidationResult {
    case valid(LockedTaxonomy)
    case invalidJSON(String)
    case missingFields([String])
    case invalidTemplates([String])         // Template-specific errors
}

/// Helper extension for JSON template generation
extension LockedTaxonomy {
    /// Generate a blank JSON template for the user to fill out externally
    /// NOTE: No executionRecipe - that gets extracted by A3 after exemplars are analyzed
    static func blankTemplate(channelId: String) -> String {
        """
        {
          "channelId": "\(channelId)",
          "templates": [
            {
              "id": "template-id-kebab-case",
              "name": "Human Readable Template Name",
              "description": "2-3 sentences describing what defines this template. Focus on structural elements, not topics.",
              "classificationCriteria": {
                "requiredSignals": [
                  "signal-that-must-be-present-1",
                  "signal-that-must-be-present-2"
                ],
                "antiSignals": [
                  "signal-that-must-NOT-be-present"
                ]
              },
              "exemplarVideoIds": [
                "VIDEO_ID_1",
                "VIDEO_ID_2",
                "VIDEO_ID_3"
              ]
            }
          ]
        }
        """
    }

    /// Generate a single template JSON snippet for adding to existing taxonomy
    static func singleTemplateSnippet() -> String {
        """
        {
          "id": "new-template-id-kebab-case",
          "name": "New Template Name",
          "description": "2-3 sentences describing this template.",
          "classificationCriteria": {
            "requiredSignals": ["signal-1", "signal-2"],
            "antiSignals": ["anti-signal-1"]
          },
          "exemplarVideoIds": ["VIDEO_ID_1", "VIDEO_ID_2"]
        }
        """
    }

    /// Validate a JSON string and return a LockedTaxonomy or error
    static func validate(json: String, expectedChannelId: String) -> TaxonomyValidationResult {
        guard let data = json.data(using: .utf8) else {
            return .invalidJSON("Could not convert string to data")
        }

        do {
            let decoded = try JSONDecoder().decode(LockedTaxonomyInput.self, from: data)

            // Validate channel ID matches
            if decoded.channelId != expectedChannelId {
                return .missingFields(["channelId mismatch: expected '\(expectedChannelId)' but got '\(decoded.channelId)'"])
            }

            // Validate templates
            var templateErrors: [String] = []
            for (index, template) in decoded.templates.enumerated() {
                if template.id.isEmpty {
                    templateErrors.append("Template \(index + 1): missing id")
                }
                if template.name.isEmpty {
                    templateErrors.append("Template \(index + 1): missing name")
                }
                if template.exemplarVideoIds.isEmpty {
                    templateErrors.append("Template '\(template.name)': needs at least one exemplar video")
                }
            }

            if !templateErrors.isEmpty {
                return .invalidTemplates(templateErrors)
            }

            // Convert to LockedTaxonomy
            let taxonomy = LockedTaxonomy(
                channelId: decoded.channelId,
                templates: decoded.templates.map { input in
                    LockedTemplate(
                        id: input.id,
                        name: input.name,
                        description: input.description,
                        classificationCriteria: ClassificationCriteria(
                            requiredSignals: input.classificationCriteria.requiredSignals,
                            antiSignals: input.classificationCriteria.antiSignals
                        ),
                        exemplarVideoIds: input.exemplarVideoIds
                    )
                },
                createdAt: Date(),
                updatedAt: Date(),
                lockedAt: nil
            )

            return .valid(taxonomy)

        } catch {
            return .invalidJSON("JSON parsing error: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON Input Types (for parsing user-pasted JSON)

/// Input format for parsing user-pasted taxonomy JSON
struct LockedTaxonomyInput: Codable {
    let channelId: String
    let templates: [LockedTemplateInput]
}

/// Input format for a single template (classification only, no executionRecipe)
struct LockedTemplateInput: Codable {
    let id: String
    let name: String
    let description: String
    let classificationCriteria: ClassificationCriteriaInput
    let exemplarVideoIds: [String]
}

struct ClassificationCriteriaInput: Codable {
    let requiredSignals: [String]
    let antiSignals: [String]
}
