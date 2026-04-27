//
//  YouTubeTranscriptService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//


import Foundation
/*
 ╔════════════════════════════════════════════════════════════════════════════╗
 ║                    YOUTUBE TRANSCRIPT SERVICE SETUP                        ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                                                                            ║
 ║  This service requires a local Python backend running on your Mac.         ║
 ║  The backend uses the youtube-transcript-api library to fetch transcripts. ║
 ║                                                                            ║
 ║  ⚠️  IMPORTANT: Only works in iOS Simulator (not real devices)             ║
 ║                                                                            ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                         HOW TO START THE SERVER                            ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                                                                            ║
 ║  1. Open Terminal                                                          ║
 ║  2. Navigate to the backend folder:                                        ║
 ║        cd youtube-transcript-backend                                       ║
 ║  3. Start the server:                                                      ║
 ║        python3 transcript_server.py                                        ║
 ║  4. You should see:                                                        ║
 ║        INFO: Uvicorn running on http://0.0.0.0:8000                        ║
 ║  5. Keep Terminal open while using the app                                 ║
 ║  6. Press Ctrl+C to stop the server when done                              ║
 ║                                                                            ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                            TEST THE SERVER                                 ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                                                                            ║
 ║  In a NEW Terminal tab, run:                                               ║
 ║     curl http://localhost:8000/api/transcript/ipoekJlQpA0                  ║
 ║                                                                            ║
 ║  You should see JSON with transcript text.                                 ║
 ║                                                                            ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                     FIRST-TIME SETUP (if needed)                           ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                                                                            ║
 ║  If the folder/file doesn't exist, run these commands:                     ║
 ║                                                                            ║
 ║     mkdir youtube-transcript-backend                                       ║
 ║     cd youtube-transcript-backend                                          ║
 ║     pip3 install fastapi uvicorn youtube-transcript-api                    ║
 ║                                                                            ║
 ║  Then create transcript_server.py with the Python code (see Claude chat).  ║
 ║                                                                            ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                           TROUBLESHOOTING                                  ║
 ╠════════════════════════════════════════════════════════════════════════════╣
 ║                                                                            ║
 ║  • "Connection refused" → Server not running. Start it in Terminal.        ║
 ║  • 404 error → Video may not have captions enabled.                        ║
 ║  • Works in Simulator but not device → localhost only works in Simulator.  ║
 ║  • "command not found: python" → Use python3 instead.                      ║
 ║                                                                            ║
 ╚════════════════════════════════════════════════════════════════════════════╝
 */
class YouTubeTranscriptService {
    // TODO: Replace with your deployed backend URL
    private let backendURL = "http://localhost:8000" // Change this when deployed
    
    func fetchTranscript(videoId: String) async throws -> String {
        let urlString = "\(backendURL)/api/transcript/\(videoId)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TranscriptAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        struct TranscriptResponse: Codable {
            let success: Bool
            let transcript: String
            let segments: [TranscriptSegment]?
        }
        
        struct TranscriptSegment: Codable {
            let text: String
            let start: Double
            let duration: Double
        }
        
        let transcriptResponse = try JSONDecoder().decode(TranscriptResponse.self, from: data)
        
        guard transcriptResponse.success else {
            throw NSError(domain: "TranscriptAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Transcript fetch failed"])
        }
        
        return transcriptResponse.transcript
    }
    
}
