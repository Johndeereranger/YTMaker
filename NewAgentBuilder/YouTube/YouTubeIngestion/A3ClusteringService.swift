//
//  A3ClusteringService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//


// Services/A3ClusteringService.swift
//
//import Foundation
//import FirebaseFirestore
//
//class A3ClusteringService {
//    static let shared = A3ClusteringService()
//    
//    init() {}
//    
//    // MARK: - Main Entry Point
//    
//    func runStyleAnalysis(
//        channelId: String,
//        onProgress: @escaping (String) -> Void
//    ) async throws -> A3Result {
//        
//        // Step 1: Load videos with scriptSummary
//        onProgress("Loading analyzed videos...")
//        let videos = try await loadVideosWithSummary(channelId: channelId)
//        
//        guard videos.count >= 5 else {
//            throw A3Error.notEnoughVideos(found: videos.count, required: 5)
//        }
//        
//        // Step 2: Build feature vectors
//        onProgress("Building feature vectors...")
//        let featureVectors = videos.map { buildFeatureVector(from: $0.scriptSummary!) }
//        
//        // Step 3: Cluster (k-means, k=3-5 based on video count)
//        onProgress("Clustering into style profiles...")
//        let k = min(5, max(3, videos.count / 5))
//        let clusters = kMeansCluster(vectors: featureVectors, k: k)
//        
//        // Step 4: For each cluster, create StyleProfile
//        onProgress("Analyzing clusters...")
//        var profiles: [StyleProfile] = []
//        var exemplars: [StyleExemplar] = []
//        
//        for (clusterIndex, cluster) in clusters.enumerated() {
//            let clusterVideos = cluster.indices.map { videos[$0] }
//            
//            // Compute centroid
//            let centroid = computeCentroid(cluster.vectors)
//            
//            // LLM call: name and describe this cluster
//            onProgress("Naming style \(clusterIndex + 1) of \(clusters.count)...")
//            let (name, description, topics) = try await nameCluster(
//                videos: clusterVideos,
//                centroid: centroid
//            )
//            
//            // Select top exemplars (closest to centroid)
//            let rankedVideos = rankByDistanceFromCentroid(
//                videos: clusterVideos,
//                vectors: cluster.vectors,
//                centroid: centroid
//            )
//            
//            let profileId = UUID().uuidString
//            
//            // Create StyleProfile
//            let profile = StyleProfile(
//                profileId: profileId,
//                channelId: channelId,
//                name: name,
//                description: description,
//                triggerTopics: topics,
//                centroidAvgTurnPosition: centroid.turnPosition,
//                centroidAvgSectionCount: centroid.sectionCount,
//                centroidAvgBeatCount: centroid.beatCount,
//                centroidBeatDistribution: centroid.beatDistribution,
//                centroidStanceDistribution: centroid.stanceDistribution,
//                centroidTempoDistribution: centroid.tempoDistribution,
//                typicalSectionSequence: mostCommonSequence(clusterVideos),
//                turnPositionMean: centroid.turnPosition,
//                turnPositionStdDev: nil,
//                turnPositionMin: nil,
//                turnPositionMax: nil,
//                voiceStanceDistribution: centroid.stanceDistribution,
//                voiceTempoDistribution: centroid.tempoDistribution,
//                voiceAvgFormality: centroid.avgFormality,
//                discriminators: [], // filled later
//                exemplarIds: rankedVideos.prefix(10).map { $0.video.videoId },
//                videoCount: clusterVideos.count,
//                createdAt: Date(),
//                updatedAt: Date()
//            )
//            profiles.append(profile)
//            
//            // Create StyleExemplars
//            for (rank, ranked) in rankedVideos.prefix(10).enumerated() {
//                let exemplar = StyleExemplar(
//                    exemplarId: UUID().uuidString,
//                    styleId: profileId,  // ← Changed from profileId to styleId
//                    channelId: channelId,
//                    videoId: ranked.video.videoId,
//                    rank: rank + 1,
//                    distanceFromCentroid: ranked.distance,
//                    rationale: "",
//                    snippetBeatIds: [],
//                    snippetTexts: [],
//                    snippetWhys: [],
//                    createdAt: Date()
//                )
//                exemplars.append(exemplar)
//            }
//        }
//        
//        // Step 5: LLM call for discriminators
//        onProgress("Generating discriminators...")
//        let discriminators = try await generateDiscriminators(profiles: profiles)
//        for i in profiles.indices {
//            profiles[i].discriminators = discriminators[i]
//        }
//        
//        // Step 6: Compute global constraints
//        onProgress("Computing constraints...")
//        let constraints = computeGlobalConstraints(videos: videos)
//        let anchorFamilies = aggregateAnchorFamilies(videos: videos)
//        
//        // Step 7: Save to Firestore
//        onProgress("Saving to Firestore...")
//        try await saveResults(
//            channelId: channelId,
//            profiles: profiles,
//            exemplars: exemplars,
//            constraints: constraints,
//            anchorFamilies: anchorFamilies,
//            videoCount: videos.count
//        )
//        
//        return A3Result(
//            profiles: profiles,
//            exemplars: exemplars,
//            videosAnalyzed: videos.count
//        )
//    }
//    
//    // Add to A3ClusteringService
//
//    func loadStyleProfiles(profileIds: [String]) async throws -> [StyleProfile] {
//        let db = Firestore.firestore()
//        var profiles: [StyleProfile] = []
//        
//        for profileId in profileIds {
//            let doc = try await db.collection("styleProfiles").document(profileId).getDocument()
//            if let profile = try? doc.data(as: StyleProfile.self) {
//                profiles.append(profile)
//            }
//        }
//        
//        return profiles
//    }
//    
//    // MARK: - Data Loading
//    
//    private func loadVideosWithSummary(channelId: String) async throws -> [YouTubeVideo] {
//        let db = Firestore.firestore()
//        let snapshot = try await db.collection("videos")
//            .whereField("channelId", isEqualTo: channelId)
//            .whereField("scriptSummary", isNotEqualTo: NSNull())
//            .getDocuments()
//        
//        return try snapshot.documents.compactMap { doc in
//            try doc.data(as: YouTubeVideo.self)
//        }
//    }
//    
//    // MARK: - Feature Vector
//    
//    private func buildFeatureVector(from summary: ScriptSummary) -> FeatureVector {
//        // Normalize distributions to percentages
//        let totalBeats = Double(summary.totalBeats)
//        
//        var beatDist: [String: Double] = [:]
//        for (type, count) in summary.beatDistribution {
//            beatDist[type] = Double(count) / totalBeats
//        }
//        
//        var stanceDist: [String: Double] = [:]
//        for (stance, count) in summary.stanceCounts {
//            stanceDist[stance] = Double(count) / totalBeats
//        }
//        
//        var tempoDist: [String: Double] = [:]
//        for (tempo, count) in summary.tempoCounts {
//            tempoDist[tempo] = Double(count) / totalBeats
//        }
//        
//        return FeatureVector(
//            turnPosition: summary.turnPosition,
//            sectionCount: Double(summary.sectionCount),
//            beatCount: Double(summary.totalBeats),
//            avgFormality: summary.avgFormality,
//            avgSentenceLength: summary.avgSentenceLength,
//            questionRate: Double(summary.questionCount) / totalBeats,
//            beatDistribution: beatDist,
//            stanceDistribution: stanceDist,
//            tempoDistribution: tempoDist
//        )
//    }
//    
//    // MARK: - Clustering (simplified k-means)
//    
//    private func kMeansCluster(vectors: [FeatureVector], k: Int) -> [Cluster] {
//        // Simple k-means implementation
//        // Returns k clusters with indices into original vectors array
//        
//        guard vectors.count >= k else {
//            return [Cluster(indices: Array(0..<vectors.count), vectors: vectors)]
//        }
//        
//        // Initialize centroids randomly
//        var centroids = Array(vectors.shuffled().prefix(k))
//        var assignments = [Int](repeating: 0, count: vectors.count)
//        
//        // Iterate until convergence (max 20 iterations)
//        for _ in 0..<20 {
//            // Assign each vector to nearest centroid
//            var changed = false
//            for i in vectors.indices {
//                let nearest = centroids.indices.min(by: { 
//                    distance(vectors[i], centroids[$0]) < distance(vectors[i], centroids[$1])
//                }) ?? 0
//                
//                if assignments[i] != nearest {
//                    assignments[i] = nearest
//                    changed = true
//                }
//            }
//            
//            if !changed { break }
//            
//            // Recompute centroids
//            for c in 0..<k {
//                let clusterVectors = vectors.indices.filter { assignments[$0] == c }.map { vectors[$0] }
//                if !clusterVectors.isEmpty {
//                    centroids[c] = averageVector(clusterVectors)
//                }
//            }
//        }
//        
//        // Build cluster results
//        var clusters: [Cluster] = []
//        for c in 0..<k {
//            let indices = vectors.indices.filter { assignments[$0] == c }
//            let clusterVectors = indices.map { vectors[$0] }
//            clusters.append(Cluster(indices: Array(indices), vectors: clusterVectors))
//        }
//        
//        return clusters.filter { !$0.indices.isEmpty }
//    }
//    
//    private func distance(_ a: FeatureVector, _ b: FeatureVector) -> Double {
//        // Euclidean distance on key features
//        var sum = 0.0
//        sum += pow(a.turnPosition - b.turnPosition, 2) * 2.0  // weight turn position
//        sum += pow(a.avgFormality - b.avgFormality, 2)
//        sum += pow(a.avgSentenceLength - b.avgSentenceLength, 2) / 100.0
//        sum += pow(a.questionRate - b.questionRate, 2)
//        
//        // Distribution distance (simplified)
//        for key in Set(a.stanceDistribution.keys).union(b.stanceDistribution.keys) {
//            let aVal = a.stanceDistribution[key] ?? 0
//            let bVal = b.stanceDistribution[key] ?? 0
//            sum += pow(aVal - bVal, 2)
//        }
//        
//        return sqrt(sum)
//    }
//    
//    private func averageVector(_ vectors: [FeatureVector]) -> FeatureVector {
//        let count = Double(vectors.count)
//        
//        var avgBeatDist: [String: Double] = [:]
//        var avgStanceDist: [String: Double] = [:]
//        var avgTempoDist: [String: Double] = [:]
//        
//        for v in vectors {
//            for (k, val) in v.beatDistribution { avgBeatDist[k, default: 0] += val / count }
//            for (k, val) in v.stanceDistribution { avgStanceDist[k, default: 0] += val / count }
//            for (k, val) in v.tempoDistribution { avgTempoDist[k, default: 0] += val / count }
//        }
//        
//        return FeatureVector(
//            turnPosition: vectors.map(\.turnPosition).reduce(0, +) / count,
//            sectionCount: vectors.map(\.sectionCount).reduce(0, +) / count,
//            beatCount: vectors.map(\.beatCount).reduce(0, +) / count,
//            avgFormality: vectors.map(\.avgFormality).reduce(0, +) / count,
//            avgSentenceLength: vectors.map(\.avgSentenceLength).reduce(0, +) / count,
//            questionRate: vectors.map(\.questionRate).reduce(0, +) / count,
//            beatDistribution: avgBeatDist,
//            stanceDistribution: avgStanceDist,
//            tempoDistribution: avgTempoDist
//        )
//    }
//    
//    // MARK: - LLM Calls
//    
//    private func nameCluster(
//        videos: [YouTubeVideo],
//        centroid: FeatureVector
//    ) async throws -> (name: String, description: String, topics: [String]) {
//        // Build prompt with video titles and centroid stats
//        let titles = videos.prefix(10).map { "- \($0.title)" }.joined(separator: "\n")
//        
//        let prompt = """
//        Analyze these YouTube videos that cluster together based on writing style:
//        
//        VIDEOS:
//        \(titles)
//        
//        STYLE CHARACTERISTICS:
//        - Turn position: \(String(format: "%.0f%%", centroid.turnPosition * 100)) through the script
//        - Average formality: \(String(format: "%.1f", centroid.avgFormality))/10
//        - Stance distribution: \(centroid.stanceDistribution)
//        - Tempo distribution: \(centroid.tempoDistribution)
//        
//        Provide:
//        1. A short name for this style (2-4 words, like "INVESTIGATIVE_DEBUNK" or "PERSONAL_JOURNEY")
//        2. A 2-3 sentence description of this writing style
//        3. 3-5 topic triggers (what topics suit this style)
//        
//        Return JSON:
//        {
//          "name": "STYLE_NAME",
//          "description": "Description here...",
//          "topics": ["topic1", "topic2", "topic3"]
//        }
//        """
//        
//        // TODO: Call your AI engine here
//        // For now, return placeholder
//        return (
//            name: "STYLE_\(videos.count)",
//            description: "Auto-detected style profile",
//            topics: ["general"]
//        )
//    }
//    
//    private func generateDiscriminators(profiles: [StyleProfile]) async throws -> [[String]] {
//        // LLM compares profiles pairwise to find what makes each unique
//        // TODO: Implement actual LLM call
//        return profiles.map { _ in ["Unique characteristic 1", "Unique characteristic 2"] }
//    }
//    
//    // MARK: - Helpers
//    
//    private func computeCentroid(_ vectors: [FeatureVector]) -> FeatureVector {
//        return averageVector(vectors)
//    }
//    
//    private func rankByDistanceFromCentroid(
//        videos: [YouTubeVideo],
//        vectors: [FeatureVector],
//        centroid: FeatureVector
//    ) -> [(video: YouTubeVideo, distance: Double)] {
//        let distances = vectors.map { distance($0, centroid) }
//        let paired = zip(videos, distances).map { ($0, $1) }
//        return paired.sorted { $0.1 < $1.1 }
//    }
//    
//    private func mostCommonSequence(_ videos: [YouTubeVideo]) -> [String] {
//        var counts: [[String]: Int] = [:]
//        for video in videos {
//            if let seq = video.scriptSummary?.sectionSequence {
//                counts[seq, default: 0] += 1
//            }
//        }
//        return counts.max(by: { $0.value < $1.value })?.key ?? []
//    }
//    
//    private func computeGlobalConstraints(videos: [YouTubeVideo]) -> GlobalConstraintsData {
//        let summaries = videos.compactMap(\.scriptSummary)
//        
//        let sentenceLengths = summaries.map(\.avgSentenceLength)
//        let formalities = summaries.map(\.avgFormality)
//        
//        return GlobalConstraintsData(
//            sentenceLengthMin: sentenceLengths.min() ?? 0,
//            sentenceLengthMax: sentenceLengths.max() ?? 0,
//            sentenceLengthTarget: sentenceLengths.reduce(0, +) / Double(sentenceLengths.count),
//            formalityMin: formalities.min() ?? 0,
//            formalityMax: formalities.max() ?? 0,
//            formalityTarget: formalities.reduce(0, +) / Double(formalities.count)
//        )
//    }
//    
//    private func aggregateAnchorFamilies(videos: [YouTubeVideo]) -> AnchorFamiliesData {
//        var openers: [String: Int] = [:]
//        var turns: [String: Int] = [:]
//        var proofs: [String: Int] = [:]
//        
//        for video in videos {
//            guard let summary = video.scriptSummary else { continue }
//            for (i, text) in summary.anchorTexts.enumerated() {
//                let function = summary.anchorFunctions[safe: i] ?? ""
//                switch function.lowercased() {
//                case "opener": openers[text, default: 0] += 1
//                case "turn": turns[text, default: 0] += 1
//                case "proofframe": proofs[text, default: 0] += 1
//                default: break
//                }
//            }
//        }
//        
//        let total = Double(videos.count)
//        
//        return AnchorFamiliesData(
//            openerPhrases: Array(openers.keys.prefix(10)),
//            openerFrequencies: Array(openers.values.prefix(10)).map { Double($0) / total },
//            turnPhrases: Array(turns.keys.prefix(10)),
//            turnFrequencies: Array(turns.values.prefix(10)).map { Double($0) / total },
//            proofPhrases: Array(proofs.keys.prefix(10)),
//            proofFrequencies: Array(proofs.values.prefix(10)).map { Double($0) / total }
//        )
//    }
//    
//    // MARK: - Save to Firestore
//    
//    private func saveResults(
//        channelId: String,
//        profiles: [StyleProfile],
//        exemplars: [StyleExemplar],
//        constraints: GlobalConstraintsData,
//        anchorFamilies: AnchorFamiliesData,
//        videoCount: Int
//    ) async throws {
//        let db = Firestore.firestore()
//        
//        // Save StyleProfiles
//        for profile in profiles {
//            let data = try Firestore.Encoder().encode(profile)
//            try await db.collection("styleProfiles").document(profile.profileId).setData(data)
//        }
//        
//        // Save StyleExemplars
//        for exemplar in exemplars {
//            let data = try Firestore.Encoder().encode(exemplar)
//            try await db.collection("styleExemplars").document(exemplar.exemplarId).setData(data)
//        }
//        
//        // Update channel with A3 data
//        try await db.collection("channels").document(channelId).updateData([
//            "profileIds": profiles.map(\.profileId),
//            "scriptsAnalyzed": videoCount,
//            "lastFullClusterAt": Timestamp(date: Date()),
//            "pendingRecluster": false,
//            "constraintSentenceLengthMin": constraints.sentenceLengthMin,
//            "constraintSentenceLengthMax": constraints.sentenceLengthMax,
//            "constraintSentenceLengthTarget": constraints.sentenceLengthTarget,
//            "anchorOpenerPhrases": anchorFamilies.openerPhrases,
//            "anchorOpenerFrequencies": anchorFamilies.openerFrequencies,
//            "anchorTurnPhrases": anchorFamilies.turnPhrases,
//            "anchorTurnFrequencies": anchorFamilies.turnFrequencies,
//            "anchorProofPhrases": anchorFamilies.proofPhrases,
//            "anchorProofFrequencies": anchorFamilies.proofFrequencies
//        ])
//    }
//    
//    func runClustering(
//          channelId: String,
//          videos: [YouTubeVideo],
//          onProgress: @escaping (String) -> Void
//      ) async throws {
//          
//          onProgress("Loading scriptSummaries...")
//          
//          // 1. Load all scriptSummaries
//          var summaries: [(video: YouTubeVideo, summary: ScriptSummary)] = []
//          
//          for video in videos {
//              if let loadedVideo = try? await YouTubeFirebaseService.shared.loadVideo(videoId: video.videoId),
//                 let summary = loadedVideo.scriptSummary {
//                  summaries.append((video, summary))
//              }
//          }
//          
//          guard summaries.count >= 5 else {
//              throw A3Error.insufficientData("Need at least 5 videos with scriptSummary, found \(summaries.count)")
//          }
//          
//          onProgress("Analyzing \(summaries.count) videos...")
//          
//          // 2. Extract feature vectors
//          let features = summaries.map { extractFeatures(from: $0.summary) }
//          
//          onProgress("Running clustering algorithm...")
//          
//          // 3. Run K-means clustering (simple implementation)
//          let k = min(5, summaries.count / 2)  // Number of clusters
//          let clusters = kMeansClustering(features: features, k: k)
//          
//          onProgress("Creating style profiles...")
//          
//          // 4. Create StyleProfiles for each cluster
//          var styleProfiles: [StyleProfile] = []
//          var styleExemplars: [StyleExemplar] = []
//          
//          for (clusterIndex, memberIndices) in clusters.enumerated() {
//              let clusterSummaries = memberIndices.map { summaries[$0] }
//              
//              // Create profile
//              let profile = createStyleProfile(
//                  clusterIndex: clusterIndex,
//                  channelId: channelId,
//                  members: clusterSummaries
//              )
//              styleProfiles.append(profile)
//              
//              // Create exemplars
//              for (video, summary) in clusterSummaries {
//                  let exemplar = StyleExemplar(
//                      id: "\(channelId)_\(video.videoId)_exemplar",
//                      styleProfileId: profile.id,
//                      videoId: video.videoId,
//                      channelId: channelId,
//                      videoTitle: video.title,
//                      fitScore: calculateFitScore(summary: summary, profile: profile),
//                      createdAt: Date()
//                  )
//                  styleExemplars.append(exemplar)
//              }
//          }
//          
//          onProgress("Saving to Firebase...")
//          
//          // 5. Save everything
//          try await saveResults(
//              channelId: channelId,
//              profiles: styleProfiles,
//              exemplars: styleExemplars
//          )
//          
//          onProgress("Complete! Created \(styleProfiles.count) style profiles")
//      }
//      
//      // MARK: - Feature Extraction
//      
//      private struct FeatureVector {
//          var turnPosition: Double
//          var avgFormality: Double
//          var avgSentenceLength: Double
//          var questionDensity: Double
//          var stanceDistribution: [String: Double]
//          var tempoDistribution: [String: Double]
//          var sectionCount: Double
//          var beatDensity: Double
//      }
//      
//      private func extractFeatures(from summary: ScriptSummary) -> FeatureVector {
//          let questionDensity = Double(summary.questionCount) / Double(max(summary.totalBeats, 1))
//          let beatDensity = Double(summary.totalBeats) / Double(max(summary.sectionCount, 1))
//          
//          // Normalize stance counts to distribution
//          let totalStance = Double(summary.stanceCounts.values.reduce(0, +))
//          var stanceDistribution: [String: Double] = [:]
//          for (key, value) in summary.stanceCounts {
//              stanceDistribution[key] = totalStance > 0 ? Double(value) / totalStance : 0
//          }
//          
//          // Normalize tempo counts to distribution
//          let totalTempo = Double(summary.tempoCounts.values.reduce(0, +))
//          var tempoDistribution: [String: Double] = [:]
//          for (key, value) in summary.tempoCounts {
//              tempoDistribution[key] = totalTempo > 0 ? Double(value) / totalTempo : 0
//          }
//          
//          return FeatureVector(
//              turnPosition: summary.turnPosition,
//              avgFormality: summary.avgFormality / 10.0, // Normalize to 0-1
//              avgSentenceLength: min(summary.avgSentenceLength / 30.0, 1.0), // Normalize
//              questionDensity: min(questionDensity, 1.0),
//              stanceDistribution: stanceDistribution,
//              tempoDistribution: tempoDistribution,
//              sectionCount: Double(summary.sectionCount) / 10.0, // Normalize
//              beatDensity: beatDensity / 10.0 // Normalize
//          )
//      }
//      
//      // MARK: - Clustering
//      
//      private func kMeansClustering(features: [FeatureVector], k: Int) -> [[Int]] {
//          guard features.count >= k else {
//              return [Array(0..<features.count)]
//          }
//          
//          // Simple distance function
//          func distance(_ a: FeatureVector, _ b: FeatureVector) -> Double {
//              var sum = 0.0
//              sum += pow(a.turnPosition - b.turnPosition, 2)
//              sum += pow(a.avgFormality - b.avgFormality, 2)
//              sum += pow(a.avgSentenceLength - b.avgSentenceLength, 2)
//              sum += pow(a.questionDensity - b.questionDensity, 2)
//              sum += pow(a.sectionCount - b.sectionCount, 2)
//              sum += pow(a.beatDensity - b.beatDensity, 2)
//              return sqrt(sum)
//          }
//          
//          // Initialize centroids randomly
//          var centroids = Array(features.shuffled().prefix(k))
//          var assignments = [Int](repeating: 0, count: features.count)
//          
//          // Iterate
//          for _ in 0..<20 {
//              // Assign points to nearest centroid
//              for (i, feature) in features.enumerated() {
//                  var minDist = Double.infinity
//                  var minIndex = 0
//                  for (j, centroid) in centroids.enumerated() {
//                      let dist = distance(feature, centroid)
//                      if dist < minDist {
//                          minDist = dist
//                          minIndex = j
//                      }
//                  }
//                  assignments[i] = minIndex
//              }
//              
//              // Update centroids
//              for j in 0..<k {
//                  let members = features.enumerated().filter { assignments[$0.offset] == j }.map { $0.element }
//                  if !members.isEmpty {
//                      centroids[j] = averageFeatures(members)
//                  }
//              }
//          }
//          
//          // Group by assignment
//          var clusters: [[Int]] = Array(repeating: [], count: k)
//          for (i, assignment) in assignments.enumerated() {
//              clusters[assignment].append(i)
//          }
//          
//          return clusters.filter { !$0.isEmpty }
//      }
//      
//      private func averageFeatures(_ features: [FeatureVector]) -> FeatureVector {
//          let n = Double(features.count)
//          return FeatureVector(
//              turnPosition: features.map { $0.turnPosition }.reduce(0, +) / n,
//              avgFormality: features.map { $0.avgFormality }.reduce(0, +) / n,
//              avgSentenceLength: features.map { $0.avgSentenceLength }.reduce(0, +) / n,
//              questionDensity: features.map { $0.questionDensity }.reduce(0, +) / n,
//              stanceDistribution: [:], // Simplified
//              tempoDistribution: [:], // Simplified
//              sectionCount: features.map { $0.sectionCount }.reduce(0, +) / n,
//              beatDensity: features.map { $0.beatDensity }.reduce(0, +) / n
//          )
//      }
//      
//      // MARK: - Profile Creation
//      
//      private func createStyleProfile(
//          clusterIndex: Int,
//          channelId: String,
//          members: [(video: YouTubeVideo, summary: ScriptSummary)]
//      ) -> StyleProfile {
//          
//          let summaries = members.map { $0.summary }
//          
//          // Aggregate statistics
//          let avgFormality = summaries.map { $0.avgFormality }.reduce(0, +) / Double(summaries.count)
//          let avgTurnPosition = summaries.map { $0.turnPosition }.reduce(0, +) / Double(summaries.count)
//          let avgSentenceLength = summaries.map { $0.avgSentenceLength }.reduce(0, +) / Double(summaries.count)
//          let avgQuestionCount = Double(summaries.map { $0.questionCount }.reduce(0, +)) / Double(summaries.count)
//          
//          // Aggregate section sequences (find most common)
//          var sectionSequenceCounts: [String: Int] = [:]
//          for summary in summaries {
//              let key = summary.sectionSequence.joined(separator: "-")
//              sectionSequenceCounts[key, default: 0] += 1
//          }
//          let commonSequence = sectionSequenceCounts.max(by: { $0.value < $1.value })?.key ?? ""
//          
//          // Aggregate stance distribution
//          var aggregatedStance: [String: Int] = [:]
//          for summary in summaries {
//              for (stance, count) in summary.stanceCounts {
//                  aggregatedStance[stance, default: 0] += count
//              }
//          }
//          
//          // Aggregate tempo distribution
//          var aggregatedTempo: [String: Int] = [:]
//          for summary in summaries {
//              for (tempo, count) in summary.tempoCounts {
//                  aggregatedTempo[tempo, default: 0] += count
//              }
//          }
//          
//          // Generate name based on characteristics
//          let styleName = generateStyleName(
//              formality: avgFormality,
//              turnPosition: avgTurnPosition,
//              questionDensity: avgQuestionCount / 20.0
//          )
//          
//          return StyleProfile(
//              id: "\(channelId)_style_\(clusterIndex)",
//              channelId: channelId,
//              name: styleName,
//              description: "Detected writing pattern from \(members.count) videos",
//              avgFormality: avgFormality,
//              avgTurnPosition: avgTurnPosition,
//              avgSentenceLength: avgSentenceLength,
//              avgQuestionDensity: avgQuestionCount / 20.0,
//              commonSectionSequence: commonSequence.split(separator: "-").map { String($0) },
//              stanceDistribution: aggregatedStance,
//              tempoDistribution: aggregatedTempo,
//              videoCount: members.count,
//              exemplarVideoIds: members.map { $0.video.videoId },
//              createdAt: Date(),
//              updatedAt: Date()
//          )
//      }
//      
//      private func generateStyleName(formality: Double, turnPosition: Double, questionDensity: Double) -> String {
//          var parts: [String] = []
//          
//          // Formality descriptor
//          if formality < 4 {
//              parts.append("Casual")
//          } else if formality > 7 {
//              parts.append("Formal")
//          } else {
//              parts.append("Balanced")
//          }
//          
//          // Turn position descriptor
//          if turnPosition < 0.3 {
//              parts.append("Early-Turn")
//          } else if turnPosition > 0.7 {
//              parts.append("Late-Turn")
//          } else {
//              parts.append("Mid-Turn")
//          }
//          
//          // Question density descriptor
//          if questionDensity > 0.3 {
//              parts.append("Question-Heavy")
//          } else if questionDensity < 0.1 {
//              parts.append("Statement-Based")
//          }
//          
//          return parts.joined(separator: " ")
//      }
//      
//      private func calculateFitScore(summary: ScriptSummary, profile: StyleProfile) -> Double {
//          // Simple fit score based on how close video is to profile averages
//          var score = 1.0
//          
//          score -= abs(summary.avgFormality - profile.avgFormality) / 10.0 * 0.25
//          score -= abs(summary.turnPosition - profile.avgTurnPosition) * 0.25
//          score -= abs(summary.avgSentenceLength - profile.avgSentenceLength) / 30.0 * 0.25
//          
//          return max(0, min(1, score))
//      }
//      
//      // MARK: - Persistence
//      
//      private func saveResults(
//          channelId: String,
//          profiles: [StyleProfile],
//          exemplars: [StyleExemplar]
//      ) async throws {
//          // Save profiles
//          for profile in profiles {
//              try await CreatorAnalysisFirebase.shared.saveStyleProfile(profile)
//          }
//          
//          // Save exemplars
//          for exemplar in exemplars {
//              try await CreatorAnalysisFirebase.shared.saveStyleExemplar(exemplar)
//          }
//          
//          // Update channel with style IDs
//          let styleIds = profiles.map { $0.id }
//          try await YouTubeFirebaseService.shared.updateChannelStyleIds(
//              channelId: channelId,
//              styleIds: styleIds
//          )
//      }
//}
//
//// MARK: - Supporting Types
//
//struct FeatureVector {
//    var turnPosition: Double
//    var sectionCount: Double
//    var beatCount: Double
//    var avgFormality: Double
//    var avgSentenceLength: Double
//    var questionRate: Double
//    var beatDistribution: [String: Double]
//    var stanceDistribution: [String: Double]
//    var tempoDistribution: [String: Double]
//}
//
//struct Cluster {
//    var indices: [Int]
//    var vectors: [FeatureVector]
//}
//
//struct A3Result {
//    var profiles: [StyleProfile]
//    var exemplars: [StyleExemplar]
//    var videosAnalyzed: Int
//}
//
//struct GlobalConstraintsData {
//    var sentenceLengthMin: Double
//    var sentenceLengthMax: Double
//    var sentenceLengthTarget: Double
//    var formalityMin: Double
//    var formalityMax: Double
//    var formalityTarget: Double
//}
//
//struct AnchorFamiliesData {
//    var openerPhrases: [String]
//    var openerFrequencies: [Double]
//    var turnPhrases: [String]
//    var turnFrequencies: [Double]
//    var proofPhrases: [String]
//    var proofFrequencies: [Double]
//}
//
//enum A3Error: LocalizedError {
//    case notEnoughVideos(found: Int, required: Int)
//    
//    var errorDescription: String? {
//        switch self {
//        case .notEnoughVideos(let found, let required):
//            return "Need at least \(required) analyzed videos. Found: \(found)"
//        }
//    }
//}
////
////// Safe array subscript
////extension Array {
////    subscript(safe index: Int) -> Element? {
////        return indices.contains(index) ? self[index] : nil
////    }
////}


