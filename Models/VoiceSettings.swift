import Foundation

/// Voice style parameters for Chatterbox TTS
struct VoiceSettings: Codable, Equatable {
    /// Emotion/Energy intensity (0.0 = flat/monotone, 1.0 = dramatic/expressive)
    var emotionEnergy: Float

    /// Voice match strength / CFG weight (0.0 = natural, 1.0 = strongly stylized)
    var voiceMatchStrength: Float

    /// Pacing/Speed (0.5 = slow, 2.0 = fast)
    var pacing: Float

    /// Fade-out length in seconds (0.0 = no fade, 5.0 = long tail)
    var fadeOutLength: Float

    /// The currently applied preset (nil if custom/manual adjustments)
    var activePreset: VoiceStylePreset?

    static let `default` = VoiceSettings(
        emotionEnergy: 0.5,
        voiceMatchStrength: 0.5,
        pacing: 1.0,
        fadeOutLength: 0.0,
        activePreset: nil
    )

    /// Apply a preset to this settings instance
    mutating func applyPreset(_ preset: VoiceStylePreset) {
        if preset == .custom {
            activePreset = .custom
            return
        }
        let presetSettings = preset.settings
        emotionEnergy = presetSettings.emotionEnergy
        voiceMatchStrength = presetSettings.voiceMatchStrength
        pacing = presetSettings.pacing
        fadeOutLength = presetSettings.fadeOutLength
        activePreset = preset
    }

    /// Check if current settings match a preset (within tolerance)
    func matchesPreset(_ preset: VoiceStylePreset) -> Bool {
        guard preset != .custom else { return false }
        let presetSettings = preset.settings
        let tolerance: Float = 0.01
        return abs(emotionEnergy - presetSettings.emotionEnergy) < tolerance &&
               abs(voiceMatchStrength - presetSettings.voiceMatchStrength) < tolerance &&
               abs(pacing - presetSettings.pacing) < tolerance &&
               abs(fadeOutLength - presetSettings.fadeOutLength) < tolerance
    }

    /// Detect which preset (if any) matches the current settings
    var detectedPreset: VoiceStylePreset {
        for preset in VoiceStylePreset.displayablePresets {
            if matchesPreset(preset) {
                return preset
            }
        }
        return .custom
    }

    /// Ranges for UI sliders
    struct Ranges {
        static let emotionEnergy: ClosedRange<Float> = 0.0...1.0
        static let voiceMatchStrength: ClosedRange<Float> = 0.0...1.0
        static let pacing: ClosedRange<Float> = 0.5...2.0
        static let fadeOutLength: ClosedRange<Float> = 0.0...5.0
    }

    /// Step values for sliders
    struct Steps {
        static let emotionEnergy: Float = 0.05
        static let voiceMatchStrength: Float = 0.1
        static let pacing: Float = 0.05
        static let fadeOutLength: Float = 0.25
    }
}
