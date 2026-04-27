//
//  ImagePromptViewer.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/20/25.
//


// ImagePromptViewer.swift
import SwiftUI
import UserInfoLibrary

public func extractStoragePath(fromDownloadURL urlString: String) -> String? {
    guard let url = URL(string: urlString),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let pathRange = components.path.range(of: "/o/") else {
        return nil
    }

    let encodedPath = String(components.path[pathRange.upperBound...])
    return encodedPath.removingPercentEncoding
}

struct CachedImageView: View {
    let name: String
    let remotePath: String
    let cornerRadius: CGFloat
    let maxWidth: CGFloat?
    let maxHeight: CGFloat?

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ifLet(maxWidth) { view, width in
                        view.frame(maxWidth: width)
                    }
                    .ifLet(maxHeight) { view, height in
                        view.frame(maxHeight: height)
                    }
                    .cornerRadius(cornerRadius)
                    .shadow(radius: 4)
            } else if isLoading {
                ProgressView()
                    .frame(height: maxHeight ?? 200)
            } else {
                Color.gray
                    .frame(height: maxHeight ?? 200)
                    .overlay(Text("Failed to load"))
                    .cornerRadius(cornerRadius)
            }
        }
        .task(id: "\(name)-\(remotePath)") {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Cancel any existing loading task
        loadingTask?.cancel()
        
        // Create new loading task
        loadingTask = Task {
            image = nil
            isLoading = true
            
            do {
                let loadedImage = try await ImageStoreManager.shared.retrieveImage(name: name, remotePath: remotePath)
                
                // Only update if we haven't been cancelled
                if !Task.isCancelled {
                    await MainActor.run {
                        self.image = loadedImage
                        self.isLoading = false
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("❌ Failed to load image \(name): \(error)")
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
        
        await loadingTask?.value
    }
}

extension View {
    @ViewBuilder
    func ifLet<T, V: View>(_ value: T?, transform: (Self, T) -> V) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}
// MARK: - ImagePromptRow
struct ImagePromptRow: View {
    let prompt: ImagePrompt // Assuming your prompt model is called ImagePrompt
    let onRegenerate: (ImagePrompt) -> Void
    let hideImge: (ImagePrompt) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CachedImageView(
                       name: prompt.id,
                       remotePath: extractStoragePath(fromDownloadURL: prompt.url) ?? "",
                       cornerRadius: 12, maxWidth: nil,
                       maxHeight: 300
                   )
//            AsyncImage(url: URL(string: prompt.url)) { phase in
//                switch phase {
//                case .success(let image):
//                    image
//                        .resizable()
//                        .aspectRatio(contentMode: .fit)
//                        .frame(maxWidth: .infinity)
//                        .cornerRadius(12)
//                        .shadow(radius: 4)
//                case .failure:
//                    Color.gray.frame(height: 200).overlay(Text("Failed to load"))
//                case .empty:
//                    ProgressView()
//                @unknown default:
//                    EmptyView()
//                }
//            }

            VStack(alignment: .leading, spacing: 4) {
                Text("🆔 ID: \(prompt.id)").font(.caption)
                Text("🌱 Seed: \(prompt.seed ?? "n/a")").font(.caption)
                Text("📈 Steps: \(prompt.samplingSteps?.description ?? "n/a")").font(.caption)
                Text("🎯 Guidance: \(prompt.guidance?.description ?? "n/a")").font(.caption)
                Text("📝 Prompt: \(prompt.prompt)").font(.footnote)
                Text("Detail Prompt: \(prompt.detailedPrompt)").font(.footnote)
                Text("Prompt Tags: \(prompt.promptTags)").font(.footnote)
                
            }
            HStack {
                Button(action: {
                    hideImge(prompt)
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Hide Image")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    onRegenerate(prompt)
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - ImagePromptViewer
struct ImagePromptViewer: View {
    @StateObject private var viewModel = ImagePromptViewerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
//            Button(action: {
//                Task {
//                    await viewModel.regenerateAllPromptsAggressive()
//                }
//            }) {
//                HStack {
//                    Image(systemName: "arrow.triangle.2.circlepath")
//                    Text("Regenerate All Prompts")
//                }
//                .foregroundColor(.white)
//                .padding(.horizontal, 16)
//                .padding(.vertical, 8)
//                .background(Color.red)
//                .cornerRadius(8)
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(viewModel.prompts) { prompt in
                            ImagePromptRow(
                                prompt: prompt,
                                onRegenerate: { prompt in
                                    Task {
                                        await viewModel.regeneratePrompt(prompt)
                                    }
                                },
                                hideImge: { prompt in
                                    Task {
                                        await viewModel.hidePrompt(prompt)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
//                ScrollView {
//                    LazyVStack(alignment: .leading, spacing: 24) {
//                        ForEach(viewModel.prompts) { prompt in
//                            ImagePromptRow(
//                                prompt: prompt,
//                                onRegenerate: { prompt in
//                                    Task {
//                                        await viewModel.regeneratePrompt(prompt)
//                                    }
//                                },
//                                hideImge: { prompt in
//                                    Task {
//                                        await viewModel.hidePrompt(prompt)
//                                    }
//                                }
//                            )
//                                
//                        }
//                    }
//                    .padding()
//                }
            //}
        }
        .navigationTitle("Image Prompts")
        .onAppear {
            Task {
                await viewModel.loadPrompts()
            }
        }
    }
}

// ViewModel
class ImagePromptViewerViewModel: ObservableObject {
    @Published var prompts: [ImagePrompt] = []
    var allPrompts: [ImagePrompt] = []
    @MainActor
    func loadPrompts() async {
        
        do {
            
                let gotPrompts = try await ImagePromptManager.instance.fetchAllPrompts()
            self.allPrompts = gotPrompts
            self.prompts = gotPrompts.filter { !$0.isHidden }
           
        } catch {
            print("❌ Failed to load image prompts: \(error)")
        }
    }
    
    func hidePrompt(_ prompt: ImagePrompt) async {
        do {
            try await ImagePromptManager.instance.hidePrompt(for: prompt.id)
            
            // Update data model
            if let index = allPrompts.firstIndex(where: { $0.id == prompt.id }) {
                allPrompts[index].isHidden = true
            }
            
            // Reassign to trigger SwiftUI update
            self.prompts = allPrompts.filter { !$0.isHidden }
            
        } catch {
            print("Failed to hide prompt: \(error.localizedDescription)")
        }
    }
    

    func regeneratePrompt(_ prompt: ImagePrompt) async {
        do {
            // Generate new prompt using the existing image URL
            let newPromptText = try await GPTPromptGenerator.generatePrompt(from: prompt.url)
            try await ImagePromptManager.instance.updatePromptTags(for: prompt.id, promptTags: newPromptText)
            //try await ImagePromptManager.instance.updateDetailedPrompt(for: prompt.id, detailedPrompt: newPromptText)
            
            // Find the index of the prompt we're updating
            guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
                print("Could not find prompt to update")
                return
            }
            
            // Update the prompt on the main thread since we're modifying @Published property
            await MainActor.run {
                var updatedPrompt = prompts[index]
                updatedPrompt.promptTags = newPromptText
                prompts[index] = updatedPrompt
            }
            
            print("Successfully regenerated prompt for ID: \(prompt.id)", newPromptText)
            
        } catch {
            print("Failed to regenerate prompt: \(error.localizedDescription)")
            //throw error // Re-throw for retry logic
        }
    }

    func regenerateAllPromptsWithRateLimit(concurrentLimit: Int = 3, requestsPerMinute: Int = 150) async {
        let total = prompts.count
        let minDelayBetweenRequests = 60.0 / Double(requestsPerMinute) // Seconds between requests
        
        print("🔄 Starting regeneration of \(total) prompts")
        print("⚡ Rate limit: \(requestsPerMinute) requests/min (\(String(format: "%.2f", minDelayBetweenRequests))s between requests)")
        print("🔀 Concurrent limit: \(concurrentLimit)")
        
        actor RateLimiter {
            private var lastRequestTime = Date.distantPast
            private let minInterval: TimeInterval
            
            init(requestsPerMinute: Int) {
                self.minInterval = 60.0 / Double(requestsPerMinute)
            }
            
            func waitForNextSlot() async {
                let now = Date()
                let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
                
                if timeSinceLastRequest < minInterval {
                    let waitTime = minInterval - timeSinceLastRequest
                    print("⏳ Rate limiting: waiting \(String(format: "%.2f", waitTime))s")
                    try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
                
                lastRequestTime = Date()
            }
        }
        
        actor TokenLimiter {
            private var tokensUsed: Int = 0
            private var lastResetTime: Date = Date()
            private let maxTokensPerMinute: Int

            init(maxTokensPerMinute: Int) {
                self.maxTokensPerMinute = maxTokensPerMinute
            }

            func waitForTokenSlot(needed: Int) async {
                let now = Date()
                if now.timeIntervalSince(lastResetTime) > 10 {
                    tokensUsed = 0
                    lastResetTime = now
                }

                while tokensUsed + needed > maxTokensPerMinute {
                    let waitTime: TimeInterval = 1.0
                    print("⏳ Waiting for token budget... (\(tokensUsed)/\(maxTokensPerMinute) used)")
                    try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))

                    let current = Date()
                    if current.timeIntervalSince(lastResetTime) > 60 {
                        tokensUsed = 0
                        lastResetTime = current
                    }
                }

                tokensUsed += needed
            }
            func addActualUsage(_ tokens: Int) async {
                   let now = Date()
                   if now.timeIntervalSince(lastResetTime) > 60 {
                       tokensUsed = 0
                       lastResetTime = now
                   }
                   tokensUsed += tokens
               }
        }
        
        actor CompletionCounter {
            private var count = 0
            private var failures = 0
            
            func increment() -> Int {
                count += 1
                return count
            }
            
            func recordFailure() -> Int {
                failures += 1
                return failures
            }
            
            func getStats() -> (completed: Int, failed: Int) {
                return (count, failures)
            }
        }
        actor TokenUsageHistory {
            private var recentTokenUsages: [Int] = []
            private let maxHistorySize = 20

            func record(_ tokens: Int) {
                recentTokenUsages.append(tokens)
                if recentTokenUsages.count > maxHistorySize {
                    recentTokenUsages.removeFirst()
                }
            }

            func estimateNextUsage() -> Int {
                guard !recentTokenUsages.isEmpty else { return 1000 } // Default guess
                let avg = Double(recentTokenUsages.reduce(0, +)) / Double(recentTokenUsages.count)
                return min(Int(avg * 1.10), 29000) // Add 10% buffer, cap at 29,000
            }
        }
        
        let rateLimiter = RateLimiter(requestsPerMinute: requestsPerMinute)
        let counter = CompletionCounter()
        let tokenLimiter = TokenLimiter(maxTokensPerMinute: 29000) // Stay just under 30K
        let tokenHistory = TokenUsageHistory()
        await withTaskGroup(of: Void.self) { group in
            var activeTaskCount = 0
            let promptsToProcess = prompts.filter { $0.promptTags == "" }
            let total = promptsToProcess.count
            for prompt in promptsToProcess {
               // if prompt.detailedPrompt != "" {continue}
                // Wait if we've hit the concurrency limit
                if activeTaskCount >= concurrentLimit {
                    await group.next()
                    activeTaskCount -= 1
                }
                
                group.addTask {
                    await rateLimiter.waitForNextSlot()
                    await tokenLimiter.waitForTokenSlot(needed: 2210)
                    
                    print("\(self.timestamp()) -  🔄 Regenerating prompt: \(prompt.id.prefix(8))")
                    
                    // Retry logic with exponential backoff
                    var success = false
                    var retryCount = 0
                    let maxRetries = 3
                    
                    while !success && retryCount < maxRetries {
                        do {
                            if retryCount > 0 {
                                let backoffDelay = min(pow(2.0, Double(retryCount)) * 5.0, 60.0) // Max 60s
                                print("\(self.timestamp()) - 🔄 Retry \(retryCount) for \(prompt.id.prefix(8)) in \(String(format: "%.1f", backoffDelay))s")
                                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                            }
                            
                            await self.regeneratePrompt(prompt)
                            success = true
                            
                            let current = await counter.increment()
                            print("\(self.timestamp()) - ✅ [\(current)/\(total)] Completed: \(prompt.id.prefix(8))")
                            
                        } catch {
                            retryCount += 1
                            print("❌ Attempt \(retryCount) failed for \(prompt.id.prefix(8)): \(error.localizedDescription)")
                            
                            if retryCount >= maxRetries {
                                let failures = await counter.recordFailure()
                                print("💥 [\(failures) failed] Giving up on: \(prompt.id.prefix(8))")
                            }
                        }
                    }
                }
                activeTaskCount += 1
            }
            
            await group.waitForAll()
        }
        
        let (completed, failed) = await counter.getStats()
        print("🎉 Regeneration complete!")
        print("✅ Successful: \(completed)/\(total)")
        print("❌ Failed: \(failed)/\(total)")
        
        if failed > 0 {
            print("💡 Consider reducing concurrentLimit or requestsPerMinute if you see many failures")
        }
    }

    // Alternative version with more conservative settings for ChatGPT-4o
    func regenerateAllPromptsConservative() async {
        await regenerateAllPromptsWithRateLimit(
            concurrentLimit: 2,        // Very conservative concurrency
            requestsPerMinute: 100     // Well under the 200/min limit
        )
    }

    // Aggressive version (use with caution)
    func regenerateAllPromptsAggressive() async {
        await regenerateAllPromptsWithRateLimit(
            concurrentLimit: 4,        // Higher concurrency
            requestsPerMinute: 11     // Close to limit but with buffer
        )
    }
    
    func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

// Assumes ImagePrompt is already defined elsewhere
