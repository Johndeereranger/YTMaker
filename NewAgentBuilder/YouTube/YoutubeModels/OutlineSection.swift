////
////  OutlineSection.swift
////  NewAgentBuilder
////
////  Created by Byron Smith on 1/5/26.
////
//
//
//import Foundation
//import SwiftUI
//
///// Represents a section within a video's strategic outline.
///// Each section captures both Byron's raw analysis and AI's normalized interpretation.
//struct OutlineSection: Identifiable, Codable, Equatable {
//    // MARK: - Core Identity
//    
//    let id: UUID
//    var startSentenceId: UUID
//    var endSentenceId: UUID?
//    var patternIds: [UUID]
//    
//    // MARK: - Byron's Input
//    
//    var userTitle: String
//    var userNotes: String?
//    var userBelief: String?
//    
//
//    
//    // MARK: - AI's Analysis
//    
//    var aiTitle: String?
//    var aiSummary: String?
//    var aiStrategicPurpose: String?
//    var aiMechanism: String?
//    var aiInputsRecipe: String?
//    var aiBSFlags: String?
//    var aiArchetype: String?
//    
//    // MARK: - Initialization
//    
//    init(
//        id: UUID = UUID(),
//        startSentenceId: UUID,
//        endSentenceId: UUID? = nil,
//        patternIds: [UUID] = [],
//        userTitle: String,
//        userNotes: String? = nil,
//        userBelief: String? = nil,
//        aiTitle: String? = nil,
//        aiSummary: String? = nil,
//        aiStrategicPurpose: String? = nil,
//        aiMechanism: String? = nil,
//        aiInputsRecipe: String? = nil,
//        aiBSFlags: String? = nil,
//        aiArchetype: String? = nil
//    ) {
//        self.id = id
//        self.startSentenceId = startSentenceId
//        self.endSentenceId = endSentenceId
//        self.patternIds = patternIds
//        self.userTitle = userTitle
//        self.userNotes = userNotes
//        self.userBelief = userBelief
//        self.aiTitle = aiTitle
//        self.aiSummary = aiSummary
//        self.aiStrategicPurpose = aiStrategicPurpose
//        self.aiMechanism = aiMechanism
//        self.aiInputsRecipe = aiInputsRecipe
//        self.aiBSFlags = aiBSFlags
//        self.aiArchetype = aiArchetype
//    }
//    
//    // MARK: - Computed Properties
//    
//    var displayName: String {
//        aiTitle ?? userTitle
//    }
//    
//    var hasAIAnalysis: Bool {
//        aiTitle != nil || aiSummary != nil || aiStrategicPurpose != nil ||
//        aiMechanism != nil || aiInputsRecipe != nil || aiBSFlags != nil || aiArchetype != nil
//    }
//}
//
//// MARK: - Field Documentation
//
//extension OutlineSection {
//    enum FieldType: String, CaseIterable {
//        case userTitle
//        case userNotes
//        case userBelief
//        case aiTitle
//        case aiSummary
//        case aiStrategicPurpose
//        case aiMechanism
//        case aiInputsRecipe
//        case aiBSFlags
//        case aiArchetype
//        
//        var displayName: String {
//            switch self {
//            case .userTitle: return "Section Title"
//            case .userNotes: return "Your Notes"
//            case .userBelief: return "Belief Installed"
//            case .aiTitle: return "AI Title"
//            case .aiSummary: return "AI Summary"
//            case .aiStrategicPurpose: return "Strategic Purpose"
//            case .aiMechanism: return "Mechanism"
//            case .aiInputsRecipe: return "Inputs Recipe"
//            case .aiBSFlags: return "BS Flags"
//            case .aiArchetype: return "Archetype"
//            }
//        }
//        
//        var icon: String {
//            switch self {
//            case .userTitle: return "text.badge.plus"
//            case .userNotes: return "note.text"
//            case .userBelief: return "lightbulb"
//            case .aiTitle: return "wand.and.stars"
//            case .aiSummary: return "doc.plaintext"
//            case .aiStrategicPurpose: return "target"
//            case .aiMechanism: return "gearshape.2"
//            case .aiInputsRecipe: return "list.bullet.clipboard"
//            case .aiBSFlags: return "flag"
//            case .aiArchetype: return "tag"
//            }
//        }
//        
//        var color: Color {
//            switch self {
//            case .userTitle: return .blue
//            case .userNotes: return .green
//            case .userBelief: return .orange
//            case .aiTitle: return .purple
//            case .aiSummary: return .cyan
//            case .aiStrategicPurpose: return .indigo
//            case .aiMechanism: return .pink
//            case .aiInputsRecipe: return .mint
//            case .aiBSFlags: return .red
//            case .aiArchetype: return .teal
//            }
//        }
//        
//        var purpose: String {
//            switch self {
//            case .userTitle:
//                return "Your navigational label written in the moment. Speed + indexing, not taxonomy. Lets you scroll and instantly know 'oh yeah, that part.'"
//            case .userNotes:
//                return "Raw Byron brain dump including skepticism, BS accusations, what feels manipulative. Source of truth. Captures tone, suspicion, credibility tricks AI won't infer."
//            case .userBelief:
//                return "One-line section outcome: 'By the end of this section, viewer believes/feels ____'. Forces closure and composability. Makes section a usable Lego block."
//            case .aiTitle:
//                return "Polished, reusable name AI wouldn't naturally write in the moment. Normalize literal titles into playbook-friendly labels that repeat across videos."
//            case .aiSummary:
//                return "Clean 1-3 sentence compression of literal events/content. NO purpose, NO judgment. Fast skim line when returning weeks later. Makes comparing outlines feasible."
//            case .aiStrategicPurpose:
//                return "AI's normalized phrasing of section's function/belief installed. Consistency across outlines for pattern recognition and clustering. Must preserve intent including skepticism."
//            case .aiMechanism:
//                return "The HOW - credibility/manipulation mechanics used to install the belief. Captures the layer you won't reliably label mid-watch. Turns outline into playbook."
//            case .aiInputsRecipe:
//                return "Categorical shopping list of ingredients required to write this section type. Converts 'I want this archetype' into 'here's what I need to gather.' 3-7 reusable categories only - NOT literal facts."
//            case .aiBSFlags:
//                return "Credibility audit: where section is unfalsifiable, inflated, cross-promotional, padded. Identify spots where belief is created with weak evidence. Not moralizing - analyzing."
//            case .aiArchetype:
//                return "Stable class label for clustering across videos. Once you have 20+ outlines, filter all sections of same type and study patterns. Consistent and searchable."
//            }
//        }
//        
//        var examples: [String] {
//            switch self {
//            case .userTitle:
//                return [
//                    "Historical Ramble",
//                    "Intro - Mystery Building",
//                    "Map Authority Section"
//                ]
//            case .userNotes:
//                return [
//                    "Long ramble about food plots. Has nothing to do with tracking buck. BS credibility padding.",
//                    "Shows comprehensive map. Makes it look like he tracked this deer 100 times. Probably saw it once.",
//                    "Creates mystique around deer and property. Not about hunting yet. Just building intrigue."
//                ]
//            case .userBelief:
//                return [
//                    "Viewer trusts he knows this land deeply",
//                    "Viewer believes this deer is uniquely intelligent",
//                    "Viewer thinks his research is comprehensive"
//                ]
//            case .aiTitle:
//                return [
//                    "Single-Day Anchor Story",
//                    "Map Authority Flex",
//                    "Historical Ramble (Credibility Padding)",
//                    "Mystery Preservation Exit"
//                ]
//            case .aiSummary:
//                return [
//                    "Long ramble about last year's food, drought, planting methods. Not tied to the buck.",
//                    "Shows detailed map with tracking data spanning months. Breaks down one specific day's movements.",
//                    "Sets up mystery about deer's intelligence and unpredictability. Poses questions without definitive answers."
//                ]
//            case .aiStrategicPurpose:
//                return [
//                    "Establish perceived expertise through irrelevant familiarity signals",
//                    "Inflate comprehensiveness of research through visual authority",
//                    "Preserve viewer engagement by maintaining mystery rather than providing closure"
//                ]
//            case .aiMechanism:
//                return [
//                    "Effort-based trust + scope inflation through irrelevant familiarity",
//                    "Visual authority + data density without denominators",
//                    "Speculation shield + pattern imply + absence→intelligence conversion",
//                    "Engage-trap + mystery preservation + non-falsifiable framing"
//                ]
//            case .aiInputsRecipe:
//                return [
//                    "Historical context + constraint details + effort signals + method details",
//                    "Visual proof artifact + timeline anchor + repeated sighting language + scale claims",
//                    "Mystery framing + intelligence attribution + unanswered questions + cross-promotional hooks",
//                    "Wind details + location specifics + timeline + outcome ambiguity"
//                ]
//            case .aiBSFlags:
//                return [
//                    "Non-falsifiable claims. No denominator. Scope without sample size.",
//                    "Largely irrelevant to hunt. Functions as credibility padding.",
//                    "Visual implies comprehensive tracking but likely one observation inflated.",
//                    "Intelligence attribution without evidence. Mystery used to avoid falsifiable claims."
//                ]
//            case .aiArchetype:
//                return [
//                    "Credibility Ramble",
//                    "Authority Inflate",
//                    "Single-Day Proof Anchor",
//                    "Mystery Preservation Exit",
//                    "Pressure → Intelligence Conversion"
//                ]
//            }
//        }
//        
//        var goodExample: String {
//            examples.first ?? ""
//        }
//        
//        var badExample: String? {
//            switch self {
//            case .aiSummary:
//                return "This section builds credibility through historical context. [NO - that's purpose, not what happens]"
//            case .aiInputsRecipe:
//                return "drought, food plots, drill vs broadcast [NO - literal facts, not categories]"
//            default:
//                return nil
//            }
//        }
//        
//        var constraints: [String] {
//            switch self {
//            case .userTitle:
//                return ["Your words only", "Speed over perfection", "For navigation, not taxonomy"]
//            case .userNotes:
//                return ["Include skepticism", "Call out BS", "Capture tone and suspicion", "Source of truth for AI"]
//            case .userBelief:
//                return ["One line only", "Complete the sentence: 'Viewer now believes/feels...'", "Forces composability"]
//            case .aiTitle:
//                return ["Reusable across videos", "Playbook-friendly naming", "Not overly literal"]
//            case .aiSummary:
//                return ["1-3 sentences max", "Literal content ONLY", "NO purpose statements", "NO judgments"]
//            case .aiStrategicPurpose:
//                return ["Preserve Byron's skepticism", "Normalized phrasing", "Not polite - accurate", "For clustering"]
//            case .aiMechanism:
//                return ["Name specific techniques", "Focus on manipulation mechanics", "How belief is installed"]
//            case .aiInputsRecipe:
//                return ["3-7 categorical bullets", "Reusable categories ONLY", "NO literal facts", "Shopping list format"]
//            case .aiBSFlags:
//                return ["Identify credibility inflation", "Not moralizing - analyzing", "Spot unfalsifiable claims", "Note scope without proof"]
//            case .aiArchetype:
//                return ["Stable across videos", "Searchable class label", "Different from aiTitle", "For filtering/clustering"]
//            }
//        }
//        
//        var usageScenario: String {
//            switch self {
//            case .userTitle:
//                return "When scrolling through sections, you see 'Historical Ramble' and immediately remember which part that was."
//            case .userNotes:
//                return "Reading your notes, AI can tell you were suspicious of credibility claims and marked it as potential BS."
//            case .userBelief:
//                return "When building your script, you pick 'Viewer trusts expertise' as a needed outcome and slot in sections that achieve it."
//            case .aiTitle:
//                return "You search your library for 'Authority Flex' and find 5 videos using that section type."
//            case .aiSummary:
//                return "Weeks later, you skim the summary instead of rereading messy notes or full transcript."
//            case .aiStrategicPurpose:
//                return "AI clusters 10 outlines and finds 7 sections all 'Establish expertise through familiarity' with different mechanics."
//            case .aiMechanism:
//                return "When writing your version, you tell AI: 'Use effort-trust + spec-shield, avoid denominators.'"
//            case .aiInputsRecipe:
//                return "You want a 'Credibility Ramble' section, recipe tells you to gather: historical context about YOUR land + constraint details about YOUR gear."
//            case .aiBSFlags:
//                return "You compare 10 videos and see BS is placed early (credibility building) and late (mystery exits)."
//            case .aiArchetype:
//                return "Filter shows all 'Credibility Ramble' sections across 20 videos, revealing common length and placement patterns."
//            }
//        }
//        
//        var isUserField: Bool {
//            switch self {
//            case .userTitle, .userNotes, .userBelief:
//                return true
//            default:
//                return false
//            }
//        }
//        
//        var isAIField: Bool {
//            !isUserField
//        }
//    }
//    
//    // Access field value by type
//    func value(for fieldType: FieldType) -> String? {
//        switch fieldType {
//        case .userTitle: return userTitle
//        case .userNotes: return userNotes
//        case .userBelief: return userBelief
//        case .aiTitle: return aiTitle
//        case .aiSummary: return aiSummary
//        case .aiStrategicPurpose: return aiStrategicPurpose
//        case .aiMechanism: return aiMechanism
//        case .aiInputsRecipe: return aiInputsRecipe
//        case .aiBSFlags: return aiBSFlags
//        case .aiArchetype: return aiArchetype
//        }
//    }
//    
//    // Get all user fields with values
//    var populatedUserFields: [(FieldType, String)] {
//        FieldType.allCases.filter { $0.isUserField }.compactMap { fieldType in
//            guard let value = value(for: fieldType), !value.isEmpty else { return nil }
//            return (fieldType, value)
//        }
//    }
//    
//    // Get all AI fields with values
//    var populatedAIFields: [(FieldType, String)] {
//        FieldType.allCases.filter { $0.isAIField }.compactMap { fieldType in
//            guard let value = value(for: fieldType), !value.isEmpty else { return nil }
//            return (fieldType, value)
//        }
//    }
//}
//
//// MARK: - AI Prompt Constraints
//
//extension OutlineSection {
//    static let aiPromptConstraints = """
//    FIELD SCOPE RULES FOR AI ANALYSIS:
//    
//    \(FieldType.aiTitle.displayName):
//    Purpose: \(FieldType.aiTitle.purpose)
//    Example: \(FieldType.aiTitle.goodExample)
//    Constraints: \(FieldType.aiTitle.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiSummary.displayName):
//    Purpose: \(FieldType.aiSummary.purpose)
//    Example: \(FieldType.aiSummary.goodExample)
//    BAD Example: \(FieldType.aiSummary.badExample ?? "")
//    Constraints: \(FieldType.aiSummary.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiStrategicPurpose.displayName):
//    Purpose: \(FieldType.aiStrategicPurpose.purpose)
//    Example: \(FieldType.aiStrategicPurpose.goodExample)
//    Constraints: \(FieldType.aiStrategicPurpose.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiMechanism.displayName):
//    Purpose: \(FieldType.aiMechanism.purpose)
//    Example: \(FieldType.aiMechanism.goodExample)
//    Constraints: \(FieldType.aiMechanism.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiInputsRecipe.displayName):
//    Purpose: \(FieldType.aiInputsRecipe.purpose)
//    Example: \(FieldType.aiInputsRecipe.goodExample)
//    BAD Example: \(FieldType.aiInputsRecipe.badExample ?? "")
//    Constraints: \(FieldType.aiInputsRecipe.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiBSFlags.displayName):
//    Purpose: \(FieldType.aiBSFlags.purpose)
//    Example: \(FieldType.aiBSFlags.goodExample)
//    Constraints: \(FieldType.aiBSFlags.constraints.joined(separator: " • "))
//    
//    \(FieldType.aiArchetype.displayName):
//    Purpose: \(FieldType.aiArchetype.purpose)
//    Example: \(FieldType.aiArchetype.goodExample)
//    Constraints: \(FieldType.aiArchetype.constraints.joined(separator: " • "))
//    """
//}
import Foundation
import SwiftUI