import Foundation

/// A3 Clustering Service
/// Purpose: Cluster analyzed videos by their ScriptSummary data to detect writing patterns.
/// Goal: When you have a new outline/topic, find similar scripts from your analyzed library.
class A3ClusteringService {
    
    // MARK: - Public Entry Point
    
    /// Run clustering analysis on videos that have scriptSummary
    /// Requires: At least 5 videos with scriptSummary
    func runClustering(
        channelId: String,
        videos: [YouTubeVideo],
        onProgress: @escaping (String) -> Void
    ) async throws {
        
        // 1. Filter to videos with scriptSummary
        let videosWithSummary = videos.filter { $0.scriptSummary != nil }
        
        guard videosWithSummary.count >= 5 else {
            throw A3Error.insufficientData("Need at least 5 videos with scriptSummary, found \(videosWithSummary.count)")
        }
        
        onProgress("Analyzing \(videosWithSummary.count) videos...")
        
        // 2. Extract numeric features from each ScriptSummary
        var videoFeatures: [(video: YouTubeVideo, features: [Double])] = []
        
        for video in videosWithSummary {
            guard let summary = video.scriptSummary else { continue }
            let features = extractFeatures(from: summary)
            videoFeatures.append((video, features))
        }
        
        onProgress("Running clustering algorithm...")
        
        // 3. Determine number of clusters (k)
        // Rule: k = min(5, count/3) - at least 3 videos per cluster
        let k = max(2, min(5, videosWithSummary.count / 3))
        
        // 4. Run K-means clustering
        let assignments = kMeansClustering(
            features: videoFeatures.map { $0.features },
            k: k,
            maxIterations: 50
        )
        
        onProgress("Creating \(k) style profiles...")
        
        // 5. Group videos by cluster
        var clusters: [[Int]] = Array(repeating: [], count: k)
        for (index, clusterIndex) in assignments.enumerated() {
            clusters[clusterIndex].append(index)
        }
        
        // 6. Create StyleProfiles and StyleExemplars
        var profileIds: [String] = []
        
        for (clusterIndex, memberIndices) in clusters.enumerated() where !memberIndices.isEmpty {
            let members = memberIndices.map { videoFeatures[$0] }
            
            onProgress("Creating profile \(clusterIndex + 1) from \(members.count) videos...")
            
            // Create profile
            let profile = createStyleProfile(
                clusterIndex: clusterIndex,
                channelId: channelId,
                members: members
            )
            
            // Save profile
            try await CreatorAnalysisFirebase.shared.saveStyleProfile(profile)
            profileIds.append(profile.profileId)
            
            // Create and save exemplars (top 5 closest to centroid)
            let exemplars = createExemplars(
                profile: profile,
                members: members,
                maxExemplars: 5
            )
            try await CreatorAnalysisFirebase.shared.saveStyleExemplars(exemplars)
        }
        
        onProgress("Updating channel...")
        
        // 7. Update channel with profileIds
        try await YouTubeFirebaseService.shared.updateChannelProfileIds(
            channelId: channelId,
            profileIds: profileIds
        )
        
        try await YouTubeFirebaseService.shared.updateChannelScriptsAnalyzed(
            channelId: channelId,
            count: videosWithSummary.count
        )
        
        onProgress("✅ Created \(profileIds.count) style profiles from \(videosWithSummary.count) videos")
    }
    
