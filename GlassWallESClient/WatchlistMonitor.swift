// MARK: - GlassWall Watchlist Monitor
// Centralises path-matching logic for Suspicious Configuration Injection detection.
// Thread-safe — both ESClient (background ES queue) and the XPC update handler
// call into this concurrently.

import Foundation

final class WatchlistMonitor {

    static let shared = WatchlistMonitor()

    private let lock = NSLock()
    private var prefixes: [String]

    private init() {
        // Expand ~ to the real home directory at init time.
        prefixes = GlassWall.watchlistPaths.map {
            ($0 as NSString).expandingTildeInPath
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns true if `path` falls inside any watched directory.
    func isWatchlistPath(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return prefixes.contains { path.hasPrefix($0) }
    }

    /// Replace the watchlist with a new set of paths (called from XPC handler).
    func update(paths: [String]) {
        let expanded = paths.map { ($0 as NSString).expandingTildeInPath }
        lock.lock(); defer { lock.unlock() }
        prefixes = expanded
    }

    /// Returns the matched watchlist prefix for a given path, if any.
    func matchedPrefix(for path: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return prefixes.first { path.hasPrefix($0) }
    }

    /// Human-readable category name for UI display.
    func category(for path: String) -> String {
        guard let prefix = matchedPrefix(for: path) else { return "Unknown" }
        if prefix.contains("LaunchAgent")            { return "Launch Agent Persistence" }
        if prefix.contains("LaunchDaemon")           { return "Launch Daemon Persistence" }
        if prefix.contains("PrivilegedHelperTools")  { return "Privileged Helper Install" }
        if prefix.contains("NativeMessagingHosts")   { return "Browser Native Messaging Host" }
        return "Suspicious System Path"
    }
}
