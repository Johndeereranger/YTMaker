//
//  ScriptListViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


// MARK: - ScriptListViewModel
import Foundation
import Firebase

@MainActor
class ScriptListViewModel: ObservableObject {
    @Published var scripts: [Script] = []
    @Published var isPresentingNewScriptSheet = false

    func loadScripts() async {
        do {
            scripts = try await ScriptManager.instance.fetchScripts()
        } catch {
            print("❌ Failed to load scripts: \(error)")
        }
    }

    func addScript(title: String, content: String) async {
        let newScript = Script(title: title, content: content)
        do {
            try await ScriptManager.instance.saveScript(newScript)
            await loadScripts()
        } catch {
            print("❌ Failed to save script: \(error)")
        }
    }
    
    
}
