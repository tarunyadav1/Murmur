import Foundation
import Combine

@MainActor
final class TextInputViewModel: ObservableObject {

    @Published var text: String = ""

    var characterCount: Int { text.count }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Estimated speaking duration at normal speed (~150 WPM)
    var estimatedDuration: String {
        let minutes = Double(wordCount) / 150.0
        if minutes < 1 {
            let seconds = Int(minutes * 60)
            return "\(seconds)s"
        }
        return String(format: "%.1f min", minutes)
    }

    func clear() {
        text = ""
    }
}
