//
//  ScriptBreakdownDiagnosticView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//


import SwiftUI

/// Add this view to help diagnose Firebase save/load issues
// ScriptBreakdownDiagnosticView.swift (UPDATED)

import SwiftUI

struct ScriptBreakdownDiagnosticView: View {
    let videoId: String
    @State private var diagnosticInfo: String = ""
    @State private var isRunning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Script Breakdown Diagnostic")
                .font(.title2)
                .fontWeight(.bold)

            Text("Video ID: \(videoId)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button(action: { Task { await runDiagnostic() } }) {
                    HStack {
                        if isRunning { ProgressView().scaleEffect(0.8) }
                        Text(isRunning ? "Running..." : "Run Diagnostic")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .disabled(isRunning)

                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                .disabled(diagnosticInfo.isEmpty)
            }

            ScrollView {
                Text(diagnosticInfo.isEmpty ? "Tap 'Run Diagnostic' to generate output..." : diagnosticInfo)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled) // ✅ lets you manually select + copy
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
    }

    private func copyToClipboard() {
        guard !diagnosticInfo.isEmpty else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticInfo, forType: .string)
        #else
        UIPasteboard.general.string = diagnosticInfo
        #endif

        print("✅ Copied diagnostic output to clipboard")
    }

    private func append(_ text: String) {
        // ✅ UI updates must occur on the main thread
        DispatchQueue.main.async {
            self.diagnosticInfo += text
        }
        // ✅ also print so you see it in Xcode console while it runs
        print(text, terminator: "")
    }

    private func runDiagnostic() async {
        await MainActor.run {
            isRunning = true
            diagnosticInfo = ""
        }

        append("""
        ========================================
        SCRIPT BREAKDOWN DIAGNOSTIC
        ========================================
        Video ID: \(videoId)
        Timestamp: \(Date())

        """)

        do {
            let firebaseService = YouTubeFirebaseService()

            append("\n📹 Checking video existence...\n")
            if let video = try await firebaseService.fetchVideo(videoId: videoId) {
                append("✅ Video found: '\(video.title)'\n")
            } else {
                append("❌ Video not found in Firebase\n")
                await MainActor.run { isRunning = false }
                return
            }

            append("\n📋 Loading script breakdown...\n")
            if let breakdown = try await firebaseService.loadScriptBreakdown(videoId: videoId) {
                append("✅ Breakdown loaded successfully\n")
                append("""
                
                BREAKDOWN SUMMARY:
                  - Sentences: \(breakdown.sentences.count)
                  - Sections: \(breakdown.sections.count)
                  - Patterns: \(breakdown.allMarkedPatterns.count)
                  - Last edited: \(breakdown.lastEditedDate)

                """)

                append("\nSECTIONS DETAIL:\n")
                for (index, section) in breakdown.sections.enumerated() {
                    append("\n  Section \(index + 1): \(section.name)\n")
                    append("    - ID: \(section.id)\n")
                    append("    - Display name: \(section.displayName)\n")
                    append("    - Has AI analysis: \(section.hasAIAnalysis)\n")

                    if let belief = section.beliefInstalled, !belief.isEmpty {
                        append("    - Belief: '\(belief)'\n")
                    } else {
                        append("    - Belief: (none)\n")
                    }

                    if let notes = section.rawNotes, !notes.isEmpty {
                        let preview = String(notes.prefix(80))
                        append("    - Notes: '\(preview)\(notes.count > 80 ? "..." : "")'\n")
                    } else {
                        append("    - Notes: (none)\n")
                    }

                    if section.hasAIAnalysis {
                        append("    AI FIELDS:\n")
                        if let aiTitle = section.aiTitle, !aiTitle.isEmpty {
                            append("      - AI Title: '\(aiTitle)'\n")
                        }
                        if let aiSummary = section.aiSummary, !aiSummary.isEmpty {
                            let preview = String(aiSummary.prefix(80))
                            append("      - AI Summary: '\(preview)\(aiSummary.count > 80 ? "..." : "")'\n")
                        }
                        if let aiArchetype = section.aiArchetype, !aiArchetype.isEmpty {
                            append("      - AI Archetype: '\(aiArchetype)'\n")
                        }
                        if let aiPurpose = section.aiStrategicPurpose, !aiPurpose.isEmpty {
                            let preview = String(aiPurpose.prefix(80))
                            append("      - AI Purpose: '\(preview)\(aiPurpose.count > 80 ? "..." : "")'\n")
                        }
                        if let aiMechanism = section.aiMechanism, !aiMechanism.isEmpty {
                            let preview = String(aiMechanism.prefix(80))
                            append("      - AI Mechanism: '\(preview)\(aiMechanism.count > 80 ? "..." : "")'\n")
                        }
                    }

                    let sectionPatterns = breakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
                    append("    - Patterns: \(sectionPatterns.count)\n")
                }

                append("\n💾 Testing save operation...\n")
                try await firebaseService.saveScriptBreakdown(videoId: videoId, breakdown: breakdown)
                append("✅ Save completed\n")

                append("\n🔍 Verifying save by reloading...\n")
                if let reloadedBreakdown = try await firebaseService.loadScriptBreakdown(videoId: videoId) {
                    append("✅ Reloaded successfully\n")

                    if reloadedBreakdown.sections.count == breakdown.sections.count {
                        append("✅ Section count matches: \(reloadedBreakdown.sections.count)\n")
                    } else {
                        append("❌ Section count MISMATCH: \(reloadedBreakdown.sections.count) vs \(breakdown.sections.count)\n")
                    }

                    if let firstOriginal = breakdown.sections.first,
                       let firstReloaded = reloadedBreakdown.sections.first {
                        append("\nFIRST SECTION COMPARISON:\n")
                        append("  Original name: '\(firstOriginal.name)'\n")
                        append("  Reloaded name: '\(firstReloaded.name)'\n")
                        append("  Names match: \(firstOriginal.name == firstReloaded.name ? "✅" : "❌")\n")

                        append("\n  Original belief: '\(firstOriginal.beliefInstalled ?? "(nil)")'\n")
                        append("  Reloaded belief: '\(firstReloaded.beliefInstalled ?? "(nil)")'\n")
                        append("  Beliefs match: \(firstOriginal.beliefInstalled == firstReloaded.beliefInstalled ? "✅" : "❌")\n")

                        append("\n  Original has AI: \(firstOriginal.hasAIAnalysis)\n")
                        append("  Reloaded has AI: \(firstReloaded.hasAIAnalysis)\n")

                        if firstOriginal.hasAIAnalysis || firstReloaded.hasAIAnalysis {
                            append("  Original AI title: '\(firstOriginal.aiTitle ?? "(nil)")'\n")
                            append("  Reloaded AI title: '\(firstReloaded.aiTitle ?? "(nil)")'\n")
                            append("  AI titles match: \(firstOriginal.aiTitle == firstReloaded.aiTitle ? "✅" : "❌")\n")

                            append("  Original AI archetype: '\(firstOriginal.aiArchetype ?? "(nil)")'\n")
                            append("  Reloaded AI archetype: '\(firstReloaded.aiArchetype ?? "(nil)")'\n")
                            append("  AI archetypes match: \(firstOriginal.aiArchetype == firstReloaded.aiArchetype ? "✅" : "❌")\n")
                        }
                    }
                } else {
                    append("❌ Failed to reload after save\n")
                }
            } else {
                append("❌ No script breakdown found\n")
            }

            append("""
            
            ========================================
            DIAGNOSTIC COMPLETE
            ========================================

            """)

        } catch {
            append("\n❌ ERROR: \(error)\n")
            append("Error details: \(error.localizedDescription)\n")
        }

        await MainActor.run { isRunning = false }
    }
}


