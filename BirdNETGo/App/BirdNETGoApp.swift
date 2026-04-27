import SwiftUI

@main
struct BirdNETGoApp: App {
    private let environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, environment)
        }
    }
}
