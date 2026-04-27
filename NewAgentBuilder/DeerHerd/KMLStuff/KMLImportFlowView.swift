//
//  KMLImportFlowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/2/25.
//


// MARK: - KMLImportFlowView.swift
// Simple flow: Import KML → Color Mapping → Save Pins → Done
import SwiftUI

//struct KMLImportFlowView: View {
//    @StateObject private var viewModel = ImportViewModel()
//    @EnvironmentObject var nav: NavigationViewModel
//    @Environment(\.dismiss) var dismiss
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                switch viewModel.currentStep {
//                case .optionalKML:
//                    OptionalKMLView(viewModel: viewModel)
//                    
//                case .colorMapping:
//                    ColorMappingView(viewModel: viewModel)
//                    
//                case .complete:
//                    KMLImportSuccessView(pinsCount: viewModel.kmlPins.count)
//                    
//                default:
//                    Text("Loading...")
//                }
//            }
//            .navigationTitle("Import KML Pins")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//        .navigationViewStyle(.stack)
//        .onAppear {
//            // Start at KML import
//            viewModel.currentStep = .optionalKML
//        }
//    }
//}
// MARK: - KMLImportFlowView.swift
// Simple flow: Import KML → Color Mapping → Save Pins → Done
import SwiftUI

struct KMLImportFlowView: View {
    //@StateObject private var viewModel = ImportViewModel()
    @EnvironmentObject var viewModel: ImportViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                switch viewModel.currentStep {
                case .optionalKML:
                    OptionalKMLView(viewModel: viewModel)
                    
                case .colorMapping:
                    ColorMappingView(viewModel: viewModel)
                    
                case .complete:
                    if let sessionId = viewModel.currentSession?.id {
                        KMLImportSuccessView(
                            pinsCount: viewModel.kmlPins.count,
                            sessionId: sessionId
                        )
                    } else {
                        Text("Error: No session found")
                    }
                    
                default:
                    Text("Loading...")
                }
            }
            .navigationTitle("Import KML Pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Start at KML import
            viewModel.currentStep = .optionalKML
        }
    }
}
