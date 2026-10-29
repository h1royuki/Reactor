import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var showNSFW: Bool {
        didSet { defaults.set(showNSFW, forKey: "showNSFW") }
    }

    var autoplayVideo: Bool {
        didSet { defaults.set(autoplayVideo, forKey: "autoplayVideo") }
    }

    var fullQualityImages: Bool {
        didSet { defaults.set(fullQualityImages, forKey: "fullQualityImages") }
    }

    /// Skip posts already scrolled past or opened when the feed and tag pages load.
    var hideSeen: Bool {
        didSet { defaults.set(hideSeen, forKey: "hideSeen") }
    }

    var defaultFeed: PostLineType {
        didSet { defaults.set(defaultFeed.rawValue, forKey: "defaultFeed") }
    }

    private init() {
        defaults.register(defaults: ["autoplayVideo": true, "hideSeen": true])
        hideSeen = defaults.bool(forKey: "hideSeen")
        showNSFW = defaults.bool(forKey: "showNSFW")
        autoplayVideo = defaults.bool(forKey: "autoplayVideo")
        fullQualityImages = defaults.bool(forKey: "fullQualityImages")
        defaultFeed = PostLineType(rawValue: defaults.string(forKey: "defaultFeed") ?? "") ?? .good
    }
}
