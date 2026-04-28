# GlassWall

**A next-generation, open-source privacy firewall + behavioural threat detection system for macOS.**

GlassWall is a Zero-Trust, user-controlled security layer that combines per-process network filtering, endpoint behavioural monitoring, and a real-time glassmorphic UI — giving you complete, explainable visibility into what your Mac is doing.

---

## What It Does

| Layer | Technology | Capability |
|-------|-----------|-----------|
| **Network Firewall** | `NetworkExtension` (NEFilterDataProvider) | Per-process, per-domain outbound control |
| **Behavioural Monitor** | `EndpointSecurity.framework` | File writes, renames, mmap, LaunchAgent installs |
| **Policy Engine** | Swift / XPC | Zero-Trust rule resolution with 4 precedence tiers |
| **UI** | SwiftUI glassmorphism | Non-blocking Intent Cards, live pulse feed, rule governance |

---

## Core Features

### Network Firewall
- **Zero-Trust default**: every unknown outbound connection is blocked until the user decides.
- **Per-process/per-domain rules** — Chrome can reach google.com without trusting all of Chrome.
- **Cached verdicts** resolve in microseconds (no XPC round-trip for known flows).
- **Digital Clean Room (Panic Mode)**: one-click menu bar toggle that blocks everything except Apple system services.

### Behavioural Monitor
- Watches `~/Library/LaunchAgents/`, `~/Library/Application Support/…/NativeMessagingHosts/`, `/Library/PrivilegedHelperTools/`, and more.
- Flags **Suspicious Configuration Injection** with process name, signing identity, file path, and action type.
- Detects **W+X mmap** (write + execute memory-mapped files) — a common code-injection indicator.

### Intent Card (Core UX)
- Floating non-blocking overlay (top-right) — does **not** freeze system execution.
- Four decision buttons with distinct persistence scopes:

  | Decision | Scope |
  |----------|-------|
  | **Whitelist** | Permanent allow |
  | **Incognito** | Allow for 60 minutes |
  | **Jail** | Block for current session |
  | **Blacklist** | Permanently block binary |

- 30-second countdown timer — auto-blocks if no response (safe default).

---

## Architecture

```
GlassWall.app  ←XPC→  NetworkExtension (System Extension)
      ↕  XPC
  ES Daemon (LaunchDaemon / root)
```

See [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) for the full data flow, security model, and entitlement notes.

---

## Project Structure

```
Shared/                         Models + XPC protocols (all targets)
GlassWall/                      Main SwiftUI app
  App/                          Entry point + AppDelegate
  MenuBar/                      NSStatusItem controller
  PolicyEngine/                 Rule engine, store, decision machine
  Views/                        All SwiftUI screens
  DesignSystem/                 Glassmorphic components
GlassWallNetworkExtension/      NEFilterDataProvider + FilterControlProvider
GlassWallESClient/              EndpointSecurity daemon (root)
Entitlements/                   Per-target .entitlements files
Docs/                           Architecture documentation
```

---

## Requirements

| Requirement | Value |
|-------------|-------|
| macOS | 13 Ventura or later |
| Architecture | arm64 + x86\_64 (universal) |
| Xcode | 15+ |
| Apple Developer Account | Required (paid, for System Extension entitlement) |
| ES Entitlement | Must be requested from Apple separately |

---

## macOS Constraints

- **No raw packet capture** — `NEFilterDataProvider` operates at the flow level, not packet level. This is intentional and correct per Apple guidelines.
- **ES detection-only** — AUTH events are always allowed; the daemon flags but does not block file writes in v1 to avoid kernel deadline crashes.
- **System Extension approval** — users must approve the extension in System Settings → Privacy & Security on first launch.

---

## License

MIT — see `LICENSE`.
