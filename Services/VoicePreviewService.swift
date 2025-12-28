import Foundation
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "VoicePreview")

/// Simple service for playing voice sample previews
@MainActor
final class VoicePreviewService: ObservableObject {

    static let shared = VoicePreviewService()

    @Published private(set) var currentlyPlayingVoiceId: String?
    @Published private(set) var isPlaying: Bool = false

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    /// Play a voice sample preview
    func play(voice: Voice) {
        // Stop any current playback
        stop()

        guard let sampleURL = voice.sampleURL else {
            logger.warning("No sample URL for voice: \(voice.id)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: sampleURL)
            audioPlayer?.delegate = AudioPlayerDelegateHandler.shared
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            currentlyPlayingVoiceId = voice.id
            isPlaying = true

            // Set up completion handler
            AudioPlayerDelegateHandler.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.currentlyPlayingVoiceId = nil
                }
            }

            logger.info("Playing voice sample: \(voice.id)")
        } catch {
            logger.error("Failed to play voice sample: \(error.localizedDescription)")
        }
    }

    /// Stop current playback
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlayingVoiceId = nil
    }

    /// Toggle play/stop for a voice
    func toggle(voice: Voice) {
        if currentlyPlayingVoiceId == voice.id && isPlaying {
            stop()
        } else {
            play(voice: voice)
        }
    }
}

// Helper class to handle AVAudioPlayerDelegate
private class AudioPlayerDelegateHandler: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerDelegateHandler()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
