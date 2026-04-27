//
//  PresetLibraryHomeView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Main view for browsing and managing the preset library.
//

import SwiftUI

struct PresetLibraryHomeView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel = PresetLibraryViewModel()
    @State private var showingImport = false
    @State private var selectedType: EditType?
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Action Buttons Row
                HStack(spacing: 12) {
                    // Import Button
                    importButton

                    // Move Library Button
                    moveLibraryButton
                }

                // Filter tabs
                filterSection

                // Presets List
                if viewModel.isLoading {
                    ProgressView("Loading presets...")
                        .padding()
                } else if viewModel.library.isEmpty {
                    emptyStateView
                } else {
                    presetsGrid
                }
            }
            .padding()
        }
        .navigationTitle("Preset Library")
        .searchable(text: $searchText, prompt: "Search presets...")
        .onChange(of: searchText) { _, newValue in
            viewModel.search(newValue)
        }
        .sheet(isPresented: $showingImport) {
            FCPXMLImportView { result in
                viewModel.importPresets(from: result)
            }
        }
        .task {
            await viewModel.loadPresets()
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Presets")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Import FCPXML files to extract reusable transforms, text styles, transitions, and B-roll patterns.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Import Button

    private var importButton: some View {
        Button {
            showingImport = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Import")
                    .font(.headline)
                Text("FCPXML")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Move Library Button

    private var moveLibraryButton: some View {
        Button {
            nav.push(.moveLibrary)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "film.stack.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Moves")
                    .font(.headline)
                Text("Library")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PresetFilterChip(
                    title: "All",
                    count: viewModel.filteredLibrary.totalCount,
                    isSelected: selectedType == nil
                ) {
                    selectedType = nil
                }

                ForEach(EditType.allCases, id: \.self) { type in
                    let count = viewModel.filteredLibrary.filtered(by: type).count
                    PresetFilterChip(
                        title: type.displayName,
                        count: count,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Presets Yet")
                .font(.headline)

            Text("Import an FCPXML file from Final Cut Pro to extract edit presets.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Presets Grid

    private var presetsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            if let type = selectedType {
                // Show only selected type
                ForEach(viewModel.filteredLibrary.filtered(by: type), id: \.id) { preset in
                    PresetCard(preset: preset) {
                        viewModel.toggleFavorite(preset)
                    } onDelete: {
                        viewModel.delete(preset)
                    }
                }
            } else {
                // Show all types with section headers
                if !viewModel.filteredLibrary.transforms.isEmpty {
                    Section {
                        ForEach(viewModel.filteredLibrary.transforms) { preset in
                            PresetCard(preset: preset) {
                                viewModel.toggleFavorite(preset)
                            } onDelete: {
                                viewModel.delete(preset)
                            }
                        }
                    } header: {
                        sectionHeader("Transforms", count: viewModel.filteredLibrary.transforms.count)
                    }
                }

                if !viewModel.filteredLibrary.textOverlays.isEmpty {
                    Section {
                        ForEach(viewModel.filteredLibrary.textOverlays) { preset in
                            PresetCard(preset: preset) {
                                viewModel.toggleFavorite(preset)
                            } onDelete: {
                                viewModel.delete(preset)
                            }
                        }
                    } header: {
                        sectionHeader("Text Overlays", count: viewModel.filteredLibrary.textOverlays.count)
                    }
                }

                if !viewModel.filteredLibrary.transitions.isEmpty {
                    Section {
                        ForEach(viewModel.filteredLibrary.transitions) { preset in
                            PresetCard(preset: preset) {
                                viewModel.toggleFavorite(preset)
                            } onDelete: {
                                viewModel.delete(preset)
                            }
                        }
                    } header: {
                        sectionHeader("Transitions", count: viewModel.filteredLibrary.transitions.count)
                    }
                }

                if !viewModel.filteredLibrary.bRolls.isEmpty {
                    Section {
                        ForEach(viewModel.filteredLibrary.bRolls) { preset in
                            PresetCard(preset: preset) {
                                viewModel.toggleFavorite(preset)
                            } onDelete: {
                                viewModel.delete(preset)
                            }
                        }
                    } header: {
                        sectionHeader("B-Roll", count: viewModel.filteredLibrary.bRolls.count)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Filter Chip

struct PresetFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.3))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let preset: any EditPreset
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: preset.editType.icon)
                    .font(.title2)
                    .foregroundColor(.blue)

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: preset.isFavorite ? "star.fill" : "star")
                        .foregroundColor(preset.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Name
            Text(preset.name)
                .font(.headline)
                .lineLimit(2)

            // Description
            if let description = preset.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Tags
            if !preset.tags.isEmpty {
                HStack {
                    ForEach(preset.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Source file
            if let source = preset.sourceFile {
                Text(source)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minHeight: 150)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    preset.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: preset.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Preset?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This preset will be permanently deleted.")
        }
    }
}

// MARK: - View Model

@MainActor
class PresetLibraryViewModel: ObservableObject {
    @Published var library = PresetLibrary(transforms: [], textOverlays: [], transitions: [], bRolls: [])
    @Published var filteredLibrary = PresetLibrary(transforms: [], textOverlays: [], transitions: [], bRolls: [])
    @Published var isLoading = false
    @Published var showingError = false
    @Published var errorMessage: String?

    private let storage = PresetStorageService.shared
    private var searchText = ""

    func loadPresets() async {
        isLoading = true
        defer { isLoading = false }

        library = storage.loadAll()
        applyFilters()
    }

    func search(_ text: String) {
        searchText = text
        applyFilters()
    }

    func importPresets(from result: FCPXMLParseResult) {
        do {
            let count = try storage.saveAll(from: result)
            print("Imported \(count) presets")

            // Reload
            library = storage.loadAll()
            applyFilters()
        } catch {
            errorMessage = "Failed to save presets: \(error.localizedDescription)"
            showingError = true
        }
    }

    func toggleFavorite(_ preset: any EditPreset) {
        // This would need to update the specific preset type
        // For now, just reload
        library = storage.loadAll()
        applyFilters()
    }

    func delete(_ preset: any EditPreset) {
        do {
            try storage.delete(id: preset.id, type: preset.editType)
            library = storage.loadAll()
            applyFilters()
        } catch {
            errorMessage = "Failed to delete preset: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func applyFilters() {
        if searchText.isEmpty {
            filteredLibrary = library
        } else {
            filteredLibrary = library.filtered(by: searchText)
        }
    }
}
