import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "App")

@main
struct MurmurApp: App {

    @StateObject private var licenseService = LicenseService()
    @StateObject private var pythonEnv = PythonEnvironmentService()
    @StateObject private var ttsService = TTSService()
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var settingsService = SettingsService()

    @State private var isLicenseValidated = false
    @State private var isCheckingLicense = true
    @State private var isSetupComplete = false
    @State private var _serverManager: ServerManager?

    private var serverManager: ServerManager {
        if let existing = _serverManager {
            return existing
        }
        let manager = ServerManager(pythonEnvironment: pythonEnv)
        return manager
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isCheckingLicense {
                    // Initial license check loading state
                    licenseLoadingView
                } else if !isLicenseValidated {
                    // Show license activation view
                    LicenseView(licenseService: licenseService) {
                        withAnimation(.spring(duration: 0.5)) {
                            isLicenseValidated = true
                        }
                    }
                } else if isSetupComplete {
                    // Main app content
                    ContentView()
                        .environmentObject(ttsService)
                        .environmentObject(audioPlayerService)
                        .environmentObject(settingsService)
                        .task {
                            await loadModelOnLaunch()
                        }
                } else {
                    // Setup flow
                    if let manager = _serverManager {
                        SetupView(
                            pythonEnv: pythonEnv,
                            serverManager: manager,
                            onComplete: {
                                withAnimation(.spring(duration: 0.5)) {
                                    isSetupComplete = true
                                }
                            }
                        )
                    } else {
                        // Initial loading state
                        ZStack {
                            Color(NSColor.windowBackgroundColor)
                            ProgressView()
                                .scaleEffect(1.2)
                        }
                        .task {
                            _serverManager = ServerManager(pythonEnvironment: pythonEnv)
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 500)
            .task {
                await checkLicense()
            }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Remove New Window command
            }

            CommandGroup(after: .newItem) {
                Button("Open Document...") {
                    NotificationCenter.default.post(name: .openDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Divider()
            }

            CommandMenu("Speech") {
                Button("Generate") {
                    NotificationCenter.default.post(
                        name: .generateSpeech,
                        object: nil
                    )
                }
                .keyboardShortcut(.return, modifiers: .command)

                Divider()

                Button("Play/Pause") {
                    audioPlayerService.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Stop") {
                    audioPlayerService.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            CommandMenu("Voice") {
                Button("Restart Voice Engine") {
                    Task {
                        await _serverManager?.restartServer()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(_serverManager?.serverState != .running)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsService)
                .environmentObject(ttsService)
                .environmentObject(licenseService)
        }
    }

    // MARK: - License Loading View

    private var licenseLoadingView: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Checking license...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - License Check

    private func checkLicense() async {
        logger.info("Starting license check...")

        // Small delay for UI smoothness
        try? await Task.sleep(for: .milliseconds(300))

        let isValid = await licenseService.checkLicenseOnLaunch()
        logger.info("License check result: \(isValid)")

        await MainActor.run {
            isLicenseValidated = isValid
            isCheckingLicense = false
            logger.info("State updated - isLicenseValidated: \(isValid), isCheckingLicense: false")
        }
    }

    // MARK: - Model Loading

    private func loadModelOnLaunch() async {
        if let manager = _serverManager, manager.serverState != .running {
            await manager.startServer()
        }

        do {
            try await ttsService.loadModel()
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let generateSpeech = Notification.Name("generateSpeech")
    static let openDocument = Notification.Name("openDocument")
}
