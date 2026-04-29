import SwiftUI

struct StationView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = StationViewModel()
    @State private var isDeleteConfirmationPresented = false
    @State private var profilePendingDeletion: StationProfile?
    @State private var profilePendingRename: StationProfile?
    @State private var renameText = ""
    @State private var isAddingNewStation = false
    @State private var didApplyInitialMode = false

    /// Optional preset that lets callers (e.g. a "+ Add Station" menu entry
    /// on the Dashboard) push this view straight into the add-station form
    /// instead of the manage view.
    let initialMode: Mode

    init(initialMode: Mode = .manage) {
        self.initialMode = initialMode
    }

    enum Mode {
        case manage
        case addStation
    }

    var body: some View {
        Form {
            if isAddingNewStation {
                addStationSection
            } else {
                stationsSection

                connectionSection

                if viewModel.activeProfile == nil {
                    addStationSection
                }

                accountSection

                if viewModel.canDeleteActiveProfile {
                    deleteActiveSection
                }

                diagnosticsSection
            }

            if let statusMessage = viewModel.statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if isAddingNewStation && viewModel.activeProfile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isAddingNewStation = false
                        Task {
                            await viewModel.restoreActiveProfileForm(environment: appEnvironment)
                        }
                    }
                    .accessibilityLabel("Cancel adding station")
                }
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)

            if !didApplyInitialMode {
                didApplyInitialMode = true
                if initialMode == .addStation {
                    isAddingNewStation = true
                    viewModel.prepareForNewStation()
                }
            }

            if appEnvironment.configuration.debugShowsDeleteStationConfirmation, viewModel.canDeleteActiveProfile {
                profilePendingDeletion = viewModel.activeProfile
                isDeleteConfirmationPresented = true
            }
        }
        .refreshable {
            if viewModel.activeProfile != nil {
                await viewModel.revalidateActiveProfile(environment: appEnvironment)
            } else {
                await viewModel.refreshAuthStatus(environment: appEnvironment)
            }
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

    @ViewBuilder
    private var connectionSection: some View {
        if let active = viewModel.activeProfile {
            Section("Connection") {
                liveStatusRow

                LabeledContent("Station", value: active.name)
                LabeledContent("URL", value: active.baseURL.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let report = viewModel.connectionReport {
                    LabeledContent("Identity", value: report.identity)
                    LabeledContent("TLS", value: report.tlsState.displayName)
                    LabeledContent(
                        "Security",
                        value: report.appConfig.security.enabled
                            ? String(localized: "Enabled")
                            : String(localized: "Disabled")
                    )
                }

                Button {
                    Task {
                        await viewModel.revalidateActiveProfile(environment: appEnvironment)
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isValidating {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Refresh Connection")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .contentShape(Rectangle())
                }
                .disabled(viewModel.isBusy || viewModel.isValidating)
            }
        }
    }

    private var liveStatusRow: some View {
        let status = viewModel.liveStatus
        return HStack(spacing: 10) {
            Image(systemName: status.systemImage)
                .foregroundStyle(statusColor(for: status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.displayName)
                    .font(.headline)
                if let subtitle = liveStatusSubtitle(for: status) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(liveStatusAccessibilityLabel(for: status))
    }

    private func statusColor(for status: StationViewModel.LiveStatus) -> Color {
        switch status {
        case .connected, .reachable:
            return .green
        case .checking:
            return .secondary
        case .unknown:
            return .orange
        case .noStation:
            return .secondary
        }
    }

    private func liveStatusSubtitle(for status: StationViewModel.LiveStatus) -> String? {
        switch status {
        case .connected:
            return String(localized: "Validated this session")
        case .reachable(let date):
            let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
            return String(localized: "Last response \(relative)")
        case .checking:
            return String(localized: "Validating connection…")
        case .unknown:
            return String(localized: "No recent response yet — pull to refresh.")
        case .noStation:
            return nil
        }
    }

    private func liveStatusAccessibilityLabel(for status: StationViewModel.LiveStatus) -> String {
        if let subtitle = liveStatusSubtitle(for: status) {
            return "\(status.displayName). \(subtitle)"
        }
        return status.displayName
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var addStationSection: some View {
        Section(viewModel.activeProfile == nil ? "Connect Your Station" : "Add Station") {
            TextField("Base URL", text: $viewModel.baseURLText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    let didConnect = await viewModel.connect(environment: appEnvironment)
                    if didConnect {
                        isAddingNewStation = false
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                    Text("Connect Station")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .disabled(viewModel.isBusy)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if viewModel.activeProfile != nil {
            Section("Account") {
                accountFields

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
    }

    @ViewBuilder
    private var accountFields: some View {
        // We always render the credential fields when an active profile
        // exists so users can see and edit saved Keychain values without
        // having to tap Connect. The Log In button is only enabled once
        // we've confirmed the station advertises basic auth.
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

        if viewModel.connectionReport == nil {
            Text("Refresh the connection to enable login.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !viewModel.canLogIn {
            Text("This station does not advertise direct password login.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button {
            Task { await viewModel.logIn(environment: appEnvironment) }
        } label: {
            Label("Log In", systemImage: "person.badge.key")
        }
        .disabled(viewModel.isBusy || !viewModel.canLogIn)

        Button(role: .destructive) {
            Task { await viewModel.logOut(environment: appEnvironment) }
        } label: {
            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .disabled(viewModel.isBusy || !viewModel.canLogOut)
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

    private var navigationTitle: LocalizedStringKey {
        if isAddingNewStation {
            return "Add Station"
        }
        return "Station Management"
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
