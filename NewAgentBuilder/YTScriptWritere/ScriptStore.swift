//
//  ScriptStore.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//


// ============================================================================
// MARK: - GLOBAL SCRIPT STORE WITH PERSISTENCE
// ============================================================================
import SwiftUI

class ScriptStore: ObservableObject {
    static let instance = ScriptStore()
    
    @Published var scripts: [YTScript] = []
    
    private let saveKey = "SavedYTScripts"
    private let saveURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("ytscripts.json")
    }()
    
    private init() {
        loadScripts()
    }
    
    // MARK: - CRUD Operations
    
    func createScript(_ script: YTScript) {
        scripts.append(script)
        saveScripts()
        objectWillChange.send()
    }
    
    func updateScript(_ script: YTScript) {
        if let index = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[index] = script
            scripts[index].dateModified = Date()
            saveScripts()
            objectWillChange.send()
        }
    }
    
    func deleteScript(_ script: YTScript) {
        scripts.removeAll { $0.id == script.id }
        saveScripts()
        objectWillChange.send()
    }
    
    func deleteScripts(at offsets: IndexSet) {
        scripts.remove(atOffsets: offsets)
        saveScripts()
        objectWillChange.send()
    }
    
    // MARK: - Persistence
    
    private func saveScripts() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(scripts)
            try data.write(to: saveURL)
            print("✅ Saved \(scripts.count) scripts to disk")
        } catch {
            print("❌ Failed to save scripts: \(error)")
        }
    }
    
    private func loadScripts() {
        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            scripts = try decoder.decode([YTScript].self, from: data)
            print("✅ Loaded \(scripts.count) scripts from disk")
        } catch {
            print("⚠️ No saved scripts found, loading mock data")
            loadMockData()
        }
    }
    
    // MARK: - Mock Data (Only on first launch)
    
    private func loadMockData() {
    }
}
