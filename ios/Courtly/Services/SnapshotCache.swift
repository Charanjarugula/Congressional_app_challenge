import Foundation

/// The last copy of each screen's data, so tabs paint before the network answers and work offline.
/// Each account's files live in their own folder: a write that lands late, from an account that is
/// no longer signed in, goes to that account's folder and is never read by the next one.
enum SnapshotCache {
    /// Bump when a cached model or the folder layout changes; older folders are removed on first use.
    private static let version = 3

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "snapshots-v\(version)")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: base.appending(path: "snapshots"))
            for older in 1..<version { try? FileManager.default.removeItem(at: base.appending(path: "snapshots-v\(older)")) }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// The signed-in player's own folder; without an account, the shared one (the profile itself).
    private static func file(_ key: String, account: UUID?) -> URL {
        var dir = root
        if let account {
            dir = dir.appending(path: account.uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appending(path: "\(key).json")
    }

    static func load<T: Decodable>(_ type: T.Type, key: String, account: UUID? = nil) -> T? {
        guard let data = try? Data(contentsOf: file(key, account: account)) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String, account: UUID? = nil) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        try? data.write(to: file(key, account: account), options: .atomic)
    }

    static func remove(key: String, account: UUID? = nil) {
        try? FileManager.default.removeItem(at: file(key, account: account))
    }

    /// Everything, every account's folder included: the device forgets the player who signed out.
    static func clear() {
        try? FileManager.default.removeItem(at: root)
    }
}
