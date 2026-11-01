import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

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

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
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
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
    }

    /// Set on the windows rather than via preferredColorScheme, so sheets and covers follow
    /// immediately and "System" reliably hands control back to iOS.
    func applyTheme() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = theme.interfaceStyle
            }
        }
    }
}
