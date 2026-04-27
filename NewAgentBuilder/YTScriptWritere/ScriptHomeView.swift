//
//  ScriptHomeView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//
import SwiftUI

// MARK: - Script Home View (Main List)
struct ScriptHomeView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var store = ScriptStore.instance
    @State private var searchText = ""
    @State private var showingNewScript = false
    @State private var selectedScripts = Set<YTScript.ID>()
    @State private var showingDeleteConfirmation = false
    @State private var scriptToDelete: YTScript?
    
    var filteredScripts: [YTScript] {
        if searchText.isEmpty {
            return store.scripts.sorted { $0.dateModified > $1.dateModified }
        } else {
            return store.scripts
                .filter { $0.title.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.dateModified > $1.dateModified }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredScripts) { script in
                Button {
                    nav.push(.scriptEditor(script))
                } label: {
                    ScriptRowView(script: script)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.deleteScript(script)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        nav.push(.scriptEditor(script))
                    } label: {
                        Label("Open", systemImage: "arrow.right")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        scriptToDelete = script
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.deleteScript(filteredScripts[index])
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search scripts")
        .navigationTitle("Scripts")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewScript = true
                } label: {
                    Label("New Script", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewScript) {
            NewScriptView()
        }
        .alert("Delete Script?", isPresented: $showingDeleteConfirmation, presenting: scriptToDelete) { script in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.deleteScript(script)
            }
        } message: { script in
            Text("Are you sure you want to delete '\(script.title)'? This action cannot be undone.")
        }
    }
}
