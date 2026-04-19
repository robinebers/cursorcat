import Foundation
import Combine

enum CostMode: String, Codable {
    case actual
    case rawAPI
}

@MainActor
final class UserSettings: ObservableObject {
    private enum Keys {
        static let globalShortcut = "settings.globalShortcut"
        static let costMode = "settings.costMode"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published var globalShortcut: GlobalShortcut? {
        didSet { persistGlobalShortcut() }
    }

    @Published var globalShortcutRegistrationError: String?

    @Published var costMode: CostMode {
        didSet { defaults.set(costMode.rawValue, forKey: Keys.costMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: Keys.costMode),
           let storedMode = CostMode(rawValue: rawValue) {
            costMode = storedMode
        } else {
            costMode = .rawAPI
        }

        if let data = defaults.data(forKey: Keys.globalShortcut),
           let shortcut = try? decoder.decode(GlobalShortcut.self, from: data) {
            globalShortcut = shortcut
        } else {
            globalShortcut = nil
        }
    }

    private func persistGlobalShortcut() {
        if let globalShortcut,
           let data = try? encoder.encode(globalShortcut) {
            defaults.set(data, forKey: Keys.globalShortcut)
        } else {
            defaults.removeObject(forKey: Keys.globalShortcut)
        }
    }
}
