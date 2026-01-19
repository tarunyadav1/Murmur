import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var ttsService: KokoroTTSService

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Defaults Section
                SettingsSection(title: "Defaults", icon: "slider.horizontal.3") {
                    VStack(spacing: 16) {
                        // Voice Picker
                        HStack {
                            Text("Default Voice")
                                .font(.subheadline)
                            Spacer()
                            Picker("", selection: $settingsService.settings.defaultVoice) {
                                ForEach(VoiceCategory.allCases) { category in
                                    let voices = Voice.voices(in: category)
                                    if !voices.isEmpty {
                                        Section(category.displayName) {
                                            ForEach(voices) { voice in
                                                Text(voice.displayName).tag(voice)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(width: 180)
                        }

                        Divider()

                        // Export Format
                        HStack {
                            Text("Export Format")
                                .font(.subheadline)
                            Spacer()
                            Picker("", selection: $settingsService.settings.defaultExportFormat) {
                                ForEach(AudioExportFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }
                }

                // Voice Style Section
                SettingsSection(title: "Default Voice Style", icon: "waveform") {
                    VStack(spacing: 16) {
                        SettingsSlider(
                            title: "Emotion / Energy",
                            value: $settingsService.settings.voiceSettings.emotionEnergy,
                            range: VoiceSettings.Ranges.emotionEnergy,
                            step: VoiceSettings.Steps.emotionEnergy,
                            format: "%.2f"
                        )

                        SettingsSlider(
                            title: "Voice Match Strength",
                            value: $settingsService.settings.voiceSettings.voiceMatchStrength,
                            range: VoiceSettings.Ranges.voiceMatchStrength,
                            step: VoiceSettings.Steps.voiceMatchStrength,
                            format: "%.1f"
                        )

                        SettingsSlider(
                            title: "Pacing",
                            value: $settingsService.settings.voiceSettings.pacing,
                            range: VoiceSettings.Ranges.pacing,
                            step: VoiceSettings.Steps.pacing,
                            format: "%.2fx"
                        )

                        SettingsSlider(
                            title: "Fade-Out Length",
                            value: $settingsService.settings.voiceSettings.fadeOutLength,
                            range: VoiceSettings.Ranges.fadeOutLength,
                            step: VoiceSettings.Steps.fadeOutLength,
                            format: "%.2fs"
                        )
                    }
                }

                // Behavior Section
                SettingsSection(title: "Behavior", icon: "gearshape") {
                    Toggle(isOn: $settingsService.settings.autoPlayOnGenerate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-play after generation")
                                .font(.subheadline)
                            Text("Automatically play audio when generation completes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                // Save Location Section
                SettingsSection(title: "Save Location", icon: "folder") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let location = settingsService.settings.defaultSaveLocation {
                                Text(location.lastPathComponent)
                                    .font(.subheadline)
                                Text(location.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("System default")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            if settingsService.settings.defaultSaveLocation != nil {
                                Button("Reset") {
                                    withAnimation {
                                        settingsService.settings.defaultSaveLocation = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button("Choose...") {
                                selectSaveLocation()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                // Voice Engine Section
                SettingsSection(title: "Voice Engine", icon: "cpu") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.subheadline)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(ttsService.isModelLoaded ? .green : .secondary)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: ttsService.isModelLoaded ? .green.opacity(0.5) : .clear, radius: 4)

                                Text(ttsService.isModelLoaded ? "Ready" : "Not ready")
                                    .font(.caption)
                                    .foregroundStyle(ttsService.isModelLoaded ? .green : .secondary)
                            }
                        }

                        Spacer()

                        if ttsService.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if !ttsService.isModelLoaded {
                            Button {
                                Task {
                                    try? await ttsService.loadModel()
                                }
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                // Reset Section
                SettingsSection(title: "Reset", icon: "arrow.counterclockwise") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset All Settings")
                                .font(.subheadline)
                            Text("Restore all settings to their default values")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            withAnimation {
                                settingsService.reset()
                            }
                        } label: {
                            Text("Reset")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func selectSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            withAnimation {
                settingsService.settings.defaultSaveLocation = panel.url
            }
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Content
            content()
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        }
    }
}

// MARK: - Settings Slider

struct SettingsSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.subheadline)
                .frame(width: 140, alignment: .leading)

            Slider(value: $value, in: range, step: step)
                .tint(.accentColor)

            Text(String(format: format, value))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
