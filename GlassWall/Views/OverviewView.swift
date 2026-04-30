// MARK: - Overview View
// Security dashboard: status summary, key metrics, recent activity,
// and quick access to the main actions. This is the default landing tab.

import SwiftUI

struct OverviewView: View {

    @EnvironmentObject private var engine: PolicyEngine
    var onSetup: () -> Void

    // Computed stats
    private var allowedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return engine.connectionEvents.filter { $0.verdict == .allow && $0.timestamp >= start }.count
    }
    private var blockedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return engine.connectionEvents.filter { $0.verdict == .block && $0.timestamp >= start }.count
    }
    private var watchlistCount: Int {
        engine.behaviorEvents.filter { $0.isWatchlistHit }.count
    }
    private var ruleCount: Int { engine.ruleStore.rules.count }

    private var securityStatus: (label: String, color: Color, icon: String) {
        if engine.panicMode.isEnabled {
            return ("Locked Down", .gwPanic, "lock.shield.fill")
        }
        if watchlistCount > 0 {
            return ("Attention Needed", .gwWarning, "exclamationmark.shield.fill")
        }
        if engine.pendingFlows.isEmpty && engine.connectionEvents.count > 0 {
            return ("Protected", .gwAllow, "checkmark.shield.fill")
        }
        return ("Watching", .gwTeal, "shield.lefthalf.filled")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GWS.xl) {
                heroCard
                statsRow
                recentActivity
                if engine.ruleStore.rules.isEmpty {
                    gettingStartedCard
                }
            }
            .padding(GWS.xl)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Hero Card
    // ─────────────────────────────────────────────────────────────────────────

    private var heroCard: some View {
        GlassmorphicCard(
            cornerRadius: GWR.lg,
            padding: GWS.xl,
            glowColor: securityStatus.color,
            glowRadius: 18
        ) {
            HStack(spacing: GWS.xl) {
                VStack(alignment: .leading, spacing: GWS.lg) {
                    // Status
                    HStack(spacing: GWS.md) {
                        ZStack {
                            Circle()
                                .fill(securityStatus.color.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: securityStatus.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(securityStatus.color)
                        }
                        .breathingGlow(securityStatus.color, radius: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(securityStatus.label)
                                .font(.gwLargeTitle)
                                .foregroundStyle(securityStatus.color)
                            Text(statusSubtitle)
                                .font(.gwBody)
                                .foregroundStyle(.gwText2)
                        }
                    }

                    // Panic mode quick toggle
                    panicToggleButton
                }

                Spacer()

                // Live activity mini-feed
                miniActivityFeed
                    .frame(width: 240)
            }
        }
    }

    private var statusSubtitle: String {
        if engine.panicMode.isEnabled { return "Only Apple system services can connect." }
        if watchlistCount > 0        { return "\(watchlistCount) suspicious file event\(watchlistCount == 1 ? "" : "s") detected." }
        if !engine.pendingFlows.isEmpty { return "\(engine.pendingFlows.count) connection\(engine.pendingFlows.count == 1 ? "" : "s") waiting for your decision." }
        return "All network connections are being monitored."
    }

    private var panicToggleButton: some View {
        let active = engine.panicMode.isEnabled
        return Button {
            withAnimation(.gwSpring) { engine.setPanicMode(!active) }
        } label: {
            HStack(spacing: GWS.sm) {
                Image(systemName: active ? "lock.open" : "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(active ? "Disable Clean Room" : "Enable Clean Room")
                    .font(.gwBodyMed)
            }
            .foregroundStyle(active ? .gwText2 : .gwPanic)
            .padding(.horizontal, GWS.lg)
            .padding(.vertical, GWS.sm + 2)
            .background(active ? Color.gwSurface : Color.gwPanic.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    active ? Color.gwBorder : Color.gwPanic.opacity(0.35),
                    lineWidth: 0.75
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var miniActivityFeed: some View {
        VStack(alignment: .leading, spacing: GWS.xs) {
            Text("RECENT")
                .font(.gwCaptionMed)
                .foregroundStyle(.gwText3)
                .tracking(0.8)

            if engine.connectionEvents.isEmpty {
                VStack(spacing: GWS.sm) {
                    ScanLine(color: .gwTeal)
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: GWR.xs))
                        .opacity(0.5)
                    Text("Waiting for activity…")
                        .font(.gwCaption)
                        .foregroundStyle(.gwText3)
                }
            } else {
                VStack(spacing: GWS.xs) {
                    ForEach(engine.connectionEvents.prefix(5)) { ev in
                        HStack(spacing: GWS.sm) {
                            StatusDot(verdict: ev.verdict, size: 6)
                            Text(ev.process.name)
                                .font(.gwCaptionMed)
                                .foregroundStyle(.gwText2)
                                .lineLimit(1)
                            Spacer()
                            Text(ev.remoteHost)
                                .font(.gwMonoSmall)
                                .foregroundStyle(.gwText3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Stats Row
    // ─────────────────────────────────────────────────────────────────────────

    private var statsRow: some View {
        HStack(spacing: GWS.lg) {
            StatCard(
                value: "\(allowedToday)",
                label: "Allowed Today",
                icon: "checkmark.circle.fill",
                color: .gwAllow
            )
            StatCard(
                value: "\(blockedToday)",
                label: "Blocked Today",
                icon: "xmark.circle.fill",
                color: .gwBlock
            )
            StatCard(
                value: "\(ruleCount)",
                label: "Saved Rules",
                icon: "list.bullet.rectangle.portrait.fill",
                color: .gwBlue
            )
            StatCard(
                value: watchlistCount > 0 ? "\(watchlistCount)" : "—",
                label: "Threat Events",
                icon: "exclamationmark.shield.fill",
                color: watchlistCount > 0 ? .gwCritical : .gwText3
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Recent Activity
    // ─────────────────────────────────────────────────────────────────────────

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: GWS.md) {
            Text("Recent Connections")
                .font(.gwHeadline)
                .foregroundStyle(.gwText2)

            GlassmorphicCard(cornerRadius: GWR.md, padding: 0) {
                if engine.connectionEvents.isEmpty {
                    HStack {
                        Spacer()
                        Text("No connections yet — activity will appear here.")
                            .font(.gwBody)
                            .foregroundStyle(.gwText3)
                            .padding(GWS.xl)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(engine.connectionEvents.prefix(8)) { ev in
                            MiniEventRow(event: ev)
                            if ev.id != engine.connectionEvents.prefix(8).last?.id {
                                GlassDivider().padding(.leading, GWS.lg + 18)
                            }
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Getting Started Card
    // ─────────────────────────────────────────────────────────────────────────

    private var gettingStartedCard: some View {
        GlassmorphicCard(cornerRadius: GWR.lg, padding: GWS.xl, glowColor: .gwTeal, glowRadius: 10) {
            HStack(spacing: GWS.xl) {
                VStack(alignment: .leading, spacing: GWS.md) {
                    Label("Getting Started", systemImage: "sparkles")
                        .font(.gwHeadline)
                        .foregroundStyle(.gwTeal)

                    Text("GlassWall is active and watching all outbound connections. When an app connects somewhere new, you'll see a prompt asking what to do.")
                        .font(.gwBody)
                        .foregroundStyle(.gwText2)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("View Setup Guide") { onSetup() }
                        .buttonStyle(.plain)
                        .font(.gwBodyMed)
                        .foregroundStyle(.gwTeal)
                        .padding(.horizontal, GWS.lg)
                        .padding(.vertical, GWS.sm + 1)
                        .background(Color.gwTeal.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.gwTeal.opacity(0.35), lineWidth: 0.75))
                }
                Spacer()
                Image(systemName: "hand.raised.circle")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.gwTeal.opacity(0.4))
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Stat Card
// ─────────────────────────────────────────────────────────────────────────────

struct StatCard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        GlassmorphicCard(cornerRadius: GWR.md, padding: GWS.lg) {
            HStack(spacing: GWS.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.gwText1)
                        .monospacedDigit()
                    Text(label)
                        .font(.gwCaption)
                        .foregroundStyle(.gwText3)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Mini Event Row (Overview only)
// ─────────────────────────────────────────────────────────────────────────────

struct MiniEventRow: View {
    let event: ConnectionEvent

    var body: some View {
        HStack(spacing: GWS.md) {
            StatusDot(verdict: event.verdict, size: 6)
                .frame(width: 18)

            Text(event.process.name)
                .font(.gwBodyMed)
                .foregroundStyle(.gwText1)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.gwText3)

            Text(event.remoteHost)
                .font(.gwMono)
                .foregroundStyle(.gwText2)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            VerdictBadge(verdict: event.verdict, compact: true)

            Text(event.timestamp, format: .dateTime.hour().minute().second())
                .font(.gwMonoSmall)
                .foregroundStyle(.gwText3)
                .monospacedDigit()
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, GWS.lg)
        .padding(.vertical, GWS.sm + 2)
    }
}
