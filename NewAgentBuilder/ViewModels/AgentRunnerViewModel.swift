//
//  AgentRunnerViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/29/25.
//


import Foundation

enum AgentRunnerMode {
    case initial
    case forking
    case extraStep
}





import Firebase
@MainActor
class AgentRunnerViewModel: ObservableObject {
    @Published var isChatMode: Bool = false
    @Published var agent: Agent
    @Published var mode: AgentRunnerMode = .initial
    @Published var userInput: String = ""
    @Published var currentStepIndex: Int = 0
    @Published var promptRuns: [PromptRun] = []
    @Published var completedRuns: [PromptRun] = []
    @Published var forkRuns: [PromptRun] = []
    @Published var allRuns: [PromptRun] = [] // ✅ Add this
    @Published var forceShowInputBar: Bool = false
    @Published var allowAutoInputBar: Bool = true
    @Published var isPromptExpanded: Bool = true
    @Published var isInputExpanded: Bool = true
    @Published var isEditingPrompt: Bool = false
    @Published var isRunningStep: Bool = false
    var sharedInput: String? = nil
    @Published var isThinking: Bool = false
    
    var chatSession: ChatSession
        
    var promptSteps: [PromptStep] {
         agent.promptSteps
     }

    var currentStep: PromptStep? {
        guard agent.promptSteps.indices.contains(currentStepIndex) else { return nil }
        return agent.promptSteps[currentStepIndex]
    }
    
    var lastRunHasNoResponse: Bool {
        guard let last = promptRuns.last else { return true }
        return last.response.isEmpty
    }
    
    var isInputBarVisible: Bool {
        (lastRunHasNoResponse && allowAutoInputBar) || forceShowInputBar
    }
    
    func extraRunsForStep(_ stepId: UUID) -> [PromptRun] {
        // Get all completed runs for this step
        let stepRuns = allRuns
            .filter { $0.promptStepId == stepId && !$0.response.isEmpty }
            .sorted(by: { $0.createdAt < $1.createdAt })

        // Identify the selected final run (last completed run)
        guard let finalRun = stepRuns.last else {
            return []
        }

        // Return all runs except the final one
        return stepRuns.filter { $0.id != finalRun.id && $0.purpose != .normal }
    }
    private let executionEngine: AgentExecutionEngine

    init(agent: Agent, session: ChatSession) {
        self.agent = agent
        self.chatSession = session
        self.isChatMode = agent.isChatAgent
        if agent.isChatAgent {
            self.forceShowInputBar = true
        }
        self.executionEngine = AgentExecutionEngine(agent: agent, session: session)
    }
//    init(agent: Agent, session: ChatSession) {
//        self.agent = agent
//        self.chatSession = session
//        self.isChatMode = agent.isChatAgent
//        if agent.isChatAgent {
//            self.forceShowInputBar = true
//        }
//    }
    func isLastStep(_ run: PromptRun) -> Bool {
        guard let lastId = agent.promptSteps.last?.id else { return false }
        return run.promptStepId == lastId
    }
    
    func loadPromptRuns() async {
        do {
            let runs = try await PromptRunManager.instance.fetchPromptRuns(for: chatSession.id)
            self.allRuns = runs.sorted(by: { $0.createdAt < $1.createdAt })
            DispatchQueue.main.async {
                // 🧩 Group runs by step
                let grouped = Dictionary(grouping: runs, by: \.promptStepId)

                var completed: [PromptRun] = []
                var forks: [PromptRun] = []
                var active: [PromptRun] = []

                var latestCompletedStepIndex: Int?

                for (stepId, stepRuns) in grouped {
                    // ⏱ Sort by creation date
                    let sorted = stepRuns.sorted(by: { $0.createdAt < $1.createdAt })
                    print("🔍 Step \(stepId) — sorted runs:")
                    // 🟢 Pull all runs with responses
                    let withResponse = sorted.filter { !$0.response.isEmpty }

                    // 🎯 If any run has no response, treat it as active
                    if let pending = sorted.first(where: { $0.response.isEmpty }) {
                        active.append(pending)

                        if let stepIndex = self.agent.promptSteps.firstIndex(where: { $0.id == stepId }) {
                            latestCompletedStepIndex = max(latestCompletedStepIndex ?? -1, stepIndex)
                        }
                    }

                    // ✅ Classify completed + fork runs
                    if let lastCompleted = withResponse.last,
                       let stepIndex = self.agent.promptSteps.firstIndex(where: { $0.id == stepId }) {
                        print("✅ Completed Run Selected: \(lastCompleted.id) | \(lastCompleted.createdAt)")
                        completed.append(lastCompleted)
                        latestCompletedStepIndex = max(latestCompletedStepIndex ?? -1, stepIndex)

                        let forkCandidates = withResponse.dropLast()
                        forks.append(contentsOf: forkCandidates)
                    }
                }

                self.completedRuns = completed.sorted { a, b in
                    guard
                        let i1 = self.agent.promptSteps.firstIndex(where: { $0.id == a.promptStepId }),
                        let i2 = self.agent.promptSteps.firstIndex(where: { $0.id == b.promptStepId })
                    else { return false }
                    return i1 < i2
                }
                self.forkRuns = forks
                self.promptRuns = active

                // 🔢 Update step index
                self.currentStepIndex = latestCompletedStepIndex ?? 0

                // 🧪 If no active run, inject a placeholder
                if self.promptRuns.isEmpty,
                   self.agent.promptSteps.indices.contains(self.currentStepIndex) {
                    let step = self.agent.promptSteps[self.currentStepIndex]
                    let placeholder = PromptRun(
                        promptStepId: step.id,
                        chatSessionId: self.chatSession.id,
                        basePrompt: step.prompt,
                        userInput: "",
                        finalPrompt: step.prompt,
                        response: "",
                        createdAt: Date(),
                        inputID: "".normalized().sha256ToUUID(),
                        purpose: .normal
                    )
                    self.promptRuns = [placeholder]
                }
                
                print("🏁 Final completedRuns order:")
                for r in completed {
                    print("   → \(r.createdAt) | \(r.id)")
                }

                print("💾 loadPromptRuns() → step \(self.currentStepIndex), promptRuns: \(self.promptRuns.count), completed: \(self.completedRuns.count), forks: \(self.forkRuns.count)")
            }

        } catch {
            print("❌ Failed to load prompt runs: \(error)")
        }
    }
    func userTappedEditInput() {
        forceShowInputBar = true
    }
    func moveToNextStep() {
        currentStepIndex += 1
        userInput = ""
       // generatedOutputs.removeAll()
        promptRuns.removeAll()
    }

