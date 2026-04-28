// MARK: - GlassWall ES Daemon: XPC Server
// Exposes the ESEventXPCProtocol endpoint that the main app connects to.
// Receives ESClient events and forwards them to all connected app clients.
// Also handles inbound commands: panic mode toggle, watchlist updates.

import Foundation
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.esClient, category: "ESXPCServer")

final class ESXPCServer: NSObject {

    private var listener: NSXPCListener?

    // All active app connections (there should only be one, but handle
    // reconnects gracefully).
    private var connections: [NSXPCConnection] = []
    private let connectionsLock = NSLock()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    func start() {
        let l = GlassWallXPC.esEventListener()
        l.delegate = self
        l.resume()
        listener = l
        os_log("ESXPCServer listening on %{public}@",
               log: log, type: .info, GlassWall.MachService.esEvents)
    }

    func stop() {
        listener?.invalidate()
        listener = nil
        connectionsLock.lock(); defer { connectionsLock.unlock() }
        connections.forEach { $0.invalidate() }
        connections.removeAll()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Event Broadcast
    // ─────────────────────────────────────────────────────────────────────────

    /// Called by ESClient.delegate — push the event to all connected apps.
    func broadcast(event: BehaviorEvent) {
        guard let data = try? BehaviorEventPush(event: event).toJSONData() else { return }

        connectionsLock.lock()
        let snapshot = connections
        connectionsLock.unlock()

        for conn in snapshot {
            guard let proxy = conn.remoteObjectProxy as? ESEventXPCProtocol else { continue }
            proxy.pushBehaviorEvent(data) {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: NSXPCListenerDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension ESXPCServer: NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate that the connecting process is the GlassWall app.
        // In production, verify the code-signing requirement here using
        // Security.framework SecCodeCopyGuestWithAttributes / SecRequirementCreateWithString.
        guard isConnectionFromApp(newConnection) else {
            os_log("Rejected XPC connection from untrusted process", log: log, type: .error)
            return false
        }

        newConnection.remoteObjectInterface = NSXPCInterface(with: ESEventXPCProtocol.self)
        newConnection.exportedInterface     = NSXPCInterface(with: ESEventXPCProtocol.self)
        newConnection.exportedObject        = self

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            os_log("App XPC connection invalidated", log: log, type: .info)
            self.connectionsLock.lock(); defer { self.connectionsLock.unlock() }
            self.connections.removeAll { $0 === conn }
        }

        newConnection.resume()

        connectionsLock.lock(); defer { connectionsLock.unlock() }
        connections.append(newConnection)

        os_log("App XPC connection accepted (%{public}d active)",
               log: log, type: .info, connections.count)
        return true
    }

    // Minimal check: verify the connecting process's bundle ID.
    // Replace with SecRequirement validation in production.
    private func isConnectionFromApp(_ conn: NSXPCConnection) -> Bool {
        let pid = conn.processIdentifier
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(MAXPATHLEN)) > 0 else { return false }
        let path = String(cString: buf)
        // Ensure the connecting binary lives inside the GlassWall.app bundle.
        return path.contains("GlassWall.app")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: ESEventXPCProtocol (server-side implementation)
// ─────────────────────────────────────────────────────────────────────────────

extension ESXPCServer: ESEventXPCProtocol {

    func pushBehaviorEvent(_ eventData: Data, withReply reply: @escaping () -> Void) {
        // Server-side stub — the daemon only sends events, never receives them
        // via this method. The protocol is symmetric to allow the same interface
        // object, but this direction is unused.
        reply()
    }

    func setPanicMode(_ enabled: Bool, withReply reply: @escaping () -> Void) {
        os_log("Panic mode set to %{public}@", log: log, type: .info,
               enabled ? "ON" : "OFF")
        // Notify ESClient to adjust behaviour (e.g., increase alert verbosity).
        NotificationCenter.default.post(
            name: .glasswallPanicModeChanged,
            object: nil,
            userInfo: ["enabled": enabled]
        )
        reply()
    }

    func updateWatchlist(_ pathsData: Data, withReply reply: @escaping () -> Void) {
        guard let paths = try? pathsData.decoded(as: [String].self) else {
            reply(); return
        }
        WatchlistMonitor.shared.update(paths: paths)
        os_log("Watchlist updated: %{public}d paths", log: log, type: .info, paths.count)
        reply()
    }
}

extension Notification.Name {
    static let glasswallPanicModeChanged = Notification.Name("com.glasswall.es.panicMode")
}
