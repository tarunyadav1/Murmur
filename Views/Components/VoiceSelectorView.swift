import SwiftUI

struct VoiceSelectorView: View {

    @Binding var selectedVoice: Voice
    @StateObject private var previewService = VoicePreviewService.shared
    @State private var expandedCategories: Set<VoiceCategory> = [.default]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(VoiceCategory.allCases) { category in
                        let voices = Voice.voices(in: category)
                        if !voices.isEmpty {
                            VoiceCategorySection(
                                category: category,
                                voices: voices,
                                selectedVoice: $selectedVoice,
                                previewService: previewService,
                                isExpanded: expandedCategories.contains(category),
                                onToggle: {
                                    if expandedCategories.contains(category) {
                                        expandedCategories.remove(category)
                                    } else {
                                        expandedCategories.insert(category)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

struct VoiceCategorySection: View {

    let category: VoiceCategory
    let voices: [Voice]
    @Binding var selectedVoice: Voice
    @ObservedObject var previewService: VoicePreviewService
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 16)
                    Image(systemName: category.icon)
                    Text(category.displayName)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(voices.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(voices) { voice in
                        VoiceRow(
                            voice: voice,
                            isSelected: voice == selectedVoice,
                            isPlaying: previewService.currentlyPlayingVoiceId == voice.id,
                            onSelect: { selectedVoice = voice },
                            onPlayToggle: { previewService.toggle(voice: voice) }
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

struct VoiceRow: View {

    let voice: Voice
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onPlayToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Play button for voice preview
            if voice.hasSample {
                Button(action: onPlayToggle) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isPlaying ? .orange : .accentColor)
                }
                .buttonStyle(.plain)
                .help("Preview voice")
            } else {
                // Placeholder for alignment
                Color.clear
                    .frame(width: 18, height: 18)
            }

            // Voice selection button
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(voice.displayName)
                            if voice.gender != .neutral && voice.gender != .unknown {
                                Text(voice.gender == .female ? "♀" : "♂")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(voice.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
