import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case dashboard
    case feed
    case species
    case station

    var id: Self { self }

    init?(launchArgumentValue: String) {
        switch launchArgumentValue.lowercased() {
        case "dashboard", "stats":
            self = .dashboard
        case "feed":
            self = .feed
        case "species":
            self = .species
        case "station":
            self = .station
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .dashboard:
            "Dashboard"
        case .feed:
            "Feed"
        case .species:
            "Species"
        case .station:
            "Station"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "chart.bar"
        case .feed:
            "list.bullet"
        case .species:
            "leaf"
        case .station:
            "antenna.radiowaves.left.and.right"
        }
    }

    static func initialTab(from arguments: [String] = ProcessInfo.processInfo.arguments) -> AppTab {
        guard let argumentIndex = arguments.firstIndex(of: "-initialTab"), arguments.indices.contains(argumentIndex + 1) else {
            return .dashboard
        }

        return AppTab(launchArgumentValue: arguments[argumentIndex + 1]) ?? .dashboard
    }
}
