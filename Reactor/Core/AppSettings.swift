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

    var defaultFeed: PostLineType {
        didSet { defaults.set(defaultFeed.rawValue, forKey: "defaultFeed") }
    }

    private init() {
        showNSFW = defaults.bool(forKey: "showNSFW")
        autoplayVideo = defaults.bool(forKey: "autoplayVideo")
        fullQualityImages = defaults.bool(forKey: "fullQualityImages")
        defaultFeed = PostLineType(rawValue: defaults.string(forKey: "defaultFeed") ?? "") ?? .good
    }
}
