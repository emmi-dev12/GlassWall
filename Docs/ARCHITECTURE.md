# GlassWall — Architecture Reference

> Zero-Trust macOS privacy firewall + behavioural threat detection.  
> Targets macOS 13 Ventura and later. Supports arm64 + x86\_64 (universal binary).

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Space                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────┐              │
│  │           GlassWall.app (main process)        │              │
│  │                                               │              │
│  │  ┌──────────────┐   ┌───────────────────┐    │              │
│  │  │ PolicyEngine │   │   SwiftUI Views    │    │              │
│  │  │  (Observable)│◄──│  ContentView       │    │              │
│  │  │              │   │  LivePulseView     │    │              │
│  │  │ DecisionEngine│   │  IntentCardView   │    │              │
│  │  │ RuleStore    │   │  GovernanceView    │    │              │
│  │  └──────┬───────┘   │  BehaviorView      │    │              │
│  │         │XPC         └───────────────────┘    │              │
│  │         │ listen                              │              │
│  └─────────┼───────────────────────────────────-┘              │
│            │                          ▲                         │
│    XPC: com.glasswall.app.policy      │ XPC: com.glasswall.app.esevents
│            │                          │                         │
│  ┌─────────▼──────────────┐  ┌────────┴──────────────────┐    │
│  │  Network Extension      │  │    ES Daemon              │    │
│  │  (System Extension)     │  │  (LaunchDaemon / root)    │    │
│  │                         │  │                           │    │
│  │  FilterDataProvider     │  │  ESClient                 │    │
│  │  FilterControlProvider  │  │  WatchlistMonitor         │    │
│  │                         │  │  ESXPCServer              │    │
│  └──────────┬──────────────┘  └───────────────────────────┘    │
│             │                                                   │
└─────────────┼───────────────────────────────────────────────────┘
              │ NEFilterDataProvider intercepts flows
┌─────────────▼───────────────────────────────────────────────────┐
│                     macOS Kernel / Network Stack                 │
│              (com.apple.network.content.filter kext)            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Data Flow

### Network Flow (happy path — cached rule)

```
New TCP/UDP connection attempt
        │
        ▼
FilterDataProvider.handleNewFlow()
        │
        ├─ panicMode? ──► allow only clean-room domains → verdict
        │
        ├─ cache hit? ──► return .allow() / .drop()  immediately
        │
        └─ cache miss ──► return .needRules()
                │
                ▼
        FilterControlProvider.handleNewFlow()
                │
                ▼ (XPC)
        PolicyEngine.handleVerdictRequest()
                │
                ├─ DecisionEngine.resolve()
                │       │
                │       ├─ Rule found → respond immediately
                │       │
                │       └─ No rule → park reply → show IntentCardView
                │                         │
                │                    User decides
                │                         │
                │                    engine.applyDecision()
                │                         │
                ▼                         ▼
        FlowDecisionResponse (XPC) ◄──────┘
                │
                ▼
        FilterControlProvider.applyVerdict()
        → NEFilterControlVerdict → resume flow
        → NotificationCenter → cache update → FilterDataProvider
```

### Behavioral Event Flow

```
File write / rename / mmap
        │
        ▼
EndpointSecurity kernel event
        │
        ▼
ESClient.handleRawEvent()
        │
        ├─ AUTH events → always respond ES_AUTH_RESULT_ALLOW (detect-only)
        │
        ├─ WatchlistMonitor.isWatchlistPath()
        │       └─ hit → BehaviorSeverity.critical
        │
        └─ Build BehaviorEvent
                │
                ▼ (delegate)
        ESXPCServer.broadcast()
                │
                ▼ (XPC)
        PolicyEngine.pushBehaviorEvent()
                │
                ▼
        @Published behaviorEvents → BehaviorView (SwiftUI)
```

---

## 3. Module Breakdown

| Module | Target Type | Entitlement | Purpose |
|--------|-------------|-------------|---------|
| `Shared/` | Swift sources (linked into all targets) | — | Constants, models, XPC protocols |
| `GlassWall/` | `.app` | `network.networkextension`, `system-extension.install` | Main UI + Policy Engine + XPC listener |
| `GlassWallNetworkExtension/` | System Extension (`.appex`) | `network.networkextension` content-filter | Per-flow network interception |
| `GlassWallESClient/` | Command-line tool (LaunchDaemon) | `endpoint-security.client` | Filesystem + ES behavioural monitoring |

---

## 4. Security Implementation Details

### 4.1 Network Extension

- Uses **`NEFilterDataProvider`** (hot path) + **`NEFilterControlProvider`** (decision path).
- `FilterDataProvider.handleNewFlow` returns in microseconds: either a cache hit verdict or `.needRules()`.
- `FilterControlProvider` bridges to the main app via XPC (`com.glasswall.app.policy` Mach service).
- **Flow timeout**: 30 s hard limit before auto-block. The countdown is displayed in the Intent Card.
- **Panic Mode**: overrides all other logic. Only `GlassWall.cleanRoomAllowedDomains` pass.

