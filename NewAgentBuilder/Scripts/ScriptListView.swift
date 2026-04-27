//
//  ScriptListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import SwiftUI

struct ScriptListView: View {
    @StateObject private var viewModel = ScriptListViewModel()
    @EnvironmentObject var nav: NavigationViewModel
    @State private var isPresentingNewScriptSheet = false
    @State private var newScriptTitle: String = ""
    @State private var newScriptContent: String = ""
    
    var body: some View {
       
            List {
                ForEach(viewModel.scripts.sorted(by: { $0.createdAt > $1.createdAt })) { script in
                    Button {
                        nav.push(.scriptDetail(script))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(script.title)
                                .font(.headline)
                            Text(script.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain) // optional for visual consistency
                }
                //.onDelete(perform: viewModel.deleteScript)
            }
            .navigationTitle("Scripts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isPresentingNewScriptSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewScriptSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Title")) {
                            TextField("Script title", text: $newScriptTitle)
                        }

                        Section(header: Text("Full Content")) {
                            TextEditor(text: $newScriptContent)
                                .frame(height: 200)
                        }
                    }
                    .navigationTitle("New Script")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isPresentingNewScriptSheet = false
                                newScriptTitle = ""
                                newScriptContent = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                Task {
                                    await viewModel.addScript(title: newScriptTitle, content: newScriptContent)
                                    isPresentingNewScriptSheet = false
                                    newScriptTitle = ""
                                    newScriptContent = ""
                                }
                            }
                            .disabled(newScriptTitle.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .task {
                await viewModel.loadScripts()
            }
        
    }
}
