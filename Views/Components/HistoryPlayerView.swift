import SwiftUI
import AppKit

/// Full-featured player view for history records - macOS HIG compliant design
struct HistoryPlayerView: View {
    let record: GenerationRecord
    @ObservedObject var audioPlayerService: AudioPlayerService
    @ObservedObject var historyService: HistoryService
    let onClose: () -> Void
    let onRegenerate: (GenerationRecord) -> Void

    @State private var waveformData: [Float] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showDeleteConfirmation = false

    private let waveformBarCount = 60
    private let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // MARK: - Computed Properties

    private var progress: Double {
        audioPlayerService.duration > 0 ? audioPlayerService.currentTime / audioPlayerService.duration : 0
    }

    private var isThisRecordPlaying: Bool {
        audioPlayerService.playingRecordId == record.id
    }

    private var isPlaying: Bool {
        isThisRecordPlaying && audioPlayerService.isPlaying
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                // Main content - fills available space
                playerContent
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadAudio()
        }
        .onChange(of: record.id) { _, _ in
            // When a different record is selected, stop current audio and load the new one
            audioPlayerService.stop()
            loadAudio()
        }
        .onKeyPress(.space) {
            togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            skipBackward()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            skipForward()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .alert("Delete Recording", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAndClose()
            }
        } message: {
            Text("This will permanently delete this recording from history.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("History")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            // Metadata in toolbar
            HStack(spacing: 8) {
                Image(systemName: "person.wave.2")
                    .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                Text(record.voiceName)
                    .fontWeight(.medium)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(record.displayDate)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Spacer()

            // Actions in toolbar
            HStack(spacing: 12) {
                Button(action: copyText) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy text")

                Button(action: exportAudio) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export audio")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Player Content

    private var playerContent: some View {
        VStack(spacing: 0) {
            // Text display - simple scrolling text without word-by-word highlighting
            // This is much more performant than WrappingHStack with individual word views
            ScrollView {
                Text(record.text)
                    .font(.title2)
                    .lineSpacing(8)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Bottom controls - fixed height
            VStack(spacing: 16) {
                // Waveform
                waveformSection
                    .frame(height: 60)
                    .padding(.horizontal, 24)

                // Time
                HStack {
                    Text(formatTime(audioPlayerService.currentTime))
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(audioPlayerService.duration))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

                // Playback controls
                HStack(spacing: 40) {
                    Button(action: skipBackward) {
                        Image(systemName: "gobackward.5")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button(action: togglePlayPause) {
                        ZStack {
                            Circle()
                                .fill(MurmurDesign.Colors.accentGradient)
                                .frame(width: 64, height: 64)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: skipForward) {
                        Image(systemName: "goforward.5")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                // Speed control
                HStack(spacing: 8) {
                    ForEach(availableSpeeds, id: \.self) { speed in
                        let isSelected = abs(audioPlayerService.playbackSpeed - speed) < 0.01

                        Button {
                            audioPlayerService.setSpeed(speed)
                        } label: {
                            Text(formatSpeed(speed))
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? MurmurDesign.Colors.voicePrimary : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Regenerate button
                Button {
                    onRegenerate(record)
                } label: {
                    Label("Open in Editor", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.vertical, 20)
            .background(.bar)
        }
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width / CGFloat(waveformBarCount)
            let bars = waveformData.isEmpty
                ? Array(repeating: Float(0.15), count: waveformBarCount)
                : waveformData

            HStack(spacing: 2) {
                ForEach(0..<waveformBarCount, id: \.self) { index in
                    let height = CGFloat(bars[safe: index] ?? 0.15) * geometry.size.height
                    let barProgress = Double(index) / Double(waveformBarCount)
                    let isPast = barProgress < progress

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            isPast
                                ? AnyShapeStyle(MurmurDesign.Colors.accentGradient)
                                : AnyShapeStyle(Color.secondary.opacity(0.2))
                        )
                        .frame(width: barWidth - 2, height: max(4, height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seekProgress = max(0, min(1, value.location.x / geometry.size.width))
                        audioPlayerService.seek(to: seekProgress * audioPlayerService.duration)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio playback position")
            .accessibilityValue("\(formatTime(audioPlayerService.currentTime)) of \(formatTime(audioPlayerService.duration))")
            .accessibilityHint("Drag to seek through the audio")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    skipForward()
                case .decrement:
                    skipBackward()
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading audio...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Failed to load audio")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Go Back", action: onClose)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func loadAudio() {
        isLoading = true
        loadError = nil

        do {
            let samples = try historyService.loadAudio(for: record)
            try audioPlayerService.loadAudio(samples: samples)
            audioPlayerService.playingRecordId = record.id
            waveformData = FloatingAudioPlayer.computeWaveform(from: samples, barCount: waveformBarCount)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            audioPlayerService.pause()
        } else {
            audioPlayerService.play()
        }
    }

    private func skipBackward() {
        audioPlayerService.skip(by: -5)
    }

    private func skipForward() {
        audioPlayerService.skip(by: 5)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        ToastManager.shared.showSuccess("Text copied")
    }

    private func exportAudio() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "murmur_\(record.voiceName.lowercased().replacingOccurrences(of: " ", with: "_")).wav"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let sourceURL = historyService.audioURL(for: record)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: url)
                Task { @MainActor in
                    ToastManager.shared.showSuccess("Audio exported")
                }
            } catch {
                Task { @MainActor in
                    ToastManager.shared.showError("Export failed")
                }
            }
        }
    }

    private func deleteAndClose() {
        audioPlayerService.stop()
        historyService.deleteRecord(record)
        onClose()
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatSpeed(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == floor(speed) {
            return "\(Int(speed))x"
        } else {
            return String(format: "%.2gx", speed)
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
