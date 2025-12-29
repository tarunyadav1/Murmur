import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "TTS")

/// Available TTS quality tiers
enum TTSTier: String, Codable, CaseIterable, Identifiable {
    case fast = "fast"      // Kokoro 82M - instant generation
    case normal = "normal"  // Chatterbox Turbo 350M - balanced
    case high = "high"      // Chatterbox Standard 500M - best quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .high: return "High Quality"
        }
    }

    var modelInfo: String {
        switch self {
        case .fast: return "Kokoro 82M"
        case .normal: return "Turbo 350M"
        case .high: return "Standard 500M"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Instant generation, perfect for quick drafts"
        case .normal: return "Balanced speed and quality with paralinguistic tags"
        case .high: return "Best quality with emotion and voice matching controls"
        }
    }

    var icon: String {
        switch self {
        case .fast: return "bolt.fill"
        case .normal: return "scale.3d"
        case .high: return "sparkles"
        }
    }

    /// Whether this tier supports exaggeration and cfg_weight parameters
    var supportsEmotionControls: Bool {
        switch self {
        case .fast: return false
        case .normal: return false
        case .high: return true
        }
    }

    /// Whether this tier uses Kokoro voices
    var usesKokoroVoices: Bool {
        self == .fast
    }
}

/// Legacy model enum for backwards compatibility
enum TTSModel: String, Codable {
    case standard = "standard"
    case turbo = "turbo"
}

/// Errors that can occur during TTS operations
enum TTSError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case serverNotRunning
    case invalidResponse
    case generationTimeout

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "TTS model is not loaded. Please start the Chatterbox server."
        case .generationFailed(let reason):
            return "Failed to generate speech: \(reason)"
        case .serverNotRunning:
            return "TTS server is not running. Please start the Chatterbox server."
        case .invalidResponse:
            return "Invalid response from TTS server."
        case .generationTimeout:
            return "Speech generation timed out."
        }
    }
}

/// Request payload for TTS generation
private struct TTSRequest: Encodable {
    let text: String
    let tier: String
    let exaggeration: Float
    let cfg_weight: Float
    let speed: Float
    let voice_id: String?
}

/// Response from TTS server
private struct TTSResponse: Decodable {
    let audio_base64: String
    let sample_rate: Int
    let duration_seconds: Double
    let format: String
    let tier_used: String?
    let model_used: String?
}

/// Tier status from health check
private struct TierStatus: Decodable {
    let available: Bool
    let loaded: Bool
}

/// Health check response
private struct HealthResponse: Decodable {
    let status: String
    let tiers: [String: TierStatus]?
    let device: String
    // Legacy fields
    let models_loaded: [String: Bool]?
    let available_models: [String]
}

