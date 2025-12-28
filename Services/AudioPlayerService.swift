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
    func loadAudio(samples: [Float], sampleRate: Int = TTSService.sampleRate) throws {
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
        player.play()
        isPlaying = true
        startProgressTimer()
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
        // Use Combine Timer for reliable main-thread updates at 60fps
        timerCancellable = Timer.publish(every: 1.0/60.0, on: .main, in: .common)
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

    /// Creates WAV file data from PCM samples
    private func createWAVData(from samples: [Float], sampleRate: Int) -> Data {
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(channels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(channels * bitsPerSample / 8)
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var data = Data()

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

        // Convert Float samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
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
