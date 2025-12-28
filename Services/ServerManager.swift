import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "ServerManager")

/// Manages the Chatterbox TTS server process lifecycle
@MainActor
final class ServerManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var serverState: ServerState = .stopped
    @Published private(set) var statusMessage: String = "Server not running"

    enum ServerState: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    // MARK: - Configuration

    let port: Int
    private var serverProcess: Process?
    private var healthCheckTask: Task<Void, Never>?
    private let pythonEnvironment: PythonEnvironmentService

    // MARK: - Initialization

    init(port: Int = 8787, pythonEnvironment: PythonEnvironmentService) {
        self.port = port
        self.pythonEnvironment = pythonEnvironment
    }

    deinit {
        // Clean up process on deinit
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Server Lifecycle

    /// Start the Chatterbox server
    func startServer() async {
        guard serverState != .running && serverState != .starting else {
            logger.info("Server already running or starting")
            return
        }

        guard pythonEnvironment.isReady else {
            serverState = .failed("Python environment not ready")
            statusMessage = "Please complete setup first"
            return
        }

        serverState = .starting
        statusMessage = "Starting up..."

        do {
            try await launchServer()

            // Wait for server to be ready (up to 2 minutes for model loading)
            let ready = await waitForServerReady(maxAttempts: 60, delaySeconds: 2.0)

            if ready {
                serverState = .running
                statusMessage = "Server running on port \(port)"
                logger.info("Chatterbox server started successfully")

                // Start health check monitoring
                startHealthMonitoring()
            } else {
                throw ServerError.startupTimeout
            }

        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
            // Keep the failed state visible - don't call stopServerSync() which would hide the error
            serverState = .failed(friendlyErrorMessage(from: error))
            statusMessage = friendlyErrorMessage(from: error)
        }
    }

    /// Convert technical errors to user-friendly messages
    private func friendlyErrorMessage(from error: Error) -> String {
        let description = error.localizedDescription.lowercased()

        if description.contains("python") || description.contains("configured") {
            return "Voice engine not configured. Please restart the app."
        } else if description.contains("script") || description.contains("not found") {
            return "App files are missing. Please reinstall."
        } else if description.contains("timeout") {
            return "Taking longer than expected. Please wait or restart."
        } else {
            return "Could not start. Please restart the app."
        }
    }

    /// Stop the server
    func stopServer() async {
        stopServerSync()
    }

    private func stopServerSync() {
        healthCheckTask?.cancel()
        healthCheckTask = nil

        if let process = serverProcess, process.isRunning {
            logger.info("Stopping Chatterbox server...")
            process.terminate()

            // Give it a moment to terminate gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    process.interrupt()
                }
            }
        }

        serverProcess = nil
        serverState = .stopped
        statusMessage = "Server stopped"
    }

    /// Restart the server
    func restartServer() async {
        await stopServer()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await startServer()
    }

    // MARK: - Private Methods

    private func launchServer() async throws {
        guard let pythonPath = pythonEnvironment.pythonPath else {
            throw ServerError.pythonNotConfigured
        }

        let serverScript = pythonEnvironment.serverDirectory.appendingPathComponent("server.py")

        guard FileManager.default.fileExists(atPath: serverScript.path) else {
            throw ServerError.serverScriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [serverScript.path]
        process.currentDirectoryURL = pythonEnvironment.serverDirectory

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["HOST"] = "127.0.0.1"

        // Ensure the venv's bin is in PATH
        let venvBin = pythonEnvironment.serverDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("python-env/bin").path
        env["PATH"] = "\(venvBin):/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")

        // Set PYTHONPATH to include the server directory
        env["PYTHONPATH"] = pythonEnvironment.serverDirectory.path

        // Tell server where to find voice samples (fixes path resolution issues)
        env["MURMUR_VOICE_SAMPLES_DIR"] = pythonEnvironment.voiceSamplesURL.path

        process.environment = env

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Log server output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                logger.debug("Server stdout: \(str)")
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                logger.debug("Server stderr: \(str)")
            }
        }

        try process.run()
        serverProcess = process

        logger.info("Server process launched with PID: \(process.processIdentifier)")
    }

    private func waitForServerReady(maxAttempts: Int, delaySeconds: Double) async -> Bool {
        for attempt in 1...maxAttempts {
            if await checkServerHealth() {
                return true
            }

            // User-friendly message without technical details
            if attempt < 10 {
                statusMessage = "Loading voices..."
            } else if attempt < 30 {
                statusMessage = "Almost ready..."
            } else {
                statusMessage = "Still loading (this may take a minute)..."
            }

            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            // Check if process died
            if let process = serverProcess, !process.isRunning {
                logger.error("Server process terminated unexpectedly")
                return false
            }
        }
        return false
    }

    private func checkServerHealth() async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.debug("Health check: bad response")
                return false
            }

            struct HealthResponse: Decodable {
                let status: String
                let model_loaded: Bool
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            logger.info("Health check: model_loaded=\(health.model_loaded)")
            return health.model_loaded

        } catch {
            logger.debug("Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    private func startHealthMonitoring() {
        healthCheckTask?.cancel()

        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

                guard !Task.isCancelled else { break }

                let healthy = await checkServerHealth()

                await MainActor.run {
                    if !healthy && self.serverState == .running {
                        logger.warning("Server health check failed")
                        self.serverState = .failed("Server connection lost")
                        self.statusMessage = "Server connection lost"
                    }
                }
            }
        }
    }

    // MARK: - Errors

    enum ServerError: LocalizedError {
        case pythonNotConfigured
        case serverScriptNotFound
        case startupTimeout
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .pythonNotConfigured:
                return "Python environment not configured"
            case .serverScriptNotFound:
                return "Server script not found"
            case .startupTimeout:
                return "Server failed to start within timeout"
            case .alreadyRunning:
                return "Server is already running"
            }
        }
    }
}
