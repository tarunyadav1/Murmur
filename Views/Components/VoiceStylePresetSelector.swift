import SwiftUI

/// A visual grid selector for voice style presets
struct VoiceStylePresetSelector: View {
    @Binding var voiceSettings: VoiceSettings
    @State private var hoveredPreset: VoiceStylePreset?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style Presets")
                .font(.headline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VoiceStylePreset.displayablePresets) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: voiceSettings.detectedPreset == preset,
                        isHovered: hoveredPreset == preset,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                // Toggle: if already selected, deselect to custom
                                if voiceSettings.detectedPreset == preset {
                                    voiceSettings.activePreset = nil
                                } else {
                                    voiceSettings.applyPreset(preset)
                                }
                            }
                        }
                    )
                    .onHover { isHovered in
                        hoveredPreset = isHovered ? preset : nil
                    }
                }
            }

            // Show current preset info
            if voiceSettings.detectedPreset != .custom {
                PresetInfoBanner(preset: voiceSettings.detectedPreset)
            }
        }
    }
}

/// Individual preset card in the grid
struct PresetCard: View {
    let preset: VoiceStylePreset
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .primary)

                Text(preset.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

/// Info banner showing details about the selected preset
struct PresetInfoBanner: View {
    let preset: VoiceStylePreset

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.icon)
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.description)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(preset.useCases)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
        )
    }
}

#Preview {
    VoiceStylePresetSelector(voiceSettings: .constant(.default))
        .frame(width: 300)
        .padding()
}
