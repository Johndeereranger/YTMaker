//
//  FidelityCrossVideoComparisonView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

struct FidelityCrossVideoComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allTests: [StoredFidelityTestRun] = []
    @State private var testedVideos: [(videoId: String, videoTitle: String, testCount: Int, lastTest: Date)] = []
    @State private var selectedPromptType: FidelityPromptType = .a1a
    @State private var commonVariancePatterns: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary stats
                    summarySection

                    Divider()

                    // Prompt type picker
                    Picker("Prompt Type", selection: $selectedPromptType) {
                        Text("A1a (Sections)").tag(FidelityPromptType.a1a)
                        Text("A1b (Beats)").tag(FidelityPromptType.a1b)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPromptType) { _, _ in
                        loadData()
                    }

                    // Common variance patterns
                    if selectedPromptType == .a1a && !commonVariancePatterns.isEmpty {
                        commonVariancePatternsSection
                    }

                    Divider()

                    // Per-video breakdown
                    perVideoBreakdownSection
                }
                .padding()
            }
            .navigationTitle("Fidelity Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear All") {
                        FidelityTestManager.shared.clearAll()
                        loadData()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                loadData()
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Summary")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    Text("\(testedVideos.count)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Videos Tested")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("\(allTests.count)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Total Runs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    let stableRuns = allTests.filter { $0.varianceCount == 0 }.count
                    let pct = allTests.isEmpty ? 0 : Int(Double(stableRuns) / Double(allTests.count) * 100)
                    Text("\(pct)%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(pct >= 80 ? .green : (pct >= 50 ? .orange : .red))
                    Text("100% Stable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private var commonVariancePatternsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common Variance Points")
                .font(.headline)

            Text("Roles that frequently show variance across videos:")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(Array(commonVariancePatterns.sorted { $0.value > $1.value }), id: \.key) { role, count in
                HStack {
                    Text(role)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(roleColor(role))

                    Spacer()

                    Text("\(count) videos with variance")
                        .font(.caption)
                        .foregroundColor(.orange)

                    // Show stability trend
                    let trend = FidelityTestManager.shared.getStabilityTrendForRole(role)
                    HStack(spacing: 2) {
                        ForEach(trend.indices, id: \.self) { idx in
                            Circle()
                                .fill(trend[idx].isStable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var perVideoBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Video Results")
                .font(.headline)

            if testedVideos.isEmpty {
                Text("No fidelity tests recorded yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(testedVideos, id: \.videoId) { video in
                    videoResultCard(video)
                }
            }
        }
    }

    private func videoResultCard(_ video: (videoId: String, videoTitle: String, testCount: Int, lastTest: Date)) -> some View {
        let videoTests = allTests.filter { $0.videoId == video.videoId && $0.promptType == selectedPromptType }
        let latestTest = videoTests.first  // Already sorted by date desc

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.videoTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text("\(video.testCount) tests, last: \(video.lastTest, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let test = latestTest {
                    VStack(alignment: .trailing, spacing: 2) {
                        if test.varianceCount == 0 {
                            Text("100% Stable")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("\(test.varianceCount) variance")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Text("T: \(String(format: "%.1f", test.temperature))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Show latest test results as dots
            if let test = latestTest {
                HStack(spacing: 4) {
                    ForEach(test.results) { result in
                        VStack(spacing: 2) {
                            Circle()
                                .fill(result.isStable ? Color.green : Color.orange)
                                .frame(width: 12, height: 12)
                            Text(shortRole(result.role))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }

                // Show variance details for unstable roles
                let unstableResults = test.results.filter { !$0.isStable }
                if !unstableResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(unstableResults) { result in
                            HStack {
                                Text(result.role)
                                    .font(.caption2)
                                    .foregroundColor(roleColor(result.role))
                                    .frame(width: 70, alignment: .leading)

                                Text(result.varianceDetails)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func loadData() {
        allTests = FidelityTestManager.shared.loadAll()
            .filter { $0.promptType == selectedPromptType }
        testedVideos = FidelityTestManager.shared.getTestedVideos()
        commonVariancePatterns = FidelityTestManager.shared.findCommonVariancePatterns()
    }

    private func shortRole(_ role: String) -> String {
        switch role {
        case "HOOK": return "HK"
        case "SETUP": return "SU"
        case "EVIDENCE": return "EV"
        case "TURN": return "TN"
        case "PAYOFF": return "PO"
        case "CTA": return "CT"
        case "SPONSORSHIP": return "SP"
        default:
            if role.hasPrefix("Beat ") {
                return "B\(role.dropFirst(5))"
            }
            return String(role.prefix(2))
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "HOOK": return .blue
        case "SETUP": return .green
        case "EVIDENCE": return .purple
        case "TURN": return .orange
        case "PAYOFF": return .pink
        case "CTA": return .red
        case "SPONSORSHIP": return .gray
        default: return .secondary
        }
    }
}
