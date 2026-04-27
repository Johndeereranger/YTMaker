//
//  KMLMatchResultsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - KMLMatchResultsView.swift
import SwiftUI
import MapKit

//struct KMLMatchResultsView: View {
//    @ObservedObject var viewModel: ImportViewModel
//    @State private var showManualMatch = false
//
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 24) {
//                // Header
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Matching Results")
//                        .font(.title)
//                        .fontWeight(.bold)
//
//                    Text("Review how KML pins matched to your photos")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                }
//                .padding(.horizontal)
//
//                // Summary Stats
//                HStack(spacing: 16) {
//                    StatCard(
//                        title: "Matched",
//                        value: "\(viewModel.matchedPairs.count)",
//                        color: .green,
//                        icon: "checkmark.circle.fill"
//                    )
//
//                    StatCard(
//                        title: "Photo Groups",
//                        value: "\(photoGroupCount(viewModel.unmatchedPhotos))",
//                        color: .orange,
//                        icon: "photo.fill"
//                    )
//
//                    StatCard(
//                        title: "Pins in Database",  // Changed from "Pins Only"
//                        value: "\(viewModel.unmatchedPins.count)",
//                        color: .blue,
//                        icon: "mappin.circle.fill"
//                    )
//                }
//                .padding(.horizontal)
//
//                // Manual Match Button (if unmatched items exist)
//                if !viewModel.unmatchedPins.isEmpty || !viewModel.unmatchedPhotos.isEmpty {
//                    Button(action: {
//                        showManualMatch = true
//                    }) {
//                        HStack {
//                            Image(systemName: "hand.point.up.left.fill")
//                                .foregroundColor(.orange)
//                            Text("Manually Match Unmatched Items")
//                                .fontWeight(.semibold)
//                            Spacer()
//                            Image(systemName: "chevron.right")
//                        }
//                        .padding()
//                        .background(Color.orange.opacity(0.1))
//                        .cornerRadius(12)
//                    }
//                    .padding(.horizontal)
//                }
//
//                // Matched Pairs
//                if !viewModel.matchedPairs.isEmpty {
//                    VStack(alignment: .leading, spacing: 12) {
//                        Text("✅ Matched Pairs (\(viewModel.matchedPairs.count))")
//                            .font(.headline)
//                            .padding(.horizontal)
//
//                        ForEach(Array(viewModel.matchedPairs.enumerated()), id: \.offset) { index, pair in
//                            MatchedPairRow(
//                                photo: pair.photo,
//                                pin: pair.pin,
//                                classification: viewModel.colorMappings[pair.pin.color] ?? .buck
//                            )
//                        }
//                    }
//                }
//
//                // Unmatched Photos
//                if !viewModel.unmatchedPhotos.isEmpty {
//                    VStack(alignment: .leading, spacing: 12) {
//                        Text("📷 Photos Without KML Pin (\(photoGroupCount(viewModel.unmatchedPhotos)))")
//                            .font(.headline)
//                            .padding(.horizontal)
//
//                        Text("These will get default 'Unknown' classification")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .padding(.horizontal)
//
//                        ForEach(viewModel.unmatchedPhotos) { photo in
//                            UnmatchedPhotoRow(photo: photo)
//                        }
//                    }
//                }
//
//
//
//                // Action Button
//                Button(action: {
//                    Task {
//                        await viewModel.completeImport()
//                    }
//                }) {
//                    if viewModel.isProcessing {
//                        ProgressView()
//                            .progressViewStyle(.circular)
//                            .tint(.white)
//                    } else {
//                        Text("Done")
//                            .fontWeight(.semibold)
//                    }
//                }
//                .frame(maxWidth: .infinity)
//                .padding()
//                .background(Color.blue)
//                .foregroundColor(.white)
//                .cornerRadius(12)
//                .padding(.horizontal)
//                .disabled(viewModel.isProcessing)
//            }
//            .padding(.vertical)
//        }
//        .navigationTitle("Match Results")
//        .sheet(isPresented: $showManualMatch) {
//            ManualMatchSheet(viewModel: viewModel)
//        }
//    }
//
//    private func photoGroupCount(_ photos: [Photo]) -> Int {
//        let groups = Dictionary(grouping: photos) { photo in
//            if let filename = photo.metadata["filename"] {
//                return filename
//                    .replacingOccurrences(of: "_T.JPG", with: "", options: .caseInsensitive)
//                    .replacingOccurrences(of: "_V.JPG", with: "", options: .caseInsensitive)
//            }
//            return photo.id
//        }
//        return groups.count
//    }
//}

// MARK: - ManualMatchSheet.swift (COMPLETE REBUILD)
import SwiftUI
import CoreLocation

struct ManualMatchSheet: View {
    @ObservedObject var viewModel: ImportViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedPin: KMLPin?
    @State private var selectedPhotoGroup: [Photo]?
    @State private var showPhotoViewer = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // LEFT: Unmatched Photo Groups (SWAPPED)
                    VStack(spacing: 0) {
                      // Text("Photo Groups (\(filteredPhotoGroups.count))")
                        
                        Text("Photo Groups (\(photoGroups.count))")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.1))
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                //ForEach(filteredPhotoGroups.indices, id: \.self) { index in
                                ForEach(filteredPhotoGroups.indices, id: \.self) { index in
                                    PhotoGroupCard(
                                        photoGroup: filteredPhotoGroups[index],
                                        isSelected: selectedPhotoGroup?.first?.id == filteredPhotoGroups[index].first?.id,
                                        nearbyPins: filteredPins(for: filteredPhotoGroups[index])
                                    )
                                    .onTapGesture {
                                        selectedPhotoGroup = filteredPhotoGroups[index]
                                        selectedPin = nil  // Clear pin selection
                                    }
                                    .onLongPressGesture {
                                        selectedPhotoGroup = filteredPhotoGroups[index]
                                        showPhotoViewer = true
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(width: geometry.size.width / 2)
                    
                    Divider()
                    
                    // RIGHT: Filtered Pins (SWAPPED)
                    VStack(spacing: 0) {
                        if let photoGroup = selectedPhotoGroup {
                            VStack(spacing: 8) {
                                Text("Nearby Pins")
                                    .font(.headline)
                                Text("\(filteredPins(for: photoGroup).count) within 300m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                        } else {
                            Text("Select a photo group")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.1))
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                if let photoGroup = selectedPhotoGroup {
                                    ForEach(filteredPins(for: photoGroup), id: \.id) { pin in
                                        FilteredPinCard(
                                            pin: pin,
                                            photoGroup: photoGroup,
                                            classification: viewModel.colorMappings[pin.color] ?? .unknown,
                                            isSelected: selectedPin?.id == pin.id
                                        )
                                        .onTapGesture {
                                            selectedPin = pin
                                        }
                                    }
                                } else {
                                    Text("Select a photo group to see nearby pins")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding()
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(width: geometry.size.width / 2)
                }
                
                // Bottom Action Bar
                if selectedPin != nil || selectedPhotoGroup != nil {
                    VStack {
                        Spacer()
                        actionBar
                    }
                }
            }
            .navigationTitle("Manual Matching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPhotoViewer) {
                if let photoGroup = selectedPhotoGroup {
                    PhotoViewerSheet(photoGroup: photoGroup)
                }
            }
        }
    }
    
    private var actionBar: some View {
        VStack(spacing: 12) {
            if let pin = selectedPin, let group = selectedPhotoGroup {
                let distance = distanceBetween(pin: pin, photoGroup: group)
                let timeDiff = timeDifference(pin: pin, photoGroup: group)
                
                VStack(spacing: 4) {
                    Text("Match these?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 16) {
                        Text("\(String(format: "%.1fm", distance))")
                            .font(.caption)
                        Text("Δt: \(formatTimeDiff(timeDiff))")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    Button("Clear") {
                        selectedPin = nil
                        selectedPhotoGroup = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Match") {
                        matchManually(pin: pin, photoGroup: group)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("View Photo") {
                        showPhotoViewer = true
                    }
                    .buttonStyle(.bordered)
                }
            } else if selectedPhotoGroup != nil {
                VStack(spacing: 4) {
                    Text("Photo group selected")
                        .font(.subheadline)
                    Text("Tap a pin on the right to match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("View Full Photo") {
                        showPhotoViewer = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }
    
    // MARK: - Filtering Logic
    
    /// Group photos by base filename
    private var photoGroups: [[Photo]] {
        var groups: [String: [Photo]] = [:]
        for photo in viewModel.unmatchedPhotos {
            if let filename = photo.metadata["filename"] {
                let base = filename
                    .replacingOccurrences(of: "_T.JPG", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "_V.JPG", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "_T.jpg", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "_V.jpg", with: "", options: .caseInsensitive)
                if groups[base] == nil {
                    groups[base] = []
                }
                groups[base]?.append(photo)
            }
        }
        return Array(groups.values).sorted { g1, g2 in
            g1.first?.timestamp ?? Date() < g2.first?.timestamp ?? Date()
        }
    }
    
    /// Filter photo groups: only show groups with at least one nearby pin (within 300m, same day)
    private var filteredPhotoGroups: [[Photo]] {
        photoGroups.filter { group in
            !filteredPins(for: group).isEmpty
        }
    }
    
    /// Get pins near a photo group: within 300m, same day, sorted by time difference
    private func filteredPins(for photoGroup: [Photo]) -> [KMLPin] {
        guard let firstPhoto = photoGroup.first else { return [] }
        
        let photoDate = Calendar.current.startOfDay(for: firstPhoto.timestamp)
        let photoCoord = CLLocationCoordinate2D(latitude: firstPhoto.gpsLat, longitude: firstPhoto.gpsLon)
        
        let filtered = viewModel.unmatchedPins.filter { pin in
            // Filter 1: Same day
            let pinDate = Calendar.current.startOfDay(for: pin.createdDate)
            guard pinDate == photoDate else { return false }
            
            // Filter 2: Within 300 meters
            let distance = CoordinateUtilities.shared.distance(
                from: pin.coordinate,
                to: photoCoord
            )
            return distance <= 300.0
        }
        
        // Sort by time difference (closest first)
        return filtered.sorted { pin1, pin2 in
            let diff1 = abs(firstPhoto.timestamp.timeIntervalSince(pin1.createdDate))
            let diff2 = abs(firstPhoto.timestamp.timeIntervalSince(pin2.createdDate))
            return diff1 < diff2
        }
    }
    
    private func distanceBetween(pin: KMLPin, photoGroup: [Photo]) -> Double {
        guard let firstPhoto = photoGroup.first else { return 0 }
        return CoordinateUtilities.shared.distance(
            from: pin.coordinate,
            to: CLLocationCoordinate2D(latitude: firstPhoto.gpsLat, longitude: firstPhoto.gpsLon)
        )
    }
    
    private func timeDifference(pin: KMLPin, photoGroup: [Photo]) -> TimeInterval {
        guard let firstPhoto = photoGroup.first else { return 0 }
        return abs(firstPhoto.timestamp.timeIntervalSince(pin.createdDate))
    }
    
    private func formatTimeDiff(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
    
    private func matchManually(pin: KMLPin, photoGroup: [Photo]) {
        // Sort so visible comes first (same as automatic matching)
        var sortedGroup = photoGroup
        sortedGroup.sort { photo1, photo2 in
            let filename1 = photo1.metadata["filename"] ?? ""
            let filename2 = photo2.metadata["filename"] ?? ""
            
            // Visible (_V) comes before Thermal (_T)
            let isVisible1 = filename1.contains("_V.") || filename1.contains("_v.")
            let isVisible2 = filename2.contains("_V.") || filename2.contains("_v.")
            
            if isVisible1 && !isVisible2 { return true }  // V before T
            if !isVisible1 && isVisible2 { return false } // T after V
            return false // Keep original order if both same type
        }
        
        // Append the entire photo group (not just first photo)
        viewModel.matchedPairs.append((photoGroup: sortedGroup, pin: pin))
        
        // Remove matched pin
        viewModel.unmatchedPins.removeAll { $0.id == pin.id }
        
        // Remove all photos in the group from unmatched
        for photo in photoGroup {
            viewModel.unmatchedPhotos.removeAll { $0.id == photo.id }
        }
        
        selectedPin = nil
        selectedPhotoGroup = nil
    }
}



// MARK: - KMLMatchResultsView.swift (FIXED - Actually groups all photos)
struct KMLMatchResultsView: View {
    @ObservedObject var viewModel: ImportViewModel
    @State private var showManualMatch = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Matching Results")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Review how KML pins matched to your photos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Summary Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "Matched",
                        value: "\(matchedPhotoGroups.count)",  // ← Count of groups, not pairs
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )
                    
                    StatCard(
                        title: "Photo Groups",
                        value: "\(unmatchedPhotoGroups.count)",
                        color: .orange,
                        icon: "photo.fill"
                    )
                    
                    StatCard(
                        title: "Pins in Database",
                        value: "\(viewModel.unmatchedPins.count)",
                        color: .blue,
                        icon: "mappin.circle.fill"
                    )
                }
                .padding(.horizontal)
                
                // Manual Match Button
                if !viewModel.unmatchedPins.isEmpty || !viewModel.unmatchedPhotos.isEmpty {
                    Button(action: {
                        showManualMatch = true
                    }) {
                        HStack {
                            Image(systemName: "hand.point.up.left.fill")
                                .foregroundColor(.orange)
                            Text("Manually Match Unmatched Items")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                // Matched Pairs - Now shows full groups with both thermal and visible
                if !matchedPhotoGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("✅ Matched Pairs (\(matchedPhotoGroups.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(matchedPhotoGroups.keys.sorted()), id: \.self) { baseFilename in
                            if let photoGroup = matchedPhotoGroups[baseFilename],
                               let pair = findMatchedPair(for: photoGroup) {
                                MatchedPairRow(
                                    photoGroup: photoGroup,
                                    pin: pair.pin,
                                    classification: viewModel.colorMappings[pair.pin.color] ?? .doe
                                )
                            }
                        }
                    }
                }
                
                // Unmatched Photo Groups
                if !unmatchedPhotoGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📷 Photo Groups Without KML Pin (\(unmatchedPhotoGroups.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Text("These will get default 'Unknown' classification")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ForEach(Array(unmatchedPhotoGroups.keys.sorted()), id: \.self) { baseFilename in
                            if let photoGroup = unmatchedPhotoGroups[baseFilename] {
                                UnmatchedPhotoGroupRow(photoGroup: photoGroup)
                            }
                        }
                    }
                }
                
                // Action Button
                Button(action: {
                    Task {
                        await viewModel.completeImport()
                    }
                }) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(viewModel.isProcessing)
            }
            .padding(.vertical)
        }
        .navigationTitle("Match Results")
        .sheet(isPresented: $showManualMatch) {
            ManualMatchSheet(viewModel: viewModel)
        }
    }
    
    // MARK: - Photo Grouping (shared logic)
    private func groupPhotosBySequence(_ photos: [Photo]) -> [String: [Photo]] {
        var groups: [String: [Photo]] = [:]
        for photo in photos {
            guard let filename = photo.metadata["filename"],
                  let sequence = extractDJISequenceNumber(from: filename) else {
                continue
            }
            
            if groups[sequence] == nil {
                groups[sequence] = []
            }
            groups[sequence]?.append(photo)
        }
        return groups
    }

    private func extractDJISequenceNumber(from filename: String) -> String? {
        // DJI_20251203201351_0011_V.JPG -> extract "0011"
        let components = filename.components(separatedBy: "_")
        guard components.count >= 3,
                  components[0] == "DJI" else {
            return nil
        }
        return components[2] // The sequence number (0011, 0012, etc.)
    }

    // MARK: - Computed Properties for View
    private var matchedPhotoGroups: [String: [Photo]] {
        // Get sequence numbers of matched photos
        let matchedSequences = Set(viewModel.matchedPairs.compactMap { pair -> String? in
            guard let filename = pair.photoGroup.first?.metadata["filename"] else { return nil }
            return extractDJISequenceNumber(from: filename)
        })
        
        // Filter to matched photos only
        let matchedPhotos = viewModel.importedPhotos.filter { photo in
            guard let filename = photo.metadata["filename"],
                  let sequence = extractDJISequenceNumber(from: filename) else {
                return false
            }
            return matchedSequences.contains(sequence)
        }
        
        return groupPhotosBySequence(matchedPhotos)
    }

    private var unmatchedPhotoGroups: [String: [Photo]] {
        return groupPhotosBySequence(viewModel.unmatchedPhotos)
    }

    // MARK: - Helper: Find the matched pair for a photo group
    private func findMatchedPair(for photoGroup: [Photo]) -> (photoGroup: [Photo], pin: KMLPin)? {
        for photo in photoGroup {
            if let pair = viewModel.matchedPairs.first(where: { matchedPair in
                matchedPair.photoGroup.contains(where: { $0.id == photo.id })
            }) {
                return pair
            }
        }
        return nil
    }
}
// MARK: - MatchedPairRow.swift (UPDATED - Shows BOTH photos, color first)
struct MatchedPairRow: View {
    let photoGroup: [Photo]  // ← Changed from single Photo to array
    let pin: KMLPin
    let classification: DeerClassification
    
    // Get visible photo (color)
    private var visiblePhoto: Photo? {
        photoGroup.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_V.") || filename.contains("_v.")
            }
            return false
        }
    }
    
    // Get thermal photo
    private var thermalPhoto: Photo? {
        photoGroup.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_T.") || filename.contains("_t.")
            }
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // VISIBLE/COLOR photo FIRST
            if let visible = visiblePhoto {
                photoThumbnail(visible)
            } else {
                Text("No Visible ")
            }
            
            // THERMAL photo SECOND
            if let thermal = thermalPhoto {
                photoThumbnail(thermal)
            } else {
                Text (" NO THERMAL ")
            }
            
            // If only one photo exists, show it
            if visiblePhoto == nil && thermalPhoto == nil, let firstPhoto = photoGroup.first {
                HStack {
                    photoThumbnail(firstPhoto)
                    Text("No Group Photos")
                }
                
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(colorForPin(pin.color))
                        .frame(width: 12, height: 12)
                    Text(classification.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text("Pin: \(pin.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let firstPhoto = photoGroup.first {
                    Text(firstPhoto.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if photoGroup.count > 1 {
                    Text("\(photoGroup.count) photos")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Debug info
            if let firstPhoto = photoGroup.first {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("RAW DEBUG:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("Photo: \(rawTimestamp(firstPhoto.timestamp))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text("Pin: \(rawTimestamp(pin.createdDate))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text("Δt: \(Int(abs(firstPhoto.timestamp.timeIntervalSince(pin.createdDate))))s")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // Helper: Photo thumbnail view
    private func photoThumbnail(_ photo: Photo) -> some View {
        AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.firebaseStorageUrl ?? "")) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func colorForPin(_ color: String) -> Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
    
    private func rawTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - UnmatchedPhotoGroupRow.swift (NEW - Shows photo groups)
struct UnmatchedPhotoGroupRow: View {
    let photoGroup: [Photo]
    
    // Get visible photo (color)
    private var visiblePhoto: Photo? {
        photoGroup.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_V.") || filename.contains("_v.")
            }
            return false
        }
    }
    
    // Get thermal photo
    private var thermalPhoto: Photo? {
        photoGroup.first { photo in
            if let filename = photo.metadata["filename"] {
                return filename.contains("_T.") || filename.contains("_t.")
            }
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // VISIBLE/COLOR photo FIRST
            if let visible = visiblePhoto {
                photoThumbnail(visible)
            }
            
            // THERMAL photo SECOND
            if let thermal = thermalPhoto {
                photoThumbnail(thermal)
            }
            
            // If only one photo exists, show it
            if visiblePhoto == nil && thermalPhoto == nil, let firstPhoto = photoGroup.first {
                photoThumbnail(firstPhoto)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo Group (no KML pin)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Default: Unknown")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                if let firstPhoto = photoGroup.first {
                    Text(firstPhoto.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if photoGroup.count > 1 {
                    Text("\(photoGroup.count) photos (T+V)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Image(systemName: "photo.fill")
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // Helper: Photo thumbnail view
    private func photoThumbnail(_ photo: Photo) -> some View {
        AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.firebaseStorageUrl ?? "")) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Photo Group Card (Left Side)
struct PhotoGroupCard: View {
    let photoGroup: [Photo]
    let isSelected: Bool
    let nearbyPins: [KMLPin]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let firstPhoto = (photoGroup.first { $0.metadata["filename"]?.contains("_V") == true } ?? photoGroup.first) {
                // Thumbnail
                AsyncImage(url: URL(string: firstPhoto.thumbnailUrl ?? firstPhoto.firebaseStorageUrl ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Info
                if let filename = firstPhoto.metadata["filename"] {
                    Text(filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                
                Text(firstPhoto.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Nearby pins count
                HStack {
                    Image(systemName: "mappin.circle")
                        .font(.caption2)
                    Text("\(nearbyPins.count) nearby")
                        .font(.caption2)
                }
                .foregroundColor(nearbyPins.isEmpty ? .orange : .green)
                
                if photoGroup.count > 1 {
                    Text("\(photoGroup.count) photos (T+V)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Filtered Pin Card (Right Side)
struct FilteredPinCard: View {
    let pin: KMLPin
    let photoGroup: [Photo]
    let classification: DeerClassification
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorForPin(pin.color))
                    .frame(width: 16, height: 16)
                
                Text(classification.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            Text(pin.name)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let firstPhoto = photoGroup.first {
                let distance = CoordinateUtilities.shared.distance(
                    from: pin.coordinate,
                    to: CLLocationCoordinate2D(latitude: firstPhoto.gpsLat, longitude: firstPhoto.gpsLon)
                )
                let timeDiff = abs(firstPhoto.timestamp.timeIntervalSince(pin.createdDate))
                
                HStack(spacing: 12) {
                    Text("\(String(format: "%.1fm", distance))")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Text("Δt: \(formatTimeDiff(timeDiff))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Raw timestamps for debugging
            Text("Pin: \(rawTimestamp(pin.createdDate))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private func colorForPin(_ color: String) -> Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
    
    private func formatTimeDiff(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
    
    private func rawTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Photo Viewer Sheet
struct PhotoViewerSheet: View {
    let photoGroup: [Photo]
    @Environment(\.dismiss) var dismiss
    @State private var selectedIndex = 0
    
    var body: some View {
        NavigationView {
            VStack {
                if photoGroup.count > 1 {
                    Picker("Type", selection: $selectedIndex) {
                        ForEach(photoGroup.indices, id: \.self) { index in
                            if let filename = photoGroup[index].metadata["filename"] {
                                if filename.contains("_T.") || filename.contains("_t.") {
                                    Text("Thermal").tag(index)
                                } else {
                                    Text("Visible").tag(index)
                                }
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                
                AsyncImage(url: URL(string: photoGroup[selectedIndex].firebaseStorageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                
                Spacer()
            }
            .navigationTitle("View Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Pin Card
struct PinCard: View {
    let pin: KMLPin
    let classification: DeerClassification
    let isSelected: Bool
    let nearestDistance: Double?
    
    // Add this computed property
    private var nearestPhotoInfo: (distance: Double, timeDiff: Double)? {
        // Calculate from unmatchedPhotos - you'll need to pass viewModel or calculate in parent
        return nil // Parent will handle this
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(colorFor(pin.color))
                    .frame(width: 16, height: 16)
                Text("Pin \(pin.name)")
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            Text(classification.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Show full time with seconds
            Text(pin.createdDate.formatted(date: .omitted, time: .complete))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let dist = nearestDistance {
                Text("Nearest: \(String(format: "%.1fm", dist))")
                    .font(.caption2)
                    .foregroundColor(dist > 30 ? .red : .orange)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.15) : Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
    
    private func colorFor(_ color: String) -> Color {
        switch color {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}




// MARK: - Subviews

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
// MARK: - MatchedPairRow.swift (UPDATED - Shows raw timestamps)
//
//struct MatchedPairRow: View {
//    let photo: Photo
//    let pin: KMLPin
//    let classification: DeerClassification
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            // Photo thumbnail
//            AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.firebaseStorageUrl ?? "")) { image in
//                image
//                    .resizable()
//                    .scaledToFill()
//            } placeholder: {
//                Rectangle()
//                    .fill(Color.gray.opacity(0.2))
//            }
//            .frame(width: 60, height: 60)
//            .clipShape(RoundedRectangle(cornerRadius: 8))
//            
//            VStack(alignment: .leading, spacing: 4) {
//                HStack {
//                    Circle()
//                        .fill(colorForPin(pin.color))
//                        .frame(width: 12, height: 12)
//                    Text(classification.rawValue)
//                        .font(.subheadline)
//                        .fontWeight(.medium)
//                }
//                
//                Text("Pin: \(pin.name)")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                // FORMATTED timestamp
//                Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
//                    .font(.caption2)
//                    .foregroundColor(.secondary)
//            }
//            
//            Spacer()
//            
//            // NEW: Raw date/time debugging info
//            VStack(alignment: .trailing, spacing: 4) {
//                Text("RAW DEBUG:")
//                    .font(.caption2)
//                    .fontWeight(.bold)
//                    .foregroundColor(.orange)
//                
//                Text("Photo: \(rawTimestamp(photo.timestamp))")
//                    .font(.caption2)
//                    .foregroundColor(.orange)
//                
//                Text("Pin: \(rawTimestamp(pin.createdDate))")
//                    .font(.caption2)
//                    .foregroundColor(.orange)
//                
//                Text("Δt: \(Int(abs(photo.timestamp.timeIntervalSince(pin.createdDate))))s")
//                    .font(.caption2)
//                    .foregroundColor(.green)
//            }
//            
//            Image(systemName: "checkmark.circle.fill")
//                .foregroundColor(.green)
//        }
//        .padding()
//        .background(Color.gray.opacity(0.05))
//        .cornerRadius(12)
//        .padding(.horizontal)
//    }
//    
//    private func colorForPin(_ color: String) -> Color {
//        switch color.lowercased() {
//        case "red": return .red
//        case "blue": return .blue
//        case "green": return .green
//        case "yellow": return .yellow
//        case "purple": return .purple
//        default: return .gray
//        }
//    }
//    
//    // NEW: Raw timestamp formatter
//    private func rawTimestamp(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
//        formatter.timeZone = TimeZone.current
//        return formatter.string(from: date)
//    }
//}



struct UnmatchedPhotoRow: View {
    let photo: Photo
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.firebaseStorageUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo (no KML pin)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Default: Buck")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "photo.fill")
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct UnmatchedPinRow: View {
    let pin: KMLPin
    let classification: DeerClassification
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colorForPin(pin.color))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.white)
                    .font(.title2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Pin \(pin.name) (no photo)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(classification.rawValue)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(pin.createdDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func colorForPin(_ color: String) -> Color {
        switch color {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}

// Add this new row type right after UnmatchedPinRow
struct UnmatchedPinDebugRow: View {
    let pin: KMLPin
    let viewModel: ImportViewModel
    
    private var closestPhotoInfo: (photo: Photo, distance: Double, timeDiff: Int)? {
        guard !viewModel.importedPhotos.isEmpty else { return nil }
        
        let results = viewModel.importedPhotos.compactMap { photo -> (Photo, Double, Int)? in
            let dist = viewModel.coordinateDistanceCalculator.distance(
                from: pin.coordinate,
                to: CLLocationCoordinate2D(latitude: photo.gpsLat, longitude: photo.gpsLon)
            )
            let timeDiff = Int(abs(photo.timestamp.timeIntervalSince(pin.createdDate)))
            return (photo, dist, timeDiff)
        }
        
        return results.min(by: { $0.1 < $1.1 })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unmatched Pin")
                        .font(.headline)
                    Text(pin.createdDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            
            if let info = closestPhotoInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Closest photo:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if let filename = info.photo.metadata["filename"] {
                            Text(filename)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(info.photo.timestamp.formatted(.dateTime.hour().minute().second()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 20) {
                        Label("\(String(format: "%.1f", info.distance)) m", systemImage: "ruler")
                        Label("\(info.timeDiff)s Δt", systemImage: "clock")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(.leading, 8)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