    // MARK: - Feature Extraction
    
    /// Extract numeric features from ScriptSummary for clustering
    /// Returns a normalized feature vector
    private func extractFeatures(from summary: ScriptSummary) -> [Double] {
        var features: [Double] = []
        
        // 1. Structure features
        features.append(summary.turnPosition)  // Already 0-1
        features.append(normalize(Double(summary.sectionCount), min: 3, max: 10))
        features.append(normalize(Double(summary.totalBeats), min: 10, max: 50))
        
        // 2. Voice features
        features.append(normalize(summary.avgFormality, min: 1, max: 10))
        features.append(normalize(summary.avgSentenceLength, min: 5, max: 30))
        features.append(normalize(Double(summary.questionCount), min: 0, max: 20))
        
        // 3. Stance distribution (convert counts to percentages)
        let totalStance = Double(summary.stanceCounts.values.reduce(0, +))
        let stanceTypes = ["critical", "neutral", "playful", "helpful", "authoritative"]
        for stance in stanceTypes {
            let count = Double(summary.stanceCounts[stance] ?? 0)
            features.append(totalStance > 0 ? count / totalStance : 0)
        }
        
        // 4. Tempo distribution
        let totalTempo = Double(summary.tempoCounts.values.reduce(0, +))
        let tempoTypes = ["fast", "steady", "slow_build"]
        for tempo in tempoTypes {
            let count = Double(summary.tempoCounts[tempo] ?? 0)
            features.append(totalTempo > 0 ? count / totalTempo : 0)
        }
        
        // 5. Beat distribution (top beat types)
        let totalBeats = Double(summary.beatDistribution.values.reduce(0, +))
        let beatTypes = ["TEASE", "DATA", "QUESTION", "STORY", "CONTEXT", "PROMISE", "PAYOFF"]
        for beatType in beatTypes {
            let count = Double(summary.beatDistribution[beatType] ?? 0)
            features.append(totalBeats > 0 ? count / totalBeats : 0)
        }
        
        return features
    }
    
