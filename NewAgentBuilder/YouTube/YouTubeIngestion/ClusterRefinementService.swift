//
//  ClusterRefinementService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/24/26.
//

import Foundation

/// Service for refining clusters through outlier detection and comparison
/// Uses the model as a fit-checker instead of a clusterer
class ClusterRefinementService {

    static let shared = ClusterRefinementService()

    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    // MARK: - Outlier Detection (Single Cluster)

    /// Analysis depth options
    enum AnalysisDepth: String, CaseIterable {
        case lightweight = "Lightweight (Title + Summary)"
        case fullTranscript = "Full Transcript Analysis"
        case executionTrace = "Execution Trace (Template Compatibility)"

        var description: String {
            switch self {
            case .lightweight: return "Fast, uses title and core question only"
            case .fullTranscript: return "Deep analysis using full video scripts"
            case .executionTrace: return "Tests structural survivability with break categories"
            }
        }
    }

    // MARK: - Execution Trace Outlier Detection (New Template-Focused Approach)

    /// Analyze cluster compatibility using execution traces and break categories
    /// Tests structural survivability: "Would using this video's trace as a template break?"
    func findOutlierWithExecutionTraces(
        clusterName: String,
        videos: [ClusterVideoSummary],
        executionTraces: [String: ExecutionTrace]  // videoId -> trace
    ) async throws -> ExecutionTraceOutlierResult {

        // Build video summaries with execution traces
        let videoSummaries = videos.enumerated().map { index, video -> String in
            guard let trace = executionTraces[video.id] else {
                return """
                VIDEO \(index + 1): "\(video.title)"
                ID: \(video.id)
                [No execution trace available]
                """
            }

            let pivotSummary = trace.pivots.map { p in
                "  - Pivot \(p.pivotNumber) at \(p.timestampPercent)%: \"\(p.triggerMoment)\""
            }.joined(separator: "\n")

            return """
            ═══════════════════════════════════════════════════════════════
            VIDEO \(index + 1): "\(video.title)"
            ID: \(video.id)
            ═══════════════════════════════════════════════════════════════
            OPENING (~\(trace.opening.durationSeconds)s): \(trace.opening.hookType) - \(trace.opening.whatHappens)
            PIVOTS:
            \(pivotSummary)
            EVIDENCE FLOW: \(trace.evidenceFlow.joined(separator: " → "))
            ESCALATION: \(trace.escalation)
            RESOLUTION: \(trace.resolution)
            NARRATOR: \(trace.narratorRole)
            """
        }.joined(separator: "\n\n")

        let prompt = Self.buildExecutionTraceOutlierPrompt(
            clusterName: clusterName,
            videoSummaries: videoSummaries,
            videoCount: videos.count
        )

        let freshAdapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let response = await freshAdapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: Self.executionTraceOutlierSystemPrompt,
            params: ["temperature": 0.1, "max_tokens": 2000]
        )

