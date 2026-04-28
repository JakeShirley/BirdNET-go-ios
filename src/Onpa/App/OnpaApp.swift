import SwiftUI

@main
struct OnpaApp: App {
    private let environment = AppEnvironment.live
    @AppStorage(AppearancePreference.storageKey) private var appearanceRawValue = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootTabView(initialTab: AppTab.initialTab())
                .environment(\.appEnvironment, environment)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
    }

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRawValue) ?? .system
    }
}