### 4.2 EndpointSecurity

- Runs as a **LaunchDaemon** (root), installed via `SMJobBless` / `SMAppService`.
- Subscribes to: `AUTH_CREATE`, `AUTH_RENAME`, `NOTIFY_MMAP`, `NOTIFY_WRITE`.
- **Detection-only**: always responds `ES_AUTH_RESULT_ALLOW` to AUTH events within the kernel deadline. Blocking file writes in v1 is intentionally avoided for stability.
- **Watchlist** matches by path prefix (thread-safe `NSLock`-guarded dictionary).
- Code-signing flags are inspected from `es_process_t.codesigning_flags` (`CS_VALID = 0x1`).

### 4.3 XPC Security

- Both XPC listeners validate the connecting process's binary path.
- Production hardening: replace path check with `SecCodeCopyGuestWithAttributes` + `SecRequirementCreateWithString` to verify the code-signing team ID and bundle ID of the peer.
- The NE extension→app channel (`com.glasswall.app.policy`) is registered as a **Mach service** in the app's launchd job, so only the user's GlassWall session can connect.

### 4.4 Policy Engine Precedence

```
Priority  Kind        Scope               Verdict
   0      blacklist   binary (all domains) BLOCK (permanent)
   1      jail        binary + domain      BLOCK (session)
   2      incognito   binary + domain      ALLOW (60 min TTL)
   3      whitelist   binary + domain      ALLOW (permanent)
   —      (no rule)   —                   PENDING → user prompt
```

`DecisionEngine.resolve()` selects the rule with the lowest precedence number (most restrictive wins).

---

## 5. SwiftUI UI System Design

### Design Language: Glassmorphism

```
Background:  LinearGradient #0A0E1A → #050810
Surfaces:    .ultraThinMaterial + Color.white.opacity(0.06)
Borders:     Color.white.opacity(0.10) @ 0.5pt stroke
Accent:      #00D4FF (cyan) / #7B61FF (violet)
Status:      #00FF9C allow / #FF3B5C block / #FFB800 pending
```

### Component Hierarchy

```
GlassWallApp
└── WindowGroup
    └── ContentView
        ├── PanicBanner (conditional)
        ├── WindowChrome (tabs + brand)
        ├── [LivePulseView | GovernanceView | BehaviorView]
        │       LivePulseView
        │       ├── Toolbar (search + filter chips)
        │       └── LazyVStack<ConnectionEventRow>
        │               └── expandedDetail (tap-to-expand)
        │       GovernanceView
        │       ├── Toolbar (search + kind filter menu)
        │       └── Section<RuleRow> per RuleKind
        │       BehaviorView
        │       ├── Toolbar (search + severity chips)
        │       ├── WatchlistBanner (horizontal scroll, critical hits)
        │       └── LazyVStack<BehaviorEventRow>
        │               └── BehaviorEventDetailSheet (sheet)
        └── IntentCardOverlay (ZStack top layer)
            └── IntentCardView × pending.count
                ├── Header (process + icon)
                ├── ConnectionInfo grid
                ├── DecisionButtons (whitelist/incognito/jail/blacklist)
                └── TimerBar (countdown → auto-jail)
```

### Performance

| Concern | Solution |
|---------|----------|
| Per-packet UI updates | `eventBuffer` coalesces into 250 ms batches; max 1 000 items in `connectionEvents` |
| ES event flood | `LazyVStack` virtualises rendering; max 500 in `behaviorEvents` |
| Cache lookup in NE | `[String:Verdict]` dictionary with concurrent `DispatchQueue` read / barrier write |
| Intent Card stacking | Max 4 cards shown; overflow shown as "+N more" |

---

## 6. Policy Engine Logic (State Machine)

```
              ┌─────────────────────────────────────────┐
              │            FLOW ARRIVES                 │
              └──────────────────┬──────────────────────┘
                                 │
                    ┌────────────▼───────────┐
                    │     Panic Mode ON?      │
                    └────────────┬───────────┘
                        YES │       │ NO
                            ▼       ▼
                    ┌──────────┐  ┌──────────────────────────┐
                    │Clean-room│  │  RuleStore.resolve()      │
                    │ domain?  │  │  binaryPath + domain      │
                    └────┬─────┘  └──────────┬───────────────┘
                  YES │  │ NO      FOUND │     │ NOT FOUND
                      ▼  ▼              ▼     ▼
                   ALLOW BLOCK   ┌──────────┐  ┌──────────┐
                                 │ Evaluate │  │ PENDING  │
                                 │ RuleKind │  │→ IntentCard│
                                 └────┬─────┘  └─────┬────┘
                         whitelist/   │              │
                         incognito    │         User selects
                              │       │ jail/       │ RuleKind
                              ▼       │ blacklist   │
                           ALLOW      ▼             │
                                   BLOCK      record()→RuleStore
                                                    │
                                              resume flow
```

---

## 7. macOS Constraints & Entitlements Notes

### Feasibility flags

