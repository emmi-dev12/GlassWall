// MARK: - Content View
// Root window: tab bar (Live Pulse / Governance / Behavior) with glassmorphic
// chrome, panic mode banner, and the Intent Card overlay that floats on top.

import SwiftUI

enum GlassWallTab: String, CaseIterable {
    case pulse      = "Live Pulse"
    case governance = "Governance"
    case behavior   = "Behavior"

    var icon: String {
        switch self {
        case .pulse:      return "waveform.path.ecg"
        case .governance: return "list.bullet.rectangle.portrait"
        case .behavior:   return "eye.trianglebadge.exclamationmark"
        }
    }
}

struct ContentView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var selectedTab: GlassWallTab = .pulse

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────────
            LinearGradient(
                colors: [.gwBgTop, .gwBgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Optional scanline texture over the bg
            ScanlineEffect(color: .gwAccent.opacity(0.3))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ── Main layout ───────────────────────────────────────────────────
            VStack(spacing: 0) {
                if engine.panicMode.isEnabled {
                    panicBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                windowChrome

                Divider().overlay(Color.gwBorderSubtle)

                // Tab content
                Group {
                    switch selectedTab {
                    case .pulse:      LivePulseView()
                    case .governance: GovernanceView()
                    case .behavior:   BehaviorView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.gwSpring, value: engine.panicMode.isEnabled)

            // ── Intent Card overlay (non-blocking, always on top) ─────────────
            if !engine.pendingFlows.isEmpty {
                IntentCardOverlay()
                    .allowsHitTesting(true)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Window Chrome (title bar + tabs)
    // ─────────────────────────────────────────────────────────────────────────

    private var windowChrome: some View {
        HStack(spacing: GWSpacing.lg) {
            // Brand mark
            HStack(spacing: GWSpacing.sm) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.gwAccent)
                    .glowPulse(color: .gwAccent, radius: 6)
                Text("GlassWall")
                    .font(.gwTitle)
                    .foregroundStyle(.gwTextPrimary)
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.gwBorderSubtle)

            // Tab bar
            HStack(spacing: 2) {
                ForEach(GlassWallTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }

            Spacer()

            // Status indicators
            statusArea
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: GlassWallTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.gwFast) { selectedTab = tab }
        } label: {
            HStack(spacing: GWSpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                // Pending badge on Pulse tab
                if tab == .pulse && !engine.pendingFlows.isEmpty {
                    Text("\(engine.pendingFlows.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gwPending)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? .gwAccent : .gwTextSecondary)
            .padding(.horizontal, GWSpacing.md)
            .padding(.vertical, GWSpacing.sm)
            .background(isSelected ? Color.gwAccent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: GWRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statusArea: some View {
        HStack(spacing: GWSpacing.md) {
            // Connection count
            Label("\(engine.connectionEvents.count)", systemImage: "network")
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)

            // Panic mode indicator
            if engine.panicMode.isEnabled {
                Label("PANIC", systemImage: "lock.shield.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gwPanic)
                    .glowPulse(color: .gwPanic, radius: 4)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Panic Mode Banner
    // ─────────────────────────────────────────────────────────────────────────

    private var panicBanner: some View {
        HStack(spacing: GWSpacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.gwPanic)

            VStack(alignment: .leading, spacing: 2) {
                Text("Digital Clean Room Active")
                    .font(.gwHeadline)
                    .foregroundStyle(.gwPanic)
                Text("Only Apple system services are permitted. All other outbound traffic is blocked.")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextSecondary)
            }

            Spacer()

            Button("Disable Clean Room") {
                withAnimation(.gwSpring) {
                    engine.setPanicMode(false)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.gwPanic)
            .padding(.horizontal, GWSpacing.md)
            .padding(.vertical, GWSpacing.sm)
            .background(Color.gwPanic.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gwPanic.opacity(0.4), lineWidth: 0.5))
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.sm)
        .background(Color.gwPanicDim)
        .panicBorderFlash()
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    let engine = PolicyEngine()
    return ContentView()
        .environmentObject(engine)
}
