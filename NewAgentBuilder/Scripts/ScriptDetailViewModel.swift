//
//  ScriptDetailViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


// MARK: - ScriptDetailViewModel
import Foundation
import Firebase
import UserInfoLibrary

@MainActor
class ScriptDetailViewModel: ObservableObject {
    static var instance: ScriptDetailViewModel!

        static func initialize(with script: Script) {
            instance = ScriptDetailViewModel(script: script)
        }

    @Published var soundBeats: [SoundBeat] = []
    @Published var isThinking: Bool = false
    @Published var imagePromptsByBeatId: [UUID: [ImagePrompt]] = [:]
    @Published var selectedImagePromptsByBeatId: [UUID: String] = [:]
    @Published var fullSizeImagePrompt: ImagePrompt? = nil
    
    // Add these properties at the top level of ScriptDetailViewModel
    @Published var beatRun: PromptRun? = nil
    @Published var matchingPromptRun: PromptRun? = nil
    @Published var generatePromptRun: PromptRun? = nil
    
    let script: Script
    private let speechAPIManager: SpeechServiceAPIManager? = SpeechServiceAPIManager(apiKey: Constants.speechAPIKey)

    init(script: Script) {
        print("INit ScriptDetailViewModel")
        self.script = script
    }
    
    func loadSoundBeats() async {
        do {
            soundBeats = try await SoundBeatManager.instance.fetchSoundBeats(for: script.id)
          //  print("✅ Loaded \(soundBeats.count) sound beats")
            for beat in soundBeats {
//                print("🔄 Beat: \(beat.id)")
//                print("- selectedImagePromptId: \(beat.selectedImagePromptId ?? "nil")")
//                print("- matchedImageURL: \(beat.matchedImageURL ?? "nil")")
                   //print("🔊 Beat: \(beat.id) — prompt: \(beat.generatedPrompt ?? "n/a")")
                   let prompts = try await ImagePromptManager.instance.fetchPrompts(for: beat.id)
                   imagePromptsByBeatId[beat.id] = prompts
                 //  print("🖼️ Found \(prompts.count) image prompts for beat \(beat.id)")
               }
        } catch {
            print("❌ Failed to load sound beats: \(error)")
        }
    }
    
    func generateSpeech() async {
        guard let apiManager = speechAPIManager else { return }

        isThinking = true
        defer { isThinking = false }

        for beat in soundBeats {
            if !FileManagerSingleton.instance.audioFileExists(for: beat) {
                do {
                    let audioData = try await apiManager.synthesizeToData(text: beat.text, voice: .neuralMale)
                    FileManagerSingleton.instance.storeAudioAsWAV(beat: beat, audioData: audioData)
                    print("✅ Audio generated and stored for beat \(beat.id)")
                } catch {
                    print("❌ Failed to generate audio for beat \(beat.id): \(error)")
                }
            } else {
                print("🔇 Skipped beat \(beat.id), audio already exists")
            }
        }
    }
    @MainActor
    func imageAddedFromlibrary(for beatID: UUID, imagePrompt: ImagePrompt) async {
        print("📥 Adding image from library to beat \(beatID): \(imagePrompt.id)")

        // 1. Add beatID to reusedBy if not already there
        var updatedPrompt = imagePrompt
        if !updatedPrompt.reusedBy.contains(beatID.uuidString) {
            updatedPrompt.reusedBy.append(beatID.uuidString)
            do {
                try await ImagePromptManager.instance.appendReusedBy(
                    promptId: updatedPrompt.id,
                    beatId: beatID.uuidString
                )
                print("🔗 Updated reusedBy for imagePrompt \(updatedPrompt.id)")
            } catch {
                print("❌ Failed to update reusedBy: \(error)")
            }
        }

        // 2. Update imagePromptsByBeatId
        var updatedImagePrompts = imagePromptsByBeatId
        if var existing = updatedImagePrompts[beatID] {
            existing.append(updatedPrompt)
            updatedImagePrompts[beatID] = existing
        } else {
            updatedImagePrompts[beatID] = [updatedPrompt]
        }
        imagePromptsByBeatId = updatedImagePrompts

        // 3. Update selectedImagePromptsByBeatId
        selectedImagePromptsByBeatId[beatID] = updatedPrompt.id

        // 4. Update the beat itself in memory and Firebase
        if let index = soundBeats.firstIndex(where: { $0.id == beatID }) {
            var updatedBeat = soundBeats[index]
            updatedBeat.selectedImagePromptId = updatedPrompt.id
            updatedBeat.matchedImageURL = updatedPrompt.url

            // Update local array
            var updatedBeats = soundBeats
            updatedBeats[index] = updatedBeat
            soundBeats = updatedBeats

            // Save to Firestore
            do {
                try await SoundBeatManager.instance.updateSelectedPrompt(for: updatedBeat)
                print("✅ Beat updated with selectedImagePromptId: \(updatedPrompt.id)")
            } catch {
                print("❌ Failed to update beat in Firestore: \(error)")
            }
        } else {
            print("❌ Beat ID \(beatID) not found in soundBeats array")
        }

        // 5. Optional: set full screen image if needed
        fullSizeImagePrompt = updatedPrompt
    }
    
