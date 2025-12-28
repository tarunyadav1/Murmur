import Foundation
import Combine

@MainActor
final class PlaybackViewModel: ObservableObject {

    let audioPlayerService: AudioPlayerService

    private var cancellables = Set<AnyCancellable>()

    init(audioPlayerService: AudioPlayerService) {
        self.audioPlayerService = audioPlayerService
    }

    var isPlaying: Bool { audioPlayerService.isPlaying }
    var isReady: Bool { audioPlayerService.isReady }
    var currentTime: TimeInterval { audioPlayerService.currentTime }
    var duration: TimeInterval { audioPlayerService.duration }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentTimeFormatted: String {
        formatTime(currentTime)
    }

    var durationFormatted: String {
        formatTime(duration)
    }

    func play() { audioPlayerService.play() }
    func pause() { audioPlayerService.pause() }
    func stop() { audioPlayerService.stop() }
    func togglePlayPause() { audioPlayerService.togglePlayPause() }

    func seek(to progress: Double) {
        let time = progress * duration
        audioPlayerService.seek(to: time)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
