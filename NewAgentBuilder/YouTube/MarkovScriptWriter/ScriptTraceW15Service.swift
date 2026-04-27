//
//  ScriptTraceW15Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - W1.5: Payload Decomposition Service

/// Decomposes gist frames into atomic content payloads.
/// Each payload maps to exactly one sentence in the output script.
class ScriptTraceW15Service {
    private let adapter = ClaudeModelAdapter(model: .claude35Sonnet)

    // MARK: - Decompose Gist

    /// Decompose a single gist frame into atomic content payloads.
    func decomposeGist(
        gistText: String,
        gistFrame: GistFrame,
        targetMove: String
    ) async -> [ContentPayload] {
        let systemPrompt = """
        You decompose gist frames into atomic content payloads.
        Each payload = ONE fact/claim/observation = one future sentence.

        Payload types:
        - quantitative_finding: numbers, data, measurements
        - geographic_specificity: place references, locations
        - contradiction: opposing claims, surprises
        - action_description: actions taken, events
        - status_claim: state of affairs, conditions
        - temporal_context: time references, sequences
        - causal_claim: because/therefore relationships
        - identity_statement: who/what something is

        Return ONLY valid JSON. No markdown.
        """

        let userPrompt = """
        Gist type: \(gistFrame.rawValue) | Target move: \(targetMove)
        Content: "\(gistText)"

        Decompose into atomic payloads. Each must fit one sentence.
        Return JSON array:
        [{"payload_idx": 0, "content_text": "...", "payload_type": "...", "target_slot_types": ["..."], "complexity": "single|compound"}]
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.2, "max_tokens": 2000]
        )

        return parsePayloads(response, gistFrameId: UUID())
    }

    // MARK: - Parse Response

    private func parsePayloads(_ response: String, gistFrameId: UUID) -> [ContentPayload] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Fallback: treat entire gist as a single payload
            return [ContentPayload(
                gistFrameId: gistFrameId,
                payloadIndex: 0,
                contentText: "Could not decompose",
                payloadType: .statusClaim,
                targetSlotTypes: [.other],
                complexity: .single
            )]
        }

        return jsonArray.enumerated().map { idx, dict in
            let contentText = dict["content_text"] as? String ?? ""
            let typeStr = dict["payload_type"] as? String ?? "status_claim"
            let payloadType = PayloadType(rawValue: typeStr) ?? .statusClaim
            let slotStrs = dict["target_slot_types"] as? [String] ?? ["other"]
            let slots = slotStrs.compactMap { SlotType(rawValue: $0) }
            let complexityStr = dict["complexity"] as? String ?? "single"
            let complexity: ContentPayload.PayloadComplexity = complexityStr == "compound" ? .compound : .single

            return ContentPayload(
                gistFrameId: gistFrameId,
                payloadIndex: idx,
                contentText: contentText,
                payloadType: payloadType,
                targetSlotTypes: slots.isEmpty ? [.other] : slots,
                complexity: complexity
            )
        }
    }
}