    // In ScriptDetailViewModel.imageGeneratedFor method:
    @MainActor
    func imageGeneratedFor(beatID: UUID, imagePrompt: ImagePrompt) async {
        print("📥 ViewModel received imagePrompt ID: \(imagePrompt.id) for beat ID: \(beatID)")
        print("📊 BEFORE: imagePromptsByBeatId[\(beatID)]?.count = \(imagePromptsByBeatId[beatID]?.count ?? 0)")
        self.fullSizeImagePrompt = imagePrompt
        // 1. Update local state
        var updated = imagePromptsByBeatId
        if var existing = updated[beatID] {
            existing.append(imagePrompt)
            updated[beatID] = existing
            print("➕ Added to existing collection, new count: \(existing.count)")
        } else {
            updated[beatID] = [imagePrompt]
            print("🆕 Created new collection for beat")
        }

        // Trigger SwiftUI UI update for dictionary
        imagePromptsByBeatId = updated
        
        print("📊 AFTER: imagePromptsByBeatId[\(beatID)]?.count = \(imagePromptsByBeatId[beatID]?.count ?? 0)")

        // 2. Set this as the selected image prompt
        selectedImagePromptsByBeatId[beatID] = imagePrompt.id
        print("🔘 Selected image prompt ID: \(imagePrompt.id) for beat ID: \(beatID)")
        
        // Let's check what data is available before updating
        print("BEAT DATA CHECK (BEFORE UPDATE):")
        if let beat = soundBeats.first(where: { $0.id == beatID }) {
            print("- Beat: \(beat.id)")
            print("- Beat.matchedImageURL: \(beat.matchedImageURL ?? "nil")")
            print("- Beat.selectedImagePromptId: \(beat.selectedImagePromptId ?? "nil")")
        } else {
            print("❌ Could not find beat with ID: \(beatID) in soundBeats array!")
        }
        
        // 3. Update the SoundBeat in memory
        if let index = soundBeats.firstIndex(where: { $0.id == beatID }) {
            // Create a copy of the entire array to trigger proper SwiftUI updates
            var updatedBeats = soundBeats
            
            // Modify the specific beat
            var updatedBeat = updatedBeats[index]
            updatedBeat.selectedImagePromptId = imagePrompt.id
            updatedBeat.matchedImageURL = imagePrompt.url
            updatedBeats[index] = updatedBeat
            
            // Replace the entire array to ensure SwiftUI detects the change
            soundBeats = updatedBeats
            
            print("BEAT DATA CHECK (AFTER UPDATE):")
            print("- Beat: \(updatedBeat.id)")
            print("- Beat.matchedImageURL: \(updatedBeat.matchedImageURL ?? "nil")")
            print("- Beat.selectedImagePromptId: \(updatedBeat.selectedImagePromptId ?? "nil")")
            
            // 4. Critical step: Update SoundBeat in Firebase
            do {
                try await SoundBeatManager.instance.updateSelectedPrompt(for: updatedBeat)
                print("✅ Updated Firebase with selectedImagePromptId: \(imagePrompt.id)")
            } catch {
                print("❌ Failed to update Firebase: \(error)")
            }
        } else {
            print("❌ Could not find beat with ID: \(beatID) in soundBeats array!")
        }
    }

