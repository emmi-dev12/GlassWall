// MARK: - GlassWall Network Extension: Filter Data Provider
//
// NEFilterDataProvider runs inside the system-extension process sandbox.
// It is the hot path for every new network flow:
//   1. Check the local rule cache (zero XPC latency for known binaries).
//   2. If uncached, pause the flow and hand it to FilterControlProvider
//      via `needRules()` — the OS bridges the two providers internally.
//   3. FilterControlProvider contacts the main app over XPC and returns
//      a verdict, which is applied via `resumeFlow(_:withVerdict:)`.
//
// Performance contract:
//   • handleNewFlow must return synchronously — do not block.
//   • Cache hits must be O(1) dictionary lookups.
//   • All XPC work happens in FilterControlProvider.

import NetworkExtension
import Foundation
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.networkExtension,
                        category: "FilterDataProvider")

final class FilterDataProvider: NEFilterDataProvider {

    // ── Rule Cache ────────────────────────────────────────────────────────────
    // A lightweight in-process cache populated by FilterControlProvider after
    // each verdict. Keyed by "binaryPath|domain" for per-process/per-domain
    // granularity.  Access only on `cacheQueue`.

    private let cacheQueue = DispatchQueue(label: "com.glasswall.ne.cache",
                                           attributes: .concurrent)
    private var verdictCache: [String: Verdict] = [:]

    // ── Panic Mode ────────────────────────────────────────────────────────────
    // Written by FilterControlProvider when the app broadcasts a panic toggle.
    private var panicModeActive: Bool = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: NEFilterDataProvider lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        os_log("FilterDataProvider starting", log: log, type: .info)

        // Receive cache invalidation / panic-mode updates from the control
        // provider via shared NEFilterProvider storage (no XPC needed here).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCacheUpdate(_:)),
            name: .glasswallCacheUpdate,
            object: nil
        )

        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("FilterDataProvider stopping: %{public}d", log: log, type: .info,
               reason.rawValue)
        NotificationCenter.default.removeObserver(self)
        completionHandler()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Flow Handling (hot path)
    // ─────────────────────────────────────────────────────────────────────────

    override func handleNewFlow(_ flow: NEFilterFlow) -> NENewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint
        else {
            // Non-TCP/UDP or unknown flow type — allow by default so the OS
            // remains functional.
            return .allow()
        }

        let binaryPath = flow.sourceAppAuditToken
            .map { Self.resolveBinaryPath(from: $0) } ?? "unknown"
        let remoteHost = remoteEndpoint.hostname
        let port       = UInt16(remoteEndpoint.port) ?? 0
        let cacheKey   = "\(binaryPath)|\(remoteHost)"

        // ── Panic Mode: drop everything not on the clean-room allow list ──
        if panicModeActive {
            let isCleanRoomHost = GlassWall.cleanRoomAllowedDomains
                .contains { remoteHost.hasSuffix($0) }
            if !isCleanRoomHost {
                os_log("PanicMode: blocking %{public}@ → %{public}@",
                       log: log, type: .default, binaryPath, remoteHost)
                return .drop()
            }
            return .allow()
        }

        // ── Cache lookup ──────────────────────────────────────────────────────
        var cachedVerdict: Verdict?
        cacheQueue.sync {
            cachedVerdict = verdictCache[cacheKey]
        }

        if let verdict = cachedVerdict {
            os_log("Cache hit %{public}@ → %{public}@ : %{public}@",
                   log: log, type: .debug, binaryPath, remoteHost, verdict.rawValue)
            return verdict == .allow ? .allow() : .drop()
        }

        // ── Unknown flow: defer to FilterControlProvider ───────────────────
        os_log("Cache miss, deferring %{public}@ → %{public}@:%{public}d",
               log: log, type: .default, binaryPath, remoteHost, port)

        // Store metadata so the control provider can reconstruct the event
        // without re-inspecting the flow object (which may not be available).
        let meta = FlowMetadata(
            binaryPath: binaryPath,
            remoteHost: remoteHost,
            remotePort: port,
            proto: socketFlow.socketProtocol == IPPROTO_UDP ? .udp : .tcp
        )
        storeFlowMetadata(meta, forKey: cacheKey)

        return .needRules()
    }

    // Called for subsequent packets on a flow whose verdict is already known.
    override func handleInboundData(from flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    override func handleOutboundData(from flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Cache Management (called by FilterControlProvider)
    // ─────────────────────────────────────────────────────────────────────────

    func cacheVerdict(_ verdict: Verdict, forKey key: String) {
        cacheQueue.async(flags: .barrier) {
            self.verdictCache[key] = verdict
        }
    }

    func invalidateCache(forBinaryPath path: String) {
        cacheQueue.async(flags: .barrier) {
            self.verdictCache = self.verdictCache.filter { !$0.key.hasPrefix(path) }
        }
    }

    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.verdictCache.removeAll()
        }
    }

    func setPanicMode(_ enabled: Bool) {
        panicModeActive = enabled
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func handleCacheUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let key      = userInfo["key"]     as? String,
              let rawValue = userInfo["verdict"]  as? String,
              let verdict  = Verdict(rawValue: rawValue)
        else { return }
        cacheVerdict(verdict, forKey: key)
    }

    /// Resolve binary path from an audit token using libproc.
    /// Returns "unknown" if the token cannot be resolved (sandboxed extension
    /// has limited proc_pidpath access).
    private static func resolveBinaryPath(from token: Data) -> String {
        // Audit tokens are 32-byte opaque structs; the PID sits at offset 5
        // (uint32 index) in the audit_token_t layout on both arm64 and x86_64.
        guard token.count >= 32 else { return "unknown" }
        let pid: pid_t = token.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 20, as: pid_t.self)
        }
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN))
        return result > 0 ? String(cString: pathBuf) : "unknown(pid:\(pid))"
    }

    /// Stash flow metadata in NEFilterProvider's shared storage so the control
    /// provider — running in the same extension process — can read it without XPC.
    private func storeFlowMetadata(_ meta: FlowMetadata, forKey key: String) {
        guard let data = try? meta.toJSONData() else { return }
        filterConfiguration.vendorConfiguration?[key] = data.base64EncodedString()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Flow Metadata (shared between DataProvider and ControlProvider)
// ─────────────────────────────────────────────────────────────────────────────

struct FlowMetadata: Codable {
    let binaryPath: String
    let remoteHost: String
    let remotePort: UInt16
    let proto: TransportProtocol
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Notification Names
// ─────────────────────────────────────────────────────────────────────────────

extension Notification.Name {
    static let glasswallCacheUpdate = Notification.Name("com.glasswall.ne.cacheUpdate")
}
