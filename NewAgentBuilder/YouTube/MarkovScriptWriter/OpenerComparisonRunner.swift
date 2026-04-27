//
//  OpenerComparisonRunner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  Wave-based async executor for running all 10 opener comparison methods.
//  Manages dependency graph: Wave 1 (independent), Wave 2 (needs M1 / call-1 outputs), Wave 3 (final drafts for M8/M9/M10).
//

import Foundation

@MainActor
class OpenerComparisonRunner {

    // MARK: - Inputs

    let model: AIModel
    let strategy: OpenerStrategy
    let matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    let filteredGists: [RamblingGist]
    let enabledMethods: Set<OpenerMethod>

    /// Structured inputs for S-methods (nil when only M-methods are enabled).
    let structuredBundle: StructuredInputBundle?

    /// Which fingerprint types to run for S-methods (subset of available).
    let enabledFingerprintTypes: Set<FingerprintPromptType>

    // MARK: - Progress

    var onProgress: ((String, OpenerMethod?, MethodRunStatus) -> Void)?

    // MARK: - Init

    init(
        model: AIModel,
        strategy: OpenerStrategy,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist],
        enabledMethods: Set<OpenerMethod>,
        structuredBundle: StructuredInputBundle? = nil,
        enabledFingerprintTypes: Set<FingerprintPromptType> = Set(FingerprintPromptType.allCases)
    ) {
        self.model = model
        self.strategy = strategy
        self.matchOpenings = matchOpenings
        self.filteredGists = filteredGists
        self.enabledMethods = enabledMethods
        self.structuredBundle = structuredBundle
        self.enabledFingerprintTypes = enabledFingerprintTypes
    }

    // MARK: - Run

    func run() async -> OpenerStrategyComparisonRun {
        var strategyRun = OpenerStrategyComparisonRun(
            strategyId: strategy.strategyId,
            strategyName: strategy.strategyName
        )

        // Determine which methods to actually run (including implicit dependencies)
        let methodsToRun = resolveMethodsToRun()

        // ═══════════════════════════════════════════
        // WAVE 1: Independent methods + first calls of multi-call methods
        // M1, M3, M5-call-1, M6-call-1, M7-call-1, M8-call-1
        // ═══════════════════════════════════════════

        report("Wave 1: Starting independent calls...", nil, .running)

        var m1Result: OpenerMethodResult?
        var m3Result: OpenerMethodResult?
        var m5ExtractedRules: String = ""
        var m6VoiceAnalysis: String = ""
        var m7SentenceJobs: String = ""
        var m8MechanicalSpec: String = ""
        var m9StartDraft: String = ""
        var m10StartDraft: String = ""

        // Intermediate call records for multi-call methods
        var m5Call1Record: OpenerMethodCall?
        var m6Call1Record: OpenerMethodCall?
        var m7Call1Record: OpenerMethodCall?
        var m8Call1Record: OpenerMethodCall?
        var m9Call1Record: OpenerMethodCall?
        var m10Call1Record: OpenerMethodCall?

        await withTaskGroup(of: (String, Any?).self) { group in

            // M1: Baseline Draft
            if methodsToRun.contains(.m1_baselineDraft) {
                group.addTask { [self] in
                    await self.report("M1: Drafting...", .m1_baselineDraft, .running)
                    let result = await self.runM1()
                    return ("m1", result)
                }
            }

            // M3: Cognitive Scaffolding
            if methodsToRun.contains(.m3_cognitiveScaffolding) {
                group.addTask { [self] in
                    await self.report("M3: Cognitive scaffolding...", .m3_cognitiveScaffolding, .running)
                    let result = await self.runM3()
                    return ("m3", result)
                }
            }

            // M5-call-1: Extract Rules
            if methodsToRun.contains(.m5_spoonFedRules) {
                group.addTask { [self] in
                    await self.report("M5: Extracting rules...", .m5_spoonFedRules, .running)
                    let (rules, call) = await self.runM5Call1()
                    return ("m5c1", (rules, call))
                }
            }

            // M6-call-1: Voice Analysis
            if methodsToRun.contains(.m6_twoCallAnalysis) {
                group.addTask { [self] in
                    await self.report("M6: Analyzing voice...", .m6_twoCallAnalysis, .running)
                    let (analysis, call) = await self.runM6Call1()
                    return ("m6c1", (analysis, call))
                }
            }

            // M7-call-1: Extract Sentence Jobs
            if methodsToRun.contains(.m7_sentenceFunction) {
                group.addTask { [self] in
                    await self.report("M7: Extracting sentence jobs...", .m7_sentenceFunction, .running)
                    let (jobs, call) = await self.runM7Call1()
                    return ("m7c1", (jobs, call))
                }
            }

            // M8-call-1: Mechanical Spec
            if methodsToRun.contains(.m8_mechanical3Phase) {
                group.addTask { [self] in
                    await self.report("M8: Extracting mechanical spec...", .m8_mechanical3Phase, .running)
                    let (spec, call) = await self.runM8Call1()
                    return ("m8c1", (spec, call))
                }
            }

            // M9-call-1: M3 Draft (Start)
            if methodsToRun.contains(.m9_analyzeThenFixM3) {
                group.addTask { [self] in
                    await self.report("M9: Generating M3 draft...", .m9_analyzeThenFixM3, .running)
                    let (draft, call) = await self.runM9Call1()
                    return ("m9c1", (draft, call))
                }
            }

            // M10-call-1: M1 Draft (Start)
            if methodsToRun.contains(.m10_analyzeThenFixM1) {
                group.addTask { [self] in
                    await self.report("M10: Generating M1 draft...", .m10_analyzeThenFixM1, .running)
                    let (draft, call) = await self.runM10Call1()
                    return ("m10c1", (draft, call))
                }
            }

            for await (key, value) in group {
                switch key {
                case "m1":
                    m1Result = value as? OpenerMethodResult
                case "m3":
                    m3Result = value as? OpenerMethodResult
                case "m5c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m5ExtractedRules = tuple.0
                        m5Call1Record = tuple.1
                    }
                case "m6c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m6VoiceAnalysis = tuple.0
                        m6Call1Record = tuple.1
                    }
                case "m7c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m7SentenceJobs = tuple.0
                        m7Call1Record = tuple.1
                    }
                case "m8c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m8MechanicalSpec = tuple.0
                        m8Call1Record = tuple.1
                    }
                case "m9c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m9StartDraft = tuple.0
                        m9Call1Record = tuple.1
                    }
                case "m10c1":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m10StartDraft = tuple.0
                        m10Call1Record = tuple.1
                    }
                default: break
                }
            }
        }

        // Store Wave 1 complete results
        if let r = m1Result {
            strategyRun.methodResults.append(r)
            report("M1: Done", .m1_baselineDraft, r.status)
        }
        if let r = m3Result {
            strategyRun.methodResults.append(r)
            report("M3: Done", .m3_cognitiveScaffolding, r.status)
        }

        let m1DraftText = m1Result?.outputText ?? ""

        // ═══════════════════════════════════════════
        // M11: Detached task — runs 6 sequential calls in parallel with Waves 2-3
        // Launched here because it only needs M1, and shouldn't block other waves
        // ═══════════════════════════════════════════

        var m11Task: Task<OpenerMethodResult?, Never>? = nil
        if methodsToRun.contains(.m11_iterativeRefinement) && !m1DraftText.isEmpty {
            m11Task = Task { [self] in
                await self.report("M11: Starting iterative refinement...", .m11_iterativeRefinement, .running)
                return await self.runM11(m1Draft: m1DraftText)
            }
        }

        // ═══════════════════════════════════════════
        // S-METHODS: Detached tasks — each runs 6 fingerprint variants sequentially.
        // The 4 S-methods run in parallel with each other and with M-method Waves 2-3.
        // ═══════════════════════════════════════════

        var sMethodTasks: [Task<[OpenerMethodResult], Never>] = []

        if let bundle = structuredBundle {
            let availableFPTypes = bundle.availableFingerprintTypes.filter { enabledFingerprintTypes.contains($0) }

            let sMethods: [OpenerMethod] = [
                .s1_singlePassStructured,
                .s2_sentenceBySentence,
                .s3_draftThenFix,
                .s4_specFirstGeneration,
                .s5_skeletonDriven
            ]

            for sMethod in sMethods {
                guard methodsToRun.contains(sMethod) else { continue }

                if sMethod == .s5_skeletonDriven {
                    // S5 doesn't use fingerprints — run 3 independent variants
                    let task = Task { [self] () -> [OpenerMethodResult] in
                        var results: [OpenerMethodResult] = []
                        for i in 1...3 {
                            await self.report("S5 #\(i): Running...", .s5_skeletonDriven, .running)
                            let result = await self.runS5(bundle: bundle, runIndex: i)
                            results.append(result)
                            await self.report("S5 #\(i): Done", .s5_skeletonDriven, .running)
                        }
                        return results
                    }
                    sMethodTasks.append(task)
                } else {
                    // S1-S4: run once per fingerprint variant
                    let task = Task { [self] () -> [OpenerMethodResult] in
                        var results: [OpenerMethodResult] = []
                        for fpType in availableFPTypes {
                            await self.report("\(sMethod.rawValue) [\(fpType.shortLabel)]: Running...", sMethod, .running)
                            let result: OpenerMethodResult
                            switch sMethod {
                            case .s1_singlePassStructured:
                                result = await self.runS1(bundle: bundle, fingerprintType: fpType)
                            case .s2_sentenceBySentence:
                                result = await self.runS2(bundle: bundle, fingerprintType: fpType)
                            case .s3_draftThenFix:
                                result = await self.runS3(bundle: bundle, fingerprintType: fpType)
                            case .s4_specFirstGeneration:
                                result = await self.runS4(bundle: bundle, fingerprintType: fpType)
                            default:
                                continue
                            }
                            results.append(result)
                            await self.report("\(sMethod.rawValue) [\(fpType.shortLabel)]: Done", sMethod, .running)
                        }
                        return results
                    }
                    sMethodTasks.append(task)
                }
            }
        }

        // ═══════════════════════════════════════════
        // WAVE 2: Methods needing M1 + multi-call continuations
        // M2, M4, M5-call-2, M6-call-2, M7-call-2, M8-call-2
        // ═══════════════════════════════════════════

        report("Wave 2: Starting dependent calls...", nil, .running)

        var m2Result: OpenerMethodResult?
        var m4Result: OpenerMethodResult?
        var m5Result: OpenerMethodResult?
        var m6Result: OpenerMethodResult?
        var m7Result: OpenerMethodResult?
        var m8ContentMap: String = ""
        var m8Call2Record: OpenerMethodCall?
        var m9Analysis: String = ""
        var m9FixList: String = ""
        var m9Call2Record: OpenerMethodCall?
        var m10Analysis: String = ""
        var m10FixList: String = ""
        var m10Call2Record: OpenerMethodCall?

        await withTaskGroup(of: (String, Any?).self) { group in

            // M2: Voice-Matched Rewrite (needs M1)
            if methodsToRun.contains(.m2_voiceRewrite) && !m1DraftText.isEmpty {
                group.addTask { [self] in
                    await self.report("M2: Rewriting...", .m2_voiceRewrite, .running)
                    let result = await self.runM2(draftText: m1DraftText)
                    return ("m2", result)
                }
            }

            // M4: Analysis-First Rewrite (needs M1)
            if methodsToRun.contains(.m4_analysisRewrite) && !m1DraftText.isEmpty {
                group.addTask { [self] in
                    await self.report("M4: Analysis rewrite...", .m4_analysisRewrite, .running)
                    let result = await self.runM4(draftText: m1DraftText)
                    return ("m4", result)
                }
            }

            // M5-call-2: Apply Rules (needs M1 + rules)
            if methodsToRun.contains(.m5_spoonFedRules) && !m1DraftText.isEmpty && !m5ExtractedRules.isEmpty {
                group.addTask { [self] in
                    await self.report("M5: Applying rules...", .m5_spoonFedRules, .running)
                    let result = await self.runM5Call2(
                        draftText: m1DraftText,
                        extractedRules: m5ExtractedRules,
                        call1Record: m5Call1Record
                    )
                    return ("m5", result)
                }
            }

            // M6-call-2: Constrained Rewrite (needs M1 + analysis)
            if methodsToRun.contains(.m6_twoCallAnalysis) && !m1DraftText.isEmpty && !m6VoiceAnalysis.isEmpty {
                group.addTask { [self] in
                    await self.report("M6: Constrained rewrite...", .m6_twoCallAnalysis, .running)
                    let result = await self.runM6Call2(
                        draftText: m1DraftText,
                        voiceAnalysis: m6VoiceAnalysis,
                        call1Record: m6Call1Record
                    )
                    return ("m6", result)
                }
            }

            // M7-call-2: Execute Jobs (needs jobs)
            if methodsToRun.contains(.m7_sentenceFunction) && !m7SentenceJobs.isEmpty {
                group.addTask { [self] in
                    await self.report("M7: Executing sentence jobs...", .m7_sentenceFunction, .running)
                    let result = await self.runM7Call2(
                        sentenceJobs: m7SentenceJobs,
                        call1Record: m7Call1Record
                    )
                    return ("m7", result)
                }
            }

            // M8-call-2: Content Map (needs spec)
            if methodsToRun.contains(.m8_mechanical3Phase) && !m8MechanicalSpec.isEmpty {
                group.addTask { [self] in
                    await self.report("M8: Building content map...", .m8_mechanical3Phase, .running)
                    let (map, call) = await self.runM8Call2(mechanicalSpec: m8MechanicalSpec)
                    return ("m8c2", (map, call))
                }
            }

            // M9-call-2: Analyze M3 draft
            if methodsToRun.contains(.m9_analyzeThenFixM3) && !m9StartDraft.isEmpty {
                group.addTask { [self] in
                    await self.report("M9: Analyzing draft...", .m9_analyzeThenFixM3, .running)
                    let (analysis, fixList, call) = await self.runM9Call2(startDraft: m9StartDraft)
                    return ("m9c2", (analysis, fixList, call))
                }
            }

            // M10-call-2: Analyze M1 draft
            if methodsToRun.contains(.m10_analyzeThenFixM1) && !m10StartDraft.isEmpty {
                group.addTask { [self] in
                    await self.report("M10: Analyzing draft...", .m10_analyzeThenFixM1, .running)
                    let (analysis, fixList, call) = await self.runM10Call2(startDraft: m10StartDraft)
                    return ("m10c2", (analysis, fixList, call))
                }
            }

            for await (key, value) in group {
                switch key {
                case "m2": m2Result = value as? OpenerMethodResult
                case "m4": m4Result = value as? OpenerMethodResult
                case "m5": m5Result = value as? OpenerMethodResult
                case "m6": m6Result = value as? OpenerMethodResult
                case "m7": m7Result = value as? OpenerMethodResult
                case "m8c2":
                    if let tuple = value as? (String, OpenerMethodCall?) {
                        m8ContentMap = tuple.0
                        m8Call2Record = tuple.1
                    }
                case "m9c2":
                    if let tuple = value as? (String, String, OpenerMethodCall?) {
                        m9Analysis = tuple.0
                        m9FixList = tuple.1
                        m9Call2Record = tuple.2
                    }
                case "m10c2":
                    if let tuple = value as? (String, String, OpenerMethodCall?) {
                        m10Analysis = tuple.0
                        m10FixList = tuple.1
                        m10Call2Record = tuple.2
                    }
                default: break
                }
            }
        }

        // Store Wave 2 results
        for result in [m2Result, m4Result, m5Result, m6Result, m7Result].compactMap({ $0 }) {
            strategyRun.methodResults.append(result)
            report("\(result.method.rawValue): Done", result.method, result.status)
        }

        // ═══════════════════════════════════════════
        // WAVE 3: Final drafts — M8-call-3, M9-call-3, M10-call-3 (parallel)
        // ═══════════════════════════════════════════

        let needsM8Wave3 = methodsToRun.contains(.m8_mechanical3Phase) && !m8MechanicalSpec.isEmpty && !m8ContentMap.isEmpty
        let needsM9Wave3 = methodsToRun.contains(.m9_analyzeThenFixM3) && !m9StartDraft.isEmpty && !m9Analysis.isEmpty
        let needsM10Wave3 = methodsToRun.contains(.m10_analyzeThenFixM1) && !m10StartDraft.isEmpty && !m10Analysis.isEmpty

        if needsM8Wave3 || needsM9Wave3 || needsM10Wave3 {
            report("Wave 3: Final drafts...", nil, .running)

            await withTaskGroup(of: (String, Any?).self) { group in
                if needsM8Wave3 {
                    group.addTask { [self] in
                        await self.report("M8: Writing final draft...", .m8_mechanical3Phase, .running)
                        let result = await self.runM8Call3(
                            mechanicalSpec: m8MechanicalSpec,
                            contentMap: m8ContentMap,
                            call1Record: m8Call1Record,
                            call2Record: m8Call2Record
                        )
                        return ("m8", result)
                    }
                }

                if needsM9Wave3 {
                    group.addTask { [self] in
                        await self.report("M9: Fixing draft...", .m9_analyzeThenFixM3, .running)
                        let result = await self.runM9Call3(
                            startDraft: m9StartDraft,
                            analysis: m9Analysis,
                            fixPriorityList: m9FixList,
                            call1Record: m9Call1Record,
                            call2Record: m9Call2Record
                        )
                        return ("m9", result)
                    }
                }

                if needsM10Wave3 {
                    group.addTask { [self] in
                        await self.report("M10: Fixing draft...", .m10_analyzeThenFixM1, .running)
                        let result = await self.runM10Call3(
                            startDraft: m10StartDraft,
                            analysis: m10Analysis,
                            fixPriorityList: m10FixList,
                            call1Record: m10Call1Record,
                            call2Record: m10Call2Record
                        )
                        return ("m10", result)
                    }
                }

                for await (key, value) in group {
                    if let result = value as? OpenerMethodResult {
                        strategyRun.methodResults.append(result)
                        report("\(result.method.rawValue): Done", result.method, result.status)
                    }
                }
            }
        }

        // ═══════════════════════════════════════════
        // Collect M11 (may still be running its 6 sequential calls)
        // ═══════════════════════════════════════════

        if let task = m11Task {
            if let result = await task.value {
                strategyRun.methodResults.append(result)
                report("M11: Done", .m11_iterativeRefinement, result.status)
            }
        }

        // ═══════════════════════════════════════════
        // Collect S-method results
        // ═══════════════════════════════════════════

        for task in sMethodTasks {
            let results = await task.value
            for result in results {
                strategyRun.methodResults.append(result)
                report("\(result.displayLabel): Done", result.method, result.status)
            }
        }

        return strategyRun
    }

    // MARK: - Individual Method Runners

    private func runM1() async -> OpenerMethodResult {
        let (system, user) = OpenerMatcherPromptEngine.buildFilteredDraftPrompt(
            strategy: strategy,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 2000, callIndex: 0, callLabel: "Draft")

        var result = OpenerMethodResult(method: .m1_baselineDraft, strategyId: strategy.strategyId, outputText: call.outputText, calls: [call], status: .completed)
        result.finalize(cost: computeCost(calls: [call]))
        return result
    }

    private func runM2(draftText: String) async -> OpenerMethodResult {
        let (system, user) = OpenerMatcherPromptEngine.buildRewritePrompt(
            draftText: draftText,
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 4000, callIndex: 0, callLabel: "Rewrite")

        let parsed = OpenerMatcherPromptEngine.parseM2Response(rawResponse: call.rawResponse)
        var intermediates: [String: String] = ["voiceAnalysis": parsed.voiceAnalysis]
        if !parsed.narrativeModeRepair.isEmpty {
            intermediates["narrativeModeRepair"] = parsed.narrativeModeRepair
        }
        if !parsed.annotatedDraft.isEmpty {
            intermediates["annotatedDraft"] = parsed.annotatedDraft
        }
        var result = OpenerMethodResult(
            method: .m2_voiceRewrite,
            strategyId: strategy.strategyId,
            outputText: parsed.rewriteText,
            intermediateOutputs: intermediates,
            calls: [call],
            status: .completed
        )
        result.finalize(cost: computeCost(calls: [call]))
        return result
    }

    private func runM3() async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildCognitiveScaffoldingPrompt(
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 3000, callIndex: 0, callLabel: "Cognitive Scaffolding")

        let parsed = OpenerComparisonPromptEngine.parseCognitiveScaffoldingResponse(call.rawResponse)
        var result = OpenerMethodResult(
            method: .m3_cognitiveScaffolding,
            strategyId: strategy.strategyId,
            outputText: parsed.opening,
            intermediateOutputs: ["analysis": parsed.analysis],
            calls: [call],
            status: .completed
        )
        result.finalize(cost: computeCost(calls: [call]))
        return result
    }

    private func runM4(draftText: String) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildAnalysisRewritePrompt(
            draftText: draftText,
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 3000, callIndex: 0, callLabel: "Analysis Rewrite")

        let parsed = OpenerComparisonPromptEngine.parseAnalysisRewriteResponse(call.rawResponse)
        var result = OpenerMethodResult(
            method: .m4_analysisRewrite,
            strategyId: strategy.strategyId,
            outputText: parsed.rewriteText.isEmpty ? call.outputText : parsed.rewriteText,
            intermediateOutputs: parsed.analysis.isEmpty ? [:] : ["mechanicalAnalysis": parsed.analysis],
            calls: [call],
            status: .completed
        )
        result.finalize(cost: computeCost(calls: [call]))
        return result
    }

    // M5 split into two functions for wave execution
    private func runM5Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildRuleExtractionPrompt(
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 2000, callIndex: 0, callLabel: "Extract Rules")
        return (call.outputText, call)
    }

    private func runM5Call2(draftText: String, extractedRules: String, call1Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildRuleApplicationPrompt(
            draftText: draftText,
            extractedRules: extractedRules
        )
        let call2 = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 3000, callIndex: 1, callLabel: "Apply Rules")

        // Parse for ## RULE VIOLATIONS / ## REWRITTEN OPENING markers
        let parsed = OpenerComparisonPromptEngine.parseRuleApplicationResponse(call2.rawResponse)
        let allCalls = [call1Record, call2].compactMap { $0 }

        var result = OpenerMethodResult(
            method: .m5_spoonFedRules,
            strategyId: strategy.strategyId,
            outputText: parsed.rewriteText.isEmpty ? call2.outputText : parsed.rewriteText,
            intermediateOutputs: [
                "extractedRules": extractedRules,
                "ruleViolations": parsed.ruleViolations
            ],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // M6 split
    private func runM6Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildVoiceAnalysisPrompt(
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 2000, callIndex: 0, callLabel: "Voice Analysis")
        return (call.outputText, call)
    }

    private func runM6Call2(draftText: String, voiceAnalysis: String, call1Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildConstrainedRewritePrompt(
            draftText: draftText,
            voiceAnalysis: voiceAnalysis,
            matchOpenings: matchOpenings
        )
        let call2 = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 3000, callIndex: 1, callLabel: "Constrained Rewrite")

        let allCalls = [call1Record, call2].compactMap { $0 }
        var result = OpenerMethodResult(
            method: .m6_twoCallAnalysis,
            strategyId: strategy.strategyId,
            outputText: call2.outputText,
            intermediateOutputs: ["voiceAnalysis": voiceAnalysis],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // M7 split
    private func runM7Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildSentenceJobExtractionPrompt(
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 2000, callIndex: 0, callLabel: "Extract Sentence Jobs")
        return (call.outputText, call)
    }

    private func runM7Call2(sentenceJobs: String, call1Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildSentenceJobExecutionPrompt(
            sentenceJobs: sentenceJobs,
            filteredGists: filteredGists,
            matchOpenings: matchOpenings
        )
        let call2 = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 2000, callIndex: 1, callLabel: "Execute Jobs")

        let allCalls = [call1Record, call2].compactMap { $0 }
        var result = OpenerMethodResult(
            method: .m7_sentenceFunction,
            strategyId: strategy.strategyId,
            outputText: call2.outputText,
            intermediateOutputs: ["sentenceJobs": sentenceJobs],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // M8 three calls
    private func runM8Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildMechanicalSpecPrompt(
            matchOpenings: matchOpenings
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 2000, callIndex: 0, callLabel: "Mechanical Spec")
        return (call.outputText, call)
    }

    private func runM8Call2(mechanicalSpec: String) async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildContentMapPrompt(
            mechanicalSpec: mechanicalSpec,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 2000, callIndex: 1, callLabel: "Content Map")
        return (call.outputText, call)
    }

    private func runM8Call3(mechanicalSpec: String, contentMap: String, call1Record: OpenerMethodCall?, call2Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildMechanicalDraftPrompt(
            mechanicalSpec: mechanicalSpec,
            contentMap: contentMap,
            matchOpenings: matchOpenings
        )
        let call3 = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 2000, callIndex: 2, callLabel: "Mechanical Draft")

        let allCalls = [call1Record, call2Record, call3].compactMap { $0 }
        var result = OpenerMethodResult(
            method: .m8_mechanical3Phase,
            strategyId: strategy.strategyId,
            outputText: call3.outputText,
            intermediateOutputs: [
                "mechanicalSpec": mechanicalSpec,
                "contentMap": contentMap
            ],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - M9: Analyze-Then-Fix (M3 Start)

    /// M9-call-1: Generate start draft using M3's Cognitive Scaffolding prompt.
    private func runM9Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildCognitiveScaffoldingPrompt(
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 3000, callIndex: 0, callLabel: "M3 Draft (Start)")

        // Only capture the ## OPENING section, discard ## ANALYSIS
        let parsed = OpenerComparisonPromptEngine.parseCognitiveScaffoldingResponse(call.rawResponse)
        return (parsed.opening.isEmpty ? call.outputText : parsed.opening, call)
    }

    /// M9-call-2: Analyze the start draft against templates.
    private func runM9Call2(startDraft: String) async -> (String, String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildAnalyzeDraftPrompt(
            draftText: startDraft,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 3000, callIndex: 1, callLabel: "Analyze Draft")

        let parsed = OpenerComparisonPromptEngine.parseAnalyzeDraftResponse(call.rawResponse)
        return (parsed.fullAnalysis, parsed.fixPriorityList, call)
    }

    /// M9-call-3: Execute atomic fixes from the priority list (not full analysis).
    private func runM9Call3(startDraft: String, analysis: String, fixPriorityList: String, call1Record: OpenerMethodCall?, call2Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildFixDraftPrompt(
            draftText: startDraft,
            fixPriorityList: fixPriorityList,
            matchOpenings: matchOpenings
        )
        let call3 = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 2000, callIndex: 2, callLabel: "Fix Draft")

        let parsed = OpenerComparisonPromptEngine.parseFixDraftResponse(call3.rawResponse)

        let allCalls = [call1Record, call2Record, call3].compactMap { $0 }
        var result = OpenerMethodResult(
            method: .m9_analyzeThenFixM3,
            strategyId: strategy.strategyId,
            outputText: parsed.fixedScript.isEmpty ? call3.outputText : parsed.fixedScript,
            intermediateOutputs: [
                "startDraft": startDraft,
                "analysis": analysis,
                "fixPriorityList": fixPriorityList,
                "verification": parsed.verification
            ],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - M10: Analyze-Then-Fix (M1 Start)

    /// M10-call-1: Generate start draft using M1's Baseline Draft prompt.
    private func runM10Call1() async -> (String, OpenerMethodCall?) {
        let (system, user) = OpenerMatcherPromptEngine.buildFilteredDraftPrompt(
            strategy: strategy,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 2000, callIndex: 0, callLabel: "M1 Draft (Start)")
        return (call.outputText, call)
    }

    /// M10-call-2: Analyze the start draft against templates.
    private func runM10Call2(startDraft: String) async -> (String, String, OpenerMethodCall?) {
        let (system, user) = OpenerComparisonPromptEngine.buildAnalyzeDraftPrompt(
            draftText: startDraft,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.2, maxTokens: 3000, callIndex: 1, callLabel: "Analyze Draft")

        let parsed = OpenerComparisonPromptEngine.parseAnalyzeDraftResponse(call.rawResponse)
        return (parsed.fullAnalysis, parsed.fixPriorityList, call)
    }

    /// M10-call-3: Execute atomic fixes from the priority list (not full analysis).
    private func runM10Call3(startDraft: String, analysis: String, fixPriorityList: String, call1Record: OpenerMethodCall?, call2Record: OpenerMethodCall?) async -> OpenerMethodResult {
        let (system, user) = OpenerComparisonPromptEngine.buildFixDraftPrompt(
            draftText: startDraft,
            fixPriorityList: fixPriorityList,
            matchOpenings: matchOpenings
        )
        let call3 = await callLLM(system: system, user: user, temperature: 0.3, maxTokens: 2000, callIndex: 2, callLabel: "Fix Draft")

        let parsed = OpenerComparisonPromptEngine.parseFixDraftResponse(call3.rawResponse)

        let allCalls = [call1Record, call2Record, call3].compactMap { $0 }
        var result = OpenerMethodResult(
            method: .m10_analyzeThenFixM1,
            strategyId: strategy.strategyId,
            outputText: parsed.fixedScript.isEmpty ? call3.outputText : parsed.fixedScript,
            intermediateOutputs: [
                "startDraft": startDraft,
                "analysis": analysis,
                "fixPriorityList": fixPriorityList,
                "verification": parsed.verification
            ],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - M11: Iterative Refinement (3 Rounds × 2 Calls)

    /// Run M11's full 6-call pipeline: 3 rounds of (diagnose → fix).
    /// Each round takes the previous round's output as input.
    private func runM11(m1Draft: String) async -> OpenerMethodResult {
        var currentDraft = m1Draft
        var allCalls: [OpenerMethodCall] = []
        var intermediates: [String: String] = ["startDraft": m1Draft]
        var callIndex = 0

        for round in 1...3 {
            // Call A: Diagnose — which sentences don't match the template voice?
            report("M11: Round \(round)/3 — diagnosing...", .m11_iterativeRefinement, .running)
            let (diagSystem, diagUser) = OpenerComparisonPromptEngine.buildIterativeDiagnosisPrompt(
                draftText: currentDraft,
                matchOpenings: matchOpenings,
                roundNumber: round
            )
            let diagCall = await callLLM(
                system: diagSystem, user: diagUser,
                temperature: 0.2, maxTokens: 2000,
                callIndex: callIndex, callLabel: "Round \(round) Diagnosis"
            )
            let diagnosis = diagCall.outputText
            allCalls.append(diagCall)
            intermediates["diagnosis\(round)"] = diagnosis
            callIndex += 1

            // Check if diagnosis says no changes needed
            if diagnosis.uppercased().contains("NO CHANGES NEEDED") {
                report("M11: Round \(round) — no changes needed, stopping early.", .m11_iterativeRefinement, .running)
                break
            }

            // Call B: Fix — apply the sentence replacements
            report("M11: Round \(round)/3 — fixing...", .m11_iterativeRefinement, .running)
            let (fixSystem, fixUser) = OpenerComparisonPromptEngine.buildIterativeFixPrompt(
                draftText: currentDraft,
                diagnosis: diagnosis,
                matchOpenings: matchOpenings
            )
            let fixCall = await callLLM(
                system: fixSystem, user: fixUser,
                temperature: 0.3, maxTokens: 2000,
                callIndex: callIndex, callLabel: "Round \(round) Fix"
            )
            let parsed = OpenerComparisonPromptEngine.parseIterativeFixResponse(fixCall.rawResponse)
            currentDraft = parsed.fixedScript.isEmpty ? fixCall.outputText : parsed.fixedScript
            allCalls.append(fixCall)
            intermediates["v\(round + 1)"] = currentDraft
            if !parsed.changesApplied.isEmpty {
                intermediates["changes\(round)"] = parsed.changesApplied
            }
            callIndex += 1
        }

        var result = OpenerMethodResult(
            method: .m11_iterativeRefinement,
            strategyId: strategy.strategyId,
            outputText: currentDraft,
            intermediateOutputs: intermediates,
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - S1: Single-Pass Structured

    private func runS1(bundle: StructuredInputBundle, fingerprintType: FingerprintPromptType) async -> OpenerMethodResult {
        let (system, user) = StructuredComparisonPromptEngine.buildS1Prompt(
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let call = await callLLM(system: system, user: user, temperature: 0.4, maxTokens: 2000, callIndex: 0, callLabel: "Single-Pass [\(fingerprintType.shortLabel)]")

        var result = OpenerMethodResult(
            method: .s1_singlePassStructured,
            strategyId: strategy.strategyId,
            fingerprintVariant: fingerprintType,
            outputText: call.outputText,
            intermediateOutputs: ["structuralSpec": StructuredComparisonPromptEngine.buildStructuralSpec(bundle: bundle)],
            calls: [call],
            status: .completed
        )
        result.finalize(cost: computeCost(calls: [call]))
        return result
    }

    // MARK: - S2: Sentence-by-Sentence

    private func runS2(bundle: StructuredInputBundle, fingerprintType: FingerprintPromptType) async -> OpenerMethodResult {
        var allCalls: [OpenerMethodCall] = []
        var previousSentences: [String] = []
        var intermediates: [String: String] = [:]

        let sentenceCount = bundle.targetSentenceCount

        for i in 0..<sentenceCount {
            let (system, user) = StructuredComparisonPromptEngine.buildS2SentencePrompt(
                sentenceIndex: i,
                bundle: bundle,
                fingerprintType: fingerprintType,
                matchOpenings: matchOpenings,
                filteredGists: filteredGists,
                previousSentences: previousSentences
            )
            let call = await callLLM(
                system: system, user: user,
                temperature: 0.3, maxTokens: 300,
                callIndex: i, callLabel: "Sentence \(i + 1) [\(fingerprintType.shortLabel)]"
            )

            let sentence = call.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            previousSentences.append(sentence)
            allCalls.append(call)
            intermediates["sentence_\(i + 1)"] = sentence
        }

        let finalText = previousSentences.joined(separator: " ")
        var result = OpenerMethodResult(
            method: .s2_sentenceBySentence,
            strategyId: strategy.strategyId,
            fingerprintVariant: fingerprintType,
            outputText: finalText,
            intermediateOutputs: intermediates,
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - S3: Draft-Then-Fix

    private func runS3(bundle: StructuredInputBundle, fingerprintType: FingerprintPromptType) async -> OpenerMethodResult {
        // Call 1: Generate draft
        let (draftSystem, draftUser) = StructuredComparisonPromptEngine.buildS3DraftPrompt(
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let draftCall = await callLLM(
            system: draftSystem, user: draftUser,
            temperature: 0.4, maxTokens: 2000,
            callIndex: 0, callLabel: "Draft [\(fingerprintType.shortLabel)]"
        )
        let draftText = draftCall.outputText

        // Call 2: Evaluate
        let (evalSystem, evalUser) = StructuredComparisonPromptEngine.buildS3EvaluatePrompt(
            draftText: draftText,
            bundle: bundle,
            fingerprintType: fingerprintType
        )
        let evalCall = await callLLM(
            system: evalSystem, user: evalUser,
            temperature: 0.2, maxTokens: 3000,
            callIndex: 1, callLabel: "Evaluate [\(fingerprintType.shortLabel)]"
        )
        let evaluation = evalCall.outputText

        // Call 3: Fix
        let (fixSystem, fixUser) = StructuredComparisonPromptEngine.buildS3FixPrompt(
            draftText: draftText,
            evaluationFeedback: evaluation,
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings
        )
        let fixCall = await callLLM(
            system: fixSystem, user: fixUser,
            temperature: 0.3, maxTokens: 2000,
            callIndex: 2, callLabel: "Fix [\(fingerprintType.shortLabel)]"
        )

        let allCalls = [draftCall, evalCall, fixCall]
        var result = OpenerMethodResult(
            method: .s3_draftThenFix,
            strategyId: strategy.strategyId,
            fingerprintVariant: fingerprintType,
            outputText: fixCall.outputText,
            intermediateOutputs: [
                "draft": draftText,
                "evaluation": evaluation
            ],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - S4: Spec-First Generation

    private func runS4(bundle: StructuredInputBundle, fingerprintType: FingerprintPromptType) async -> OpenerMethodResult {
        // Call 1: Generate plan
        let (planSystem, planUser) = StructuredComparisonPromptEngine.buildS4PlanPrompt(
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let planCall = await callLLM(
            system: planSystem, user: planUser,
            temperature: 0.2, maxTokens: 3000,
            callIndex: 0, callLabel: "Plan [\(fingerprintType.shortLabel)]"
        )
        let plan = planCall.outputText

        // Call 2: Execute plan
        let (execSystem, execUser) = StructuredComparisonPromptEngine.buildS4ExecutePrompt(
            plan: plan,
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        let execCall = await callLLM(
            system: execSystem, user: execUser,
            temperature: 0.4, maxTokens: 2000,
            callIndex: 1, callLabel: "Execute [\(fingerprintType.shortLabel)]"
        )

        let allCalls = [planCall, execCall]
        var result = OpenerMethodResult(
            method: .s4_specFirstGeneration,
            strategyId: strategy.strategyId,
            fingerprintVariant: fingerprintType,
            outputText: execCall.outputText,
            intermediateOutputs: ["plan": plan],
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - S5: Skeleton-Driven (Lookup Table)

    private func runS5(bundle: StructuredInputBundle, runIndex: Int) async -> OpenerMethodResult {
        var allCalls: [OpenerMethodCall] = []
        var previousSentences: [String] = []
        var intermediates: [String: String] = [:]

        let sentenceCount = bundle.targetSentenceCount

        for i in 0..<sentenceCount {
            let (system, user) = StructuredComparisonPromptEngine.buildS5SentencePrompt(
                sentenceIndex: i,
                bundle: bundle,
                matchOpenings: matchOpenings,
                filteredGists: filteredGists,
                previousSentences: previousSentences
            )
            let call = await callLLM(
                system: system, user: user,
                temperature: 0.4, maxTokens: 300,
                callIndex: i, callLabel: "Sentence \(i + 1) [#\(runIndex)]"
            )

            let sentence = SkeletonComplianceService.cleanResponse(call.outputText)
            previousSentences.append(sentence)
            allCalls.append(call)
            intermediates["sentence_\(i + 1)"] = sentence

            // Validate: run hint detectors and check signature match
            let targetSig = i < bundle.targetSignatureSequence.count
                ? bundle.targetSignatureSequence[i]
                : "narrative_action"
            let parsed = ScriptFidelityService.parseSentence(text: sentence, index: i)
            let actualSig = ScriptFidelityService.extractSlotSignature(from: parsed)
            let match = actualSig == targetSig ? "MATCH" : "MISS"
            intermediates["sig_check_\(i + 1)"] = "\(match) target=\(targetSig) actual=\(actualSig) wc=\(parsed.wordCount)"
        }

        let finalText = previousSentences.joined(separator: " ")
        var result = OpenerMethodResult(
            method: .s5_skeletonDriven,
            strategyId: strategy.strategyId,
            runVariantIndex: runIndex,
            outputText: finalText,
            intermediateOutputs: intermediates,
            calls: allCalls,
            status: .completed
        )
        result.finalize(cost: computeCost(calls: allCalls))
        return result
    }

    // MARK: - LLM Call Helper

    private func callLLM(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        callIndex: Int,
        callLabel: String
    ) async -> OpenerMethodCall {
        let startTime = CFAbsoluteTimeGetCurrent()

        let adapter = ClaudeModelAdapter(model: model)
        let bundle = await adapter.generate_response_bundle(
            prompt: user,
            promptBackgroundInfo: system,
            params: ["temperature": temperature, "max_tokens": maxTokens]
        )

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        let responseText = bundle?.content ?? ""
        let telemetry = bundle.map { SectionTelemetry(from: $0) }

        return OpenerMethodCall(
            callIndex: callIndex,
            callLabel: callLabel,
            systemPrompt: system,
            userPrompt: user,
            rawResponse: responseText,
            outputText: responseText,
            telemetry: telemetry,
            durationMs: elapsed
        )
    }

    // MARK: - Helpers

    private func resolveMethodsToRun() -> Set<OpenerMethod> {
        var resolved = enabledMethods
        // Ensure dependencies are included
        for method in enabledMethods {
            for dep in method.dependencies {
                resolved.insert(dep)
            }
        }
        return resolved
    }

    private func computeCost(calls: [OpenerMethodCall]) -> Double {
        calls.compactMap { call -> Double? in
            guard let t = call.telemetry else { return nil }
            return PromptCostEstimator.instance.estimateCost(
                model: t.modelUsed,
                promptTokens: t.promptTokens,
                completionTokens: t.completionTokens
            )
        }.reduce(0, +)
    }

    private func report(_ message: String, _ method: OpenerMethod?, _ status: MethodRunStatus) {
        onProgress?(message, method, status)
    }
}
