import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "PythonEnvironment")

/// Manages Python virtual environment and Chatterbox installation using bundled Python
@MainActor
final class PythonEnvironmentService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var setupState: SetupState = .notStarted
    @Published private(set) var setupProgress: Double = 0.0
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var pythonPath: String?
    @Published private(set) var isReady: Bool = false

    enum SetupState: Equatable {
        case notStarted
        case checkingPython
        case creatingEnvironment
        case installingDependencies
        case downloadingModel
        case ready
        case failed(String)
    }

    // MARK: - Paths

    /// Bundled Python in app Resources
    private var bundledPythonURL: URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        return URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("Python/python/bin/python3.11")
    }

    private var appSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Murmur", isDirectory: true)
    }

    private var venvURL: URL {
        appSupportURL.appendingPathComponent("python-env", isDirectory: true)
    }

    private var venvPythonURL: URL {
        venvURL.appendingPathComponent("bin/python3")
    }

    private var venvPipURL: URL {
        venvURL.appendingPathComponent("bin/pip")
    }

    private var serverScriptURL: URL {
        appSupportURL.appendingPathComponent("ChatterboxServer/server.py")
    }

    var serverDirectory: URL {
        appSupportURL.appendingPathComponent("ChatterboxServer", isDirectory: true)
    }

    var voiceSamplesURL: URL {
        appSupportURL.appendingPathComponent("VoiceSamples", isDirectory: true)
    }

    // MARK: - Setup

    /// Check if environment is already set up
    func checkExistingSetup() async -> Bool {
        let pythonExists = FileManager.default.fileExists(atPath: venvPythonURL.path)
        let serverExists = FileManager.default.fileExists(atPath: serverScriptURL.path)

        if pythonExists && serverExists {
            // Verify chatterbox is installed
            do {
                let result = try await runCommand(venvPythonURL.path, arguments: ["-c", "import chatterbox; print('ok')"])
                if result.contains("ok") {
                    pythonPath = venvPythonURL.path
                    setupState = .ready
                    isReady = true
                    logger.info("Existing Python environment found and verified")

                    // Always sync server files and voice samples on launch
                    await syncServerFiles()
                    await syncVoiceSamples()

                    return true
                }
            } catch {
                logger.warning("Existing environment found but chatterbox not working: \(error.localizedDescription)")
            }
        }

        return false
    }

    /// Sync server files from bundle to Application Support (ensures latest code)
    private func syncServerFiles() async {
        let fm = FileManager.default

        guard let bundlePath = Bundle.main.resourcePath else {
            logger.warning("Bundle resources not found, skipping server files sync")
            return
        }

        let bundleServerDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("ChatterboxServer")

        guard fm.fileExists(atPath: bundleServerDir.path) else {
            logger.warning("Server files not found in bundle")
            return
        }

        do {
            // Sync server.py
            let srcServer = bundleServerDir.appendingPathComponent("server.py")
            let dstServer = serverDirectory.appendingPathComponent("server.py")
            if fm.fileExists(atPath: dstServer.path) {
                try fm.removeItem(at: dstServer)
            }
            try fm.copyItem(at: srcServer, to: dstServer)

            // Sync requirements.txt
            let srcReq = bundleServerDir.appendingPathComponent("requirements.txt")
            let dstReq = serverDirectory.appendingPathComponent("requirements.txt")
            if fm.fileExists(atPath: dstReq.path) {
                try fm.removeItem(at: dstReq)
            }
            try fm.copyItem(at: srcReq, to: dstReq)

            logger.info("Server files synced from bundle")
        } catch {
            logger.error("Failed to sync server files: \(error.localizedDescription)")
        }
    }

    /// Sync voice samples from bundle to Application Support
    private func syncVoiceSamples() async {
        let fm = FileManager.default

        guard let bundlePath = Bundle.main.resourcePath else {
            logger.warning("Bundle resources not found, skipping voice samples sync")
            return
        }

        let bundleVoiceSamplesDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("VoiceSamples")

        guard fm.fileExists(atPath: bundleVoiceSamplesDir.path) else {
            logger.warning("Voice samples not found in bundle")
            return
        }

        do {
            // Remove existing and copy fresh from bundle
            if fm.fileExists(atPath: self.voiceSamplesURL.path) {
                try fm.removeItem(at: self.voiceSamplesURL)
            }
            try fm.copyItem(at: bundleVoiceSamplesDir, to: self.voiceSamplesURL)
            logger.info("Voice samples synced to \(self.voiceSamplesURL.path)")
        } catch {
            logger.error("Failed to sync voice samples: \(error.localizedDescription)")
        }
    }

    /// Perform full setup using bundled Python
    func setup() async {
        guard setupState != .ready else { return }

        do {
            // Step 1: Verify bundled Python
            setupState = .checkingPython
            statusMessage = "Initializing..."
            setupProgress = 0.1

            guard let bundledPython = bundledPythonURL,
                  FileManager.default.fileExists(atPath: bundledPython.path) else {
                throw SetupError.bundledPythonNotFound
            }

            // Verify bundled Python works
            let version = try await runCommand(bundledPython.path, arguments: ["--version"])
            logger.info("Using bundled Python: \(version.trimmingCharacters(in: .whitespacesAndNewlines))")

            // Step 2: Create App Support directory
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Step 3: Copy server files from bundle
            statusMessage = "Preparing..."
            setupProgress = 0.15
            try await copyServerFiles()

            // Step 4: Create virtual environment using bundled Python
            setupState = .creatingEnvironment
            statusMessage = "Setting up..."
            setupProgress = 0.2

            if FileManager.default.fileExists(atPath: venvURL.path) {
                // Remove old venv to ensure clean state
                try FileManager.default.removeItem(at: venvURL)
            }

            let venvPath = venvURL.path
            _ = try await runCommand(bundledPython.path, arguments: ["-m", "venv", venvPath])
            logger.info("Created virtual environment at \(venvPath)")

            // Step 5: Install dependencies
            setupState = .installingDependencies
            statusMessage = "Installing voice engine..."
            setupProgress = 0.3

            // Upgrade pip first
            _ = try await runCommand(venvPipURL.path, arguments: ["install", "--upgrade", "pip"], timeout: 120)
            setupProgress = 0.4

            // Install requirements
            let requirementsPath = serverDirectory.appendingPathComponent("requirements.txt").path
            _ = try await runCommand(venvPipURL.path, arguments: ["install", "-r", requirementsPath], timeout: 600)
            setupProgress = 0.7

            // Step 6: Pre-download model
            setupState = .downloadingModel
            statusMessage = "Downloading voices..."
            setupProgress = 0.8

            let preloadScript = """
            import torch
            from chatterbox.tts import ChatterboxTTS
            device = 'mps' if torch.backends.mps.is_available() else 'cpu'
            print(f'Loading model on {device}...')
            model = ChatterboxTTS.from_pretrained(device=device)
            print('Model loaded successfully!')
            """

            do {
                _ = try await runCommand(venvPythonURL.path, arguments: ["-c", preloadScript], timeout: 600)
                logger.info("Model pre-downloaded successfully")
            } catch {
                // Model will download on first use, not critical
                logger.warning("Model pre-download skipped: \(error.localizedDescription)")
            }

            setupProgress = 1.0
            pythonPath = venvPythonURL.path
            setupState = .ready
            isReady = true
            statusMessage = "Ready"
            logger.info("Python environment setup complete")

        } catch {
            logger.error("Setup failed: \(error.localizedDescription)")
            let userMessage = friendlyErrorMessage(from: error)
            setupState = .failed(userMessage)
            statusMessage = userMessage
        }
    }

    /// Convert technical errors to user-friendly messages
    private func friendlyErrorMessage(from error: Error) -> String {
        let description = error.localizedDescription.lowercased()

        if description.contains("network") || description.contains("internet") || description.contains("connection") {
            return "Please check your internet connection and try again."
        } else if description.contains("disk") || description.contains("space") || description.contains("storage") {
            return "Not enough storage space. Please free up some disk space and try again."
        } else if description.contains("timeout") {
            return "The download took too long. Please check your connection and try again."
        } else if description.contains("bundled") || description.contains("not found") {
            return "App files are missing. Please reinstall Murmur."
        } else {
            return "Something went wrong. Please try again or contact support."
        }
    }

    // MARK: - Private Helpers

    private func copyServerFiles() async throws {
        let fm = FileManager.default

        // Create server directory
        try fm.createDirectory(at: serverDirectory, withIntermediateDirectories: true)

        // Get bundle resources
        guard let bundlePath = Bundle.main.resourcePath else {
            throw SetupError.bundleResourcesNotFound
        }

        let bundleServerDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("ChatterboxServer")

        // Check if server files exist in bundle
        guard fm.fileExists(atPath: bundleServerDir.path) else {
            throw SetupError.bundleResourcesNotFound
        }

        // Copy server.py
        let srcServer = bundleServerDir.appendingPathComponent("server.py")
        let dstServer = serverDirectory.appendingPathComponent("server.py")

        if fm.fileExists(atPath: dstServer.path) {
            try fm.removeItem(at: dstServer)
        }
        try fm.copyItem(at: srcServer, to: dstServer)

        // Copy requirements.txt
        let srcReq = bundleServerDir.appendingPathComponent("requirements.txt")
        let dstReq = serverDirectory.appendingPathComponent("requirements.txt")

        if fm.fileExists(atPath: dstReq.path) {
            try fm.removeItem(at: dstReq)
        }
        try fm.copyItem(at: srcReq, to: dstReq)

        logger.info("Server files copied from bundle")

        // Copy VoiceSamples folder for voice cloning
        try await copyVoiceSamples()
    }

    private func copyVoiceSamples() async throws {
        let fm = FileManager.default

        guard let bundlePath = Bundle.main.resourcePath else {
            logger.warning("Bundle resources not found, skipping voice samples copy")
            return
        }

        let bundleVoiceSamplesDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("VoiceSamples")

        // Check if voice samples exist in bundle
        guard fm.fileExists(atPath: bundleVoiceSamplesDir.path) else {
            logger.warning("Voice samples not found in bundle at \(bundleVoiceSamplesDir.path)")
            return
        }

        // Remove existing voice samples directory if it exists
        if fm.fileExists(atPath: self.voiceSamplesURL.path) {
            try fm.removeItem(at: self.voiceSamplesURL)
        }

        // Copy the entire VoiceSamples folder
        try fm.copyItem(at: bundleVoiceSamplesDir, to: self.voiceSamplesURL)
        logger.info("Voice samples copied to \(self.voiceSamplesURL.path)")
    }

    private func runCommand(_ command: String, arguments: [String], timeout: TimeInterval = 120) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            // Set environment
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
            // Ensure pip installs to the venv
            env["PIP_REQUIRE_VIRTUALENV"] = "false"
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Timeout handling
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            process.waitUntilExit()
            timeoutWorkItem.cancel()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                continuation.resume(returning: output + errorOutput)
            } else {
                let combinedOutput = output + errorOutput
                continuation.resume(throwing: SetupError.commandFailed(combinedOutput))
            }
        }
    }

    // MARK: - Errors

    enum SetupError: LocalizedError {
        case bundledPythonNotFound
        case bundleResourcesNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundledPythonNotFound:
                return "Bundled Python not found in application. Please reinstall the app."
            case .bundleResourcesNotFound:
                return "Application resources not found. Please reinstall the app."
            case .commandFailed(let output):
                return "Command failed: \(output.prefix(500))"
            }
        }
    }
}
