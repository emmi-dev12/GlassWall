// MARK: - GlassWall Rule Store
// Persists PolicyRule objects to the shared App Group UserDefaults container.
// Session-scoped (jail) rules live only in memory and are not persisted.
// Thread-safe via a serial dispatch queue.

import Foundation
import Combine

final class RuleStore: ObservableObject {

    @Published private(set) var rules: [PolicyRule] = []

    private let queue = DispatchQueue(label: "com.glasswall.rulestore")
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: GlassWall.appGroupID) ?? .standard
        loadFromDisk()
        pruneExpired()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: CRUD
    // ─────────────────────────────────────────────────────────────────────────

    func add(_ rule: PolicyRule) {
        queue.async { [weak self] in
            guard let self else { return }
            // Remove any conflicting rule for the same (binary, domain) pair
            // that has lower or equal precedence.
            var current = rules
            current.removeAll {
                $0.binaryPath == rule.binaryPath &&
                $0.domain == rule.domain &&
                $0.kind.precedence >= rule.kind.precedence
            }
            current.append(rule)
            DispatchQueue.main.async { self.rules = current }
            if rule.kind != .jail { self.persistToDisk(current) }
        }
    }

    func remove(id: RuleID) {
        queue.async { [weak self] in
            guard let self else { return }
            var current = rules
            current.removeAll { $0.id == id }
            DispatchQueue.main.async { self.rules = current }
            self.persistToDisk(current)
        }
    }

    func removeAll(forBinaryPath path: String) {
        queue.async { [weak self] in
            guard let self else { return }
            var current = rules
            current.removeAll { $0.binaryPath == path }
            DispatchQueue.main.async { self.rules = current }
            self.persistToDisk(current)
        }
    }

    /// Remove all .jail and .incognito rules (called at app launch / session reset).
    func clearSessionRules() {
        queue.async { [weak self] in
            guard let self else { return }
            let current = rules.filter { $0.kind == .whitelist || $0.kind == .blacklist }
            DispatchQueue.main.async { self.rules = current }
            self.persistToDisk(current)
        }
    }

    /// Remove expired .incognito rules.
    func pruneExpired() {
        queue.async { [weak self] in
            guard let self else { return }
            let current = rules.filter { !$0.isExpired }
            if current.count != rules.count {
                DispatchQueue.main.async { self.rules = current }
                self.persistToDisk(current)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lookup
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns the highest-priority non-expired rule for a (binary, domain) pair,
    /// or nil if no matching rule exists.
    func resolve(binaryPath: String, domain: String) -> PolicyRule? {
        rules
            .filter { rule in
                rule.binaryPath == binaryPath &&
                (rule.domain == nil || rule.domain == domain) &&
                !rule.isExpired
            }
            .min(by: { $0.kind.precedence < $1.kind.precedence })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Persistence
    // ─────────────────────────────────────────────────────────────────────────

    private func persistToDisk(_ rules: [PolicyRule]) {
        // Only persist permanent rules.
        let permanent = rules.filter { $0.kind == .whitelist || $0.kind == .blacklist }
        guard let data = try? permanent.toJSONData() else { return }
        defaults.set(data, forKey: GlassWall.DefaultsKey.rules)
    }

    private func loadFromDisk() {
        guard let data  = defaults.data(forKey: GlassWall.DefaultsKey.rules),
              let saved = try? data.decoded(as: [PolicyRule].self)
        else { return }
        rules = saved
    }
}
