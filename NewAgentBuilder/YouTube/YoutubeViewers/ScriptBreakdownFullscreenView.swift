//
//  ScriptBreakdownFullscreenView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/3/26.
//
import SwiftUI

struct ScriptBreakdownFullscreenView: View {
    let video: YouTubeVideo
    
    var body: some View {
        if let transcript = video.transcript, !transcript.isEmpty {
            ScriptBreakdownEditorView(video: video, transcript: transcript, isFullscreen: true)
                .navigationTitle("Script Breakdown")
        } else {
            Text("No transcript available")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}
