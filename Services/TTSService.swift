import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "TTS")

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
            return "TTS model is not loaded. Please wait for Kokoro to initialize."
        case .generationFailed(let reason):
            return "Failed to generate speech: \(reason)"
        case .serverNotRunning:
            return "TTS server is not running. Please restart the app."
        case .invalidResponse:
            return "Invalid response from TTS server."
        case .generationTimeout:
            return "Speech generation timed out."
        }
    }
}

/// Request payload for TTS generation (Kokoro format)
private struct TTSRequest: Encodable {
    let text: String
    let voice: String
    let speed: Float
}

/// Response from Kokoro TTS server
private struct TTSResponse: Decodable {
    let audio: String        // Base64 encoded WAV
    let sample_rate: Int
    let duration: Double
    let generation_time: Double
    let real_time_factor: Double
}

/// Health check response from Kokoro server
private struct HealthResponse: Decodable {
    let status: String
    let model_loaded: Bool
    let model_loading: Bool?
    let load_error: String?
    let device: String
    let sample_rate: Int?
    let voices_count: Int?
}

/// Voice info from Kokoro server
struct KokoroVoice: Decodable, Identifiable {
    let id: String
    let name: String
    let gender: String
    let accent: String
    let description: String
}

/// Service for text-to-speech generation using Kokoro via HTTP
@MainActor
final class TTSService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastError: TTSError?
    @Published private(set) var serverDevice: String = "unknown"
    @Published private(set) var kokoroVoices: [KokoroVoice] = []
    @Published var selectedVoiceId: String = "af_bella"

    // MARK: - Private Properties

    private let serverURL: URL
    private let session: URLSession
    private var currentGenerationTask: Task<[Float], Error>?

    /// Sample rate for generated audio (Kokoro outputs 24kHz)
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

    /// Check if the TTS server is running and model is loaded
    func loadModel() async throws {
        guard !isLoading else { return }

        isLoading = true
        downloadProgress = 0.0
        lastError = nil

        defer { isLoading = false }

        logger.info("Checking Kokoro TTS server status...")

        do {
            let health = try await checkServerHealth()

            if health.model_loaded {
                isModelLoaded = true
                serverDevice = health.device
                downloadProgress = 1.0

                // Fetch available voices
                await fetchVoices()

                logger.info("Kokoro TTS connected on \(health.device)")
            } else if health.model_loading == true {
                logger.info("Server running, model is loading...")
                lastError = .modelNotLoaded
                throw TTSError.modelNotLoaded
            } else {
                logger.warning("Server running but model not loaded")
                lastError = .modelNotLoaded
                throw TTSError.modelNotLoaded
            }
        } catch let error as TTSError {
            lastError = error
            throw error
        } catch {
            logger.error("Failed to connect to Kokoro server: \(error.localizedDescription)")
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

    private func fetchVoices() async {
        do {
            let url = serverURL.appendingPathComponent("voices")
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            self.kokoroVoices = try JSONDecoder().decode([KokoroVoice].self, from: data)
            logger.info("Loaded \(self.kokoroVoices.count) Kokoro voices")
        } catch {
            logger.warning("Failed to fetch voices: \(error.localizedDescription)")
        }
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
        voice: Voice? = nil,
        speed: Float = 1.0,
        voiceSettings: VoiceSettings = .default
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

        defer {
            Task { @MainActor in
                self.isGenerating = false
            }
        }

        // Use provided voice or selected voice
        let voiceId = voice?.id == "default" ? selectedVoiceId : (voice?.id ?? selectedVoiceId)

        logger.info("Generating with Kokoro: voice=\(voiceId), speed=\(voiceSettings.pacing)")
        logger.info("Text: \"\(trimmedText.prefix(50))...\"")

        do {
            let requestBody = TTSRequest(
                text: trimmedText,
                voice: voiceId,
                speed: voiceSettings.pacing
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
            guard let audioData = Data(base64Encoded: ttsResponse.audio) else {
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

            let speedStr = String(format: "%.1f", ttsResponse.duration / ttsResponse.generation_time)
            logger.info("Generated \(ttsResponse.duration)s audio in \(String(format: "%.2f", ttsResponse.generation_time))s (\(speedStr)x real-time)")
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