    func updatePrompt(for stepId: UUID, newPrompt: String) {
        if let index = agent.promptSteps.firstIndex(where: { $0.id == stepId }) {
            agent.promptSteps[index].prompt = newPrompt
        }
    }
    
    
    func updateSessionTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        chatSession.title = trimmed

        Task {
            do {
                try await AgentManager().updateChatSessions(
                    agentId: agent.id,
                    chatSessions: agent.chatSessions.map {
                        var updated = $0
                        if updated.id == chatSession.id {
                            updated.title = trimmed
                        }
                        return updated
                    }
                )

                // 🔄 Update local state AFTER successful Firestore write
                if let index = agent.chatSessions.firstIndex(where: { $0.id == chatSession.id }) {
                    agent.chatSessions[index].title = trimmed
                }

                print("✅ Session title synced to Firestore.")
            } catch {
                print("⚠️ Firestore sync failed: \(error.localizedDescription)")
            }
        }
    }

//    func runCurrentStep(with input: String) async {
//        guard let step = currentStep else { return }
//
//        do {
//            let engine = AgentExecutionEngine(agent: agent, session: chatSession)
//            let run = try await engine.runStep(
//                step: step,
//                userInput: input,
//                sharedInput: nil
//            )
//            promptRuns.append(run)
//            allRuns.append(run)
//        } catch {
//            print("❌ Failed to run current step: \(error)")
//        }
////        userInput = input
////        guard let step = currentStep else { return }
////        let inputConsideringChunks = HTMLProcessor.instance.injectChunk(for: currentStep?.id ?? UUID(), finalInput: input, userInput: userInput)
////        do {
////            let response = try await runSmartPromptStep(
////                systemPrompt: step.prompt,
////                userInput: input,
////                stepId: currentStep?.id ?? UUID()
////            )
////
////            if let first = promptRuns.first, first.userInput.isEmpty && first.response.isEmpty {
////                promptRuns.removeFirst()
////            }
////
////            let placeholderRun = PromptRun(
////                promptStepId: step.id,
////                chatSessionId: chatSession.id,
////                basePrompt: step.prompt,
////                userInput: inputConsideringChunks,
////                finalPrompt: inputConsideringChunks + step.prompt,
////                response: "",
////                inputID: input.normalized().sha256ToUUID(),
////                purpose: .normal
////            )
////
////            let newRun = buildPromptRun(from: placeholderRun, response: response)
////            print(newRun.totalTokenCount ?? "ERRR", "Total Token Counts")
////            promptRuns.append(newRun)
////            await persist(newRun)
////            userInput = ""
////
////        } catch {
////            print("❌ Failed to run step: \(error)")
////        }
//    }
    
    
    private func persist(_ run: PromptRun) async {
        do {
               try await PromptRunManager.instance.savePromptRun(run)
           } catch {
               print("❌ Failed to save run to Firestore: \(error)")
           }
    }
    private func buildPromptRun(from run: PromptRun, response: AIResponseBundle) -> PromptRun {
        PromptRun(
            promptStepId: run.promptStepId,
            chatSessionId: run.chatSessionId,
            basePrompt: run.basePrompt,
            userInput: run.userInput,
            finalPrompt: run.basePrompt + "\n" + run.userInput,
            response: response.content,
            createdAt: Date(),
            modelUsed: response.modelUsed,
            promptTokenCount: response.promptTokens,
            completionTokenCount: response.completionTokens,
            totalTokenCount: response.totalTokens,
            finishReason: response.finishReason,
            cachedTokens: response.cachedTokens,
            inputID: run.inputID,
            purpose: run.purpose,
            imageURL: run.imageURL
        )
    }
    
    private func buildUpdatedFields(for run: PromptRun) -> [String: Any] {
        return [
            "response": run.response,
            "finalPrompt": run.finalPrompt,
            "createdAt": Timestamp(date: run.createdAt),
            "modelUsed": run.modelUsed as Any,
            "promptTokenCount": run.promptTokenCount as Any,
            "completionTokenCount": run.completionTokenCount as Any,
            "totalTokenCount": run.totalTokenCount as Any,
            "finishReason": run.finishReason as Any,
            "cachedTokens": run.cachedTokens as Any
        ]
    }



