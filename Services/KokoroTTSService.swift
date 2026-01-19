import Foundation
import os.log
import MLXAudio
import MLX

private let logger = Logger(subsystem: "com.murmur.app", category: "KokoroTTS")

/// Errors that can occur during TTS operations
enum KokoroTTSError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case invalidVoice
    case generationCancelled
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Voice model is not loaded. Please wait for initialization."
        case .generationFailed(let reason):
            return "Failed to generate speech: \(reason)"
        case .invalidVoice:
            return "Invalid voice selected."
        case .generationCancelled:
            return "Generation was cancelled."
        case .modelLoadFailed(let reason):
            return "Failed to load voice model: \(reason)"
        }
    }
}

// KokoroVoice language extension is defined in Models/Language.swift

/// Native Swift TTS Service using mlx-audio KokoroTTS
/// Replaces the Python-based TTSService with direct Swift MLX implementation
@MainActor
final class KokoroTTSService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadingProgress: Double = 0.0
    @Published private(set) var loadingMessage: String = ""
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastError: KokoroTTSError?
    @Published private(set) var serverDevice: String = "mps" // Always Metal on Apple Silicon
    @Published var selectedVoiceId: String = "af_bella"

    // MARK: - Voice List (compatible with existing KokoroVoice)

    @Published private(set) var kokoroVoices: [KokoroVoice] = []

    // MARK: - Private Properties

    private var kokoroEngine: KokoroTTS?
    private var currentGenerationTask: Task<[Float], Error>?

    /// Lock to serialize audio generation (mlx-audio has race conditions)
    private let generationLock = NSLock()

    /// Track if we're waiting for generation to complete
    private var isWaitingForGeneration = false

    /// Sample rate for Kokoro output (24kHz)
    static let sampleRate: Int = 24000

    // MARK: - Voice Definitions

    /// All available Kokoro voices with metadata
    private static let voiceDefinitions: [String: (name: String, gender: String, accent: String, description: String)] = [
        // American Female
        "af_heart": ("Heart", "female", "American", "Default voice"),
        "af_alloy": ("Alloy", "female", "American", "Clear and articulate"),
        "af_aoede": ("Aoede", "female", "American", "Melodic tone"),
        "af_bella": ("Bella", "female", "American", "Warm and friendly"),
        "af_jessica": ("Jessica", "female", "American", "Professional"),
        "af_kore": ("Kore", "female", "American", "Youthful energy"),
        "af_nicole": ("Nicole", "female", "American", "Confident"),
        "af_nova": ("Nova", "female", "American", "Modern and fresh"),
        "af_river": ("River", "female", "American", "Calm and flowing"),
        "af_sarah": ("Sarah", "female", "American", "Natural and warm"),
        "af_sky": ("Sky", "female", "American", "Light and airy"),
        // American Male
        "am_adam": ("Adam", "male", "American", "Deep and authoritative"),
        "am_echo": ("Echo", "male", "American", "Resonant"),
        "am_eric": ("Eric", "male", "American", "Professional narrator"),
        "am_fenrir": ("Fenrir", "male", "American", "Strong and bold"),
        "am_liam": ("Liam", "male", "American", "Friendly and approachable"),
        "am_michael": ("Michael", "male", "American", "Trustworthy"),
        "am_onyx": ("Onyx", "male", "American", "Deep and smooth"),
        "am_puck": ("Puck", "male", "American", "Playful"),
        "am_santa": ("Santa", "male", "American", "Jolly and warm"),
        // British Female
        "bf_alice": ("Alice", "female", "British", "Elegant"),
        "bf_emma": ("Emma", "female", "British", "Classic British"),
        "bf_isabella": ("Isabella", "female", "British", "Refined"),
        "bf_lily": ("Lily", "female", "British", "Soft and gentle"),
        // British Male
        "bm_daniel": ("Daniel", "male", "British", "Distinguished"),
        "bm_fable": ("Fable", "male", "British", "Storyteller"),
        "bm_george": ("George", "male", "British", "Classic gentleman"),
        "bm_lewis": ("Lewis", "male", "British", "Warm British"),
        // Japanese
        "jf_alpha": ("Alpha", "female", "Japanese", "Clear Japanese"),
        "jf_gongitsune": ("Gongitsune", "female", "Japanese", "Traditional"),
        "jf_nezumi": ("Nezumi", "female", "Japanese", "Soft and gentle"),
        "jf_tebukuro": ("Tebukuro", "female", "Japanese", "Warm"),
        "jm_kumo": ("Kumo", "male", "Japanese", "Deep Japanese"),
        // Chinese
        "zf_xiaobei": ("Xiaobei", "female", "Chinese", "Mandarin Chinese"),
        "zf_xiaoni": ("Xiaoni", "female", "Chinese", "Soft Mandarin"),
        "zf_xiaoxiao": ("Xiaoxiao", "female", "Chinese", "Natural Mandarin"),
        "zf_xiaoyi": ("Xiaoyi", "female", "Chinese", "Clear Mandarin"),
        "zm_yunjian": ("Yunjian", "male", "Chinese", "Professional Mandarin"),
        "zm_yunxi": ("Yunxi", "male", "Chinese", "Warm Mandarin"),
        "zm_yunxia": ("Yunxia", "male", "Chinese", "Deep Mandarin"),
        "zm_yunyang": ("Yunyang", "male", "Chinese", "Natural Mandarin"),
        // Spanish
        "ef_dora": ("Dora", "female", "Spanish", "Native Spanish"),
        "em_alex": ("Alex", "male", "Spanish", "Native Spanish"),
        // French
        "ff_siwis": ("Siwis", "female", "French", "French female"),
        // Hindi
        "hf_alpha": ("Alpha (HI)", "female", "Hindi", "Hindi female"),
        "hf_beta": ("Beta (HI)", "female", "Hindi", "Hindi female alt"),
        "hf_omega": ("Omega (HI)", "female", "Hindi", "Hindi female omega"),
        "hm_psi": ("Psi (HI)", "male", "Hindi", "Hindi male"),
        // Italian
        "if_sara": ("Sara (IT)", "female", "Italian", "Italian female"),
        "im_nicola": ("Nicola", "male", "Italian", "Italian male"),
        // Portuguese
        "pf_dora": ("Dora (PT)", "female", "Portuguese", "Brazilian Portuguese"),
        "pm_alex": ("Alex (PT)", "male", "Portuguese", "Brazilian Portuguese male"),
        "pm_santa": ("Santa (PT)", "male", "Portuguese", "Portuguese male"),
    ]

    /// Map string voice IDs to TTSVoice enum
    private static let voiceMapping: [String: TTSVoice] = [
        // American Female
        "af_heart": .afHeart,
        "af_alloy": .afAlloy,
        "af_aoede": .afAoede,
        "af_bella": .afBella,
        "af_jessica": .afJessica,
        "af_kore": .afKore,
        "af_nicole": .afNicole,
        "af_nova": .afNova,
        "af_river": .afRiver,
        "af_sarah": .afSarah,
        "af_sky": .afSky,
        // American Male
        "am_adam": .amAdam,
        "am_echo": .amEcho,
        "am_eric": .amEric,
        "am_fenrir": .amFenrir,
        "am_liam": .amLiam,
        "am_michael": .amMichael,
        "am_onyx": .amOnyx,
        "am_puck": .amPuck,
        "am_santa": .amSanta,
        // British Female
        "bf_alice": .bfAlice,
        "bf_emma": .bfEmma,
        "bf_isabella": .bfIsabella,
        "bf_lily": .bfLily,
        // British Male
        "bm_daniel": .bmDaniel,
        "bm_fable": .bmFable,
        "bm_george": .bmGeorge,
        "bm_lewis": .bmLewis,
        // Japanese
        "jf_alpha": .jfAlpha,
        "jf_gongitsune": .jfGongitsune,
        "jf_nezumi": .jfNezumi,
        "jf_tebukuro": .jfTebukuro,
        "jm_kumo": .jmKumo,
        // Chinese
        "zf_xiaobei": .zfXiaobei,
        "zf_xiaoni": .zfXiaoni,
        "zf_xiaoxiao": .zfXiaoxiao,
        "zf_xiaoyi": .zfXiaoyi,
        "zm_yunjian": .zmYunjian,
        "zm_yunxi": .zmYunxi,
        "zm_yunxia": .zmYunxia,
        "zm_yunyang": .zmYunyang,
        // Spanish
        "ef_dora": .efDora,
        "em_alex": .emAlex,
        // French
        "ff_siwis": .ffSiwis,
        // Hindi
        "hf_alpha": .hfAlpha,
        "hf_beta": .hfBeta,
        "hf_omega": .hfOmega,
        "hm_psi": .hmPsi,
        // Italian
        "if_sara": .ifSara,
        "im_nicola": .imNicola,
        // Portuguese
        "pf_dora": .pfDora,
        "pm_santa": .pmSanta,
    ]

    /// Convert string voice ID to TTSVoice enum
    private func voiceEnum(from id: String) -> TTSVoice {
        Self.voiceMapping[id] ?? .afBella
    }

    // MARK: - Initialization

    init() {
        // Populate voice list
        populateVoiceList()
    }

    private func populateVoiceList() {
        kokoroVoices = Self.voiceDefinitions.map { id, info in
            KokoroVoice(
                id: id,
                name: info.name,
                gender: info.gender,
                accent: info.accent,
                description: info.description
            )
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Model Loading

    /// Load the Kokoro model - called to check/initialize the model
    func loadModel() async throws {
        guard !isLoading else { return }
        guard !isModelLoaded else { return }

        isLoading = true
        loadingProgress = 0.0
        loadingMessage = "Initializing voice engine..."
        lastError = nil

        defer {
            isLoading = false
        }

        do {
            logger.info("Loading Kokoro TTS model...")

            // Check for bundled model
            guard let modelURL = bundledModelURL else {
                throw KokoroTTSError.modelLoadFailed("Voice model not found. Please reinstall the app.")
            }

            loadingMessage = "Loading voice model..."
            loadingProgress = 0.3

            // Create KokoroTTS with bundled model path
            kokoroEngine = KokoroTTS(customURL: modelURL)
            logger.info("Using bundled model at: \(modelURL.path)")

            loadingProgress = 0.8
            loadingProgress = 0.9
            loadingMessage = "Finalizing..."

            // Small delay for UI smoothness
            try? await Task.sleep(nanoseconds: 200_000_000)

            isModelLoaded = true
            loadingProgress = 1.0
            loadingMessage = "Ready"

            logger.info("Kokoro TTS model loaded successfully")

        } catch let error as KokoroTTSError {
            logger.error("Failed to load Kokoro model: \(error.localizedDescription)")
            lastError = error
            throw error
        } catch {
            logger.error("Failed to load Kokoro model: \(error.localizedDescription)")
            let ttsError = KokoroTTSError.modelLoadFailed(error.localizedDescription)
            lastError = ttsError
            throw ttsError
        }
    }

    /// Get bundled model URL if available
    private var bundledModelURL: URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let modelDir = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("KokoroModel")

        // Check for kokoro-v1_0.safetensors (the expected file name)
        let modelFile = modelDir.appendingPathComponent("kokoro-v1_0.safetensors")

        if FileManager.default.fileExists(atPath: modelFile.path) {
            logger.info("Found bundled model at: \(modelFile.path)")
            return modelFile
        }

        // Also check for model.safetensors (alternate naming)
        let altModelFile = modelDir.appendingPathComponent("model.safetensors")
        if FileManager.default.fileExists(atPath: altModelFile.path) {
            logger.info("Found bundled model (alt) at: \(altModelFile.path)")
            return altModelFile
        }

        logger.info("No bundled model found in KokoroModel directory")
        return nil
    }

    func unloadModel() {
        kokoroEngine?.resetModel()
        kokoroEngine = nil
        isModelLoaded = false
    }

    /// Check if server is healthy (for compatibility - always returns true when model loaded)
    func ensureReady() async -> Bool {
        if isModelLoaded {
            return true
        }

        do {
            try await loadModel()
            return isModelLoaded
        } catch {
            return false
        }
    }

    /// Refresh voices (for compatibility - voices are static)
    func refreshVoices() async {
        populateVoiceList()
    }

    // MARK: - Language Support

    /// Get all native voices for a specific language (internal)
    private func nativeVoices(for language: Language) -> [KokoroVoice] {
        kokoroVoices.filter { $0.language == language }
    }

    /// Get the default native voice for a language (internal)
    private func defaultNativeVoice(for language: Language) -> KokoroVoice? {
        let languageVoices = nativeVoices(for: language)
        return languageVoices.first { $0.gender == "female" } ?? languageVoices.first
    }

    /// Get the currently selected voice's language
    var selectedVoiceLanguage: Language? {
        kokoroVoices.first { $0.id == selectedVoiceId }?.language
    }

    /// Get available languages based on loaded voices
    var availableLanguages: [Language] {
        let languages = Set(kokoroVoices.compactMap { $0.language })
        return Language.allCases.filter { languages.contains($0) }
    }

    /// Switch to a voice for the specified language
    func switchToLanguage(_ language: Language) {
        if let voice = defaultNativeVoice(for: language) {
            selectedVoiceId = voice.id
        }
    }

    // MARK: - Speech Generation

    /// Cancel any ongoing generation
    func cancelGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isGenerating = false
    }

    /// Generate speech from text - returns Float samples compatible with existing AudioPlayerService
    func generate(
        text: String,
        voice: Voice? = nil,
        speed: Float = 1.0,
        voiceSettings: VoiceSettings = .default
    ) async throws -> [Float] {
        guard isModelLoaded else {
            throw KokoroTTSError.modelNotLoaded
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return []
        }

        // Wait for any previous generation to complete (mlx-audio has race conditions)
        if isWaitingForGeneration {
            logger.info("Waiting for previous generation to complete...")
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if !isWaitingForGeneration {
                    break
                }
            }
        }

        isGenerating = true
        isWaitingForGeneration = true
        lastError = nil

        defer {
            Task { @MainActor in
                self.isGenerating = false
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms cooldown
                self.isWaitingForGeneration = false
            }
        }

        // Determine voice
        let voiceId = voice?.id == "default" ? selectedVoiceId : (voice?.id ?? selectedVoiceId)
        let ttsVoice = voiceEnum(from: voiceId)

        logger.info("Generating with Kokoro: voice=\(voiceId), speed=\(voiceSettings.pacing)")
        logger.info("Text (\(trimmedText.count) chars): \"\(trimmedText.prefix(100))\"")

        // Split text into sentences to process sequentially
        // This avoids the eSpeak thread-safety crash that occurs when mlx-audio
        // processes multiple sentences in parallel on background threads
        let sentences = splitIntoSentences(trimmedText)
        logger.info("Split into \(sentences.count) sentence(s)")

        var allSamples: [Float] = []
        let silenceSamples = [Float](repeating: 0, count: Int(0.05 * Float(Self.sampleRate))) // 50ms silence between sentences

        for (index, sentence) in sentences.enumerated() {
            let sentenceText = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentenceText.isEmpty else { continue }

            logger.info("Processing sentence \(index + 1)/\(sentences.count): \"\(sentenceText.prefix(50))...\"")

            // WORKAROUND: mlx-audio has internal state issues that cause subsequent sentences
            // to fail after the first few. Recreate engine for EACH sentence to ensure clean state.
            guard let modelURL = bundledModelURL else {
                throw KokoroTTSError.modelNotLoaded
            }
            let freshEngine = KokoroTTS(customURL: modelURL)

            do {
                let samples = try await generateWithEngine(
                    engine: freshEngine,
                    ttsVoice: ttsVoice,
                    text: sentenceText,
                    voiceSettings: VoiceSettings(
                        emotionEnergy: voiceSettings.emotionEnergy,
                        voiceMatchStrength: voiceSettings.voiceMatchStrength,
                        pacing: voiceSettings.pacing,
                        fadeOutLength: 0 // Don't fade individual sentences
                    )
                )

                if !samples.isEmpty {
                    // Check if this is an error tone (880Hz beep from failed phonemization)
                    // This happens when eSpeak fails to process certain characters (e.g., Hindi)
                    if containsErrorTone(samples: samples) {
                        logger.warning("Skipping sentence \(index + 1) - contains error tone (phonemization failed)")
                        // Don't add error tones to output, continue with next sentence
                    } else {
                        allSamples.append(contentsOf: samples)
                        // Add silence between sentences (except after last)
                        if index < sentences.count - 1 {
                            allSamples.append(contentsOf: silenceSamples)
                        }
                    }
                }
            } catch {
                logger.error("Sentence \(index + 1) failed: \(error.localizedDescription)")
                // Continue with other sentences
            }
        }

        if allSamples.isEmpty {
            throw KokoroTTSError.generationFailed("No audio generated")
        }

        // Apply fade-out to final audio
        let finalSamples = applyFadeOut(
            to: allSamples,
            fadeLength: voiceSettings.fadeOutLength,
            sampleRate: Self.sampleRate
        )

        logger.info("Generated total \(finalSamples.count) samples (\(String(format: "%.2f", Double(finalSamples.count) / Double(Self.sampleRate)))s)")

        return finalSamples
    }

    /// Split text into sentences for sequential processing
    private func splitIntoSentences(_ text: String) -> [String] {
        // Preprocess text to handle problematic characters for eSpeak
        let processedText = preprocessTextForTTS(text)

        // Use a simple sentence splitter that handles common cases
        var sentences: [String] = []
        var currentSentence = ""

        // Include Hindi danda (।) and double danda (॥) for Devanagari
        let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？", "।", "॥"]
        let quoteChars: Set<Character> = ["\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]

        for char in processedText {
            currentSentence.append(char)

            if sentenceEnders.contains(char) {
                // Check if this might be an abbreviation (e.g., "Mr.", "Dr.")
                let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                let lastWord = trimmed.split(separator: " ").last.map(String.init) ?? ""

                // Common abbreviations to ignore
                let abbreviations = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "vs", "etc", "inc", "ltd", "co"]
                let isAbbreviation = abbreviations.contains(lastWord.lowercased().replacingOccurrences(of: ".", with: ""))

                if !isAbbreviation {
                    // Include any trailing quotes
                    let nextIndex = processedText.index(after: processedText.index(processedText.startIndex, offsetBy: currentSentence.count - 1, limitedBy: processedText.endIndex) ?? processedText.endIndex)
                    if nextIndex < processedText.endIndex && quoteChars.contains(processedText[nextIndex]) {
                        continue // Wait for the quote
                    }

                    sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
                    currentSentence = ""
                }
            }
        }

        // Add any remaining text as final sentence
        let remaining = currentSentence.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        // If no sentences were found, return the whole text as one
        if sentences.isEmpty {
            sentences = [processedText]
        }

        return sentences
    }

    /// Preprocess text to handle characters that may cause eSpeak issues
    private func preprocessTextForTTS(_ text: String) -> String {
        var result = text

        // Replace problematic Unicode characters that can cause eSpeak to fail
        // These replacements help prevent phonemization failures

        // Replace various dash types with simple hyphen
        result = result.replacingOccurrences(of: "–", with: "-")  // en-dash
        result = result.replacingOccurrences(of: "—", with: "-")  // em-dash
        result = result.replacingOccurrences(of: "−", with: "-")  // minus sign

        // Replace smart quotes with simple quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")  // left double quote
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")  // right double quote
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")   // left single quote
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")   // right single quote

        // Replace ellipsis with three periods
        result = result.replacingOccurrences(of: "…", with: "...")

        // Remove zero-width characters that can cause issues
        result = result.replacingOccurrences(of: "\u{200B}", with: "")  // zero-width space
        result = result.replacingOccurrences(of: "\u{200C}", with: "")  // zero-width non-joiner
        result = result.replacingOccurrences(of: "\u{200D}", with: "")  // zero-width joiner
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")  // BOM

        // Normalize whitespace
        result = result.replacingOccurrences(of: "\t", with: " ")
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // Remove multiple consecutive spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result
    }

    /// Internal generation method with a specific engine instance
    private func generateWithEngine(
        engine: KokoroTTS,
        ttsVoice: TTSVoice,
        text: String,
        voiceSettings: VoiceSettings
    ) async throws -> [Float] {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Use continuation to properly await the async callback-based API
        // The mlx-audio generateAudio method runs asynchronously and sends callbacks
        let allSamples: [Float] = try await withCheckedThrowingContinuation { continuation in
                var samples: [Float] = []
                var hasResumed = false
                let lock = NSLock()
                var receivedCallbacks = 0
                var totalSamplesReceived = 0
                var completionTimer: DispatchWorkItem?
                var noCallbackTimer: DispatchWorkItem?
                let generationStartTime = CFAbsoluteTimeGetCurrent()

                func resumeWith(result: Result<[Float], Error>) {
                    lock.lock()
                    guard !hasResumed else {
                        lock.unlock()
                        return
                    }
                    hasResumed = true
                    completionTimer?.cancel()
                    noCallbackTimer?.cancel()
                    let finalSamples = samples
                    lock.unlock()

                    switch result {
                    case .success:
                        continuation.resume(returning: finalSamples)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                func scheduleCompletion() {
                    completionTimer?.cancel()
                    let workItem = DispatchWorkItem {
                        lock.lock()
                        let sampleCount = samples.count
                        let callbackCount = receivedCallbacks
                        lock.unlock()

                        logger.info("Completion timer fired: \(callbackCount) callbacks, \(sampleCount) samples")

                        if sampleCount > 0 {
                            resumeWith(result: .success([]))
                        } else {
                            // No samples received - this is an error
                            logger.error("No audio samples received after \(callbackCount) callbacks")
                            resumeWith(result: .failure(KokoroTTSError.generationFailed("No audio data generated")))
                        }
                    }
                    completionTimer = workItem
                    // Wait 1.5 seconds after the last callback to ensure all chunks are received
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
                }

                do {
                    logger.info("Calling generateAudio...")

                    try engine.generateAudio(
                        voice: ttsVoice,
                        text: text,
                        speed: voiceSettings.pacing
                    ) { audioChunk in
                        // Convert audio chunk to [Float]
                        let chunkSamples: [Float] = audioChunk.asArray(Float.self)
                        let chunkTime = CFAbsoluteTimeGetCurrent() - generationStartTime

                        lock.lock()
                        samples.append(contentsOf: chunkSamples)
                        receivedCallbacks += 1
                        totalSamplesReceived += chunkSamples.count
                        let currentCallbacks = receivedCallbacks
                        let currentTotal = totalSamplesReceived
                        lock.unlock()

                        logger.debug("Callback #\(currentCallbacks) at \(String(format: "%.2f", chunkTime))s: +\(chunkSamples.count) samples (total: \(currentTotal))")

                        // Cancel no-callback timer since we got a callback
                        noCallbackTimer?.cancel()
                        noCallbackTimer = nil

                        // Schedule completion after receiving chunks
                        scheduleCompletion()
                    }

                    logger.info("generateAudio returned, waiting for callbacks...")

                    // If no callbacks received within 5 seconds, something is wrong
                    let noCallbackWork = DispatchWorkItem {
                        lock.lock()
                        let callbackCount = receivedCallbacks
                        lock.unlock()

                        if callbackCount == 0 {
                            logger.error("No callbacks received within 5 seconds")
                            resumeWith(result: .failure(KokoroTTSError.generationFailed("Generation timed out - no audio produced")))
                        }
                    }
                    noCallbackTimer = noCallbackWork
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: noCallbackWork)

                    // Safety timeout - max 90 seconds for very long text
                    DispatchQueue.main.asyncAfter(deadline: .now() + 90.0) {
                        lock.lock()
                        let sampleCount = samples.count
                        lock.unlock()

                        logger.warning("Safety timeout reached with \(sampleCount) samples")
                        resumeWith(result: .success([]))
                    }

                } catch {
                    logger.error("generateAudio threw: \(error.localizedDescription)")
                    resumeWith(result: .failure(error))
                }
            }

            let generationTime = CFAbsoluteTimeGetCurrent() - startTime
            let duration = Double(allSamples.count) / Double(Self.sampleRate)

            logger.info("Generated \(allSamples.count) samples (\(String(format: "%.2f", duration))s) in \(String(format: "%.2f", generationTime))s")

            // Check if we actually got audio
            if allSamples.isEmpty {
                throw KokoroTTSError.generationFailed("No audio was generated")
            }

            // Apply fade-out if configured
            let finalSamples = applyFadeOut(
                to: allSamples,
                fadeLength: voiceSettings.fadeOutLength,
                sampleRate: Self.sampleRate
            )

            return finalSamples
    }

    /// Generate audio for multiple text chunks and combine into single output
    func generateChunked(
        chunks: [String],
        voice: Voice? = nil,
        speed: Float = 1.0,
        voiceSettings: VoiceSettings = .default,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [Float] {
        guard isModelLoaded else {
            throw KokoroTTSError.modelNotLoaded
        }

        guard !chunks.isEmpty else {
            return []
        }

        isGenerating = true
        lastError = nil

        defer {
            Task { @MainActor in
                self.isGenerating = false
            }
        }

        var allSamples: [Float] = []
        let totalChunks = chunks.count

        // Silence between chunks (0.3 seconds)
        let silenceSamples = [Float](repeating: 0, count: Int(0.3 * Float(Self.sampleRate)))

        for (index, chunk) in chunks.enumerated() {
            // Check for cancellation
            try Task.checkCancellation()

            // Report progress
            await MainActor.run {
                onProgress?(index, totalChunks)
            }

            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else { continue }

            logger.info("Generating chunk \(index + 1)/\(totalChunks): \"\(trimmedChunk.prefix(30))...\"")

            do {
                let samples = try await generate(
                    text: trimmedChunk,
                    voice: voice,
                    speed: speed,
                    voiceSettings: VoiceSettings(
                        emotionEnergy: voiceSettings.emotionEnergy,
                        voiceMatchStrength: voiceSettings.voiceMatchStrength,
                        pacing: voiceSettings.pacing,
                        fadeOutLength: 0 // Don't fade individual chunks
                    )
                )

                allSamples.append(contentsOf: samples)

                // Add silence between chunks (except after last chunk)
                if index < totalChunks - 1 {
                    allSamples.append(contentsOf: silenceSamples)
                }

            } catch {
                logger.error("Failed to generate chunk \(index + 1): \(error.localizedDescription)")
                throw error
            }
        }

        // Apply fade-out to the final combined audio
        let finalSamples = applyFadeOut(
            to: allSamples,
            fadeLength: voiceSettings.fadeOutLength,
            sampleRate: Self.sampleRate
        )

        // Report completion
        await MainActor.run {
            onProgress?(totalChunks, totalChunks)
        }

        logger.info("Generated combined audio: \(finalSamples.count) samples (\(String(format: "%.1f", Double(finalSamples.count) / Double(Self.sampleRate)))s)")

        return finalSamples
    }

    // MARK: - Audio Processing

    /// Detect if audio contains error tones (880Hz beeps from failed phonemization)
    /// mlx-audio generates these when eSpeak fails to process certain characters
    private func containsErrorTone(samples: [Float], originalTextLength: Int = 0) -> Bool {
        // Error tones from mlx-audio are exactly 4800 samples (0.2s at 24kHz)
        // Only filter these specific error tones, not short but valid audio
        let errorToneSampleCount = 4800
        let tolerance = 100  // Allow small variance

        // If the audio is exactly the error tone length, check if it's actually an error tone
        if abs(samples.count - errorToneSampleCount) < tolerance {
            let duration = Double(samples.count) / Double(Self.sampleRate)
            logger.warning("Detected likely error tone: exactly \(samples.count) samples (\(String(format: "%.2f", duration))s)")
            return true
        }

        // For longer audio, check if it's a sustained error tone
        guard samples.count > 1000 else { return false }

        // 880Hz at 24000Hz sample rate = ~27.3 samples per cycle
        // Error tones are characterized by:
        // 1. Very regular periodic signal
        // 2. Consistent amplitude throughout
        // 3. Frequency close to 880Hz

        // Check a segment from the middle of the audio
        let segmentStart = samples.count / 4
        let segmentLength = min(4800, samples.count / 2) // 0.2 seconds
        let segment = Array(samples[segmentStart..<(segmentStart + segmentLength)])

        // Count zero crossings to estimate frequency
        var zeroCrossings = 0
        for i in 1..<segment.count {
            if (segment[i-1] >= 0 && segment[i] < 0) || (segment[i-1] < 0 && segment[i] >= 0) {
                zeroCrossings += 1
            }
        }

        // Estimated frequency = (zero crossings / 2) / (segment duration)
        let segmentDuration = Double(segmentLength) / Double(Self.sampleRate)
        let estimatedFrequency = Double(zeroCrossings / 2) / segmentDuration

        // Check if frequency is close to 880Hz (allowing ±100Hz tolerance)
        let isErrorFrequency = estimatedFrequency > 780 && estimatedFrequency < 980

        if isErrorFrequency {
            // Additional check: error tones have very consistent amplitude (low variance)
            let mean = segment.reduce(0, +) / Float(segment.count)
            let variance = segment.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(segment.count)
            let absMax = segment.map { abs($0) }.max() ?? 0

            // Error tones have specific characteristics:
            // - Moderate amplitude (not silence, not clipping)
            // - Regular waveform (moderate variance for a sine-like wave)
            let isErrorAmplitude = absMax > 0.05 && absMax < 0.95
            let normalizedVariance = variance / (absMax * absMax + 0.0001)
            let isRegularWave = normalizedVariance > 0.15 && normalizedVariance < 0.7

            if isErrorAmplitude && isRegularWave {
                logger.warning("Detected error tone: freq=\(String(format: "%.0f", estimatedFrequency))Hz, amp=\(String(format: "%.2f", absMax)), samples=\(samples.count)")
                return true
            }
        }

        return false
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

// MARK: - Type Alias for Compatibility

/// Type alias to allow gradual migration from TTSService to KokoroTTSService
/// Once migration is complete, references to KokoroVoice can be updated to KokoroVoice
typealias KokoroNativeVoice = KokoroVoice
