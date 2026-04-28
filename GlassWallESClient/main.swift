// MARK: - GlassWall ES Daemon Entry Point
// Runs as a LaunchDaemon (root) with the EndpointSecurity entitlement.
// Lifecycle: launchd starts this binary at boot; it runs indefinitely.

import Foundation
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.esClient, category: "main")

// ── Wire up components ────────────────────────────────────────────────────────

let xpcServer = ESXPCServer()
let esClient  = ESClient()

// ESClient events → XPC broadcast to main app.
class EventRelay: ESClientDelegate {
    func esClient(_ client: ESClient, didObserve event: BehaviorEvent) {
        xpcServer.broadcast(event: event)
    }
}
let relay = EventRelay()
esClient.delegate = relay

// Panic-mode notification from XPC server → log (ESClient is detect-only).
NotificationCenter.default.addObserver(
    forName: .glasswallPanicModeChanged,
    object: nil,
    queue: nil
) { note in
    let enabled = note.userInfo?["enabled"] as? Bool ?? false
    os_log("Panic mode relay: %{public}@", log: log, type: .info,
           enabled ? "ON" : "OFF")
}

// ── Start ─────────────────────────────────────────────────────────────────────

do {
    xpcServer.start()
    try esClient.start()
    os_log("GlassWall ES daemon running", log: log, type: .info)
} catch {
    os_log("Failed to start ESClient: %{public}@", log: log, type: .fault,
           error.localizedDescription)
    exit(EXIT_FAILURE)
}

// ── Run loop ──────────────────────────────────────────────────────────────────

// Handle SIGTERM gracefully (launchd sends this on system shutdown).
signal(SIGTERM) { _ in
    os_log("Received SIGTERM, shutting down", log: log, type: .info)
    esClient.stop()
    xpcServer.stop()
    exit(EXIT_SUCCESS)
}

RunLoop.main.run()
