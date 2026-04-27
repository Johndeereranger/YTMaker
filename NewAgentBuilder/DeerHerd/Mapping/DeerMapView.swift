//
//  DeerMapView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//

// MARK: - DeerMapView.swift (Fixed)
import SwiftUI
import MapKit

struct DeerMapView: View {
    @StateObject private var viewModel: MapViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var selectedPin: KMLPin?
    @State private var selectedObservation: DeerObservation?
    //@State private var showObservationDetail = false
    @State private var showFilters = false
    @State private var showPinDetail = false
    
    @State private var cameraPosition: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var visiblePins: [KMLPin] = []
    @State private var visibleObservations: [DeerObservation] = []
    @State private var showAreaComparison = false
    @State private var isStandardMap: Bool = true
    
    // Init for property-based view
    init(property: Property) {
        _viewModel = StateObject(wrappedValue: MapViewModel(property: property))
        
        if let boundary = property.boundaryKML, !boundary.coordinates.isEmpty {
            let center = boundary.coordinates[boundary.coordinates.count / 2]
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }
    
    // Init for session-based view (just imported pins)
    init(sessionId: String) {
        _viewModel = StateObject(wrappedValue: MapViewModel(property: nil, sessionId: sessionId))
        _cameraPosition = State(initialValue: .automatic)
    }
    
    // Init for unassigned pins view
    init() {
        _viewModel = StateObject(wrappedValue: MapViewModel(property: nil))
        _cameraPosition = State(initialValue: .automatic)
    }
    
    var body: some View {
        ZStack {
            mapView
            overlayToolbar
            mapStyleToggle
            
            if viewModel.isEditingBoundary {
                CrosshairOverlay(onAddPoint: {
                    if let center = getCenterCoordinate() {
                        viewModel.addBoundaryVertex(at: center)
                    }
                }, onSave: {
                    Task { await viewModel.saveBoundary() }
                }, onCancel: {
                    viewModel.cancelBoundaryEdit()
                })
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFilters) {
            FilterSheetUnified(viewModel: viewModel)
            //FilterSheetPins(viewModel: viewModel)
        }
        .sheet(item: $selectedPin) { pin in
            PinDetailSheet(pin: pin, viewModel: viewModel)
                .onAppear {
                    print("📄 PIN SHEET PRESENTING")
                    print("   Pin ID: \(pin.id)")
                }
        }
        .sheet(isPresented: $showAreaComparison) {
            AreaComparisonView(viewModel: viewModel)
        }
        .sheet(item: $selectedObservation) { observation in
            ObservationDetailView(
                observation: observation,
                viewModel: viewModel,
                onDismiss: { selectedObservation = nil }
            )
            .onAppear {
                print("📄 OBSERVATION SHEET PRESENTING")
                print("   Obs ID: \(observation.id)")
            }
        }
        .task {
            await viewModel.loadData()
            updateVisiblePins()
        }
        .onChange(of: viewModel.pinFilter) { _, _ in
            Task {
                await viewModel.loadData()
                viewModel.calculateAllSurveyedAreas()
            }
        }
        .onChange(of: viewModel.dateFilter) { _, _ in
            viewModel.calculateStats()
            viewModel.calculateAllSurveyedAreas()
        }
        .onChange(of: viewModel.classificationFilter) { _, _ in
            viewModel.calculateStats()
            viewModel.calculateAllSurveyedAreas()
        }
        .onChange(of: viewModel.selectedBuckProfile) { _, _ in
            viewModel.calculateStats()
        }
        .onChange(of: viewModel.filteredPins) { _, _ in
            updateVisiblePins()
        }
    }
    
    private var navigationTitle: String {
        if let property = viewModel.property {
            return property.name
        }
        
        switch viewModel.pinFilter {
        case .session:
            return "Imported Pins"
        case .unassigned:
            return "Unassigned Pins"
        case .property:
            return "Property Pins"
        case .all:
            return "All Pins"
        }
    }
    
    func getCenterCoordinate() -> CLLocationCoordinate2D? {
        return nil // Implement based on camera tracking if needed
    }
    
    // MARK: - Subviews
    
    private var mapView: some View {
//        Map(position: $cameraPosition) {
//            boundaryContent
//            pinsContent
//            observationsContent
//        }
//        .mapStyle(.standard)
        
        Map(position: $cameraPosition) {
             boundaryContent
            if viewModel.showSurveyBoundary, let area = viewModel.currentSurveyedArea {
                    SurveyBoundaryOverlay(area: area)
                }
             pinsContent
             observationsContent
         }
         .mapStyle(isStandardMap ? .standard : .imagery)
         .onMapCameraChange { context in
             // Track visible region
             visibleRegion = context.region
             updateVisiblePins()
         }
    }
    
    private func updateVisiblePins() {
        guard let region = visibleRegion else {
            visiblePins = []
            return
        }
        
        let center = region.center
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta
        
        let minLat = center.latitude - latDelta / 2
        let maxLat = center.latitude + latDelta / 2
        let minLon = center.longitude - lonDelta / 2
        let maxLon = center.longitude + lonDelta / 2
        
        visiblePins = viewModel.filteredPins.filter { pin in
            pin.coordinate.latitude >= minLat &&
            pin.coordinate.latitude <= maxLat &&
            pin.coordinate.longitude >= minLon &&
            pin.coordinate.longitude <= maxLon
        }
        visibleObservations = viewModel.filteredObservations.filter { obs in
            obs.gpsLat >= minLat &&
            obs.gpsLat <= maxLat &&
            obs.gpsLon >= minLon &&
            obs.gpsLon <= maxLon
        }
    }
    
    @MapContentBuilder
    private var boundaryContent: some MapContent {
        if viewModel.showBoundary,
           let property = viewModel.property,
           let boundary = property.boundaryKML {
            MapPolygon(coordinates: boundary.coordinates)
                .foregroundStyle(Color.blue.opacity(0.2))
                .stroke(Color.blue, lineWidth: 2)
        }
    }
    
    private var mapStyleToggle: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        isStandardMap.toggle()  // Simple toggle
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: isStandardMap ? "map" : "globe.americas.fill")
                            .font(.title3)
                        Text(isStandardMap ? "Satellite" : "Map")  // Show what it will switch TO
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                }
                .padding(.trailing, 16)
                .padding(.bottom, viewModel.property != nil ? 200 : 100)
            }
        }
    }
    
    @MapContentBuilder
    private var pinsContent: some MapContent {
        ForEach(viewModel.filteredPins) { pin in
            Annotation(pin.name, coordinate: pin.coordinate) {
                PinAnnotationView(pin: pin)
                    .onTapGesture {
                        print("🔵 PIN TAPPED")
                        print("   Pin ID: \(pin.id)")
                        print("   Pin name: \(pin.name)")
                        selectedPin = pin
                        print("   selectedPin set: \(selectedPin?.id ?? "nil")")
                        //showPinDetail = true
                        print("   showPinDetail = true")

                    }
            }
        }
    }
    
    @MapContentBuilder
    private var observationsContent: some MapContent {
        ForEach(viewModel.filteredObservations) { observation in
            if viewModel.displayMode == .photoThumbnails {
                photoAnnotation(for: observation)
            } else {
                pinAnnotation(for: observation)
            }
        }
    }
    
    @MapContentBuilder
    private func photoAnnotation(for observation: DeerObservation) -> some MapContent {
        if let photo = observation.primaryPhoto {
            Annotation("", coordinate: observation.coordinate) {
                PhotoAnnotationView(
                    photo: photo,
                    isHighlighted: viewModel.selectedBuckProfile != nil
                )
                .onTapGesture {
                    print("🟢 OBSERVATION TAPPED")
                    print("   Obs ID: \(observation.id)")
                    print("   Obs classification: \(observation.classification)")
                    selectedObservation = observation
                    print("   selectedObservation set: \(selectedObservation?.id ?? "nil")")
                    //showObservationDetail = true
                    print("   showObservationDetail = true")
                }
            }
        }
    }
    
