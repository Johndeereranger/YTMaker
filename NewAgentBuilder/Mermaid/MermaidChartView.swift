//
//  MermaidChartView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/28/25.
////
//import SwiftUI
//import UIKit
//import WebKit
//
//struct MermaidChartView: UIViewRepresentable {
//    let mermaidCode: String
//
//    func makeUIView(context: Context) -> WKWebView {
//        let webView = WKWebView()
//        webView.loadHTMLString(htmlWrapper(for: mermaidCode), baseURL: nil)
//        return webView
//    }
//
//    func updateUIView(_ uiView: WKWebView, context: Context) {
//        uiView.loadHTMLString(htmlWrapper(for: mermaidCode), baseURL: nil)
//    }
//
//    private func htmlWrapper(for code: String) -> String {
//        """
//        <!DOCTYPE html>
//        <html>
//        <head>
//            <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
//            <meta name="viewport" content="width=device-width, initial-scale=1.0">
//            <style>
//                body { margin: 0; padding: 1rem; font-family: sans-serif; background-color: #fafafa; }
//            </style>
//        </head>
//        <body>
//            <div class="mermaid">
//            \(code)
//            </div>
//            <script>mermaid.initialize({ startOnLoad: true });</script>
//        </body>
//        </html>
//        """
//    }
//}
