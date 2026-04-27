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

        costMode = defaults.string(forKey: Keys.costMode).flatMap(CostMode.init(rawValue:)) ?? .rawAPI
        globalShortcut = defaults.data(forKey: Keys.globalShortcut).flatMap { try? decoder.decode(GlobalShortcut.self, from: $0) }
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
