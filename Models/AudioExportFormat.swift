import Foundation
import UniformTypeIdentifiers

enum AudioExportFormat: String, CaseIterable, Identifiable, Codable {
    case wav = "wav"
    case m4a = "m4a"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: return "WAV (Highest Quality)"
        case .m4a: return "M4A/AAC (Smaller Size)"
        }
    }

    var fileExtension: String { rawValue }

    var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .m4a: return "audio/mp4"
        }
    }

    var contentType: UTType {
        switch self {
        case .wav: return .wav
        case .m4a: return .mpeg4Audio
        }
    }
}
