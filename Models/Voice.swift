import Foundation

/// Represents a voice for TTS generation with voice cloning support.
struct Voice: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String
    let gender: Gender
    let style: Style
    let sampleFile: String?

    init(id: String, name: String, description: String, gender: Gender, style: Style, sampleFile: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.gender = gender
        self.style = style
        self.sampleFile = sampleFile
    }

    enum Gender: String, Codable, CaseIterable {
        case female
        case male
        case neutral
        case unknown

        var displayName: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            case .neutral: return "Neutral"
            case .unknown: return "Unknown"
            }
        }
    }

    enum Style: String, Codable, CaseIterable {
        case narrator
        case casual
        case professional
        case character
        case general
        case `default`

        var displayName: String {
            switch self {
            case .narrator: return "Narrator"
            case .casual: return "Casual"
            case .professional: return "Professional"
            case .character: return "Character"
            case .general: return "General"
            case .default: return "Default"
            }
        }
    }

    var displayName: String { name }
}

// MARK: - Voice Category

enum VoiceCategory: String, CaseIterable, Identifiable {
    case `default` = "default"
    case narrator = "narrator"
    case casual = "casual"
    case professional = "professional"
    case character = "character"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .narrator: return "Narrator"
        case .casual: return "Casual"
        case .professional: return "Professional"
        case .character: return "Character"
        }
    }

    var icon: String {
        switch self {
        case .default: return "waveform"
        case .narrator: return "book.fill"
        case .casual: return "bubble.left.fill"
        case .professional: return "briefcase.fill"
        case .character: return "person.fill"
        }
    }
}

// MARK: - Voice Extensions

extension Voice {
    /// The default voice
    static let defaultVoice = Voice(
        id: "default",
        name: "Default",
        description: "Default voice",
        gender: .neutral,
        style: .default
    )

    /// Built-in voices loaded from the bundled voice library
    static let builtInVoices: [Voice] = {
        var voices: [Voice] = [defaultVoice]

        // Load from bundled voices.json - try multiple paths
        var voicesURL: URL?

        // Method 1: Direct path via resourceURL (for folder references)
        if let resourceURL = Bundle.main.resourceURL {
            let directPath = resourceURL.appendingPathComponent("VoiceSamples/voices.json")
            if FileManager.default.fileExists(atPath: directPath.path) {
                voicesURL = directPath
            }
        }

        // Method 2: Standard bundle resource lookup (for groups)
        if voicesURL == nil {
            voicesURL = Bundle.main.url(forResource: "voices", withExtension: "json", subdirectory: "VoiceSamples")
        }

        guard let url = voicesURL,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voiceArray = json["voices"] as? [[String: Any]] else {
            return voices
        }

        for voiceData in voiceArray {
            guard let id = voiceData["id"] as? String,
                  let name = voiceData["name"] as? String else {
                continue
            }

            let description = voiceData["description"] as? String ?? ""
            let genderStr = voiceData["gender"] as? String ?? "unknown"
            let styleStr = voiceData["style"] as? String ?? "general"

            let sampleFile = voiceData["file"] as? String

            let voice = Voice(
                id: id,
                name: name,
                description: description,
                gender: Gender(rawValue: genderStr) ?? .unknown,
                style: Style(rawValue: styleStr) ?? .general,
                sampleFile: sampleFile
            )

            voices.append(voice)
        }

        return voices
    }()

    /// Get all voices in a specific category
    static func voices(in category: VoiceCategory) -> [Voice] {
        if category == .default {
            return [defaultVoice]
        }
        return builtInVoices.filter { $0.style.rawValue == category.rawValue }
    }

    /// Get category for this voice
    var category: VoiceCategory {
        VoiceCategory(rawValue: style.rawValue) ?? .default
    }

    /// Get the URL to the voice sample file (from bundle)
    var sampleURL: URL? {
        guard let sampleFile = sampleFile else { return nil }

        // Try bundle resource path first
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("VoiceSamples/\(sampleFile)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    /// Whether this voice has a playable sample
    var hasSample: Bool {
        sampleURL != nil
    }
}
