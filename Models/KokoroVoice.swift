import Foundation

/// Represents a native Kokoro voice for TTS generation
struct KokoroVoice: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let gender: String
    let accent: String
    let description: String

    var displayName: String { name }

    /// Gender display name
    var genderDisplayName: String {
        gender.capitalized
    }

    /// Check if this is a female voice
    var isFemale: Bool {
        gender.lowercased() == "female"
    }

    /// Check if this is a male voice
    var isMale: Bool {
        gender.lowercased() == "male"
    }
}
