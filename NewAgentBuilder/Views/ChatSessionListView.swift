//
//  ChatSessionListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/5/25.
//


import SwiftUI

struct ChatSessionListView: View {
    @StateObject private var viewModel = AgentViewModel.instance
    let agentId: UUID
    @EnvironmentObject var nav: NavigationViewModel
    @State private var localSessions: [ChatSession] = []

    private var agent: Agent {
        guard let agent = viewModel.agents.first(where: { $0.id == agentId }) else {
            return Agent.empty // 👈 fallback (you define .empty)
        }
        return agent
    }

    var body: some View {
     
    
                List {
                    ForEach(localSessions, id: \.id) { session in
                        ChatSessionRowView(session: session) {
                            if let index = localSessions.firstIndex(where: { $0.id == session.id }) {
                                let removed = localSessions.remove(at: index)
                                Task {
                                    await AgentViewModel.instance.deleteChatSession(removed, forAgentId: agent.id)
                                }
                            }
                        }
                              .frame(maxWidth: .infinity, alignment: .leading)
                              .contentShape(Rectangle())
                              .onTapGesture {
                                  nav.push(.agentRunner(agent, session))
                              }// Keep it visually consistent (no button chrome)
                    }
                }
      

        
        .navigationTitle("\(agent.name) Sessions")
        .id(UUID())
        .onAppear {
            localSessions = agent.chatSessions.sorted(by: { $0.createdAt > $1.createdAt })
        }
    }
    
    private func deleteChatSessions(at offsets: IndexSet) {
        let sessionsToDelete = offsets.map { localSessions[$0] }

        // Remove from local list to trigger UI update
        localSessions.remove(atOffsets: offsets)

        for session in sessionsToDelete {
            Task {
                await AgentViewModel.instance.deleteChatSession(session, forAgentId: agent.id)
            }
        }
    }
}

struct ChatSessionRowView: View {
    let session: ChatSession
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                showDeleteConfirm = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .alert("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { onDelete() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
