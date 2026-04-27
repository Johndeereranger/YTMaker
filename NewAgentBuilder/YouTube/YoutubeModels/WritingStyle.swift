//
//  WritingStyle.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//
import Foundation

// MARK: - WritingStyle (collection: writingStyles/{styleId})

// MARK: - StyleProfile (collection: styleProfiles/{profileId})

struct StyleProfile: Codable, Identifiable, Hashable, Equatable {
    var id: String { profileId }
    var profileId: String
    var channelId: String
    var name: String
    var description: String
    var triggerTopics: [String]
    
    // Centroid - flattened
    var centroidAvgTurnPosition: Double
    var centroidAvgSectionCount: Double
    var centroidAvgBeatCount: Double
    var centroidBeatDistribution: [String: Double]
    var centroidStanceDistribution: [String: Double]
    var centroidTempoDistribution: [String: Double]
    
    // Choreography - flattened
    var typicalSectionSequence: [String]
    var turnPositionMean: Double
    var turnPositionStdDev: Double?
    var turnPositionMin: Double?
    var turnPositionMax: Double?
    
    // Voice - flattened
    var voiceStanceDistribution: [String: Double]
    var voiceTempoDistribution: [String: Double]
    var voiceAvgFormality: Double
    
    // Discriminators (what makes this style unique)
    var discriminators: [String]
    
    var exemplarIds: [String]
    var videoCount: Int
    var createdAt: Date
    var updatedAt: Date
    
    func hash(into hasher: inout Hasher) { hasher.combine(profileId) }
    static func == (lhs: StyleProfile, rhs: StyleProfile) -> Bool { lhs.profileId == rhs.profileId }
}


// MARK: - StyleExemplar (collection: styleExemplars/{exemplarId})

struct StyleExemplar: Codable, Identifiable, Hashable, Equatable {
    var id: String { exemplarId }
    var exemplarId: String
    var styleId: String
    var channelId: String
    var videoId: String
    var rank: Int
    var distanceFromCentroid: Double
    var rationale: String
    
    // Snippets - parallel arrays
    var snippetBeatIds: [String]
    var snippetTexts: [String]
    var snippetWhys: [String]
    
    var createdAt: Date
    
    func hash(into hasher: inout Hasher) { hasher.combine(exemplarId) }
    static func == (lhs: StyleExemplar, rhs: StyleExemplar) -> Bool { lhs.exemplarId == rhs.exemplarId }
}
