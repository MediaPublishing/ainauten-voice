// -------------------------------------------------------------------
// LocalWhisper.swift
// 100% Native macOS Swift & SwiftUI App
// Serves as the primary user interface and status bar icon.
// Manages python subprocesses in the background and connects via HTTP.
// -------------------------------------------------------------------

import SwiftUI
import AppKit
import Foundation

// MARK: - API Models

struct StatusResponse: Codable {
    let daemon_status: String
    let daemon_recording: Bool
    let ollama_running: Bool
    let ollama_models: [String]
    let active_hotkey: String
}

struct DictationEntry: Codable, Identifiable {
    let id: Int
    let timestamp: String
    let app: String?
    let duration: Double?
    let num_words: Int?
    let raw_text: String
    let refined_text: String?
}

struct HistoryResponse: Codable {
    let history: [DictationEntry]
}

struct AppSettings: Codable {
    var whisper_model: String = "base"
    var whisper_language: String = "auto"
    var global_hotkey: String = "option+space"
    var ollama_enabled: String = "true"
    var ollama_model: String = "gemma4-obliterated:latest"
    var system_prompt: String = ""
    var custom_vocabulary: String = ""
}

// MARK: - API Client

class APIClient: ObservableObject {
    static let shared = APIClient()
    private let baseURL = "http://127.0.0.1:4950"
    
    func getStatus(completion: @escaping (StatusResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/status") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            let response = try? JSONDecoder().decode(StatusResponse.self, from: data)
            DispatchQueue.main.async {
                completion(response)
            }
        }.resume()
    }
    
    func getHistory(query: String = "", completion: @escaping ([DictationEntry]) -> Void) {
        var urlString = "\(baseURL)/api/history?limit=100"
        if !query.isEmpty {
            urlString += "&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            let response = try? JSONDecoder().decode(HistoryResponse.self, from: data)
            DispatchQueue.main.async {
                completion(response?.history ?? [])
            }
        }.resume()
    }
    
    func getSettings(completion: @escaping (AppSettings?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/settings") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
            DispatchQueue.main.async {
                completion(settings)
            }
        }.resume()
    }
    
    func saveSettings(_ settings: AppSettings, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/settings") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(settings)
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(success)
            }
        }.resume()
    }
    
    func deleteEntry(id: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/delete/\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(success)
            }
        }.resume()
    }
    
    func toggleRecording() {
        guard let url = URL(string: "\(baseURL)/api/record/toggle") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
}

