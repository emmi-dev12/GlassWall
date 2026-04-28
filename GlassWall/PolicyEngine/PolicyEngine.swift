// MARK: - GlassWall Policy Engine
// The central coordinator in the main app process. It:
//   1. Listens on the XPC policy endpoint for verdict requests from the NE.
//   2. Resolves known flows immediately via DecisionEngine / RuleStore.
//   3. Enqueues pending flows to the UI and waits for user decisions.
//   4. Broadcasts resolved verdicts back over XPC.
//   5. Receives BehaviorEvents from the ES daemon and publishes them to the UI.
//   6. Manages Panic Mode state.

import Foundation
import Combine
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.app, category: "PolicyEngine")

@MainActor
final class PolicyEngine: NSObject, ObservableObject {

    // ── Sub-components ────────────────────────────────────────────────────────
    let ruleStore      = RuleStore()
    private lazy var decisionEngine = DecisionEngine(ruleStore: ruleStore)

    // ── Published state (drives SwiftUI) ─────────────────────────────────────
    @Published var connectionEvents: [ConnectionEvent]  = []
    @Published var behaviorEvents:   [BehaviorEvent]    = []
    @Published var pendingFlows:     [ConnectionEvent]  = []
    @Published var panicMode:        PanicModeState     = .disabled

    // ── XPC infrastructure ────────────────────────────────────────────────────
    private var xpcListener:   NSXPCListener?
    private var esConnection:  NSXPCConnection?
    private var pendingReplies: [FlowID: (Data) -> Void] = [:]
    private let xpcQueue = DispatchQueue(label: "com.glasswall.pe.xpc")

    // ── Event batch buffer (throttles LivePulseView updates) ─────────────────
    private var eventBuffer: [ConnectionEvent] = []
    private var bufferTimer: Timer?

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    func start() {
        startXPCListener()
        connectToESDaemon()
        startBufferFlushTimer()
        ruleStore.clearSessionRules()
        os_log("PolicyEngine started", log: log, type: .info)
    }