        return try parseExecutionTraceOutlierResult(response: response)
    }

    /// Build execution trace outlier prompt (exposed for copying)
    static func buildExecutionTraceOutlierPrompt(clusterName: String, videoSummaries: String, videoCount: Int) -> String {
        return """
        CLUSTER: "\(clusterName)"
        VIDEOS: \(videoCount)

        \(videoSummaries)

        ═══════════════════════════════════════════════════════════════
        STRUCTURAL SURVIVABILITY TEST
        ═══════════════════════════════════════════════════════════════

        For each video in this cluster, test:
        "If this video's execution trace were used as a template to write every OTHER video in the cluster, where would it BREAK?"

        ### Break Categories (use only these):

        - opening-mismatch: Opening architecture doesn't transfer
        - narrator-mismatch: Creator's relationship to material is incompatible
        - evidence-flow-mismatch: Proof accumulation sequence doesn't fit
        - pivot-mechanics-mismatch: Turns are triggered by incompatible mechanisms
        - escalation-mismatch: How stakes/complexity builds is structurally different
        - resolution-mismatch: Closing architecture doesn't transfer
        - none: No structural break — compatible

        ### The Test:

        For each video, ask: "If I used Video X's trace as a template to generate the other videos, would it work?"

        If a video causes structural breaks with the MAJORITY of other videos → it's an outlier.
        If all videos are compatible as templates for each other → allCompatible: true.

        ### CRITICAL: Test Each Pairing

        Do not assume transitivity. Test each video against the cluster.

        ═══════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════

        {
          "allCompatible": true | false,
          "clusterExecutionPattern": "Describe the shared execution pattern if compatible",
          "outliers": [
            {
              "videoId": "id",
              "videoTitle": "title",
              "breaksWith": ["videoId1", "videoId2"],
              "breakCategory": "one of the break categories above",
              "breakExplanation": "Why this video's trace doesn't transfer",
              "percentOfClusterIncompatible": 0.0
            }
          ],
          "compatibilityMatrix": [
            {
              "videoId": "id",
              "compatibleWith": ["id1", "id2"],
              "incompatibleWith": []
            }
          ]
        }

        Return ONLY valid JSON.
        """
    }

    /// System prompt for execution trace outlier detection
    static let executionTraceOutlierSystemPrompt = """
        You are validating a cluster's template compatibility using execution traces.

        The test is STRUCTURAL SURVIVABILITY:
        "If I used Video A's execution trace as a template to write Video B, would the structure break?"

        Focus on:
        - Opening architecture compatibility
        - Pivot mechanics compatibility
        - Evidence flow compatibility
        - Escalation pattern compatibility
        - Resolution architecture compatibility
        - Narrator role compatibility

        Be rigorous. Test each pairing. Report specific break categories.

        If all videos are template-compatible, say allCompatible: true.
        If one video breaks with the majority, it's an outlier.

        Return only valid JSON.
        """

    /// Analyze a single cluster to find the video that fits least (lightweight mode)
    func findOutlier(
        clusterName: String,
        videos: [ClusterVideoSummary],
        allClusterNames: [String]
    ) async throws -> OutlierAnalysisResult {

        let videoList = videos.enumerated().map { index, video in
            "\(index + 1). \"\(video.title)\" - \(video.oneLiner)"
        }.joined(separator: "\n")

        let otherClusters = allClusterNames.filter { $0 != clusterName }.joined(separator: ", ")

        let prompt = Self.buildOutlierPrompt(videoList: videoList, clusterName: clusterName, otherClusters: otherClusters)

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: Self.outlierSystemPrompt,
            params: ["temperature": 0.1, "max_tokens": 1000]
        )

        return try parseOutlierResult(response: response)
    }

    /// Build the outlier detection prompt (exposed for copying)
    static func buildOutlierPrompt(videoList: String, clusterName: String, otherClusters: String) -> String {
        return """
        Here are videos in a cluster called "\(clusterName)":

        \(videoList)

        ═══════════════════════════════════════════════════════════════
        NARRATIVE ARC PATTERNS (pick from this list)
        ═══════════════════════════════════════════════════════════════

        Every video uses ONE dominant narrative arc. Here are the patterns:

        1. MYSTERY-REVEAL
           Opens with unanswered question → investigates → reveals answer at end
           "What really happened to X?" / "Why does X exist?"

        2. ESCALATING STAKES
           Each section raises consequences → builds to "this changes everything"
           Stakes go: interesting → important → world-changing

        3. TRANSFORMATION ARC
           Shows change over time: X was this → something happened → now X is this
           "How X became Y" / "The rise and fall of X"

        4. SYSTEMATIC EXPLAINER
           Breaks down how something works, layer by layer
           "Here's component A, here's component B, here's how they connect"

        5. PROBLEM-SOLUTION
           Presents problem → explores why it's hard → presents solution/hope
           "X is broken, but here's how we might fix it"

        6. JOURNEY/ADVENTURE
           Follows someone/something through a sequence of events
           "I tried X" / "We went to X" / "The story of X's attempt to..."

        7. VERSUS/COMPARISON
           Structured as A vs B throughout the entire video
           "X vs Y: which is better?" / "The war between X and Y"

        8. COUNTDOWN/LIST
           Ranked or sequential items driving the structure
           "Top 10 X" / "The 5 stages of X"

        ═══════════════════════════════════════════════════════════════
        TASK: Identify each video's arc, then check for misfits
        ═══════════════════════════════════════════════════════════════

        Step 1: For each video, identify which arc pattern it uses (from the list above)
        Step 2: What arc do the MAJORITY share?
        Step 3: Does any video use a DIFFERENT arc pattern?

        CRITICAL RULES:
        - IGNORE the topic. "Why Rome Fell" and "Why Startups Fail" can both be TRANSFORMATION ARC.
        - IGNORE whether it's "real" vs "theoretical". Both can use MYSTERY-REVEAL.
        - ONLY look at the narrative structure pattern.

        Your default answer should be "allFitWell: true".
        Only flag an outlier if it uses a genuinely DIFFERENT arc pattern from the majority.

        RESPOND WITH JSON:
        {
          "videoArcs": [
            {"title": "<video 1 title>", "arc": "<arc name from list>"},
            {"title": "<video 2 title>", "arc": "<arc name from list>"},
            ...
          ],
          "majorityArc": "<the arc most videos share>",
          "outlierIndex": <1-based index of outlier, or 0 if all share same arc>,
          "outlierTitle": "<title of outlier, or empty if none>",
          "outlierArc": "<the different arc the outlier uses, or empty if none>",
          "whyDoesntBelong": "<explain the arc difference, NOT topic difference>",
          "whatOtherVideosShare": "<e.g. 'MYSTERY-REVEAL: all open with a question and build to an answer'>",
          "specificEvidence": null,
          "suggestedCluster": "<cluster that might use this arc: \(otherClusters), or 'none'>",
          "confidence": "<high/medium/low>",
          "allFitWell": <true if all videos share the same arc pattern>
        }
        """
    }

    /// System prompt for outlier detection (exposed for copying)
    static let outlierSystemPrompt = """
        You are analyzing videos by their NARRATIVE ARC PATTERN only.

        IGNORE: topic, subject matter, whether it's "real" or "theoretical", tone, style
        FOCUS ONLY ON: Which narrative arc pattern does each video use?

        Two videos about completely different subjects (physics vs cooking vs history)
        can all use the same arc (e.g., MYSTERY-REVEAL).

        A video about "real technology" and a video about "thought experiments"
        can both use SYSTEMATIC EXPLAINER arc.

        Your job: identify arcs, find if one video uses a different arc than the others.
        If all videos use the same arc pattern, say "allFitWell: true".

        Return only valid JSON.
        """

    /// System prompt for full transcript analysis (exposed for copying)
    static let fullTranscriptSystemPrompt = """
        You are analyzing video transcripts by their NARRATIVE ARC PATTERN only.

        IGNORE completely: topic, subject matter, whether content is "real" or "theoretical", tone, style, evidence types, video length

        FOCUS ONLY ON: What narrative structure does each transcript follow?
        - How does it OPEN? (question, problem statement, "let me explain", story setup)
        - How does it BUILD? (escalating stakes, layered explanation, mystery unfolding, comparison)
        - How does it RESOLVE? (reveal, solution, transformation complete, call to action)

        Two videos about completely different subjects can use the same arc.
        A "thought experiment" video and a "real technology" video can both use SYSTEMATIC EXPLAINER.

        Read the actual transcript text. Identify the arc from the structure, not the content.

        If all videos use the same arc pattern, say "allFitWell: true".
        Only flag an outlier if you're confident it uses a DIFFERENT arc.

        Return only valid JSON.
        """

    /// Analyze a single cluster using FULL TRANSCRIPTS for deep analysis
    /// Use this when you need the model to understand the actual content, not just metadata
    func findOutlierWithFullTranscripts(
        clusterName: String,
        videos: [ClusterVideoSummary],
        allClusterNames: [String]
    ) async throws -> OutlierAnalysisResult {

        // Build detailed video list with full transcripts
        let videoList = videos.enumerated().map { index, video in
            let transcript = video.transcript ?? "[No transcript available]"
            // Truncate each transcript to ~10000 chars to fit multiple in context
            let truncatedTranscript = String(transcript.prefix(10000))
            let wasTruncated = transcript.count > 10000

            return """
            ═══════════════════════════════════════════════════════════════
            VIDEO \(index + 1): "\(video.title)"
            ═══════════════════════════════════════════════════════════════
            Core Question: \(video.oneLiner)

            FULL TRANSCRIPT\(wasTruncated ? " (truncated)" : ""):
            \(truncatedTranscript)
            """
        }.joined(separator: "\n\n")

        let otherClusters = allClusterNames.filter { $0 != clusterName }.joined(separator: ", ")

        let prompt = """
        You have access to the FULL TRANSCRIPTS of videos in a cluster called "\(clusterName)".

        \(videoList)

        ═══════════════════════════════════════════════════════════════
        NARRATIVE ARC PATTERNS (pick from this list)
        ═══════════════════════════════════════════════════════════════

        Every video uses ONE dominant narrative arc. Identify each video's arc by reading the transcript:

        1. MYSTERY-REVEAL
           Opens with unanswered question → investigates → reveals answer at end
           Look for: Opening hook is a question, answer withheld until end

        2. ESCALATING STAKES
           Each section raises consequences → builds to "this changes everything"
           Look for: Stakes go interesting → important → world-changing

        3. TRANSFORMATION ARC
           Shows change over time: X was this → something happened → now X is this
           Look for: Clear before/after, turning point in the middle

        4. SYSTEMATIC EXPLAINER
           Breaks down how something works, layer by layer
           Look for: "First, let me explain A... Now B... And finally C..."

        5. PROBLEM-SOLUTION
           Presents problem → explores why it's hard → presents solution/hope
           Look for: Problem statement early, solution or hope at the end

        6. JOURNEY/ADVENTURE
           Follows someone/something through a sequence of events
           Look for: Chronological progression, "then... then... then..."

        7. VERSUS/COMPARISON
           Structured as A vs B throughout the entire video
           Look for: Constant back-and-forth between two things

        8. COUNTDOWN/LIST
           Ranked or sequential items driving the structure
           Look for: "Number 5... Number 4..." or similar enumeration

        ═══════════════════════════════════════════════════════════════
        HOW TO IDENTIFY ARC FROM TRANSCRIPT
        ═══════════════════════════════════════════════════════════════

        OPENING (first 10%):
        - Question asked? → likely MYSTERY-REVEAL
        - Problem stated? → likely PROBLEM-SOLUTION
        - "Let me explain how X works" → likely SYSTEMATIC EXPLAINER
        - "X used to be... but then..." → likely TRANSFORMATION ARC

        MIDDLE (body):
        - Stakes keep rising? → ESCALATING STAKES
        - Layers of understanding? → SYSTEMATIC EXPLAINER
        - A vs B throughout? → VERSUS/COMPARISON
        - Numbered items? → COUNTDOWN/LIST

        ENDING (final 10%):
        - Big reveal/answer? → MYSTERY-REVEAL
        - Solution presented? → PROBLEM-SOLUTION
        - "And that's how X became Y" → TRANSFORMATION ARC

        ═══════════════════════════════════════════════════════════════
        TASK: Identify each video's arc, then check for misfits
        ═══════════════════════════════════════════════════════════════

        Step 1: Read each transcript and identify its arc pattern
        Step 2: What arc do the MAJORITY share?
        Step 3: Does any video use a DIFFERENT arc pattern?

        CRITICAL: IGNORE the topic entirely. Only look at narrative structure.

        Your default answer should be "allFitWell: true".
        Only flag an outlier if it uses a genuinely DIFFERENT arc pattern.

        RESPOND WITH JSON:
        {
          "videoArcs": [
            {"title": "<video 1 title>", "arc": "<arc name from list>"},
            {"title": "<video 2 title>", "arc": "<arc name from list>"},
            ...
          ],
          "majorityArc": "<the arc most videos share>",
          "outlierIndex": <1-based index of outlier, or 0 if all share same arc>,
          "outlierTitle": "<title of outlier, or empty if none>",
          "outlierArc": "<the different arc the outlier uses, or empty if none>",
          "whyDoesntBelong": "<explain the arc difference, referencing transcript evidence>",
          "whatOtherVideosShare": "<e.g. 'MYSTERY-REVEAL: all open with a question and build to an answer'>",
          "specificEvidence": "<quote actual phrases showing the outlier's different arc structure>",
          "suggestedCluster": "<cluster that might use this arc: \(otherClusters), or 'none'>",
          "confidence": "<high/medium/low>",
          "allFitWell": <true if all videos share the same arc pattern>
        }
        """

        let systemPrompt = Self.fullTranscriptSystemPrompt

        // Use fresh adapter for potentially long response
        let freshAdapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let response = await freshAdapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.1, "max_tokens": 2000]
        )

        return try parseOutlierResult(response: response)
    }

    // MARK: - Cluster Comparison (Two Clusters)

    /// Compare two clusters to find videos that should swap
    func compareClusterPair(
        clusterA: ClusterForComparison,
        clusterB: ClusterForComparison
    ) async throws -> ClusterComparisonResult {

        let listA = clusterA.videos.enumerated().map { index, video in
            "\(index + 1). \"\(video.title)\" - \(video.oneLiner)"
        }.joined(separator: "\n")

        let listB = clusterB.videos.enumerated().map { index, video in
            "\(index + 1). \"\(video.title)\" - \(video.oneLiner)"
        }.joined(separator: "\n")

        let prompt = """
        CLUSTER A - "\(clusterA.name)":
        \(listA)

        CLUSTER B - "\(clusterB.name)":
        \(listB)

        ═══════════════════════════════════════════════════════════════
        WHAT IS A "STORY ARC"?
        ═══════════════════════════════════════════════════════════════

        The STORY ARC is the dominant narrative pattern that drives the video.
        It's HOW the video takes the viewer on a journey, NOT what topic it covers.

        Examples of distinct story arcs:
        - Mystery-Reveal: Opens with puzzle, builds tension, reveals answer
        - Escalating Stakes: Each section raises the consequences
        - Transformation Arc: Shows how X became Y over time
        - Systematic Breakdown: Explains how X works piece by piece
        - Contrast/Comparison: Structured around A vs B throughout

        Two videos about DIFFERENT topics can share the SAME arc.

        ═══════════════════════════════════════════════════════════════
        TASK: Do these two clusters have DISTINCT story arcs?
        ═══════════════════════════════════════════════════════════════

        First, identify the DOMINANT story arc for each cluster.
        Then check: is any video clearly using the OTHER cluster's arc?

        IMPORTANT: Your default should be "noChangesNeeded: true".

        Only recommend a swap if:
        1. The two clusters have CLEARLY DIFFERENT story arcs
        2. A video OBVIOUSLY uses the other cluster's arc
        3. You would recommend the SAME swap if you ran this 10 times

        DO NOT recommend swaps just because:
        - A video covers a topic that "sounds like" the other cluster
        - A video is slightly different in tone
        - You feel like you "should" find something

        RESPOND WITH JSON:
        {
          "swapsRecommended": [
            {
              "videoTitle": "<title>",
              "fromCluster": "<A or B>",
              "toCluster": "<A or B>",
              "reason": "<why this video uses the OTHER cluster's story arc>"
            }
          ],
          "outliers": [
            {
              "videoTitle": "<title>",
              "currentCluster": "<A or B>",
              "reason": "<why it uses NEITHER cluster's story arc>"
            }
          ],
          "clusterAEngine": "<name the specific story arc that defines Cluster A>",
          "clusterBEngine": "<name the specific story arc that defines Cluster B>",
          "noChangesNeeded": <true if both clusters are clean, false only if confident>
        }

        If no swaps are needed, return empty arrays and noChangesNeeded: true.
        """

        let systemPrompt = """
        You are a content clustering analyst comparing two clusters by STORY ARC.

        Your job is to check if any video is using the wrong cluster's narrative pattern.
        You are NOT looking for topic mismatches or style differences.

        BE CONSERVATIVE. Default to "noChangesNeeded: true".
        Only recommend swaps for CLEAR structural mismatches.

        Ask yourself: "If I ran this comparison 10 times, would I recommend the same swap?"
        If not, don't recommend it.

        Return only valid JSON.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.1, "max_tokens": 1500]
        )

        return try parseComparisonResult(response: response)
    }

    // MARK: - Outlier Grouping Analysis

    /// Analyze a set of outliers to see if any form natural groups
    func analyzeOutliers(outliers: [ClusterVideoSummary]) async throws -> OutlierGroupingResult {

        let videoList = outliers.enumerated().map { index, video in
            "\(index + 1). \"\(video.title)\" - \(video.oneLiner)"
        }.joined(separator: "\n")

        let prompt = """
        These videos don't fit existing clusters:

        \(videoList)

        ═══════════════════════════════════════════════════════════════
        TASK: Do any of these share the SAME STORY ARC?
        ═══════════════════════════════════════════════════════════════

        Remember: Story arc is HOW the video takes the viewer on a journey.
        - Mystery-Reveal: Opens with puzzle, builds tension, reveals answer
        - Escalating Stakes: Each section raises the consequences
        - Transformation Arc: Shows how X became Y
        - Systematic Breakdown: Explains how X works
        - Contrast/Comparison: A vs B throughout

        Look for videos that use the SAME narrative pattern, regardless of topic.

        IMPORTANT: Be conservative. Only suggest a new cluster if:
        1. At least 2 videos share a CLEAR, NAMEABLE story arc
        2. You're confident they'd cluster together if you ran this 10 times

        Videos that don't clearly match anything are "true orphans" - that's OK.

        RESPOND WITH JSON:
        {
          "potentialGroups": [
            {
              "suggestedName": "<name based on the story arc, not the topic>",
              "videoTitles": ["<title1>", "<title2>"],
              "sharedEngine": "<the specific story arc these videos share>",
              "confidence": "<high/medium/low>"
            }
          ],
          "trueOrphans": [
            {
              "videoTitle": "<title>",
              "reason": "<brief note - orphans are fine>"
            }
          ],
          "recommendation": "<create cluster(s) / leave as uncategorized / mixed>"
        }
        """

        let systemPrompt = """
        You are reviewing outlier videos to see if any share a story arc.

        BE CONSERVATIVE. It's perfectly fine for outliers to remain uncategorized.
        Only suggest a new cluster if there's a genuine shared narrative pattern.

        Don't force connections that aren't there.
        Videos about similar TOPICS but different ARCS should NOT be grouped.

        Return only valid JSON.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.1, "max_tokens": 1500]
        )

        return try parseOutlierGroupingResult(response: response)
    }

    // MARK: - Parsing

    private func parseOutlierResult(response: String) throws -> OutlierAnalysisResult {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw RefinementError.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(OutlierAnalysisResult.self, from: data)
        return decoded
    }

    private func parseComparisonResult(response: String) throws -> ClusterComparisonResult {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw RefinementError.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(ClusterComparisonResult.self, from: data)
        return decoded
    }

    private func parseOutlierGroupingResult(response: String) throws -> OutlierGroupingResult {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw RefinementError.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(OutlierGroupingResult.self, from: data)
        return decoded
    }

    private func parseExecutionTraceOutlierResult(response: String) throws -> ExecutionTraceOutlierResult {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw RefinementError.invalidResponse("Could not find JSON in execution trace outlier response")
        }

        let decoded = try JSONDecoder().decode(ExecutionTraceOutlierResult.self, from: data)
        return decoded
    }

    private func extractJSON(from response: String) -> String? {
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            return String(response[firstBrace...lastBrace])
        }
        return nil
    }

    enum RefinementError: Error, LocalizedError {
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let msg): return "Invalid refinement response: \(msg)"
            }
        }
    }
}

