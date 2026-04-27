import SwiftUI

struct StationView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = StationViewModel()

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Base URL", text: $viewModel.baseURLText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await viewModel.connect(environment: appEnvironment) }
                } label: {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.isBusy)

                if let report = viewModel.connectionReport {
                    LabeledContent("Station", value: report.profile.name)
                    LabeledContent("Status", value: report.status.displayName)
                    LabeledContent("Identity", value: report.identity)
                    LabeledContent("TLS", value: report.tlsState.displayName)
                    LabeledContent("Security", value: report.appConfig.security.enabled ? "Enabled" : "Disabled")
                } else {
                    LabeledContent("Station", value: "Not connected")
                    LabeledContent("Status", value: "Offline")
                }
            }

            Section("Account") {
                if viewModel.connectionReport == nil {
                    Text("Connect a station to enable account actions.")
                        .foregroundStyle(.secondary)
                } else if !viewModel.canLogIn {
                    Text("This station does not advertise direct password login.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Username (optional)", text: $viewModel.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)

                    Toggle("Save in Keychain", isOn: $viewModel.rememberCredentials)
                        .onChange(of: viewModel.rememberCredentials) {
                            Task { await viewModel.savePreferences(environment: appEnvironment) }
                        }

                    Button {
                        Task { await viewModel.logIn(environment: appEnvironment) }
                    } label: {
                        Label("Log In", systemImage: "person.badge.key")
                    }
                    .disabled(viewModel.isBusy)

                    Button(role: .destructive) {
                        Task { await viewModel.logOut(environment: appEnvironment) }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(viewModel.isBusy || !viewModel.canLogOut)
                }

                if let authStatus = viewModel.authStatus {
                    LabeledContent("Authenticated", value: authStatus.authenticated ? "Yes" : "No")
                    if let username = authStatus.username, !username.isEmpty {
                        LabeledContent("User", value: username)
                    }
                    if let method = authStatus.method, !method.isEmpty {
                        LabeledContent("Method", value: method)
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                }
            }

            Section("App") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Station")
        .task {
            await viewModel.load(environment: appEnvironment)
        }
        .refreshable {
            await viewModel.refreshAuthStatus(environment: appEnvironment)
        }
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
        StationView()
    }
    .environment(\.appEnvironment, .preview)
}
