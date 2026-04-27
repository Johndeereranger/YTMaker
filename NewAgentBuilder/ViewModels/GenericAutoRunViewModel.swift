//
//  GenericAutoRunViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/23/25.
//


// MARK: - GenericAutoRunViewModel
import Foundation
import SwiftUI
import Combine

@MainActor
class GenericAutoRunViewModel: ObservableObject {

    @Published var droppedInput: String = ""            // e.g., raw HTML
    @Published var selectedWeek: Int = 1                 // Configurable input

    @Published var stepOutputs: [String] = []
    @Published var campCode: String = ""

    @Published var isRunning: Bool = false
    @Published var errorMessage: String? = nil

    @Published var agent: Agent?
   // let agentId: UUID

    
    @Published var chatSession: ChatSession?
    
    // MARK: - Init
    init() {}
//    init(agentId: UUID) {
//        self.agentId = agentId
//        Task {
//            await loadAgent()
//        }
//    }
    func setAgent(_ agent: Agent) {
           self.agent = agent
           self.chatSession = nil
           self.droppedInput = ""
           self.stepOutputs = []
           self.campCode = ""
           self.isRunning = false
           self.errorMessage = nil
       }

    // MARK: - Load Agent
    func loadAgent() async {
        guard let agentId = agent?.id else { return }
        do {
            if let fetched = try await AgentManager().fetchAgent(with: agentId) {
                self.agent = fetched
            } else {
                errorMessage = "❌ No agent found for ID \(agentId)"
            }
        } catch {
            errorMessage = "❌ Failed to fetch agent: \(error.localizedDescription)"
        }
    }

