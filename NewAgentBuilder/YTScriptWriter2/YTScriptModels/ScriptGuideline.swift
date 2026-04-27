//
//  ScriptGuideline.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//


import Foundation

struct ScriptGuideline: Identifiable, Codable {
    let id = UUID()
    let category: GuidelineCategory
    let title: String
    let summary: String
    let explanation: String
    let checkPrompt: String
    let fixPrompt: String
    let suggestionsPrompt: String
}

enum GuidelineCategory: String, CaseIterable, Codable {
    case all = "All Guidelines"  // ⭐ NEW - first in list
    case structure = "Structure & Flow"
    case hooks = "Hooks & Retention"
    case psychology = "Psychology Hacks"
    case voice = "Voice & Style"
    case pacing = "Pacing & Rhythm"
    case clarity = "Clarity & Comprehension"
    case derrick = "Derrick"
}
