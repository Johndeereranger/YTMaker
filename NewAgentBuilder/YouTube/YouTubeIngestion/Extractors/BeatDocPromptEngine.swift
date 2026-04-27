//
//  BeatDocPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//

import Foundation

// A1c: Beat Doc Engine v2.2 (Complete 112-field extraction)
struct BeatDocPromptEngine {
    let video: YouTubeVideo
    let beat: SimpleBeat
    let section: SectionData
    let allBeatsInSection: [SimpleBeat]
    
    func generatePrompt() -> String {
        guard let transcript = video.transcript else {
            return "⚠️ No transcript available"
        }
        
        // Find beat position in section
        let beatIndex = allBeatsInSection.firstIndex(where: { $0.beatId == beat.beatId }) ?? 0
        let isFirstBeat = beatIndex == 0
        let isLastBeat = beatIndex == allBeatsInSection.count - 1
        let previousBeat = isFirstBeat ? nil : allBeatsInSection[beatIndex - 1]
        let nextBeat = isLastBeat ? nil : allBeatsInSection[beatIndex + 1]
        
        return """
You are performing detailed mechanical extraction on a single beat from a YouTube script.
This is BeatDoc Model v2.2 with 112 fields.

BEAT CONTEXT:
Beat ID: \(beat.beatId)
Type: \(beat.type)
Position: Beat \(beatIndex + 1) of \(allBeatsInSection.count) in \(section.role) section
Is First Beat: \(isFirstBeat)
Is Last Beat: \(isLastBeat)

SECTION CONTEXT:
Section ID: \(section.id)
Section Role: \(section.role)
Section Goal: \(section.goal)
Logic Spine Step: \(section.logicSpineStep)

VIDEO CONTEXT:
Video ID: \(video.videoId)
Channel ID: \(video.channelId ?? "unknown")

BEAT TEXT (from A1b):
\(beat.text)

WORD POSITION (from A1b):
Start: word \(beat.startWordIndex)
End: word \(beat.endWordIndex)
Word span: \(beat.endWordIndex - beat.startWordIndex) words

ADJACENT BEATS:
Previous Beat: \(previousBeat?.beatId ?? "none") - \(previousBeat?.type ?? "N/A")
Next Beat: \(nextBeat?.beatId ?? "none") - \(nextBeat?.type ?? "N/A")

FULL TRANSCRIPT (for context):
\(transcript)

---

TASK: Extract complete mechanical fingerprint for this beat using BeatDoc v2.2 schema (112 fields).

OUTPUT FORMAT: Flat JSON with ALL fields (no nested objects except arrays).

{
  /* =========================
     IDENTITY & ORIGIN
     ========================= */
  "beatId": "\(beat.beatId)",
  "beatKey": "section_1_hook_b1",
  "sectionId": "\(section.id)",
  "sectionKey": "sect_1",
  "sourceVideoId": "\(video.videoId)",
  "sourceChannelId": "\(video.channelId ?? "unknown")",
  "type": "\(beat.type)",
  "beatRole": "primary_tease|supporting_context|evidence_drop|reframe|escalation|resolution_note",
  
  /* =========================
     CONTENT
     ========================= */
  "text": "EXACT text from beat...",
  
  /* =========================
     TEXT ANCHORING
     ========================= */
  "sentenceIndexScope": "transcript",
  "sentenceStartIndex": 0,
  "sentenceEndIndex": 1,
  "startWordIndex": \(beat.startWordIndex),
  "endWordIndex": \(beat.endWordIndex),
  "wordCount": 0,
  "startCharIndex": 0,
  "endCharIndex": 267,
  
  /* =========================
     COMPILER / EXTRACTION INTENT
     ========================= */
  "compilerFunction": "Detailed mechanical description of what this beat does...",
  "compilerWhyNow": "Why this beat appears HERE in the section...",
  "compilerSetsUp": "What the NEXT beat must deliver (empty string if last beat)",
  "compilerEvidenceKind": "clip|stat|quote|none",
  "compilerEvidenceText": "Description of evidence if present (empty string if none)",
  
  /* =========================
     CORE RETRIEVAL
     ========================= */
  "moveKey": "HOOK_TEASE_CLIP_EXCITEMENT_CULTURAL_ACKNOWLEDGMENT_PROMISE",
  "mechanicsTags": ["section:hook", "beat:tease", "tempo:fast", "stance:playful"],
  "retrievalPriority": "high|medium|low",
  
  /* =========================
     PROOF
     ========================= */
  "proofMode": "none|stat|anecdote|authority_quote|demo|conceptual|logic",
  "proofDensity": "none|light|heavy",
  
  /* =========================
     MECHANICS (CORE)
     ========================= */
  "tempo": "fast|medium|slow",
  "stance": "neutral|adversarial|empathetic|playful|skeptical|authoritative",
  "sentenceCount": 2,
  "avgSentenceLength": 17.5,
  "sentenceLengthVariance": 2.5,
  "questionCount": 0,
  "teaseDistance": 8,
  "personalVoice": true,
  "informationDensity": "low|moderate|high|very_high",
  "cognitiveLoad": "low|moderate|high|very_high",
  
  /* =========================
     ENHANCED MECHANICS
     ========================= */
  "sentenceRhythm": "staccato|varied|flowing|building|none",
  "emotionalDirection": "escalating|de-escalating|flat|oscillating|none",
  "questionPlacement": "opening|middle|closing|none",
  "promiseExplicit": true,
  
  /* =========================
     SPECIFICITY
     ========================= */
  "namedEntities": ["Max Verstappen", "F1"],
  "temporalAnchors": ["2004", "last week"],
  "quantitativeAnchors": ["66 laps", "$5 million"],
  
  /* =========================
     CONTRAST
     ========================= */
  "contrastPresent": true,
  "contrastType": "before_after|common_vs_correct|obvious_vs_hidden|none",
  
  /* =========================
     RHETORICAL DEVICES
     ========================= */
  "rhetoricalDeviceLabels": ["foreshadowing", "specificity"],
  "questionRhetorical": 0,
  "questionGenuine": 0,
  "questionOpen": 0,
  "questionSelfAnswer": 0,
  
  /* =========================
     TOPIC (CORE)
     ========================= */
  "topicPrimary": "controversial_referee_call",
  "topicSecondary": ["sports_technology_adoption", "tennis_officiating"],
  "topicSpecificity": "case_example|general_principle|technical_detail",
  
  /* =========================
     TOPIC DEPTH
     ========================= */
  "topicAbstraction": "concrete_case|general_principle|abstract_concept|none",
  "domainSpecificity": "highly_specific|somewhat_specific|broadly_applicable|universal",
  "topicAccessibility": "expert_only|informed_audience|general_audience|universal",
  "subjectCategories": ["sports", "technology"],
  "crossDomainApplicability": ["business_innovation", "policy_change"],
  
  /* =========================
     STYLE (CORE)
     ========================= */
  "styleFormality": 3,
  "styleVocabularyLevel": 5,
  "styleHumor": "none|playful|sarcastic|dry|absurdist",
  
  /* =========================
     VOICE DETAILS
     ========================= */
  "pronounUsage": "first_person|second_person|third_person|mixed|impersonal",
  "casualMarkers": ["Cool", "Let's", "right?"],
  "contractions": "frequent|moderate|rare|none", /* this is the FREQUENCY of the contractions not a list*/
  "humorDensity": "none|light|moderate|heavy",
  "profanity": false,
  "profanityType": "mild|moderate|strong|none",
  
  /* =========================
     QUALITY & REUSABILITY
     ========================= */
  "qualityLevel": "canonical|high|medium|skip",
  "anchorStrength": 4,
  "reusabilityLevel": "high|medium|low",
  "qualityReasoning": "Why this beat is canonical/high/medium/skip...",
  "reusabilityScore": 8,
  
  /* =========================
     REUSABILITY DETAILS
     ========================= */
  "adaptationDifficulty": "trivial|easy|moderate|hard|not_reusable",
  "crossTopicViability": ["tech_launches", "policy_changes"],
  "usageFrequency": "frequent|moderate|rare|one_time",
  "cooldownRecommendation": 3,
  "overuseRisk": "high|medium|low|none",
  "contextDependency": "independent|lightly_dependent|heavily_dependent|context_bound",
  "frequencyClass": "rare_pattern|uncommon_pattern|common_pattern|overused_pattern|unknown",
  
  /* =========================
     HUMAN VALIDATION
     ========================= */
  "humanValidatedBy": "",
  "humanValidatedAt": "",
  
  /* =========================
     PROMISE/PAYOFF
     ========================= */
  "promiseType": "accessible_explanation|outcome|explanation|insight|none",
  "payoffType": "clip|explanation|stat|quote|example|demonstration|logic|none",
  "requiresPayoffWithinBeats": 1,
  "promiseStrength": "weak|moderate|strong|none",
  
  /* =========================
     VOICE MOVES
     ========================= */
  "voiceMoves": ["temporal_anchor_opener", "transformation_promise"],
  "customVoiceMoves": [],
  "customRhetoricalTags": [],
  
  /* =========================
     ANCHORS
     ========================= */
  "anchorIds": [],
  "containsAnchor": false,
  "anchorText": "",
  "anchorFunction": "opener|proofFrame|pivot|turn|none",
  "anchorIsReusable": false,
  "anchorFamily": "curiosityOpeners|proofFrames|turns|none",
  
  /* =========================
     BEAT RELATIONSHIPS (ALL UUIDs)
     ========================= */
  "setsUpBeatIds": ["\(nextBeat?.beatId ?? "")"],
  "paysOffBeatIds": [],
  "callsBackToBeatIds": [],
  "referencesBeatIds": [],
  "similarMoveKeys": [],
  
  /* =========================
     SEMANTIC CONSTRAINTS
     ========================= */
  "semanticConstraints": ["must_deliver_controversial_call"],
  "mustIntroduce": "automation_vs_human_tension",
  "requiresContext": [],
  
  /* =========================
     TRANSITIONS
     ========================= */
  "transitionType": "none|callback|direct_pivot|contrarian_flip|question_bridge|summary_bridge",
  "transitionExpectation": "immediate_payoff|delayed_answer|thorough_exploration",
  "transitionBridgeType": "explicit|implicit|none",
  "forwardPromiseBeatId": "\(nextBeat?.beatId ?? "")",
  "forwardPromiseWillDeliver": "controversial_call_evidence",
  "forwardPromiseType": "immediate_payoff|delayed_answer|thematic_resolution",
  
  /* =========================
     TEMPLATE
     ========================= */
  "templatePattern": "",
  "templateSlots": [],
  "templateApplicableTo": [],
  "templateRequiresSpecificity": false,
  "templateRequiresTimestamp": false,
  "templateRequiresNamedEntity": false,
  "templateExampleTopic": "",
  "templateExampleResult": "",
  "templateViability": "high|medium|low|none",
  
  /* =========================
     POSITION METADATA
     ========================= */
  "orderIndex": \(beatIndex),
  "beatIndexInSection": \(beatIndex + 1),
  "sectionRole": "\(section.role)",
  "globalBeatIndex": 0,
  "totalBeatsInSection": \(allBeatsInSection.count),
  "totalBeatsInScript": 0,
  
  /* =========================
     EMOTION
     ========================= */
  "emotionArcPosition": "rising_tension|calm_setup|shock_peak|conflict_peak|relief_release|resolution_warm|awe_expand|hope_uplift",
  "emotionTargetFeelings": ["curiosity", "anticipation"],
  "emotionAudienceState": "curious|uninformed|engaged|skeptical|convinced|conflicted|satisfied",
  "emotionDevice": "curiosity_gap|dramatic_reveal|moral_stakes|personal_vulnerability|contrast|surprise",
  "emotionValence": 0,
  "emotionArousal": 3,
  "emotionIntensity": 3,
  "emotionTrajectory": "rising|falling|stable",
  
  /* =========================
     MUSIC BRIEF
     ========================= */
  "musicBrief": "",
  "musicInstrumentation": [],
  "musicTempoRange": "",
  "musicMood": "",
  "musicDynamicRange": "",
  
  /* =========================
     ARGUMENT STRUCTURE
     ========================= */
  "argumentPolarity": "neutral|for|against",
  "argumentResolutionStyle": "setup|one_sided|acknowledge_both_sides|synthesis|unresolved",
  "argumentMove": "establish_premise|challenge_assumption|provide_evidence|shift_frame|resolve_tension",
  "argumentEvidenceStrategy": "none|case_example|statistic|authority|demonstration|logic|anecdote",
  "logicalFlow": "linear|circular|branching|inverted",
  "argumentStructure": "claim_evidence|problem_solution|question_answer",
  
  /* =========================
     FACTUAL CLAIMS
     ========================= */
  "hasFactualClaims": true,
  "hasNumbers": true,
  "hasQuotes": false,
  "hasHistoricalReferences": true,
  "claimRisk": "low|medium|high",
  "claimKinds": ["historical_event", "specific_date"],
  "requiresHedge": false,
  "specificityLevel": "vague|moderate|high|very_high",
  
  /* =========================
     RHETORICAL DETAIL
     ========================= */
  "rhetoricalDetail_foreshadowing_usage": "none|light|heavy",
  "rhetoricalDetail_foreshadowing_example": "changed a sport forever",
  "rhetoricalDetail_specificity_usage": "none|light|heavy",
  "rhetoricalDetail_specificity_example": "2004, Serena Williams...",
  
  /* =========================
     NARRATIVE
     ========================= */
  "narrativeTechniques": ["temporal_anchor", "named_entities", "outcome_foreshadowing"],
  
  /* =========================
     VOICE METRICS
     ========================= */
  "pronounFrequency": 0,
  "directAddress": false,
  "toneIndicators": ["neutral", "authoritative"],
  
  /* =========================
     PROSE DESCRIPTIONS
     ========================= */
  "mechanicsDescription": "200-300 word explanation of HOW this beat works mechanically...",
  "topicDescription": "100-150 word explanation of WHAT this beat is about...",
  
  /* =========================
     WRITER GUIDANCE (DESCRIPTIVE)
     ========================= */
  "writerHints": ["good_for_HOOK", "strong_opener", "best_used_early"],
  "avoidContexts": ["formal_presentation", "children_audience"],
  
  /* =========================
     PERFORMANCE SIGNALS
     ========================= */
  "performanceRetentionAtBeat": 0.0,
  "performanceEngagementLift": "unknown",
  "performanceConfidence": 0.0,
  
  /* =========================
     EXTRACTION METADATA
     ========================= */
  "extractedAt": "\(ISO8601DateFormatter().string(from: Date()))",
  "extractedBy": "A1c_beat_doc_extractor",
  "extractorVersion": "2.2",
  "parseConfidence": 0.95,
  "manualReviewRequired": false,
  "reviewNotes": ""
}

MOVEKEY CONSTRUCTION:
Format: {SECTION}_{TYPE}_{KEY_CHARACTERISTIC}_{DELIVERY}
Examples:
- HOOK_TEASE_CLIP_EXCITEMENT_CULTURAL_ACKNOWLEDGMENT_PROMISE
- HOOK_TEASE_HISTORICAL_CASE_PROMISE
- EVIDENCE_DATA_STAT_HEAVY
- TURN_FALSE_EXPLANATION_DISMISSAL
- TURN_MORAL_OBJECTION_DIRECT_ADDRESS
- PAYOFF_WORLD_MODELING_REFRAME

MECHANICS TAGS CONSTRUCTION:
Always include: ["section:{role}", "beat:{type}", "tempo:{tempo}", "stance:{stance}"]
Add as applicable: "proof:{mode}", "promise:{type}", "anchor:present", "contrast:present"

CRITICAL REQUIREMENTS:
1. ALL 112 fields must be present (use empty string "" for optional strings, [] for arrays, 0 for numbers, false for bools)
2. ANALYZE the beat text to determine all mechanical fields
3. Calculate sentenceCount by counting sentences in beat text
4. Calculate wordCount by counting words in beat text
5. Calculate avgSentenceLength and sentenceLengthVariance from actual sentences
6. Determine beatRole based on function this beat serves
7. Calculate character indexes by counting from start of transcript
8. moveKey must be specific and descriptive
9. mechanicsTags must include at minimum: section, beat type, tempo, stance
10. emotionValence: -2 (very negative) to +2 (very positive)
11. emotionArousal/Intensity: 0-4 scale
12. styleFormality/vocabularyLevel: 1-10 scale
13. Return ONLY the raw JSON object - your response must start with { and end with } - no preamble text, no explanation, no markdown code blocks, no ```json fences
14. Use EXACT text from beat for text field
15. Empty arrays [] not null for array fields
16. Empty strings "" not null for optional string fields
17. namedEntities: Proper nouns ONLY (people, places, brands)
18. temporalAnchors: Time references ONLY (dates, "last week", etc)
19. quantitativeAnchors: Numbers and quantities ONLY ("$5M", "23%", etc)

VALIDATION CHECKLIST:
□ All 112 fields present
□ No null values (use "", [], 0, false as appropriate)
□ moveKey follows naming convention
□ mechanicsTags includes minimum 4 tags
□ Edge beatIds reference real beats
□ Emotion scores within valid ranges
□ Text matches original beat text exactly
□ Sentence/word counts calculated from beat text
□ Character indexes calculated from full transcript
□ namedEntities contains ONLY proper nouns
□ temporalAnchors contains ONLY time references
□ quantitativeAnchors contains ONLY numbers
"""
    }
    