/// Service for text-to-speech generation using Chatterbox via HTTP
@MainActor
final class TTSService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastError: TTSError?
    @Published private(set) var serverDevice: String = "unknown"
    @Published private(set) var availableTiers: [TTSTier] = []
    @Published var selectedTier: TTSTier = .fast

    // MARK: - Private Properties

    private let serverURL: URL
    private let session: URLSession
    private var currentGenerationTask: Task<[Float], Error>?

    /// Sample rate for generated audio (Chatterbox outputs 24kHz)
    static let sampleRate: Int = 24000

    // MARK: - Initialization

    init(serverPort: Int = 8787) {
        self.serverURL = URL(string: "http://127.0.0.1:\(serverPort)")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minutes for longer texts
        config.timeoutIntervalForResource = 600 // 10 minutes max
        self.session = URLSession(configuration: config)
    }

    // MARK: - Server Connection

    /// Check if the TTS server is running and at least one tier is loaded
    func loadModel() async throws {
        guard !isLoading else { return }

        isLoading = true
        downloadProgress = 0.0
        lastError = nil

        defer { isLoading = false }

        logger.info("Checking TTS server status...")

        do {
            let health = try await checkServerHealth()

            // Parse available tiers from new format or legacy format
            var available: [TTSTier] = []

            if let tiers = health.tiers {
                // New tier-based format
                for (tierName, status) in tiers {
                    if status.loaded, let tier = TTSTier(rawValue: tierName) {
                        available.append(tier)
                    }
                }
            } else {
                // Legacy format - map to tiers
                for modelName in health.available_models {
                    if let tier = TTSTier(rawValue: modelName) {
                        available.append(tier)
                    } else if modelName == "standard" {
                        available.append(.high)
                    } else if modelName == "turbo" {
                        available.append(.normal)
                    } else if modelName == "kokoro" {
                        available.append(.fast)
                    }
                }
            }

            // Sort tiers by preference (fast first)
            available.sort { $0.rawValue < $1.rawValue }
            availableTiers = available

            if !available.isEmpty {
                isModelLoaded = true
                serverDevice = health.device
                downloadProgress = 1.0

                // Select fast tier if available and currently selected tier isn't available
                if !available.contains(selectedTier) {
                    selectedTier = available.first ?? .fast
                }

                let tierNames = available.map { $0.displayName }.joined(separator: ", ")
                logger.info("TTS server connected, tiers loaded: \(tierNames) on \(health.device)")
            } else {
                logger.warning("Server running but no tiers loaded")
                lastError = .modelNotLoaded
                throw TTSError.modelNotLoaded
            }
        } catch let error as TTSError {
            lastError = error
            throw error
        } catch {
            logger.error("Failed to connect to TTS server: \(error.localizedDescription)")
            lastError = .serverNotRunning
            throw TTSError.serverNotRunning
        }
    }

    private func checkServerHealth() async throws -> HealthResponse {
        let url = serverURL.appendingPathComponent("health")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.serverNotRunning
        }

        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func unloadModel() {
        isModelLoaded = false
    }

    // MARK: - Speech Generation

    /// Cancel any ongoing generation
    func cancelGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isGenerating = false
    }

    func generate(
        text: String,
        voice: Voice,
        speed: Float = 1.0,
        voiceSettings: VoiceSettings = .default,
        tier: TTSTier? = nil
    ) async throws -> [Float] {
        guard isModelLoaded else {
            throw TTSError.modelNotLoaded
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return []
        }

        isGenerating = true
        lastError = nil

        // Use provided tier or the selected tier
        let tierToUse = tier ?? selectedTier

        defer {
            Task { @MainActor in
                self.isGenerating = false
            }
        }

        logger.info("Starting generation with \(tierToUse.displayName) tier: \"\(trimmedText.prefix(50))...\"")
        logger.info("Settings: voice=\(voice.id), emotion=\(voiceSettings.emotionEnergy), cfg=\(voiceSettings.voiceMatchStrength), speed=\(voiceSettings.pacing)")

        do {
            // Determine voice_id based on tier
            let voiceId: String?
            if tierToUse == .fast {
                // For fast tier, use Kokoro voice names or default
                voiceId = voice.id == "default" ? "af_bella" : voice.id
            } else {
                // For normal/high tiers, use Chatterbox voice
                voiceId = voice.id == "default" ? nil : voice.id
            }

            let requestBody = TTSRequest(
                text: trimmedText,
                tier: tierToUse.rawValue,
                exaggeration: voiceSettings.emotionEnergy,
                cfg_weight: voiceSettings.voiceMatchStrength,
                speed: voiceSettings.pacing,
                voice_id: voiceId
            )

            let url = serverURL.appendingPathComponent("generate")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TTSError.generationFailed(errorMessage)
            }

            let ttsResponse = try JSONDecoder().decode(TTSResponse.self, from: data)

            // Decode base64 audio
            guard let audioData = Data(base64Encoded: ttsResponse.audio_base64) else {
                throw TTSError.invalidResponse
            }

            // Convert WAV data to Float samples
            let samples = try extractSamplesFromWAV(audioData)

            // Apply fade-out if configured
            let finalSamples = applyFadeOut(
                to: samples,
                fadeLength: voiceSettings.fadeOutLength,
                sampleRate: ttsResponse.sample_rate
            )

            let tierUsed = ttsResponse.tier_used ?? tierToUse.rawValue
            logger.info("Generated \(finalSamples.count) samples (\(ttsResponse.duration_seconds)s) using \(tierUsed) tier")
            return finalSamples

        } catch let error as TTSError {
            lastError = error
            throw error
        } catch {
            logger.error("Generation error: \(error.localizedDescription)")
            let ttsError = TTSError.generationFailed(error.localizedDescription)
            lastError = ttsError
            throw ttsError
        }
    }

    // MARK: - Audio Processing

    private func extractSamplesFromWAV(_ data: Data) throws -> [Float] {
        // WAV header parsing
        guard data.count > 44 else {
            throw TTSError.invalidResponse
        }

        // Find "data" chunk
        var dataOffset = 12
        while dataOffset < data.count - 8 {
            let chunkID = String(data: data[dataOffset..<dataOffset+4], encoding: .ascii)
            let chunkSize = data.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: dataOffset + 4, as: UInt32.self)
            }

            if chunkID == "data" {
                dataOffset += 8
                break
            }
            dataOffset += 8 + Int(chunkSize)
        }

        guard dataOffset < data.count else {
            throw TTSError.invalidResponse
        }

        // Extract float samples (assuming 16-bit PCM, convert to float)
        let audioData = data[dataOffset...]
        var samples: [Float] = []
        samples.reserveCapacity(audioData.count / 2)

        for i in stride(from: 0, to: audioData.count - 1, by: 2) {
            let index = audioData.startIndex + i
            let low = Int16(audioData[index])
            let high = Int16(audioData[index + 1]) << 8
            let sample = low | high
            samples.append(Float(sample) / 32768.0)
        }

        return samples
    }

    private func applyFadeOut(to samples: [Float], fadeLength: Float, sampleRate: Int) -> [Float] {
        guard fadeLength > 0, !samples.isEmpty else {
            return samples
        }

        var result = samples
        let fadeSamples = min(Int(fadeLength * Float(sampleRate)), samples.count)

        if fadeSamples > 0 {
            let startIndex = samples.count - fadeSamples
            for i in 0..<fadeSamples {
                let fadeMultiplier = Float(fadeSamples - i) / Float(fadeSamples)
                result[startIndex + i] *= fadeMultiplier
            }
        }

        return result
    }
}
