//
//  YTSCRIPTHomeView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/5/25.
//


import SwiftUI
import SwiftUI
//
//struct YTSCRIPTHomeView: View {
//    @EnvironmentObject var nav: NavigationViewModel
//    @State private var scripts: [YTSCRIPT] = []
//    @State private var showingNewScriptSheet = false
//    @State private var newScriptTitle = ""
//    
//    var body: some View {
//        List {
//            Section(header: Text("Scripts")) {
//                ForEach(scripts) { script in
//                    Button {
//                        nav.push(.newScriptEditor(script))
//                    } label: {
//                        HStack {
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(script.title)
//                                    .font(.headline)
//                                
//                                HStack {
//                                    Text(script.status.capitalized)
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                    
//                                    Spacer()
//                                    
//                                    Text(script.lastModified, style: .relative)
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }
//                            }
//                            Spacer()
//                            Image(systemName: "chevron.right")
//                                .foregroundColor(.gray)
//                        }
//                    }
//                    .buttonStyle(.plain)
//                }
//                .onDelete(perform: deleteScripts)
//            }
//        }
//        .navigationTitle("YT Scripts")
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                Button {
//                    showingNewScriptSheet = true
//                } label: {
//                    Label("New Script", systemImage: "plus")
//                }
//            }
//        }
//        .sheet(isPresented: $showingNewScriptSheet) {
//            newScriptSheet
//        }
//        .onAppear {
//            loadScripts()
//        }
//    }
//    
//    private var newScriptSheet: some View {
//        NavigationStack {
//            Form {
//                Section {
//                    TextField("Script Title", text: $newScriptTitle)
//                }
//            }
//            .navigationTitle("New Script")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") {
//                        showingNewScriptSheet = false
//                        newScriptTitle = ""
//                    }
//                }
//                
//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Create") {
//                        createNewScript()
//                    }
//                    .disabled(newScriptTitle.isEmpty)
//                }
//            }
//        }
//        .frame(width: 400, height: 200)
//    }
//    
//    private func loadScripts() {
//        // TODO: Load from Firebase
//        if scripts.isEmpty {
//            scripts = [
//                YTSCRIPT(title: "Scrape Timing Myth"),
//                YTSCRIPT(title: "Moon Phase Discovery"),
//                YTSCRIPT(title: "Buck Pressure Study")
//            ]
//        }
//    }
//    
//    private func createNewScript() {
//        let newScript = YTSCRIPT(title: newScriptTitle)
//        scripts.append(newScript)
//        nav.push(.newScriptEditor(newScript))
//        showingNewScriptSheet = false
//        newScriptTitle = ""
//    }
//    
//    private func deleteScripts(at offsets: IndexSet) {
//        scripts.remove(atOffsets: offsets)
//    }
//}


import SwiftUI

struct YTSCRIPTHomeView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @State private var scripts: [YTSCRIPT] = []
    @State private var showingNewScriptSheet = false
    @State private var newScriptTitle = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading scripts...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                    Text("Error loading scripts")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadScripts() }
                    }
                }
            } else {
                scriptsList
            }
        }
        .navigationTitle("YT Scripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewScriptSheet = true
                } label: {
                    Label("New Script", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewScriptSheet) {
            newScriptSheet
        }
        .task {
            await loadScripts()
        }
    }
    
    private var scriptsList: some View {
        List {
            // Semantic Script Writer - Corpus-matched writing
            Section {
                Button {
                    nav.push(.semanticScriptWriter)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.title2)
                            .foregroundColor(.purple)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Semantic Script Writer")
                                .font(.headline)
                            Text("Ramble → Match to corpus → Generate with patterns")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } header: {
                Text("AI Writing Tools")
            }

            if scripts.isEmpty {
                ContentUnavailableView(
                    "No Scripts Yet",
                    systemImage: "doc.text",
                    description: Text("Create your first script to get started")
                )
            } else {
                Section(header: Text("Scripts")) {
                    ForEach(scripts) { script in
                        Button {
                            nav.push(.newScriptEditor(script))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(script.title)
                                        .font(.headline)
                                    
                                    HStack {
                                        Text(script.status.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(script.lastModified, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteScripts)
                }
            }
        }
    }
    
    private var newScriptSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Script Title", text: $newScriptTitle)
                }
            }
            .navigationTitle("New Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewScriptSheet = false
                        newScriptTitle = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createNewScript() }
                    }
                    .disabled(newScriptTitle.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 200)
    }
    
    private func loadScripts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            scripts = try await YTSCRIPTManager.shared.fetchAllScripts()
            print("✅ Loaded \(scripts.count) scripts from Firebase")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to load scripts: \(error)")
        }
        
        isLoading = false
    }
    
    private func createNewScript() async {
        let newScript = YTSCRIPT(title: newScriptTitle)
        
        do {
            try await YTSCRIPTManager.shared.createScript(newScript)
            scripts.insert(newScript, at: 0)
            nav.push(.newScriptEditor(newScript))
            showingNewScriptSheet = false
            newScriptTitle = ""
        } catch {
            print("❌ Failed to create script: \(error)")
            errorMessage = "Failed to create script: \(error.localizedDescription)"
        }
    }
    
    private func deleteScripts(at offsets: IndexSet) {
        for index in offsets {
            let script = scripts[index]
            Task {
                do {
                    try await YTSCRIPTManager.shared.deleteScript(id: script.id)
                    await MainActor.run {
                        scripts.remove(at: index)
                    }
                } catch {
                    print("❌ Failed to delete script: \(error)")
                }
            }
        }
    }
}