| Feature | Status | Notes |
|---------|--------|-------|
| Per-process network filtering | ✅ Feasible | NEFilterDataProvider has `sourceAppAuditToken` |
| Synchronous flow blocking | ✅ Feasible | `.needRules()` + `resumeFlow()` |
| Raw packet capture | ❌ Not feasible | Not available to NEFilterDataProvider; would require NEPacketTunnelProvider (VPN approach) with user consent |
| Indefinite flow freeze | ❌ Not feasible | Kernel imposes ~10 s timeout; we use 30 s UI timer with auto-block fallback |
| ES AUTH blocking for file writes | ⚠️ Possible but risky | Missed deadline kills the es_client; v1 uses detect-only for stability |
| Kernel kext | ❌ Deprecated | Apple deprecated kexts; System Extensions are the correct path |
| Reading process signing info in NE sandbox | ⚠️ Limited | `sourceAppAuditToken` works; full `SecCode` lookup requires specific entitlements |

### Entitlement acquisition path

1. **`com.apple.developer.networking.networkextension`** — available via standard Apple Developer account; select "Content Filter Provider" capability in Xcode.
2. **`com.apple.developer.system-extension.install`** — requires explicit provisioning profile with the capability enabled.
3. **`com.apple.developer.endpoint-security.client`** — must be requested via Apple's [Endpoint Security entitlement request form](https://developer.apple.com/contact/request/endpoint-security-entitlement/). Apple reviews these manually; expect 1–4 weeks.
4. **SIP** — for development/testing with an ES client, you may need to partially disable SIP: `csrutil enable --without fs` from Recovery Mode. Never ship with SIP disabled.

### Distribution

- The main `.app` + Network Extension bundle ship together via the Mac App Store or Developer ID.
- The ES daemon (`GlassWallESClient`) ships as a privileged helper tool, installed via `SMAppService.register()` (macOS 13+) or the legacy `SMJobBless`. It lives in `/Library/PrivilegedHelperTools/`.
- The LaunchDaemon plist (`com.glasswall.app.esclient.plist`) is deployed to `/Library/LaunchDaemons/` during first-launch setup, requiring one-time admin authorisation.

---

## 8. File Index

```
GlassWall/
├── Shared/
│   ├── Constants.swift                  Global IDs, timing, watchlist paths
│   ├── SharedModels.swift               Codable domain models (ConnectionEvent, BehaviorEvent, PolicyRule…)
│   └── GlassWallXPCProtocol.swift       XPC protocol definitions + connection factories
│
├── GlassWall/                           Main App target
│   ├── App/
│   │   ├── GlassWallApp.swift           @main SwiftUI entry, @NSApplicationDelegateAdaptor
│   │   └── AppDelegate.swift            System Extension lifecycle, NEFilterManager, menu bar
│   ├── MenuBar/
│   │   └── MenuBarController.swift      NSStatusItem, panic mode toggle, badge
│   ├── PolicyEngine/
│   │   ├── PolicyEngine.swift           @MainActor ObservableObject; XPC listener; event buffer
│   │   ├── RuleStore.swift              Persistent + session rule CRUD; App Group UserDefaults
│   │   └── DecisionEngine.swift         Rule resolution state machine; record() from user intent
│   └── Views/
│       ├── ContentView.swift            Root window: tab bar, panic banner, Intent Card overlay
│       ├── LivePulseView.swift          Throttled real-time connection feed
│       ├── IntentCardView.swift         Floating non-blocking decision overlay
│       ├── GovernanceView.swift         Rule management (search, filter, delete)
│       ├── BehaviorView.swift           ES event timeline + watchlist hit banner
│       └── DesignSystem/
│           ├── DesignTokens.swift       Colors, fonts, spacing, animation constants
│           ├── GlassmorphicCard.swift   Reusable glass-effect card container
│           ├── NeonIndicator.swift      Animated glowing status dot
│           └── PulseAnimation.swift     RippleEffect, ScanlineEffect, GlowPulse modifier
│
├── GlassWallNetworkExtension/           System Extension target
│   ├── FilterDataProvider.swift         Hot-path: cache lookup, panic mode, .needRules()
│   ├── FilterControlProvider.swift      Decision path: XPC to app, resume paused flows
│   ├── NetworkExtensionMain.swift       Class registration stub
│   └── Info.plist                       NSExtension + SystemExtension declarations
│
├── GlassWallESClient/                   LaunchDaemon target (root)
│   ├── ESClient.swift                   es_new_client wrapper, AUTH/NOTIFY handlers
│   ├── WatchlistMonitor.swift           Thread-safe path prefix matcher + category labels
│   ├── ESXPCServer.swift                NSXPCListener; broadcast events; accept config
│   ├── main.swift                       Daemon entry point, SIGTERM handler, RunLoop
│   └── com.glasswall.app.esclient.plist LaunchDaemon descriptor
│
├── Entitlements/
│   ├── GlassWall.entitlements
│   ├── GlassWallNetworkExtension.entitlements
│   └── GlassWallESClient.entitlements
│
└── Docs/
    └── ARCHITECTURE.md                  ← this file
```