    func selectedImagePromptForBeat(_ beatId: UUID) -> ImagePrompt? {
        guard let prompts = imagePromptsByBeatId[beatId],
              !prompts.isEmpty else { return nil }

        if let selectedID = selectedImagePromptsByBeatId[beatId] {
            return prompts.first(where: { $0.id == selectedID }) ?? prompts.first
        }

        return prompts.first
    }

    
    func triggerImageGeneration(for beat: SoundBeat) async {
        do {
            isThinking = true

            guard let prompt = beat.generatedPrompt, !prompt.isEmpty else {
                print("❌ No prompt available for beat \(beat.id)")
                isThinking = false
                return
            }

            // Generate image via Scenario API
            let scenarioViewModel = ScenarioAPIViewModel(key: Constants.scenarioAPIKey, secret: Constants.scenarioAPISecret)
             await scenarioViewModel.generateImages(prompt: prompt)

             guard let image = scenarioViewModel.generatedImages.first else {
                 print("❌ No image generated")
                 return
             }
            do {
                    // Upload to Firebase
//                    let imagePath = "stickImages/\(UUID().uuidString).jpg"
//                    let url = try await FirebaseImageManager.shared.storeImage(image, atPath: imagePath)
//
//                    // Get shortID
//                    let shortID = try await ImagePromptManager.instance.nextShortID()
//
//                    // Create ImagePrompt (we have no seed/style metadata from your method, so pass nil)
//                    let promptModel = try await ImagePromptManager.instance.createPrompt(
//                        from: image,
//                        url: url,
//                        shortID: shortID,
//                        beatId: beat.id,
//                        seed: nil,
//                        style: nil,
//                        guidance: 7.5,
//                        samplingSteps: 30,
//                        attemptIndex: 0
//                    )
//
//                    // Save locally
//                    if imagePromptsByBeatId[beat.id] != nil {
//                        imagePromptsByBeatId[beat.id]?.append(promptModel)
//                    } else {
//                        imagePromptsByBeatId[beat.id] = [promptModel]
//                    }

                    print("✅ Image generated and saved for beat \(beat.id)")

                } catch {
                    print("❌ Upload or save failed: \(error)")
                }

        } catch {
            print("❌ Failed to generate image: \(error)")
        }

        isThinking = false
    }
    
