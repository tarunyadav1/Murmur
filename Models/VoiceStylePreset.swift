import Foundation

/// Predefined voice style presets that adjust TTS parameters for specific moods/effects
enum VoiceStylePreset: String, CaseIterable, Identifiable, Codable {
    case custom
    case calm
    case expressive
    case dramatic
    case natural
    case energetic
    case measured

    var id: String { rawValue }

    /// Display name for the preset
    var displayName: String {
        switch self {
        case .custom: return "Custom"
        case .calm: return "Calm"
        case .expressive: return "Expressive"
        case .dramatic: return "Dramatic"
        case .natural: return "Natural"
        case .energetic: return "Energetic"
        case .measured: return "Measured"
        }
    }

    /// Short description of what this preset is for
    var description: String {
        switch self {
        case .custom:
            return "Manually adjust all parameters"
        case .calm:
            return "Subdued, relaxed delivery"
        case .expressive:
            return "Lively, engaging tone"
        case .dramatic:
            return "Bold, theatrical presence"
        case .natural:
            return "Balanced, conversational"
        case .energetic:
            return "High energy, enthusiastic"
        case .measured:
            return "Slow, deliberate pacing"
        }
    }

    /// Example use cases for this preset
    var useCases: String {
        switch self {
        case .custom:
            return "Fine-tune to your needs"
        case .calm:
            return "Meditation, relaxation, bedtime"
        case .expressive:
            return "Storytelling, presentations"
        case .dramatic:
            return "Trailers, announcements, impact"
        case .natural:
            return "Podcasts, audiobooks, general"
        case .energetic:
            return "Ads, promos, gaming, sports"
        case .measured:
            return "Instructions, poetry, emphasis"
        }
    }

    /// Icon for this preset
    var icon: String {
        switch self {
        case .custom: return "slider.horizontal.3"
        case .calm: return "moon.fill"
        case .expressive: return "face.smiling.fill"
        case .dramatic: return "theatermasks.fill"
        case .natural: return "waveform"
        case .energetic: return "bolt.fill"
        case .measured: return "metronome.fill"
        }
    }

    /// The VoiceSettings values for this preset
    var settings: VoiceSettings {
        switch self {
        case .custom:
            return .default

        case .calm:
            // Subdued, relaxed - low energy, natural matching, slower pace
            return VoiceSettings(
                emotionEnergy: 0.2,
                voiceMatchStrength: 0.4,
                pacing: 0.85,
                fadeOutLength: 0.5
            )

        case .expressive:
            // Lively, engaging - high emotion, good matching
            return VoiceSettings(
                emotionEnergy: 0.75,
                voiceMatchStrength: 0.6,
                pacing: 1.05,
                fadeOutLength: 0.0
            )

        case .dramatic:
            // Bold, theatrical - maximum expression, strong matching, slower for impact
            return VoiceSettings(
                emotionEnergy: 0.95,
                voiceMatchStrength: 0.8,
                pacing: 0.9,
                fadeOutLength: 0.75
            )

        case .natural:
            // Balanced, conversational - moderate everything
            return VoiceSettings(
                emotionEnergy: 0.5,
                voiceMatchStrength: 0.5,
                pacing: 1.0,
                fadeOutLength: 0.0
            )

        case .energetic:
            // High energy, enthusiastic - high emotion, faster pace
            return VoiceSettings(
                emotionEnergy: 0.9,
                voiceMatchStrength: 0.65,
                pacing: 1.2,
                fadeOutLength: 0.0
            )

        case .measured:
            // Slow, deliberate - moderate energy, slower pace for clarity
            return VoiceSettings(
                emotionEnergy: 0.4,
                voiceMatchStrength: 0.5,
                pacing: 0.75,
                fadeOutLength: 0.25
            )
        }
    }

    /// All presets except custom (for display purposes)
    static var displayablePresets: [VoiceStylePreset] {
        allCases.filter { $0 != .custom }
    }
}
