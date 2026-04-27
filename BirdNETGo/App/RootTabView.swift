import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
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
                StatsView()
            }
            .tabItem { Label(AppTab.stats.title, systemImage: AppTab.stats.systemImage) }
            .tag(AppTab.stats)

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
