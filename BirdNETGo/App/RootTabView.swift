import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: AppTab

    init(initialTab: AppTab = .dashboard) {
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                StatsView()
            }
            .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
            .tag(AppTab.dashboard)

            NavigationStack {
                FeedView()
            }
            .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage) }
            .tag(AppTab.feed)

            NavigationStack {
                SpeciesView()
            }
            .tabItem { Label(AppTab.species.title, systemImage: AppTab.species.systemImage) }
            .tag(AppTab.species)

            NavigationStack {
                StationView()
            }
            .tabItem { Label(AppTab.station.title, systemImage: AppTab.station.systemImage) }
            .tag(AppTab.station)
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, .preview)
}
