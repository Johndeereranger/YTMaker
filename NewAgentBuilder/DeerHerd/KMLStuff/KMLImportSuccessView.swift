//
//  KMLImportSuccessView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/2/25.
//


// MARK: - KMLImportSuccessView.swift
//import SwiftUI
//
//struct KMLImportSuccessView: View {
//    let pinsCount: Int
//    @Environment(\.dismiss) var dismiss
//    
//    var body: some View {
//        VStack(spacing: 30) {
//            Image(systemName: "checkmark.circle.fill")
//                .font(.system(size: 80))
//                .foregroundColor(.green)
//            
//            Text("Pins Imported Successfully")
//                .font(.title)
//                .fontWeight(.bold)
//            
//            VStack(spacing: 8) {
//                Text("\(pinsCount) pins")
//                    .font(.system(size: 48, weight: .bold))
//                    .foregroundColor(.blue)
//                
//                Text("Ready to assign to properties")
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//            }
//            .padding()
//            .background(Color.gray.opacity(0.1))
//            .cornerRadius(12)
//            
//            Spacer()
//            
//            Button("Done") {
//                dismiss()
//            }
//            .buttonStyle(.borderedProminent)
//            .controlSize(.large)
//        }
//        .padding()
//    }
//}

// MARK: - KMLImportSuccessView.swift
import SwiftUI

struct KMLImportSuccessView: View {
    let pinsCount: Int
    let sessionId: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var nav: NavigationViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Pins Imported Successfully")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 8) {
                Text("\(pinsCount) pins")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)
                
                Text("Ready to view on map")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    dismiss()
                    nav.push(.pinMapView(sessionId: sessionId))
                }) {
                    Label("View on Map", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    dismiss()
                    // Give dismiss time to complete, THEN navigate on the OUTER stack
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        nav.push(.pinMapView(sessionId: sessionId))
                    }
                }) {
                    Label("View on Map", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}
