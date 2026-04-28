// MARK: - GlassWall EndpointSecurity Client
//
// Wraps the C-level EndpointSecurity framework in a Swift class.
// Must run as root (or with com.apple.developer.endpoint-security.client
// entitlement + SIP/AMFI bypass for development).
//
// Event selection strategy:
//   AUTH events  → we have a decision window; used for file-create/rename
//                  where we want to alert the user before the write lands.
//   NOTIFY events → fire-and-forget; used for mmap (too late to block, but
//                   important for injection detection telemetry).
//
// ⚠️  AUTH events have a hard kernel deadline. If we do not respond within
//     ~10 s the kernel auto-allows AND the es_client is forcibly killed.
//     We always auth-allow (no blocking) and use the event purely for
//     detection — the user is shown an alert but the file write proceeds.
//     True blocking would require smarter policy coordination not appropriate
//     for a v1 product that prioritises stability.

import Foundation
import EndpointSecurity
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.esClient, category: "ESClient")

// Delegate receives parsed events on an arbitrary background queue.
protocol ESClientDelegate: AnyObject {
    func esClient(_ client: ESClient, didObserve event: BehaviorEvent)
}

final class ESClient {

    weak var delegate: ESClientDelegate?

    private var client: OpaquePointer?   // es_client_t *
    private let eventQueue = DispatchQueue(label: "com.glasswall.es.events",
                                           qos: .userInitiated)
    private(set) var isRunning = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    func start() throws {
        guard !isRunning else { return }

        var localClient: OpaquePointer?
        let result = es_new_client(&localClient) { [weak self] client, message in
            self?.handleRawEvent(client: client, message: message)
        }

        switch result {
        case ES_NEW_CLIENT_RESULT_SUCCESS:
            client = localClient
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
            throw ESClientError.notPermitted
        case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
            throw ESClientError.notEntitled
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
            throw ESClientError.notPrivileged
        default:
            throw ESClientError.unknown(result.rawValue)
        }

        guard let c = client else { throw ESClientError.unknown(-1) }

        let subscribeResult = es_subscribe(c, [
            ES_EVENT_TYPE_AUTH_CREATE,
            ES_EVENT_TYPE_AUTH_RENAME,
            ES_EVENT_TYPE_NOTIFY_MMAP,
            ES_EVENT_TYPE_NOTIFY_WRITE,
        ], 4)

        guard subscribeResult == ES_RETURN_SUCCESS else {
            throw ESClientError.subscribeFailed
        }

        isRunning = true
        os_log("ESClient started", log: log, type: .info)
    }

