import Foundation

enum Constants {
    static let appName = "Murmur"
    static let sampleRate = 24000
    static let maxTextLength = 10000
    static let defaultChunkSize = 500 // characters per batch chunk

    enum Speed {
        static let minimum: Float = 0.5
        static let maximum: Float = 2.0
        static let `default`: Float = 1.0
        static let step: Float = 0.1

        static let presets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    }

    enum UserDefaultsKeys {
        static let settings = "com.murmur.settings"
        static let license = "com.murmur.license"
    }

    enum License {
        static let gumroadProductId = "b6lNvnB4q0MeK3VP02U4gg=="
        static let gumroadPurchaseURL = "https://tarunyadav.gumroad.com/l/ruzpof"
        static let offlineGracePeriodDays = 30
    }
}
