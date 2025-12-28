import Foundation
import Combine

/// Persists user preferences using UserDefaults
@MainActor
final class SettingsService: ObservableObject {

    private let userDefaults: UserDefaults
    private let settingsKey = "com.murmur.settings"

    @Published var settings: AppSettings {
        didSet {
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }

    func reset() {
        settings = .default
    }
}
