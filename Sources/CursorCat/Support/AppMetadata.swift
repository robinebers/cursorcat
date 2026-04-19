import Foundation

enum AppMetadata {
    static var displayName: String {
        stringValue("CFBundleDisplayName")
            ?? stringValue(kCFBundleNameKey as String)
            ?? "CursorCat"
    }

    static var version: String {
        stringValue("CFBundleShortVersionString") ?? "0.0.0"
    }

    static var build: String {
        stringValue(kCFBundleVersionKey as String) ?? version
    }

    static var versionDescription: String {
        if build == version {
            return version
        }
        return "\(version) (\(build))"
    }

    static var sparkleFeedURL: URL? {
        guard let string = stringValue("SUFeedURL"),
              !string.isEmpty else {
            return nil
        }
        return URL(string: string)
    }

    static var sparklePublicEDKey: String? {
        guard let value = stringValue("SUPublicEDKey"),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func stringValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
