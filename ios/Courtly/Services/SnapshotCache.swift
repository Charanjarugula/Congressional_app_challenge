import Foundation

/// The last copy of each screen's data, so tabs paint before the network answers and work offline.
enum SnapshotCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: "\(key).json")) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        try? data.write(to: directory.appending(path: "\(key).json"), options: .atomic)
    }

    static func remove(key: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: "\(key).json"))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