    func stop() {
        guard isRunning, let c = client else { return }
        es_delete_client(c)
        client = nil
        isRunning = false
        os_log("ESClient stopped", log: log, type: .info)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Raw Event Handler (called on internal ES queue)
    // ─────────────────────────────────────────────────────────────────────────

    private func handleRawEvent(client: OpaquePointer, message: UnsafePointer<es_message_t>) {
        let msg = message.pointee

        switch msg.event_type {

        case ES_EVENT_TYPE_AUTH_CREATE:
            handleAuthCreate(client: client, message: message)

        case ES_EVENT_TYPE_AUTH_RENAME:
            handleAuthRename(client: client, message: message)

        case ES_EVENT_TYPE_NOTIFY_MMAP:
            handleNotifyMmap(message: message)

        case ES_EVENT_TYPE_NOTIFY_WRITE:
            handleNotifyWrite(message: message)

        default:
            break
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: AUTH_CREATE
    // ─────────────────────────────────────────────────────────────────────────

    private func handleAuthCreate(client: OpaquePointer,
                                  message: UnsafePointer<es_message_t>) {
        let msg         = message.pointee
        let process     = buildProcessContext(from: msg.process)
        let destination = String(cString: msg.event.create.destination.new_path.dir
            .pointee.path.data)
        let filename    = String(cString: msg.event.create.destination.new_path.filename.data)
        let fullPath    = (destination as NSString).appendingPathComponent(filename)

        // Always allow — we're in detection-only mode for AUTH events.
        es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)

        let isWatchlist = WatchlistMonitor.shared.isWatchlistPath(fullPath)
        let severity: BehaviorSeverity = isWatchlist ? .critical : .info

        let event = BehaviorEvent(
            eventType: isWatchlist ? eventTypeForWatchlistPath(fullPath) : .fileCreate,
            severity: severity,
            process: process,
            filePath: fullPath,
            summary: isWatchlist
                ? "⚠ Suspicious write: \(process.name) → \(fullPath)"
                : "\(process.name) created \(fullPath)",
            isWatchlistHit: isWatchlist
        )

        emitEvent(event)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: AUTH_RENAME
    // ─────────────────────────────────────────────────────────────────────────

    private func handleAuthRename(client: OpaquePointer,
                                  message: UnsafePointer<es_message_t>) {
        let msg     = message.pointee
        let process = buildProcessContext(from: msg.process)
        let srcPath = String(cString: msg.event.rename.source.pointee.path.data)

        let dstPath: String
        if msg.event.rename.destination_type == ES_DESTINATION_TYPE_NEW_PATH {
            let dir  = String(cString: msg.event.rename.destination.new_path.dir
                .pointee.path.data)
            let name = String(cString: msg.event.rename.destination.new_path.filename.data)
            dstPath  = (dir as NSString).appendingPathComponent(name)
        } else {
            dstPath = String(cString: msg.event.rename.destination.existing_file
                .pointee.path.data)
        }

        es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)

        let isWatchlist = WatchlistMonitor.shared.isWatchlistPath(dstPath)

        let event = BehaviorEvent(
            eventType: .fileRename,
            severity: isWatchlist ? .critical : .info,
            process: process,
            filePath: srcPath,
            destinationPath: dstPath,
            summary: "\(process.name) renamed \(srcPath) → \(dstPath)",
            isWatchlistHit: isWatchlist
        )

        emitEvent(event)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: NOTIFY_MMAP
    // ─────────────────────────────────────────────────────────────────────────

    private func handleNotifyMmap(message: UnsafePointer<es_message_t>) {
        let msg     = message.pointee
        let process = buildProcessContext(from: msg.process)
        let flags   = msg.event.mmap.flags

        // Only report executable or write+exec mmaps (injection indicators).
        guard (flags & PROT_EXEC) != 0 else { return }

        let filePath = msg.event.mmap.source.map {
            String(cString: $0.pointee.path.data)
        } ?? "<anonymous>"

        let isWriteExec = (flags & (PROT_WRITE | PROT_EXEC)) == (PROT_WRITE | PROT_EXEC)

        let event = BehaviorEvent(
            eventType: .mmapExecutable,
            severity: isWriteExec ? .critical : .warning,
            process: process,
            filePath: filePath,
            summary: isWriteExec
                ? "⚠ W+X mmap by \(process.name) on \(filePath)"
                : "\(process.name) mapped executable \(filePath)",
            isWatchlistHit: false
        )

        emitEvent(event)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: NOTIFY_WRITE (watchlist-only)
    // ─────────────────────────────────────────────────────────────────────────

    private func handleNotifyWrite(message: UnsafePointer<es_message_t>) {
        let msg      = message.pointee
        let filePath = String(cString: msg.event.write.target.pointee.path.data)
        guard WatchlistMonitor.shared.isWatchlistPath(filePath) else { return }

        let process = buildProcessContext(from: msg.process)

        let event = BehaviorEvent(
            eventType: eventTypeForWatchlistPath(filePath),
            severity: .critical,
            process: process,
            filePath: filePath,
            summary: "⚠ Suspicious write: \(process.name) → \(filePath)",
            isWatchlistHit: true
        )

        emitEvent(event)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func emitEvent(_ event: BehaviorEvent) {
        eventQueue.async {
            self.delegate?.esClient(self, didObserve: event)
        }
    }

    private func buildProcessContext(from process: UnsafePointer<es_process_t>) -> ProcessContext {
        let proc     = process.pointee
        let pid      = audit_token_to_pid(proc.audit_token)
        let name     = String(cString: proc.executable.pointee.path.data)
            .components(separatedBy: "/").last ?? "unknown"
        let path     = String(cString: proc.executable.pointee.path.data)
        let teamID: String? = proc.team_id.map { String(cString: $0.pointee.data) }
        let isSigned = proc.codesigning_flags & 0x1 != 0  // CS_VALID flag

        return ProcessContext(
            pid: pid,
            name: name,
            binaryPath: path,
            signingIdentity: teamID,
            isSignatureValid: isSigned
        )
    }

    private func eventTypeForWatchlistPath(_ path: String) -> BehaviorEventType {
        if path.contains("LaunchAgent") || path.contains("LaunchDaemon") {
            return .launchAgentInstall
        }
        if path.contains("PrivilegedHelperTools") {
            return .privilegedHelperWrite
        }
        if path.contains("NativeMessagingHosts") {
            return .nativeMessagingHost
        }
        return .fileCreate
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Error Types
// ─────────────────────────────────────────────────────────────────────────────

enum ESClientError: Error, LocalizedError {
    case notPermitted
    case notEntitled
    case notPrivileged
    case subscribeFailed
    case unknown(UInt32)

    var errorDescription: String? {
        switch self {
        case .notPermitted:    return "Not permitted — check SIP/AMFI settings"
        case .notEntitled:     return "Missing com.apple.developer.endpoint-security.client entitlement"
        case .notPrivileged:   return "Must run as root"
        case .subscribeFailed: return "es_subscribe() failed"
        case .unknown(let c):  return "Unknown ES error code: \(c)"
        }
    }
}
