import SwiftUI

/// Overlay showing progress during document audio generation
struct DocumentGenerationOverlay: View {

    let documentName: String
    let currentChunk: Int
    let totalChunks: Int
    let onCancel: () -> Void

    @State private var animateWave = false

    private var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(currentChunk) / Double(totalChunks)
    }

    private var progressPercent: Int {
        Int(progress * 100)
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Progress card
            VStack(spacing: 24) {
                // Header with animated icon
                VStack(spacing: 16) {
                    // Animated waveform icon
                    ZStack {
                        Circle()
                            .fill(MurmurDesign.Colors.voicePrimary.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(MurmurDesign.Colors.voicePrimary.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .scaleEffect(animateWave ? 1.2 : 1.0)
                            .opacity(animateWave ? 0 : 1)
                            .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: animateWave)

                        Image(systemName: "waveform")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }

                    VStack(spacing: 6) {
                        Text("Generating Audio")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(documentName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Progress section
                VStack(spacing: 12) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.2))

                            // Progress fill
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            MurmurDesign.Colors.voicePrimary,
                                            MurmurDesign.Colors.voicePrimary.opacity(0.8)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress)
                                .animation(.spring(duration: 0.4), value: progress)
                        }
                    }
                    .frame(height: 12)

                    // Progress text
                    HStack {
                        Text("Processing chunk \(currentChunk + 1) of \(totalChunks)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(progressPercent)%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                    }
                }

                // Chunk visualization
                HStack(spacing: 4) {
                    ForEach(0..<totalChunks, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(chunkColor(for: index))
                            .frame(height: 6)
                    }
                }
                .padding(.horizontal, 4)

                // Cancel button
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .onAppear {
            animateWave = true
        }
    }

    private func chunkColor(for index: Int) -> Color {
        if index < currentChunk {
            return MurmurDesign.Colors.voicePrimary
        } else if index == currentChunk {
            return MurmurDesign.Colors.voicePrimary.opacity(0.5)
        } else {
            return Color.secondary.opacity(0.2)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        DocumentGenerationOverlay(
            documentName: "LovHack 2026 Official Participant Guide",
            currentChunk: 2,
            totalChunks: 5,
            onCancel: {}
        )
    }
}
