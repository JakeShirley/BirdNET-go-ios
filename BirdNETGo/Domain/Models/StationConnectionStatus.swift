import Foundation

enum StationConnectionStatus: Equatable, Sendable {
    case unknown
    case reachable
    case unreachable

    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .reachable:
            return "Reachable"
        case .unreachable:
            return "Unreachable"
        }
    }
}

enum StationTLSState: Equatable, Sendable {
    case secureHTTPS
    case localPlainHTTP
    case insecurePlainHTTP

    var displayName: String {
        switch self {
        case .secureHTTPS:
            return "HTTPS"
        case .localPlainHTTP:
            return "Local HTTP"
        case .insecurePlainHTTP:
            return "HTTP"
        }
    }
}

struct StationConnectionReport: Equatable, Sendable {
    var profile: StationProfile
    var status: StationConnectionStatus
    var tlsState: StationTLSState
    var appConfig: StationAppConfig

    var requiresAuthentication: Bool {
        appConfig.security.enabled && !appConfig.security.accessAllowed
    }

    var identity: String {
        appConfig.version.isEmpty ? "BirdNET-Go" : "BirdNET-Go \(appConfig.version)"
    }
}

enum StationURLValidator {
    static func normalizedURL(from text: String) throws -> URL {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw StationConnectionError.invalidURL
        }

        let candidateText = trimmedText.contains("://") ? trimmedText : "http://\(trimmedText)"
        guard var components = URLComponents(string: candidateText) else {
            throw StationConnectionError.invalidURL
        }

        components.scheme = components.scheme?.lowercased()
        guard components.scheme == "http" || components.scheme == "https" else {
            throw StationConnectionError.unsupportedScheme
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw StationConnectionError.missingHost
        }

        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty {
            components.path = "/\(components.path)"
        }
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw StationConnectionError.invalidURL
        }

        return url
    }

    static func tlsState(for url: URL) -> StationTLSState {
        if url.scheme?.lowercased() == "https" {
            return .secureHTTPS
        }

        if let host = url.host(percentEncoded: false), isLocalHost(host) {
            return .localPlainHTTP
        }

        return .insecurePlainHTTP
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let lowercasedHost = host.lowercased()
        if lowercasedHost == "localhost" || lowercasedHost.hasSuffix(".local") {
            return true
        }

        let octets = lowercasedHost.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else {
            return false
        }

        if octets[0] == 10 || octets[0] == 127 {
            return true
        }

        if octets[0] == 172 && (16...31).contains(octets[1]) {
            return true
        }

        return octets[0] == 192 && octets[1] == 168
    }
}