// MARK: - Models

struct ClusterVideoSummary: Identifiable, Codable {
    let id: String  // videoId
    let title: String
    let oneLiner: String  // Core question or brief description
    let transcript: String?  // Optional full transcript for deep analysis

    init(id: String, title: String, oneLiner: String, transcript: String? = nil) {
        self.id = id
        self.title = title
        self.oneLiner = oneLiner
        self.transcript = transcript
    }

    init(from video: YouTubeVideo, includeTranscript: Bool = false) {
        self.id = video.videoId
        self.title = video.title
        self.oneLiner = video.phase0Result?.coreQuestion ?? video.description.prefix(100).description
        self.transcript = includeTranscript ? video.transcript : nil
    }
}

struct ClusterForComparison {
    let name: String
    let videos: [ClusterVideoSummary]
}

// MARK: - Result Models

struct OutlierAnalysisResult: Codable {
    let videoArcs: [VideoArcAssignment]?  // Arc assignment for each video
    let majorityArc: String?  // The arc most videos share
    let outlierIndex: Int  // 1-based, or 0 if none
    let outlierTitle: String
    let outlierArc: String?  // The different arc the outlier uses
    let whyDoesntBelong: String
    let whatOtherVideosShare: String
    let specificEvidence: String?  // Only present in full transcript analysis
    let suggestedCluster: String
    let confidence: String
    let allFitWell: Bool

