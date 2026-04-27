//
//  AngleOption.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/8/25.
//

import SwiftUI
// Add this struct inside YTSCRIPT class
struct AngleOption: Codable, Hashable, Identifiable {
    let id: Int
    let angleStatement: String
    let nukePoint: String
    let hookType: String
    let whyItMatters: String
    let supportingPoints: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case angleStatement = "angle_statement"
        case nukePoint = "nuke_point"
        case hookType = "hook_type"
        case whyItMatters = "why_it_matters"
        case supportingPoints = "supporting_points"
    }
}
