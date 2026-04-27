//
//  DeerReportView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//


// MARK: - DeerReportView.swift
import SwiftUI
import PDFKit

struct DeerReportView: View {
    @StateObject private var viewModel: ReportViewModel
    @State private var showDateRangePicker = false
    @State private var useCustomRange = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    
    init(property: Property) {
        _viewModel = StateObject(wrappedValue: ReportViewModel(property: property))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if let url = pdfURL {
                // Show PDF preview
                PDFKitView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Button(action: { showShareSheet = true }) {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding()
            } else {
                // Configuration screen
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Generate Report")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(viewModel.property.name)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Use Custom Date Range", isOn: $useCustomRange)
                        
                        if useCustomRange {
                            VStack(spacing: 12) {
                                DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                                DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    if viewModel.isGenerating {
                        VStack {
                            ProgressView()
                            Text("Generating report...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            Task {
                                if useCustomRange {
                                    viewModel.dateRange = MapViewModel.DateRange(
                                        start: customStartDate,
                                        end: customEndDate
                                    )
                                } else {
                                    viewModel.dateRange = nil
                                }
                                
                                if let url = await viewModel.generateReport() {
                                    pdfURL = url
                                }
                            }
                        }) {
                            Label("Generate Report", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
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

// MARK: - PDFKitView.swift
import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        // No update needed
    }
}

// MARK: - ShareSheet.swift
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - DeerSettingsView.swift
import SwiftUI

struct DeerSettingsView: View {
    @StateObject private var viewModel = DeerSettingsViewModel()
    @State private var showResetConfirmation = false
    
    var body: some View {
        Form {
            Section("Default Color Mappings") {
                Text("These defaults will be suggested when importing KML files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(["red", "blue", "yellow", "green", "purple"], id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(colorForName(color))
                            .frame(width: 24, height: 24)
                        
                        Text(color.capitalized)
                        
                        Spacer()
                        
                        Picker("", selection: Binding(
                            get: { viewModel.defaultColorMappings[color] ?? .buck },
                            set: { viewModel.updateColorMapping(color, to: $0) }
                        )) {
                            ForEach(DeerClassification.allCases, id: \.self) { classification in
                                Text(classification.rawValue).tag(classification)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            
            Section("Auto-Matching") {
                VStack(alignment: .leading) {
                    Text("Distance Threshold: \(Int(viewModel.autoMatchDistance)) feet")
                        .font(.headline)
                    
                    Text("Photos within this distance of a KML pin will be automatically matched")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $viewModel.autoMatchDistance, in: 5...50, step: 5)
                }
            }
            
            Section("Actions") {
                Button("Save Settings") {
                    viewModel.saveSettings()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Reset to Defaults", role: .destructive) {
                    showResetConfirmation = true
                }
            }
            
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Units", value: "Standard (acres, miles)")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset Settings?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                // Reset to defaults
                viewModel.defaultColorMappings = [
                    "red": .buck,
                    "blue": .doe,
                    "yellow": .beddedBuck,
                    "green": .beddedDoe,
                    "purple": .matureBuck
                ]
                viewModel.autoMatchDistance = 10.0
                viewModel.saveSettings()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func colorForName(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "yellow": return .yellow
        case "green": return .green
        case "purple": return .purple
        default: return .gray
        }
    }
}