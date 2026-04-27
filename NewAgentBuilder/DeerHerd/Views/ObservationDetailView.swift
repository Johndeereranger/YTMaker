//
//  ObservationDetailView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/25/25.
//


// MARK: - ObservationDetailView.swift (UPDATED PHOTO SECTION)
// FIND THE PHOTO GALLERY SECTION AND REPLACE WITH THIS:

import SwiftUI

struct ObservationDetailView: View {
    let observation: DeerObservation
    @ObservedObject var viewModel: MapViewModel
    let onDismiss: () -> Void
    
    @State private var selectedPhotoIndex = 0
    @State private var showLinkToBuckProfile = false
    @State private var showEditClassification = false
    @State private var newClassification: DeerClassification
    @State private var showingThermal = false  // NEW: Toggle between thermal/visible
    
    init(observation: DeerObservation, viewModel: MapViewModel, onDismiss: @escaping () -> Void) {
        self.observation = observation
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _newClassification = State(initialValue: observation.classification)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo gallery with thermal/visible toggle
                    if !observation.photos.isEmpty {
                        VStack(spacing: 12) {
                            // Toggle between thermal and visible if both exist
                            if observation.hasBothPhotoTypes {
                                Picker("Photo Type", selection: $showingThermal) {
                                    Text("Visible").tag(false)
                                    Text("Thermal").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            } else {
                                Text("ONLY ONE PHOTO")
                            }
                            
                            // Display selected photo type
                            if let photoToShow = currentPhoto {
//                                AsyncImageView(url: photoToShow.firebaseStorageUrl)
//                                    .frame(height: 300)
//                                    .transition(.opacity)
//                                    .id(photoToShow.id)
                                ZoomableAsyncImageView(url: photoToShow.firebaseStorageUrl)
                                       .frame(height: 300)
                                       .transition(.opacity)
                                       .id(photoToShow.id)
                            }
                        }
                    }
                    
                    // Details
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(label: "Classification", value: observation.classification.rawValue)
                        
                        DetailRow(label: "Date", value: observation.timestamp.formatted(date: .abbreviated, time: .shortened))
                        
                        DetailRow(label: "Location", value: String(format: "%.5f, %.5f", observation.gpsLat, observation.gpsLon))
                        
                        if let buckProfileId = observation.buckProfileId,
                           let profile = viewModel.buckProfiles.first(where: { $0.id == buckProfileId }) {
                            DetailRow(label: "Buck Profile", value: profile.name)
                        }
                        
                        // Show photo count
                        if observation.photos.count > 0 {
                            DetailRow(label: "Photos", value: "\(observation.photos.count)")
                        }
                        
                        // Nearby observations
                        let nearby = viewModel.getObservationsNear(location: observation.coordinate, within: 10)
                            .filter { $0.id != observation.id }
                        
                        if !nearby.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Other observations nearby")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(nearby.count) observation(s) within 10m")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    
                    // Actions
                    VStack(spacing: 12) {
                        if observation.classification.isBuck && observation.buckProfileId == nil {
                            Button(action: { showLinkToBuckProfile = true }) {
                                Label("Link to Buck Profile", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Button(action: { showEditClassification = true }) {
                            Label("Edit Classification", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                        
                        Button(role: .destructive, action: {
                            Task {
                                await viewModel.deleteObservation(observation)
                                onDismiss()
                            }
                        }) {
                            Label("Delete Observation", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Observation Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showLinkToBuckProfile) {
                LinkToBuckProfileSheet(
                    observation: observation,
                    buckProfiles: viewModel.buckProfiles,
                    onLink: { profileId in
                        Task {
                            var updated = observation
                            updated.buckProfileId = profileId
                            await viewModel.updateObservation(updated)
                            onDismiss()
                        }
                    }
                )
            }
            .sheet(isPresented: $showEditClassification) {
                EditClassificationSheet(
                    currentClassification: observation.classification,
                    onSave: { classification in
                        Task {
                            var updated = observation
                            updated.classification = classification
                            await viewModel.updateObservation(updated)
                            showEditClassification = false
                            //await viewModel.fetchObservations()
                        }
                    }
                )
            }
        }
    }
    
    // NEW: Helper to get current photo based on toggle
    private var currentPhoto: Photo? {
        if showingThermal {
            return observation.thermalPhoto ?? observation.primaryPhoto
        } else {
            return observation.primaryPhoto
        }
    }
}
