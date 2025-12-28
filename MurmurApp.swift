import SwiftUI

@main
struct MurmurApp: App {

    @StateObject private var pythonEnv = PythonEnvironmentService()
    @StateObject private var ttsService = TTSService()
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var settingsService = SettingsService()

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
                if isSetupComplete {
                    ContentView()
                        .environmentObject(ttsService)
                        .environmentObject(audioPlayerService)
                        .environmentObject(settingsService)
                        .task {
                            await loadModelOnLaunch()
                        }
                } else {
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
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Remove New Window command
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
        }
    }

    private func loadModelOnLaunch() async {
        if let manager = _serverManager, manager.serverState != .running {
            await manager.startServer()
        }

        do {
            try await ttsService.loadModel()
        } catch {
            print("Failed to load model: \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let generateSpeech = Notification.Name("generateSpeech")
}
