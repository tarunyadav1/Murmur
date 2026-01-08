import Foundation
import NaturalLanguage

/// Represents supported TTS languages in Kokoro
enum Language: String, CaseIterable, Identifiable, Codable {
    case englishUS = "American"
    case englishUK = "British"
    case spanish = "Spanish"
    case japanese = "Japanese"
    case chinese = "Chinese"
    case french = "French"
    case hindi = "Hindi"
    case italian = "Italian"
    case portuguese = "Portuguese"

    var id: String { rawValue }

    /// Display name for the language
    var displayName: String {
        switch self {
        case .englishUS: return "English (US)"
        case .englishUK: return "English (UK)"
        case .spanish: return "Spanish"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        case .french: return "French"
        case .hindi: return "Hindi"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        }
    }

    /// Short display name
    var shortName: String {
        switch self {
        case .englishUS: return "EN-US"
        case .englishUK: return "EN-UK"
        case .spanish: return "ES"
        case .japanese: return "JA"
        case .chinese: return "ZH"
        case .french: return "FR"
        case .hindi: return "HI"
        case .italian: return "IT"
        case .portuguese: return "PT"
        }
    }

    /// Icon for the language (using globe for universality, avoiding flags)
    var icon: String {
        switch self {
        case .englishUS, .englishUK: return "globe.americas"
        case .spanish: return "globe.americas"
        case .japanese: return "globe.asia.australia"
        case .chinese: return "globe.asia.australia"
        case .french: return "globe.europe.africa"
        case .hindi: return "globe.asia.australia"
        case .italian: return "globe.europe.africa"
        case .portuguese: return "globe.americas"
        }
    }

    /// Voice ID prefix for this language (used in Kokoro voice IDs)
    var voicePrefix: String {
        switch self {
        case .englishUS: return "a"  // af_, am_
        case .englishUK: return "b"  // bf_, bm_
        case .spanish: return "e"    // ef_, em_
        case .japanese: return "j"   // jf_, jm_
        case .chinese: return "z"    // zf_, zm_
        case .french: return "f"     // ff_
        case .hindi: return "h"      // hf_, hm_
        case .italian: return "i"    // if_, im_
        case .portuguese: return "p" // pf_, pm_
        }
    }

    /// Initialize from Kokoro accent string
    static func from(accent: String) -> Language? {
        let normalized = accent.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "american": return .englishUS
        case "british": return .englishUK
        case "spanish": return .spanish
        case "japanese": return .japanese
        case "chinese", "mandarin": return .chinese
        case "french": return .french
        case "hindi": return .hindi
        case "italian": return .italian
        case "portuguese", "brazilian": return .portuguese
        default: return nil
        }
    }

    /// Initialize from Apple's NLLanguage
    static func from(nlLanguage: NLLanguage) -> Language? {
        switch nlLanguage {
        case .english: return .englishUS // Default to US English
        case .spanish: return .spanish
        case .japanese: return .japanese
        case .simplifiedChinese, .traditionalChinese: return .chinese
        case .french: return .french
        case .hindi: return .hindi
        case .italian: return .italian
        case .portuguese: return .portuguese
        default: return nil
        }
    }

    /// Get the corresponding NLLanguage for this language
    var nlLanguage: NLLanguage {
        switch self {
        case .englishUS, .englishUK: return .english
        case .spanish: return .spanish
        case .japanese: return .japanese
        case .chinese: return .simplifiedChinese
        case .french: return .french
        case .hindi: return .hindi
        case .italian: return .italian
        case .portuguese: return .portuguese
        }
    }
}

// MARK: - Language Detection Service

/// Service for detecting language from text using Apple's NaturalLanguage framework
final class LanguageDetectionService {

    /// Shared instance
    static let shared = LanguageDetectionService()

    private let recognizer = NLLanguageRecognizer()

    private init() {}

    /// Detect the dominant language from text
    /// - Parameter text: The text to analyze
    /// - Returns: The detected Language, or nil if uncertain
    func detectLanguage(from text: String) -> Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil } // Need minimum text for reliable detection

        recognizer.reset()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage else { return nil }
        return Language.from(nlLanguage: dominant)
    }

    /// Detect language with confidence score
    /// - Parameter text: The text to analyze
    /// - Returns: Tuple of detected Language and confidence (0.0-1.0), or nil
    func detectLanguageWithConfidence(from text: String) -> (language: Language, confidence: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lower threshold for non-ASCII text (like Hindi, Chinese, Japanese)
        let hasNonASCII = trimmed.unicodeScalars.contains { !$0.isASCII }
        let minLength = hasNonASCII ? 5 : 10
        guard trimmed.count >= minLength else { return nil }

        recognizer.reset()
        recognizer.processString(trimmed)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)

        // Find the best matching supported language
        // Lower confidence threshold for non-Latin scripts (they're more distinctive)
        let confidenceThreshold = hasNonASCII ? 0.2 : 0.3
        for (nlLanguage, confidence) in hypotheses.sorted(by: { $0.value > $1.value }) {
            if let language = Language.from(nlLanguage: nlLanguage), confidence > confidenceThreshold {
                return (language, confidence)
            }
        }

        return nil
    }

    /// Get all language hypotheses for the text
    /// - Parameter text: The text to analyze
    /// - Returns: Dictionary of supported Languages to confidence scores
    func getLanguageHypotheses(from text: String) -> [Language: Double] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return [:] }

        recognizer.reset()
        recognizer.processString(trimmed)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)

        var result: [Language: Double] = [:]
        for (nlLanguage, confidence) in hypotheses {
            if let language = Language.from(nlLanguage: nlLanguage) {
                result[language] = confidence
            }
        }

        return result
    }

    /// Check if the text appears to be in a specific language
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - language: The language to check for
    /// - Returns: True if the text likely matches the language
    func isText(_ text: String, inLanguage language: Language) -> Bool {
        guard let detected = detectLanguageWithConfidence(from: text) else { return false }
        return detected.language == language && detected.confidence > 0.5
    }
}

// MARK: - KokoroVoice Extension

extension KokoroVoice {
    /// Get the Language for this voice based on its accent
    var language: Language? {
        Language.from(accent: accent)
    }
}
