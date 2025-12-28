import Foundation

/// Represents a single text block in the batch queue
struct TextBlock: Identifiable, Equatable {
    let id: UUID
    var text: String
    var status: Status
    var generatedAudio: [Float]?
    var errorMessage: String?
    var progress: Double

    enum Status: Equatable {
        case pending
        case generating
        case completed
        case failed
    }

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.status = .pending
        self.generatedAudio = nil
        self.errorMessage = nil
        self.progress = 0.0
    }

    var characterCount: Int { text.count }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Estimated duration in seconds (rough: ~150 words per minute)
    var estimatedDuration: TimeInterval {
        Double(wordCount) / 150.0 * 60.0
    }

    /// Preview of text content (first 50 characters)
    var preview: String {
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(50)) + "..."
    }
}
