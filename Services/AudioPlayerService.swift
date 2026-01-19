import Foundation
import AVFoundation
import Combine

/// Manages audio playback with seek, pause, and progress tracking
@MainActor
final class AudioPlayerService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isReady: Bool = false
    @Published var playingRecordId: UUID?  // Track which history record is currently loaded
    @Published var playbackSpeed: Float = 1.0

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CVDisplayLink?
    private var timerCancellable: AnyCancellable?
    private var currentSamples: [Float]?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Audio Loading

    /// Loads PCM audio samples for playback
    /// - Parameters:
    ///   - samples: Audio samples as [Float]
    ///   - sampleRate: Sample rate in Hz (default 24000 for Kokoro)
    func loadAudio(samples: [Float], sampleRate: Int = KokoroTTSService.sampleRate) throws {
        stop()

        currentSamples = samples

        // Convert Float samples to WAV data for AVAudioPlayer
        let wavData = createWAVData(from: samples, sampleRate: sampleRate)

        audioPlayer = try AVAudioPlayer(data: wavData)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()

        duration = audioPlayer?.duration ?? 0
        currentTime = 0
        isReady = true
    }

    // MARK: - Playback Controls

    func play() {
        guard let player = audioPlayer, isReady else { return }
        player.enableRate = true
        player.rate = playbackSpeed
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    /// Set playback speed (0.5x to 2x)
    func setSpeed(_ speed: Float) {
        let clampedSpeed = max(0.5, min(2.0, speed))
        playbackSpeed = clampedSpeed
        if let player = audioPlayer {
            player.enableRate = true
            player.rate = clampedSpeed
        }
    }

    /// Skip forward or backward by seconds
    func skip(by seconds: TimeInterval) {
        let newTime = currentTime + seconds
        seek(to: newTime)
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Volume Control

    var volume: Float {
        get { audioPlayer?.volume ?? 1.0 }
        set { audioPlayer?.volume = newValue }
    }

    // MARK: - Progress Tracking

    private func startProgressTimer() {
        stopProgressTimer()
        // Use Combine Timer for reliable main-thread updates at 15fps (sufficient for UI)
        timerCancellable = Timer.publish(every: 1.0/15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
    }

    private func stopProgressTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Audio Access

    /// Returns current audio samples for export
    var audioSamples: [Float]? {
        return currentSamples
    }

    // MARK: - WAV Conversion

    /// Creates WAV file data from PCM samples (optimized for large arrays)
    private func createWAVData(from samples: [Float], sampleRate: Int) -> Data {
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(channels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(channels * bitsPerSample / 8)
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        // Pre-allocate data with exact size needed
        var data = Data(capacity: 44 + samples.count * 2)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert Float samples to Int16 using bulk operation
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            int16Samples[i] = Int16(clamped * Float(Int16.max))
        }

        // Append all samples at once
        int16Samples.withUnsafeBufferPointer { buffer in
            data.append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress!)
                .assumingMemoryBound(to: UInt8.self), count: samples.count * 2))
        }

        return data
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopProgressTimer()
        }
    }
}