//    @MapContentBuilder
//    private func pinAnnotation(for observation: DeerObservation) -> some MapContent {
//        Annotation("", coordinate: observation.coordinate) {
//            ColoredPinView(
//                color: observation.color,
//                classification: observation.classification,
//                isHighlighted: observation.buckProfileId == viewModel.selectedBuckProfile?.id
//            )
//            .onTapGesture {
//                selectedObservation = observation
//                showObservationDetail = true
//            }
//        }
//    }
    
    @MapContentBuilder
    private func pinAnnotation(for observation: DeerObservation) -> some MapContent {
        Annotation("", coordinate: observation.coordinate) {
            ColoredPinView(
                color: observation.color,
                classification: observation.classification,
                isHighlighted: observation.buckProfileId == viewModel.selectedBuckProfile?.id, isIncluded: observation.isIncludedInCalculations,
                onTap: {  // PASS THE HANDLER
                    print("🟢 OBSERVATION (PIN) TAPPED")
                    print("   Obs ID: \(observation.id)")
                    selectedObservation = observation
                    //showObservationDetail = true
                }
            )
        }
    }
    
    
    private var overlayToolbar: some View {
        VStack(spacing: 0) {
            topToolbar
            
            // Active filter badges
            ActiveFilterBadges(viewModel: viewModel)
                .padding(.top, 8)
            
            Spacer()
            
            // Bottom panels
            VStack(spacing: 12) {
                // NEW: Combined visible content panel
                HStack {
                    VisibleContentPanel(
                        visiblePins: visiblePins,
                        visibleObservations: visibleObservations,
                        totalPins: viewModel.filteredPins.count,
                        totalObservations: viewModel.filteredObservations.count
                    )
                    Spacer()
                }
                
                HStack {
                     AreaCalculationPanel(viewModel: viewModel)
                     Spacer()
                 }
             
                
                // Existing stats panel (property view only)
                if viewModel.property != nil {
                    HStack {
                        StatsPanel(viewModel: viewModel)
                        Spacer()
                    }
                }
            }
            .padding()
        }
    }

    
    private var topToolbar: some View {
        HStack {
            filterButton
            Spacer()
            
            if viewModel.property != nil && !viewModel.isEditingBoundary {
                Button(action: { viewModel.startEditingBoundary() }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                Spacer()
            }
            
            if viewModel.property != nil {
                displayModePicker
            }
        }
        .padding()
    }
    
    private var filterButton: some View {
        Button(action: { showFilters.toggle() }) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .padding(8)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }
    
    private var displayModePicker: some View {
        Picker("Display", selection: $viewModel.displayMode) {
            Label("Photos", systemImage: "photo")
                .tag(MapViewModel.DisplayMode.photoThumbnails)
            Label("Pins", systemImage: "mappin.circle.fill")
                .tag(MapViewModel.DisplayMode.coloredPins)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    @ViewBuilder
    private var observationDetailSheet: some View {
        if let observation = selectedObservation {
            ObservationDetailView(
                observation: observation,
                viewModel: viewModel,
                onDismiss: { selectedObservation = nil  }
            )
        }
    }
}

// MARK: - PinAnnotationView
struct PinAnnotationView: View {
    let pin: KMLPin
    
    var body: some View {
        ZStack {
            Circle()
                .fill(lightColorForPin)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .shadow(radius: 4)
                .opacity(pin.isIncludedInCalculations ? 1.0 : 0.4)
            
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.gray)
                .font(.system(size: 12))
            
            if !pin.isIncludedInCalculations {
                           Image(systemName: "xmark")
                               .font(.system(size: 16, weight: .bold))
                               .foregroundColor(.red)
                       }
        }
    }
    
    private var colorForPin: Color {
        switch pin.color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
    private var lightColorForPin: Color {
            switch pin.color.lowercased() {
            case "red": return Color(red: 1.0, green: 0.6, blue: 0.6)      // Light red
            case "blue": return Color(red: 0.6, green: 0.8, blue: 1.0)     // Light blue
            case "green": return Color(red: 0.6, green: 1.0, blue: 0.6)    // Light green
            case "yellow": return Color(red: 1.0, green: 1.0, blue: 0.6)   // Light yellow
            case "purple": return Color(red: 0.8, green: 0.6, blue: 1.0)   // Light purple
            default: return Color(red: 0.8, green: 0.8, blue: 0.8)         // Light gray
            }
        }
}

// MARK: - PinStatsPanel
struct PinStatsPanel: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pins: \(viewModel.filteredPins.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(viewModel.pinFilter.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Color Breakdown")
                        .font(.caption)
                        .fontWeight(.semibold)
                    HStack(spacing: 4) {
                        ForEach(uniqueColors, id: \.self) { color in
                            Circle()
                                .fill(colorForString(color))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private var uniqueColors: [String] {
        Array(Set(viewModel.filteredPins.map { $0.color })).sorted()
    }
    
    private func colorForString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}

// MARK: - PinDetailSheet
struct PinDetailSheet: View {
    let pin: KMLPin
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showPropertyPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    DetailRow(label: "Name", value: pin.name)
                    DetailRow(label: "Color", value: pin.color.capitalized)
                    DetailRow(label: "Date", value: pin.createdDate.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(label: "Location", value: String(format: "%.5f, %.5f", pin.coordinate.latitude, pin.coordinate.longitude))
                    
                    if let email = pin.creatorEmail {
                        DetailRow(label: "Created By", value: email)
                    }
                }
                
                Section("Status") {
                    if let propertyId = pin.propertyId {
                        DetailRow(label: "Property", value: propertyId)
                    } else {
                        HStack {
                            Text("Property")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Unassigned")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if let sessionId = pin.sessionId {
                        DetailRow(label: "Session", value: sessionId)
                    }
                }
                
                Section("Actions") {
                    if pin.propertyId == nil {
                        Button(action: { showPropertyPicker = true }) {
                            Label("Assign to Property", systemImage: "map")
                        }
                    }
                    
                    Button(role: .destructive, action: {
                        Task {
                            await viewModel.deletePin(pin)
                            dismiss()
                        }
                    }) {
                        Label("Delete Pin", systemImage: "trash")
                    }
                }
                
                Section {
                    Toggle(isOn: Binding(
                        get: { pin.isIncludedInCalculations },
                        set: { _ in
                            Task {
                                await viewModel.togglePinCalculationStatus(pin)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Include in Survey Calculations")
                                .font(.body)
                            Text("When off, this pin won't count toward density or area calculations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Survey Analysis")
                } footer: {
                    if !pin.isIncludedInCalculations {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This pin is excluded from calculations")
                                .font(.caption)
                        }
                    }
                }
                
                
            }
            .navigationTitle("Pin Details")
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

// MARK: - FilterSheetPins
//struct FilterSheetPinsOld: View {
//    @ObservedObject var viewModel: MapViewModel
//    @Environment(\.dismiss) var dismiss
//    
//    var body: some View {
//        NavigationView {
//            Form {
//                Section("Pin Filter") {
//                    if case .session(let sessionId) = viewModel.pinFilter {
//                        HStack {
//                            Text("Current Filter")
//                            Spacer()
//                            Text("Just Imported")
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                    
//                    Button("Show All Unassigned") {
//                        viewModel.pinFilter = .unassigned
//                        dismiss()
//                    }
//                }
//                
//                Section("Display") {
//                    Toggle("Show Boundary", isOn: $viewModel.showBoundary)
//                }
//                
//                Section("Date Range") {
//                    Picker("Time Period", selection: $viewModel.dateFilter) {
//                        ForEach(MapViewModel.DateFilter.allCases.filter { $0 != .custom && $0 != .sessions }, id: \.self) { filter in
//                            Text(filter.displayName).tag(filter)
//                        }
//                    }
//                }
//            }
//            .navigationTitle("Filters")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}
// MARK: - New FilterSheetPins with Clear UI

struct FilterSheetPins: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // SECTION 1: Pin Source
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pin Source")
                            .font(.headline)
                        
                        // Current filter display
                        HStack {
                            Image(systemName: filterIcon)
                                .foregroundColor(.blue)
                            Text(filterDescription)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Quick switch buttons
                        HStack(spacing: 12) {
                            FilterButton(
                                title: "Unassigned",
                                isActive: isUnassignedFilter,
                                action: {
                                    viewModel.pinFilter = .unassigned
                                    Task { await viewModel.loadData() }
                                }
                            )
                            
                            FilterButton(
                                title: "All Pins",
                                isActive: isAllFilter,
                                action: {
                                    viewModel.pinFilter = .all
                                    Task { await viewModel.loadData() }
                                }
                            )
                        }
                    }
                }
                
                // SECTION 2: Color Filter
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Filter by Color")
                                .font(.headline)
                            Spacer()
                            if !viewModel.selectedColors.isEmpty {
                                Button("Clear") {
                                    viewModel.selectedColors.removeAll()
                                }
                                .font(.caption)
                            }
                        }
                        
                        if viewModel.availableColors.isEmpty {
                            Text("No colors available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(viewModel.availableColors, id: \.self) { color in
                                    ColorChip(
                                        color: color,
                                        isSelected: viewModel.selectedColors.contains(color),
                                        action: {
                                            if viewModel.selectedColors.contains(color) {
                                                viewModel.selectedColors.remove(color)
                                            } else {
                                                viewModel.selectedColors.insert(color)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                
                // SECTION 3: Match Status
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Match Status")
                            .font(.headline)
                        
                        Picker("", selection: $viewModel.matchStatusFilter) {
                            ForEach(MapViewModel.MatchStatusFilter.allCases, id: \.self) { status in
                                HStack {
                                    Image(systemName: matchStatusIcon(status))
                                    Text(status.rawValue)
                                }
                                .tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                // SECTION 4: Date Range
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Date Range")
                            .font(.headline)
                        
                        Picker("", selection: $viewModel.dateFilter) {
                            ForEach(MapViewModel.DateFilter.allCases.filter { $0 != .custom && $0 != .sessions }, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // SECTION 5: Results Summary
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.blue)
                            Text("Showing \(viewModel.filteredPins.count) of \(viewModel.kmlPins.count) pins")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        if viewModel.activeFilterCount > 0 {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.orange)
                                Text("\(viewModel.activeFilterCount) active filter(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.activeFilterCount > 0 {
                        Button("Reset All") {
                            viewModel.resetFilters()
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var filterIcon: String {
        switch viewModel.pinFilter {
        case .session: return "clock.badge.checkmark"
        case .unassigned: return "square.dashed"
        case .property: return "map"
        case .all: return "mappin.circle"
        }
    }
    
    private var filterDescription: String {
        switch viewModel.pinFilter {
        case .session:
            return "Just Imported"
        case .unassigned:
            return "Unassigned Pins"
        case .property(let id):
            return "Property: \(id.prefix(8))..."
        case .all:
            return "All Pins"
        }
    }
    
    private var isUnassignedFilter: Bool {
        if case .unassigned = viewModel.pinFilter { return true }
        return false
    }
    
    private var isAllFilter: Bool {
        if case .all = viewModel.pinFilter { return true }
        return false
    }
    
    private func matchStatusIcon(_ status: MapViewModel.MatchStatusFilter) -> String {
        switch status {
        case .all: return "circle"
        case .matched: return "photo"
        case .unmatched: return "photo.badge.exclamationmark"
        }
    }
}

// MARK: - Supporting Views

struct FilterButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(8)
        }
    }
}

struct ColorChip: View {
    let color: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorForString(color))
                    .frame(width: 16, height: 16)
                
                Text(color.capitalized)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func colorForString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        default: return .gray
        }
    }
}

// MARK: - FlowLayout (for wrapping color chips)

// MARK: - PhotoAnnotationView.swift
import SwiftUI

struct PhotoAnnotationView: View {
    let photo: Photo
    let isHighlighted: Bool
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHighlighted ? Color.yellow : Color.white, lineWidth: 2)
                    )
                    .shadow(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let urlString = photo.thumbnailUrl ?? photo.firebaseStorageUrl,
              let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    thumbnailImage = image
                }
            }
        } catch {
            print("❌ Failed to load thumbnail: \(error)")
        }
    }
}

// MARK: - ColoredPinView.swift
import SwiftUI
struct ColoredPinView: View {
    let color: String  // "red", "blue", "green", etc.
    let classification: DeerClassification
    let isHighlighted: Bool
    let isIncluded: Bool
    let onTap: () -> Void
    
    var body: some View {
            ZStack {
                Circle()
                    .fill(pinColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(isHighlighted ? Color.yellow : Color.white, lineWidth: isHighlighted ? 3 : 2)
                    )
                    .shadow(radius: 4)
                    .opacity(isIncluded ? (isHighlighted ? 1.0 : 0.7) : 0.3)
                
                Image(systemName: iconForClassification)
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                
                if !isIncluded {
                             Image(systemName: "xmark")
                                 .font(.system(size: 16, weight: .bold))
                                 .foregroundColor(.red)
                         }
            }
            .opacity(isHighlighted ? 1.0 : 0.7)
            .onTapGesture {  // MOVE IT HERE
                print("🔵 COLORED PIN TAPPED")
                onTap()
            }
        }
    
    private var pinColor: Color {
        switch color.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        case "black": return .black
        default: return .gray
        }
    }
    
    private var iconForClassification: String {
        switch classification {
        case .buck, .matureBuck, .beddedBuck, .matureBeddedBuck:
            return "flag.fill"
        case .doe, .beddedDoe:
            return "circle.fill"
        case .coyote, .fox:
            return "pawprint.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}
//struct ColoredPinViewOld: View {
//    let classification: DeerClassification
//    let isHighlighted: Bool
//    
//    var body: some View {
//        ZStack {
//            Circle()
//                .fill(colorForClassification)
//                .frame(width: 30, height: 30)
//                .overlay(
//                    Circle()
//                        .stroke(isHighlighted ? Color.yellow : Color.white, lineWidth: isHighlighted ? 3 : 2)
//                )
//                .shadow(radius: 4)
//            
//            Image(systemName: classification.isBuck ? "flag.fill" : "circle.fill")
//                .foregroundColor(.white)
//                .font(.system(size: 12))
//        }
//        .opacity(isHighlighted ? 1.0 : 0.7)
//    }
//    
//    private var colorForClassification: Color {
//        switch classification {
//        case .buck, .matureBuck:
//            return .red
//        case .doe:
//            return .blue
//        case .beddedBuck, .matureBeddedBuck:
//            return .orange
//        case .beddedDoe:
//            return .green
//        }
//    }
//}

// MARK: - StatsPanel.swift
import SwiftUI

struct StatsPanel: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Observations: \(viewModel.visibleObservationCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Deer/sq mi: \(String(format: "%.1f", viewModel.deerPerSquareMile))")
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Buck:Doe")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(viewModel.buckToDoRatio)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}

// MARK: - FilterSheet.swift
import SwiftUI

struct FilterSheetDeer: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    var body: some View {
        NavigationView {
            Form {
                // Display options
                Section("Display") {
                    Toggle("Show Boundary", isOn: $viewModel.showBoundary)
                }
                
                // Date filters
                Section("Date Range") {
                    Picker("Time Period", selection: $viewModel.dateFilter) {
                        ForEach(MapViewModel.DateFilter.allCases.filter { $0 != .custom && $0 != .sessions }, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    
                    Button("Custom Date Range") {
                        showCustomDatePicker = true
                    }
                    
                    if viewModel.sessions.count <= 10 && viewModel.sessions.count > 0 {
                        Button("Select Sessions") {
                            viewModel.dateFilter = .sessions
                        }
                    }
                }
                
                // Session selector (if applicable)
                if viewModel.dateFilter == .sessions {
                    Section("Select Sessions") {
                        ForEach(viewModel.sessions) { session in
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedSessionIds.contains(session.id) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.selectedSessionIds.insert(session.id)
                                    } else {
                                        viewModel.selectedSessionIds.remove(session.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(session.date, style: .date)
                                        .font(.headline)
                                    Text(session.timeOfDay.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Time of day
                Section("Time of Day") {
                    Picker("Time", selection: $viewModel.timeOfDayFilter) {
                        ForEach(MapViewModel.TimeOfDayFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Classification
                Section("Deer Type") {
                    Picker("Classification", selection: $viewModel.classificationFilter) {
                        ForEach(MapViewModel.ClassificationFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Buck profile filter
                if !viewModel.buckProfiles.isEmpty {
                    Section("Buck Profile") {
                        Picker("Select Buck", selection: $viewModel.selectedBuckProfile) {
                            Text("All Bucks").tag(nil as BuckProfile?)
                            ForEach(viewModel.buckProfiles) { profile in
                                Text(profile.name).tag(profile as BuckProfile?)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        viewModel.dateFilter = .allTime
                        viewModel.timeOfDayFilter = .all
                        viewModel.classificationFilter = .all
                        viewModel.selectedBuckProfile = nil
                        viewModel.selectedSessionIds.removeAll()
                        viewModel.showBoundary = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomDatePicker) {
            CustomDateRangePicker(
                startDate: $customStartDate,
                endDate: $customEndDate,
                onApply: {
                    viewModel.customDateRange = MapViewModel.DateRange(start: customStartDate, end: customEndDate)
                    viewModel.dateFilter = .custom
                    showCustomDatePicker = false
                }
            )
        }
    }
}

// MARK: - CustomDateRangePicker.swift
import SwiftUI

struct CustomDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}



struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

// MARK: - AsyncImageView.swift
import SwiftUI

struct AsyncImageView: View {
    let url: String?
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let urlString = url, let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let loadedImage = UIImage(data: data) {
                await MainActor.run {
                    image = loadedImage
                    isLoading = false
                }
            }
        } catch {
            print("❌ Failed to load image: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - LinkToBuckProfileSheet.swift
import SwiftUI

struct LinkToBuckProfileSheet: View {
    let observation: DeerObservation
    let buckProfiles: [BuckProfile]
    let onLink: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(buckProfiles) { profile in
                    Button(action: {
                        onLink(profile.id)
                        dismiss()
                    }) {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.headline)
                            if let age = profile.ageEstimate {
                                Text("Age: \(age)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Buck Profile")
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

// MARK: - EditClassificationSheet.swift
import SwiftUI

struct EditClassificationSheet: View {
    let currentClassification: DeerClassification
    let onSave: (DeerClassification) -> Void
    @State private var selectedClassification: DeerClassification
    @Environment(\.dismiss) var dismiss
    
    init(currentClassification: DeerClassification, onSave: @escaping (DeerClassification) -> Void) {
        self.currentClassification = currentClassification
        self.onSave = onSave
        _selectedClassification = State(initialValue: currentClassification)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Classification", selection: $selectedClassification) {
                    ForEach(DeerClassification.allCases, id: \.self) { classification in
                        Text(classification.rawValue).tag(classification)
                    }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("Edit Classification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedClassification)
                        dismiss()
                    }
                }
            }
        }
    }
}


// MARK: - Active Filter Display (Add to DeerMapView)

// Add this view above the map to show active filters
struct ActiveFilterBadges: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        if viewModel.activeFilterCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Color filters
                    if !viewModel.selectedColors.isEmpty {
                        FilterBadge(
                            icon: "paintpalette",
                            text: "\(viewModel.selectedColors.count) color(s)",
                            color: .blue,
                            onRemove: {
                                viewModel.selectedColors.removeAll()
                            }
                        )
                    }
                    
                    // Match status
                    if viewModel.matchStatusFilter != .all {
                        FilterBadge(
                            icon: "photo",
                            text: viewModel.matchStatusFilter.rawValue,
                            color: .orange,
                            onRemove: {
                                viewModel.matchStatusFilter = .all
                            }
                        )
                    }
                    
                    // Date filter
                    if viewModel.dateFilter != .allTime {
                        FilterBadge(
                            icon: "calendar",
                            text: viewModel.dateFilter.displayName,
                            color: .green,
                            onRemove: {
                                viewModel.dateFilter = .allTime
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 40)
        }
    }
}

struct FilterBadge: View {
    let icon: String
    let text: String
    let color: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(16)
    }
}

// MARK: - Update DeerMapView to include badges

// Replace the overlayToolbar in DeerMapView with:
// MARK: - VisiblePinsPanel.swift (NEW)
import SwiftUI
import MapKit

struct VisiblePinsPanel: View {
    let visiblePins: [KMLPin]
    let totalPins: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Total count
            Text("Visible Pins: \(visiblePins.count) of \(totalPins)")
                .font(.caption)
                .fontWeight(.semibold)
            
            // Color breakdown (only colors that are visible)
            if !visiblePins.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(colorBreakdown, id: \.color) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.swiftUIColor)
                                .frame(width: 12, height: 12)
                            
                            Text("\(item.color.capitalized): \(item.count)")
                                .font(.caption2)
                        }
                    }
                }
            } else {
                Text("No pins in view")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    // MARK: - Color Breakdown
    
    private var colorBreakdown: [ColorCount] {
        var counts: [String: Int] = [:]
        
        for pin in visiblePins {
            counts[pin.color, default: 0] += 1
        }
        
        // Sort by count descending, then alphabetically
        return counts.map { ColorCount(color: $0.key, count: $0.value) }
            .sorted { first, second in
                if first.count != second.count {
                    return first.count > second.count
                }
                return first.color < second.color
            }
    }
    
    struct ColorCount {
        let color: String
        let count: Int
        
        var swiftUIColor: Color {
            switch color.lowercased() {
            case "red": return .red
            case "blue": return .blue
            case "green": return .green
            case "yellow": return .yellow
            case "purple": return .purple
            default: return .gray
            }
        }
    }
}


struct VisibleContentPanel: View {
    let visiblePins: [KMLPin]
    let visibleObservations: [DeerObservation]
    let totalPins: Int
    let totalObservations: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Total counts
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle")
                        .font(.caption)
                    Text("\(visiblePins.count)/\(totalPins) pins")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.caption)
                    Text("\(visibleObservations.count)/\(totalObservations) obs")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            
            // Color breakdown for visible pins
            if !visiblePins.isEmpty {
                Text("Pin Colors:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 4) {
                    ForEach(pinColorBreakdown, id: \.color) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.swiftUIColor)
                                .frame(width: 10, height: 10)
                            Text("\(item.color): \(item.count)")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Classification breakdown for visible observations
            if !visibleObservations.isEmpty {
                Text("Deer:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 4) {
                    ForEach(deerClassificationBreakdown, id: \.name) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.caption2)
                            Text("\(item.name): \(item.count)")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            if visiblePins.isEmpty && visibleObservations.isEmpty {
                Text("Nothing visible in current view")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Pin Color Breakdown
    
    private var pinColorBreakdown: [ColorCount] {
        var counts: [String: Int] = [:]
        for pin in visiblePins {
            counts[pin.color, default: 0] += 1
        }
        return counts.map { ColorCount(color: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    struct ColorCount {
        let color: String
        let count: Int
        
        var swiftUIColor: Color {
            switch color.lowercased() {
            case "red": return .red
            case "blue": return .blue
            case "green": return .green
            case "yellow": return .yellow
            case "purple": return .purple
            default: return .gray
            }
        }
    }
    
    // MARK: - Deer Classification Breakdown
    
    private var deerClassificationBreakdown: [ClassificationCount] {
        var counts: [String: Int] = [:]
        for obs in visibleObservations {
            let category = obs.classification.category
            counts[category, default: 0] += 1
        }
        return counts.map { ClassificationCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    struct ClassificationCount {
        let name: String
        let count: Int
        
        var icon: String {
            switch name.lowercased() {
            case "buck": return "flag.fill"
            case "doe": return "circle.fill"
            case "bedded": return "bed.double.fill"
            case "unknown": return "questionmark.circle"
            default: return "circle"
            }
        }
    }
}


extension DeerClassification {
    var category: String {
        switch self {
        case .buck, .matureBuck: return "Buck"
        case .beddedBuck, .matureBeddedBuck: return "Bedded Buck"
        case .doe: return "Doe"
        case .beddedDoe: return "Bedded Doe"
        case .coyote: return "Coyote"
        case .fox: return "Fox"
        case .unknown: return "Unknown"
        }
    }
}
