import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "ServerManager")

/// Manages the TTS server process lifecycle
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

    /// Start the TTS server
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

            // Wait for server to be ready (up to 5 minutes for first-time model download)
            let ready = await waitForServerReady(maxAttempts: 150, delaySeconds: 2.0)

            if ready {
                serverState = .running
                statusMessage = "Server running on port \(port)"
                logger.info("TTS server started successfully")

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
            logger.info("Stopping TTS server...")
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

    /// Kill any existing process listening on our port
    private func killExistingServerOnPort() async {
        let serverPort = self.port
        logger.info("Checking for existing process on port \(serverPort)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "lsof -ti tcp:\(serverPort) | xargs kill -9 2>/dev/null || true"]

        do {
            try process.run()
            process.waitUntilExit()
            // Give it a moment for the port to be released
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            logger.info("Cleared port \(serverPort)")
        } catch {
            logger.warning("Failed to kill existing process: \(error.localizedDescription)")
        }
    }

    private func launchServer() async throws {
        // Kill any existing process on our port first
        await killExistingServerOnPort()

        // Check for Kokoro environment (for fast TTS)
        let appSupportDir = pythonEnvironment.serverDirectory.deletingLastPathComponent()
        let kokoroEnvPath = appSupportDir.appendingPathComponent("kokoro-env/bin/python3").path

        // Use Kokoro environment
        guard FileManager.default.fileExists(atPath: kokoroEnvPath) else {
            throw ServerError.pythonNotConfigured
        }

        let pythonPath = kokoroEnvPath
        let serverScriptName = "kokoro_server.py"
        logger.info("Starting voice server...")

        let serverScript = pythonEnvironment.serverDirectory.appendingPathComponent(serverScriptName)

        guard FileManager.default.fileExists(atPath: serverScript.path) else {
            throw ServerError.serverScriptNotFound
        }

        let process = Process()
        // Launch Python directly (bash wrapper causes quoting issues)
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [serverScript.path]
        process.currentDirectoryURL = pythonEnvironment.serverDirectory

        logger.info("DEBUG: Python path: \(pythonPath)")
        logger.info("DEBUG: Script path: \(serverScript.path)")
        logger.info("DEBUG: Working dir: \(self.pythonEnvironment.serverDirectory.path)")
        logger.info("DEBUG: Python exists: \(FileManager.default.fileExists(atPath: pythonPath))")
        logger.info("DEBUG: Python executable: \(FileManager.default.isExecutableFile(atPath: pythonPath))")
        logger.info("DEBUG: Script exists: \(FileManager.default.fileExists(atPath: serverScript.path))")

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["HOST"] = "127.0.0.1"

        // Ensure the venv's bin is in PATH
        let venvDir = URL(fileURLWithPath: pythonPath).deletingLastPathComponent().path
        env["PATH"] = "\(venvDir):/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")

        // Set PYTHONPATH to include the server directory
        env["PYTHONPATH"] = pythonEnvironment.serverDirectory.path

        // Tell server where to find voice samples (fixes path resolution issues)
        env["MURMUR_VOICE_SAMPLES_DIR"] = pythonEnvironment.voiceSamplesURL.path

        // Tell server where to find the bundled Kokoro model (avoids HuggingFace download)
        if let resourcePath = Bundle.main.resourcePath {
            let bundledModelPath = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("KokoroModel").path
            if FileManager.default.fileExists(atPath: bundledModelPath) {
                env["MURMUR_KOKORO_MODEL_PATH"] = bundledModelPath
                logger.info("Using bundled Kokoro model at: \(bundledModelPath)")
            }
        }

        // Fix SSL certificate issues on macOS - use system certificates
        // Multiple env vars for different Python libraries
        env["SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
        env["SSL_CERT_DIR"] = "/etc/ssl/certs"
        env["REQUESTS_CA_BUNDLE"] = "/etc/ssl/cert.pem"
        env["CURL_CA_BUNDLE"] = "/etc/ssl/cert.pem"
        env["HTTPX_SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
        // For HuggingFace Hub specifically
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        // Set longer timeout for model downloads
        env["HF_HUB_DOWNLOAD_TIMEOUT"] = "300"

        process.environment = env
        logger.info("DEBUG: PATH = \(env["PATH"] ?? "nil")")

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

        // Add termination handler to catch crashes
        process.terminationHandler = { proc in
            logger.error("DEBUG: Server process terminated! Exit code: \(proc.terminationStatus), reason: \(proc.terminationReason.rawValue)")
        }
    }

    private func waitForServerReady(maxAttempts: Int, delaySeconds: Double) async -> Bool {
        var serverResponded = false

        for attempt in 1...maxAttempts {
            let result = await checkServerHealthDetailed()

            switch result {
            case .ready:
                return true

            case .loading:
                // Server is responding but model is loading - this is good progress
                serverResponded = true
                statusMessage = "Loading voice model..."
                logger.info("Server responding, model loading (attempt \(attempt))")

            case .notLoaded:
                serverResponded = true
                statusMessage = "Preparing voices..."

            case .error(let message):
                serverResponded = true
                logger.error("Server reported error: \(message)")
                statusMessage = "Error loading model"
                // Don't immediately fail - model might recover
                if attempt > 5 {
                    return false
                }

            case .unreachable:
                // Server not yet responding
                if !serverResponded {
                    // First phase: waiting for server to start
                    if attempt < 5 {
                        statusMessage = "Starting server..."
                    } else if attempt < 15 {
                        statusMessage = "Loading voice engine..."
                    } else if attempt < 45 {
                        statusMessage = "Downloading voice model (first run)..."
                    } else if attempt < 90 {
                        statusMessage = "Still downloading... please wait..."
                    } else {
                        statusMessage = "Almost ready..."
                    }
                } else {
                    // Server was responding but stopped - this is bad
                    logger.warning("Server stopped responding after being available")
                    statusMessage = "Server connection lost..."
                }
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

    /// Result of a health check
    private enum HealthCheckResult {
        case ready           // Model loaded and ready
        case loading         // Server running, model loading
        case notLoaded       // Server running, model not loaded
        case error(String)   // Server running but error occurred
        case unreachable     // Server not responding
    }

    private func checkServerHealth() async -> Bool {
        let result = await checkServerHealthDetailed()
        switch result {
        case .ready:
            return true
        case .loading, .notLoaded, .error, .unreachable:
            return false
        }
    }

    private func checkServerHealthDetailed() async -> HealthCheckResult {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.debug("Health check: bad response")
                return .unreachable
            }

            // Kokoro server format
            struct KokoroHealthResponse: Decodable {
                let status: String
                let model_loaded: Bool
                let model_loading: Bool?
                let load_error: String?
                let device: String
            }

            // Tier status from three-tier format
            struct TierStatus: Decodable {
                let available: Bool
                let loaded: Bool
            }

            // Health response supporting multiple formats
            struct HealthResponse: Decodable {
                let status: String
                let tiers: [String: TierStatus]?
                let device: String
                // Legacy fields
                let models_loaded: [String: Bool]?
                let available_models: [String]?
                // Kokoro fields
                let model_loaded: Bool?
                let model_loading: Bool?
                let load_error: String?
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)

            // Check for Kokoro format first (model_loaded field)
            if let modelLoaded = health.model_loaded {
                if let loadError = health.load_error, !loadError.isEmpty {
                    logger.error("Health check: model load error: \(loadError)")
                    return .error(loadError)
                }

                if health.model_loading == true {
                    logger.info("Health check: model loading...")
                    return .loading
                }

                if modelLoaded {
                    logger.info("Health check: model ready, device=\(health.device)")
                    return .ready
                } else {
                    return .notLoaded
                }
            }

            // Check tier-based format
            if let tiers = health.tiers {
                let anyLoaded = tiers.values.contains { $0.loaded }
                let loadedTiers = tiers.filter { $0.value.loaded }.map { $0.key }
                logger.info("Health check: tiers=\(loadedTiers), device=\(health.device)")
                return anyLoaded ? .ready : .notLoaded
            }

            // Legacy format
            if let modelsLoaded = health.models_loaded {
                let anyLoaded = modelsLoaded.values.contains(true)
                logger.info("Health check: models=\(health.available_models ?? []), anyLoaded=\(anyLoaded)")
                return anyLoaded ? .ready : .notLoaded
            }

            // Fallback to available_models
            if let availableModels = health.available_models, !availableModels.isEmpty {
                return .ready
            }

            return .notLoaded

        } catch {
            logger.debug("Health check failed: \(error.localizedDescription)")
            return .unreachable
        }
    }

    private func startHealthMonitoring() {
        healthCheckTask?.cancel()

        healthCheckTask = Task {
            var consecutiveFailures = 0
            let maxFailuresBeforeRestart = 2

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds (faster checks)

                guard !Task.isCancelled else { break }

                let healthy = await checkServerHealth()

                await MainActor.run {
                    if healthy {
                        consecutiveFailures = 0
                        if self.serverState == .failed("Server connection lost") {
                            // Server recovered
                            self.serverState = .running
                            self.statusMessage = "Server running on port \(self.port)"
                        }
                    } else if self.serverState == .running {
                        consecutiveFailures += 1
                        logger.warning("Server health check failed (\(consecutiveFailures)/\(maxFailuresBeforeRestart))")

                        if consecutiveFailures >= maxFailuresBeforeRestart {
                            logger.error("Server appears to have crashed, attempting auto-restart...")
                            self.serverState = .failed("Server connection lost - restarting...")
                            self.statusMessage = "Restarting server..."

                            // Trigger auto-restart
                            Task {
                                await self.autoRestart()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Auto-restart the server after a crash
    private func autoRestart() async {
        // Stop any existing process
        if let process = serverProcess, process.isRunning {
            process.terminate()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            if process.isRunning {
                process.interrupt()
            }
        }
        serverProcess = nil

        // Wait a moment before restarting
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Restart the server
        logger.info("Auto-restarting server...")
        await startServer()
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
