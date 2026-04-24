import Foundation

enum AppStorageKeys {
    static let hasSeenOnboarding = "hasSeenOnboarding"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let lastUpdateDate = "lastUpdateDate"
    static let onboardingFavoriteLines = "onboardingFavoriteLines"
    static let onboardingHomeLabel = "onboardingHomeLabel"
    static let onboardingDepartureTime = "onboardingDepartureTime"
    static let onboardingNeedsProfileSync = "onboardingNeedsProfileSync"
    static let onboardingLastAppliedUserId = "onboardingLastAppliedUserId"
    static let onboardingPendingPushPermission = "onboardingPendingPushPermission"
}

struct OnboardingPreferences: Equatable {
    let favoriteLines: [String]
    let homeLabel: String
    let departureTime: String

    var hasUsefulData: Bool {
        !favoriteLines.isEmpty || !homeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum OnboardingPreferenceStore {
    static func load() -> OnboardingPreferences {
        let defaults = UserDefaults.standard
        return OnboardingPreferences(
            favoriteLines: defaults.stringArray(forKey: AppStorageKeys.onboardingFavoriteLines) ?? [],
            homeLabel: defaults.string(forKey: AppStorageKeys.onboardingHomeLabel) ?? "",
            departureTime: defaults.string(forKey: AppStorageKeys.onboardingDepartureTime) ?? "08:15"
        )
    }

    static func save(_ preferences: OnboardingPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.favoriteLines, forKey: AppStorageKeys.onboardingFavoriteLines)
        defaults.set(preferences.homeLabel, forKey: AppStorageKeys.onboardingHomeLabel)
        defaults.set(preferences.departureTime, forKey: AppStorageKeys.onboardingDepartureTime)
        defaults.set(true, forKey: AppStorageKeys.onboardingNeedsProfileSync)
    }

    static func shouldApply(for userId: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppStorageKeys.onboardingNeedsProfileSync) else { return false }
        return defaults.string(forKey: AppStorageKeys.onboardingLastAppliedUserId) != userId
    }

    static func markApplied(for userId: String) {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: AppStorageKeys.onboardingNeedsProfileSync)
        defaults.set(userId, forKey: AppStorageKeys.onboardingLastAppliedUserId)
    }
}
