//
//  FortyBookAutoRunView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/22/25.
//


// MARK: - FortyBookAutoRunView
import SwiftUI

struct FortyBookAutoRunView: View {
   // @State private var droppedHTML: String = ""
    @State private var droppedHTML: String = ""
    @State private var selectedWeek: Int = 1
    @State private var stepOutputs: [String] = []
    @State private var isRunning: Bool = false
    @State private var agent: Agent? = nil
    @State private var campCode: String = ""
    
    //var agent: Agent
    private let agentId = UUID(uuidString: "91B60D7A-9463-42D9-A684-0D97FA73EA84")!
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📥 Upload Devotional HTML + Select Week")
                .font(.headline)
            
            HTMLDropView(htmlText: $droppedHTML)
                .frame(width: 80, height: 80)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .onChange(of: droppedHTML) { newValue in
                       print("🔥 droppedHTML changed: \(newValue.count) characters")
                       let code = extractCampVerses(from: newValue, week: selectedWeek)
                       print("🧪 campCode updated →", campCode.debugDescription)
                    DispatchQueue.main.async {
                        self.campCode = code
                         print("✅ campCode set on main thread")
                     }
                   }
            
            Picker("Week", selection: $selectedWeek) {
                ForEach(1...44, id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: selectedWeek) { newValue in
                DispatchQueue.main.async {
                    self.selectedWeek = newValue
                }
            }
            
            Button(action: {
                Task {
                    await runAgentWithHTMLAndWeek()
                }
            }) {
                Label("Run All Agent Steps", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(droppedHTML.isEmpty || isRunning)
            
            if isRunning {
                ProgressView("Running Agent...")
                    .padding(.top)
            }
            Button(action: copyAllSwiftCode_debug) {
                Label("Debug", systemImage: "doc.on.doc")
            }
            
            ScrollView {
                if !stepOutputs.isEmpty {
                    ParsedAttributedCodeViewShort(raw: stepOutputs.joined(separator: "\n\n"))
                }
                if !stepOutputs.isEmpty {
                    ParsedAttributedCodeView(raw: stepOutputs.joined(separator: "\n\n"))
                }
                
            }
            
            // ✅ Copy All Swift Code Button
            if !stepOutputs.isEmpty {
                Button(action: copyAllSwiftCode) {
                    Label("Copy All Swift Code", systemImage: "doc.on.doc")
                }
                .padding(.top)
            }
         
            
            if !campCode.isEmpty {
                Button(action: copyCampCode) {
                    Label("Copy Camp Code", systemImage: "doc.on.doc")
                }
                .padding(.top)
            }
        }
        .padding()
        .task {
            await loadAgent()
        }

    }
    
    private func loadAgent() async {
        do {
            if let fetched = try await AgentManager().fetchAgent(with: agentId) {
                await MainActor.run {
                    self.agent = fetched
                }
            } else {
                print("❌ No agent found")
            }
        } catch {
            print("❌ Failed to fetch agent: \(error)")
        }
    }
    
    // MARK: - Agent Runner Logic
    private func runAgentWithHTMLAndWeek() async {
        guard let agent = agent, !droppedHTML.isEmpty else { return }
        
        await MainActor.run {
            isRunning = true
            stepOutputs = []
        }
        let sessionIndex = agent.chatSessions.count  + 1
        let session = ChatSession(
            id: UUID(),
            agentId: agent.id,
            title: "Week \(selectedWeek)",
            createdAt: Date()
        )
        print("agent \(agent.id) has \(agent.chatSessions.count) sessions. Adding new session \(sessionIndex)...")
        var updatedAgent = agent
        updatedAgent.chatSessions.append(session)
        do {
            try await AgentManager.instance.updateChatSessions(
                agentId: updatedAgent.id,
                chatSessions: updatedAgent.chatSessions
            )
            print("Updated Agent with new session has \(updatedAgent.chatSessions.count) sessions...")
            let reloaded = try await AgentManager().fetchAgent(with: agent.id)
            if let updated = reloaded {
                if let index = AgentViewModel.instance.agents.firstIndex(where: { $0.id == updated.id }) {
                    AgentViewModel.instance.agents[index] = updated
                }
                AgentViewModel.instance.updateAgentInstance(updated)
            }
            print("✅ Saved ChatSession to agent's array")
        } catch {
            print("❌ Failed to save ChatSession array: \(error)")
        }
        let runner = AgentRunnerViewModel(agent: agent, session: session)
        var input = droppedHTML
        
        for (index, step) in agent.promptSteps.enumerated() {
            do {
                let run = try await runner.runPromptStep(
                    stepId: step.id,
                    input: input,
                    chatSessionId: session.id,
                    purpose: .normal
                )
                input = run.response
                await MainActor.run {
                    stepOutputs.append(run.response)
                   // stepOutputs.append("✅ Step \(index + 1): \(step.title)\n\(run.response.prefix(500))...")
                }
            } catch {
                await MainActor.run {
                    stepOutputs.append("❌ Step \(index + 1): \(step.title) failed → \(error.localizedDescription)")
                }
                break
            }
        }
        
        await MainActor.run {
            stepOutputs.append("🏁 Finished agent run")
            isRunning = false
        }
        
    }
    private func copyAllSwiftCode() {
        let allCode = stepOutputs
            .map {
                $0.replacingOccurrences(of: "```swift\n", with: "")
                  .replacingOccurrences(of: "```", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.starts(with: "func createWeek") }
            .joined(separator: "\n\n")

        UIPasteboard.general.string = allCode
        print("📋 Copied full Swift code output")
    }
    
    private func copyCampCode() {
           UIPasteboard.general.string = campCode
           print("📋 Copied CAMP code to clipboard")
       }

       private func extractCampVerses(from fullHTML: String, week: Int) -> String {
           let campVerse = HTMLProcessor.instance.extractCampVerses(from: fullHTML, week: week)
           print("🧪 extractCampVerses returned:", campVerse.debugDescription)
           print(campVerse)
           return campVerse
       }
    
    private func copyAllSwiftCode_debug() {
        var collected: [String] = []
        var newCollected: [String] = []
        newCollected.append(step1)
        newCollected.append(step2)

        for (index, raw) in newCollected.enumerated() {
            print("🔍 [\(index)] Raw value:")
            print(raw)

            let cleaned = raw
                .replacingOccurrences(of: "```swift\n", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            print("✅ [\(index)] After cleanup:")
            print(cleaned.prefix(100)) // Print just the start

            if cleaned.starts(with: "func createWeek") {
                print("✅ [\(index)] Match: added to output")
                collected.append(cleaned)
            } else {
                print("❌ [\(index)] Skipped: did not start with 'func createWeek'")
            }
        }

        let allCode = collected.joined(separator: "\n\n")
        UIPasteboard.general.string = allCode
        print("📋 Final output copied with \(collected.count) items.")
    }
}
// NOTE: You must pass an `Agent` into this view when presenting it.
// Example usage:
// FortyBookAutoRunView(agent: myScriptFormatterAgent)




public let step1 = """
```swift
func createWeek12Day0() -> AttributedString {
    var attributedString = AttributedString("WEEK 12: The Identity of God\n\n")
    attributedString.font = .title.bold()

    var part1 = AttributedString("Introduction\n")
    part1.font = .body.bold()
    attributedString.append(part1)

    var part2 = AttributedString("Over the next seven weeks, we are going to examine the core beliefs of our faith, learning why we believe what we believe.")
    part2.font = .body
    attributedString.append(part2)

    var part3 = AttributedString("\n\nWhen we dig into the theological foundations of faith, the word we often hear is doctrine. I realize many people can find this word intimidating. They may initially think that understanding doctrine requires going to Bible school or theological seminary. That could not be further from the truth. In fact, you and I ")
    part3.font = .body
    attributedString.append(part3)

    var part4 = AttributedString("need ")
    part4.font = .body.italic()
    attributedString.append(part4)

    var part5 = AttributedString("to know what we really believe. Why?")
    part5.font = .body
    attributedString.append(part5)

    var part6 = AttributedString("\n\nLet’s look at four reasons why knowing what we believe as Christians matters, built from an article written by Stephen Rees.")
    part6.font = .body
    attributedString.append(part6)


    var part7 = AttributedString("\n\nI hope you are as excited as I am. You will not just be learning from me, as various portions of the information we will be studying together over the next few weeks have been gleaned from and built upon content from Wayne Grudem’s valuable ")
    part7.font = .body
    attributedString.append(part7)

    var part8 = AttributedString("Systematic Theology")
    part8.font = .body.italic()
    attributedString.append(part8)

    var part9 = AttributedString(". Let’s get started.")
    part9.font = .body
    attributedString.append(part9)

//    var scriptureReference = AttributedString("\n\nCAMP in Romans 10:9–15 ")
//    scriptureReference.font = .body.bold()
//    attributedString.append(scriptureReference)

    return attributedString
}
``` 
"""


public let step2 = """
```swift
func createWeek12Day1() -> AttributedString {
    var attributedString = AttributedString("WEEK 12, DAY 1: The Attributes of God\n\n")
    attributedString.font = .title.bold()

    var part1 = AttributedString("This week we focus on the doctrine of God. If someone asked me for a brief definition of God, I would tell them that God is the Creator and Ruler of the universe. He has eternally existed in three persons—the Father, the Son, and the Holy Spirit. All three are co-equal and one God. ")
    part1.font = .body
    attributedString.append(part1)
    
    var part2 = AttributedString("A person could easily spend their entire life studying the subject of God. I want to try to make it less intimidating this week by simply talking about God in four areas: His attributes, His activity, the Trinity, and the certainties about God we can build our life upon. ")
    part2.font = .body
    attributedString.append(part2)

    var part3 = AttributedString("First, we will focus on several of God’s attributes, or His characteristics. Some of God’s characteristics are only for Him. Other characteristics of God we are to emulate—we should desire to mirror them in our lives. For example, when we talk about God’s attribute of being infinite, we can never be infinite. That is only for Him. But when we talk about God as being love, we certainly can emulate Him and reflect His love in our lives. ")
    part3.font = .body
    attributedString.append(part3)

    var part4 = AttributedString("So, how can we describe God? What are some of His attributes? ")
    part4.font = .body
    attributedString.append(part4)

    var part5 = AttributedString("God is intelligent.")
    part5.font = .body.bold()
    attributedString.append(part5)

    var part6 = AttributedString(" He is a knowing being. He is not a blind force. He is not some metaphysical presence. He is infinite.\n\n\n")
    part6.font = .body
    attributedString.append(part6)

    var part7 = AttributedString("God is spiritual.")
    part7.font = .body.bold()
    attributedString.append(part7)

    var part8 = AttributedString(" This is very important. God is transcendent. He is above time and space. He is not constrained by a physical body. The Scripture says in John 4:24: ")
    part8.font = .body
    attributedString.append(part8)

    var scripture1 = AttributedString("“God is spirit, and those who worship him must worship in spirit and truth.”\n\n\n")
    scripture1.font = .body.italic()
    attributedString.append(scripture1)

    var part9 = AttributedString("God is personal.")
    part9.font = .body.bold()
    attributedString.append(part9)

    var part10 = AttributedString(" God has a personality, and He relates to us with that personality. He is not a cosmic, distant force. God is a personal being. We see this in passages like Zephaniah 3:17: ")
    part10.font = .body
    attributedString.append(part10)

    var scripture2 = AttributedString("“The Lord your God is in your midst, a mighty one who will save; he will rejoice over you with gladness; he will quiet you by his love; he will exult over you with loud singing.”\n\n\n")
    scripture2.font = .body.italic()
    attributedString.append(scripture2)

    var part11 = AttributedString("God is self-existent.")
    part11.font = .body.bold()
    attributedString.append(part11)

    var part12 = AttributedString(" God needs nothing, and never has He needed anything or anyone.\n\n\n")
    part12.font = .body
    attributedString.append(part12)

    var part13 = AttributedString("God is self-sufficient.")
    part13.font = .body.bold()
    attributedString.append(part13)

    var part14 = AttributedString(" Everything God needs to be God is in God.\n\n\n")
    part14.font = .body
    attributedString.append(part14)

    var part15 = AttributedString("God is eternal.")
    part15.font = .body.bold()
    attributedString.append(part15)

    var part16 = AttributedString(" He always has been, He is, and He always will be.\n\n\n")
    part16.font = .body
    attributedString.append(part16)

    var part17 = AttributedString("God is glorious.")
    part17.font = .body.bold()
    attributedString.append(part17)

    var part18 = AttributedString(" Revelation 4:11 says, ")
    part18.font = .body
    attributedString.append(part18)

    var scripture3 = AttributedString("“Worthy are you, our Lord and God, to receive glory and honor and power, for you created all things, and by your will they existed and were created.” ")
    scripture3.font = .body.italic()
    attributedString.append(scripture3)
    
    var part19 = AttributedString("\n\nAnd finally, for today,\n\n")
    part19.font = .body
    attributedString.append(part19)
    
    var part20 = AttributedString("God is unchanging.")
    part20.font = .body.bold().italic()
    attributedString.append(part20)

    var part21 = AttributedString(" This is so crucial. I do not want to build my life on a deity that changes. So much in our lives changes. I change. You change. The world changes. Conditions change. Circumstances change. Health changes. Economies change. Societies change. Governments change. The beliefs of the people around us change. But God does not change. Malachi 3:6 reads, ")
    part21.font = .body
    attributedString.append(part21)

    var scripture4 = AttributedString("“For I the Lord do not change; therefore you, O children of Jacob, are not consumed.” ")
    scripture4.font = .body.italic()
    attributedString.append(scripture4)

    var part22 = AttributedString("You may have heard it said, He is the same yesterday, today, and forever. If you are struggling to see God moving in your life right now, think back to a time when you did experience His faithfulness. You can rest assured that if He has been faithful before, He will be faithful again. Because He cannot change, He cannot stop being what He has always been—")
    part22.font = .body
    attributedString.append(part22)

    var part23 = AttributedString("faithful.")
    part23.font = .body.italic()
    attributedString.append(part23)

    var part24 = AttributedString(" Let these attributes encourage you deeply. ")
    part24.font = .body
    attributedString.append(part24)

    var reflection = AttributedString("Personal Reflection:")
    reflection.font = .body.italic()
    attributedString.append(reflection)

    var part25 = AttributedString(" Which attribute of God are you the most thankful for today? Why? What other attributes are meaningful to you?")
    part25.font = .body
    attributedString.append(part25)

//    var scriptureReference = AttributedString("\n\nCAMP in Revelation 4:1-11 ")
//    scriptureReference.font = .body.bold()
//    attributedString.append(scriptureReference)

    return attributedString
}
```

"""


