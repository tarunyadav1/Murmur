import Foundation

struct AppSettings: Codable, Equatable {
    var defaultVoice: Voice
    var defaultSpeed: Float
    var defaultExportFormat: AudioExportFormat
    var defaultSaveLocation: URL?
    var autoPlayOnGenerate: Bool
    var keepModelLoaded: Bool
    var voiceSettings: VoiceSettings

    static let `default` = AppSettings(
        defaultVoice: .defaultVoice,
        defaultSpeed: 1.0,
        defaultExportFormat: .wav,
        defaultSaveLocation: nil,
        autoPlayOnGenerate: true,
        keepModelLoaded: true,
        voiceSettings: .default
    )
}
