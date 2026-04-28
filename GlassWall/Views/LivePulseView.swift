// MARK: - Live Pulse View
// Real-time throttled feed of all network connection decisions.
// Events arrive in batches (see PolicyEngine.flushBuffer) to prevent
// per-packet UI thrashing. The list is virtualised by SwiftUI's LazyVStack.

import SwiftUI

struct LivePulseView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText = ""
    @State private var filterVerdict: Verdict? = nil

    private var filtered: [ConnectionEvent] {
        engine.connectionEvents.filter { event in
            let matchesSearch = searchText.isEmpty ||
                event.process.name.localizedCaseInsensitiveContains(searchText) ||
                event.remoteHost.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = filterVerdict == nil || event.verdict == filterVerdict
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.gwBorderSubtle)
            if filtered.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Toolbar
    // ─────────────────────────────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: GWSpacing.md) {
            // Live indicator
            HStack(spacing: GWSpacing.xs) {
                NeonIndicator(color: .gwAllow, size: 7, isAnimating: true)
                Text("LIVE")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextSecondary)
            }

            Spacer()

            // Search
            HStack(spacing: GWSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.gwTextTertiary)
                TextField("Filter by app or domain…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.gwBody)
                    .foregroundStyle(.gwTextPrimary)
                    .frame(width: 180)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gwTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, GWSpacing.md)
            .padding(.vertical, GWSpacing.xs)
            .background(Color.gwSurfaceSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gwBorderSubtle, lineWidth: 0.5))

            // Verdict filter chips
            HStack(spacing: GWSpacing.xs) {
                verdictChip(nil,      label: "All")
                verdictChip(.allow,   label: "Allowed")
                verdictChip(.block,   label: "Blocked")
                verdictChip(.pending, label: "Pending")
            }

            // Event count badge
            Text("\(filtered.count)")
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
    }

    private func verdictChip(_ verdict: Verdict?, label: String) -> some View {
        let selected = filterVerdict == verdict
        return Button {
            withAnimation(.gwFast) { filterVerdict = verdict }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(selected
                    ? (verdict?.color ?? .gwAccent)
                    : .gwTextTertiary)
                .padding(.horizontal, GWSpacing.sm)
                .padding(.vertical, 3)
                .background(selected
                    ? (verdict?.color ?? .gwAccent).opacity(0.15)
                    : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Event List
    // ─────────────────────────────────────────────────────────────────────────

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 1, pinnedViews: []) {
                ForEach(filtered) { event in
                    ConnectionEventRow(event: event)
                        .transition(.move(edge: .top).combined(with: .opacity))
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
            ScanlineEffect(color: .gwAccent)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: GWRadius.md))
                .overlay(
                    VStack(spacing: GWSpacing.sm) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 28))
                            .foregroundStyle(.gwAccent)
                        Text("Waiting for connections…")
                            .font(.gwBody)
                            .foregroundStyle(.gwTextSecondary)
                    }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GWSpacing.xxl)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Connection Event Row
// ─────────────────────────────────────────────────────────────────────────────

struct ConnectionEventRow: View {

    let event: ConnectionEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: GWSpacing.md) {

                NeonIndicator(verdict: event.verdict, size: 7)
                    .frame(width: 20)

                // App icon placeholder + name
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.process.name)
                        .font(.gwHeadline)
                        .foregroundStyle(.gwTextPrimary)
                        .lineLimit(1)
                    Text("PID \(event.process.pid)")
                        .font(.gwCaption)
                        .foregroundStyle(.gwTextTertiary)
                }
                .frame(width: 120, alignment: .leading)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.gwTextTertiary)

                // Destination
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.remoteHost)
                        .font(.gwMono)
                        .foregroundStyle(.gwTextPrimary)
                        .lineLimit(1)
                    Text(":\(event.remotePort) \(event.proto.rawValue)")
                        .font(.gwCaption)
                        .foregroundStyle(.gwTextTertiary)
                }

                Spacer()

                // Verdict badge
                verdictBadge

                // Timestamp
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)

                // Expand chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.gwTextTertiary)
            }
            .padding(.horizontal, GWSpacing.lg)
            .padding(.vertical, GWSpacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.gwFast) { isExpanded.toggle() }
            }

            if isExpanded {
                expandedDetail
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().overlay(Color.gwBorderSubtle.opacity(0.5))
        }
        .background(isExpanded ? Color.gwSurfaceSecondary : .clear)
    }

    private var verdictBadge: some View {
        Text(event.verdict.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(event.verdict.color)
            .padding(.horizontal, GWSpacing.sm)
            .padding(.vertical, 3)
            .background(event.verdict.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: GWSpacing.sm) {
            detailRow("Binary", value: event.process.binaryPath)
            if let ip = event.remoteIP {
                detailRow("Resolved IP", value: ip)
            }
            if let kind = event.ruleKind {
                detailRow("Rule", value: kind.label)
            }
            detailRow("Signing ID", value: event.process.signingIdentity ?? "—")
            detailRow("Signature", value: event.process.isSignatureValid ? "Valid" : "Invalid / Ad-hoc")
        }
        .padding(.horizontal, GWSpacing.xl + GWSpacing.md)
        .padding(.bottom, GWSpacing.md)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.gwMono)
                .foregroundStyle(.gwTextSecondary)
                .textSelection(.enabled)
        }
    }
}
