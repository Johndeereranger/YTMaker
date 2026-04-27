//
//  BeatDoc.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//

//
//// MARK: - BeatDoc Model (Full A1c Output)
//struct BeatDoc: Codable, Identifiable, Hashable, Equatable {
//    // Identity
//    let beatId: String
//    let type: String
//    let beatRole: String
//    
//    // Content
//    let text: String
//    
//    // Text Anchoring
//    let sentenceIndexScope: String
//    let sentenceStartIndex: Int
//    let sentenceEndIndex: Int
//    let startWordIndex: Int
//    let endWordIndex: Int
//    let wordCount: Int
//    let startCharIndex: Int
//    let endCharIndex: Int
//    
//    // Compiler
//    let compilerFunction: String
//    let compilerWhyNow: String
//    let compilerSetsUp: String?
//    let compilerEvidenceKind: String
//    let compilerEvidenceText: String?
//    
//    // Core Keys
//    let moveKey: String
//    
//    // Proof
//    let proofMode: String
//    let proofDensity: String
//    
//    // Mechanics
//    let tempo: String
//    let stance: String
//    let sentenceCount: Int
//    let avgSentenceLength: Int
//    let sentenceLengthVariance: Int
//    let questionCount: Int
//    let teaseDistance: Int?
//    let personalVoice: Bool
//    let informationDensity: String
//    let cognitiveLoad: String
//    let rhetoricalDeviceLabels: [String]
//    let questionRhetorical: Int
//    let questionGenuine: Int
//    let questionOpen: Int
//    let questionSelfAnswer: Int
//    
//    // Topic/Style
//    let topicPrimary: String
//    let topicSecondary: [String]
//    let topicSpecificity: String
//    let styleFormality: Int
//    let styleVocabularyLevel: Int
//    let styleHumor: String
//    
//    // Quality
//    let qualityLevel: String
//    let anchorStrength: Int
//    let reusabilityLevel: String
//    let qualityReasoning: String
//    let humanValidatedBy: String?
//    let humanValidatedAt: String?
//    
//    // Promise/Payoff
//    let promiseType: String?
//    let payoffType: String?
//    let requiresPayoffWithinBeats: Int?
//    let promiseStrength: String?
//    
//    // Voice
//    let voiceMoves: [String]
//    let customVoiceMoves: [String]
//    let customAntiPatternsAvoided: [String]
//    let customRhetoricalTags: [String]
//    
//    // Anchors
//    let anchorIds: [String]
//    
//    // Edges
//    let setsUpBeatIds: [String]
//    let paysOffBeatIds: [String]
//    let callsBackToBeatIds: [String]
//    let referencesBeatIds: [String]
//    
//    // Dependencies
//    let semanticConstraints: [String]
//    let mustIntroduce: String?
//    let requiresContext: [String]
//    
//    // Transition
//    let transitionType: String
//    let transitionExpectation: String?
//    let transitionBridgeType: String?
//    let forwardPromiseBeatId: String?
//    let forwardPromiseWillDeliver: String?
//    let forwardPromiseType: String?
//    
//    // Template
//    let templatePattern: String?
//    let templateSlots: [String]?
//    let templateApplicableTo: [String]?
//    let templateRequiresSpecificity: Bool?
//    let templateRequiresTimestamp: Bool?
//    let templateRequiresNamedEntity: Bool?
//    let templateExampleTopic: String?
//    let templateExampleResult: String?
//    let reusabilityScore: Int?
//    let reusableBecause: [String]?
//    
//    // Position
//    let orderIndex: Int
//    let beatIndexInSection: Int
//    let sectionRole: String
//    let globalBeatIndex: Int
//    let totalBeatsInSection: Int
//    let totalBeatsInScript: Int
//    
//    // Emotion/Audio
//    let emotionArcPosition: String
//    let emotionTargetFeelings: [String]
//    let emotionAudienceState: String
//    let emotionDevice: String
//    let emotionValence: Int
//    let emotionArousal: Int
//    let emotionIntensity: Int
//    let emotionTrajectory: String
//    let musicBrief: String
//    let musicInstrumentation: [String]
//    let musicTempoRange: String
//    let musicMood: String
//    let musicDynamicRange: String
//    
//    // Argument
//    let argumentPolarity: String
//    let argumentResolutionStyle: String
//    let argumentMove: String
//    let argumentEvidenceStrategy: String
//    
//    // Anti-patterns
//    let antiPatternsAvoided: [String]
//    let styleAvoidances: [String]
//    
//    // Claims
//    let hasFactualClaims: Bool
//    let hasNumbers: Bool
//    let hasQuotes: Bool
//    let hasHistoricalReferences: Bool
//    let claimRisk: String
//    let claimKinds: [String]
//    let requiresHedge: Bool
//    let specificityLevel: String
//    
//    // Narrative
//    let narrativeTechniques: [String]
//    
//    // Voice Metrics
//    let pronounFrequency: Int
//    let directAddress: Bool
//    let casualMarkers: [String]
//    let toneIndicators: [String]
//    
//    // Embeddings
//    let mechanicsDescription: String
//    let topicDescription: String
//    let embeddingModel: String
//    let embeddedAt: String?
//    let vectorId: String?
//    let mechanicsHash: String
//    let templateHash: String?
//    
//    // Metadata
//    let extractedAt: String
//    let extractedBy: String
//    let extractorVersion: String
//    let sourceScriptId: String
//    let parseConfidence: Double
//    let manualReviewRequired: Bool
//    let reviewNotes: String?
//    
//    var id: String { beatId }
//    
//    // MARK: - Hashable & Equatable
//    
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(beatId)
//    }
//    
//    static func == (lhs: BeatDoc, rhs: BeatDoc) -> Bool {
//        lhs.beatId == rhs.beatId
//    }
//}