// MARK: - App Delegate & Coordinator

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var backendProcess: Process?
    
    @Published var daemonStatus = "inaktiv"
    @Published var isRecording = false
    @Published var ollamaRunning = false
    @Published var ollamaModels: [String] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Start Python Subprocess invisibly
        startBackend()
        
        // 2. Setup Menubar Status Icon
        setupMenuBar()
        
        // 3. Set Accessory Policy (Menu Bar app only, hides Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // 4. Start Live Status Polling
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopBackend()
    }
    
    private func startBackend() {
        print("[Swift] Starte Python-Backend...")
        
        let process = Process()
        let bundlePath = Bundle.main.bundlePath
        let workingDirectory: String
        
        if bundlePath.hasSuffix(".app") {
            // Running compiled inside App Bundle - start the PyInstaller executable directly
            print("[Swift] Bundle-Modus aktiv. Starte gebündeltes Backend-Binary...")
            workingDirectory = "\(bundlePath)/Contents/Resources/python_backend"
            let binaryPath = "\(workingDirectory)/LocalWhisperBackend"
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = []
        } else {
            // Running locally in dev workspace
            print("[Swift] Entwicklungs-Modus aktiv.")
            workingDirectory = FileManager.default.currentDirectoryPath
            let pythonScriptPath = "\(workingDirectory)/main.py"
            let pythonExecutable = "\(workingDirectory)/.venv/bin/python3"
            
            if FileManager.default.fileExists(atPath: pythonExecutable) {
                process.executableURL = URL(fileURLWithPath: pythonExecutable)
            } else {
                process.executableURL = URL(fileURLWithPath: "/opt/anaconda3/bin/python3")
            }
            process.arguments = [pythonScriptPath]
        }
        
        // Fallback for executable URL if not set
        if process.executableURL == nil {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        }
        
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        // Mute stdout/stderr to run completely silently
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            self.backendProcess = process
            print("[Swift] Backend Subprozess erfolgreich gestartet (PID: \(process.processIdentifier)).")
        } catch {
            print("[Swift] FEHLER beim Starten des Backends: \(error)")
        }
    }
    
    private func stopBackend() {
        if let process = backendProcess, process.isRunning {
            print("[Swift] Stoppe Python-Backend (PID: \(process.processIdentifier))...")
            process.terminate()
            process.waitUntilExit()
            print("[Swift] Backend gestoppt.")
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "🎙️"
            button.action = #selector(menuItemAction(_:))
            button.target = self
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "📊 Verlauf & Einstellungen...", action: #selector(showAppWindow), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "🎙️ Diktat starten/stoppen", action: #selector(toggleRecordingAction), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        
        let statusItemMenu = NSMenuItem(title: "Zustand: bereit", action: nil, keyEquivalent: "")
        statusItemMenu.tag = 100
        menu.addItem(statusItemMenu)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "❌ Beenden", action: #selector(terminateApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func menuItemAction(_ sender: AnyObject) {
        // Managed via NSMenu
    }
    
    @objc func toggleRecordingAction() {
        APIClient.shared.toggleRecording()
    }
    
    @objc func terminateApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func showAppWindow() {
        if window == nil {
            let contentView = ContentView().environmentObject(self)
            
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            
            window?.center()
            window?.title = "LocalWhisper"
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.isReleasedWhenClosed = false
            window?.delegate = self
            window?.contentView = NSHostingView(rootView: contentView)
        }
        
        // Show dock icon when window opens
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Hide dock icon when window is closed, runs purely in status bar
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func pollStatus() {
        APIClient.shared.getStatus { [weak self] response in
            guard let self = self, let data = response else { return }
            
            self.daemonStatus = data.daemon_status
            self.isRecording = data.daemon_recording
            self.ollamaRunning = data.ollama_running
            self.ollamaModels = data.ollama_models
            
            // Dynamic title / icon in macOS menu bar
            if let button = self.statusItem?.button {
                if data.daemon_recording {
                    button.title = "🔴 AUFNAHME"
                } else if data.daemon_status == "transkribiert..." {
                    button.title = "⏳ Transkription..."
                } else if data.daemon_status.contains("verfeinert") {
                    button.title = "🔮 KI-Glättung..."
                } else if data.daemon_status == "fügt ein..." {
                    button.title = "✍️ Einfügen..."
                } else {
                    button.title = "🎙️"
                }
            }
            
            // Update menu item label
            if let menu = self.statusItem?.menu, let statusItemMenu = menu.item(withTag: 100) {
                statusItemMenu.title = "Zustand: \(data.daemon_status)"
            }
        }
    }
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var currentView = "history"
    
    var body: some View {
        HSplitView {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 0) {
                // Header / Logo
                HStack(spacing: 12) {
                    Image(systemName: "microphone.and.signal.meter")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(10)
                        .shadow(color: .purple.opacity(0.4), radius: 6)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LocalWhisper")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("100% Offline & Privat")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 32)
                
                // Navigation items
                VStack(spacing: 4) {
                    SidebarButton(title: "Diktate", icon: "clock.arrow.circlepath", isActive: currentView == "history") {
                        currentView = "history"
                    }
                    
                    SidebarButton(title: "Einstellungen", icon: "slider.horizontal.3", isActive: currentView == "settings") {
                        currentView = "settings"
                    }
                    
                    SidebarButton(title: "Hilfe", icon: "questionmark.circle", isActive: currentView == "help") {
                        currentView = "help"
                    }
                }
                .padding(.horizontal, 8)
                
                Spacer()
                
                // Live System Status
                VStack(alignment: .leading, spacing: 10) {
                    Text("SYSTEM-STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    
                    StatusRow(label: "Daemon", isOnline: appDelegate.daemonStatus != "inaktiv" && appDelegate.daemonStatus != "Fehler", pulse: appDelegate.isRecording)
                    StatusRow(label: "Whisper", isOnline: appDelegate.daemonStatus != "inaktiv" && appDelegate.daemonStatus != "Fehler", pulse: appDelegate.daemonStatus == "transkribiert...")
                    StatusRow(label: "Ollama (KI)", isOnline: appDelegate.ollamaRunning, pulse: appDelegate.daemonStatus.contains("verfeinert"))
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(12)
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.bottom, 16)
            }
            .frame(width: 220)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
            // Detail / Views switcher
            Group {
                if currentView == "history" {
                    HistoryView()
                } else if currentView == "settings" {
                    SettingsView()
                } else {
                    HelpView()
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 850, minHeight: 580)
    }
}

// Sidebar Button Helper
struct SidebarButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isActive ? .bold : .regular))
                    .foregroundColor(isActive ? .purple : .secondary)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .purple : .primary)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isActive ? Color.purple.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// System Status Row Helper
struct StatusRow: View {
    let label: String
    let isOnline: Bool
    var pulse: Bool = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(isOnline ? Color.green : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .scaleEffect(scale)
                    .onAppear {
                        if pulse {
                            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                scale = 1.5
                            }
                        }
                    }
                
                Text(isOnline ? (pulse ? "Aktiv" : "Bereit") : "Offline")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isOnline ? .green : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isOnline ? Color.green.opacity(0.12) : Color.primary.opacity(0.04))
            .cornerRadius(10)
        }
    }
}

