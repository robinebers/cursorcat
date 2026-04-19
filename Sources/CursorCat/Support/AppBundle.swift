import Foundation

enum AppBundle {
    private final class BundleToken {}

    static let resources: Bundle = {
        // In a packaged macOS .app, the SwiftPM resource bundle is staged into
        // Contents/Resources/ by the release script. SwiftPM's generated
        // Bundle.module accessor looks next to Bundle.main.bundleURL instead,
        // which resolves to the .app root and fails to find it — so prefer the
        // macOS-standard location first.
        if let resourcesURL = Bundle.main.resourceURL {
            let packaged = resourcesURL.appendingPathComponent("CursorCat_CursorCat.bundle")
            if let bundle = Bundle(url: packaged) {
                return bundle
            }
        }

        // Fall back to SwiftPM's auto-generated accessor for `swift run` and tests,
        // or to the token-class bundle when built outside SwiftPM.
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }()
}
