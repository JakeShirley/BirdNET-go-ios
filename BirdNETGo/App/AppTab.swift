import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case feed
    case species
    case stats
    case station

    var id: Self { self }

    init?(launchArgumentValue: String) {
        switch launchArgumentValue.lowercased() {
        case "feed":
            self = .feed
        case "species":
            self = .species
        case "stats":
            self = .stats
        case "station":
            self = .station
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .feed:
            "Feed"
        case .species:
            "Species"
        case .stats:
            "Stats"
        case .station:
            "Station"
        }
    }

    var systemImage: String {
        switch self {
        case .feed:
            "list.bullet"
        case .species:
            "leaf"
        case .stats:
            "chart.bar"
        case .station:
            "antenna.radiowaves.left.and.right"
        }
    }

    static func initialTab(from arguments: [String] = ProcessInfo.processInfo.arguments) -> AppTab {
        guard let argumentIndex = arguments.firstIndex(of: "-initialTab"), arguments.indices.contains(argumentIndex + 1) else {
            return .feed
        }

        return AppTab(launchArgumentValue: arguments[argumentIndex + 1]) ?? .feed
    }
}