// Visual Effect / Frosted Glass View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - History View

struct HistoryView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var searchQuery = ""
    @State private var history: [DictationEntry] = []
    @State private var isLoading = false
    @State private var showCopiedToast = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diktier-Verlauf")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Deine lokal transkribierten und veredelten Diktate")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Record Trigger compact button
                Button(action: {
                    APIClient.shared.toggleRecording()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: appDelegate.isRecording ? "stop.fill" : "mic.fill")
                        Text(appDelegate.isRecording ? "Stoppen" : "Diktieren")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(appDelegate.isRecording ? Color.red : Color.purple)
                    .cornerRadius(8)
                    .shadow(color: appDelegate.isRecording ? .red.opacity(0.3) : .purple.opacity(0.3), radius: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Suche in deinen Diktaten...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: searchQuery) { [searchQuery] newValue in
                        loadHistory(query: newValue)
                    }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Status banner wave when transcribing
            if appDelegate.daemonStatus == "transkribiert..." || appDelegate.daemonStatus.contains("verfeinert") {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    
                    Text(appDelegate.daemonStatus == "transkribiert..." ? "Verarbeite Sprache... Bitte warten." : "KI-Veredelung (Ollama)... Verfeinere Grammatik.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            
            // History list
            if isLoading {
                Spacer()
                ProgressView("Lade Verlauf...")
                Spacer()
            } else if history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "microphone.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Keine Diktate gefunden.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                    Text("Drücke den Shortcut (Option+Space) und nimm dein erstes Diktat auf!")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(history) { entry in
                            DictationCard(entry: entry) {
                                // Delete completion
                                loadHistory(query: searchQuery)
                            } copyCallback: {
                                showCopiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    showCopiedToast = false
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .overlay(
            // Copied Toast
            VStack {
                Spacer()
                if showCopiedToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("In die Zwischenablage kopiert!")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(20)
                    .shadow(radius: 6)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
        .onAppear {
            loadHistory()
        }
    }
    
    private func loadHistory(query: String = "") {
        isLoading = history.isEmpty // only show loader on first loading
        APIClient.shared.getHistory(query: query) { list in
            self.history = list
            self.isLoading = false
        }
    }
}

// Dictation Card Component
struct DictationCard: View {
    let entry: DictationEntry
    let onDelete: () -> Void
    let copyCallback: () -> Void
    
    @State private var showRawText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: App, Date, Duration, Actions
            HStack {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "app.dashed")
                        Text(entry.app ?? "Unbekannte App")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(6)
                    
                    // Duration & Words Text
                    Text("\(entry.duration != nil ? String(format: "%.1fs", entry.duration!) : "0s") • \(entry.num_words ?? 0) Wörter")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Copy & Delete Buttons
                HStack(spacing: 6) {
                    Button(action: {
                        let text = entry.refined_text ?? entry.raw_text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copyCallback()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        APIClient.shared.deleteEntry(id: entry.id) { success in
                            if success {
                                withAnimation {
                                    onDelete()
                                }
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Text Content (Refined / Raw)
            Text(entry.refined_text ?? entry.raw_text)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(4)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Raw text toggle if refined exists and is different
            if entry.refined_text != nil && entry.refined_text != entry.raw_text {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .background(Color.primary.opacity(0.06))
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                    
                    Button(action: {
                        withAnimation {
                            showRawText.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showRawText ? 180 : 0))
                            Text("Roh-Transkription anzeigen")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    if showRawText {
                        Text(entry.raw_text)
                            .font(.system(size: 11).italic())
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var settings = AppSettings()
    @State private var saveStatus = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einstellungen")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Passe die Spracherkennung und KI-Veredelung an deine Bedürfnisse an")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Group 1: Whisper Engine
                    VStack(alignment: .leading, spacing: 14) {
                        Text("🎙️ Spracherkennung (Whisper)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.bottom, 4)
                        
                        // Model Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Whisper-Modellgröße")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $settings.whisper_model) {
                                Text("Tiny (Sehr schnell, geringe Genauigkeit)").tag("tiny")
                                Text("Base (Standard, ausgewogen)").tag("base")
                                Text("Small (Genauer, etwas langsamer)").tag("small")
                                Text("Medium (Sehr hohe Genauigkeit)").tag("medium")
                            }
                            .pickerStyle(.menu)
                            
                            Text("Größere Modelle liefern bessere Ergebnisse, beanspruchen aber mehr CPU und Rechenzeit.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        // Language Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Diktat-Sprache")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $settings.whisper_language) {
                                Text("Automatisch erkennen").tag("auto")
                                Text("Hochdeutsch").tag("de")
                                Text("Englisch").tag("en")
                            }
                            .pickerStyle(.segmented)
                            
                            Text("Automatisch ist sinnvoll, wenn Du zwischen Deutsch und Englisch wechselst. Eine feste Sprache ist robuster bei längeren einsprachigen Diktaten.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        // Hotkey
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Globaler Tastatur-Shortcut")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            TextField("option+space", text: $settings.global_hotkey)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Das Tastaturkürzel zum Diktieren (z.B. option+space oder ctrl+alt+s).")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    // Group 2: Ollama AI
                    VStack(alignment: .leading, spacing: 14) {
                        Text("🔮 KI-Veredelung (Ollama)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.bottom, 4)
                        
                        // Enabled Toggle
                        Toggle("Automatische KI-Textkorrektur aktivieren", isOn: Binding(
                            get: { settings.ollama_enabled == "true" },
                            set: { settings.ollama_enabled = $0 ? "true" : "false" }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        
                        if settings.ollama_enabled == "true" {
                            // Model Picker
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ollama LLM-Modell")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $settings.ollama_model) {
                                    if appDelegate.ollamaModels.isEmpty {
                                        Text("Keine Modelle gefunden").tag("")
                                    } else {
                                        ForEach(appDelegate.ollamaModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(appDelegate.ollamaModels.isEmpty)
                                
                                Text("Das lokale Modell, welches Füllwörter filtert und Deutsch oder Englisch glättet.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    // Group 3: Vocabulary & Prompts
                    VStack(alignment: .leading, spacing: 14) {
                        Text("📚 Custom Vokabular & System-Prompt")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.bottom, 4)
                        
                        // Custom Vocabulary
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wörterbuch / Eigennamen (kommagetrennt)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $settings.custom_vocabulary)
                                .frame(height: 50)
                                .cornerRadius(6)
                                .font(.system(size: 12))
                            
                            Text("Trage hier Begriffe oder Firmennamen ein, die Whisper häufig falsch transkribiert.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        if settings.ollama_enabled == "true" {
                            // System Prompt
                            VStack(alignment: .leading, spacing: 6) {
                                Text("KI-Systemanweisungen (Prompt)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $settings.system_prompt)
                                    .frame(height: 90)
                                    .cornerRadius(6)
                                    .font(.system(size: 12))
                                
                                Text("Steuert, wie die KI deine Roh-Texte nachbearbeitet.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    // Save Status / Save Button
                    HStack {
                        if !saveStatus.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: saveStatus.contains("Erfolg") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(saveStatus.contains("Erfolg") ? .green : .red)
                                Text(saveStatus)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(saveStatus.contains("Erfolg") ? .green : .red)
                            }
                            .transition(.opacity)
                        }
                        
                        Spacer()
                        
                        Button(action: saveSettings) {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "folder.badge.plus")
                                }
                                Text("Speichern")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 18)
                            .background(Color.purple)
                            .cornerRadius(8)
                            .shadow(color: .purple.opacity(0.3), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .onAppear {
            APIClient.shared.getSettings { loadedSettings in
                if let loaded = loadedSettings {
                    self.settings = loaded
                }
            }
        }
    }
    
    private func saveSettings() {
        isSaving = true
        saveStatus = ""
        APIClient.shared.saveSettings(settings) { success in
            isSaving = false
            if success {
                saveStatus = "Erfolgreich gespeichert!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    saveStatus = ""
                }
            } else {
                saveStatus = "Fehler beim Speichern"
            }
        }
    }
}

// MARK: - Help View

struct HelpView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hilfe & Tipps")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Wie Du das Beste aus deinem lokalen Diktier-Assistenten herausholst")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Help Card 1
                    HelpCardView(title: "⚡ Schnellstart", icon: "bolt.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            HelpStep(number: 1, text: "Drücke den globalen Shortcut (Standard: **Option + Leertaste**).")
                            HelpStep(number: 2, text: "Ein rotes Aufnahmesymbol erscheint in deiner Menüleiste.")
                            HelpStep(number: 3, text: "Sprich deinen Text ganz normal ein.")
                            HelpStep(number: 4, text: "Drücke erneut **Option + Leertaste**, um das Diktat zu beenden.")
                            HelpStep(number: 5, text: "Der veredelte deutsche Text wird **sofort** an deiner Cursorposition eingefügt!")
                        }
                    }
                    
                    // Help Card 2
                    HelpCardView(title: "🔮 Smart Formatting & gesprochene Befehle", icon: "wand.and.stars") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Da deine Diktate lokal mit **Gemma 4** verarbeitet werden, kannst du Befehle direkt während des Sprechens diktieren. Sag einfach:")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HelpBullet(text: "*\"Format: Liste. Erstens einkaufen, zweitens kochen...\"*")
                                HelpBullet(text: "*\"Mach daraus eine formelle E-Mail an Thomas...\"*")
                                HelpBullet(text: "*\"Schreibe als kurze Slack-Nachricht: Bin gleich da...\"*")
                            }
                            .padding(.top, 4)
                            
                            Text("Die KI versteht diese gesprochenen Befehle und gibt nur den perfekt formatierten Text aus.")
                                .font(.system(size: 11))
                                .italic()
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Help Card 3
                    HelpCardView(title: "🔒 100% Datenschutz", icon: "shield.checkered") {
                        Text("LocalWhisper arbeitet vollständig offline. Deine Audiodaten und Texte verlassen niemals deine Festplatte. Keine Cloud, keine API-Kosten, kein Telemetrie-Tracking. Perfekt für sensible E-Mails, vertrauliche Dokumente und Geschäftsgeheimnisse.")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    }
                }
                .padding(24)
            }
        }
    }
}

struct HelpCardView<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
                
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.bottom, 6)
            
            content()
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct HelpStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.purple)
                .cornerRadius(9)
            
            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineSpacing(2)
        }
    }
}

struct HelpBullet: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.purple)
            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - App Main Definition

@main
struct LocalWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
    }
}
