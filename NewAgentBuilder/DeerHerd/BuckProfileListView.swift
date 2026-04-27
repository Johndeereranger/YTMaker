//
//  BuckProfileListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - BuckProfileListView.swift
import SwiftUI

struct BuckProfileListView: View {
    @StateObject private var viewModel: BuckProfileViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showCreateSheet = false
    
    init(property: Property) {
        _viewModel = StateObject(wrappedValue: BuckProfileViewModel(property: property))
    }
    
    var body: some View {
        List {
            ForEach(viewModel.buckProfiles) { profile in
                BuckProfileRowView(profile: profile, viewModel: viewModel)
                    .onTapGesture {
                        nav.push(.buckProfileDetail(profile))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteBuckProfile(profile)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Buck Profiles")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            BuckProfileCreateView(
                onCreate: { name, age, status, notes in
                    Task {
                        await viewModel.createBuckProfile(name: name, ageEstimate: age, status: status, notes: notes)
                        showCreateSheet = false
                    }
                }
            )
        }
        .task {
            await viewModel.loadData()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading buck profiles...")
            }
        }
    }
}

struct BuckProfileRowView: View {
    let profile: BuckProfile
    @ObservedObject var viewModel: BuckProfileViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                
                HStack {
                    if let age = profile.ageEstimate {
                        Text("Age: \(age)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(profile.status.rawValue)
                        .font(.caption)
                        .foregroundColor(profile.status == .live ? .green : .red)
                }
                
                Text("\(profile.linkedObservationIds.count) observations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show thumbnail if available
            if let firstObsId = profile.linkedObservationIds.first,
               let obs = viewModel.observations.first(where: { $0.id == firstObsId }),
               let photo = obs.photos.first {
                AsyncImageView(url: photo.thumbnailUrl ?? photo.firebaseStorageUrl)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - BuckProfileCreateView.swift
import SwiftUI

struct BuckProfileCreateView: View {
    let onCreate: (String, String?, BuckProfile.BuckStatus, String?) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var ageEstimate = ""
    @State private var status: BuckProfile.BuckStatus = .live
    @State private var notes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Buck Information") {
                    TextField("Name (e.g., Split G2)", text: $name)
                    TextField("Age Estimate (e.g., 3.5yr)", text: $ageEstimate)
                    
                    Picker("Status", selection: $status) {
                        ForEach(BuckProfile.BuckStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                
                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("New Buck Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(
                            name,
                            ageEstimate.isEmpty ? nil : ageEstimate,
                            status,
                            notes.isEmpty ? nil : notes
                        )
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - BuckProfileDetailView.swift
import SwiftUI
import MapKit

struct BuckProfileDetailView: View {
    @State private var profile: BuckProfile
    @StateObject private var viewModel: BuckProfileViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showEditSheet = false
    @State private var showLinkObservations = false
    
    init(profile: BuckProfile) {
        _profile = State(initialValue: profile)
        _viewModel = StateObject(wrappedValue: BuckProfileViewModel(property: Property(
            id: profile.propertyId,
            operatorId: "",
            name: "",
            state: ""
        )))
    }
    
    var linkedObservations: [DeerObservation] {
        viewModel.observations.filter { profile.linkedObservationIds.contains($0.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        if let age = profile.ageEstimate {
                            Label(age, systemImage: "calendar")
                        }
                        
                        Label(profile.status.rawValue, systemImage: profile.status == .live ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(profile.status == .live ? .green : .red)
                    }
                    .font(.subheadline)
                    
                    if let first = profile.firstSeenDate, let last = profile.lastSeenDate {
                        Text("First seen: \(first.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Last seen: \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                // Notes
                if let notes = profile.notes, !notes.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .font(.body)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Photo Gallery
                if !linkedObservations.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Photos (\(linkedObservations.flatMap { $0.photos }.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(linkedObservations) { obs in
                                    ForEach(obs.photos) { photo in
                                        AsyncImageView(url: photo.thumbnailUrl ?? photo.firebaseStorageUrl)
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Map of observations
                if !linkedObservations.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Locations (\(linkedObservations.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Map {
                            ForEach(linkedObservations) { obs in
                                Annotation("", coordinate: obs.coordinate) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                }
                            }
                        }
                        .frame(height: 300)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                
                // Timeline
                if !linkedObservations.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Timeline")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(linkedObservations.sorted(by: { $0.timestamp > $1.timestamp })) { obs in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(obs.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                    Text(obs.classification.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    Task {
                                        await viewModel.unlinkObservation(obs.id, from: profile)
                                        // Refresh profile
                                        if let updated = try? await DeerHerdFirebaseManager.shared.fetchBuckProfile(profile.id) {
                                            profile = updated
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button(action: { showLinkObservations = true }) {
                        Label("Link More Observations", systemImage: "link")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: { showEditSheet = true }) {
                        Label("Edit Profile", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Buck Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
        .sheet(isPresented: $showEditSheet) {
            BuckProfileEditView(profile: profile) { updated in
                Task {
                    await viewModel.updateBuckProfile(updated)
                    profile = updated
                    showEditSheet = false
                }
            }
        }
        .sheet(isPresented: $showLinkObservations) {
            UnassignedBuckSelectorView(
                unassignedBucks: viewModel.getUnassignedBuckObservations(),
                onLink: { obsId in
                    Task {
                        await viewModel.linkObservation(obsId, to: profile)
                        // Refresh profile
                        if let updated = try? await DeerHerdFirebaseManager.shared.fetchBuckProfile(profile.id) {
                            profile = updated
                        }
                    }
                }
            )
        }
    }
}

// MARK: - BuckProfileEditView.swift
import SwiftUI

struct BuckProfileEditView: View {
    let profile: BuckProfile
    let onSave: (BuckProfile) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var ageEstimate: String
    @State private var status: BuckProfile.BuckStatus
    @State private var notes: String
    
    init(profile: BuckProfile, onSave: @escaping (BuckProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _ageEstimate = State(initialValue: profile.ageEstimate ?? "")
        _status = State(initialValue: profile.status)
        _notes = State(initialValue: profile.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Buck Information") {
                    TextField("Name", text: $name)
                    TextField("Age Estimate", text: $ageEstimate)
                    
                    Picker("Status", selection: $status) {
                        ForEach(BuckProfile.BuckStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = profile
                        updated.name = name
                        updated.ageEstimate = ageEstimate.isEmpty ? nil : ageEstimate
                        updated.status = status
                        updated.notes = notes.isEmpty ? nil : notes
                        onSave(updated)
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - UnassignedBuckSelectorView.swift
import SwiftUI

struct UnassignedBuckSelectorView: View {
    let unassignedBucks: [DeerObservation]
    let onLink: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if unassignedBucks.isEmpty {
                    Text("No unassigned buck observations")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(unassignedBucks) { obs in
                        Button(action: {
                            onLink(obs.id)
                            dismiss()
                        }) {
                            HStack {
                                if let photo = obs.primaryPhoto {
                                    AsyncImageView(url: photo.thumbnailUrl ?? photo.firebaseStorageUrl)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(obs.classification.rawValue)
                                        .font(.headline)
                                    Text(obs.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
