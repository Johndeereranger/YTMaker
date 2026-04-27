import Foundation
import SwiftUI

// MARK: - Core Data Structures

/// One complete experiment — a unique prompt configuration with all its sister runs
struct PromptExperiment: Identifiable, Codable {
    let id: UUID
    let videoId: String
    let createdAt: Date

    // Config (defines uniqueness of this experiment)
    let windowSize: Int
    let stepSize: Int
    let temperature: Double
    let promptVariantId: String
    let promptVariantName: String
    let promptText: String              // Full system prompt stored for forensic debugging
    let sisterRunCount: Int             // How many sister runs were requested

    // Labeling
    var autoLabel: String               // "W5-S2-T0.3 · 3 sisters"
    var manualLabel: String?            // User-provided, optional

    // Results
    var sisterRuns: [ExperimentSisterRun]
    var isComplete: Bool

    var displayLabel: String { manualLabel ?? autoLabel }

    var configSummary: String {
        "W:\(windowSize) S:\(stepSize) T:\(String(format: "%.1f", temperature))"
    }

    static func makeAutoLabel(windowSize: Int, stepSize: Int, temperature: Double, sisterCount: Int, variantName: String) -> String {
        let tempStr = String(format: "%.1f", temperature)
        return "W\(windowSize)-S\(stepSize)-T\(tempStr) · \(sisterCount) sister\(sisterCount == 1 ? "" : "s") · \(variantName)"
    }
}

// MARK: - Sister Run

/// One execution of a config (sister = same config, different run for fidelity testing)
struct ExperimentSisterRun: Identifiable, Codable {
    let id: UUID
    let runNumber: Int                  // 1, 2, 3...
    let timestamp: Date

    // Two variants always produced together
    var withDigressions: ExperimentVariant       // Full transcript
    var withoutDigressions: ExperimentVariant?   // Clean transcript (nil if no digressions found)

    let digressionExcludeIndices: Set<Int>?      // Which sentence indices were excluded
    let totalSentences: Int                      // Full transcript sentence count
    let cleanSentenceCount: Int?                 // After digression removal
}

// MARK: - Variant

/// One variant — with or without digressions
struct ExperimentVariant: Identifiable, Codable {
    let id: UUID
    let variantType: VariantType

    // Reuse existing SectionSplitterRunResult directly
    let splitterResult: SectionSplitterRunResult

    // Gap indices (0-indexed, for alignment matrix)
    // Derived from splitterResult.boundaries and .pass1Boundaries
    // For without-digressions variant, these are REMAPPED to full transcript indices
    let pass1GapIndices: Set<Int>
    let finalGapIndices: Set<Int>

    // Raw output per window (extracted from splitterResult for easy access)
    let rawWindowOutputs: [WindowRawOutput]

    // Metadata
    let runDuration: TimeInterval
    let windowCount: Int

    // Index mapping (for without-digressions variant only)
    let cleanToFullIndexMap: [Int: Int]?
}

// MARK: - Supporting Types

enum VariantType: String, Codable, Hashable {
    case withDigressions
    case withoutDigressions

    var shortLabel: String {
        switch self {
        case .withDigressions: return "+Dig"
        case .withoutDigressions: return "-Dig"
        }
    }

    var icon: String {
        switch self {
        case .withDigressions: return "text.justify"
        case .withoutDigressions: return "line.3.horizontal.decrease"
        }
    }
}

enum PassType: String, Codable, Hashable {
    case pass1
    case final

    var shortLabel: String {
        switch self {
        case .pass1: return "P1"
        case .final: return "F"
        }
    }
}

/// Raw LLM output per window (extracted for easy debug copy)
struct WindowRawOutput: Identifiable, Codable {
    var id: Int { windowIndex }
    let windowIndex: Int
    let startSentence: Int
    let endSentence: Int
    let pass1Raw: String
    let pass2Raw: String?               // nil if window wasn't refined in pass 2
}

// MARK: - Selectable Run (for comparison picker)

/// Lightweight reference to a specific run variant+pass for the comparison matrix
struct SelectableRun: Identifiable, Hashable {
    let id: String                      // Unique composite key
    let experimentId: UUID
    let experimentLabel: String
    let experimentIndex: Int            // 1-based index in the experiment list
    let sisterRunNumber: Int
    let variantType: VariantType
    let passType: PassType
    let gapIndices: Set<Int>

    var label: String {
        "E\(experimentIndex) S\(sisterRunNumber) \(variantType.shortLabel) \(passType.shortLabel)"
    }

    var shortLabel: String {
        "E\(experimentIndex)-S\(sisterRunNumber)-\(variantType == .withDigressions ? "D" : "C")-\(passType.shortLabel)"
    }

    var color: Color {
        switch (variantType, passType) {
        case (.withDigressions, .final): return .blue
        case (.withDigressions, .pass1): return .blue.opacity(0.5)
        case (.withoutDigressions, .final): return .orange
        case (.withoutDigressions, .pass1): return .orange.opacity(0.5)
        }
    }

    static func makeId(experimentId: UUID, sisterRun: Int, variant: VariantType, pass: PassType) -> String {
        "\(experimentId.uuidString)-S\(sisterRun)-\(variant.rawValue)-\(pass.rawValue)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SelectableRun, rhs: SelectableRun) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Storage

struct ExperimentStorage {

    static func key(for videoId: String) -> String {
        "prompt_experiments_\(videoId)"
    }

    static func save(_ experiments: [PromptExperiment], videoId: String) {
        do {
            let data = try JSONEncoder().encode(experiments)
            UserDefaults.standard.set(data, forKey: key(for: videoId))
        } catch {
            print("[ExperimentStorage] Save failed: \(error)")
        }
    }

    static func load(videoId: String) -> [PromptExperiment] {
        guard let data = UserDefaults.standard.data(forKey: key(for: videoId)) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PromptExperiment].self, from: data)
        } catch {
            print("[ExperimentStorage] Load failed: \(error)")
            return []
        }
    }

    static func deleteExperiment(id: UUID, videoId: String) {
        var experiments = load(videoId: videoId)
        experiments.removeAll { $0.id == id }
        save(experiments, videoId: videoId)
    }
}

// MARK: - Helper: Clean-to-Full Index Mapping

/// Builds a mapping from clean transcript indices to full transcript indices
/// so that boundary positions from the without-digressions run can be displayed
/// on the same alignment matrix as the full-transcript run.
func buildCleanToFullMap(totalSentences: Int, excludeIndices: Set<Int>) -> [Int: Int] {
    var map: [Int: Int] = [:]
    var cleanIndex = 0
    for fullIndex in 0..<totalSentences {
        if !excludeIndices.contains(fullIndex) {
            map[cleanIndex] = fullIndex
            cleanIndex += 1
        }
    }
    return map
}

/// Remaps gap indices from clean-transcript space to full-transcript space
func remapGapIndices(_ gapIndices: Set<Int>, using cleanToFullMap: [Int: Int]) -> Set<Int> {
    Set(gapIndices.compactMap { cleanToFullMap[$0] })
}