/// Represents a section within a video's strategic outline.
/// Each section captures both Byron's raw analysis and AI's normalized interpretation.
struct OutlineSection: Identifiable, Codable, Equatable {
    // MARK: - Core Identity
    
    let id: UUID
    var startSentenceId: UUID
    var endSentenceId: UUID?
    var patternIds: [UUID]
    
    // MARK: - Byron's Input (ORIGINAL field names)
    
    var name: String                // Section title
    var rawNotes: String?           // Your brain dump
    var beliefInstalled: String?    // Belief outcome
    
    // MARK: - AI's Analysis
    
    var aiTitle: String?
    var aiSummary: String?
    var aiStrategicPurpose: String?
    var aiMechanism: String?
    var aiInputsRecipe: String?
    var aiBSFlags: String?
    var aiArchetype: String?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        startSentenceId: UUID,
        endSentenceId: UUID? = nil,
        patternIds: [UUID] = [],
        name: String,
        rawNotes: String? = nil,
        beliefInstalled: String? = nil,
        aiTitle: String? = nil,
        aiSummary: String? = nil,
        aiStrategicPurpose: String? = nil,
        aiMechanism: String? = nil,
        aiInputsRecipe: String? = nil,
        aiBSFlags: String? = nil,
        aiArchetype: String? = nil
    ) {
        self.id = id
        self.startSentenceId = startSentenceId
        self.endSentenceId = endSentenceId
        self.patternIds = patternIds
        self.name = name
        self.rawNotes = rawNotes
        self.beliefInstalled = beliefInstalled
        self.aiTitle = aiTitle
        self.aiSummary = aiSummary
        self.aiStrategicPurpose = aiStrategicPurpose
        self.aiMechanism = aiMechanism
        self.aiInputsRecipe = aiInputsRecipe
        self.aiBSFlags = aiBSFlags
        self.aiArchetype = aiArchetype
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        aiTitle ?? name
    }
    
    var hasAIAnalysis: Bool {
        aiTitle != nil || aiSummary != nil || aiStrategicPurpose != nil ||
        aiMechanism != nil || aiInputsRecipe != nil || aiBSFlags != nil || aiArchetype != nil
    }
}

