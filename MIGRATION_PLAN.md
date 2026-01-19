# Migration Plan: Python Server → Native Swift MLX

## Implementation Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1: Package Dependencies | **Pending** | Need to add mlx-audio-swift package |
| Phase 2: KokoroTTSService | **DONE** | Created `Services/KokoroTTSService.swift` |
| Phase 3: ModelSetupView | **DONE** | Created `Views/ModelSetupView.swift` |
| Phase 4: MurmurApp Updates | **DONE** | Updated with feature flag |
| Phase 5: Build & Test | **DONE** | Project builds successfully |
| Phase 6: Delete Python Files | **Pending** | Wait until migration tested |
| Phase 7: Build Configuration | **DONE** | Updated `project.yml` |
| Phase 8: Final Testing | **Pending** | Test with real mlx-audio package |

### Files Created
- `Services/KokoroTTSService.swift` - Native Swift TTS service
- `Services/KokoroTTSStubs.swift` - Placeholder types (delete after adding mlx-audio-swift)
- `Views/ModelSetupView.swift` - Simplified setup view

### Files Modified
- `MurmurApp.swift` - Added feature flag and dual-path support
- `project.yml` - Added package dependency comments, excluded migration files

### Build Status
**BUILD SUCCEEDED** - Project compiles with 0 errors, only Swift 6 compatibility warnings

### Next Steps
1. Add the mlx-audio-swift package to Xcode
2. Delete `KokoroTTSStubs.swift`
3. Test with `useNativeTTS = true`
4. After testing works, delete Python-related files

---

## Overview

This plan migrates Murmur from a Python FastAPI server architecture to native Swift using the mlx-audio-swift library. This eliminates the "TTS Server is not Running" errors by removing all Python-related dependencies.

**Current Architecture:**
```
Swift App → HTTP → Python FastAPI → mlx_audio (Python) → MLX
```

**Target Architecture:**
```
Swift App → KokoroTTS (Swift) → MLX
```

---

## Phase 1: Add mlx-audio-swift Dependency

### Step 1.1: Add Swift Package

In Xcode, add the mlx-audio-swift package:

**File: `project.yml` (XcodeGen)**
```yaml
packages:
  MLXAudio:
    url: https://github.com/Blaizzy/mlx-audio
    from: "0.1.0"  # Check for latest version

targets:
  Murmur:
    dependencies:
      - package: MLXAudio
```

Or manually in Xcode:
1. File → Add Package Dependencies
2. URL: `https://github.com/Blaizzy/mlx-audio`
3. Add to Murmur target

### Step 1.2: Verify MLX Dependencies

The mlx-audio-swift package requires:
- MLX framework
- Hub (HuggingFace Swift)

These should be pulled automatically as transitive dependencies.

---

## Phase 2: Create New Native TTS Service

### Step 2.1: Create KokoroTTSService.swift

**New File: `Services/KokoroTTSService.swift`**

