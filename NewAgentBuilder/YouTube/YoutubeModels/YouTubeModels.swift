//
//  YouTubeModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/3/26.
//
import SwiftUI
// MARK: - Script Breakdown Models

struct ScriptSentence: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isSelected: Bool
    var isTyped: Bool  // For typing mode
    
    init(id: UUID = UUID(), text: String, isSelected: Bool = false, isTyped: Bool = false) {
        self.id = id
        self.text = text
        self.isSelected = isSelected
        self.isTyped = isTyped
    }
}

struct MarkedPattern: Identifiable, Codable, Equatable {
    let id: UUID
    var type: PatternType
    var sentenceIds: [UUID]              // CHANGED: was position, now sentenceIds
    var note: String?
    var sectionId: UUID?
    var extractedToPlaybook: Bool
    
    // Computed property for display
    var snippet: String {
        // Will generate snippet from sentences when displayed
        return ""  // Placeholder for now
    }
    
    init(id: UUID = UUID(), type: PatternType, sentenceIds: [UUID], note: String? = nil, sectionId: UUID? = nil) {
        self.id = id
        self.type = type
        self.sentenceIds = sentenceIds
        self.note = note
        self.sectionId = sectionId
        self.extractedToPlaybook = false
    }
}

//struct OutlineSection: Identifiable, Codable, Equatable {
//    let id: UUID
//    var name: String
//    var startSentenceId: UUID           // CHANGED
//    var endSentenceId: UUID?            // CHANGED
//    var purpose: String?
//    var patternIds: [UUID]
//    
//    init(id: UUID = UUID(), name: String, startSentenceId: UUID, endSentenceId: UUID? = nil, purpose: String? = nil) {
//        self.id = id
//        self.name = name
//        self.startSentenceId = startSentenceId
//        self.endSentenceId = endSentenceId
//        self.purpose = purpose
//        self.patternIds = []
//    }
//}



struct ScriptBreakdown: Codable, Equatable {
    var sentences: [ScriptSentence]
    var sections: [OutlineSection]
    var allMarkedPatterns: [MarkedPattern]
    var lastEditedDate: Date
    
    init() {
        self.sentences = []
        self.sections = []
        self.allMarkedPatterns = []
        self.lastEditedDate = Date()
    }
}
enum PatternType: String, Codable, CaseIterable {
    case question = "Q"
    case delay = "DELAY"
    case tease = "TEASE"
    case data = "DATA"
    case turn = "TURN"
    case ramble = "RAMBLE"
    case crossPromo = "CROSS"
    case authority = "AUTH"
    
    // Credibility inflation mechanics
    case shield = "SHIELD"
    case pattern = "Obs Pattern"
    case scope = "SCOPE"
    case effortTrust = "EFFORT"
    case engageTrap = "ENGAGE"
    case mystery = "MYSTERY"
    
    // Content capture (not analysis patterns)
    case fact = "FACT"
    case phrase = "PHRASE"
    
    var icon: String {
        switch self {
        case .question: return "questionmark.circle"
        case .delay: return "pause.circle"
        case .tease: return "eye.circle"
        case .data: return "chart.bar.circle"
        case .turn: return "arrow.turn.up.right"
        case .ramble: return "bubble.left.circle"
        case .crossPromo: return "link.circle"
        case .authority: return "checkmark.seal.fill"
        case .shield: return "shield.circle"
        case .pattern: return "repeat.circle"
        case .scope: return "arrow.up.backward.and.arrow.down.forward.circle"
        case .effortTrust: return "hammer.circle"
        case .engageTrap: return "hand.raised.circle"
        case .mystery: return "sparkles.circle"
        case .fact: return "info.circle.fill"
           case .phrase: return "text.quote"
        }
    }
    
    var color: Color {
        switch self {
        case .question: return .blue
        case .delay: return .orange
        case .tease: return .purple
        case .data: return .green
        case .turn: return .red
        case .ramble: return .brown
        case .crossPromo: return .pink
        case .authority: return .indigo
        case .shield: return .yellow
        case .pattern: return .mint
        case .scope: return .cyan
        case .effortTrust: return .gray
        case .engageTrap: return .teal
        case .mystery: return Color(red: 0.6, green: 0.4, blue: 0.8) // Mystical purple
        case .fact: return .blue
        case .phrase: return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        }
    }
    
