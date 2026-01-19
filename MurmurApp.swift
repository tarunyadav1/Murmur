import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "App")

@main
struct MurmurApp: App {

    @StateObject private var licenseService = LicenseService()
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var settingsService = SettingsService()
    @StateObject private var ttsService = KokoroTTSService()

    @State private var isLicenseValidated = false
    @State private var isCheckingLicense = true
    @State private var isSetupComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isCheckingLicense {
                    licenseLoadingView
                } else if !isLicenseValidated {
                    LicenseView(licenseService: licenseService) {
                        withAnimation(.spring(duration: 0.5)) {
                            isLicenseValidated = true
                        }
                    }
                } else if isSetupComplete {
                    mainContentView
                } else {
                    setupView
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
            CommandGroup(replacing: .newItem) {}

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
                    NotificationCenter.default.post(name: .generateSpeech, object: nil)
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
        }

        Settings {
            SettingsView()
                .environmentObject(settingsService)
                .environmentObject(ttsService)
                .environmentObject(licenseService)
        }
    }

    // MARK: - Main Content View

    private var mainContentView: some View {
        ContentView()
            .environmentObject(ttsService)
            .environmentObject(audioPlayerService)
            .environmentObject(settingsService)
    }

    // MARK: - Setup View

    private var setupView: some View {
        ModelSetupView(ttsService: ttsService) {
            withAnimation(.spring(duration: 0.5)) {
                isSetupComplete = true
            }
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
        try? await Task.sleep(for: .milliseconds(300))

        let isValid = await licenseService.checkLicenseOnLaunch()
        logger.info("License check result: \(isValid)")

        await MainActor.run {
            isLicenseValidated = isValid
            isCheckingLicense = false
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let generateSpeech = Notification.Name("generateSpeech")
    static let openDocument = Notification.Name("openDocument")
}
