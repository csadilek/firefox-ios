// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Shared
import MozillaAppServices
import UIKit

struct FlaggableFeature {

    // MARK: - Variables
    private let profile: Profile
    private let buildChannels: [AppBuildChannel]
    private var featureID: FeatureFlagName

    private var featureKey: String? {
        typealias FlagKeys = PrefsKeys.FeatureFlags
        switch featureID {
        case .chronologicalTabs:
            return FlagKeys.ChronologicalTabs
        case .historyHighlights:
            return FlagKeys.HistoryHighlightsSection
        case .historyGroups:
            return FlagKeys.HistoryGroups
        case .inactiveTabs:
            return FlagKeys.InactiveTabs
        case .jumpBackIn:
            return FlagKeys.JumpBackInSection
        case .pocket:
            return FlagKeys.ASPocketStories
        case .pullToRefresh:
            return FlagKeys.PullToRefresh
        case .recentlySaved:
            return FlagKeys.RecentlySavedSection
        case .startAtHome:
            return FlagKeys.StartAtHome
        case .tabTrayGroups:
            return FlagKeys.TabTrayGroups
        case .wallpapers:
            return FlagKeys.CustomWallpaper
        default: return nil
        }
    }

    public var featureOptionsKey: String? {
        guard let baseKey = featureKey else { return nil }
        return baseKey + "UserPreferences"
    }


    // MARK: - Initializers

    init(withID featureID: FeatureFlagName,
         and profile: Profile,
         enabledFor channels: [AppBuildChannel]
    ) {
        self.featureID = featureID
        self.profile = profile
        self.buildChannels = channels
    }

    // MARK: - Public methods

    /// Returns whether or not the feature is active for the build.
    ///
    /// This variable returns a `Bool` based on a priority queue.
    ///
    /// 1. It will check whether or not there exists a value for
    /// the feature written on disk. Users generally set these states
    /// from the debug menu and, if they have set something manually,
    /// we will respect that and return the respective value.
    ///
    /// 2. If there is no setting written to the disk, then every feature
    /// has an underlying default state for each build channel (Release,
    /// Beta, Developer) and that value will be returned.
    public func isActiveForBuild() -> Bool {
        if let key = featureKey, let existingPref = profile.prefs.boolForKey(key) {
            return existingPref

        } else {
            #if MOZ_CHANNEL_RELEASE
            return buildChannels.contains(.release)
            #elseif MOZ_CHANNEL_BETA
            return buildChannels.contains(.beta)
            #elseif MOZ_CHANNEL_FENNEC
            return buildChannels.contains(.developer)
            #else
            return buildChannels.contains(.other)
            #endif
        }
    }

    /// Returns the feature option represented as an Int. The `FeatureFlagManager` will
    /// convert it to the appropriate type.
    public func getUserPreference() -> String? {
        if let optionsKey = featureOptionsKey, let existingOption = profile.prefs.stringForKey(optionsKey) {
            return existingOption
        }

        // Feature option defaults
        switch featureID {
        case .startAtHome:
            return StartAtHomeSetting.afterFourHours.rawValue
        case .wallpapers:
            // In this case, we want to enable the tap banner to cycle through
            // wallpapers behaviour by default.
            return UserFeaturePreference.enabled.rawValue

        // Nimbus default options
        case .jumpBackIn, .pocket, .recentlySaved:
            return checkNimbusHomepageFeatures(for: sectionID(from: featureID)).rawValue
        case .inactiveTabs:
            return checkNimbusTabTrayFeatures(for: sectionID(from: featureID)).rawValue
        default:
            return UserFeaturePreference.disabled.rawValue
        }
    }

    /// Allows fine grain control over a feature, by allowing to directly set the state to ON
    /// or OFF, and also set the features option as an Int
    public func setUserPreferenceFor(_ option: String) {
        guard !option.isEmpty,
              let optionsKey = featureOptionsKey
        else { return }

        profile.prefs.setString(option, forKey: optionsKey)
    }

    /// Toggles a feature On or Off, and saves the status to UserDefaults.
    ///
    /// Not all features are user togglable. If there exists no feature key - as defined
    /// in the `featureKey()` function - with which to write to UserDefaults, then the
    /// feature cannot be turned on/off and its state can only be set when initialized,
    /// based on build channel. Furthermore, this controls build availability, and
    /// does not reflect user preferences.
    public func toggleBuildFeature() {
        guard let featureKey = featureKey else { return }
        profile.prefs.setBool(!isActiveForBuild(), forKey: featureKey)
    }
}

// MARK: - Nimbus related methods
extension FlaggableFeature {
    private func checkNimbusTabTrayFeatures(
        for sectionID: TabTraySection?,
        from nimbus: FxNimbus = FxNimbus.shared
    ) -> UserFeaturePreference {
        guard let sectionID = sectionID else { return UserFeaturePreference.disabled }
        soakNimbus(featureId: "tab-tray-feature", in: #file, at: #line) { TabTrayFeature($0) }
        let nimbusTabTrayConfig = nimbus.features.tabTrayFeature.value()

        if let sectionIsEnabled = nimbusTabTrayConfig.sectionsEnabled[sectionID],
           sectionIsEnabled {
            return UserFeaturePreference.enabled
        }

        return UserFeaturePreference.disabled
    }

    private func checkNimbusHomepageFeatures(
        for sectionID: HomeScreenSection?,
        from nimbus: FxNimbus = FxNimbus.shared
    ) -> UserFeaturePreference {
        guard let sectionID = sectionID else { return UserFeaturePreference.disabled }
        soakNimbus(featureId: "homescreen", in: #file, at: #line) { Homescreen($0) }
        let nimbusHomepageConfig = nimbus.features.homescreen.value()

        if let sectionIsEnabled = nimbusHomepageConfig.sectionsEnabled[sectionID],
           sectionIsEnabled {
            // For pocket's default value, we also need to check the locale being supported.
            // Here, we want to make sure the section is enabled && locale is supported before
            // we would return that pocket is enabled
            if sectionID == .pocket && !Pocket.IslocaleSupported(Locale.current.identifier) {
                return UserFeaturePreference.disabled
            }
            return UserFeaturePreference.enabled
        }

        return UserFeaturePreference.disabled
    }

    // Here we encapsulate translation from internal featureIDs to Nimbus' related
    // feature ids, whose definition can be found in the `nimbus.fml.yaml` file.
    private func sectionID(from featureID: FeatureFlagName) -> HomeScreenSection? {
        switch featureID {
        case .jumpBackIn:
            return .jumpBackIn
        case .recentlySaved:
            return .recentlySaved
        case .pocket:
            return .pocket
        default:
            return nil
        }
    }

    private func sectionID(from featureID: FeatureFlagName) -> TabTraySection? {
        switch featureID {
        case .inactiveTabs:
            return .inactiveTabs
        default:
            return nil
        }
    }
}

func soakNimbus<T>(featureId: String, iterations: Int = 100_000, in file: String = #file, at lineno: Int = #line, creator: @escaping (Variables) -> T) {
    print("Start soaking \(featureId)")
    for _ in 1..<iterations {
        let _ = FxNimbus.shared.features.homescreen.value()
    }
    let lastSlash = file.lastIndex(of: "/") ?? file.startIndex
    let filename = file.suffix(from: lastSlash)
    print("Finish soaking \(featureId) for \(iterations) iterations at \(filename):\(lineno)")
}
