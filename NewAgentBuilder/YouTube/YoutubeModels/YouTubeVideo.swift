//
//  YouTubeVideo.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//
import Foundation

struct YouTubeVideo: Codable, Identifiable, Hashable, Equatable {
    let videoId: String
    let channelId: String
    let title: String
    let description: String
    let publishedAt: Date
    let duration: String
    let thumbnailUrl: String
    let stats: VideoStats
    let createdAt: Date
    var scriptBreakdown: ScriptBreakdown?
    
    // Optional - add later
    var transcript: String?
    var factsText: String?
    var summaryText: String?
    var notHunting: Bool = false
    var notes: String?
    var videoType: String?
    var hook: String?
    var hookType: HookType?
    var intro: String?
    
    // A1a Analysis Results (stored ON video doc)
    var videoSummary: String?
    var logicSpine: LogicSpineData?
    var bridgePoints: [BridgePoint]?
    var validationStatus: ValidationStatus?
    var validationIssues: [ValidationIssue]?
    var extractionDate: Date?
    var scriptSummary: ScriptSummary?

    // Purpose flags (queryable booleans for Firebase filtering)
    var forTaxonomyBuilding: Bool = false
    var forScriptAnalysis: Bool = false
    var forResearchData: Bool = false
    var forIdeaGeneration: Bool = false
    var forThumbnailStudy: Bool = false
    var isPinned: Bool = false

    // Phase 0 / Taxonomy data
    var phase0Result: Phase0Result?
    var assignedTemplateId: String?

    // Rhetorical Twin Finder data
    var rhetoricalSequence: RhetoricalSequence?

    // Donor Library Pipeline status
    var donorLibraryStatus: DonorLibraryStatus?

    // Narrative Spine Pipeline status
    var narrativeSpineStatus: NarrativeSpineStatus?

    // Spine-Rhetorical Alignment status
    var spineAlignmentStatus: SpineAlignmentStatus?

    // Identifiable conformance
    var id: String { videoId }
    
    // Equatable conformance
    static func == (lhs: YouTubeVideo, rhs: YouTubeVideo) -> Bool {
        lhs.videoId == rhs.videoId
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
    }
    
