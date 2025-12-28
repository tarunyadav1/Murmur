import SwiftUI

struct PlaybackControlsView: View {

    @EnvironmentObject var audioPlayerService: AudioPlayerService

    let hasAudio: Bool
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Progress slider
            HStack {
                Text(formatTime(audioPlayerService.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 50)

                Slider(
                    value: Binding(
                        get: { progress },
                        set: { seek(to: $0) }
                    ),
                    in: 0...1
                )
                .disabled(!audioPlayerService.isReady)

                Text(formatTime(audioPlayerService.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 50)
            }

            // Control buttons
            HStack(spacing: 24) {
                Spacer()

                // Stop
                Button(action: { audioPlayerService.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .disabled(!audioPlayerService.isReady)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (Cmd+.)")

                // Play/Pause
                Button(action: { audioPlayerService.togglePlayPause() }) {
                    Image(systemName: audioPlayerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 44, height: 44)
                        .background(audioPlayerService.isReady ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .disabled(!audioPlayerService.isReady)
                .keyboardShortcut(.space, modifiers: [])
                .help("Play/Pause (Space)")

                // Export
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                }
                .disabled(!hasAudio)
                .keyboardShortcut("e", modifiers: .command)
                .help("Export (Cmd+E)")

                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var progress: Double {
        guard audioPlayerService.duration > 0 else { return 0 }
        return audioPlayerService.currentTime / audioPlayerService.duration
    }

    private func seek(to value: Double) {
        let time = value * audioPlayerService.duration
        audioPlayerService.seek(to: time)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
