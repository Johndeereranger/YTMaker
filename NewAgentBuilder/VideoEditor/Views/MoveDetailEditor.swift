//
//  MoveDetailEditor.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/6/26.
//
//  Editor panel for fine-tuning individual applied moves.
//  Allows adjusting duration, easing, and previewing the move.
//

import SwiftUI
import CoreMedia

// MARK: - Move Detail Editor

struct MoveDetailEditor: View {
    @ObservedObject var viewModel: MoveEditorViewModel
    let move: AppliedMove

    // Local editing state
    @State private var editedDuration: Double
    @State private var editedStartTime: Double
    @State private var useEaseIn: Bool = false
    @State private var useEaseOut: Bool = true

    init(viewModel: MoveEditorViewModel, move: AppliedMove) {
        self.viewModel = viewModel
        self.move = move
        _editedDuration = State(initialValue: move.durationSeconds)
        _editedStartTime = State(initialValue: move.startSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                Text("Move Settings")
                    .font(.headline)
                Spacer()

                // Delete button
                Button(action: { viewModel.removeMove(move) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Start Time
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Time")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(formatTime(editedStartTime))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .leading)

                    Slider(
                        value: $editedStartTime,
                        in: 0...max(0.1, viewModel.simplifiedDurationSeconds - editedDuration)
                    )
                    .onChange(of: editedStartTime) { _, newValue in
                        updateMoveStartTime(newValue)
                    }
                }

                // Fine adjustment buttons
                HStack(spacing: 8) {
                    Button("-1s") { adjustStartTime(by: -1.0) }
                    Button("-0.1s") { adjustStartTime(by: -0.1) }
                    Button("-1f") { adjustStartTime(by: -1.0/30.0) }
                    Spacer()
                    Button("+1f") { adjustStartTime(by: 1.0/30.0) }
                    Button("+0.1s") { adjustStartTime(by: 0.1) }
                    Button("+1s") { adjustStartTime(by: 1.0) }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }

            // Duration
            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(String(format: "%.2fs", editedDuration))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .leading)

                    Slider(
                        value: $editedDuration,
                        in: 0.03...5.0
                    )
                    .onChange(of: editedDuration) { _, newValue in
                        updateMoveDuration(newValue)
                    }
                }

                // Duration presets
                HStack(spacing: 8) {
                    ForEach([
                        ("Inst", 0.03),
                        ("Quick", 0.3),
                        ("Med", 0.5),
                        ("Slow", 1.0),
                        ("V.Slow", 2.0)
                    ], id: \.0) { label, duration in
                        Button(label) {
                            editedDuration = duration
                            updateMoveDuration(duration)
                        }
                        .buttonStyle(.bordered)
                        .tint(abs(editedDuration - duration) < 0.01 ? .accentColor : .secondary)
                    }
                }
                .font(.caption2)
            }

            // Easing
            VStack(alignment: .leading, spacing: 8) {
                Text("Easing")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    Toggle("Ease In", isOn: $useEaseIn)
                    Toggle("Ease Out", isOn: $useEaseOut)
                }
                #if os(macOS)
                .toggleStyle(.checkbox)
                #else
                .toggleStyle(.switch)
                #endif
                .font(.caption)

                // Visual easing preview
                EasingPreview(easeIn: useEaseIn, easeOut: useEaseOut)
                    .frame(height: 40)
            }

            Divider()

            // Preview controls
            HStack {
                Button(action: previewMove) {
                    Label("Preview", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)

                Button(action: seekToMove) {
                    Label("Go to Start", systemImage: "arrow.right.to.line")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 250)
    }

    // MARK: - Actions

    private func adjustStartTime(by delta: Double) {
        let newTime = max(0, min(viewModel.simplifiedDurationSeconds - editedDuration, editedStartTime + delta))
        editedStartTime = newTime
        updateMoveStartTime(newTime)
    }

    private func updateMoveStartTime(_ seconds: Double) {
        let newTime = CodableCMTime(seconds: seconds)
        viewModel.updateMovePosition(move, to: newTime)
    }

    private func updateMoveDuration(_ seconds: Double) {
        viewModel.updateMoveDuration(move, to: seconds)
    }

    private func previewMove() {
        // Seek to just before the move and play
        let previewStart = max(0, editedStartTime - 0.5)
        viewModel.seekToSeconds(previewStart)
        viewModel.play()

        // Stop after move completes
        DispatchQueue.main.asyncAfter(deadline: .now() + editedDuration + 1.0) {
            viewModel.pause()
        }
    }

    private func seekToMove() {
        viewModel.seekToSeconds(editedStartTime)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - Easing Preview

struct EasingPreview: View {
    let easeIn: Bool
    let easeOut: Bool

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height

                path.move(to: CGPoint(x: 0, y: height))

                // Draw bezier curve based on easing
                let cp1x: CGFloat = easeIn ? width * 0.4 : 0
                let cp1y: CGFloat = easeIn ? height : 0
                let cp2x: CGFloat = easeOut ? width * 0.6 : width
                let cp2y: CGFloat = easeOut ? 0 : height

                path.addCurve(
                    to: CGPoint(x: width, y: 0),
                    control1: CGPoint(x: cp1x, y: cp1y),
                    control2: CGPoint(x: cp2x, y: cp2y)
                )
            }
            .stroke(Color.accentColor, lineWidth: 2)

            // Reference line (linear)
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }
        .background(Color.platformControlBackground)
        .cornerRadius(4)
    }
}

// MARK: - Preview

#if DEBUG
struct MoveDetailEditor_Previews: PreviewProvider {
    static var previews: some View {
        let vm = MoveEditorViewModel.preview
        let move = AppliedMove(
            movePresetId: UUID(),
            startTime: CodableCMTime(seconds: 5.0),
            presetDurationSeconds: 0.5
        )

        MoveDetailEditor(viewModel: vm, move: move)
            .frame(width: 300, height: 500)
    }
}
#endif
