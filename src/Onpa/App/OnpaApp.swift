import AVFoundation
import SwiftUI

@main
struct OnpaApp: App {
    private let environment = AppEnvironment.live
    @AppStorage(AppearancePreference.storageKey) private var appearanceRawValue = AppearancePreference.system.rawValue

    init() {
        configureAudioSession()
    }

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

    /// Configure a `.playback` audio session so user-initiated bird sample
    /// playback (species details, detection detail spectrogram) is audible
    /// even when the device's silent switch is engaged. Without this, AVPlayer
    /// falls back to the default `.soloAmbient` category which is muted by the
    /// ringer switch.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: playback will still work, just subject to the silent
            // switch. Log so we can spot misconfiguration in development.
            print("[OnpaApp] Failed to configure AVAudioSession: \(error)")
        }
    }
}
