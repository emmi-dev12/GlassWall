// MARK: - GlassWall Shared Data Models
// All types are Codable so they can be serialised over XPC (as JSON Data)
// and persisted to the shared App Group defaults container.

import Foundation

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Identifiers & Enumerations
// ──────────────────────────────────────────────────────────────────────────────

public typealias FlowID      = UUID
public typealias RuleID      = UUID
public typealias BehaviorID  = UUID

/// The verdict for any given network flow or behaviour event.
public enum Verdict: String, Codable, CaseIterable {
    case pending    = "pending"
    case allow      = "allow"
    case block      = "block"
}

/// The persistence scope of a user decision.
public enum RuleKind: String, Codable, CaseIterable {
    /// Permanently trust this process ↔ domain pair.
    case whitelist  = "whitelist"
    /// Allow this session only; rule evaporates at process exit or reboot.
    case incognito  = "incognito"
    /// Block for the current login session.
    case jail       = "jail"
    /// Permanently block this binary regardless of target.
    case blacklist  = "blacklist"
}

/// Precedence order used by RuleResolver (lower index = higher priority).
public extension RuleKind {
    var precedence: Int {
        switch self {
        case .blacklist:  return 0
        case .jail:       return 1
        case .incognito:  return 2
        case .whitelist:  return 3
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Process Context
// ──────────────────────────────────────────────────────────────────────────────

/// Lightweight descriptor of the originating process captured at event time.
public struct ProcessContext: Codable, Hashable, Identifiable {
    public var id: UUID = UUID()
    public let pid: pid_t
    public let name: String
    public let binaryPath: String
    /// Code-signing team identifier; nil if ad-hoc or unsigned.
    public let signingIdentity: String?
    /// Whether the binary's signature is currently valid.
    public let isSignatureValid: Bool

    public init(
        pid: pid_t,
        name: String,
        binaryPath: String,
        signingIdentity: String? = nil,
        isSignatureValid: Bool = false
    ) {
        self.pid              = pid
        self.name             = name
        self.binaryPath       = binaryPath
        self.signingIdentity  = signingIdentity
        self.isSignatureValid = isSignatureValid
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Network Flow / Connection Event
// ──────────────────────────────────────────────────────────────────────────────

public enum FlowDirection: String, Codable {
    case outbound = "outbound"
    case inbound  = "inbound"
}

public enum TransportProtocol: String, Codable {
    case tcp = "TCP"
    case udp = "UDP"
    case other
}

/// One observed network connection attempt captured by NEFilterDataProvider.
public struct ConnectionEvent: Codable, Identifiable {
    public let id: FlowID
    public let timestamp: Date
    public let process: ProcessContext
    public let remoteHost: String          // hostname or raw IP
    public let remoteIP: String?           // resolved IP if available
    public let remotePort: UInt16
    public let direction: FlowDirection
    public let proto: TransportProtocol
    public var verdict: Verdict
    public var ruleKind: RuleKind?

    public init(
        id: FlowID = UUID(),
        timestamp: Date = Date(),
        process: ProcessContext,
        remoteHost: String,
        remoteIP: String? = nil,
        remotePort: UInt16,
        direction: FlowDirection = .outbound,
        proto: TransportProtocol = .tcp,
        verdict: Verdict = .pending,
        ruleKind: RuleKind? = nil
    ) {
        self.id           = id
        self.timestamp    = timestamp
        self.process      = process
        self.remoteHost   = remoteHost
        self.remoteIP     = remoteIP
        self.remotePort   = remotePort
        self.direction    = direction
        self.proto        = proto
        self.verdict      = verdict
        self.ruleKind     = ruleKind
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Endpoint Security / Behaviour Event
// ──────────────────────────────────────────────────────────────────────────────

public enum BehaviorEventType: String, Codable, CaseIterable {
    case fileCreate             = "file_create"
    case fileRename             = "file_rename"
    case fileDelete             = "file_delete"
    case mmapExecutable         = "mmap_exec"
    case launchAgentInstall     = "launch_agent_install"
    case privilegedHelperWrite  = "privileged_helper_write"
    case nativeMessagingHost    = "native_messaging_host"
}

/// Severity tier used to colour-code events in the Behavior timeline.
public enum BehaviorSeverity: String, Codable {
    case info       = "info"
    case warning    = "warning"
    case critical   = "critical"
}

/// One filesystem or security event captured by the ES daemon.
public struct BehaviorEvent: Codable, Identifiable {
    public let id: BehaviorID
    public let timestamp: Date
    public let eventType: BehaviorEventType
    public let severity: BehaviorSeverity
    public let process: ProcessContext
    /// Primary file path affected (creation target, rename source, mmap path…).
    public let filePath: String
    /// Destination path for rename operations.
    public let destinationPath: String?
    /// Human-readable summary shown in the timeline.
    public let summary: String
    /// Whether this path matched the GlassWall watchlist.
    public let isWatchlistHit: Bool

    public init(
        id: BehaviorID = UUID(),
        timestamp: Date = Date(),
        eventType: BehaviorEventType,
        severity: BehaviorSeverity,
        process: ProcessContext,
        filePath: String,
        destinationPath: String? = nil,
        summary: String,
        isWatchlistHit: Bool = false
    ) {
        self.id              = id
        self.timestamp       = timestamp
        self.eventType       = eventType
        self.severity        = severity
        self.process         = process
        self.filePath        = filePath
        self.destinationPath = destinationPath
        self.summary         = summary
        self.isWatchlistHit  = isWatchlistHit
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Policy Rule
// ──────────────────────────────────────────────────────────────────────────────

/// A persisted or session-scoped policy rule created by user decisions.
public struct PolicyRule: Codable, Identifiable, Hashable {
    public let id: RuleID
    public let kind: RuleKind
    public let binaryPath: String
    /// nil = matches any domain/IP for this binary.
    public let domain: String?
    public let createdAt: Date
    /// Non-nil only for .incognito rules; after this date the rule is expired.
    public let expiresAt: Date?
    public let notes: String?

    public init(
        id: RuleID = UUID(),
        kind: RuleKind,
        binaryPath: String,
        domain: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id         = id
        self.kind       = kind
        self.binaryPath = binaryPath
        self.domain     = domain
        self.createdAt  = createdAt
        self.expiresAt  = expiresAt
        self.notes      = notes
    }

    public var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: XPC Message Wrappers
// ──────────────────────────────────────────────────────────────────────────────

/// Sent by the network extension to request a verdict from the Policy Engine.
public struct FlowDecisionRequest: Codable {
    public let flowID: FlowID
    public let event: ConnectionEvent

    public init(flowID: FlowID, event: ConnectionEvent) {
        self.flowID = flowID
        self.event  = event
    }
}

/// Returned by the Policy Engine to resolve a paused flow.
public struct FlowDecisionResponse: Codable {
    public let flowID: FlowID
    public let verdict: Verdict
    public let ruleKind: RuleKind?

    public init(flowID: FlowID, verdict: Verdict, ruleKind: RuleKind? = nil) {
        self.flowID   = flowID
        self.verdict  = verdict
        self.ruleKind = ruleKind
    }
}

/// Sent by the ES daemon to push a behaviour event to the main app.
public struct BehaviorEventPush: Codable {
    public let event: BehaviorEvent

    public init(event: BehaviorEvent) {
        self.event = event
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Panic Mode State
// ──────────────────────────────────────────────────────────────────────────────

public struct PanicModeState: Codable {
    public var isEnabled: Bool
    public var enabledAt: Date?

    public static let disabled = PanicModeState(isEnabled: false, enabledAt: nil)

    public init(isEnabled: Bool, enabledAt: Date? = nil) {
        self.isEnabled = isEnabled
        self.enabledAt = enabledAt
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: JSON Helpers
// ──────────────────────────────────────────────────────────────────────────────

private let sharedEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let sharedDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

public extension Encodable {
    func toJSONData() throws -> Data {
        try sharedEncoder.encode(self)
    }
}

public extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try sharedDecoder.decode(type, from: self)
    }
}
