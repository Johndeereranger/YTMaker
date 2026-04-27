//
//  ExportButtonView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//
//import Foundation
//import SwiftUI
//
//struct ExportButtonView: View {
//    @ObservedObject var viewModel: HarvestAnalysisViewModel
//    @State private var showShareSheet = false
//    @State private var exportURL: URL?
//    @State private var showAlert = false
//    @State private var alertMessage = ""
//    
//    var body: some View {
//        Button("Export CSV") {
//            exportCSV()
//        }
//        .sheet(isPresented: $showShareSheet) {
//            if let url = exportURL {
//                 ShareSheet(activityItems: [url])
//             }
//        }
//        .alert("Export Status", isPresented: $showAlert) { Button("OK") {} } message: { Text(alertMessage) }
//    }
//    
//    private func exportCSV() {
//        if viewModel.allYearData.isEmpty { viewModel.loadAllYears() }
//        guard !viewModel.allYearData.isEmpty else {
//            alertMessage = "No data to export"; showAlert = true; return
//        }
//        
//        let exporter = CSVExporter(harvestViewModel: viewModel)
//        if let url = exporter.exportCSVToFile() {
//            exportURL = url
//            showShareSheet = true
//        } else {
//            alertMessage = "Failed to export"; showAlert = true
//        }
//    }
//}
//
////
////#if os(macOS)
////import Foundation
////#endif
////
////import SwiftUI
////
////struct ExportButtonView: View {
////    @ObservedObject var viewModel: HarvestAnalysisViewModel
////    @State private var showAlert = false
////    @State private var alertMessage = ""
////    
////    var body: some View {
////        Button("Export CSV") {
////            exportCSV()
////        }
////        .alert("Export Status", isPresented: $showAlert) {
////            Button("OK", role: .cancel) { }
////        } message: {
////            Text(alertMessage)
////        }
////    }
////
////    private func exportCSV() {
////        if viewModel.allYearData.isEmpty { viewModel.loadAllYears() }
////        guard !viewModel.allYearData.isEmpty else {
////            alertMessage = "No data to export"
////            showAlert = true
////            return
////        }
////
////        let exporter = CSVExporter(harvestViewModel: viewModel)
////        if let url = exporter.exportCSVToFile() {
////            launchFinderOrApp(for: url)
////            alertMessage = "Exported to: \(url.lastPathComponent)"
////        } else {
////            alertMessage = "Failed to export CSV"
////        }
////        showAlert = true
////    }
////
////#if os(macOS)
////private func launchFinderOrApp(for fileURL: URL) {
////    let task = Process()
////    task.launchPath = "/usr/bin/open"
////    task.arguments = [fileURL.path]
////    task.launch()
////}
////#else
////private func launchFinderOrApp(for fileURL: URL) {
////    // iOS fallback if needed
////}
////#endif
////}
//
//
//import UIKit
//import SwiftUI
//
//struct ShareSheet: UIViewControllerRepresentable {
//    let activityItems: [Any]
//    
//    func makeUIViewController(context: Context) -> UIActivityViewController {
//        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
//    }
//
//    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
//}

import SwiftUI

struct ExportButtonView2: View {
    @ObservedObject var viewModel: HarvestAnalysisViewModel
    @State private var showAlert = false
    @State private var message = ""
    
    var body: some View {
        Button("Export CSV") {
            if viewModel.allYearData.isEmpty {
                viewModel.loadAllYears()
            }
            
            let exporter = CSVExporter(harvestViewModel: viewModel)
            if let csv = exporter.generateCSV() {
                UIPasteboard.general.string = csv
                message = "✅ CSV copied! Open TextEdit, paste (Cmd+V), and save as .csv"
                showAlert = true
            } else {
                message = "❌ No data to export"
                showAlert = true
            }
        }
        .alert("Export", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(message)
        }
    }
}


import UniformTypeIdentifiers

struct ExportButtonView: View {
    @ObservedObject var viewModel: HarvestAnalysisViewModel
    @State private var showSaveDialog = false
    @State private var csvText = ""
    
    var body: some View {
        Button("Save CSV...") {
            if viewModel.allYearData.isEmpty {
                viewModel.loadAllYears()
            }
            
            let exporter = CSVExporter(harvestViewModel: viewModel)
            if let csv = exporter.generateCSV() {
                csvText = csv
                showSaveDialog = true
            }
        }
        .fileExporter(
            isPresented: $showSaveDialog,
            document: CSVFile(content: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: "harvest_\(Date().timeIntervalSince1970).csv"
        ) { result in
            if case .success(let url) = result {
                print("✅ Saved to: \(url.path)")
            }
        }
    }
}

struct CSVFile: FileDocument {
    static var readableContentTypes = [UTType.commaSeparatedText]
    var content: String
    
    init(content: String = "") {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(decoding: data, as: UTF8.self)
        } else {
            content = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8)!)
    }
}
