import SwiftUI

/// Voice style controls for speech generation parameters
struct VoiceStyleView: View {
    @Binding var voiceSettings: VoiceSettings
    @State private var showAdvancedControls: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preset Selector
            VoiceStylePresetSelector(voiceSettings: $voiceSettings)

            Divider()

            // Advanced Controls Toggle
            DisclosureGroup(
                isExpanded: $showAdvancedControls,
                content: {
                    VStack(alignment: .leading, spacing: 16) {
                        // Current preset indicator when using custom values
                        if voiceSettings.detectedPreset == .custom {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(.orange)
                                Text("Custom settings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }

                        // Emotion / Energy
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Emotion / Energy")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", voiceSettings.emotionEnergy))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Button(action: {
                                    voiceSettings.emotionEnergy = 0.5
                                    voiceSettings.activePreset = nil
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default")
                            }

                            Text("Softer  \u{2194}  More expressive")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { voiceSettings.emotionEnergy },
                                    set: { newValue in
                                        voiceSettings.emotionEnergy = newValue
                                        voiceSettings.activePreset = nil
                                    }
                                ),
                                in: VoiceSettings.Ranges.emotionEnergy,
                                step: VoiceSettings.Steps.emotionEnergy
                            )
                        }

                        // Voice Match Strength
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Voice Match Strength")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1f", voiceSettings.voiceMatchStrength))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Button(action: {
                                    voiceSettings.voiceMatchStrength = 0.5
                                    voiceSettings.activePreset = nil
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default")
                            }

                            Text("Natural  \u{2194}  Strongly stylized")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { voiceSettings.voiceMatchStrength },
                                    set: { newValue in
                                        voiceSettings.voiceMatchStrength = newValue
                                        voiceSettings.activePreset = nil
                                    }
                                ),
                                in: VoiceSettings.Ranges.voiceMatchStrength,
                                step: VoiceSettings.Steps.voiceMatchStrength
                            )
                        }

                        // Pacing
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pacing")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", voiceSettings.pacing))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Button(action: {
                                    voiceSettings.pacing = 1.0
                                    voiceSettings.activePreset = nil
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default")
                            }

                            Text("Slower with emphasis  \u{2194}  Brisk delivery")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { voiceSettings.pacing },
                                    set: { newValue in
                                        voiceSettings.pacing = newValue
                                        voiceSettings.activePreset = nil
                                    }
                                ),
                                in: VoiceSettings.Ranges.pacing,
                                step: VoiceSettings.Steps.pacing
                            )
                        }

                        // Fade-Out Length
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fade-Out Length")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2fs", voiceSettings.fadeOutLength))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                Button(action: {
                                    voiceSettings.fadeOutLength = 0.0
                                    voiceSettings.activePreset = nil
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default")
                            }

                            Text("Quick end  \u{2194}  Long tail")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { voiceSettings.fadeOutLength },
                                    set: { newValue in
                                        voiceSettings.fadeOutLength = newValue
                                        voiceSettings.activePreset = nil
                                    }
                                ),
                                in: VoiceSettings.Ranges.fadeOutLength,
                                step: VoiceSettings.Steps.fadeOutLength
                            )
                        }

                        // Reset All Button
                        HStack {
                            Spacer()
                            Button("Reset All") {
                                withAnimation {
                                    voiceSettings = .default
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Fine-Tune Controls")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
            )
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    VoiceStyleView(voiceSettings: .constant(.default))
        .frame(width: 320)
        .padding()
}
