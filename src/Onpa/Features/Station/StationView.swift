import SwiftUI

struct StationView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = StationViewModel()
    @State private var isDeleteConfirmationPresented = false
    @State private var profilePendingDeletion: StationProfile?
    @State private var profilePendingRename: StationProfile?
    @State private var renameText = ""
    @State private var isAddingNewStation = false

    var body: some View {
        Form {
            stationsSection

            connectionSection

            accountSection

            if viewModel.canDeleteActiveProfile {
                deleteActiveSection
            }

            diagnosticsSection

            if let statusMessage = viewModel.statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                }
            }
        }
        .navigationTitle("Station Management")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingNewStation = true
                    viewModel.prepareForNewStation()
                } label: {
                    Label("Add Station", systemImage: "plus")
                }
                .accessibilityLabel("Add station")
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)

            if appEnvironment.configuration.debugShowsDeleteStationConfirmation, viewModel.canDeleteActiveProfile {
                profilePendingDeletion = viewModel.activeProfile
                isDeleteConfirmationPresented = true
            }
        }
        .refreshable {
            await viewModel.refreshAuthStatus(environment: appEnvironment)
        }
        .alert(
            "Delete Station?",
            isPresented: $isDeleteConfirmationPresented,
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete Station", role: .destructive) {
                Task {
                    await viewModel.deleteProfile(profile, environment: appEnvironment)
                    profilePendingDeletion = nil
                }
            }

            Button("Cancel", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("This removes \(profile.name) and any stored credentials from this device.")
        }
        .alert("Rename Station", isPresented: renameAlertBinding, presenting: profilePendingRename) { profile in
            TextField("Station name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Save") {
                Task {
                    await viewModel.renameProfile(profile, to: renameText, environment: appEnvironment)
                    profilePendingRename = nil
                }
            }
            Button("Cancel", role: .cancel) {
                profilePendingRename = nil
            }
        } message: { profile in
            Text("Choose a new name for \(profile.baseURL.absoluteString).")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var stationsSection: some View {
        if !viewModel.profiles.isEmpty {
            Section("Stations") {
                ForEach(viewModel.profiles) { profile in
                    profileRow(profile)
                }
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: StationProfile) -> some View {
        let isActive = profile.id == viewModel.activeProfileID
        Button {
            guard !isActive else { return }
            Task { await viewModel.switchProfile(to: profile, environment: appEnvironment) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? DS.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body)
                    Text(profile.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                profilePendingDeletion = profile
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                profilePendingRename = profile
                renameText = profile.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? "\(profile.name), active" : profile.name)
        .accessibilityHint(isActive ? "" : "Switches to this station")
    }

    private var connectionSection: some View {
        Section(connectionSectionTitle) {
            TextField("Base URL", text: $viewModel.baseURLText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    await viewModel.connect(environment: appEnvironment)
                    isAddingNewStation = false
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(connectButtonTitle)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .hidden()
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .disabled(viewModel.isBusy)

            if let report = viewModel.connectionReport {
                LabeledContent("Station", value: report.profile.name)
                LabeledContent("Status", value: report.status.displayName)
                LabeledContent("Identity", value: report.identity)
                LabeledContent("TLS", value: report.tlsState.displayName)
                LabeledContent("Security", value: report.appConfig.security.enabled ? String(localized: "Enabled") : String(localized: "Disabled"))
            } else if let active = viewModel.activeProfile {
                LabeledContent("Station", value: active.name)
                LabeledContent("Status", value: String(localized: "Not validated yet"))
            } else {
                LabeledContent("Station", value: String(localized: "Not connected"))
                LabeledContent("Status", value: String(localized: "Offline"))
            }
        }
    }

    private var accountSection: some View {
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
                LabeledContent("Authenticated", value: authStatus.authenticated ? String(localized: "Yes") : String(localized: "No"))
                if let username = authStatus.username, !username.isEmpty {
                    LabeledContent("User", value: username)
                }
                if let method = authStatus.method, !method.isEmpty {
                    LabeledContent("Method", value: method)
                }
            }
        }
    }

    private var deleteActiveSection: some View {
        Section {
            Button(role: .destructive) {
                profilePendingDeletion = viewModel.activeProfile
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete Station", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .disabled(viewModel.isBusy)
        } footer: {
            Text("Removes the active station and any stored credentials on this device.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button {
                Task { await viewModel.generateDiagnostics(environment: appEnvironment) }
            } label: {
                Label("Generate Diagnostics", systemImage: "doc.badge.gearshape")
            }
            .disabled(viewModel.isBusy)

            if let diagnosticsBundleURL = viewModel.diagnosticsBundleURL {
                ShareLink(item: diagnosticsBundleURL) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Redacts station hosts and secrets.")
        }
    }

    // MARK: - Helpers

    private var connectionSectionTitle: LocalizedStringKey {
        isAddingNewStation || viewModel.activeProfile == nil ? "New Station" : "Connection"
    }

    private var connectButtonTitle: LocalizedStringKey {
        isAddingNewStation || viewModel.activeProfile == nil ? "Connect Station" : "Connect or Switch Station"
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { profilePendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    profilePendingRename = nil
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        StationView()
    }
    .environment(\.appEnvironment, .preview)
}