    /// Formatted result for copying
    var copyableText: String {
        var lines: [String] = []

        if let arcs = videoArcs, !arcs.isEmpty {
            lines.append("VIDEO ARC ASSIGNMENTS:")
            for arc in arcs {
                lines.append("  • \(arc.title): \(arc.arc)")
            }
            lines.append("")
        }

        if let majority = majorityArc {
            lines.append("MAJORITY ARC: \(majority)")
            lines.append("")
        }

        if allFitWell {
            lines.append("RESULT: All videos fit well (same arc pattern)")
        } else {
            lines.append("OUTLIER: \(outlierTitle)")
            if let arc = outlierArc {
                lines.append("OUTLIER ARC: \(arc)")
            }
            lines.append("WHY: \(whyDoesntBelong)")
            lines.append("OTHERS SHARE: \(whatOtherVideosShare)")
            if let evidence = specificEvidence, !evidence.isEmpty {
                lines.append("EVIDENCE: \(evidence)")
            }
            lines.append("SUGGESTED CLUSTER: \(suggestedCluster)")
            lines.append("CONFIDENCE: \(confidence)")
        }

        return lines.joined(separator: "\n")
    }
}

struct VideoArcAssignment: Codable {
    let title: String
    let arc: String
}

struct ClusterComparisonResult: Codable {
    let swapsRecommended: [SwapRecommendation]
    let outliers: [ComparisonOutlier]
    let clusterAEngine: String
    let clusterBEngine: String
    let noChangesNeeded: Bool
}