    var hasFacts: Bool {
        !(factsText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasSummary: Bool {
        !(summaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasTranscript: Bool {
        !(transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    var hasAnalysis: Bool {
        logicSpine != nil && bridgePoints != nil
    }

    var hasRhetoricalSequence: Bool {
        rhetoricalSequence != nil
    }

    var hasDonorLibrary: Bool {
        donorLibraryStatus?.a5Complete == true
    }

    var hasNarrativeSpine: Bool {
        narrativeSpineStatus?.complete == true
    }

    var hasSpineAlignment: Bool {
        (spineAlignmentStatus?.completedRunCount ?? 0) >= 1
    }

    var hasAllSpineAlignmentRuns: Bool {
        (spineAlignmentStatus?.completedRunCount ?? 0) >= 3
    }

    // MARK: - Word Count & Duration Computed Properties

    /// Word count from transcript (returns 0 if no transcript)
    var wordCount: Int {
        guard let text = transcript, !text.isEmpty else { return 0 }
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    /// Parse ISO 8601 duration (PT1H2M3S) to total seconds
    var durationSeconds: Int {
        var totalSeconds = 0
        var currentNumber = ""

        for char in duration {
            if char.isNumber {
                currentNumber += String(char)
            } else if char == "H" {
                totalSeconds += (Int(currentNumber) ?? 0) * 3600
                currentNumber = ""
            } else if char == "M" {
                totalSeconds += (Int(currentNumber) ?? 0) * 60
                currentNumber = ""
            } else if char == "S" {
                totalSeconds += Int(currentNumber) ?? 0
                currentNumber = ""
            }
        }
        return totalSeconds
    }

    /// Duration in minutes (decimal)
    var durationMinutes: Double {
        Double(durationSeconds) / 60.0
    }

    /// Human-readable duration (e.g., "12:34" or "1:02:34")
    var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Words per minute (returns nil if no transcript or zero duration)
    var wordsPerMinute: Int? {
        guard wordCount > 0, durationMinutes > 0 else { return nil }
        return Int((Double(wordCount) / durationMinutes).rounded())
    }

    /// Formatted stats string for template output: "12:34 | 2,450 words | 165 WPM"
    var templateStatsString: String {
        var parts: [String] = [durationFormatted]

        if wordCount > 0 {
            let formattedWords = NumberFormatter.localizedString(from: NSNumber(value: wordCount), number: .decimal)
            parts.append("\(formattedWords) words")

            if let wpm = wordsPerMinute {
                parts.append("\(wpm) WPM")
            }
        }

        return parts.joined(separator: " | ")
    }
}


extension YouTubeVideo {
    /// Calculate if video is evergreen (sustained growth)
    var isEvergreen: Bool {
        guard let history = stats.viewHistory, history.count >= 3 else {
            return false // Need at least 3 snapshots
        }
        
        // Sort by date
        let sorted = history.sorted { $0.date < $1.date }
        
        // Get first and last snapshot
        guard let first = sorted.first, let last = sorted.last else {
            return false
        }
        
        // Calculate days between first and last snapshot
        let daysBetween = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        guard daysBetween > 0 else { return false }
        
        // Calculate total growth
        let totalGrowth = Double(last.viewCount - first.viewCount) / Double(first.viewCount)
        
        // Video is evergreen if it's grown by 5%+ over time
        return totalGrowth >= 0.05
    }
    
    /// Get growth rate percentage
    var growthRate: Double? {
        guard let history = stats.viewHistory, history.count >= 2 else {
            return nil
        }
        
        let sorted = history.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else {
            return nil
        }
        
        let growth = Double(last.viewCount - first.viewCount) / Double(first.viewCount)
        return growth * 100 // Return as percentage
    }
    
    /// Days since last stats update
    var daysSinceLastUpdate: Int? {
        guard let history = stats.viewHistory,
              let lastSnapshot = history.max(by: { $0.date < $1.date }) else {
            return nil
        }
        
        return Calendar.current.dateComponents([.day], from: lastSnapshot.date, to: Date()).day
    }
}


// MARK: - Updated Video Model with Codable Keys
extension YouTubeVideo {
    enum CodingKeys: String, CodingKey {
        case videoId
        case channelId
        case title
        case description
        case publishedAt
        case duration
        case thumbnailUrl
        case stats
        case createdAt
        case scriptBreakdown
        case transcript
        case factsText
        case summaryText
        case notHunting
        case notes
        case videoType
        case hook
        case hookType
        case intro
        // A1a fields
        case videoSummary
        case logicSpine
        case bridgePoints
        case validationStatus
        case validationIssues
        case extractionDate
        case scriptSummary

        // Purpose flags
        case forTaxonomyBuilding
        case forScriptAnalysis
        case forResearchData
        case forIdeaGeneration
        case forThumbnailStudy
        case isPinned

        // Phase 0 / Taxonomy
        case phase0Result
        case assignedTemplateId

        // Rhetorical analysis
        case rhetoricalSequence

        // Donor Library
        case donorLibraryStatus

        // Narrative Spine
        case narrativeSpineStatus

        // Spine-Rhetorical Alignment
        case spineAlignmentStatus
    }

    // Custom decoder to handle optional fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        videoId = try container.decode(String.self, forKey: .videoId)
        channelId = try container.decode(String.self, forKey: .channelId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        duration = try container.decode(String.self, forKey: .duration)
        thumbnailUrl = try container.decode(String.self, forKey: .thumbnailUrl)
        stats = try container.decode(VideoStats.self, forKey: .stats)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        
        // Optional fields
        scriptBreakdown = try container.decodeIfPresent(ScriptBreakdown.self, forKey: .scriptBreakdown)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        factsText = try container.decodeIfPresent(String.self, forKey: .factsText)
        summaryText = try container.decodeIfPresent(String.self, forKey: .summaryText)
        notHunting = try container.decodeIfPresent(Bool.self, forKey: .notHunting) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        videoType = try container.decodeIfPresent(String.self, forKey: .videoType)
        hook = try container.decodeIfPresent(String.self, forKey: .hook)
        hookType = try container.decodeIfPresent(HookType.self, forKey: .hookType)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        
        // A1a fields
        videoSummary = try container.decodeIfPresent(String.self, forKey: .videoSummary)
        logicSpine = try container.decodeIfPresent(LogicSpineData.self, forKey: .logicSpine)
        bridgePoints = try container.decodeIfPresent([BridgePoint].self, forKey: .bridgePoints)
        validationStatus = try container.decodeIfPresent(ValidationStatus.self, forKey: .validationStatus)
        validationIssues = try container.decodeIfPresent([ValidationIssue].self, forKey: .validationIssues)
        extractionDate = try container.decodeIfPresent(Date.self, forKey: .extractionDate)
        
        scriptSummary = try container.decodeIfPresent(ScriptSummary.self, forKey: .scriptSummary)

        // Purpose flags
        forTaxonomyBuilding = try container.decodeIfPresent(Bool.self, forKey: .forTaxonomyBuilding) ?? false
        forScriptAnalysis = try container.decodeIfPresent(Bool.self, forKey: .forScriptAnalysis) ?? false
        forResearchData = try container.decodeIfPresent(Bool.self, forKey: .forResearchData) ?? false
        forIdeaGeneration = try container.decodeIfPresent(Bool.self, forKey: .forIdeaGeneration) ?? false
        forThumbnailStudy = try container.decodeIfPresent(Bool.self, forKey: .forThumbnailStudy) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false

        // Phase 0 / Taxonomy
        phase0Result = try container.decodeIfPresent(Phase0Result.self, forKey: .phase0Result)
        assignedTemplateId = try container.decodeIfPresent(String.self, forKey: .assignedTemplateId)

        // Rhetorical analysis
        rhetoricalSequence = try container.decodeIfPresent(RhetoricalSequence.self, forKey: .rhetoricalSequence)

        // Donor Library
        donorLibraryStatus = try container.decodeIfPresent(DonorLibraryStatus.self, forKey: .donorLibraryStatus)

        // Narrative Spine
        narrativeSpineStatus = try container.decodeIfPresent(NarrativeSpineStatus.self, forKey: .narrativeSpineStatus)

        // Spine-Rhetorical Alignment
        spineAlignmentStatus = try container.decodeIfPresent(SpineAlignmentStatus.self, forKey: .spineAlignmentStatus)
    }
}




enum HookType: String, Codable, CaseIterable {
    case question = "Question"           // "Are you making this mistake?"
    case numberList = "Number/List"      // "5 Biggest Mistakes"
    case story = "Story"                 // "I almost lost everything..."
    case problemSolution = "ProblemSolution"  // "Can't find deer? Try this..."
    case shockSurprise = "Shock"      // "This will blow your mind"
    case beforeAfter = "BeforeAfter"    // "From novice to expert"
    case controversy = "Controversy"     // "Everyone does this wrong"
    case directBenefit = "Direct Benefit" // "Double your success rate"
    case patternInterrupt = "Pattern Interrupt" // Unusual/unexpected opener
    case contrarianSnap = "Contrarian Snap"
    case secretReveal = "Secret Reveal"
    case none = "None"
}

struct VideoStats: Codable, Hashable, Equatable {
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    var viewHistory: [ViewSnapshot]?
}
struct ViewSnapshot: Codable, Hashable, Equatable {
    let date: Date
    let viewCount: Int
    let likeCount: Int
}

// MARK: - API Response Models (for decoding YouTube API)
struct YouTubeChannelResponse: Codable {
    let items: [ChannelItem]
    
    struct ChannelItem: Codable {
        let id: String
        let snippet: Snippet
        let statistics: Statistics
        let contentDetails: ContentDetails
        
        struct Snippet: Codable {
            let title: String
            let customUrl: String?
            let thumbnails: Thumbnails
            let description: String
        }
        
        struct Statistics: Codable {
            let subscriberCount: String?
            let videoCount: String?
        }
        
        struct ContentDetails: Codable {
            let relatedPlaylists: RelatedPlaylists
            
            struct RelatedPlaylists: Codable {
                let uploads: String
            }
        }
    }
}

struct YouTubePlaylistResponse: Codable {
    let items: [PlaylistItem]
    let nextPageToken: String?
    
    struct PlaylistItem: Codable {
        let contentDetails: ContentDetails
        
        struct ContentDetails: Codable {
            let videoId: String
        }
    }
}

struct YouTubeVideosResponse: Codable {
    let items: [VideoItem]
    
    struct VideoItem: Codable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
        let statistics: Statistics
        
        struct Snippet: Codable {
            let channelId: String
            let title: String
            let description: String
            let publishedAt: String
            let thumbnails: Thumbnails
        }
        
        struct ContentDetails: Codable {
            let duration: String?
        }
        
        struct Statistics: Codable {
            let viewCount: String?
            let likeCount: String?
            let commentCount: String?
        }
    }
}

struct Thumbnails: Codable {
    let high: Thumbnail
    
    struct Thumbnail: Codable {
        let url: String
    }
}


// MARK: - ScriptSummary (nested on YouTubeVideo)

struct ScriptSummary: Codable, Hashable, Equatable {
    // Structure (from A1a)
    var sectionSequence: [String]
    var turnPosition: Double
    var sectionCount: Int
    var totalBeats: Int
    
    // Beat distribution (from A1b)
    var beatDistribution: [String: Int]
    var beatDistributionBySection: [String: [String: Int]]
    
    // Voice metrics (from A1b)
    var stanceCounts: [String: Int]
    var tempoCounts: [String: Int]
    var avgFormality: Double
    var avgSentenceLength: Double
    var questionCount: Int
    
    // Anchors - parallel arrays
    var anchorTexts: [String]
    var anchorFunctions: [String]
    var anchorSectionRoles: [String]
    
    var computedAt: Date
}
