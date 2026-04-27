//
//  AgentRunStatusView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/24/25.
//


import SwiftUI
import SwiftUI

struct AgentRunStatusView: View {
    let isRunning: Bool

    @State private var now: Date = Date()
    @State private var runStartTime: Date? = nil
    @State private var runEndTime: Date? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRunning {
                Text("⚙️ Running...")
                    .font(.subheadline)
                Text("Elapsed: \(formattedElapsed(from: runStartTime, to: now))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let start = runStartTime, let end = runEndTime {
                Text("🏁 Finished in \(formattedElapsed(from: start, to: end))")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .onReceive(timer) { newNow in
            now = newNow

            if isRunning && runStartTime == nil {
                runStartTime = newNow
                runEndTime = nil
            }

            if !isRunning && runStartTime != nil && runEndTime == nil {
                runEndTime = newNow
            }
        }
        .onChange(of: isRunning) { newValue in
            if newValue {
                runStartTime = Date()
                runEndTime = nil
            }
        }
    }

    private func formattedElapsed(from: Date?, to: Date) -> String {
        guard let from = from else { return "--" }
        let interval = Int(to.timeIntervalSince(from))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