// MARK: - Field Documentation

extension OutlineSection {
    enum FieldType: String, CaseIterable {
        case name
        case rawNotes
        case beliefInstalled
        case aiTitle
        case aiSummary
        case aiStrategicPurpose
        case aiMechanism
        case aiInputsRecipe
        case aiBSFlags
        case aiArchetype
        
        var displayName: String {
            switch self {
            case .name: return "Section Title"
            case .rawNotes: return "Your Notes"
            case .beliefInstalled: return "Belief Installed"
            case .aiTitle: return "AI Title"
            case .aiSummary: return "AI Summary"
            case .aiStrategicPurpose: return "Strategic Purpose"
            case .aiMechanism: return "Mechanism"
            case .aiInputsRecipe: return "Inputs Recipe"
            case .aiBSFlags: return "BS Flags"
            case .aiArchetype: return "Archetype"
            }
        }
        
        var icon: String {
            switch self {
            case .name: return "text.badge.plus"
            case .rawNotes: return "note.text"
            case .beliefInstalled: return "lightbulb"
            case .aiTitle: return "wand.and.stars"
            case .aiSummary: return "doc.plaintext"
            case .aiStrategicPurpose: return "target"
            case .aiMechanism: return "gearshape.2"
            case .aiInputsRecipe: return "list.bullet.clipboard"
            case .aiBSFlags: return "flag"
            case .aiArchetype: return "tag"
            }
        }
        
