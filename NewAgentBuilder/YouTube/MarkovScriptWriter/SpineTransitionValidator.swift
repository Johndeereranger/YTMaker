//
//  SpineTransitionValidator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Builds a transition probability matrix from the 19-label NarrativeSpine
//  function taxonomy and validates generated spines against it.
//  Cached to disk alongside the Creator Narrative Profile.
//

import Foundation

// MARK: - Spine Transition Matrix

struct SpineTransitionMatrix: Codable {
    /// transitions[fromFunction][toFunction] = count of observed transitions
    let transitions: [String: [String: Int]]

    /// Total outgoing transition count per function
    let totalOutgoing: [String: Int]

    /// How often each function appears globally
    let functionFrequency: [String: Int]

    /// Functions that commonly start a spine
    let startFunctions: [String: Int]

    /// Functions that commonly end a spine
    let endFunctions: [String: Int]

    /// Number of spines used to build this matrix
    let sourceSpineCount: Int

    /// Total number of beat-to-beat transitions observed
    let totalTransitionCount: Int

    let builtAt: Date

    // MARK: - Build from corpus

    static func build(from spines: [NarrativeSpine]) -> SpineTransitionMatrix {
        var transitions: [String: [String: Int]] = [:]
        var totalOutgoing: [String: Int] = [:]
        var functionFrequency: [String: Int] = [:]
        var startFunctions: [String: Int] = [:]
        var endFunctions: [String: Int] = [:]
        var totalTransitions = 0

        for spine in spines {
            let beats = spine.beats.sorted { $0.beatNumber < $1.beatNumber }
            guard !beats.isEmpty else { continue }

            // Track start/end functions
            startFunctions[beats.first!.function, default: 0] += 1
            endFunctions[beats.last!.function, default: 0] += 1

            // Track function frequency
            for beat in beats {
                functionFrequency[beat.function, default: 0] += 1
            }

            // Track pairwise transitions
            for i in 0..<(beats.count - 1) {
                let from = beats[i].function
                let to = beats[i + 1].function
                transitions[from, default: [:]][to, default: 0] += 1
                totalOutgoing[from, default: 0] += 1
                totalTransitions += 1
            }
        }

        return SpineTransitionMatrix(
            transitions: transitions,
            totalOutgoing: totalOutgoing,
            functionFrequency: functionFrequency,
            startFunctions: startFunctions,
            endFunctions: endFunctions,
            sourceSpineCount: spines.count,
            totalTransitionCount: totalTransitions,
            builtAt: Date()
        )
    }

    // MARK: - Queries

    /// Probability of transitioning from one function to another.
    func probability(from: String, to: String) -> Double {
        guard let total = totalOutgoing[from], total > 0,
              let count = transitions[from]?[to] else { return 0 }
        return Double(count) / Double(total)
    }

    /// Top N most likely next functions after a given function.
    func topNextFunctions(after function: String, topK: Int = 5) -> [(function: String, probability: Double)] {
        guard let total = totalOutgoing[function], total > 0,
              let outgoing = transitions[function] else { return [] }

        return outgoing
            .map { (function: $0.key, probability: Double($0.value) / Double(total)) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    // MARK: - Disk Cache

    private static var cacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SpineTransitionMatrix", isDirectory: true)
    }

    private static func cacheFileURL(channelId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(channelId).json")
    }

    static func loadCached(channelId: String) -> SpineTransitionMatrix? {
        let fileURL = cacheFileURL(channelId: channelId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SpineTransitionMatrix.self, from: data)
        } catch {
            print("[SpineTransitionMatrix] Failed to load cache for \(channelId): \(error.localizedDescription)")
            return nil
        }
    }

    func saveToCache(channelId: String) {
        let dir = Self.cacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = Self.cacheFileURL(channelId: channelId)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(self)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[SpineTransitionMatrix] Failed to save cache for \(channelId): \(error.localizedDescription)")
        }
    }
}

// MARK: - Spine Transition Validator

struct SpineTransitionValidator {

    /// Validate a generated spine against the corpus transition matrix.
    static func validate(
        spine: NarrativeSpine,
        matrix: SpineTransitionMatrix,
        contentAtoms: [String]? = nil
    ) -> SpineValidationResult {
        let beats = spine.beats.sorted { $0.beatNumber < $1.beatNumber }

        // 1. Walk the beat sequence and compute per-transition probability
        var logProb: Double = 0
        var flaggedTransitions: [SpineValidationResult.FlaggedTransition] = []

        for i in 0..<(beats.count - 1) {
            let from = beats[i].function
            let to = beats[i + 1].function
            let p = matrix.probability(from: from, to: to)
            if p > 0 {
                logProb += log(p)
            } else {
                logProb += log(0.001) // penalty for unseen transition
            }
            if p < 0.05 {
                flaggedTransitions.append(.init(
                    fromFunction: from,
                    toFunction: to,
                    probability: p,
                    beatIndex: i + 1
                ))
            }
        }

        // 2. Check for commonly-expected transitions that are missing
        let spineTransitionSet = Set(
            (0..<(beats.count - 1)).map { i in
                "\(beats[i].function)→\(beats[i + 1].function)"
            }
        )
        var missingTransitions: [SpineValidationResult.MissingTransition] = []
        for (from, outgoing) in matrix.transitions {
            guard let total = matrix.totalOutgoing[from], total > 0 else { continue }
            for (to, count) in outgoing {
                let p = Double(count) / Double(total)
                if p >= 0.3 && !spineTransitionSet.contains("\(from)→\(to)") {
                    // Only flag if the from-function actually appears in the spine
                    if beats.contains(where: { $0.function == from }) {
                        missingTransitions.append(.init(
                            fromFunction: from,
                            toFunction: to,
                            expectedProbability: p
                        ))
                    }
                }
            }
        }

        // 3. Flag unknown function labels
        let unknownFunctions = beats
            .map(\.function)
            .filter { !NarrativeSpineBeat.isKnownFunction($0) }

        // 4. Validate dependency chain (no beat depends on a later beat)
        var hasValidDeps = true
        for beat in beats {
            for dep in beat.dependsOn {
                if dep >= beat.beatNumber && dep != 0 {
                    hasValidDeps = false
                    break
                }
            }
            if !hasValidDeps { break }
        }

        // 5. Check unmapped content atoms
        var unmappedAtoms: [String]?
        if let atoms = contentAtoms {
            let allContentTags = beats.map { $0.contentTag.lowercased() }
            let joined = allContentTags.joined(separator: " ")
            let unmapped = atoms.filter { atom in
                let keywords = atom.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 3 }
                // An atom is "mapped" if at least half its keywords appear in some contentTag
                guard !keywords.isEmpty else { return false }
                let matched = keywords.filter { joined.contains($0) }.count
                return Double(matched) / Double(keywords.count) < 0.5
            }
            if !unmapped.isEmpty {
                unmappedAtoms = unmapped
            }
        }

        return SpineValidationResult(
            sequenceLogProbability: logProb,
            lowProbabilityTransitions: flaggedTransitions,
            missingCommonTransitions: missingTransitions,
            unknownFunctions: Array(Set(unknownFunctions)),
            beatCount: beats.count,
            phaseCount: spine.phases.count,
            hasValidDependencyChain: hasValidDeps,
            unmappedContentAtoms: unmappedAtoms
        )
    }
}