struct BeatDoc: Codable, Identifiable, Hashable, Equatable {
    
    // MARK: - IDENTITY & ORIGIN
    let beatId: String              // UUID (primary key)
    let beatKey: String             // "section_1_hook_b1" (human-readable)
    let sectionId: String           // UUID (foreign key to section)
    let sectionKey: String          // "sect_1" (human-readable)
    let sourceVideoId: String       // YouTube video ID
    let sourceChannelId: String     // Channel ID
    let type: String                // TEASE, QUESTION, PROMISE, DATA, etc.
    let beatRole: String            // "primary_tease", "supporting_context", etc.
    
    var id: String { beatId }
    
    // MARK: - CONTENT
    let text: String                // Full beat text
    
    // MARK: - TEXT ANCHORING
    let sentenceIndexScope: String  // "transcript"
    let sentenceStartIndex: Int
    let sentenceEndIndex: Int
    let startWordIndex: Int
    let endWordIndex: Int
    let wordCount: Int
    let startCharIndex: Int
    let endCharIndex: Int
    
    // MARK: - COMPILER / EXTRACTION INTENT
    let compilerFunction: String         // What this beat does mechanically
    let compilerWhyNow: String          // Why this beat appears HERE
    let compilerSetsUp: String          // What next beat must deliver (empty if last)
    let compilerEvidenceKind: String    // "clip"|"stat"|"quote"|"none"
    let compilerEvidenceText: String    // Description of evidence if present (empty if none)
    
    // MARK: - CORE RETRIEVAL
    let moveKey: String                 // "HOOK_TEASE_CLIP_EXCITEMENT_CULTURAL_ACKNOWLEDGMENT_PROMISE"
    let mechanicsTags: [String]         // ["section:hook", "beat:tease", "tempo:fast", "stance:playful"]
    let retrievalPriority: String       // "high"|"medium"|"low"
    
    // MARK: - PROOF
    let proofMode: String               // "none"|"stat"|"anecdote"|"authority_quote"|"demo"|"conceptual"|"logic"
    let proofDensity: String            // "none"|"light"|"heavy"
    
    // MARK: - MECHANICS
    let tempo: String                   // "fast"|"medium"|"slow"
    let stance: String                  // "neutral"|"adversarial"|"empathetic"|"playful"|"skeptical"|"authoritative"
    let sentenceCount: Int
    let avgSentenceLength: Double
    let sentenceLengthVariance: Double
    let questionCount: Int
    let teaseDistance: Int              // Sentences to payoff (0 if not a tease)
    let personalVoice: Bool
    let informationDensity: String      // "low"|"moderate"|"high"|"very_high"
    let cognitiveLoad: String           // "low"|"moderate"|"high"|"very_high"
    
    // Enhanced Mechanics (defaults to "none" if not applicable)
    let sentenceRhythm: String          // "staccato"|"varied"|"flowing"|"building"|"none"
    let emotionalDirection: String      // "escalating"|"de-escalating"|"flat"|"oscillating"|"none"
    let questionPlacement: String       // "opening"|"middle"|"closing"|"none"
    let promiseExplicit: Bool           // true = "I'll show you...", false = implicit or no promise
    
    // Specificity
    let namedEntities: [String]         // ["Max Verstappen", "F1"] (empty if none)
    let temporalAnchors: [String]       // ["2004", "last week", "three years ago"] - TIME references (empty if none)
    let quantitativeAnchors: [String]   // ["66 laps", "$5 million", "23%"] - NUMBERS/quantities (empty if none)
    
    // Contrast
    let contrastPresent: Bool           // Does this beat use contrast?
    let contrastType: String            // "before_after"|"common_vs_correct"|"obvious_vs_hidden"|"none"
    
