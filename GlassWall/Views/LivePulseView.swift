// MARK: - Live Pulse View v2
// Real-time feed of all network connection decisions.
// Uses NSWorkspace to load actual app icons for each process.

import SwiftUI
import AppKit

struct LivePulseView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText    = ""
    @State private var filter: Verdict? = nil
    @State private var expanded: FlowID? = nil

    private var events: [ConnectionEvent] {
        engine.connectionEvents.filter { event in
            let matchVerdict = filter == nil || event.verdict == filter
            let matchSearch  = searchText.isEmpty
                || event.process.name.localizedCaseInsensitiveContains(searchText)
                || event.remoteHost.localizedCaseInsensitiveContains(searchText)
            return matchVerdict && matchSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GlassDivider()

            if engine.connectionEvents.isEmpty {
                emptyState
            } else if events.isEmpty {
                noResultsState
            } else {
                feed
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: GWS.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Activity")
                    .font(.gwTitle)
                    .foregroundStyle(.gwText1)
                Text("\(engine.connectionEvents.count) connections monitored")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
            }

            Spacer()

            // Search field
            SearchField(text: $searchText, placeholder: "Search app or domain…")
                .frame(width: 210)

            // Filter chips
            HStack(spacing: GWS.xs) {
                FilterChip(label: "All",     color: .gwText2,  isOn: filter == nil)    { filter = nil }
                FilterChip(label: "Allowed", color: .gwAllow,  isOn: filter == .allow) { filter = .allow }
                FilterChip(label: "Blocked", color: .gwBlock,  isOn: filter == .block) { filter = .block }
                FilterChip(label: "Waiting", color: .gwPending, isOn: filter == .pending) { filter = .pending }
            }
        }
        .padding(.horizontal, GWS.xl)
        .padding(.vertical, GWS.lg)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Feed
    // ─────────────────────────────────────────────────────────────────────────

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events) { event in
                    PulseRow(event: event, isExpanded: expanded == event.id) {
                        withAnimation(.gwSnappy) {
                            expanded = expanded == event.id ? nil : event.id
                        }
                    }
                    GlassDivider().padding(.leading, 60)
                }
            }
            .animation(.gwFade, value: events.count)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Empty States
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: GWS.xl) {
            ZStack {
                ScanLine(color: .gwTeal)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: GWR.md))
                    .opacity(0.6)

                VStack(spacing: GWS.md) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.gwTeal)
                        .breathingGlow(.gwTeal, radius: 12)
                    Text("Watching for connections…")
                        .font(.gwHeadline)
                        .foregroundStyle(.gwText2)
                }
            }
            .frame(width: 340)

            Text("Network activity will appear here in real time once apps start making connections.")
                .font(.gwBody)
                .foregroundStyle(.gwText3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GWS.xxxl)
    }

    private var noResultsState: some View {
        VStack(spacing: GWS.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.gwText3)
            Text("No matching connections")
                .font(.gwHeadline)
                .foregroundStyle(.gwText2)
            Button("Clear filter") { searchText = ""; filter = nil }
                .buttonStyle(.plain)
                .font(.gwBodyMed)
                .foregroundStyle(.gwTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Pulse Row
// ─────────────────────────────────────────────────────────────────────────────

struct PulseRow: View {

    let event: ConnectionEvent
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var appIcon: NSImage? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: GWS.lg) {
                // App icon + status dot
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = appIcon {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 20))
                                .foregroundStyle(.gwText3)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    StatusDot(verdict: event.verdict, size: 7)
                        .offset(x: 3, y: 3)
                }
                .frame(width: 36)

                // Process + destination
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: GWS.sm) {
                        Text(event.process.name)
                            .font(.gwHeadline)
                            .foregroundStyle(.gwText1)
                            .lineLimit(1)

                        if !event.process.isSignatureValid {
                            Label("Unsigned", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.gwWarning)
                                .labelStyle(.iconOnly)
                        }
                    }

                    HStack(spacing: GWS.xs) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.gwText3)
                        Text(event.remoteHost)
                            .font(.gwMono)
                            .foregroundStyle(.gwText2)
                            .lineLimit(1)
                        Text(":\(event.remotePort)")
                            .font(.gwMonoSmall)
                            .foregroundStyle(.gwText3)
                    }
                }

                Spacer()

                // Verdict + time
                VStack(alignment: .trailing, spacing: 4) {
                    VerdictBadge(verdict: event.verdict, compact: false)
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.gwMonoSmall)
                        .foregroundStyle(.gwText3)
                        .monospacedDigit()
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gwText3)
                    .animation(.gwSnappy, value: isExpanded)
            }
            .padding(.horizontal, GWS.xl)
            .padding(.vertical, GWS.md)
            .background(isHovered || isExpanded ? Color.gwSurfaceHover : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { isHovered = $0 }

            // Expanded detail panel
            if isExpanded {
                expandedPanel
                    .transition(.gwFadeIn)
            }
        }
        .animation(.gwSnappy, value: isExpanded)
        .task { appIcon = loadAppIcon(path: event.process.binaryPath) }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: GWS.sm) {
            HStack(spacing: GWS.xxl) {
                detailColumn(items: [
                    ("Binary",      (event.process.binaryPath as NSString).lastPathComponent),
                    ("Full path",   event.process.binaryPath),
                    ("PID",         "\(event.process.pid)"),
                ])
                detailColumn(items: [
                    ("Remote IP",   event.remoteIP ?? "—"),
                    ("Protocol",    event.proto.rawValue),
                    ("Signing",     event.process.signingIdentity ?? "Unsigned / Ad-hoc"),
                ])
                if let kind = event.ruleKind {
                    VStack(alignment: .leading, spacing: GWS.xs) {
                        Text("Rule applied")
                            .font(.gwCaptionMed)
                            .foregroundStyle(.gwText3)
                        RuleKindBadge(kind: kind)
                    }
                }
            }
        }
        .padding(.horizontal, GWS.xl + 36 + GWS.lg)   // align with text column
        .padding(.bottom, GWS.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gwSurface.opacity(0.5))
    }

    private func detailColumn(items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: GWS.xs) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.gwCaptionMed)
                        .foregroundStyle(.gwText3)
                    Text(value)
                        .font(.gwMono)
                        .foregroundStyle(.gwText2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func loadAppIcon(path: String) -> NSImage? {
        guard path != "unknown", !path.isEmpty else { return nil }
        // Walk up the path to find the .app bundle
        var url = URL(fileURLWithPath: path)
        while url.pathExtension != "app" && url.pathComponents.count > 2 {
            url = url.deletingLastPathComponent()
        }
        let workspace = NSWorkspace.shared
        if url.pathExtension == "app" {
            return workspace.icon(forFile: url.path)
        }
        return workspace.icon(forFile: path)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Reusable Search Field + Filter Chip
// ─────────────────────────────────────────────────────────────────────────────

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search…"

    var body: some View {
        HStack(spacing: GWS.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.gwText3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.gwBody)
                .foregroundStyle(.gwText1)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gwText3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, GWS.md)
        .padding(.vertical, GWS.sm - 1)
        .background(Color.gwSurface)
        .clipShape(RoundedRectangle(cornerRadius: GWR.pill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GWR.pill, style: .continuous)
                .strokeBorder(Color.gwBorder, lineWidth: 0.75)
        )
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let isOn:  Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.gwCaptionMed)
                .foregroundStyle(isOn ? color : .gwText3)
                .padding(.horizontal, GWS.sm)
                .padding(.vertical, 4)
                .background(isOn ? color.opacity(0.14) : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.30) : Color.clear, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .animation(.gwFade, value: isOn)
    }
}
