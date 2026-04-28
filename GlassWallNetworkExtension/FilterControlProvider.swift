// MARK: - GlassWall Network Extension: Filter Control Provider
//
// NEFilterControlProvider handles flows that DataProvider returned `.needRules()`
// for. Its job is to:
//   1. Build a ConnectionEvent from the paused flow.
//   2. Send it to the main app over XPC and wait for a verdict.
//   3. Resume the flow and write the verdict back to DataProvider's cache.
//
// The OS gives us a finite window (GlassWall.flowDecisionTimeoutSeconds) before
// it auto-drops the paused flow. If the user does not respond in time we
// default to BLOCK (Zero Trust default).

import NetworkExtension
import Foundation
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.networkExtension,
                        category: "FilterControlProvider")

final class FilterControlProvider: NEFilterControlProvider {

    // ── XPC connection to the main app's Policy Engine listener ───────────────
    private var xpcConnection: NSXPCConnection?
    private let xpcQueue = DispatchQueue(label: "com.glasswall.ne.xpc")

    // ── Pending flow store: flowID → NEFilterFlow ─────────────────────────────
    // Flows are held here between needRules() and resumeFlow().
    private var pendingFlows: [FlowID: NEFilterFlow] = [:]
    private let pendingQueue = DispatchQueue(label: "com.glasswall.ne.pending",
                                             attributes: .concurrent)

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        os_log("FilterControlProvider starting", log: log, type: .info)
        connectToApp()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("FilterControlProvider stopping: %{public}d", log: log, type: .info,
               reason.rawValue)
        xpcConnection?.invalidate()
        xpcConnection = nil
        completionHandler()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: NEFilterControlProvider — handle paused flows
    // ─────────────────────────────────────────────────────────────────────────

    override func handleNewFlow(_ flow: NEFilterFlow,
                                completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint
        else {
            completionHandler(.allow(withUpdateRules: false))
            return
        }

        let flowID     = FlowID()
        let binaryPath = resolvedBinaryPath(for: flow)
        let remoteHost = remoteEndpoint.hostname
        let port       = UInt16(remoteEndpoint.port) ?? 0

        let processCtx = ProcessContext(
            pid: Self.pid(from: flow),
            name: Self.processName(from: flow),
            binaryPath: binaryPath,
            signingIdentity: Self.signingIdentity(from: flow),
            isSignatureValid: Self.isSignatureValid(from: flow)
        )

        let event = ConnectionEvent(
            id: flowID,
            process: processCtx,
            remoteHost: remoteHost,
            remotePort: port,
            direction: .outbound,
            proto: socketFlow.socketProtocol == IPPROTO_UDP ? .udp : .tcp,
            verdict: .pending
        )

        // Register this flow so we can resume it after the verdict arrives.
        pendingQueue.async(flags: .barrier) {
            self.pendingFlows[flowID] = flow
        }

        // Set a hard timeout: if the user doesn't decide in time, block.
        let deadlineItem = DispatchWorkItem { [weak self] in
            self?.applyTimeoutVerdict(flowID: flowID,
                                     cacheKey: "\(binaryPath)|\(remoteHost)",
                                     completionHandler: completionHandler)
        }
        xpcQueue.asyncAfter(deadline: .now() + GlassWall.flowDecisionTimeoutSeconds,
                            execute: deadlineItem)

        // Request verdict from main app.
        requestVerdict(for: event) { [weak self] response in
            deadlineItem.cancel()
            self?.applyVerdict(response: response,
                               cacheKey: "\(binaryPath)|\(remoteHost)",
                               completionHandler: completionHandler)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: XPC — connect to main app
    // ─────────────────────────────────────────────────────────────────────────

    private func connectToApp() {
        let conn = GlassWallXPC.policyEngineConnection()

        conn.invalidationHandler = { [weak self] in
            os_log("XPC connection to app invalidated, reconnecting…",
                   log: log, type: .error)
            self?.xpcConnection = nil
            // Exponential backoff reconnect.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                self?.connectToApp()
            }
        }

        conn.interruptionHandler = { [weak self] in
            os_log("XPC connection interrupted", log: log, type: .error)
            self?.connectToApp()
        }

        conn.resume()
        xpcConnection = conn
        os_log("XPC connection to app established", log: log, type: .info)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Verdict Application
    // ─────────────────────────────────────────────────────────────────────────

    private func requestVerdict(for event: ConnectionEvent,
                                completion: @escaping (FlowDecisionResponse) -> Void) {
        guard let conn = xpcConnection,
              let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                  os_log("XPC proxy error: %{public}@", log: log, type: .error,
                         err.localizedDescription)
                  // Default block on XPC failure.
                  completion(FlowDecisionResponse(flowID: event.id, verdict: .block))
              }) as? PolicyEngineXPCProtocol
        else {
            completion(FlowDecisionResponse(flowID: event.id, verdict: .block))
            return
        }

        guard let data = try? FlowDecisionRequest(flowID: event.id, event: event).toJSONData()
        else {
            completion(FlowDecisionResponse(flowID: event.id, verdict: .block))
            return
        }

        proxy.requestVerdict(for: data) { responseData in
            guard let response = try? responseData.decoded(as: FlowDecisionResponse.self)
            else {
                completion(FlowDecisionResponse(flowID: event.id, verdict: .block))
                return
            }
            completion(response)
        }
    }

    private func applyVerdict(response: FlowDecisionResponse,
                              cacheKey: String,
                              completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        let netVerdict: NEFilterNewFlowVerdict = response.verdict == .allow ? .allow() : .drop()
        let controlVerdict = NEFilterControlVerdict(newFlowVerdict: netVerdict,
                                                    forFlows: [])

        // Write verdict into DataProvider cache via notification (same process).
        NotificationCenter.default.post(
            name: .glasswallCacheUpdate,
            object: nil,
            userInfo: ["key": cacheKey, "verdict": response.verdict.rawValue]
        )

        pendingQueue.async(flags: .barrier) {
            self.pendingFlows.removeValue(forKey: response.flowID)
        }

        completionHandler(controlVerdict)
    }

    private func applyTimeoutVerdict(flowID: FlowID,
                                     cacheKey: String,
                                     completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        os_log("Flow verdict timeout for %{public}@, applying block",
               log: log, type: .error, flowID.uuidString)
        applyVerdict(
            response: FlowDecisionResponse(flowID: flowID, verdict: .block),
            cacheKey: cacheKey,
            completionHandler: completionHandler
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Metadata Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func resolvedBinaryPath(for flow: NEFilterFlow) -> String {
        flow.sourceAppAuditToken.flatMap { token -> String? in
            guard token.count >= 32 else { return nil }
            let pid: pid_t = token.withUnsafeBytes { $0.load(fromByteOffset: 20, as: pid_t.self) }
            var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            return proc_pidpath(pid, &buf, UInt32(MAXPATHLEN)) > 0 ? String(cString: buf) : nil
        } ?? "unknown"
    }

    private static func pid(from flow: NEFilterFlow) -> pid_t {
        guard let token = flow.sourceAppAuditToken, token.count >= 32 else { return 0 }
        return token.withUnsafeBytes { $0.load(fromByteOffset: 20, as: pid_t.self) }
    }

    private static func processName(from flow: NEFilterFlow) -> String {
        flow.sourceAppUniqueIdentifier?.description ?? "Unknown"
    }

    private static func signingIdentity(from flow: NEFilterFlow) -> String? {
        // NEFilterFlow does not expose signing identity directly.
        // Use Security framework to look it up by binary path if available.
        nil
    }

    private static func isSignatureValid(from flow: NEFilterFlow) -> Bool { false }
}
