//
//  YTSCRIPTModePickerView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/23/26.
//

import SwiftUI

struct YTSCRIPTModePickerView: View {
    @Bindable var script: YTSCRIPT

    @State private var channels: [YouTubeChannel] = []
    @State private var styleProfiles: [StyleProfile] = []
    @State private var isLoadingChannels = false
    @State private var isLoadingProfiles = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Channel Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Study Creator")
                        .font(.headline)

                    Text("Select a creator whose style you want to emulate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isLoadingChannels {
                        ProgressView("Loading channels...")
                    } else {
                        Picker("Channel", selection: $script.selectedChannelId) {
                            Text("None").tag(nil as String?)
                            ForEach(channels, id: \.channelId) { channel in
                                Text(channel.name).tag(channel.channelId as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // MARK: - Style Profile Selection (only if channel selected)
                if script.selectedChannelId != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Style Profile")
                            .font(.headline)

                        Text("Choose the mode/approach for this script")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if isLoadingProfiles {
                            ProgressView("Loading profiles...")
                        } else if styleProfiles.isEmpty {
                            Text("No style profiles found for this creator. Run A3 clustering first.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            ForEach(styleProfiles) { profile in
                                StyleProfileRow(
                                    profile: profile,
                                    isSelected: script.selectedStyleProfileId == profile.profileId
                                )
                                .onTapGesture {
                                    script.selectedStyleProfileId = profile.profileId
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // MARK: - Selected Profile Summary
                if let profileId = script.selectedStyleProfileId,
                   let profile = styleProfiles.first(where: { $0.profileId == profileId }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected: \(profile.name)")
                            .font(.headline)

                        Text(profile.description)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if !profile.triggerTopics.isEmpty {
                            Text("Best for: \(profile.triggerTopics.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        if !profile.discriminators.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Key characteristics:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                ForEach(profile.discriminators.prefix(3), id: \.self) { disc in
                                    Text("• \(disc)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Style Mode")
        .task {
            await loadChannels()
        }
        .onChange(of: script.selectedChannelId) { oldValue, newValue in
            // Clear profile when channel changes
            if oldValue != newValue {
                script.selectedStyleProfileId = nil
                if let channelId = newValue {
                    Task {
                        await loadProfiles(for: channelId)
                    }
                } else {
                    styleProfiles = []
                }
            }
        }
    }

    private func loadChannels() async {
        isLoadingChannels = true
        defer { isLoadingChannels = false }

        do {
            // Load channels that have been studied (have styleIds)
            let allChannels = try await YouTubeFirebaseService.shared.getAllChannels()
            channels = allChannels.filter { !($0.styleIds?.isEmpty ?? true) }

            // If script already has a channel selected, load its profiles
            if let channelId = script.selectedChannelId {
                await loadProfiles(for: channelId)
            }
        } catch {
            print("Failed to load channels: \(error)")
        }
    }

    private func loadProfiles(for channelId: String) async {
        isLoadingProfiles = true
        defer { isLoadingProfiles = false }

        do {
            styleProfiles = try await CreatorAnalysisFirebase.shared.loadStyleProfiles(channelId: channelId)
        } catch {
            print("Failed to load profiles: \(error)")
            styleProfiles = []
        }
    }
}

// MARK: - Style Profile Row
struct StyleProfileRow: View {
    let profile: StyleProfile
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(profile.videoCount) videos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}