```swift
import Foundation
import os.log
import MLXAudio  // or the actual module name from mlx-audio-swift

private let logger = Logger(subsystem: "com.murmur.app", category: "KokoroTTS")

/// Errors that can occur during TTS operations
enum KokoroTTSError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case invalidVoice
    case generationCancelled

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
        }
    }
}

/// Native Swift TTS Service using mlx-audio KokoroTTS
@MainActor
final class KokoroTTSService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadingProgress: Double = 0.0
    @Published private(set) var loadingMessage: String = ""
    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastError: KokoroTTSError?
    @Published var selectedVoiceId: String = "af_bella"

    // MARK: - Private Properties

    private var kokoroEngine: KokoroTTS?
    private var currentGenerationTask: Task<[Float], Error>?

    /// Sample rate for Kokoro output (24kHz)
    static let sampleRate: Int = 24000

    // MARK: - Voice Mapping

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

    init() {}

    // MARK: - Model Loading

    /// Load the Kokoro model
    func loadModel() async throws {
        guard !isLoading else { return }

        isLoading = true
        loadingProgress = 0.0
        loadingMessage = "Initializing voice engine..."
        lastError = nil

        defer {
            isLoading = false
        }

        do {
            logger.info("Loading Kokoro TTS model...")

            // Check for bundled model first
            if let bundledModelURL = bundledModelURL {
                loadingMessage = "Loading bundled model..."
                loadingProgress = 0.3

                kokoroEngine = KokoroTTS(customURL: bundledModelURL)
                logger.info("Using bundled model at: \(bundledModelURL.path)")
            } else {
                // Download from HuggingFace Hub
                loadingMessage = "Downloading voice model..."
                loadingProgress = 0.1

                kokoroEngine = try await KokoroTTS.fromHub(
                    repoId: "mlx-community/Kokoro-82M-bf16",
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.loadingProgress = 0.1 + (progress.fractionCompleted * 0.7)
                        }
                    }
                )
            }

            loadingProgress = 0.9
            loadingMessage = "Finalizing..."

            isModelLoaded = true
            loadingProgress = 1.0
            loadingMessage = "Ready"

            logger.info("Kokoro TTS model loaded successfully")

        } catch {
            logger.error("Failed to load Kokoro model: \(error.localizedDescription)")
            let ttsError = KokoroTTSError.generationFailed(error.localizedDescription)
            lastError = ttsError
            throw ttsError
        }
    }

    /// Get bundled model URL if available
    private var bundledModelURL: URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let modelPath = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("KokoroModel")
            .appendingPathComponent("model.safetensors")

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.deletingLastPathComponent()
        }

        return nil
    }

    func unloadModel() {
        kokoroEngine?.resetModel()
        kokoroEngine = nil
        isModelLoaded = false
    }

    // MARK: - Speech Generation

    /// Cancel any ongoing generation
    func cancelGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isGenerating = false
    }

    /// Generate speech from text
    func generate(
        text: String,
        voice: Voice? = nil,
        speed: Float = 1.0,
        voiceSettings: VoiceSettings = .default
    ) async throws -> [Float] {
        guard isModelLoaded, let engine = kokoroEngine else {
            throw KokoroTTSError.modelNotLoaded
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

        // Determine voice
        let voiceId = voice?.id == "default" ? selectedVoiceId : (voice?.id ?? selectedVoiceId)
        let ttsVoice = voiceEnum(from: voiceId)

        logger.info("Generating with Kokoro: voice=\(voiceId), speed=\(voiceSettings.pacing)")

        do {
            // Generate audio using native Swift Kokoro
            let startTime = CFAbsoluteTimeGetCurrent()

            var allSamples: [Float] = []

            // Use streaming generation with callback
            try engine.generate(
                text: trimmedText,
                voice: ttsVoice,
                speed: voiceSettings.pacing
            ) { audioChunk in
                // Convert MLXArray to [Float]
                let samples = audioChunk.asArray(Float.self)
                allSamples.append(contentsOf: samples)
            }

            let generationTime = CFAbsoluteTimeGetCurrent() - startTime
            let duration = Double(allSamples.count) / Double(Self.sampleRate)

            logger.info("Generated \(String(format: "%.2f", duration))s audio in \(String(format: "%.2f", generationTime))s")

            // Apply fade-out if configured
            let finalSamples = applyFadeOut(
                to: allSamples,
                fadeLength: voiceSettings.fadeOutLength,
                sampleRate: Self.sampleRate
            )

            return finalSamples

        } catch {
            logger.error("Generation error: \(error.localizedDescription)")
            let ttsError = KokoroTTSError.generationFailed(error.localizedDescription)
            lastError = ttsError
            throw ttsError
        }
    }

    /// Generate audio for multiple text chunks
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
            try Task.checkCancellation()

            await MainActor.run {
                onProgress?(index, totalChunks)
            }

            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedChunk.isEmpty else { continue }

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

            if index < totalChunks - 1 {
                allSamples.append(contentsOf: silenceSamples)
            }
        }

        // Apply fade-out to final combined audio
        let finalSamples = applyFadeOut(
            to: allSamples,
            fadeLength: voiceSettings.fadeOutLength,
            sampleRate: Self.sampleRate
        )

        await MainActor.run {
            onProgress?(totalChunks, totalChunks)
        }

        return finalSamples
    }

    // MARK: - Audio Processing

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

    // MARK: - Voice Info (for compatibility)

    /// All available voices
    var availableVoices: [KokoroVoiceInfo] {
        Self.voiceMapping.map { id, voice in
            KokoroVoiceInfo(
                id: id,
                name: voiceName(for: id),
                gender: voiceGender(for: id),
                accent: voiceAccent(for: id),
                description: voiceDescription(for: id)
            )
        }.sorted { $0.id < $1.id }
    }

    private func voiceName(for id: String) -> String {
        let parts = id.split(separator: "_")
        guard parts.count >= 2 else { return id }
        return String(parts[1]).capitalized
    }

    private func voiceGender(for id: String) -> String {
        guard let second = id.dropFirst().first else { return "unknown" }
        return second == "f" ? "female" : "male"
    }

    private func voiceAccent(for id: String) -> String {
        guard let first = id.first else { return "American" }
        switch first {
        case "a": return "American"
        case "b": return "British"
        case "j": return "Japanese"
        case "z": return "Chinese"
        case "e": return "Spanish"
        case "f": return "French"
        case "h": return "Hindi"
        case "i": return "Italian"
        case "p": return "Portuguese"
        default: return "American"
        }
    }

    private func voiceDescription(for id: String) -> String {
        "\(voiceAccent(for: id)) \(voiceGender(for: id)) voice"
    }
}

/// Voice info structure for UI compatibility
struct KokoroVoiceInfo: Identifiable {
    let id: String
    let name: String
    let gender: String
    let accent: String
    let description: String
}
```

