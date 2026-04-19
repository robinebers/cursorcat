import Foundation

enum AppBundle {
    #if SWIFT_PACKAGE
    static let resources = Bundle.module
    #else
    private final class BundleToken {}

    static let resources = Bundle(for: BundleToken.self)
    #endif
}