        var color: Color {
            switch self {
            case .name: return .blue
            case .rawNotes: return .green
            case .beliefInstalled: return .orange
            case .aiTitle: return .purple
            case .aiSummary: return .cyan
            case .aiStrategicPurpose: return .indigo
            case .aiMechanism: return .pink
            case .aiInputsRecipe: return .mint
            case .aiBSFlags: return .red
            case .aiArchetype: return .teal
            }
        }
        
        var purpose: String {
            switch self {
            case .name:
                return "Your navigational label written in the moment. Speed + indexing, not taxonomy. Lets you scroll and instantly know 'oh yeah, that part.'"
            case .rawNotes:
                return "Raw Byron brain dump including skepticism, BS accusations, what feels manipulative. Source of truth. Captures tone, suspicion, credibility tricks AI won't infer."
            case .beliefInstalled:
                return "One-line section outcome: 'By the end of this section, viewer believes/feels ____'. Forces closure and composability. Makes section a usable Lego block."
            case .aiTitle:
                return "Polished, reusable name AI wouldn't naturally write in the moment. Normalize literal titles into playbook-friendly labels that repeat across videos."
            case .aiSummary:
                return "Clean 1-3 sentence compression of literal events/content. NO purpose, NO judgment. Fast skim line when returning weeks later. Makes comparing outlines feasible."
            case .aiStrategicPurpose:
                return "AI's normalized phrasing of section's function/belief installed. Consistency across outlines for pattern recognition and clustering. Must preserve intent including skepticism."
            case .aiMechanism:
                return "The HOW - credibility/manipulation mechanics used to install the belief. Captures the layer you won't reliably label mid-watch. Turns outline into playbook."
            case .aiInputsRecipe:
                return "Categorical shopping list of ingredients required to write this section type. Converts 'I want this archetype' into 'here's what I need to gather.' 3-7 reusable categories only - NOT literal facts."
            case .aiBSFlags:
                return "Credibility audit: where section is unfalsifiable, inflated, cross-promotional, padded. Identify spots where belief is created with weak evidence. Not moralizing - analyzing."
            case .aiArchetype:
                return "Stable class label for clustering across videos. Once you have 20+ outlines, filter all sections of same type and study patterns. Consistent and searchable."
            }
        }
        