    /// Normalize a value to 0-1 range
    private func normalize(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0.5 }
        return Swift.max(0, Swift.min(1, (value - min) / (max - min)))
    }
    
    // MARK: - K-Means Clustering
    
    /// Simple K-means clustering implementation
    private func kMeansClustering(features: [[Double]], k: Int, maxIterations: Int) -> [Int] {
        guard !features.isEmpty, k > 0 else { return [] }
        
        let n = features.count
        let dim = features[0].count
        
        // Initialize centroids randomly (pick k random points)
        var centroids: [[Double]] = []
        var usedIndices: Set<Int> = []
        
        while centroids.count < k && usedIndices.count < n {
            let randomIndex = Int.random(in: 0..<n)
            if !usedIndices.contains(randomIndex) {
                usedIndices.insert(randomIndex)
                centroids.append(features[randomIndex])
            }
        }
        
        // If we couldn't get k distinct points, pad with first points
        while centroids.count < k {
            centroids.append(features[centroids.count % n])
        }
        
        var assignments = Array(repeating: 0, count: n)
        
        for _ in 0..<maxIterations {
            // Assign each point to nearest centroid
            var newAssignments = Array(repeating: 0, count: n)
            
            for i in 0..<n {
                var minDist = Double.infinity
                var bestCluster = 0
                
                for c in 0..<k {
                    let dist = euclideanDistance(features[i], centroids[c])
                    if dist < minDist {
                        minDist = dist
                        bestCluster = c
                    }
                }
                
                newAssignments[i] = bestCluster
            }
            
            // Check for convergence
            if newAssignments == assignments {
                break
            }
            assignments = newAssignments
            
            // Update centroids
            for c in 0..<k {
                let members = (0..<n).filter { assignments[$0] == c }
                
                if members.isEmpty {
                    // Empty cluster - keep previous centroid
                    continue
                }
                
                // Compute mean of members
                var newCentroid = Array(repeating: 0.0, count: dim)
                for memberIndex in members {
                    for d in 0..<dim {
                        newCentroid[d] += features[memberIndex][d]
                    }
                }
                for d in 0..<dim {
                    newCentroid[d] /= Double(members.count)
                }
                centroids[c] = newCentroid
            }
        }
        
        return assignments
    }
    
    /// Euclidean distance between two feature vectors
    private func euclideanDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return Double.infinity }
        var sum = 0.0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sqrt(sum)
    }
    
    // MARK: - Profile Creation
    
    /// Create a StyleProfile from a cluster of videos
    private func createStyleProfile(
        clusterIndex: Int,
        channelId: String,
        members: [(video: YouTubeVideo, features: [Double])]
    ) -> StyleProfile {
        
        let summaries = members.compactMap { $0.video.scriptSummary }
        guard !summaries.isEmpty else {
            return emptyProfile(clusterIndex: clusterIndex, channelId: channelId)
        }
        
        let count = Double(summaries.count)
        
        // Aggregate turn positions
        let turnPositions = summaries.map { $0.turnPosition }
        let turnMean = turnPositions.reduce(0, +) / count
        let turnStdDev = standardDeviation(turnPositions)
        
        // Aggregate section counts
        let sectionCounts = summaries.map { Double($0.sectionCount) }
        let avgSectionCount = sectionCounts.reduce(0, +) / count
        
        // Aggregate beat counts
        let beatCounts = summaries.map { Double($0.totalBeats) }
        let avgBeatCount = beatCounts.reduce(0, +) / count
        
        // Aggregate formality
        let formalities = summaries.map { $0.avgFormality }
        let avgFormality = formalities.reduce(0, +) / count
        
        // Aggregate stance distribution (normalized)
        var stanceAgg: [String: Double] = [:]
        for summary in summaries {
            let total = Double(summary.stanceCounts.values.reduce(0, +))
            guard total > 0 else { continue }
            for (stance, count) in summary.stanceCounts {
                stanceAgg[stance, default: 0] += Double(count) / total
            }
        }
        for key in stanceAgg.keys {
            stanceAgg[key] = (stanceAgg[key] ?? 0) / count
        }
        
        // Aggregate tempo distribution (normalized)
        var tempoAgg: [String: Double] = [:]
        for summary in summaries {
            let total = Double(summary.tempoCounts.values.reduce(0, +))
            guard total > 0 else { continue }
            for (tempo, count) in summary.tempoCounts {
                tempoAgg[tempo, default: 0] += Double(count) / total
            }
        }
        for key in tempoAgg.keys {
            tempoAgg[key] = (tempoAgg[key] ?? 0) / count
        }
        
        // Aggregate beat distribution (normalized)
        var beatAgg: [String: Double] = [:]
        for summary in summaries {
            let total = Double(summary.beatDistribution.values.reduce(0, +))
            guard total > 0 else { continue }
            for (beatType, count) in summary.beatDistribution {
                beatAgg[beatType, default: 0] += Double(count) / total
            }
        }
        for key in beatAgg.keys {
            beatAgg[key] = (beatAgg[key] ?? 0) / count
        }
        
        // Find most common section sequence
        var sequenceCounts: [String: Int] = [:]
        for summary in summaries {
            let key = summary.sectionSequence.joined(separator: "→")
            sequenceCounts[key, default: 0] += 1
        }
        let typicalSequence = sequenceCounts.max(by: { $0.value < $1.value })?.key ?? ""
        
        // Generate descriptive name
        let name = generateProfileName(
            turnPosition: turnMean,
            dominantStance: stanceAgg.max(by: { $0.value < $1.value })?.key ?? "neutral",
            dominantTempo: tempoAgg.max(by: { $0.value < $1.value })?.key ?? "steady"
        )
        
        // Generate description
        let description = generateProfileDescription(
            videoCount: members.count,
            avgFormality: avgFormality,
            turnPosition: turnMean,
            stanceDistribution: stanceAgg,
            tempoDistribution: tempoAgg
        )
        
        return StyleProfile(
            profileId: "\(channelId)_profile_\(clusterIndex)",
            channelId: channelId,
            name: name,
            description: description,
            triggerTopics: [],  // Could be enhanced with LLM later
            centroidAvgTurnPosition: turnMean,
            centroidAvgSectionCount: avgSectionCount,
            centroidAvgBeatCount: avgBeatCount,
            centroidBeatDistribution: beatAgg,
            centroidStanceDistribution: stanceAgg,
            centroidTempoDistribution: tempoAgg,
            typicalSectionSequence: typicalSequence.split(separator: "→").map(String.init),
            turnPositionMean: turnMean,
            turnPositionStdDev: turnStdDev,
            turnPositionMin: turnPositions.min(),
            turnPositionMax: turnPositions.max(),
            voiceStanceDistribution: stanceAgg,
            voiceTempoDistribution: tempoAgg,
            voiceAvgFormality: avgFormality,
            discriminators: [],  // Could be enhanced with LLM later
            exemplarIds: [],  // Will be filled after exemplars are created
            videoCount: members.count,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    /// Create an empty profile (edge case)
    private func emptyProfile(clusterIndex: Int, channelId: String) -> StyleProfile {
        return StyleProfile(
            profileId: "\(channelId)_profile_\(clusterIndex)",
            channelId: channelId,
            name: "Profile \(clusterIndex + 1)",
            description: "Empty profile",
            triggerTopics: [],
            centroidAvgTurnPosition: 0.5,
            centroidAvgSectionCount: 5,
            centroidAvgBeatCount: 20,
            centroidBeatDistribution: [:],
            centroidStanceDistribution: [:],
            centroidTempoDistribution: [:],
            typicalSectionSequence: [],
            turnPositionMean: 0.5,
            turnPositionStdDev: nil,
            turnPositionMin: nil,
            turnPositionMax: nil,
            voiceStanceDistribution: [:],
            voiceTempoDistribution: [:],
            voiceAvgFormality: 5.0,
            discriminators: [],
            exemplarIds: [],
            videoCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    // MARK: - Exemplar Creation
    
    /// Create StyleExemplars for videos closest to the cluster centroid
    private func createExemplars(
        profile: StyleProfile,
        members: [(video: YouTubeVideo, features: [Double])],
        maxExemplars: Int
    ) -> [StyleExemplar] {
        
        guard !members.isEmpty else { return [] }
        
        // Compute centroid from all member features
        let dim = members[0].features.count
        var centroid = Array(repeating: 0.0, count: dim)
        for member in members {
            for d in 0..<dim {
                centroid[d] += member.features[d]
            }
        }
        for d in 0..<dim {
            centroid[d] /= Double(members.count)
        }
        
        // Calculate distance from centroid for each member
        var distances: [(index: Int, distance: Double)] = []
        for (index, member) in members.enumerated() {
            let dist = euclideanDistance(member.features, centroid)
            distances.append((index, dist))
        }
        
        // Sort by distance (closest first)
        distances.sort { $0.distance < $1.distance }
        
        // Create exemplars for top N
        var exemplars: [StyleExemplar] = []
        let topN = min(maxExemplars, distances.count)
        
        for rank in 0..<topN {
            let memberIndex = distances[rank].index
            let video = members[memberIndex].video
            let distance = distances[rank].distance
            
            let exemplar = StyleExemplar(
                exemplarId: "\(profile.profileId)_ex_\(rank)",
                styleId: profile.profileId,
                channelId: profile.channelId,
                videoId: video.videoId,
                rank: rank + 1,
                distanceFromCentroid: distance,
                rationale: "Rank \(rank + 1) closest to cluster centroid (distance: \(String(format: "%.3f", distance)))",
                snippetBeatIds: [],  // Could be enhanced by loading beats
                snippetTexts: [],
                snippetWhys: [],
                createdAt: Date()
            )
            exemplars.append(exemplar)
        }
        
        return exemplars
    }
    
    // MARK: - Helper Functions
    
    /// Calculate standard deviation
    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
    
    /// Generate a descriptive profile name
    private func generateProfileName(
        turnPosition: Double,
        dominantStance: String,
        dominantTempo: String
    ) -> String {
        
        var parts: [String] = []
        
        // Turn position descriptor
        if turnPosition < 0.4 {
            parts.append("Early-Turn")
        } else if turnPosition > 0.7 {
            parts.append("Late-Turn")
        } else {
            parts.append("Mid-Turn")
        }
        
        // Stance descriptor
        switch dominantStance {
        case "critical":
            parts.append("Critical")
        case "playful":
            parts.append("Playful")
        case "authoritative":
            parts.append("Authoritative")
        case "helpful":
            parts.append("Helpful")
        default:
            parts.append("Balanced")
        }
        
        // Tempo descriptor
        switch dominantTempo {
        case "fast":
            parts.append("Fast-Paced")
        case "slow_build":
            parts.append("Building")
        default:
            break  // Don't add for "steady"
        }
        
        return parts.joined(separator: " ")
    }
    
    /// Generate a descriptive profile description
    private func generateProfileDescription(
        videoCount: Int,
        avgFormality: Double,
        turnPosition: Double,
        stanceDistribution: [String: Double],
        tempoDistribution: [String: Double]
    ) -> String {
        
        var description = "Writing pattern from \(videoCount) videos. "
        
        // Formality
        if avgFormality < 4 {
            description += "Casual, conversational tone. "
        } else if avgFormality > 7 {
            description += "Formal, professional tone. "
        } else {
            description += "Moderate formality. "
        }
        
        // Turn position
        let turnPercent = Int(turnPosition * 100)
        description += "Key turn typically at \(turnPercent)% through the video. "
        
        // Dominant stance
        if let topStance = stanceDistribution.max(by: { $0.value < $1.value }),
           topStance.value > 0.4 {
            let pct = Int(topStance.value * 100)
            description += "Predominantly \(topStance.key) stance (\(pct)%)."
        }
        
        return description
    }
}

// MARK: - Error Types

enum A3Error: LocalizedError {
    case insufficientData(String)
    case clusteringFailed(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientData(let msg): return "Insufficient data: \(msg)"
        case .clusteringFailed(let msg): return "Clustering failed: \(msg)"
        case .saveFailed(let msg): return "Save failed: \(msg)"
        }
    }
}
