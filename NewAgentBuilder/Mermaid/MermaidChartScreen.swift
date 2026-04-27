//
//  MermaidChartScreen.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/28/25.
//


import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Mermaid Drop Zone View
struct MermaidDropZoneView: View {
    @Binding var mermaidCode: String
    @Binding var errorMessage: String?
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 8) {
            Text("📥 Drop .txt/.md file")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isTargeted ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTargeted ? Color.green : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                )
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                }
            
            Text("Or paste below:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $mermaidCode)
                .font(.system(.body, design: .monospaced))
                .frame(height: 600) // Compact for split-screen
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3))
                )
                .overlay(
                    Text("Paste Mermaid code")
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(8)
                        .visible(mermaidCode.isEmpty),
                    alignment: .topLeading
                )
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.errorMessage = "Load failed: \(error.localizedDescription)"
                        }
                        return
                    }
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let content = try? String(contentsOf: url) else {
                        DispatchQueue.main.async {
                            self.errorMessage = "Invalid file"
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.mermaidCode = content
                        self.errorMessage = nil
                    }
                }
                return true
            }
            
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { object, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.errorMessage = "Text load failed: \(error.localizedDescription)"
                        }
                        return
                    }
                    guard let str = object else {
                        DispatchQueue.main.async {
                            self.errorMessage = "Invalid text"
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.mermaidCode = str
                        self.errorMessage = nil
                    }
                }
                return true
            }
        }
        DispatchQueue.main.async {
            self.errorMessage = "Unsupported drop type"
        }
        return false
    }
}