    // MARK: - RHETORICAL DEVICES
    let rhetoricalDeviceLabels: [String]
    let questionRhetorical: Int
    let questionGenuine: Int
    let questionOpen: Int
    let questionSelfAnswer: Int
    
    // MARK: - TOPIC
    let topicPrimary: String
    let topicSecondary: [String]
    let topicSpecificity: String        // "case_example"|"general_principle"|"technical_detail"
    
    // Topic Depth
    let topicAbstraction: String        // "concrete_case"|"general_principle"|"abstract_concept"|"none"
    let domainSpecificity: String       // "highly_specific"|"somewhat_specific"|"broadly_applicable"|"universal"
    let topicAccessibility: String      // "expert_only"|"informed_audience"|"general_audience"|"universal"
    let subjectCategories: [String]     // ["sports", "entertainment", "technology"]
    let crossDomainApplicability: [String] // Other domains this could work in
    
    // MARK: - STYLE
    let styleFormality: Int             // 1-10 scale
    let styleVocabularyLevel: Int       // 1-10 scale
    let styleHumor: String              // "none"|"playful"|"sarcastic"|"dry"|"absurdist"
    
    // Voice Details
    let pronounUsage: String            // "first_person"|"second_person"|"third_person"|"mixed"|"impersonal"
    let casualMarkers: [String]         // ["Cool", "Let's", "right?"] (empty if none)
    let contractions: String            // "frequent"|"moderate"|"rare"|"none"
    let humorDensity: String            // "none"|"light"|"moderate"|"heavy"
    let profanity: Bool
    let profanityType: String           // "mild"|"moderate"|"strong"|"none"
    
    // MARK: - QUALITY & REUSABILITY
    let qualityLevel: String            // "canonical"|"high"|"medium"|"skip"
    let anchorStrength: Int             // 0-5 (0 if no anchor)
    let reusabilityLevel: String        // "high"|"medium"|"low"
    let qualityReasoning: String        // Why this quality rating
    let reusabilityScore: Int           // 0-10
    
    // Reusability Details (DESCRIPTIVE not prescriptive)
    let adaptationDifficulty: String    // "trivial"|"easy"|"moderate"|"hard"|"not_reusable"
    let crossTopicViability: [String]   // Topics this pattern COULD work for
    let usageFrequency: String          // "frequent"|"moderate"|"rare"|"one_time"
    let cooldownRecommendation: Int     // Scripts between reuse (0 if no recommendation)
    let overuseRisk: String             // "high"|"medium"|"low"|"none"
    let contextDependency: String       // "independent"|"lightly_dependent"|"heavily_dependent"|"context_bound"
    let frequencyClass: String          // "rare_pattern"|"uncommon_pattern"|"common_pattern"|"overused_pattern"|"unknown"
    
    // Human Validation
    let humanValidatedBy: String        // userID (empty if not validated)
    let humanValidatedAt: String        // ISO timestamp (empty if not validated)
    
    // MARK: - PROMISE/PAYOFF
    let promiseType: String             // "accessible_explanation"|"outcome"|"explanation"|"insight"|"none"
    let payoffType: String
    let requiresPayoffWithinBeats: Int  // 0 if no payoff required
    let promiseStrength: String         // "weak"|"moderate"|"strong"|"none"
    
    // MARK: - VOICE MOVES
    let voiceMoves: [String]            // Identified moves
    let customVoiceMoves: [String]      // Creator-specific moves
    let customRhetoricalTags: [String]  // Custom tags
    
    // MARK: - ANCHORS
    let anchorIds: [String]             // UUIDs of anchor docs (empty if no anchors)
    let containsAnchor: Bool
    let anchorText: String              // The actual phrase (empty if containsAnchor = false)
    let anchorFunction: String          // "opener"|"proofFrame"|"pivot"|"turn"|"none"
    let anchorIsReusable: Bool
    let anchorFamily: String            // "curiosityOpeners"|"proofFrames"|"turns"|"none"
    
    // MARK: - BEAT RELATIONSHIPS (ALL UUIDs)
    let setsUpBeatIds: [String]         // UUIDs (empty if none)
    let paysOffBeatIds: [String]        // UUIDs (empty if none)
    let callsBackToBeatIds: [String]    // UUIDs (empty if none)
    let referencesBeatIds: [String]     // UUIDs (empty if none)
    let similarMoveKeys: [String]       // Similar patterns (empty until computed)
    
    // MARK: - SEMANTIC CONSTRAINTS
    let semanticConstraints: [String]   // Must-deliver items
    let mustIntroduce: String           // What concept must be introduced (empty if none)
    let requiresContext: [String]       // What context is needed
    
    // MARK: - TRANSITIONS
    let transitionType: String
    let transitionExpectation: String
    let transitionBridgeType: String
    let forwardPromiseBeatId: String    // UUID (empty if none)
    let forwardPromiseWillDeliver: String
    let forwardPromiseType: String
    
