//
//  AgentRegistry.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import Foundation
import Foundation

enum AgentRole: String, CaseIterable, Codable {
    case imagePrompt
    case scriptFormatter
    case codeExplainer
    case videoStoryboard
    case scriptDiagnostic
}

class AgentRegistry {
    static let shared = AgentRegistry()
    private init() {}

    // 🔹 Map each role to a known tuned Agent ID
    private let agentRoleMap: [AgentRole: UUID] = [
        .imagePrompt: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        .scriptFormatter: UUID(uuidString: "221932A0-4CFF-4E72-B1E9-A93FB5BBFC41")!,
        .codeExplainer: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-1234567890EF")!,
        .videoStoryboard: UUID(uuidString: "DEADBEEF-0000-1234-5678-CAFEBABE0000")!,
        .scriptDiagnostic: UUID(uuidString: "FEEDFACE-9876-4321-ABCD-000011112222")!
    ]

    // 🔹 Resolve and return the full Agent model from Firestore
    func resolve(for role: AgentRole) async throws -> Agent {
        guard let id = agentRoleMap[role] else {
            throw NSError(domain: "AgentRegistry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No agent mapped for role: \(role.rawValue)"
            ])
        }

        guard let agent = try await AgentManager.instance.fetchAgent(with: id) else {
            throw NSError(domain: "AgentRegistry", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Agent not found for ID: \(id)"
            ])
        }

        return agent
    }

    // 🔸 Optional: Debug helper
    func debugPrintAllRoles() async {
        for role in AgentRole.allCases {
            do {
                let agent = try await resolve(for: role)
                print("✅ \(role.rawValue): \(agent.name)")
            } catch {
                print("❌ \(role.rawValue): \(error.localizedDescription)")
            }
        }
    }
}
