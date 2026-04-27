//
//  YouTubeInsight.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/10/26.
//


import Foundation
import FirebaseFirestore

struct YouTubeInsight: Identifiable, Codable {
    var id: String
    var channelName: String
    var videoTitle: String
    var timestamp: String
    var insightType: InsightType
    var notes: String
    var screenshotUrl: String?  // Firebase Storage URL if you want to store the image
    var extractedText: String   // Raw OCR text for reference
    var createdAt: Date
    
    enum InsightType: String, Codable, CaseIterable {
        case visualCue = "Visual Cue"
        case audio = "Audio/Phrase"
        case phrasing = "Key Phrase"
        
        var icon: String {
            switch self {
            case .visualCue: return "eye.fill"
            case .audio: return "waveform"
            case .phrasing: return "text.quote"
            }
        }
    }
    
    // Helper initializer for new insights
    init(
        channelName: String,
        videoTitle: String,
        timestamp: String,
        insightType: InsightType,
        notes: String = "",
        extractedText: String = "",
        screenshotUrl: String? = nil
    ) {
        self.id = UUID().uuidString
        self.channelName = channelName
        self.videoTitle = videoTitle
        self.timestamp = timestamp
        self.insightType = insightType
        self.notes = notes
        self.extractedText = extractedText
        self.screenshotUrl = screenshotUrl
        self.createdAt = Date()
    }
}