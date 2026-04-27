import Foundation

enum BirdDetectionStreamEvent: Sendable {
    case connected
    case detection(BirdDetection)
    case heartbeat
    case pending
}

struct ServerSentEventMessage: Sendable {
    private(set) var event = "message"
    private var dataLines: [String] = []

    var hasData: Bool {
        !dataLines.isEmpty
    }

    var data: Data? {
        dataLines.joined(separator: "\n").data(using: .utf8)
    }

    mutating func append(_ line: String) {
        guard !line.hasPrefix(":") else {
            return
        }

        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let field = parts.first else {
            return
        }

        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") {
            value.removeFirst()
        }

        switch field {
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
    }
}