    func runAllSteps() async {
        guard let agent = agent, !droppedInput.isEmpty else { return }
        self.extractCampCode(using: HTMLProcessor.instance.extractCampVerses)
        self.isRunning = true
        self.stepOutputs = []
        
        let session = ChatSession(
            id: UUID(),
            agentId: agent.id,
            title: agent.generateSessionTitle(selectedWeek: selectedWeek),
            createdAt: Date()
        )
        
        DispatchQueue.main.async {
            self.chatSession = session
        }
        
        var updatedAgent = agent
        updatedAgent.chatSessions.append(session)
        
        do {
            try await AgentManager.instance.updateChatSessions(
                agentId: updatedAgent.id,
                chatSessions: updatedAgent.chatSessions
            )
            AgentViewModel.instance.updateAgentInstance(updatedAgent)
            
            if let reloaded = try await AgentManager().fetchAgent(with: agent.id) {
                self.agent = reloaded
            }
            
            let runner = AgentRunnerViewModel(agent: updatedAgent, session: session)
            var input = droppedInput
            let stepGroups = runner.groupStepsByBatchEligibility(steps: updatedAgent.promptSteps)
            print(#function, "stepGroups:", stepGroups.count)
            for group in stepGroups {
                let runMethod: RunMethod = group.count > 1
                    ? .batch(input: input, stepIds: group.map { $0.id })
                    : .normal(input: input)
                print(#function, "runMethod:", runMethod)
                // Create proper dummyRun with all required fields
                let dummyRun = PromptRun(
                    promptStepId: group.first!.id,
                    chatSessionId: session.id,
                    basePrompt: group.first!.prompt,
                    userInput: input,
                    finalPrompt: group.first!.prompt + "\n" + input,
                    response: "",
                    createdAt: Date(),
                    inputID: input.normalized().sha256ToUUID(),
                    purpose: .normal
                )
                
                do {
                    // Track initial promptRuns count to find new runs
                    let initialCount = runner.promptRuns.count
                    
                    // runCall doesn't return - it updates runner.promptRuns
                    await runner.runCall(
                        method: runMethod,
                        run: dummyRun,
                        overridePrompt: nil
                    )
                    
                    // Get the new run(s) that were added
                    //let newRuns = Array(runner.promptRuns.dropFirst(initialCount))
                    let newRuns = runner.promptRuns
                        .dropFirst(initialCount)
                        .sorted { lhs, rhs in
                            guard let lhsIndex = group.firstIndex(where: { $0.id == lhs.promptStepId }),
                                  let rhsIndex = group.firstIndex(where: { $0.id == rhs.promptStepId }) else {
                                return false
                            }
                            return lhsIndex < rhsIndex
                        }
                    if !newRuns.isEmpty {
                        for run in newRuns {
                            self.stepOutputs.append(run.response)
                            input = run.response // chain from last step in batch
                        }
                    } else {
                        self.stepOutputs.append("❌ No response received")
                        break
                    }
//                    if let lastRun = newRuns.last, !lastRun.response.isEmpty {
//                        input = lastRun.response
//                        
//                        // For batches, might want to append all responses or just the last one
//                        if group.count > 1 {
//                            // Batch - append combined or individual responses
//                            self.stepOutputs.append("✅ Batch completed: \(lastRun.response)")
//                        } else {
//                            // Single step
//                            self.stepOutputs.append(lastRun.response)
//                        }
//                    } else {
//                        self.stepOutputs.append("❌ No response received")
//                        break
//                    }
                    
                } catch {
                    self.stepOutputs.append("❌ Step failed → \(error.localizedDescription)")
                    break
                }
            }
            
            self.stepOutputs.append("🏁 Finished agent run")
            self.isRunning = false
        } catch {
            self.errorMessage = "❌ Failed to run steps: \(error.localizedDescription)"
            self.isRunning = false
        }
    }
    // MARK: - Run All Prompt Steps
    func runAllStepsOld() async {
        guard let agent = agent, !droppedInput.isEmpty else { return }
        self.extractCampCode(using: HTMLProcessor.instance.extractCampVerses)
        self.isRunning = true
        self.stepOutputs = []
     
        
        let session = ChatSession(
            id: UUID(),
            agentId: agent.id,
            title: agent.generateSessionTitle(selectedWeek: selectedWeek),
            createdAt: Date()
        )
        
        DispatchQueue.main.async{
            self.chatSession = session
        }

        var updatedAgent = agent
        updatedAgent.chatSessions.append(session)
        

        do {
            try await AgentManager.instance.updateChatSessions(
                agentId: updatedAgent.id,
                chatSessions: updatedAgent.chatSessions
            )
            AgentViewModel.instance.updateAgentInstance(updatedAgent)

            if let reloaded = try await AgentManager().fetchAgent(with: agent.id) {
                self.agent = reloaded
            }

            let runner = AgentRunnerViewModel(agent: updatedAgent, session: session)
            var input = droppedInput

            for (index, step) in updatedAgent.promptSteps.enumerated() {
                do {
                    let run = try await runner.runPromptStep(
                        stepId: step.id,
                        input: input,
                        chatSessionId: session.id,
                        purpose: .normal
                    )
                    input = run.response
                    self.stepOutputs.append(run.response)
                } catch {
                    self.stepOutputs.append("❌ Step \(index + 1) failed → \(error.localizedDescription)")
                    break
                }
            }

            self.stepOutputs.append("🏁 Finished agent run")
            self.isRunning = false
        } catch {
            self.errorMessage = "❌ Failed to run steps: \(error.localizedDescription)"
            self.isRunning = false
        }
    }

    // MARK: - Copy Utilities
    func copyAllSwiftCode() {
        let code = stepOutputs
            .map {
                $0.replacingOccurrences(of: "```swift\n", with: "")
                  .replacingOccurrences(of: "```", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.starts(with: "func createWeek") }
            .joined(separator: "\n\n")

        UIPasteboard.general.string = code
    }

    func copyCampCode() {
        UIPasteboard.general.string = campCode
    }

    // Optional: reactively update campCode
    func extractCampCode(using processor: (String, Int) -> String) {
        self.campCode = processor(droppedInput, selectedWeek)
    }
    
    func updateSessionTitle(_ newTitle: String) {
        guard var chatSession = self.chatSession else {return}
        guard var agent = self.agent else {return}
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
                    self.agent?.chatSessions[index].title = trimmed
                    self.chatSession = self.agent?.chatSessions[index]
                }

                print("✅ Session title synced to Firestore.")
            } catch {
                print("⚠️ Firestore sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    func clearAll() {
        droppedInput = ""
        selectedWeek = 1
        stepOutputs = []
        campCode = ""
        isRunning = false
        errorMessage = nil
        chatSession = nil
    }
}