    func parseResponse(_ jsonString: String) throws -> BeatDocResponse {
        print("\n")
        print("========================================")
        print("📄 BEATDOC v2.2 JSON PARSING (112 FIELDS)")
        print("========================================")
        
        print("\n📥 RAW BEATDOC JSON RESPONSE:")
        print("Length: \(jsonString.count) characters")
        print("\(String(jsonString))")
       
        
        // Clean JSON
        var cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("\n🧹 CLEANING BEATDOC JSON...")
        
        if cleanJSON.hasPrefix("```json") {
            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ Removed markdown fences")
        }
        
        // Replace smart quotes with straight quotes
        cleanJSON = cleanJSON
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // '
            .replacingOccurrences(of: "…", with: "...")
        print("✅ Replaced smart quotes and ellipsis")
        
        // SHOW THE ENTIRE JSON
        print("\n📋 COMPLETE CLEANED JSON:")
        print(String(repeating: "=", count: 80))
        print(cleanJSON)
        print(String(repeating: "=", count: 80))
        print("Total length: \(cleanJSON.count) characters\n")
        
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            print("❌ Could not convert to UTF-8 data")
            throw PromptEngineError.invalidJSON("Could not convert to UTF-8 data")
        }
        
        print("✅ Converted to Data: \(jsonData.count) bytes")
        
