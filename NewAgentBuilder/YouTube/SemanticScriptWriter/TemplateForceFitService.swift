//
//  TemplateForceFitService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Service that implements the 6-step force-fit pipeline
/// Step 0: Template retrieval from database (ClusteringResult.templates)
/// Step 1: Parallel force-fit (N AI calls)
/// Step 2: Question aggregation (1 AI call)
/// Step 3: User rambles again (human action)
/// Step 4: Parallel re-fit (N AI calls)
/// Step 5: Evaluation & ranking (1 AI call)
/// Step 6: User selection (human action)
@MainActor
class TemplateForceFitService: ObservableObject {
    static let shared = TemplateForceFitService()

    @Published var isProcessing = false
    @Published var currentPhase: String = ""
    @Published var progress: Double = 0.0

    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    private init() {}

    // MARK: - Step 1: Parallel Force-Fit (N AI Calls)

    /// Run Step 1: Force-fit rambling against all templates in parallel
    /// Templates come from StructuralTemplate (discovered from real video analysis)
    func step1ForceFitAll(
        rambling: String,
        templates: [StructuralTemplate]
    ) async -> Step1Results {
        isProcessing = true
        progress = 0.0
        currentPhase = "Step 1: Force-fitting to \(templates.count) templates..."

        var results: [ForceFitResult] = []
        let totalTemplates = Double(templates.count)

        // Run all templates in parallel using TaskGroup
        await withTaskGroup(of: ForceFitResult?.self) { group in
            for template in templates {
                group.addTask {
                    await self.forceFitSingle(rambling: rambling, template: template)
                }
            }

            var completed = 0.0
            for await result in group {
                completed += 1
                await MainActor.run {
                    self.progress = completed / totalTemplates
                    self.currentPhase = "Step 1: Fitting... \(Int(completed))/\(Int(totalTemplates))"
                }
                if let result = result {
                    results.append(result)
                }
            }
        }

        isProcessing = false
        currentPhase = ""
        return Step1Results(results: results)
    }