    func stop() {
        xpcListener?.invalidate()
        xpcListener = nil
        esConnection?.invalidate()
        esConnection = nil
        bufferTimer?.invalidate()
        bufferTimer = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: XPC Listener (receives from NE extension)
    // ─────────────────────────────────────────────────────────────────────────

    private func startXPCListener() {
        let listener = GlassWallXPC.policyEngineListener()
        listener.delegate = self
        listener.resume()
        xpcListener = listener
        os_log("Policy Engine XPC listener started", log: log, type: .info)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: ES Daemon Connection
    // ─────────────────────────────────────────────────────────────────────────

    private func connectToESDaemon() {
        let conn = GlassWallXPC.esEventConnection()
        conn.exportedInterface = NSXPCInterface(with: ESEventXPCProtocol.self)
        conn.exportedObject    = self  // Receive pushBehaviorEvent calls.

        conn.invalidationHandler = { [weak self] in
            os_log("ES daemon connection lost, reconnecting…", log: log, type: .error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self?.connectToESDaemon()
            }
        }

        conn.resume()
        esConnection = conn
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Verdict Request Handler (called from XPC, then dispatched to main)
    // ─────────────────────────────────────────────────────────────────────────

    private func handleVerdictRequest(requestData: Data,
                                      reply: @escaping (Data) -> Void) {
        guard let request = try? requestData.decoded(as: FlowDecisionRequest.self) else {
            let err = FlowDecisionResponse(flowID: UUID(), verdict: .block)
            reply((try? err.toJSONData()) ?? Data())
            return
        }

        let response = decisionEngine.resolve(event: request.event,
                                              panicMode: panicMode.isEnabled)

        if response.verdict != .pending {
            // Known rule — respond immediately.
            let event = annotated(request.event, with: response)
            appendToBuffer(event)
            sendReply(response, via: reply)
            return
        }

        // No rule — park the reply and show the Intent Card.
        pendingReplies[request.flowID] = reply
        pendingFlows.append(request.event)

        os_log("Pending flow %{public}@ from %{public}@ → %{public}@",
               log: log, type: .default,
               request.flowID.uuidString,
               request.event.process.name,
               request.event.remoteHost)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: User Decision (called from Intent Card)
    // ─────────────────────────────────────────────────────────────────────────

    func applyDecision(kind: RuleKind, for event: ConnectionEvent) {
        let rule     = decisionEngine.record(decision: kind, for: event)
        let verdict: Verdict = (kind == .whitelist || kind == .incognito) ? .allow : .block
        let response = FlowDecisionResponse(flowID: event.id, verdict: verdict,
                                            ruleKind: rule.kind)

        // Resolve the parked XPC reply.
        if let reply = pendingReplies.removeValue(forKey: event.id) {
            sendReply(response, via: reply)
        }

        // Update published flow list.
        pendingFlows.removeAll { $0.id == event.id }
        appendToBuffer(annotated(event, with: response))

        os_log("User decision: %{public}@ for %{public}@→%{public}@",
               log: log, type: .info,
               kind.rawValue, event.process.name, event.remoteHost)
    }

    func dismissPendingFlow(_ event: ConnectionEvent) {
        // Block if the user dismisses without deciding (safe default).
        applyDecision(kind: .jail, for: event)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Panic Mode
    // ─────────────────────────────────────────────────────────────────────────

    func setPanicMode(_ enabled: Bool) {
        panicMode = enabled
            ? PanicModeState(isEnabled: true, enabledAt: Date())
            : .disabled

        // Notify ES daemon.
        (esConnection?.remoteObjectProxy as? ESEventXPCProtocol)?
            .setPanicMode(enabled) {}

        let defaults = UserDefaults(suiteName: GlassWall.appGroupID) ?? .standard
        defaults.set(enabled, forKey: GlassWall.DefaultsKey.panicModeEnabled)

        os_log("Panic mode: %{public}@", log: log, type: .info, enabled ? "ON" : "OFF")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Event Buffer (throttle LivePulseView)
    // ─────────────────────────────────────────────────────────────────────────

    private func startBufferFlushTimer() {
        bufferTimer = Timer.scheduledTimer(
            withTimeInterval: GlassWall.pulseFlushInterval,
            repeats: true
        ) { [weak self] _ in
            self?.flushBuffer()
        }
    }

    private func appendToBuffer(_ event: ConnectionEvent) {
        eventBuffer.append(event)
        if eventBuffer.count >= GlassWall.pulseEventBatchSize { flushBuffer() }
    }

    private func flushBuffer() {
        guard !eventBuffer.isEmpty else { return }
        let batch = eventBuffer
        eventBuffer.removeAll(keepingCapacity: true)
        connectionEvents.insert(contentsOf: batch, at: 0)
        // Cap the displayed list to avoid unbounded memory growth.
        if connectionEvents.count > 1000 {
            connectionEvents = Array(connectionEvents.prefix(1000))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func sendReply(_ response: FlowDecisionResponse, via reply: (Data) -> Void) {
        let data = (try? response.toJSONData()) ?? Data()
        reply(data)
    }

    private func annotated(_ event: ConnectionEvent,
                            with response: FlowDecisionResponse) -> ConnectionEvent {
        var copy    = event
        copy.verdict  = response.verdict
        copy.ruleKind = response.ruleKind
        return copy
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: NSXPCListenerDelegate (accept NE connections)
// ─────────────────────────────────────────────────────────────────────────────

extension PolicyEngine: NSXPCListenerDelegate {

    nonisolated func listener(_ listener: NSXPCListener,
                              shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: PolicyEngineXPCProtocol.self)
        conn.exportedObject    = self

        conn.invalidationHandler = {
            os_log("NE connection invalidated", log: log, type: .info)
        }

        conn.resume()
        return true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: PolicyEngineXPCProtocol (serve NE extension requests)
// ─────────────────────────────────────────────────────────────────────────────

extension PolicyEngine: PolicyEngineXPCProtocol {

    nonisolated func requestVerdict(for requestData: Data,
                                    withReply reply: @escaping (Data) -> Void) {
        Task { @MainActor in
            self.handleVerdictRequest(requestData: requestData, reply: reply)
        }
    }

    nonisolated func pushConnectionEvent(_ eventData: Data,
                                         withReply reply: @escaping () -> Void) {
        guard let event = try? eventData.decoded(as: ConnectionEvent.self) else {
            reply(); return
        }
        Task { @MainActor in
            self.appendToBuffer(event)
        }
        reply()
    }

    nonisolated func queryPanicMode(withReply reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            reply(self.panicMode.isEnabled)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: ESEventXPCProtocol (receive ES daemon pushes)
// ─────────────────────────────────────────────────────────────────────────────

extension PolicyEngine: ESEventXPCProtocol {

    nonisolated func pushBehaviorEvent(_ eventData: Data,
                                       withReply reply: @escaping () -> Void) {
        guard let push = try? eventData.decoded(as: BehaviorEventPush.self) else {
            reply(); return
        }
        Task { @MainActor in
            self.behaviorEvents.insert(push.event, at: 0)
            if self.behaviorEvents.count > 500 {
                self.behaviorEvents = Array(self.behaviorEvents.prefix(500))
            }
        }
        reply()
    }

    nonisolated func setPanicMode(_ enabled: Bool, withReply reply: @escaping () -> Void) {
        reply()  // No-op: main app drives ES daemon, not vice versa.
    }

    nonisolated func updateWatchlist(_ pathsData: Data, withReply reply: @escaping () -> Void) {
        reply()
    }
}
