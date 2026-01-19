import SwiftUI
import UniformTypeIdentifiers

// MARK: - Floating Audio Player

struct FloatingAudioPlayer: View {
    let filename: String
    let duration: TimeInterval
    let currentTime: TimeInterval
    let isPlaying: Bool
    let waveformData: [Float]  // Pre-computed waveform (60 bars)
    let generationTime: Double?

    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onExport: () -> Void
    let onDismiss: () -> Void

    @State private var isMinimized = false
    @State private var isHovered = false
    @State private var dragOffset: CGSize = .zero
    @State private var savedPosition: CGSize = .zero
    @State private var showSuccessGlow = false

    private let waveformBarCount = 60

    private var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    var body: some View {
        Group {
            if isMinimized {
                minimizedPlayer
            } else {
                expandedPlayer
            }
        }
        .offset(x: dragOffset.width + savedPosition.width, y: dragOffset.height + savedPosition.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    savedPosition.width += value.translation.width
                    savedPosition.height += value.translation.height
                    dragOffset = .zero
                }
        )
        .onAppear {
            // Show success glow briefly when audio appears
            showSuccessGlow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showSuccessGlow = false }
            }
        }
    }

    /// Static helper to compute waveform from samples (call this once when audio is generated)
    static func computeWaveform(from samples: [Float], barCount: Int = 60) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.15, count: barCount)
        }

        let chunkSize = max(1, samples.count / barCount)
        var result: [Float] = []
        result.reserveCapacity(barCount)

        for i in 0..<barCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            if start < samples.count {
                var maxVal: Float = 0
                for j in start..<end {
                    let absVal = abs(samples[j])
                    if absVal > maxVal { maxVal = absVal }
                }
                result.append(max(0.08, min(1.0, maxVal * 2.2)))
            } else {
                result.append(0.08)
            }
        }

        return result
    }

    // MARK: - Minimized Player

    private var minimizedPlayer: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button(action: isPlaying ? onPause : onPlay) {
                ZStack {
                    Circle()
                        .fill(MurmurDesign.Colors.accentGradient)
                        .frame(width: 40, height: 40)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)

            // Progress ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        MurmurDesign.Colors.accentGradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
            }

            // Time
            Text(formatTime(currentTime))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // Expand button
            Button {
                withAnimation(MurmurDesign.Animations.panelSlide) {
                    isMinimized = false
                }
            } label: {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        }
        .overlay {
            Capsule()
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Expanded Player

    private var expandedPlayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Animated audio icon
                ZStack {
                    Circle()
                        .fill(MurmurDesign.Colors.voicePrimary.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
                }
                .softGlow(MurmurDesign.Colors.voicePrimary, isActive: isPlaying)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                            .monospacedDigit()

                        if let genTime = generationTime {
                            Text("•")
                            Text("Generated in \(String(format: "%.1fs", genTime))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    Button {
                        withAnimation(MurmurDesign.Animations.panelSlide) {
                            isMinimized = true
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help("Minimize")

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            // Waveform - draggable for export
            waveformView
                .frame(height: 60)
                .draggable(audioFileProvider) {
                    // Drag preview
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                        Text(filename)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

            // Controls
            HStack(spacing: 12) {
                // Stop
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(".", modifiers: .command)

                // Play/Pause - prominent
                Button(action: isPlaying ? onPause : onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(isPlaying ? "Pause" : "Play")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.space, modifiers: [])

                Spacer()

                // Keyboard hint
                KeyboardHint(keys: "Space")
                    .opacity(isHovered ? 1 : 0)

                // Export
                Button(action: onExport) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Export")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background {
            RoundedRectangle(cornerRadius: MurmurDesign.Radius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MurmurDesign.Radius.xl)
                .strokeBorder(
                    showSuccessGlow ? MurmurDesign.Colors.success.opacity(0.5) : Color.gray.opacity(0.2),
                    lineWidth: showSuccessGlow ? 2 : 0.5
                )
        }
        .softGlow(MurmurDesign.Colors.success, radius: 20, isActive: showSuccessGlow)
        .onHover { isHovered = $0 }
        .animation(MurmurDesign.Animations.quick, value: isHovered)
    }

    // MARK: - Waveform

    private var waveformView: some View {
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
                        onSeek(seekProgress * duration)
                    }
            )
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Drag Provider

    private var audioFileProvider: some Transferable {
        AudioDragItem(filename: filename)
    }
}

// MARK: - Audio Drag Item

struct AudioDragItem: Transferable {
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            item.filename
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    VStack {
        FloatingAudioPlayer(
            filename: "speech_2024_01_15.wav",
            duration: 45.5,
            currentTime: 12.3,
            isPlaying: true,
            waveformData: (0..<60).map { _ in Float.random(in: 0.1...0.9) },
            generationTime: 2.4,
            onPlay: {},
            onPause: {},
            onStop: {},
            onSeek: { _ in },
            onExport: {},
            onDismiss: {}
        )
    }
    .frame(width: 600, height: 400)
    .background(Color(NSColor.windowBackgroundColor))
}