//    private func runSmartPromptStep(systemPrompt: String, userInput: String, stepId: UUID) async throws -> AIResponseBundle {
//        let engine = AIEngine()
//        isThinking = true
//        defer { isThinking = false }
//        
//        let resolvedData = await DataSourceManager.instance.resolveData(forStepID: stepId)
//
//        let finalInput = mergePrompt(userInput, with: resolvedData)
//        let newFinalInput = HTMLProcessor.instance.injectChunk(for: stepId, finalInput: finalInput, userInput: userInput)
//        let isImageURL = userInput.lowercased().hasPrefix("http") &&
//                         (userInput.contains(".jpg") || userInput.contains(".png"))
//
//        if isImageURL {
//            guard let response = await engine.analyzeImage(
//                url: userInput,
//                prompt: userInput,
//                promptBackgroundInfo: systemPrompt,
//                params: [
//                    "temperature": 0.7,
//                    "max_tokens": 1000
//                ]
//            ) else {
//                throw NSError(domain: "AIEngine", code: -1, userInfo: [
//                    NSLocalizedDescriptionKey: "Failed to get AI image analysis response"
//                ])
//            }
//            return response
//        } else {
//            guard let response = await engine.runWithBundle(
//                prompt: newFinalInput,
//                promptBackgroundInfo: systemPrompt
//            ) else {
//                throw NSError(domain: "AIEngine", code: -1, userInfo: [
//                    NSLocalizedDescriptionKey: "Failed to get AI response"
//                ])
//            }
//            return response
//        }
//    }
    
    func runImageAnalysisStep(
        imageURL: String,
        userPrompt: String,
        backgroundPrompt: String
    ) async throws -> AIResponseBundle {
        let engine = AIEngine()
        isThinking = true
        defer { isThinking = false }

        guard let response = await engine.analyzeImage(
            url: imageURL,
            prompt: userPrompt,
            promptBackgroundInfo: backgroundPrompt,
            params: [
                "temperature": 0.7,
                "max_tokens": 3000
            ]
        ) else {
            throw NSError(domain: "AIEngine", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get AI image analysis response"
            ])
        }

        return response
    }

