//
//  TestPinMapView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/2/25.
//


// MARK: - TestPinMapView.swift
// Simple test view to diagnose navigation issue

import SwiftUI

struct TestPinMapView: View {
    let sessionId: String
    
    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("TEST PIN MAP VIEW")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Session ID:")
                    .foregroundColor(.white)
                
                Text(sessionId)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                
                Text("If you see this, navigation works!")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .onAppear {
            print("🟢 TestPinMapView appeared with sessionId: \(sessionId)")
        }
    }
}

// MARK: - How to use:
// 1. Add to navigation:
//    case .pinMapView(let sessionId):
//        TestPinMapView(sessionId: sessionId)
//
// 2. If you see green screen with text, navigation works
// 3. If you see blank screen, navigation is broken
// 4. Once working, replace with real DeerMapView