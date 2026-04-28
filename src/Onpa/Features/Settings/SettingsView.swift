import SwiftUI

struct SettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = SettingsViewModel()
    @State private var isChangelogPresented = false
    @State private var didOpenDebugChangelog = false

    var body: some View {
        Form {
            Section("Media") {
                Toggle("Auto Fetch Spectrograms", isOn: $viewModel.autoFetchSpectrograms)
                    .onChange(of: viewModel.autoFetchSpectrograms) {
                        Task { await viewModel.save(environment: appEnvironment) }
                    }
            }

            Section("Security") {
                Toggle("Remember Station Credentials", isOn: $viewModel.rememberStationCredentials)
                    .onChange(of: viewModel.rememberStationCredentials) {
                        Task { await viewModel.save(environment: appEnvironment) }
                    }
            }

            Section("App") {
                LabeledContent("Version", value: appVersion)
                NavigationLink {
                    ChangelogView()
                } label: {
                    Label("Changelog", systemImage: "list.bullet.rectangle")
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: viewModel.statusSystemImage)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar(.hidden, for: .tabBar)
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading settings")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationDestination(isPresented: $isChangelogPresented) {
            ChangelogView()
        }
        .task {
            await viewModel.load(environment: appEnvironment)
            openDebugChangelogIfNeeded()
        }
    }

    private func openDebugChangelogIfNeeded() {
        guard appEnvironment.configuration.debugShowsChangelog, !didOpenDebugChangelog else {
            return
        }
        didOpenDebugChangelog = true
        isChangelogPresented = true
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        case (nil, nil):
            return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.appEnvironment, .preview)
}
