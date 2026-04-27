//
//  DataSourceManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/14/25.
//

import Foundation

struct DataSource: Identifiable, Codable, Equatable {
    var id: String         // Always a unique lookup key
    var name: String       // Human-readable label
    var description: String?
}

class DataSourceManager {
    static let instance = DataSourceManager()
    private init() {}

    // 🔹 1. All available sources
      private let allSources: [DataSource] = [
          DataSource(id: "allImagePrompts", name: "All Image Prompts"),
          DataSource(id: "allDetailedImagePrompts", name: "All Detailed Image Prompts"),
          DataSource(id: "newImagePrompts", name: "New Image Prompts Only"),
          DataSource(id: "reusedImagePrompts", name: "Reused Prompts")
      ]

      // 🔹 2. StepID → DataSourceID bindings
      private let dataBindings: [UUID: String] = [
          UUID(uuidString: "81FBCC69-ED61-45A9-AC3E-67746E706038")!: "allDetailedImagePrompts",
          UUID(uuidString: "A1B2C3D4-2222-2222-2222-222222222222")!: "newImagePrompts",
          UUID(uuidString: "8E8851EA-BC05-49BB-838B-C98C5C999ED4")!: "allDetailedImagePrompts"
         
      ]
    func hasDataSources(for stepId: UUID) -> Bool {
          // Check if this step has a data binding
          guard let dataSourceID = dataBindings[stepId] else {
              return false
          }
          
          // Check if the data source actually exists
          return allSources.contains { $0.id == dataSourceID }
      }

      // 🔹 3. Called from runSmartPromptStep
      func resolveData(forStepID stepId: UUID) async -> String? {
          guard let dataSourceID = dataBindings[stepId] else { return nil }
          guard let source = allSources.first(where: { $0.id == dataSourceID }) else { return nil }
          return await resolveDataSource(for: source)
      }

    // 🔹 Internal resolver for a source
    private func resolveDataSource(for source: DataSource) async -> String? {
        switch source.id {
        case "allImagePrompts":
            let prompts = try? await ImagePromptManager.instance.fetchAllPrompts()
            let orderedPrompts = prompts?.sorted { $0.shortID > $1.shortID }
            //return prompts?.compactMap { $0.prompt }.joined(separator: "\n")
            return orderedPrompts?.map { "\($0.shortID) - \($0.prompt)" }.joined(separator: "\n")
        case "allDetailedImagePrompts":
            let prompts = try? await ImagePromptManager.instance.fetchAllPrompts()
            let orderedPrompts = prompts?.sorted { $0.shortID > $1.shortID }
            //return prompts?.compactMap { $0.prompt }.joined(separator: "\n")
            return orderedPrompts?.map { "\($0.shortID) - \($0.detailedPrompt)" }.joined(separator: "\n")
        case "newImagePrompts":
            let prompts = try? await ImagePromptManager.instance.fetchAllPrompts()
            return prompts?.compactMap { $0.prompt }.joined(separator: "\n")

        case "reusedImagePrompts":
            let prompts = try? await ImagePromptManager.instance.fetchAllPrompts()
            return prompts?.compactMap { $0.prompt }.joined(separator: "\n")

        default:
            return nil
        }
    }
}