//    func retryPromptRun(_ run: PromptRun) async {
//        guard let step = currentStep else { return }
//
//        do {
//            let engine = AgentExecutionEngine(agent: agent, session: chatSession)
//
//            let newRun = try await engine.runStep(
//                step: step,
//                userInput: run.userInput,
//                sharedInput: nil,
//                purpose: .retry,
//                inputID: run.inputID
//            )
//
//            promptRuns.append(newRun)
//            allRuns.append(newRun)
//
//        } catch {
//            print("❌ Failed to retry prompt run: \(error)")
//        }
////        guard let step = currentStep else { return }
////        do {
////            let response = try await runSmartPromptStep(
////                systemPrompt: run.basePrompt,
////                userInput: run.userInput,
////                stepId: step.id
////            )
////            
////            var newRun = buildPromptRun(from: run, response: response)
////            newRun.purpose = .retry
////            promptRuns.append(newRun)
////
////        } catch {
////            print("❌ Failed to retry prompt run: \(error)")
////        }
//    }
    
    
//    func promoteAndAdvanceToNextStep(using run: PromptRun) async {
//
//        completedRuns.append(run)
//        if !allRuns.contains(where: { $0.id == run.id }) {
//            allRuns.append(run)
//        }
//   
//        updatePrompt(for: run.promptStepId, newPrompt: run.basePrompt)
//
//        //  Move to next step (if exists)
//        let nextIndex = currentStepIndex + 1
//        guard agent.promptSteps.indices.contains(nextIndex) else { return }
//        currentStepIndex = nextIndex
//
//        userInput = run.response  // Preload initial userInput for next step
//
//        //  Inject placeholder PromptRun (will be filled on run)
//        if let step = currentStep {
//            let newRun = PromptRun(
//                promptStepId: step.id,
//                chatSessionId: chatSession.id,
//                basePrompt: step.prompt,
//                userInput: userInput,
//                finalPrompt: step.prompt + "\n" + userInput,
//                response: "",
//                createdAt: Date(),
//                inputID: userInput.normalized().sha256ToUUID(),
//                purpose: .normal
//            )
//            promptRuns = [newRun]
//
//            // 🔗 Save to Firestore
//            await persist(newRun)
//        }
//        forceShowInputBar = false
//        allowAutoInputBar = false
//        mode = .extraStep
//
//    }
    func updatePromptStepPrompt(stepId: UUID, newPrompt: String) {
        guard let index = agent.promptSteps.firstIndex(where: { $0.id == stepId }) else { return }

        // ✅ Update local state
        agent.promptSteps[index].prompt = newPrompt

        // 🔥 Push to Firestore
        Task {
            do {
                try await AgentManager.instance.updatePromptSteps(
                    agentId: agent.id,
                    promptSteps: agent.promptSteps
                )
                print("✅ Prompt step updated in Firestore.")
            } catch {
                print("❌ Failed to update prompt step: \(error.localizedDescription)")
            }
        }
    }
    func updateForkFeedback(runId: UUID, note: String, rating: Int) {
        
        func updateRun(in array: inout [PromptRun]) {
            if let index = array.firstIndex(where: { $0.id == runId }) {
                array[index].feedbackNote = note
                array[index].feedbackRating = rating
            }
        }

        updateRun(in: &forkRuns)
        updateRun(in: &promptRuns)
        updateRun(in: &completedRuns)

            Task {
                do {
                    try await PromptRunManager.instance.updatePromptRunFields(
                        runId: runId,
                        fields: [
                            "feedbackNote": note,
                            "feedbackRating": rating
                        ]
                    )
                } catch {
                    print("❌ Failed to update feedback in Firestore: \(error.localizedDescription)")
                }
            }
       
    }

//    func runPromptRun(_ run: PromptRun) async {
//        do {
//            let systemPrompt: String
//                 let userMessage: String
//
//                 if run.purpose == .diagnostic {
//                     systemPrompt = """
//                     You are a prompt improvement assistant. A user is testing a prompt that was sent to an LLM. Your job is to revise that prompt so that it more reliably produces output aligned with user expectations. The user has provided the original prompt, their input, the actual output, and feedback on what they expected.
//
//                     Your task is to propose a new, improved version of the original prompt that corrects the problems described.
//
//                     ❗️Your entire response should be ONLY the revised prompt. Do not include any explanations, comments, or markdown formatting.
//                     """
//                     userMessage = run.finalPrompt
//                 } else {
//                     systemPrompt = run.basePrompt
//                     userMessage = run.userInput
//                 }
//            guard let step = currentStep else { return }
//                 let response = try await runSmartPromptStep(
//                     systemPrompt: systemPrompt,
//                     userInput: userMessage,
//                     stepId: step.id
//                 )
//            
//            
//
//            let newRun = buildPromptRun(from: run, response: response)
//
//            Task {
//                let updatedFields = buildUpdatedFields(for: newRun)
//                try? await PromptRunManager.instance.updatePromptRunFields(
//                    runId: run.id,
//                    fields: updatedFields
//                )
//            }
//
//            if let index = promptRuns.firstIndex(where: { $0.id == run.id }) {
//                promptRuns[index] = newRun
//            } else {
//                if !allRuns.contains(where: { $0.id == newRun.id }) {
//                    allRuns.append(newRun)
//                } else {
//                    
//                    print("Should never get her")
//                }
//            }
//
//            isPromptExpanded = false
//            forceShowInputBar = false
//            allowAutoInputBar = false
//
//        } catch {
//            print("❌ Failed to re-run prompt: \(error)")
//        }
//    }


    
//    func prepareForkDraft(from run: PromptRun, with newPrompt: String? = nil) async {
//        print(#function, "Start")
//        guard let step = currentStep else { return }
//
//        let inputToUse = run.userInput
//        let promptToUse: String
//
//        if let override = newPrompt {
//            promptToUse = override
//        } else if run.purpose == .diagnostic && !run.response.isEmpty {
//            promptToUse = run.response
//        } else {
//            promptToUse = run.basePrompt
//        }
//        
//        // Store existing run in forkRuns before starting new fork
//        if let latest = promptRuns.last, !latest.response.isEmpty {
//            forkRuns.append(latest)
//        }
//        
//        if !allRuns.contains(where: { $0.id == run.id }) {
//            allRuns.append(run)
//        }
//
//        // Reset promptRuns to start fresh fork
//
//        let forkRun = PromptRun(
//            promptStepId: step.id,
//            chatSessionId: run.chatSessionId,
//            basePrompt: promptToUse,
//            userInput: inputToUse,
//            finalPrompt: promptToUse + "\n" + inputToUse,
//            response: "",
//            createdAt: Date(),
//            inputID: inputToUse.normalized().sha256ToUUID(),
//            purpose: .fork
//        )
//
//        promptRuns = [forkRun]
//
//        // 🔗 Save to Firestore
//        await persist(forkRun)
//        print(#function, "About to push updates")
//        // Populate input bar so the user can tweak it if needed
//        isPromptExpanded = true
//        userInput = inputToUse
//        forceShowInputBar = false
//        allowAutoInputBar = false
//        mode = .forking
//        print(#function, "Done")
//    }
    