    func findMatchingImagesInDataBase() async {
        do {
            DispatchQueue.main.async{
                self.isThinking = true
            }
            let session = ChatSession(
                id: UUID(),
                agentId: script.id,
                title: "Script \(script.title) - \(script.id.uuidString.prefix(8))",
                createdAt: Date()
            )
            
            let agent = try await AgentRegistry.shared.resolve(for: .scriptFormatter)
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            
            let allPrompts = try await ImagePromptManager.instance.fetchAllPrompts()
            let grouped = Dictionary(grouping: allPrompts, by: { $0.shortID })

            // Filter only the ones with duplicates
            let duplicates = grouped.filter { $1.count > 1 }

            if duplicates.isEmpty {
                print("✅ No duplicate shortIDs found.")
            } else {
                print("❌ Found \(duplicates.count) duplicate shortIDs:")
                for (shortID, prompts) in duplicates {
                    print("🔁 shortID: \(shortID)")
                    for prompt in prompts {
                        print("    - id: \(prompt.id), prompt: \(prompt.prompt.prefix(60))...")
                    }
                }
            }
            let shortIDMap: [Int: String] = Dictionary(uniqueKeysWithValues: allPrompts.map { ($0.shortID, $0.id) })

            // ✅ Find the prompt step by ID
            guard let matchStep = agent.promptSteps.first(where: {
                $0.id.uuidString == "8AC9F986-EBD1-4AE1-BC30-60D0972D93DB"
               // $0.id.uuidString == "FDF9D2E3-DE94-4FE3-B064-8BEE89BE577E"
            }) else {
                print("❌ Could not find step with matching ID")
                return
            }
            for beat in soundBeats {
                let beatInputText = buildContextWithFocusedBeat(beats: soundBeats, focusID: beat.id.uuidString)
                print(#function, beatInputText)
                let beatResult = try await runner.runPromptStep(
                    stepId: matchStep.id,
                    input: beatInputText,
                    chatSessionId: session.id)
                
                //let matches = parseMatches(from: beatResult.response)
                let bestMatches = determineBest(from: beatResult.response)
                let resolvedMatches: [SystemMatch] = bestMatches.compactMap { match in
                    guard let shortID = Int(match.promptId),
                          let fullId = shortIDMap[shortID] else {
                        print("❌ No full ID for shortID: \(match.promptId)")
                        return nil
                    }
                     return SystemMatch(promptId: fullId, strength: match.strength, rank: match.rank)
                 }
                for match in resolvedMatches {
                    try await ImagePromptManager.instance.appendReusedBy(
                        promptId: match.promptId,
                        beatId: beat.id.uuidString
                    )
                }
                try await SoundBeatManager.instance.updateSystemMatches(for: beat.id, matches: resolvedMatches)
                //Need to update the local sound beat too and ensure the display is updated.
                if var updatedBeat = soundBeats.first(where: { $0.id == beat.id }) {
                    updatedBeat.systemMatches = bestMatches
                    try await SoundBeatManager.instance.saveSoundBeat(updatedBeat)

                    DispatchQueue.main.async {
                        self.soundBeats = self.soundBeats.map { beat in
                            beat.id == updatedBeat.id ? updatedBeat : beat
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isThinking = false
               // await loadSoundBeats()
                print("✅ Matching image search complete for \(self.soundBeats.count) beats")
            }
          
            
        } catch {
            print("❌ findMatchingImagesInDataBase: \(error.localizedDescription)")
            DispatchQueue.main.async{
                self.isThinking = false
            }
        }
        
    }
    
    func determineBest(from response: String) -> [SystemMatch] {
        var matches: [SystemMatch] = []
        var rank = 1
        
        // Helper to map score to MatchStrength
        func strengthFromScore(_ score: Int) -> MatchStrength {
            switch score {
            case 90...100: return .strong
            case 70...89: return .moderate
            case 50...69: return .weak
            case 30...49: return .none
            default: return .none // Ignore scores outside 30-100
            }
        }
        
        // Step 1: Extract JSON array from raw string
        guard let jsonRegex = try? NSRegularExpression(pattern: #"\[\s*\{.*?\}\s*(,\s*\{.*?\}\s*)*\]"#, options: .dotMatchesLineSeparators) else {
            print("❌ Failed to create JSON regex pattern")
            return matches
        }
        
        let range = NSRange(location: 0, length: response.utf16.count)
        guard let jsonMatch = jsonRegex.firstMatch(in: response, options: [], range: range),
              let jsonRange = Range(jsonMatch.range, in: response) else {
            print("❌ No JSON array found in response")
            return matches
        }
        
        let jsonString = String(response[jsonRange])
        
        // Step 2: Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert JSON string to data")
            return matches
        }
        
        do {
            let jsonArray = try JSONDecoder().decode([[String: AnyCodable]].self, from: jsonData)
            
            // Step 3: Convert to prompt objects and sort by score
            let prompts: [(id: String, score: Int)] = jsonArray.compactMap { dict in
                guard let id = dict["id"]?.value as? String,
                      let score = dict["score"]?.value as? Int,
                      (30...100).contains(score) else { return nil }
                return (id: id, score: score)
            }.sorted { $0.score > $1.score } // Sort descending
            
            // Step 4: Select top 8 and map to SystemMatch
            for prompt in prompts.prefix(8) {
                 let strength = strengthFromScore(prompt.score)
                    matches.append(SystemMatch(promptId: prompt.id, strength: strength, rank: rank))
                    rank += 1
                
            }
        } catch {
            print("❌ JSON parsing error: \(error)")
        }
        
        return matches
    }


    // Parse Claude response like "Beat 13. text\n- 234 🟢\n- 18 🟡\n- 19 🟠\n- 20 🔴"
    func parseMatches(from response: String) -> [SystemMatch] {
        let lines = response.components(separatedBy: .newlines)
        var matches: [SystemMatch] = []
        var rank = 1
        
        // Create regex once, outside the loop
        guard let regex = try? NSRegularExpression(pattern: #"[-•]?\s*(\d+)\s+(🟢|🟡|🟠|🔴)"#) else {
            print("❌ Failed to create regex pattern")
            return matches
        }
        
        // Helper function to convert emoji to MatchStrength
        func strengthFromEmoji(_ emoji: String) -> MatchStrength? {
            return MatchStrength.allCases.first { $0.emoji == emoji }
        }
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            let range = NSRange(location: 0, length: line.utf16.count)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: line),
               let emojiRange = Range(match.range(at: 2), in: line) {
                
                let promptId = String(line[idRange])
                let emojiString = String(line[emojiRange])
                
                if let strength = strengthFromEmoji(emojiString) {
                    matches.append(SystemMatch(promptId: promptId, strength: strength, rank: rank))
                    rank += 1
                    
                    if matches.count == 8 { break }
                }
            }
        }
        
        return matches
    }
    func buildContextWithFocusedBeat(
        beats: [SoundBeat],
        focusID: String // the ID of the current beat being analyzed
    ) -> String {
        let sortedBeats = beats.sorted { $0.order < $1.order }

        let scriptBlock = sortedBeats
            .map { beat in
                let marker = (beat.id.uuidString == focusID) ? "👉" : "  "
                return "\(marker) \(beat.order). \(beat.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n")

        return """
        You are evaluating one specific line within a full script. The line marked with 👉 is your current focus.
        Do not evaluate it in isolation. Instead, consider how it fits into the **narrative flow** of the script:
        - What came before sets the context.
        - What follows shows the direction or consequence.

        Choose an image that reflects the **emotional and conceptual shift** at that point — not just the literal meaning of the focused line.

        Below is the full script with one line marked as 👉:
        \(scriptBlock)
        """
    }

    func runInitialPass() async {
        do {
            DispatchQueue.main.async{
                self.isThinking = true
            }
            // ✅ 1️⃣ Create a shared session for the full agent run
            let session = ChatSession(
                id: UUID(),
                agentId: script.id,
                title: "Script \(script.title) - \(script.id.uuidString.prefix(8))",
                createdAt: Date()
            )
            
            // ✅ 2️⃣ Load agent & runner
            let agent = try await AgentRegistry.shared.resolve(for: .scriptFormatter)
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            let beatStep = agent.promptSteps[0] // Step 1: script → beats
            //let matchingPrompt = agent.promptSteps[1]
            let generatePrompt = agent.promptSteps[1]
            
            // ✅ 3️⃣ Run step 1: Get raw beat-formatted output
            let beatRun = try await runner.runPromptStep(
                stepId: beatStep.id,
                input: script.content,
                chatSessionId: session.id,
                purpose: .normal
            )
            
//            let matchingPromptRun = try await runner.runPromptStep(
//                stepId: matchingPrompt.id,
//                input: beatRun.response,
//                chatSessionId: session.id,
//                purpose: .normal
//            )
            
            let generatePromptRun = try await runner.runPromptStep(
                stepId: generatePrompt.id,
                input: beatRun.response,
                chatSessionId: session.id,
                purpose: .normal
            )
            let beats = SoundBeatParser.parseShort(beatRaw: beatRun.response, promptRaw: generatePromptRun.response, scriptId: script.id)
//            let beats = SoundBeatParser.parseWithRankedMatch(beatRaw: beatRun.response, promptRaw: generatePromptRun.response, matchingRaw: matchingPromptRun.response, scriptId: script.id)
            
            try await SoundBeatManager.instance.saveSoundBeats(beats, forScript: script)
            await loadSoundBeats()
            print("✅ Initial pass completed with \(beats.count) beats")
          DispatchQueue.main.async{
              self.isThinking = false
              self.beatRun = beatRun
              //self.matchingPromptRun = matchingPromptRun
              self.generatePromptRun = generatePromptRun
          }
            
            
            
        }  catch {
            print("❌ Initial pass failed: \(error.localizedDescription)")
            DispatchQueue.main.async{
                self.isThinking = false
            }
        }
    }


    func runInitialPassOld() async {
        do {
            DispatchQueue.main.async{
                self.isThinking = true
            }
            // ✅ 1️⃣ Create a shared session for the full agent run
            let session = ChatSession(
                id: UUID(),
                agentId: script.id,
                title: "Script \(script.title) - \(script.id.uuidString.prefix(8))",
                createdAt: Date()
            )

            // ✅ 2️⃣ Load agent & runner
            let agent = try await AgentRegistry.shared.resolve(for: .scriptFormatter)
            let runner = AgentRunnerViewModel(agent: agent, session: session)

            guard agent.promptSteps.count >= 2 else {
                print("❌ Agent must have at least two prompt steps")
                return
            }

            let beatStep = agent.promptSteps[0] // Step 1: script → beats
            let promptStep = agent.promptSteps[1] // Step 2: beat → prompt
            let matchingPrompt = agent.promptSteps[2]
            

            // ✅ 3️⃣ Run step 1: Get raw beat-formatted output
            let beatRun = try await runner.runPromptStep(
                stepId: beatStep.id,
                input: script.content,
                chatSessionId: session.id,
                purpose: .normal
            )

            let promptRun = try await runner.runPromptStep(
                stepId: promptStep.id,
                input: beatRun.response,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            let matchingPromptRun = try await runner.runPromptStep(
                stepId: matchingPrompt.id,
                input: promptRun.response,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            
            let beats = SoundBeatParser.parse(beatRaw: beatRun.response, promptRaw: promptRun.response, matchingRaw: matchingPromptRun.response, scriptId: script.id)
            //need to combine the responses into a SoundBeat
            
            //below
            
            // ✅ 4️⃣ Parse all three responses into SoundBeats
              let beatsArray = SoundBeatParser.parse(
                  beatRaw: beatRun.response,
                  promptRaw: promptRun.response,
                  matchingRaw: matchingPromptRun.response,
                  scriptId: script.id
              )
              
              // ✅ 5️⃣ Save SoundBeats to Firebase
              try await SoundBeatManager.instance.saveSoundBeats(beats, forScript: script)

              // ✅ 6️⃣ Refresh UI
              await loadSoundBeats()
              print("✅ Initial pass completed with \(beats.count) beats")
            DispatchQueue.main.async{
                self.isThinking = false
            }

        } catch {
            print("❌ Initial pass failed: \(error.localizedDescription)")
            DispatchQueue.main.async{
                self.isThinking = false
            }
        }
    }
    
//    func selectedImagePromptForBeat(_ beatId: UUID) -> ImagePrompt? {
//        guard let beat = soundBeats.first(where: { $0.id == beatId }),
//              let prompts = imagePromptsByBeatId[beatId], !prompts.isEmpty else {
//            return nil
//        }
//
//        if let selectedId = beat.selectedImagePromptId {
//            return prompts.first(where: { $0.id == selectedId }) ?? prompts.first
//        }
//
//        return prompts.first
//    }
    
    func selectImagePrompt(_ promptId: String, for beat: SoundBeat) async {
        guard var updated = soundBeats.first(where: { $0.id == beat.id }),
              let prompt = imagePromptsByBeatId[beat.id]?.first(where: { $0.id == promptId }) else {
            return
        }

        updated.selectedImagePromptId = promptId
        updated.matchedImageURL = prompt.url

        do {
            try await SoundBeatManager.instance.updateSelectedPrompt(for: updated)
            await loadSoundBeats()
            
            selectedImagePromptsByBeatId[beat.id] = promptId
        } catch {
            print("❌ Failed to update selected prompt: \(error)")
        }
    }
    
    @MainActor
    func selectImagePrompt(_ promptId: String, for beatID: UUID) async {
        guard let beat = soundBeats.first(where: { $0.id == beatID }) else { return }
        await selectImagePrompt(promptId, for: beat)
    }
    
    func exportBeatsAsJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let sortedBeats = soundBeats.sorted(by: { $0.order < $1.order })

        do {
            let data = try encoder.encode(sortedBeats)
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"

            // Print to console, or write to file as needed
            print("📤 Exported JSON:\n\(jsonString)")
        } catch {
            print("❌ Failed to encode soundBeats: \(error)")
        }
    }
}

// You will need a matching implementation for `generateSoundBeats(from:)`, `generatePrompt(for:)`, and `saveSoundBeats(_, forScript:)` in ScriptManager and PromptEngine.
// Helper struct for JSON decoding
struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self.value = string
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        }
    }
}