    var description: String {
        switch self {
        case .question:
            return "Any question (explicit or implied) that creates curiosity and makes the viewer predict what's coming next."
        case .delay:
            return "Explicitly postponing the answer to a question or promise. The creator COULD reveal something now but chooses to withhold it."
        case .tease:
            return "Hints at upcoming payoff or promises something interesting is coming without revealing what it is yet. Creates anticipation."
        case .data:
            return "Specific, verifiable facts, statistics, or concrete details. These are provable claims with precision."
        case .turn:
            return "Pivot words that signal a shift in direction or contradict what was just established. Changes the viewer's expectation."
        case .ramble:
            return "Tangential details or side stories that may seem unfocused but often add authenticity or context."
        case .crossPromo:
            return "References to other videos, content, or platforms. Used to build continuity and drive traffic without being pushy."
        case .authority:
            return "Stated credentials, experience claims, or explicit expertise declarations. Establishes credibility through who you are or what you've done, not just current data."
        case .shield:
            return "Pre-emptive language that forgives uncertainty or speculation. Makes interpretation acceptable and disarms criticism."
        case .pattern:
            return "Claims about trends or repeated behavior WITHOUT specific statistics. Converts anecdotes into implied frequency."
        case .scope:
            return "Large time/effort claims without clear boundaries or sample sizes. Creates impression of comprehensive research."
        case .effortTrust:
            return "Specific details about constraints, costs, or friction that prove authenticity. 'Who would fake this much boring detail?'"
        case .engageTrap:
            return "Questions or prompts that make the viewer mentally participate, which reduces skepticism."
        case .mystery:
            return "Attributing intelligence, awareness, or almost mystical qualities to the animal. Makes the subject fascinating and unknowable."
        case .fact:
            return "Key factual information worth saving for future reference. Not for pattern analysis."
        case .phrase:
            return "Well-crafted wording worth reusing. Not for pattern analysis."
        }
    }

    var examples: [String] {
        switch self {
        case .question:
            return [
                "Why do bucks bed 200 yards away from food sources?",
                "What happened to Buck 52 after rifle season started?",
                "The question everyone asks: do mature bucks really go nocturnal?"
            ]
        case .delay:
            return [
                "But before I get into that, let me show you what the property was like last season...",
                "I'll explain why he moved in a minute, but first you need to understand the wind patterns..."
            ]
        case .tease:
            return [
                "Here's where it gets interesting...",
                "What I found next completely changed my understanding...",
                "Wait until you see what happened on day 12..."
            ]
        case .data:
            return [
                "I tracked this deer for exactly 200 hours",
                "He bedded at 9:25 a.m., stood at 2:15 p.m.",
                "308 instances recorded vs 59 trail camera photos"
            ]
        case .turn:
            return [
                "But when I looked at the data, the pattern was completely different...",
                "However, this buck did the opposite of what I expected..."
            ]
        case .ramble:
            return [
                "I got distracted by a bobcat that was hunting in the soybeans...",
                "There was a suspicious car slowing down near my drone..."
            ]
        case .crossPromo:
            return [
                "If you watch my past videos, you'll know this property had really good acorn mast...",
                "In future videos, I promise to address thermal hubs in much deeper context...",
                "I'll cover that in another video"
            ]
        case .authority:
            return [
                    // Earned authority (credentials/experience)
                    "I studied this buck more than any other deer last season.",
                    "I've learned this the hard way so you don't have to.",
                    "This is something most hunters completely miss.",
                    
                    // Asserted authority (curation/framing)
                    "There's a lot, and I'll try to move through them pretty quickly.",
                    "This takes us to my favorite question.",
                    "My favorite statistic is that I've only recorded him walking into a field two times.",
                    "Here's what really matters in this scenario.",
                    "I won't go deep into this topic right now—there's going to be an entire video on it soon.",
                    "Let that settle in.",
                    
                    // Combined (both types working together)
                    "Trust me—this is where guys get it wrong every year.",
                    "It's my job to point out what actually matters here."
                ]
        case .shield:
            return [
                "This is where my research introduces a touch of human interpretation...",
                "I think it's because... but there's a chance..."
            ]
        case .pattern:
            return [
                "Time and time again, I've seen mature bucks do this...",
                "One of the most consistent patterns I've studied..."
            ]
        case .scope:
            return [
                "Over 9 months of research...",
                "After countless hours in the field..."
            ]
        case .effortTrust:
            return [
                "My batteries only last 30-40 minutes, so I have to swap mid-flight...",
                "It's been 19 days since I last found him. Still searching..."
            ]
        case .engageTrap:
            return [
                "So how would YOU hunt this scenario?",
                "Before I show you what happened, pause and think: what would you expect?"
            ]
        case .mystery:
            return [
                "This continues to show a clear sign of intelligence for whitetail deer and their capabilities for thinking out day-to-day actions.",
                "Their day-to-day decisions often suggest a level of awareness and intent that is pretty easy to underestimate.",
                "I think he knew he was leaving the area, so he prepared for his trip and vanished into the night."
            ]
        case .fact:
            return [] // User-captured content, no template examples
        case .phrase:
            return [] // User-captured content, no template examples
        }
    }
}