        var examples: [String] {
            switch self {
            case .name:
                return [
                    "Historical Ramble",
                    "Intro - Mystery Building",
                    "Map Authority Section"
                ]
            case .rawNotes:
                return [
                    "Long ramble about food plots. Has nothing to do with tracking buck. BS credibility padding.",
                    "Shows comprehensive map. Makes it look like he tracked this deer 100 times. Probably saw it once.",
                    "Creates mystique around deer and property. Not about hunting yet. Just building intrigue."
                ]
            case .beliefInstalled:
                return [
                    "Viewer trusts he knows this land deeply",
                    "Viewer believes this deer is uniquely intelligent",
                    "Viewer thinks his research is comprehensive"
                ]
            case .aiTitle:
                return [
                    "Single-Day Anchor Story",
                    "Map Authority Flex",
                    "Historical Ramble (Credibility Padding)",
                    "Mystery Preservation Exit"
                ]
            case .aiSummary:
                return [
                    "Long ramble about last year's food, drought, planting methods. Not tied to the buck.",
                    "Shows detailed map with tracking data spanning months. Breaks down one specific day's movements.",
                    "Sets up mystery about deer's intelligence and unpredictability. Poses questions without definitive answers."
                ]
            case .aiStrategicPurpose:
                return [
                    "Establish perceived expertise through irrelevant familiarity signals",
                    "Inflate comprehensiveness of research through visual authority",
                    "Preserve viewer engagement by maintaining mystery rather than providing closure"
                ]
            case .aiMechanism:
                return [
                    "Effort-based trust + scope inflation through irrelevant familiarity",
                    "Visual authority + data density without denominators",
                    "Speculation shield + pattern imply + absence→intelligence conversion",
                    "Engage-trap + mystery preservation + non-falsifiable framing"
                ]
            case .aiInputsRecipe:
                return [
                    "Historical context + constraint details + effort signals + method details",
                    "Visual proof artifact + timeline anchor + repeated sighting language + scale claims",
                    "Mystery framing + intelligence attribution + unanswered questions + cross-promotional hooks",
                    "Wind details + location specifics + timeline + outcome ambiguity"
                ]
            case .aiBSFlags:
                return [
                    "Non-falsifiable claims. No denominator. Scope without sample size.",
                    "Largely irrelevant to hunt. Functions as credibility padding.",
                    "Visual implies comprehensive tracking but likely one observation inflated.",
                    "Intelligence attribution without evidence. Mystery used to avoid falsifiable claims."
                ]
            case .aiArchetype:
                return [
                    "Credibility Ramble",
                    "Authority Inflate",
                    "Single-Day Proof Anchor",
                    "Mystery Preservation Exit",
                    "Pressure → Intelligence Conversion"
                ]
            }
        }
        
