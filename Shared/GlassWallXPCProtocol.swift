// MARK: - GlassWall XPC Protocol Definitions
// Defines the three XPC channels used across all targets:
//   1. PolicyEngineProtocol  – NE extension → main app (verdict requests)
//   2. ESEventProtocol       – ES daemon    → main app (behaviour pushes)
//   3. AppCommandProtocol    – main app     → ES daemon (config / panic mode)
//
// All payloads are exchanged as JSON-encoded Data so every target only needs
// Foundation — no shared framework binary is required.

import Foundation

// ──────────────────────────────────────────────────────────────────────────────
// MARK: 1. Policy Engine (NE extension client → main app server)
// ──────────────────────────────────────────────────────────────────────────────

/// Implemented by the main app's XPC listener.
/// The network extension connects as a client to ask for flow verdicts and to
/// push connection telemetry that already has a cached verdict.
@objc public protocol PolicyEngineXPCProtocol {

    /// Ask the policy engine for a verdict on a new, paused flow.
    /// - Parameters:
    ///   - requestData: JSON-encoded `FlowDecisionRequest`
    ///   - reply: JSON-encoded `FlowDecisionResponse`
    func requestVerdict(for requestData: Data,
                        withReply reply: @escaping (Data) -> Void)

    /// Push a pre-resolved connection event (already allowed/blocked by cache).
    /// Used for telemetry display in LivePulseView; no reply needed.
    func pushConnectionEvent(_ eventData: Data,
                             withReply reply: @escaping () -> Void)

    /// Query whether Panic Mode is currently active.
    func queryPanicMode(withReply reply: @escaping (Bool) -> Void)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: 2. ES Events (ES daemon server → main app client)
// ──────────────────────────────────────────────────────────────────────────────

/// Implemented by the ES daemon's XPC listener.
/// The main app connects as a client to receive behaviour event streams and
/// to send watchlist / panic-mode configuration updates.
@objc public protocol ESEventXPCProtocol {

    /// Push a behaviour event from the ES daemon to the main app.
    /// - Parameter eventData: JSON-encoded `BehaviorEventPush`
    func pushBehaviorEvent(_ eventData: Data,
                           withReply reply: @escaping () -> Void)

    /// Instruct the ES daemon to enter or leave Panic Mode.
    func setPanicMode(_ enabled: Bool,
                      withReply reply: @escaping () -> Void)

    /// Replace the active watchlist with a new set of path prefixes.
    func updateWatchlist(_ pathsData: Data,
                         withReply reply: @escaping () -> Void)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: 3. App Command (main app → ES daemon, forward direction)
// ──────────────────────────────────────────────────────────────────────────────
// Kept as a separate protocol so the daemon can expose a distinct Mach service
// name and validate that only the main app binary connects.

@objc public protocol AppCommandXPCProtocol {

    /// Ping the daemon to confirm it is alive.
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// Fetch current daemon status (uptime, event count, etc.) as JSON Data.
    func fetchStatus(withReply reply: @escaping (Data) -> Void)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: XPC Connection Factories
// ──────────────────────────────────────────────────────────────────────────────

public enum GlassWallXPC {

    /// Create a client connection to the main app's Policy Engine endpoint.
    /// Called from the NetworkExtension process.
    public static func policyEngineConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: GlassWall.MachService.policyEngine,
                                   options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: PolicyEngineXPCProtocol.self)
        return conn
    }

    /// Create a client connection to the ES daemon's event endpoint.
    /// Called from the main app process.
    public static func esEventConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: GlassWall.MachService.esEvents,
                                   options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: ESEventXPCProtocol.self)
        return conn
    }

    /// Create the listener for the Policy Engine endpoint.
    /// Called from the main app to accept connections from the NE extension.
    public static func policyEngineListener() -> NSXPCListener {
        NSXPCListener(machServiceName: GlassWall.MachService.policyEngine)
    }

    /// Create the listener for the ES event endpoint.
    /// Called from the ES daemon to accept connections from the main app.
    public static func esEventListener() -> NSXPCListener {
        NSXPCListener(machServiceName: GlassWall.MachService.esEvents)
    }
}
