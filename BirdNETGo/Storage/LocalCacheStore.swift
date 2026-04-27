import Foundation

struct LocalCacheKey: Hashable, Sendable {
    var namespace: String
    var identifier: String
}


protocol LocalCacheStore: Sendable {
    func loadData(for key: LocalCacheKey) async throws -> Data?
    func saveData(_ data: Data?, for key: LocalCacheKey) async throws
    func removeAllData(in namespace: String) async throws
}

actor FileSystemLocalCacheStore: LocalCacheStore {
    private let rootDirectory: URL

    init(rootDirectory: URL = FileSystemLocalCacheStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
    }

    func loadData(for key: LocalCacheKey) async throws -> Data? {
        let fileURL = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try Data(contentsOf: fileURL)
    }

    func saveData(_ data: Data?, for key: LocalCacheKey) async throws {
        let namespaceDirectory = directoryURL(for: key.namespace)
        let fileURL = fileURL(for: key)

        guard let data else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    func removeAllData(in namespace: String) async throws {
        let directoryURL = directoryURL(for: namespace)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: directoryURL)
    }

    private func directoryURL(for namespace: String) -> URL {
        rootDirectory.appending(path: sanitizedPathComponent(namespace), directoryHint: .isDirectory)
    }

    private func fileURL(for key: LocalCacheKey) -> URL {
        directoryURL(for: key.namespace)
            .appending(path: sanitizedPathComponent(key.identifier), directoryHint: .notDirectory)
            .appendingPathExtension("json")
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "default" : sanitized
    }

    private static func defaultRootDirectory() -> URL {
        if let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupportURL.appending(path: "BirdNETGo/LocalCache", directoryHint: .isDirectory)
        }

        return FileManager.default.temporaryDirectory.appending(path: "BirdNETGo/LocalCache", directoryHint: .isDirectory)
    }
}