//    
//    func createDiagnosticRun(from run: PromptRun) async {
//        guard let note = run.feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines),
//              !note.isEmpty else {
//            print("❌ No feedback note found.")
//            return
//        }
//
//        let diagnosticPrompt = "I used this prompt:\n\"\(run.basePrompt)\"\nwith input:\n\"\(run.userInput)\"\nbut received this output:\n\"\(run.response)\"\n\nThe user expected something different:\n\"\(note)\"\n\nWhat could be improved in the prompt or structure?"
//
//        let diagnosticRun = PromptRun(
//            promptStepId: run.promptStepId,
//            chatSessionId: run.chatSessionId,
//            basePrompt: run.basePrompt, // ✅ base remains the original
//            userInput: run.userInput,   // ✅ input stays the same
//            finalPrompt: diagnosticPrompt,
//            response: "",
//            createdAt: Date(),
//            inputID: run.inputID,
//            purpose: .diagnostic
//        )
//
//        promptRuns = [diagnosticRun]
//        forkRuns.append(run)
//
//        await persist(diagnosticRun)
//        await runPromptRun(diagnosticRun)
//    }
//    
    
//    func runPromptStep(
//        stepId: UUID,
//        input: String,
//        chatSessionId: UUID,
//        purpose: PromptRunPurpose = .normal,
//        inputID: String? = nil
//    ) async throws -> PromptRun {
//        // 🔍 Resolve the step
//        guard let step = agent.promptSteps.first(where: { $0.id == stepId }) else {
//            throw NSError(domain: "AgentRunner", code: 404, userInfo: [
//                NSLocalizedDescriptionKey: "Prompt step not found"
//            ])
//        }
//
//        // 🧠 Run the smart engine (with data injection + image handling)
//        let response = try await runSmartPromptStep(
//            systemPrompt: step.prompt,
//            userInput: input,
//            stepId: stepId
//        )
//
//        // 🧱 Build the placeholder PromptRun first
//        let placeholderRun = PromptRun(
//            promptStepId: stepId,
//            chatSessionId: chatSessionId,
//            basePrompt: step.prompt,
//            userInput: input,
//            finalPrompt: step.prompt + "\n" + input,
//            response: "",
//            createdAt: Date(),
//            inputID: inputID ?? input.normalized().sha256ToUUID(),
//            purpose: purpose
//        )
//
//        // 🏗 Construct full PromptRun using response bundle
//        let fullRun = buildPromptRun(from: placeholderRun, response: response)
//
//        // 💾 Save to Firestore
//        await persist(fullRun)
//
//        // 🧩 Update state on main thread
//        await MainActor.run {
//            self.promptRuns.append(fullRun)
//            self.allRuns.append(fullRun)
//        }
//
//        return fullRun
//    }
    
    
    enum AgentFlowStrategy {
        case promptChaining
        case sharedInput
        case queryEnhanced
        case imageInput
    }
    // In AgentRunnerViewModel
    func runStep(
        step: PromptStep,
        userInput: String,
        chatSessionId: UUID,
        purpose: PromptRunPurpose,
        systemPrompt: String? = nil,
        inputID: String? = nil
    ) async throws -> PromptRun {
        isThinking = true
        defer { isThinking = false }

        // Strategy-specific input preparation
        let input = step.flowStrategy == .sharedInput ? (sharedInput ?? userInput) : userInput
        let resolvedData = step.flowStrategy == .queryEnhanced ? await DataSourceManager.instance.resolveData(forStepID: step.id) : nil
        let finalInput = mergePrompt(input, with: resolvedData)
        let injectedInput = HTMLProcessor.instance.injectChunk(for: step.id, finalInput: finalInput, userInput: input)

        let isImage = step.flowStrategy == .imageInput && userInput.lowercased().hasPrefix("http") &&
                      (userInput.contains(".jpg") || userInput.contains(".png"))
        let engine = AIEngine()
        let bundle: AIResponseBundle

        if isImage {
            guard let imageResponse = await engine.analyzeImage(
                url: userInput,
                prompt: userInput,
                promptBackgroundInfo: systemPrompt ?? step.prompt,
                params: ["temperature": 0.7, "max_tokens": 1000]
            ) else {
                throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed image analysis"])
            }
            bundle = imageResponse
        } else {
            guard let textResponse = await engine.runWithBundle(
                prompt: injectedInput,
                promptBackgroundInfo: systemPrompt ?? step.prompt
            ) else {
                throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed text response"])
            }
            bundle = textResponse
        }

        let placeholderRun = PromptRun(
            promptStepId: step.id,
            chatSessionId: chatSessionId,
            basePrompt: step.prompt,
            userInput: input,
            finalPrompt: step.prompt + "\n" + injectedInput,
            response: "",
            createdAt: Date(),
            inputID: inputID ?? input.normalized().sha256ToUUID(),
            purpose: purpose
        )
        let fullRun = buildPromptRun(from: placeholderRun, response: bundle)
        await persist(fullRun)
        await MainActor.run {
            self.promptRuns.append(fullRun)
            self.allRuns.append(fullRun)
        }
        return fullRun
    }
   
}


