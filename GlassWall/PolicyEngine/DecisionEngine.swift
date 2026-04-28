// MARK: - GlassWall Decision Engine
// Implements the rule resolution state machine.
//
// Precedence (lowest index wins):
//   0. Blacklist  → always block, regardless of domain
//   1. Jail       → block for session
//   2. Incognito  → allow for limited time window
//   3. Whitelist  → always allow
//
// If no rule matches → PENDING (triggers user prompt).
// Panic Mode overrides everything: only clean-room domains pass.

import Foundation

final class DecisionEngine {

    private let ruleStore: RuleStore

    init(ruleStore: RuleStore) {
        self.ruleStore = ruleStore
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Resolution
    // ─────────────────────────────────────────────────────────────────────────

    /// Synchronously resolves a verdict for an incoming connection event.
    /// Returns `.pending` if user interaction is required.
    func resolve(event: ConnectionEvent, panicMode: Bool) -> FlowDecisionResponse {
        let binary = event.process.binaryPath
        let domain = event.remoteHost

        // ── Panic Mode override ───────────────────────────────────────────────
        if panicMode {
            let allowed = GlassWall.cleanRoomAllowedDomains
                .contains { domain.hasSuffix($0) }
            return FlowDecisionResponse(
                flowID:   event.id,
                verdict:  allowed ? .allow : .block,
                ruleKind: allowed ? .whitelist : .blacklist
            )
        }

        // ── Rule lookup ───────────────────────────────────────────────────────
        guard let rule = ruleStore.resolve(binaryPath: binary, domain: domain) else {
            return FlowDecisionResponse(flowID: event.id, verdict: .pending)
        }

        let verdict: Verdict
        switch rule.kind {
        case .whitelist, .incognito:
            verdict = .allow
        case .jail, .blacklist:
            verdict = .block
        }

        return FlowDecisionResponse(flowID: event.id, verdict: verdict, ruleKind: rule.kind)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Rule Creation from User Decision
    // ─────────────────────────────────────────────────────────────────────────

    /// Converts a user intent into a PolicyRule and stores it.
    @discardableResult
    func record(decision kind: RuleKind, for event: ConnectionEvent) -> PolicyRule {
        let expiresAt: Date? = kind == .incognito
            ? Date().addingTimeInterval(GlassWall.incognitoDuration)
            : nil

        // Blacklist applies to the entire binary regardless of domain.
        let domain: String? = kind == .blacklist ? nil : event.remoteHost

        let rule = PolicyRule(
            kind:       kind,
            binaryPath: event.process.binaryPath,
            domain:     domain,
            expiresAt:  expiresAt
        )

        ruleStore.add(rule)
        return rule
    }
}
