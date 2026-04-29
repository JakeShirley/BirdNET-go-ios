import SwiftUI

struct SettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = SettingsViewModel()
    @State private var isChangelogPresented = false
    @State private var didOpenDebugChangelog = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(selection: $viewModel.appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Label(option.label, systemImage: option.systemImage)
                            .tag(option)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.appearance) {
                    Task { await viewModel.save(environment: appEnvironment) }
                }
            }

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

            Section {
                Toggle("Generate Daily Summaries", isOn: $viewModel.enableIntelligenceSummaries)
                    .onChange(of: viewModel.enableIntelligenceSummaries) {
                        Task { await viewModel.save(environment: appEnvironment) }
                    }
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Uses Apple Intelligence on supported devices to rewrite the dashboard's daily digest in plain language. Detection data stays on your device. Falls back to the standard summary when unavailable.")
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
                    .background(.regularMaterial, in: DS.Shape.card)
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