struct SwapRecommendation: Codable {
    let videoTitle: String
    let fromCluster: String
    let toCluster: String
    let reason: String
}

struct ComparisonOutlier: Codable {
    let videoTitle: String
    let currentCluster: String
    let reason: String
}

struct OutlierGroupingResult: Codable {
    let potentialGroups: [PotentialGroup]
    let trueOrphans: [TrueOrphan]
    let recommendation: String
}

struct PotentialGroup: Codable {
    let suggestedName: String
    let videoTitles: [String]
    let sharedEngine: String
    let confidence: String
}

struct TrueOrphan: Codable {
    let videoTitle: String
    let reason: String
}

// MARK: - Execution Trace Outlier Result (New Template-Focused)

struct ExecutionTraceOutlierResult: Codable {
    let allCompatible: Bool
    let clusterExecutionPattern: String?
    let outliers: [ExecutionTraceOutlier]
    let compatibilityMatrix: [VideoCompatibility]?

    /// Formatted result for copying
    var copyableText: String {
        var lines: [String] = []

        if allCompatible {
            lines.append("RESULT: All videos are template-compatible")
            if let pattern = clusterExecutionPattern {
                lines.append("SHARED PATTERN: \(pattern)")
            }
        } else {
            lines.append("RESULT: Outliers detected")
            for outlier in outliers {
                lines.append("")
                lines.append("OUTLIER: \(outlier.videoTitle)")
                lines.append("  Break Category: \(outlier.breakCategory)")
                lines.append("  Explanation: \(outlier.breakExplanation)")
                lines.append("  Incompatible with: \(Int(outlier.percentOfClusterIncompatible * 100))% of cluster")
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct ExecutionTraceOutlier: Codable {
    let videoId: String
    let videoTitle: String
    let breaksWith: [String]
    let breakCategory: String
    let breakExplanation: String
    let percentOfClusterIncompatible: Double
}

struct VideoCompatibility: Codable {
    let videoId: String
    let compatibleWith: [String]
    let incompatibleWith: [String]
}