---

## Phase 3: Create Simplified Setup View

### Step 3.1: Create ModelSetupView.swift

**New File: `Views/ModelSetupView.swift`**

```swift
import SwiftUI

/// Simplified setup view for native Swift model loading
struct ModelSetupView: View {
    @ObservedObject var ttsService: KokoroTTSService
    let onComplete: () -> Void

    @State private var animateWave = false
    @State private var animatePulse = false

    private let accentTeal = Color(red: 0.0, green: 0.65, blue: 0.68)

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                Spacer()
                brandingSection
                Spacer()
                statusSection
                    .frame(height: 180)
                    .padding(.horizontal, 60)
                Spacer()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            animateWave = true
            animatePulse = true
            await loadModel()
        }
        .onChange(of: ttsService.isModelLoaded) { _, isLoaded in
            if isLoaded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onComplete()
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            RadialGradient(
                colors: [accentTeal.opacity(0.06), Color.clear],
                center: .top,
                startRadius: 100,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Branding

    private var brandingSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentTeal.opacity(0.25), accentTeal.opacity(0.0)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(animatePulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animatePulse)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(accentTeal)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: animateWave)
            }

            VStack(spacing: 8) {
                Text("Murmur")
                    .font(.system(size: 36, weight: .semibold, design: .default))
                Text("Private Voice Generation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Group {
            if let error = ttsService.lastError {
                failedView(error: error.localizedDescription)
            } else if ttsService.isModelLoaded {
                readyView
            } else {
                progressView
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: ttsService.loadingProgress)
                    .stroke(accentTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: ttsService.loadingProgress)

                Text("\(Int(ttsService.loadingProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Text(ttsService.loadingMessage.isEmpty ? "Loading..." : ttsService.loadingMessage)
                    .font(.system(size: 15, weight: .medium))

                if ttsService.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("This only happens once")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var readyView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentTeal.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(accentTeal)
                    .symbolEffect(.bounce, value: ttsService.isModelLoaded)
            }

            Text("You're all set")
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Setup didn't complete")
                    .font(.system(size: 16, weight: .semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { Task { await loadModel() } }) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentTeal)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private func loadModel() async {
        do {
            try await ttsService.loadModel()
        } catch {
            // Error is captured in ttsService.lastError
        }
    }
}
```

---

## Phase 4: Update MurmurApp.swift

### Step 4.1: Remove Python dependencies, use native service

**File: `MurmurApp.swift`**

```swift
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "App")

@main
struct MurmurApp: App {

    @StateObject private var licenseService = LicenseService()
    @StateObject private var ttsService = KokoroTTSService()  // CHANGED: Use native service
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var settingsService = SettingsService()

    @State private var isLicenseValidated = false
    @State private var isCheckingLicense = true
    @State private var isSetupComplete = false

    // REMOVED: pythonEnv, serverManager

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
                    ContentView()
                        .environmentObject(ttsService)
                        .environmentObject(audioPlayerService)
                        .environmentObject(settingsService)
                } else {
                    // CHANGED: Use simplified setup view
                    ModelSetupView(ttsService: ttsService) {
                        withAnimation(.spring(duration: 0.5)) {
                            isSetupComplete = true
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
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .newItem) {
                Button("Open Document...") {
                    NotificationCenter.default.post(name: .openDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
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

            // REMOVED: "Voice" menu with "Restart Voice Engine"
        }

        Settings {
            SettingsView()
                .environmentObject(settingsService)
                .environmentObject(ttsService)
                .environmentObject(licenseService)
        }
    }

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

extension Notification.Name {
    static let generateSpeech = Notification.Name("generateSpeech")
    static let openDocument = Notification.Name("openDocument")
}
```

---

## Phase 5: Update ContentView and Other Files

### Step 5.1: Update ContentView.swift

Replace `TTSService` references with `KokoroTTSService`:

```swift
// Change this:
@EnvironmentObject var ttsService: TTSService

// To this:
@EnvironmentObject var ttsService: KokoroTTSService
```

The API is compatible, so most code will work unchanged.

### Step 5.2: Update AudioPlayerService.swift

```swift
// Change this:
func loadAudio(samples: [Float], sampleRate: Int = TTSService.sampleRate)

// To this:
func loadAudio(samples: [Float], sampleRate: Int = KokoroTTSService.sampleRate)
```