        var goodExample: String {
            examples.first ?? ""
        }
        
        var badExample: String? {
            switch self {
            case .aiSummary:
                return "This section builds credibility through historical context. [NO - that's purpose, not what happens]"
            case .aiInputsRecipe:
                return "drought, food plots, drill vs broadcast [NO - literal facts, not categories]"
            default:
                return nil
            }
        }
        
        var constraints: [String] {
            switch self {
            case .name:
                return ["Your words only", "Speed over perfection", "For navigation, not taxonomy"]
            case .rawNotes:
                return ["Include skepticism", "Call out BS", "Capture tone and suspicion", "Source of truth for AI"]
            case .beliefInstalled:
                return ["One line only", "Complete the sentence: 'Viewer now believes/feels...'", "Forces composability"]
            case .aiTitle:
                return ["Reusable across videos", "Playbook-friendly naming", "Not overly literal"]
            case .aiSummary:
                return ["1-3 sentences max", "Literal content ONLY", "NO purpose statements", "NO judgments"]
            case .aiStrategicPurpose:
                return ["Preserve Byron's skepticism", "Normalized phrasing", "Not polite - accurate", "For clustering"]
            case .aiMechanism:
                return ["Name specific techniques", "Focus on manipulation mechanics", "How belief is installed"]
            case .aiInputsRecipe:
                return ["3-7 categorical bullets", "Reusable categories ONLY", "NO literal facts", "Shopping list format"]
            case .aiBSFlags:
                return ["Identify credibility inflation", "Not moralizing - analyzing", "Spot unfalsifiable claims", "Note scope without proof"]
            case .aiArchetype:
                return ["Stable across videos", "Searchable class label", "Different from aiTitle", "For filtering/clustering"]
            }
        }
        
