//
//  PropertyListViewToolbar.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/2/25.
//


// MARK: - PropertyListView.swift (Alternative: Toolbar Approach)
// This adds tools to the navigation bar instead of inline

import SwiftUI

struct PropertyListViewToolbar: View {
    @StateObject private var viewModel: PropertyListViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showCreateSheet = false
    @State private var showToolsMenu = false
    
    init(operatorId: String = "default-operator") {
        _viewModel = StateObject(wrappedValue: PropertyListViewModel())
    }
    
    var body: some View {
        List {
            ForEach(viewModel.properties) { property in
                PropertyRowView(property: property)
                    .onTapGesture {
                        nav.push(.propertyDetail(property))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteProperty(property)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            // Left side: Tools menu
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button(action: {
                        nav.push(.kmlImport)
                    }) {
                        Label("Import Pins", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: {
                        nav.push(.allPinsMapView)
                    }) {
                        Label("View All Pins", systemImage: "map")
                    }
                    
                   
                    
                    Divider()
                    
                    Button(action: {
                        // TODO: Photo browser
                    }) {
                        Label("View All Photos", systemImage: "photo")
                    }
                    .disabled(true)
                } label: {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
            }
            
            // Right side: Create property
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PropertyCreateView(onCreate: { name, state, clientEmail, notes in
                Task {
                    await viewModel.createProperty(name: name, state: state, clientEmail: clientEmail, notes: notes)
                    showCreateSheet = false
                }
            })
        }
        .task {
            await viewModel.loadProperties()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading properties...")
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}