    /// Force-fit rambling to a single template (Step 1 single call)
    /// Builds prompt dynamically from TemplateChunk properties
    private func forceFitSingle(
        rambling: String,
        template: StructuralTemplate
    ) async -> ForceFitResult? {
        // Build chunk definitions from real template data
        let chunkDefinitions = template.typicalSequence.map { chunk in
            let tags = chunk.highTags.isEmpty ? "" : " [Tags: \(chunk.highTags.joined(separator: ", "))]"
            let pivot = chunk.isPivotPoint ? " << PIVOT" : ""
            return "- Chunk \(chunk.chunkIndex): \"\(chunk.typicalRole)\" \(chunk.positionLabel)\(tags)\(pivot)"
        }.joined(separator: "\n")

        // Build expected content descriptions
        let expectedContentDesc = template.typicalSequence.map { chunk in
            let expected = generateExpectedContent(for: chunk)
            return "  Chunk \(chunk.chunkIndex) expects: \(expected)"
        }.joined(separator: "\n")

        let prompt = """
        TEMPLATE: \(template.templateName)
        From channel analysis: \(template.videoCount) videos follow this pattern
        Key characteristics: \(template.dominantCharacteristics.joined(separator: ", "))

        CHUNK SEQUENCE (discovered from real videos):
        \(chunkDefinitions)

        WHAT EACH CHUNK TYPICALLY CONTAINS:
        \(expectedContentDesc)

        ---

        USER'S RAMBLING:
        \(rambling)

        ---

        Analyze the rambling against this template:
        1. Score how much of the rambling naturally maps to this template (0-100)
        2. List which chunk indices have content present in the rambling
        3. List which chunk indices are MISSING content
        4. Generate 2-3 questions that would fill the missing chunks
           (Questions must be specific to THIS template's structural needs)

        Return JSON in this EXACT format:
        {
            "template_id": "\(template.id)",
            "fit_score": 75,
            "chunks_filled": [0, 2, 4],
            "chunks_missing": [1, 3],
            "questions": [
                "Question specific to missing chunk 1",
                "Question specific to missing chunk 3"
            ]
        }
        """

        let systemPrompt = """
        You are an expert script structure analyzer. Your job is to map raw content ("rambling") to specific template chunks discovered from analyzing real YouTube videos.

        Be generous in mapping - if content COULD fit a chunk, count it as filled.
        Only mark chunks as missing if there's truly no relevant content.
        Questions should be specific and actionable - they should directly elicit content for the missing chunk's typical role.

        Respond in valid JSON format only. No markdown, no explanation.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 2000]
        )

        return parseStep1Response(response: response, template: template)
    }

    private func parseStep1Response(response: String, template: StructuralTemplate) -> ForceFitResult? {
        guard let jsonData = extractJSON(from: response) else {
            print("Step 1: Failed to extract JSON from response")
            return createFallbackStep1Result(template: template, rawResponse: response)
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return createFallbackStep1Result(template: template, rawResponse: response)
            }

            let fitScore = json["fit_score"] as? Int ?? 0
            let chunksFilled = json["chunks_filled"] as? [Int] ?? []
            let chunksMissing = json["chunks_missing"] as? [Int] ?? []
            let questions = json["questions"] as? [String] ?? []

            return ForceFitResult(
                templateId: template.id,
                templateName: template.templateName,
                template: template,
                fitScore: fitScore,
                chunksFilled: chunksFilled,
                chunksMissing: chunksMissing,
                questions: questions,
                rawResponse: response
            )

        } catch {
            print("Step 1: Failed to parse JSON: \(error)")
            return createFallbackStep1Result(template: template, rawResponse: response)
        }
    }

    private func createFallbackStep1Result(template: StructuralTemplate, rawResponse: String) -> ForceFitResult {
        // Generate questions for missing chunks using the helper
        let questions = template.typicalSequence
            .filter { $0.isPivotPoint || $0.chunkIndex == 0 }  // Pivots and opening are most important
            .map { generateExtractionQuestion(for: $0) }

        return ForceFitResult(
            templateId: template.id,
            templateName: template.templateName,
            template: template,
            fitScore: 0,
            chunksFilled: [],
            chunksMissing: template.typicalSequence.map { $0.chunkIndex },
            questions: questions,
            rawResponse: rawResponse
        )
    }

    // MARK: - Step 2: Question Aggregation (1 AI Call)

    /// Run Step 2: Aggregate and deduplicate questions across all templates
    func step2AggregateQuestions(
        step1Results: Step1Results
    ) async -> QuestionAggregationResult {
        isProcessing = true
        currentPhase = "Step 2: Aggregating questions..."

        let allQuestions = step1Results.allRawQuestions

        // If we have very few questions, skip aggregation
        if allQuestions.count <= 5 {
            isProcessing = false
            currentPhase = ""
            return QuestionAggregationResult(
                consolidatedQuestions: allQuestions,
                questionCountBefore: allQuestions.count,
                questionCountAfter: allQuestions.count,
                rawResponse: "Skipped aggregation - only \(allQuestions.count) questions"
            )
        }

        let numberedQuestions = allQuestions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let prompt = """
        Here are \(allQuestions.count) questions generated across multiple templates:

        \(numberedQuestions)

        Many may be asking the same thing in different words.

        1. Deduplicate questions that are semantically identical
        2. Merge similar questions into single clearer versions
        3. Group remaining questions by what information they're seeking
        4. Return a consolidated question set (target: reduce by 40-60%)

        Do NOT answer the questions. Only consolidate them.

        Return JSON in this EXACT format:
        {
            "consolidated_questions": [
                "Consolidated question 1",
                "Consolidated question 2"
            ],
            "question_count_before": \(allQuestions.count),
            "question_count_after": 8
        }
        """

        let systemPrompt = """
        You are an expert at identifying semantically similar questions and consolidating them.
        Focus on preserving the intent of each question while reducing redundancy.
        Each consolidated question should be clear and actionable.

        Respond in valid JSON format only. No markdown, no explanation.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.2, "max_tokens": 2000]
        )

        isProcessing = false
        currentPhase = ""

        return parseStep2Response(response: response, originalCount: allQuestions.count)
    }

    private func parseStep2Response(response: String, originalCount: Int) -> QuestionAggregationResult {
        guard let jsonData = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let consolidated = json["consolidated_questions"] as? [String] else {
            return QuestionAggregationResult(
                consolidatedQuestions: [],
                questionCountBefore: originalCount,
                questionCountAfter: 0,
                rawResponse: response
            )
        }

        return QuestionAggregationResult(
            consolidatedQuestions: consolidated,
            questionCountBefore: originalCount,
            questionCountAfter: consolidated.count,
            rawResponse: response
        )
    }

    // MARK: - Step 4: Parallel Re-Fit (N AI Calls)

    /// Run Step 4: Re-fit with enriched content (original + answers)
    func step4ReFitAll(
        originalRambling: String,
        answerRambling: String,
        templates: [StructuralTemplate]
    ) async -> Step4Results {
        isProcessing = true
        progress = 0.0
        currentPhase = "Step 4: Re-fitting with answers..."

        var results: [ReFitResult] = []
        let totalTemplates = Double(templates.count)

        await withTaskGroup(of: ReFitResult?.self) { group in
            for template in templates {
                group.addTask {
                    await self.reFitSingle(
                        originalRambling: originalRambling,
                        answerRambling: answerRambling,
                        template: template
                    )
                }
            }

            var completed = 0.0
            for await result in group {
                completed += 1
                await MainActor.run {
                    self.progress = completed / totalTemplates
                    self.currentPhase = "Step 4: Re-fitting... \(Int(completed))/\(Int(totalTemplates))"
                }
                if let result = result {
                    results.append(result)
                }
            }
        }

        isProcessing = false
        currentPhase = ""
        return Step4Results(results: results)
    }

    /// Re-fit a single template with enriched content
    private func reFitSingle(
        originalRambling: String,
        answerRambling: String,
        template: StructuralTemplate
    ) async -> ReFitResult? {
        // Build chunk definitions from real template data
        let chunkDefinitions = template.typicalSequence.map { chunk in
            let tags = chunk.highTags.isEmpty ? "" : " [Tags: \(chunk.highTags.joined(separator: ", "))]"
            let pivot = chunk.isPivotPoint ? " << PIVOT" : ""
            let expected = generateExpectedContent(for: chunk)
            return "- Chunk \(chunk.chunkIndex): \"\(chunk.typicalRole)\" \(chunk.positionLabel)\(tags)\(pivot)\n    Expects: \(expected)"
        }.joined(separator: "\n")

        let chunkIndices = template.typicalSequence.map { String($0.chunkIndex) }.joined(separator: ", ")

        let prompt = """
        TEMPLATE: \(template.templateName)
        From channel analysis: \(template.videoCount) videos follow this pattern
        Key characteristics: \(template.dominantCharacteristics.joined(separator: ", "))

        CHUNK SEQUENCE:
        \(chunkDefinitions)

        ---

        ORIGINAL RAMBLING:
        \(originalRambling)

        ANSWER RAMBLING (responses to follow-up questions):
        \(answerRambling)

        ---

        Given this template definition and BOTH ramblings (original + answers):
        1. Score how much content now maps to this template (0-100)
        2. Map specific content to each chunk by index
        3. Rate confidence per chunk (how well does the content fit that chunk's typical role, 0-100)
        4. Flag any chunks still weak or missing

        Return JSON in this EXACT format:
        {
            "template_id": "\(template.id)",
            "fit_score": 85,
            "chunk_mapping": {
                "0": {
                    "content": "extracted content for chunk 0",
                    "confidence": 90
                },
                "1": {
                    "content": "extracted content for chunk 1",
                    "confidence": 75
                }
            },
            "weak_chunks": [3],
            "overall_confidence": 82
        }

        Include ALL chunks in chunk_mapping: [\(chunkIndices)]
        If a chunk has no content, use empty string and confidence 0.
        """

        let systemPrompt = """
        You are an expert script structure analyzer. Your job is to map content to template chunks discovered from real video analysis.
        Extract the most relevant content from the ramblings for each chunk.
        Be specific - quote or closely paraphrase the actual content, don't summarize.
        Confidence should reflect how naturally the content fits the chunk's typical role and expected tags.

        Respond in valid JSON format only. No markdown, no explanation.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 4000]
        )

        return parseStep4Response(response: response, template: template)
    }

    private func parseStep4Response(response: String, template: StructuralTemplate) -> ReFitResult? {
        guard let jsonData = extractJSON(from: response) else {
            print("Step 4: Failed to extract JSON from response")
            return createFallbackStep4Result(template: template, rawResponse: response)
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return createFallbackStep4Result(template: template, rawResponse: response)
            }

            let fitScore = json["fit_score"] as? Int ?? 0
            let weakChunksRaw = json["weak_chunks"] as? [Any] ?? []
            let weakChunks = weakChunksRaw.compactMap { item -> Int? in
                if let intVal = item as? Int { return intVal }
                if let strVal = item as? String { return Int(strVal) }
                return nil
            }
            let overallConfidence = json["overall_confidence"] as? Int ?? 0

            var chunkMapping: [Int: ChunkMapping] = [:]
            if let mappingJson = json["chunk_mapping"] as? [String: [String: Any]] {
                for (chunkIdStr, chunkData) in mappingJson {
                    guard let chunkIndex = Int(chunkIdStr) else { continue }
                    let content = chunkData["content"] as? String ?? ""
                    let confidence = chunkData["confidence"] as? Int ?? 0
                    chunkMapping[chunkIndex] = ChunkMapping(content: content, confidence: confidence)
                }
            }

            // Ensure all chunks have entries
            for chunk in template.typicalSequence where chunkMapping[chunk.chunkIndex] == nil {
                chunkMapping[chunk.chunkIndex] = ChunkMapping(content: "", confidence: 0)
            }

            return ReFitResult(
                templateId: template.id,
                templateName: template.templateName,
                template: template,
                fitScore: fitScore,
                chunkMapping: chunkMapping,
                weakChunks: weakChunks,
                overallConfidence: overallConfidence,
                rawResponse: response
            )

        } catch {
            print("Step 4: Failed to parse JSON: \(error)")
            return createFallbackStep4Result(template: template, rawResponse: response)
        }
    }

    private func createFallbackStep4Result(template: StructuralTemplate, rawResponse: String) -> ReFitResult {
        var chunkMapping: [Int: ChunkMapping] = [:]
        for chunk in template.typicalSequence {
            chunkMapping[chunk.chunkIndex] = ChunkMapping(content: "", confidence: 0)
        }

        return ReFitResult(
            templateId: template.id,
            templateName: template.templateName,
            template: template,
            fitScore: 0,
            chunkMapping: chunkMapping,
            weakChunks: template.typicalSequence.map { $0.chunkIndex },
            overallConfidence: 0,
            rawResponse: rawResponse
        )
    }

    // MARK: - Step 5: Evaluation & Ranking (1 AI Call)

    /// Run Step 5: Evaluate and rank all templates
    func step5EvaluateAndRank(
        step4Results: Step4Results
    ) async -> EvaluationResult {
        isProcessing = true
        currentPhase = "Step 5: Evaluating and ranking..."

        // Build summary of all results
        var resultsSummary = ""
        for result in step4Results.results {
            resultsSummary += """
            ---
            Template: \(result.templateName) (ID: \(result.templateId))
            Based on: \(result.template.videoCount) real videos
            Fit Score: \(result.fitScore)
            Overall Confidence: \(result.overallConfidence)
            Weak Chunks: \(result.weakChunks.map { String($0) }.joined(separator: ", "))
            Chunk Details:
            """
            for chunk in result.template.typicalSequence {
                if let mapping = result.chunkMapping[chunk.chunkIndex] {
                    let status = mapping.confidence > 50 ? "STRONG" : (mapping.confidence > 0 ? "WEAK" : "EMPTY")
                    resultsSummary += "\n  - Chunk \(chunk.chunkIndex) \"\(chunk.typicalRole)\": \(status) (\(mapping.confidence)%)"
                    if !mapping.content.isEmpty {
                        let preview = String(mapping.content.prefix(80))
                        resultsSummary += " - \"\(preview)...\""
                    }
                }
            }
            resultsSummary += "\n\n"
        }

        let prompt = """
        Here are fit results for the same content against \(step4Results.results.count) different templates:

        \(resultsSummary)

        These templates were discovered from analyzing REAL YouTube videos - they represent actual structural patterns creators use.

        Evaluate and rank them considering:
        1. Fit score (how much content mapped)
        2. Chunk confidence (how naturally did content fit each chunk's typical role)
        3. Weak chunks (how many gaps remain)
        4. Template-content alignment (does this template's DNA match what the content naturally IS)

        Return ranked list with reasoning for top 3.
        Flag if no template fits well (all below threshold of 60%).

        Return JSON in this EXACT format:
        {
            "ranked_templates": [
                {
                    "rank": 1,
                    "template_id": "...",
                    "template_name": "...",
                    "fit_score": 94,
                    "reasoning": "Best fit because..."
                },
                {
                    "rank": 2,
                    "template_id": "...",
                    "template_name": "...",
                    "fit_score": 87,
                    "reasoning": "Second best because..."
                },
                {
                    "rank": 3,
                    "template_id": "...",
                    "template_name": "...",
                    "fit_score": 71,
                    "reasoning": "Third option because..."
                }
            ],
            "recommendation": "template_id of rank 1",
            "confidence": "high",
            "warnings": ["any concerns about the fit"]
        }

        confidence must be one of: "high", "medium", "low"
        """

        let systemPrompt = """
        You are an expert script structure evaluator.
        Focus on how NATURALLY the content fits each template, not just coverage.
        A template with 80% fit where content flows naturally is better than 90% where content feels forced.
        Be honest about weaknesses - if no template is a great fit, say so in warnings.

        Respond in valid JSON format only. No markdown, no explanation.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.2, "max_tokens": 2000]
        )

        isProcessing = false
        currentPhase = ""

        return parseStep5Response(response: response)
    }

    private func parseStep5Response(response: String) -> EvaluationResult {
        guard let jsonData = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return EvaluationResult(
                rankedTemplates: [],
                recommendation: "",
                confidence: .low,
                warnings: ["Failed to parse evaluation response"],
                rawResponse: response
            )
        }

        var rankedTemplates: [RankedTemplate] = []
        if let ranked = json["ranked_templates"] as? [[String: Any]] {
            for item in ranked {
                rankedTemplates.append(RankedTemplate(
                    rank: item["rank"] as? Int ?? 0,
                    templateId: item["template_id"] as? String ?? "",
                    templateName: item["template_name"] as? String ?? "",
                    fitScore: item["fit_score"] as? Int ?? 0,
                    reasoning: item["reasoning"] as? String ?? ""
                ))
            }
        }

        let recommendation = json["recommendation"] as? String ?? ""
        let confidenceStr = json["confidence"] as? String ?? "low"
        let confidence = ConfidenceLevel(rawValue: confidenceStr) ?? .low
        let warnings = json["warnings"] as? [String] ?? []

        return EvaluationResult(
            rankedTemplates: rankedTemplates.sorted { $0.rank < $1.rank },
            recommendation: recommendation,
            confidence: confidence,
            warnings: warnings,
            rawResponse: response
        )
    }

    // MARK: - Utilities

    private func extractJSON(from text: String) -> Data? {
        var jsonString = text

        // Remove markdown code blocks
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            jsonString = String(text[start.upperBound..<end.lowerBound])
        } else if let start = text.range(of: "```"),
                  let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            jsonString = String(text[start.upperBound..<end.lowerBound])
        }

        // Try to find JSON object
        if let startBrace = jsonString.firstIndex(of: "{"),
           let endBrace = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[startBrace...endBrace])
        }

        return jsonString.data(using: .utf8)
    }
}