### Step 5.3: Update AudioExportService.swift

```swift
// Change this:
init(sampleRate: Int = TTSService.sampleRate)

// To this:
init(sampleRate: Int = KokoroTTSService.sampleRate)
```

### Step 5.4: Update BatchQueueViewModel.swift

```swift
// Change this:
private let ttsService: TTSService
init(ttsService: TTSService, audioPlayerService: AudioPlayerService)

// To this:
private let ttsService: KokoroTTSService
init(ttsService: KokoroTTSService, audioPlayerService: AudioPlayerService)
```

### Step 5.5: Update SettingsView.swift

```swift
// Change this:
@EnvironmentObject var ttsService: TTSService

// To this:
@EnvironmentObject var ttsService: KokoroTTSService
```

---

## Phase 6: Remove Python-Related Files

### Step 6.1: Delete these files

```
Services/PythonEnvironmentService.swift  ← DELETE
Services/ServerManager.swift             ← DELETE
Services/TTSService.swift                ← DELETE (replaced by KokoroTTSService)
Views/SetupView.swift                    ← DELETE (replaced by ModelSetupView)
Server/kokoro_server.py                  ← DELETE
Server/requirements.txt                  ← DELETE
```

### Step 6.2: Remove from project.yml

Remove these from XcodeGen configuration:
- `Resources/Python/` reference
- `Resources/PythonWheels/` reference
- `Server/` folder reference

### Step 6.3: Remove bundled Python from app

Remove from Resources:
- `Python/` folder (~100MB Python interpreter)
- `PythonWheels/` folder (pip wheels)
- Keep `KokoroModel/` folder (still needed for bundled weights)

---

## Phase 7: Update Build Configuration

### Step 7.1: Update project.yml

```yaml
targets:
  Murmur:
    # Remove Python-related build phases
    # Remove code signing scripts for Python

    dependencies:
      - package: MLXAudio

    settings:
      # Keep existing settings
```

### Step 7.2: Remove Python code signing

In `Scripts/`, remove or update:
- `sign_bundle.sh` - Remove Python signing code
- Any pip/venv related scripts

---

## Phase 8: Testing Checklist

### Functional Tests

- [ ] App launches without Python errors
- [ ] Model loads on first launch (shows progress)
- [ ] Model loads from bundled weights (no download)
- [ ] Voice selection works (all voices available)
- [ ] Speed control works (0.5x - 2.0x)
- [ ] Text generation produces audio
- [ ] Long text chunked generation works
- [ ] Audio playback works
- [ ] Audio export works (all formats)
- [ ] History saving/loading works
- [ ] Batch queue processing works

### Error Handling Tests

- [ ] No more "TTS Server is not Running" errors
- [ ] Model loading failure shows retry button
- [ ] Generation cancellation works
- [ ] App recovers from errors gracefully

### Performance Tests

- [ ] Startup time (should be faster)
- [ ] Generation speed (should be similar)
- [ ] Memory usage (should be lower)
- [ ] App bundle size (should be ~100MB smaller)

---

## File Summary

### Files to ADD
```
Services/KokoroTTSService.swift     (new native TTS service)
Views/ModelSetupView.swift          (new simplified setup view)
```

### Files to MODIFY
```
MurmurApp.swift                     (remove Python deps, use native)
ContentView.swift                   (change TTSService → KokoroTTSService)
Views/SettingsView.swift            (change TTSService → KokoroTTSService)
ViewModels/BatchQueueViewModel.swift (change TTSService → KokoroTTSService)
Services/AudioPlayerService.swift   (change sampleRate reference)
Services/AudioExportService.swift   (change sampleRate reference)
project.yml                         (add MLXAudio package, remove Python)
```

### Files to DELETE
```
Services/PythonEnvironmentService.swift
Services/ServerManager.swift
Services/TTSService.swift
Views/SetupView.swift
Server/kokoro_server.py
Server/requirements.txt
Resources/Python/                   (entire folder)
Resources/PythonWheels/             (entire folder)
```

---

## Rollback Plan

If issues arise, you can rollback by:

1. Revert all file changes via git
2. Keep both `TTSService` and `KokoroTTSService` during transition
3. Use feature flag to switch between implementations
4. Test native implementation thoroughly before removing Python code

---

## Expected Benefits

| Metric | Before (Python) | After (Native) |
|--------|-----------------|----------------|
| App bundle size | ~450MB | ~350MB |
| Startup time | 5-30 seconds | 1-3 seconds |
| Server errors | Common | Eliminated |
| Architecture complexity | High | Low |
| Maintenance burden | High | Low |
