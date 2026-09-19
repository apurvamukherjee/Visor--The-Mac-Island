import Foundation

/// The first-launch welcome flow. Three steps, linear, no branching — an
/// island this small has no room for a step the user can get lost in.
enum OnboardingStep: Int, CaseIterable, Equatable, Hashable, Sendable {
    case welcome
    case permissions
    case finish

    /// nil past the last step: the finish step's button calls
    /// `OnboardingService.finish()` directly rather than advancing again.
    var next: OnboardingStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), all.index(after: index) < all.endIndex else { return nil }
        return all[all.index(after: index)]
    }

    var glyph: String {
        switch self {
        case .welcome: "sparkles"
        case .permissions: "lock.shield.fill"
        case .finish: "star.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Welcome to Visor"
        case .permissions: "One quick check"
        case .finish: "You're all set"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            "Your notch, with a little more going on — music, calendar, battery and more, always one glance away."
        case .permissions:
            "Visor reads your calendar and battery locally. If a permission prompt didn't show up, grant it in "
                + "System Settings."
        case .finish:
            "That's everything. Hover the notch any time to see what's happening."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome, .permissions: "Continue"
        case .finish: "Get Started"
        }
    }

    /// The lower-emphasis link each step offers besides "Continue" —
    /// nil for the welcome step, which has nothing to hand off to yet.
    var secondaryButtonTitle: String? {
        switch self {
        case .welcome: nil
        case .permissions: "Open Settings"
        case .finish: "Star on GitHub"
        }
    }

    var secondaryURL: URL? {
        switch self {
        case .welcome: nil
        case .permissions: URL(string: "x-apple.systempreferences:com.apple.preference.security")
        case .finish: URL(string: "https://github.com/apurvamukherjee/Visor--The-Mac-Island")
        }
    }
}