    // MARK: - TEMPLATE
    let templatePattern: String         // Empty if not a template
    let templateSlots: [String]         // Empty if not a template
    let templateApplicableTo: [String]  // Empty if not a template
    let templateRequiresSpecificity: Bool
    let templateRequiresTimestamp: Bool
    let templateRequiresNamedEntity: Bool
    let templateExampleTopic: String    // Empty if not a template
    let templateExampleResult: String   // Empty if not a template
    let templateViability: String       // "high"|"medium"|"low"|"none"
    
    // MARK: - POSITION METADATA
    let orderIndex: Int                 // Order in section
    let beatIndexInSection: Int
    let sectionRole: String             // HOOK, SETUP, EVIDENCE, TURN, PAYOFF
    let globalBeatIndex: Int
    let totalBeatsInSection: Int
    let totalBeatsInScript: Int
    
    // MARK: - EMOTION
    let emotionArcPosition: String
    let emotionTargetFeelings: [String]
    let emotionAudienceState: String
    let emotionDevice: String
    let emotionValence: Int             // -2 to +2
    let emotionArousal: Int             // 0-4
    let emotionIntensity: Int           // 0-4
    let emotionTrajectory: String       // "rising"|"falling"|"stable"
    
    // MARK: - MUSIC BRIEF
    let musicBrief: String              // Empty if unknown
    let musicInstrumentation: [String]  // Empty if unknown
    let musicTempoRange: String         // Empty if unknown
    let musicMood: String               // Empty if unknown
    let musicDynamicRange: String       // Empty if unknown
    
    // MARK: - ARGUMENT STRUCTURE
    let argumentPolarity: String        // "neutral"|"for"|"against"
    let argumentResolutionStyle: String
    let argumentMove: String
    let argumentEvidenceStrategy: String
    let logicalFlow: String             // "linear"|"circular"|"branching"|"inverted"
    let argumentStructure: String       // "claim_evidence"|"problem_solution"|"question_answer"
    
    // MARK: - FACTUAL CLAIMS
    let hasFactualClaims: Bool
    let hasNumbers: Bool
    let hasQuotes: Bool
    let hasHistoricalReferences: Bool
    let claimRisk: String               // "low"|"medium"|"high"
    let claimKinds: [String]
    let requiresHedge: Bool
    let specificityLevel: String
    
    // MARK: - RHETORICAL DETAIL
    let rhetoricalDetail_foreshadowing_usage: String
    let rhetoricalDetail_foreshadowing_example: String
    let rhetoricalDetail_specificity_usage: String
    let rhetoricalDetail_specificity_example: String
    
    // MARK: - NARRATIVE
    let narrativeTechniques: [String]
    
    // MARK: - VOICE METRICS
    let pronounFrequency: Int           // Per 100 words
    let directAddress: Bool
    let toneIndicators: [String]        // ["neutral", "authoritative", "conversational"]
    
    // MARK: - PROSE DESCRIPTIONS (Human-Readable)
    let mechanicsDescription: String    // 200-300 words explaining HOW this beat works mechanically
    let topicDescription: String        // 100-150 words explaining WHAT this beat is about
    
    // MARK: - WRITER GUIDANCE (DESCRIPTIVE not prescriptive)
    let writerHints: [String]           // ["good_for_HOOK", "strong_opener", "best_used_early"]
    let avoidContexts: [String]         // ["formal_presentation", "children_audience"]
    
    // MARK: - PERFORMANCE SIGNALS (defaults to 0 until measured)
    let performanceRetentionAtBeat: Double      // % who stayed (0.0 if unknown)
    let performanceEngagementLift: String       // "high"|"medium"|"low"|"unknown"
    let performanceConfidence: Double           // 0.0-1.0 (0.0 if unknown)
    
    // MARK: - EXTRACTION METADATA
    let extractedAt: String             // ISO timestamp
    let extractedBy: String             // "A1c_beat_doc_extractor"
    let extractorVersion: String        // "2.0"
    let parseConfidence: Double         // 0.0-1.0
    let manualReviewRequired: Bool
    let reviewNotes: String             // Empty if no notes
    
    // MARK: - Equatable Conformance
    static func == (lhs: BeatDoc, rhs: BeatDoc) -> Bool {
        lhs.beatId == rhs.beatId
    }
    
    // MARK: - Hashable Conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(beatId)
    }
}


extension BeatDoc {
    var enrichmentLevel: String {
        // If moveKey is empty or default, it's only A1b
        if moveKey.isEmpty || moveKey == "UNKNOWN" {
            return "a1b"
        }
        // If quality fields are populated, it's A1c
        if !qualityLevel.isEmpty && qualityLevel != "unknown" {
            return "a1c"
        }
        return "a1b"
    }
}