        // TRY GENERIC PARSE FIRST
        print("\n🔍 ATTEMPTING GENERIC JSON PARSE...")
        if let genericJSON = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            print("✅ Valid JSON structure detected")
            print("Root keys: \(genericJSON.keys.sorted().joined(separator: ", "))")
            print("Total keys found: \(genericJSON.keys.count)")
            
            // Validate expected v2.2 fields
            let v22RequiredFields = [
                "beatId", "beatKey", "sectionId", "sectionKey", "sourceVideoId",
                "mechanicsTags", "retrievalPriority", "sentenceRhythm",
                "namedEntities", "temporalAnchors", "quantitativeAnchors",
                "contrastPresent", "topicAbstraction", "pronounUsage",
                "adaptationDifficulty", "anchorFunction", "templateViability",
                "logicalFlow", "mechanicsDescription", "topicDescription",
                "writerHints", "performanceRetentionAtBeat"
            ]
            
            let missingV22Fields = v22RequiredFields.filter { !genericJSON.keys.contains($0) }
            if !missingV22Fields.isEmpty {
                print("⚠️  Missing v2.2 fields: \(missingV22Fields.joined(separator: ", "))")
            } else {
                print("✅ All v2.2 signature fields present")
            }
        } else {
            print("❌ NOT VALID JSON")
            throw PromptEngineError.invalidJSON("Invalid JSON syntax - see debug output above")
        }
        
        print("\n🔬 ATTEMPTING TO DECODE TO BeatDocResponse v2.2...")
        
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(BeatDocResponse.self, from: jsonData)
            
            print("\n✅ BEATDOC v2.2 JSON DECODED SUCCESSFULLY!")
            print("========================================")
            print("Beat ID: \(response.beatId)")
            print("Beat Key: \(response.beatKey)")
            print("Type: \(response.type)")
            print("Move Key: \(response.moveKey)")
            print("Mechanics Tags: \(response.mechanicsTags.joined(separator: ", "))")
            print("Section Role: \(response.sectionRole)")
            print("Quality Level: \(response.qualityLevel)")
            print("Reusability Score: \(response.reusabilityScore)/10")
            print("Named Entities: \(response.namedEntities.joined(separator: ", "))")
            print("Temporal Anchors: \(response.temporalAnchors.joined(separator: ", "))")
            print("Quantitative Anchors: \(response.quantitativeAnchors.joined(separator: ", "))")
            print("========================================")
            
            return response
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("\n❌ KEY NOT FOUND ERROR")
            print("Missing key: '\(key.stringValue)'")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            // Helpful suggestions for common v2.2 fields
            let v22Fields = ["mechanicsTags", "retrievalPriority", "sentenceRhythm",
                            "namedEntities", "temporalAnchors", "quantitativeAnchors"]
            if v22Fields.contains(key.stringValue) {
                print("💡 This is a v2.2 field - ensure LLM output includes it")
            }
            
            throw PromptEngineError.invalidJSON("Missing key: \(key.stringValue)")
            
        } catch let DecodingError.typeMismatch(type, context) {
            print("\n❌ TYPE MISMATCH ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            if let key = context.codingPath.last?.stringValue {
                print("Field with issue: \(key)")
            }
            
            throw PromptEngineError.invalidJSON("Type mismatch - expected \(type)")
            
        } catch let DecodingError.valueNotFound(type, context) {
            print("\n❌ VALUE NOT FOUND ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            if let key = context.codingPath.last?.stringValue {
                print("Missing value for: \(key)")
                print("💡 Check if LLM used null instead of empty string/array")
            }
            
            throw PromptEngineError.invalidJSON("Value not found for \(type)")
            
        } catch let DecodingError.dataCorrupted(context) {
            print("\n❌ DATA CORRUPTED ERROR")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            throw PromptEngineError.invalidJSON("Data corrupted")
            
        } catch {
            print("\n❌ UNKNOWN DECODING ERROR")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
            if let decodingError = error as? DecodingError {
                print("Detailed error: \(decodingError)")
            }
            throw PromptEngineError.parsingFailed("Decoder error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Response Structure (Complete v2.2 - 112 fields)
    
    struct BeatDocResponse: Codable {
        // MARK: - IDENTITY & ORIGIN
        let beatId: String
        let beatKey: String
        let sectionId: String
        let sectionKey: String
        let sourceVideoId: String
        let sourceChannelId: String
        let type: String
        let beatRole: String
        
        // MARK: - CONTENT
        let text: String
        
        // MARK: - TEXT ANCHORING
        let sentenceIndexScope: String
        let sentenceStartIndex: Int
        let sentenceEndIndex: Int
        let startWordIndex: Int
        let endWordIndex: Int
        let wordCount: Int
        let startCharIndex: Int
        let endCharIndex: Int
        
        // MARK: - COMPILER / EXTRACTION INTENT
        let compilerFunction: String
        let compilerWhyNow: String
        let compilerSetsUp: String
        let compilerEvidenceKind: String
        let compilerEvidenceText: String
        
        // MARK: - CORE RETRIEVAL
        let moveKey: String
        let mechanicsTags: [String]
        let retrievalPriority: String
        
        // MARK: - PROOF
        let proofMode: String
        let proofDensity: String
        
        // MARK: - MECHANICS
        let tempo: String
        let stance: String
        let sentenceCount: Int
        let avgSentenceLength: Double
        let sentenceLengthVariance: Double
        let questionCount: Int
        let teaseDistance: Int
        let personalVoice: Bool
        let informationDensity: String
        let cognitiveLoad: String
        
        // Enhanced Mechanics
        let sentenceRhythm: String
        let emotionalDirection: String
        let questionPlacement: String
        let promiseExplicit: Bool
        
        // Specificity
        let namedEntities: [String]
        let temporalAnchors: [String]
        let quantitativeAnchors: [String]
        
        // Contrast
        let contrastPresent: Bool
        let contrastType: String
        
        // MARK: - RHETORICAL DEVICES
        let rhetoricalDeviceLabels: [String]
        let questionRhetorical: Int
        let questionGenuine: Int
        let questionOpen: Int
        let questionSelfAnswer: Int
        
        // MARK: - TOPIC
        let topicPrimary: String
        let topicSecondary: [String]
        let topicSpecificity: String
        
        // Topic Depth
        let topicAbstraction: String
        let domainSpecificity: String
        let topicAccessibility: String
        let subjectCategories: [String]
        let crossDomainApplicability: [String]
        
        // MARK: - STYLE
        let styleFormality: Int
        let styleVocabularyLevel: Int
        let styleHumor: String
        
        // Voice Details
        let pronounUsage: String
        let casualMarkers: [String]
        let contractions: String
        let humorDensity: String
        let profanity: Bool
        let profanityType: String
        
        // MARK: - QUALITY & REUSABILITY
        let qualityLevel: String
        let anchorStrength: Int
        let reusabilityLevel: String
        let qualityReasoning: String
        let reusabilityScore: Int
        
        // Reusability Details
        let adaptationDifficulty: String
        let crossTopicViability: [String]
        let usageFrequency: String
        let cooldownRecommendation: Int
        let overuseRisk: String
        let contextDependency: String
        let frequencyClass: String
        
        // Human Validation
        let humanValidatedBy: String
        let humanValidatedAt: String
        
        // MARK: - PROMISE/PAYOFF
        let promiseType: String
        let payoffType: String
        let requiresPayoffWithinBeats: Int
        let promiseStrength: String
        
        // MARK: - VOICE MOVES
        let voiceMoves: [String]
        let customVoiceMoves: [String]
        let customRhetoricalTags: [String]
        
        // MARK: - ANCHORS
        let anchorIds: [String]
        let containsAnchor: Bool
        let anchorText: String
        let anchorFunction: String
        let anchorIsReusable: Bool
        let anchorFamily: String
        
        // MARK: - BEAT RELATIONSHIPS
        let setsUpBeatIds: [String]
        let paysOffBeatIds: [String]
        let callsBackToBeatIds: [String]
        let referencesBeatIds: [String]
        let similarMoveKeys: [String]
        
        // MARK: - SEMANTIC CONSTRAINTS
        let semanticConstraints: [String]
        let mustIntroduce: String
        let requiresContext: [String]
        
        // MARK: - TRANSITIONS
        let transitionType: String
        let transitionExpectation: String
        let transitionBridgeType: String
        let forwardPromiseBeatId: String
        let forwardPromiseWillDeliver: String
        let forwardPromiseType: String
        
        // MARK: - TEMPLATE
        let templatePattern: String
        let templateSlots: [String]
        let templateApplicableTo: [String]
        let templateRequiresSpecificity: Bool
        let templateRequiresTimestamp: Bool
        let templateRequiresNamedEntity: Bool
        let templateExampleTopic: String
        let templateExampleResult: String
        let templateViability: String
        
        // MARK: - POSITION METADATA
        let orderIndex: Int
        let beatIndexInSection: Int
        let sectionRole: String
        let globalBeatIndex: Int
        let totalBeatsInSection: Int
        let totalBeatsInScript: Int
        
        // MARK: - EMOTION
        let emotionArcPosition: String
        let emotionTargetFeelings: [String]
        let emotionAudienceState: String
        let emotionDevice: String
        let emotionValence: Int
        let emotionArousal: Int
        let emotionIntensity: Int
        let emotionTrajectory: String
        
        // MARK: - MUSIC BRIEF
        let musicBrief: String
        let musicInstrumentation: [String]
        let musicTempoRange: String
        let musicMood: String
        let musicDynamicRange: String
        
        // MARK: - ARGUMENT STRUCTURE
        let argumentPolarity: String
        let argumentResolutionStyle: String
        let argumentMove: String
        let argumentEvidenceStrategy: String
        let logicalFlow: String
        let argumentStructure: String
        
        // MARK: - FACTUAL CLAIMS
        let hasFactualClaims: Bool
        let hasNumbers: Bool
        let hasQuotes: Bool
        let hasHistoricalReferences: Bool
        let claimRisk: String
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
        let pronounFrequency: Int
        let directAddress: Bool
        let toneIndicators: [String]
        
        // MARK: - PROSE DESCRIPTIONS
        let mechanicsDescription: String
        let topicDescription: String
        
        // MARK: - WRITER GUIDANCE
        let writerHints: [String]
        let avoidContexts: [String]
        
        // MARK: - PERFORMANCE SIGNALS
        let performanceRetentionAtBeat: Double
        let performanceEngagementLift: String
        let performanceConfidence: Double
        
        // MARK: - EXTRACTION METADATA
        let extractedAt: String
        let extractedBy: String
        let extractorVersion: String
        let parseConfidence: Double
        let manualReviewRequired: Bool
        let reviewNotes: String
    }
}
//
//enum PromptEngineError: Error {
//    case invalidJSON(String)
//    case parsingFailed(String)
//}