        var usageScenario: String {
            switch self {
            case .name:
                return "When scrolling through sections, you see 'Historical Ramble' and immediately remember which part that was."
            case .rawNotes:
                return "Reading your notes, AI can tell you were suspicious of credibility claims and marked it as potential BS."
            case .beliefInstalled:
                return "When building your script, you pick 'Viewer trusts expertise' as a needed outcome and slot in sections that achieve it."
            case .aiTitle:
                return "You search your library for 'Authority Flex' and find 5 videos using that section type."
            case .aiSummary:
                return "Weeks later, you skim the summary instead of rereading messy notes or full transcript."
            case .aiStrategicPurpose:
                return "AI clusters 10 outlines and finds 7 sections all 'Establish expertise through familiarity' with different mechanics."
            case .aiMechanism:
                return "When writing your version, you tell AI: 'Use effort-trust + spec-shield, avoid denominators.'"
            case .aiInputsRecipe:
                return "You want a 'Credibility Ramble' section, recipe tells you to gather: historical context about YOUR land + constraint details about YOUR gear."
            case .aiBSFlags:
                return "You compare 10 videos and see BS is placed early (credibility building) and late (mystery exits)."
            case .aiArchetype:
                return "Filter shows all 'Credibility Ramble' sections across 20 videos, revealing common length and placement patterns."
            }
        }
        