// ✅ Minimal Additions to support image URL-based AI prompt flow without disrupting existing flow

extension AgentRunnerViewModel {
    /// Automatically detects image URL and chooses proper handler.

    
    private func mergePrompt(_ input: String, with data: String?) -> String {
        guard let data = data, !data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return input
        }

        return """
        \(input)

        ---
        REFERENCE DATA:
        \(data)
        """
    }
}
//
//// ✅ In your AgentRunnerView, change this:
//// await viewModel.runCurrentStep(with: inputText)
//// 🔁 TO THIS:
//await viewModel.runCurrentStepSmart(input: inputText)
// MARK: - New additions
enum RunMethod {
    case normal(input: String)
    case retry
    case fork(newPrompt: String?)
    case diagnostic
    case promoteAndAdvance
    case batch(input: String, stepIds: [UUID])
}

struct RunContext {
    let step: PromptStep
    let userInput: String
    let purpose: PromptRunPurpose
    let inputID: String
    let origin: PromptRun
    let systemPrompt: String?
    let stepIds: [UUID]?
}

extension AgentRunnerViewModel {
    func groupStepsByBatchEligibility(steps: [PromptStep]) -> [[PromptStep]] {
        var groups: [[PromptStep]] = []
        var currentGroup: [PromptStep] = []

        for step in steps {
            if step.isBatchEligible {
                currentGroup.append(step)
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                    currentGroup = []
                }
                groups.append([step])
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func prepareRunContext(method: RunMethod, run: PromptRun, overridePrompt: String? = nil) async -> [RunContext] {
        switch method {
            case .batch(let input, let stepIds):
                        let groupedSteps = await groupSteps(stepIds: stepIds, input: input, inputID: run.inputID)
                        var contexts: [RunContext] = []
            
            for group in groupedSteps {
                for step in group.steps {
                    let finalInput: String
                    switch step.flowStrategy {
                    case .promptChaining:
                        finalInput = input
                    case .sharedInput:
                        finalInput = sharedInput ?? input
                    case .queryEnhanced:
                        let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id)
                        let mergedInput = mergePrompt(input, with: resolvedData)
                        finalInput = HTMLProcessor.instance.injectChunk(for: step.id, finalInput: mergedInput, userInput: input)
                    case .imageInput:
                        finalInput = input
                    }

                    contexts.append(RunContext(
                        step: step,
                        userInput: finalInput,
                        purpose: .normal,
                        inputID: run.inputID ?? "",
                        origin: run,
                        systemPrompt: nil,
                        stepIds: [step.id]
                    ))
                }
            }
//                        for group in groupedSteps {
//                            if group.stepIds.count > 1 {
//                                // Batch context
//                                contexts.append(RunContext(
//                                    step: group.steps[0], // First step as representative
//                                    userInput: input,
//                                    purpose: .normal,
//                                    inputID: run.inputID ?? "",
//                                    origin: run,
//                                    systemPrompt: nil,
//                                    stepIds: group.stepIds // Store all step IDs for batch
//                                ))
//                            } else {
//                                // Single step context
//                                let step = group.steps[0]
//                                let finalInput: String
//                                switch step.flowStrategy {
//                                case .promptChaining:
//                                    finalInput = input
//                                case .sharedInput:
//                                    finalInput = sharedInput ?? input
//                                case .queryEnhanced:
//                                    let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id)
//                                    let mergedInput = mergePrompt(input, with: resolvedData)
//                                    finalInput = HTMLProcessor.instance.injectChunk(for: step.id, finalInput: mergedInput, userInput: input)
//                                case .imageInput:
//                                    finalInput = input
//                                }
//                                contexts.append(RunContext(
//                                    step: step,
//                                    userInput: finalInput,
//                                    purpose: .normal,
//                                    inputID: run.inputID ?? "",
//                                    origin: run,
//                                    systemPrompt: nil, stepIds: [step.id]
//                                ))
//                            }
//                        }
                        return contexts
        case .normal(let input):
            let step = agent.promptSteps.first(where: { $0.id == run.promptStepId }) ?? currentStep!
            let finalInput: String
            switch step.flowStrategy {
            case .promptChaining:
                finalInput = input
            case .sharedInput:
                finalInput = sharedInput ?? input
            case .queryEnhanced:
                let resolvedData = await DataSourceManager.instance.resolveData(forStepID: step.id)
                let mergedInput = mergePrompt(input, with: resolvedData)
                finalInput = HTMLProcessor.instance.injectChunk(for: step.id, finalInput: mergedInput, userInput: input)
            case .imageInput:
                finalInput = input
            }
            return [RunContext(
                step: step,
                userInput: finalInput,
                purpose: .normal,
                inputID: input.normalized().sha256ToUUID(),
                origin: run,
                systemPrompt: nil, stepIds: [step.id]
            )]
        case .retry:
            let step = agent.promptSteps.first(where: { $0.id == run.promptStepId }) ?? currentStep!
            return [RunContext(
                step: step,
                userInput: run.userInput,
                purpose: .retry,
                inputID: run.userInput.normalized().sha256ToUUID(),
                origin: run,
                systemPrompt: nil, stepIds: [step.id]
            )]
        case .fork(let newPrompt):
            let step = agent.promptSteps.first(where: { $0.id == run.promptStepId }) ?? currentStep!
            return [RunContext(
                step: step,
                userInput: run.userInput,
                purpose: .fork,
                inputID: run.userInput.normalized().sha256ToUUID(),
                origin: run,
                systemPrompt: newPrompt, stepIds: [step.id]
            )]
        case .diagnostic:
            let step = agent.promptSteps.first(where: { $0.id == run.promptStepId }) ?? currentStep!
            
            // Handle custom diagnostic prompt
            let diagnosticInput: String
            if let customPrompt = overridePrompt {
                diagnosticInput = customPrompt
            } else {
                diagnosticInput = run.userInput
            }
            
            return [RunContext(
                step: step,
                userInput: diagnosticInput,
                purpose: .diagnostic,
                inputID: run.userInput.normalized().sha256ToUUID(),
                origin: run,
                systemPrompt: """
                You are a prompt improvement assistant. A user is testing a prompt that was sent to an LLM. Your job is to revise that prompt so that it more reliably produces output aligned with user expectations.
                Your task is to propose a new, improved version of the original prompt that corrects the problems described.
                ❗️Your entire response should be ONLY the revised prompt. Do not include any explanations, comments, or markdown formatting.
                """, stepIds: [step.id]
            )]
        case .promoteAndAdvance:
            let nextIndex = currentStepIndex + 1
            guard agent.promptSteps.indices.contains(nextIndex) else { return [] }
            currentStepIndex = nextIndex
            userInput = run.response

            let nextStep = agent.promptSteps[nextIndex]

            let newContext = RunContext(
                step: nextStep,
                userInput: userInput,
                purpose: .normal,
                inputID: userInput.normalized().sha256ToUUID(),
                origin: run,
                systemPrompt: nil,
                stepIds: [nextStep.id]
            )
            return [newContext]
        }
    }
    
    private func groupSteps(stepIds: [UUID], input: String, inputID: String?) async -> [(stepIds: [UUID], steps: [PromptStep])] {
        var groups: [(stepIds: [UUID], steps: [PromptStep])] = []
        var currentBatch: [UUID] = []
        var currentSteps: [PromptStep] = []
        
        for stepId in stepIds {
            guard let step = agent.promptSteps.first(where: { $0.id == stepId }) else { continue }
            if step.isBatchEligible {
                currentBatch.append(stepId)
                currentSteps.append(step)
            } else {
                if !currentBatch.isEmpty {
                    groups.append((stepIds: currentBatch, steps: currentSteps))
                    currentBatch = []
                    currentSteps = []
                }
                groups.append((stepIds: [stepId], steps: [step]))
            }
        }
        
        if !currentBatch.isEmpty {
            groups.append((stepIds: currentBatch, steps: currentSteps))
        }
        
        return groups
    }

    func runCall(method: RunMethod, run: PromptRun, overridePrompt: String? = nil) async {
        await MainActor.run { isThinking = true }
        defer { Task { await MainActor.run { isThinking = false } } }
        do {
            let contexts = await prepareRunContext(method: method, run: run, overridePrompt: overridePrompt)
            print(#function, "contexts count:", contexts.count)
            //print(#function, "contexts:", contexts)
            for context in contexts {
                do {
                    let result = try await executionEngine.runStep(
                        step: context.step,
                        userInput: context.userInput,
                        sharedInput: nil, // Add this parameter
                        purpose: context.purpose,
                        inputID: context.inputID
                    )
                    await finalizeRun(context: context, result: result, method: method)
                } catch {
                    print("Step failed for \(context.step.id): \(error)")
                }
            }
        } catch {
            print("runCall failed [\(method)]: \(error)")
        }
    }

    private func finalizeRun(context: RunContext, result: PromptRun, method: RunMethod) async {
        await persist(result)
        await MainActor.run {
            switch context.purpose {
            case .fork:
                if !context.origin.response.isEmpty {
                    self.forkRuns.append(context.origin) // ✅ Only append meaningful forks
                }
                self.promptRuns = [result]
                self.userInput = context.origin.userInput // ✅ Preserve original user input
                self.isPromptExpanded = true
                self.isEditingPrompt = true               // ✅ Needed to show input bar in edit mode
                self.forceShowInputBar = false
                self.allowAutoInputBar = false
                self.mode = .forking
            case .diagnostic:
                self.promptRuns = [result]
                self.forkRuns.append(context.origin)
            case .retry:
                if let index = self.promptRuns.firstIndex(where: { $0.id == context.origin.id }) {
                    self.promptRuns[index] = result
                } else {
                    self.promptRuns.append(result)
                }
            case .normal, .inputVariation:
                if case .promoteAndAdvance = method {
                    self.completedRuns.append(context.origin)
                    let nextIndex = self.currentStepIndex + 1
                    if self.agent.promptSteps.indices.contains(nextIndex) {
                        self.currentStepIndex = nextIndex
                    }
                    self.userInput = context.origin.response
                    self.mode = .forking
                }
                self.promptRuns.append(result)
                if case .batch = method {} else {
                    self.completedRuns.append(result)
                }
            }
            if !self.allRuns.contains(where: { $0.id == result.id }) {
                self.allRuns.append(result)
            }
        }
    }


    func getPromptRuns(forInputID inputID: String) -> [PromptRun] {
        let uniqueRuns = Dictionary(grouping: promptRuns.filter { $0.inputID == inputID }, by: { $0.id })
            .values
            .compactMap { $0.first }
        return uniqueRuns.sorted { $0.createdAt < $1.createdAt }
    }
}
extension AgentRunnerViewModel {
    func runPromptStep(stepId: UUID, input: String, chatSessionId: UUID, purpose: PromptRunPurpose = .normal, inputID: String? = nil) async throws -> PromptRun {
        guard let step = agent.promptSteps.first(where: { $0.id == stepId }) else {
            throw NSError(domain: "AgentRunner", code: 404, userInfo: [NSLocalizedDescriptionKey: "Prompt step not found"])
        }
        let run = PromptRun(
            promptStepId: stepId,
            chatSessionId: chatSessionId,
            basePrompt: step.prompt,
            userInput: input,
            finalPrompt: step.prompt + "\n" + input,
            response: "",
            createdAt: Date(),
            inputID: inputID ?? input.normalized().sha256ToUUID(),
            purpose: purpose
        )
        await runCall(method: .normal(input: input), run: run)
        return promptRuns.last ?? run
    }

    func runCurrentStep(with input: String) async {
        guard let step = currentStep else {
            print("No current step available")
            return
        }
        let run = PromptRun(
            promptStepId: step.id,
            chatSessionId: chatSession.id,
            basePrompt: step.prompt,
            userInput: input,
            finalPrompt: step.prompt + "\n" + input,
            response: "",
            createdAt: Date(),
            inputID: input.normalized().sha256ToUUID(),
            purpose: .normal
        )
        await runCall(method: .normal(input: input), run: run)
    }

    func retryPromptRun(_ run: PromptRun) async {
        await runCall(method: .retry, run: run)
    }

    func runPromptRun(_ run: PromptRun) async {
        let method: RunMethod = run.purpose == .diagnostic ? .diagnostic : .normal(input: run.userInput)
        await runCall(method: method, run: run)
    }

    func prepareForkDraft(from run: PromptRun, with newPrompt: String? = nil) async {
        await runCall(method: .fork(newPrompt: newPrompt), run: run)
    }

    func createDiagnosticRun(from run: PromptRun) async {
        guard let note = run.feedbackNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            print("No feedback note found")
            return
        }
        let diagnosticPrompt = """
        I used this prompt:
        "\(run.basePrompt)"
        with input:
        "\(run.userInput)"
        but received this output:
        "\(run.response)"
        
        The user expected something different:
        "\(note)"
        
        What could be improved in the prompt or structure?
        """
        await runCall(method: .diagnostic, run: run, overridePrompt: diagnosticPrompt)
    }

    func promoteAndAdvanceToNextStep(using run: PromptRun) async {
        await runCall(method: .promoteAndAdvance, run: run)
    }

    func runCurrentStepSmart(input: String) async {
        await runCurrentStep(with: input)
    }
}