// MARK: - Mermaid Chart View
struct MermaidChartView: UIViewRepresentable {
    let mermaidCode: String
    let zoomScale: CGFloat
    @Binding var errorMessage: String?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        let contentController = webView.configuration.userContentController
        contentController.add(context.coordinator, name: "mermaidError")
        loadMermaid(webView: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedCode != mermaidCode || context.coordinator.lastZoomScale != zoomScale {
            loadMermaid(webView: uiView)
            context.coordinator.lastRenderedCode = mermaidCode
            context.coordinator.lastZoomScale = zoomScale
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func loadMermaid(webView: WKWebView) {
        let codeData = mermaidCode.data(using: .utf8) ?? Data()
        let base64Code = codeData.base64EncodedString()
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0.5rem;
                    font-family: -apple-system, sans-serif;
                    background-color: transparent;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    overflow: auto;
                }
                .mermaid {
                    width: 100%;
                    height: auto;
                    max-height: 70vh;
                    transform: scale(\(zoomScale));
                    transform-origin: top center;
                }
                svg {
                    max-width: 100% !important;
                    max-height: 70vh !important;
                }
                .error {
                    color: red;
                    font-family: monospace;
                    padding: 1rem;
                    background: #ffe6e6;
                    border-radius: 8px;
                }
            </style>
        </head>
        <body>
            <div id="container" class="mermaid"></div>
            <script>
                mermaid.initialize({
                    startOnLoad: false,
                    theme: 'default',
                    securityLevel: 'loose',
                    flowchart: {
                        useMaxWidth: true,
                        htmlLabels: true,
                        nodeSpacing: 15,
                        rankSpacing: 20
                    }
                });
                try {
                    const code = atob('\(base64Code)');
                    document.getElementById('container').textContent = code;
                    mermaid.run();
                } catch (e) {
                    document.getElementById('container').innerHTML = 
                        '<div class="error">Error: ' + e.message + '</div>';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mermaidError) {
                        window.webkit.messageHandlers.mermaidError.postMessage(e.message);
                    }
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidChartView
        var lastRenderedCode: String?
        var lastZoomScale: CGFloat?
        
        init(_ parent: MermaidChartView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mermaidError", let error = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.errorMessage = "Mermaid error: \(error)"
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            document.querySelector('svg').style.touchAction = 'pan-x pan-y pinch-zoom';
            document.body.style.overflow = 'auto';
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - Main Mermaid Chart Screen
struct MermaidChartScreen: View {
    @State private var mermaidCode: String = """
    flowchart TD
        A[🚀 Start: runAgent(input)] --> B[🔁 For Each step in agent.promptSteps]
        B --> C{step.flowStrategy}
        C -->|promptChaining| PC1[🧠 Use previousRun.response as input]
        PC1 --> RunPrompt
        C -->|sharedInput| SI1[📥 Use sharedInput]
        SI1 --> RunPrompt
        C -->|queryEnhanced| QE1[🗂 resolveData(for stepID)]
        QE1 --> QE2[🔀 mergePrompt(userInput + resolvedData)]
        QE2 --> RunPrompt
        C -->|imageInput| IMG1[🖼 check: input contains image URL]
        IMG1 -->|Yes| IMG2[🧠 engine.analyzeImage()]
        IMG1 -->|No| RunPrompt
        C -->|custom| F1[⚠️ log: custom flow unsupported]
        F1 --> B
        RunPrompt --> AIEngine[🤖 engine.runWithBundle()]
        AIEngine -->|success| Resp[📦 AIResponseBundle]
        AIEngine -->|fail| ErrorFlow
        IMG2 -->|success| Resp
        IMG2 -->|fail| ErrorFlow
        Resp --> BuildRun[📝 Create PromptRun]
        BuildRun --> SaveRun[📤 Persist to Firestore]
        SaveRun -->|success| AddRun[✅ Append to promptRuns / allRuns]
        SaveRun -->|fail| ErrorFlow
        AddRun --> UpdateUI
        UpdateUI -->|promptChaining| CHAIN1[🔁 Set userInput = response<br>→ Continue]
        UpdateUI -->|sharedInput| SHARED1[🏷 Display Shared Input Section]
        UpdateUI -->|queryEnhanced/imageInput| CLEAN1[🧹 Clear userInput]
        CHAIN1 --> B
        SHARED1 --> B
        CLEAN1 --> B
        AddRun --> RetryCheck{🔄 User Taps Retry}
        RetryCheck -->|Yes| Retry[🔁 retryPromptRun]
        Retry --> RunPrompt
        RetryCheck -->|No| ForkCheck{🌱 User Taps Fork}
        ForkCheck -->|Yes| Fork[🛠 prepareForkDraft<br>→ runForkVersion]
        Fork --> RunPrompt
        ForkCheck -->|No| FeedbackCheck{📝 Add Feedback}
        FeedbackCheck -->|Yes| Feedback[📍 updateForkFeedback]
        Feedback --> CreateDiagCheck{🧪 Create Diagnostic}
        CreateDiagCheck -->|Yes| Diag[🧠 createDiagnosticRun]
        Diag --> RunPrompt
        FeedbackCheck -->|No| EndCheck{📦 More Steps}
        CreateDiagCheck -->|No| EndCheck
        EndCheck -->|Yes| B
        EndCheck -->|No| DONE[🏁 END]
        ErrorFlow[❌ Handle AgentRunnerError] --> DONE
    """
    @State private var errorMessage: String?
    @State private var showSaveAlert = false
    @State private var showExportAlert = false
    @State private var zoomScale: CGFloat = 0.8
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(spacing: 12) {
                    // Input Section
                    VStack {
                        HStack {
                            Text("Mermaid Code Input")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                mermaidCode = ""
                                errorMessage = nil
                            }
                            .buttonStyle(.bordered)
                            Button("Refresh") {
                                // No need for UUID; handled by zoomScale
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                        
                        MermaidDropZoneView(mermaidCode: $mermaidCode, errorMessage: $errorMessage)
                            //.frame(height: min(geometry.size.height * 0.3, 200))
                            .frame(height: 1000)
                    }
                    .background(Color(.systemGroupedBackground))
                    
                    Divider()
                    
                    // Chart Display Section
                    VStack {
                        HStack {
                            Text("Chart Preview")
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 8) {
                                Button("−") {
                                    zoomScale = max(zoomScale - 0.2, 0.2)
                                }
                                .font(.title2)
                                .foregroundColor(.blue)
                                
                                Text("\(Int(zoomScale * 100))%")
                                    .font(.caption)
                                    .frame(width: 40)
                                
                                Button("+") {
                                    zoomScale = min(zoomScale + 0.2, 2.0)
                                }
                                .font(.title2)
                                .foregroundColor(.blue)
                                
                                Button("Fit") {
                                    zoomScale = 0.8
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            Button(action: { showSaveAlert = true }) {
                                Text("Save")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                        
                        MermaidChartView(mermaidCode: mermaidCode, zoomScale: zoomScale, errorMessage: $errorMessage)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height * 0.6)
                            .background(Color.white)
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Mermaid Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save Mermaid Code", isPresented: $showSaveAlert) {
            Button("Save", action: saveMermaidCode)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current Mermaid code as a .txt file?")
        }
        .alert("Export Diagram", isPresented: $showExportAlert) {
            Button("Export", action: exportDiagram)
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    // Pop view if needed
                }
            }
        }
    }
    
    private func saveMermaidCode() {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            errorMessage = "Failed to access Documents directory"
            return
        }
        let fileURL = url.appendingPathComponent("mermaid_\(Date().timeIntervalSince1970).txt")
        do {
            try mermaidCode.write(to: fileURL, atomically: true, encoding: .utf8)
            errorMessage = "Saved to \(fileURL.lastPathComponent)"
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    private func exportDiagram() {
        errorMessage = "Export not implemented yet"
    }
}

// MARK: - View Extension
extension View {
    @ViewBuilder
    func visible(_ condition: Bool) -> some View {
        if condition {
            self
        }
    }
}

// MARK: - Preview
struct MermaidChartScreen_Previews: PreviewProvider {
    static var previews: some View {
        MermaidChartScreen()
            .previewDevice("iPad Pro (12.9-inch) (6th generation)")
    }
}

