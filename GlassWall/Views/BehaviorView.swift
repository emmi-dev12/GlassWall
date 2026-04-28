// MARK: - Behavior View
// Timeline of EndpointSecurity events: file writes, renames, mmap, and
// watchlist hits (Suspicious Configuration Injection alerts).
// Critical watchlist hits are pinned to the top with a prominent banner.

import SwiftUI

struct BehaviorView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText   = ""
    @State private var filterSev: BehaviorSeverity? = nil
    @State private var selectedEvent: BehaviorEvent? = nil

    private var watchlistHits: [BehaviorEvent] {
        engine.behaviorEvents.filter { $0.isWatchlistHit }
    }

    private var filtered: [BehaviorEvent] {
        engine.behaviorEvents.filter { event in
            let matchesSev    = filterSev == nil || event.severity == filterSev
            guard matchesSev else { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return event.process.name.lowercased().contains(q) ||
                   event.filePath.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.gwBorderSubtle)

            if !watchlistHits.isEmpty {
                watchlistBanner
                Divider().overlay(Color.gwBorderSubtle)
            }

            if filtered.isEmpty {
                emptyState
            } else {
                eventTimeline
            }
        }
        .sheet(item: $selectedEvent) { event in
            BehaviorEventDetailSheet(event: event)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Toolbar
    // ─────────────────────────────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: GWSpacing.md) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(.gwWarning)
                .font(.system(size: 15, weight: .semibold))

            Text("Behavior")
                .font(.gwTitle)
                .foregroundStyle(.gwTextPrimary)

            Spacer()

            HStack(spacing: GWSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.gwTextTertiary)
                TextField("Filter by process or path…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.gwBody)
                    .foregroundStyle(.gwTextPrimary)
                    .frame(width: 200)
            }
            .padding(.horizontal, GWSpacing.md)
            .padding(.vertical, GWSpacing.xs)
            .background(Color.gwSurfaceSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gwBorderSubtle, lineWidth: 0.5))

            // Severity chips
            HStack(spacing: GWSpacing.xs) {
                severityChip(nil, label: "All")
                severityChip(.critical, label: "Critical")
                severityChip(.warning,  label: "Warning")
                severityChip(.info,     label: "Info")
            }

            Text("\(filtered.count)")
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
    }

    private func severityChip(_ sev: BehaviorSeverity?, label: String) -> some View {
        let selected = filterSev == sev
        let color: Color = sev?.color ?? .gwAccent
        return Button {
            withAnimation(.gwFast) { filterSev = sev }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? color : .gwTextTertiary)
                .padding(.horizontal, GWSpacing.sm)
                .padding(.vertical, 3)
                .background(selected ? color.opacity(0.15) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Watchlist Hit Banner
    // ─────────────────────────────────────────────────────────────────────────

    private var watchlistBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GWSpacing.sm) {
                ForEach(watchlistHits.prefix(5)) { event in
                    Button { selectedEvent = event } label: {
                        HStack(spacing: GWSpacing.sm) {
                            RippleEffect(color: .gwCritical, count: 2)
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Suspicious Injection")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.gwCritical)
                                Text(event.process.name)
                                    .font(.gwCaption)
                                    .foregroundStyle(.gwTextPrimary)
                            }
                        }
                        .padding(.horizontal, GWSpacing.md)
                        .padding(.vertical, GWSpacing.sm)
                        .glassmorphic(cornerRadius: GWRadius.md,
                                      borderColor: .gwCritical.opacity(0.5),
                                      glowColor: .gwCritical,
                                      padding: 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, GWSpacing.lg)
            .padding(.vertical, GWSpacing.sm)
        }
        .background(Color.gwPanicDim)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Event Timeline
    // ─────────────────────────────────────────────────────────────────────────

    private var eventTimeline: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(filtered) { event in
                    BehaviorEventRow(event: event)
                        .onTapGesture { selectedEvent = event }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.gwFast, value: filtered.count)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Empty State
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: GWSpacing.lg) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.gwAllow.opacity(0.5))
            Text("No suspicious activity detected")
                .font(.gwHeadline)
                .foregroundStyle(.gwTextSecondary)
            Text("Filesystem events from EndpointSecurity will appear here.")
                .font(.gwBody)
                .foregroundStyle(.gwTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GWSpacing.xxl)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Behavior Event Row
// ─────────────────────────────────────────────────────────────────────────────

struct BehaviorEventRow: View {

    let event: BehaviorEvent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GWSpacing.md) {

            // Severity icon with timeline connector
            VStack(spacing: 0) {
                Image(systemName: event.severity.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.severity.color)
                    .frame(width: 24, height: 24)
                    .glowPulse(color: event.severity.color, radius: 4)
                Rectangle()
                    .fill(Color.gwBorderSubtle)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: GWSpacing.xs) {
                HStack {
                    Text(event.process.name)
                        .font(.gwHeadline)
                        .foregroundStyle(.gwTextPrimary)
                    if event.isWatchlistHit {
                        Text("WATCHLIST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.gwCritical)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.gwCritical.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.gwCaption)
                        .foregroundStyle(.gwTextTertiary)
                        .monospacedDigit()
                }

                Text(event.summary)
                    .font(.gwBody)
                    .foregroundStyle(event.isWatchlistHit ? .gwWarning : .gwTextSecondary)
                    .lineLimit(2)

                Text(event.filePath)
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
        .background(
            isHovered || event.isWatchlistHit
                ? (event.isWatchlistHit
                    ? Color.gwCritical.opacity(0.06)
                    : Color.gwSurfaceSecondary)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }

        Divider().overlay(Color.gwBorderSubtle.opacity(0.4))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Behavior Event Detail Sheet
// ─────────────────────────────────────────────────────────────────────────────

struct BehaviorEventDetailSheet: View {

    let event: BehaviorEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [.gwBgTop, .gwBgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: GWSpacing.xl) {

                // Header
                HStack {
                    Image(systemName: event.severity.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(event.severity.color)
                        .glowPulse(color: event.severity.color)

                    Text(event.eventType.rawValue.replacingOccurrences(of: "_", with: " ")
                            .capitalized)
                        .font(.gwTitle)
                        .foregroundStyle(.gwTextPrimary)

                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.gwAccent)
                }

                Divider().overlay(Color.gwBorderSubtle)

                // Details grid
                GlassmorphicCard(glowColor: event.isWatchlistHit ? .gwCritical : nil) {
                    VStack(spacing: GWSpacing.md) {
                        detailRow("Process",     event.process.name)
                        detailRow("PID",         "\(event.process.pid)")
                        detailRow("Binary",      event.process.binaryPath)
                        detailRow("Signing ID",  event.process.signingIdentity ?? "—")
                        detailRow("File Path",   event.filePath)
                        if let dst = event.destinationPath {
                            detailRow("Destination", dst)
                        }
                        detailRow("Severity",    event.severity.rawValue.capitalized)
                        detailRow("Timestamp",   event.timestamp.formatted(.dateTime))
                        if event.isWatchlistHit {
                            Divider().overlay(Color.gwCritical.opacity(0.4))
                            Text("⚠ Watchlist Hit: \(WatchlistMonitor.shared.category(for: event.filePath))")
                                .font(.gwHeadline)
                                .foregroundStyle(.gwCritical)
                        }
                    }
                }

                Spacer()
            }
            .padding(GWSpacing.xl)
        }
        .preferredColorScheme(.dark)
        .frame(width: 520, height: 480)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.gwMono)
                .foregroundStyle(.gwTextPrimary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
