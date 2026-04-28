// MARK: - GlassWall Global Constants
// Centralises all bundle IDs, App Group identifiers, and Mach service names
// so every target references a single source of truth.

import Foundation

public enum GlassWall {

    // MARK: Bundle identifiers
    public enum BundleID {
        public static let app                   = "com.glasswall.app"
        public static let networkExtension      = "com.glasswall.app.networkextension"
        public static let esClient              = "com.glasswall.app.esclient"
    }

    // MARK: App Group (shared container used by app + extension)
    public static let appGroupID = "group.com.glasswall.app"

    // MARK: Mach service names (XPC endpoints)
    public enum MachService {
        /// Main app listens on this; extensions connect to it.
        public static let policyEngine         = "com.glasswall.app.policy"
        /// ES daemon listens on this; app connects to receive events.
        public static let esEvents             = "com.glasswall.app.esevents"
    }

    // MARK: UserDefaults / persisted keys (stored in shared App Group container)
    public enum DefaultsKey {
        public static let rules                 = "glasswall.rules"
        public static let panicModeEnabled      = "glasswall.panicMode"
        public static let sessionDenyList       = "glasswall.sessionDenyList"
    }

    // MARK: Watchlist – paths that trigger Suspicious Configuration Injection alerts
    public static let watchlistPaths: [String] = [
        "~/Library/LaunchAgents/",
        "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/",
        "/Library/PrivilegedHelperTools/",
        "/Library/LaunchDaemons/",
        "/Library/LaunchAgents/",
        "~/Library/Application Support/Firefox/NativeMessagingHosts/",
    ]

    // MARK: Clean Room – domains always permitted in Panic Mode
    // Apple system services and OS-critical update/telemetry endpoints.
    public static let cleanRoomAllowedDomains: Set<String> = [
        "apple.com",
        "icloud.com",
        "mzstatic.com",
        "aaplimg.com",
        "appattest.apple.com",
        "push.apple.com",
        "gateway.icloud.com",
        "ocsp.apple.com",
        "crl.apple.com",
        "mesu.apple.com",
        "xp.apple.com",
        "swscan.apple.com",
        "swdist.apple.com",
    ]

    // MARK: Timing
    /// Flow verdict response window before the OS auto-drops the connection.
    public static let flowDecisionTimeoutSeconds: TimeInterval = 30

    /// Maximum events buffered before LivePulseView batch-renders.
    public static let pulseEventBatchSize: Int = 20

    /// Interval at which the UI flushes the event batch to the view model.
    public static let pulseFlushInterval: TimeInterval = 0.25

    /// Duration of an Incognito (time-limited) allow rule.
    public static let incognitoDuration: TimeInterval = 60 * 60  // 60 minutes
}