        var isUserField: Bool {
            switch self {
            case .name, .rawNotes, .beliefInstalled:
                return true
            default:
                return false
            }
        }
        
        var isAIField: Bool {
            !isUserField
        }
    }
    
    // Access field value by type
    func value(for fieldType: FieldType) -> String? {
        switch fieldType {
        case .name: return name
        case .rawNotes: return rawNotes
        case .beliefInstalled: return beliefInstalled
        case .aiTitle: return aiTitle
        case .aiSummary: return aiSummary
        case .aiStrategicPurpose: return aiStrategicPurpose
        case .aiMechanism: return aiMechanism
        case .aiInputsRecipe: return aiInputsRecipe
        case .aiBSFlags: return aiBSFlags
        case .aiArchetype: return aiArchetype
        }
    }
    
    // Get all user fields with values
    var populatedUserFields: [(FieldType, String)] {
        FieldType.allCases.filter { $0.isUserField }.compactMap { fieldType in
            guard let value = value(for: fieldType), !value.isEmpty else { return nil }
            return (fieldType, value)
        }
    }
    
    // Get all AI fields with values
    var populatedAIFields: [(FieldType, String)] {
        FieldType.allCases.filter { $0.isAIField }.compactMap { fieldType in
            guard let value = value(for: fieldType), !value.isEmpty else { return nil }
            return (fieldType, value)
        }
    }
}

// MARK: - AI Prompt Constraints

extension OutlineSection {
    static let aiPromptConstraints = """
    FIELD SCOPE RULES FOR AI ANALYSIS:
    
    \(FieldType.aiTitle.displayName):
    Purpose: \(FieldType.aiTitle.purpose)
    Example: \(FieldType.aiTitle.goodExample)
    Constraints: \(FieldType.aiTitle.constraints.joined(separator: " • "))
    
    \(FieldType.aiSummary.displayName):
    Purpose: \(FieldType.aiSummary.purpose)
    Example: \(FieldType.aiSummary.goodExample)
    BAD Example: \(FieldType.aiSummary.badExample ?? "")
    Constraints: \(FieldType.aiSummary.constraints.joined(separator: " • "))
    
    \(FieldType.aiStrategicPurpose.displayName):
    Purpose: \(FieldType.aiStrategicPurpose.purpose)
    Example: \(FieldType.aiStrategicPurpose.goodExample)
    Constraints: \(FieldType.aiStrategicPurpose.constraints.joined(separator: " • "))
    
    \(FieldType.aiMechanism.displayName):
    Purpose: \(FieldType.aiMechanism.purpose)
    Example: \(FieldType.aiMechanism.goodExample)
    Constraints: \(FieldType.aiMechanism.constraints.joined(separator: " • "))
    
    \(FieldType.aiInputsRecipe.displayName):
    Purpose: \(FieldType.aiInputsRecipe.purpose)
    Example: \(FieldType.aiInputsRecipe.goodExample)
    BAD Example: \(FieldType.aiInputsRecipe.badExample ?? "")
    Constraints: \(FieldType.aiInputsRecipe.constraints.joined(separator: " • "))
    
    \(FieldType.aiBSFlags.displayName):
    Purpose: \(FieldType.aiBSFlags.purpose)
    Example: \(FieldType.aiBSFlags.goodExample)
    Constraints: \(FieldType.aiBSFlags.constraints.joined(separator: " • "))
    
    \(FieldType.aiArchetype.displayName):
    Purpose: \(FieldType.aiArchetype.purpose)
    Example: \(FieldType.aiArchetype.goodExample)
    Constraints: \(FieldType.aiArchetype.constraints.joined(separator: " • "))
    """
}
