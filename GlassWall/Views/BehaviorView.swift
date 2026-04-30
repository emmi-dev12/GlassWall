// MARK: - Behavior View v2
// EndpointSecurity event timeline with severity-grouped display,
// watchlist hit pinned alerts, and a readable detail sheet.

import SwiftUI

struct BehaviorView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText   = ""
    @State private var sevFilter: BehaviorSeverity? = nil
    @State private var selected: BehaviorEvent? = nil

    private var watchlistHits: [BehaviorEvent] {
        engine.behaviorEvents.filter { $0.isWatchlistHit }
    }

    private var filtered: [BehaviorEvent] {
        engine.behaviorEvents.filter { ev in
            let matchSev  = sevFilter == nil || ev.severity == sevFilter
            let matchSearch = searchText.isEmpty
                || ev.process.name.localizedCaseInsensitiveContains(searchText)
                || ev.filePath.localizedCaseInsensitiveContains(searchText)
            return matchSev && matchSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GlassDivider()
            if !watchlistHits.isEmpty { alertStrip }
            if engine.behaviorEvents.isEmpty { emptyState }
            else if filtered.isEmpty { noResultsState }
            else { timeline }
        }
        .sheet(item: $selected) { BehaviorDetailSheet(event: $0) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: GWS.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Behavior")
                    .font(.gwTitle)
                    .foregroundStyle(.gwText1)
                Text("File system & security events")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
            }

            Spacer()

            SearchField(text: $searchText, placeholder: "Search process or path…")
                .frame(width: 220)

            HStack(spacing: GWS.xs) {
                FilterChip(label: "All",      color: .gwText2,   isOn: sevFilter == nil)          { sevFilter = nil }
                FilterChip(label: "Critical", color: .gwCritical, isOn: sevFilter == .critical)   { sevFilter = .critical }
                FilterChip(label: "Warning",  color: .gwWarning,  isOn: sevFilter == .warning)    { sevFilter = .warning }
                FilterChip(label: "Info",     color: .gwInfo,     isOn: sevFilter == .info)       { sevFilter = .info }
            }
        }
        .padding(.horizontal, GWS.xl)
        .padding(.vertical, GWS.lg)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Alert Strip (watchlist hits)
    // ─────────────────────────────────────────────────────────────────────────

    private var alertStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GWS.md) {
                ForEach(watchlistHits.prefix(6)) { ev in
                    Button { selected = ev } label: {
                        HStack(spacing: GWS.sm) {
                            ZStack {
                                ExpandingRing(color: .gwCritical)
                                    .frame(width: 22, height: 22)
                                Circle()
                                    .fill(Color.gwCritical)
                                    .frame(width: 8, height: 8)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Suspicious Write")
                                    .font(.gwCaptionMed)
                                    .foregroundStyle(.gwCritical)
                                Text(ev.process.name)
                                    .font(.gwBody)
                                    .foregroundStyle(.gwText1)
                            }
                        }
                        .padding(.horizontal, GWS.md)
                        .padding(.vertical, GWS.sm + 2)
                        .background(Color.gwCritical.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: GWR.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: GWR.sm, style: .continuous)
                                .strokeBorder(Color.gwCritical.opacity(0.30), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, GWS.xl)
            .padding(.vertical, GWS.md)
        }
        .background(Color.gwCritical.opacity(0.05))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Timeline
    // ─────────────────────────────────────────────────────────────────────────

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { ev in
                    BehaviorRow(event: ev) { selected = ev }
                    GlassDivider().padding(.leading, 60)
                }
            }
            .animation(.gwFade, value: filtered.count)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Empty States
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: GWS.xl) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.gwAllow.opacity(0.5))

            VStack(spacing: GWS.sm) {
                Text("Nothing suspicious detected")
                    .font(.gwTitle2)
                    .foregroundStyle(.gwText2)
                Text("GlassWall monitors file writes, renames, and process memory activity.\nSuspicious events — like apps installing LaunchAgents — will appear here.")
                    .font(.gwBody)
                    .foregroundStyle(.gwText3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GWS.xxxl)
    }

    private var noResultsState: some View {
        VStack(spacing: GWS.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.gwText3)
            Text("No matching events")
                .font(.gwHeadline)
                .foregroundStyle(.gwText2)
            Button("Clear filter") { searchText = ""; sevFilter = nil }
                .buttonStyle(.plain)
                .foregroundStyle(.gwTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Behavior Row
// ─────────────────────────────────────────────────────────────────────────────

struct BehaviorRow: View {

    let event:  BehaviorEvent
    let onTap:  () -> Void

    @State private var isHovered = false

    private var friendlyType: String {
        switch event.eventType {
        case .fileCreate:            return "Created file"
        case .fileRename:            return "Renamed file"
        case .fileDelete:            return "Deleted file"
        case .mmapExecutable:        return "Mapped executable memory"
        case .launchAgentInstall:    return "Installed launch agent"
        case .privilegedHelperWrite: return "Wrote privileged helper"
        case .nativeMessagingHost:   return "Installed browser extension host"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline spine
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(event.severity.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: event.severity.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.severity.color)
                }
                .gwGlowShadow(color: event.isWatchlistHit ? event.severity.color : .clear,
                               radius: 6)

                Rectangle()
                    .fill(Color.gwBorder)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 60)

            // Content
            VStack(alignment: .leading, spacing: GWS.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: GWS.sm) {
                            Text(event.process.name)
                                .font(.gwHeadline)
                                .foregroundStyle(.gwText1)

                            if event.isWatchlistHit {
                                Label("Watchlist", systemImage: "exclamationmark.shield.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.gwCritical)
                                    .padding(.horizontal, GWS.sm)
                                    .padding(.vertical, 2)
                                    .background(Color.gwCritical.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(friendlyType)
                            .font(.gwBody)
                            .foregroundStyle(event.isWatchlistHit ? .gwWarning : .gwText2)
                    }

                    Spacer()

                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.gwMonoSmall)
                        .foregroundStyle(.gwText3)
                        .monospacedDigit()
                }

                // File path chip
                HStack(spacing: GWS.xs) {
                    Image(systemName: "doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.gwText3)
                    Text(event.filePath)
                        .font(.gwMonoSmall)
                        .foregroundStyle(.gwText3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let dst = event.destinationPath {
                    HStack(spacing: GWS.xs) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.gwText3)
                        Text(dst)
                            .font(.gwMonoSmall)
                            .foregroundStyle(.gwText3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Text("Tap for details")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.vertical, GWS.md)
            .padding(.trailing, GWS.xl)
        }
        .background(
            (isHovered || event.isWatchlistHit)
                ? (event.isWatchlistHit
                    ? Color.gwCritical.opacity(0.05)
                    : Color.gwSurfaceHover)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Behavior Detail Sheet
// ─────────────────────────────────────────────────────────────────────────────

struct BehaviorDetailSheet: View {

    let event: BehaviorEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [.gwBgElevated, .gwBgBase],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack(spacing: GWS.md) {
                    Image(systemName: event.severity.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(event.severity.color)
                        .breathingGlow(event.severity.color)

                    Text(eventTitle)
                        .font(.gwTitle)
                        .foregroundStyle(.gwText1)

                    Spacer()

                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.gwBodyMed)
                        .foregroundStyle(.gwTeal)
                        .padding(.horizontal, GWS.md)
                        .padding(.vertical, GWS.sm - 1)
                        .background(Color.gwTeal.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(GWS.xl)

                GlassDivider()

                ScrollView {
                    VStack(spacing: GWS.lg) {
                        // Watchlist hit banner
                        if event.isWatchlistHit {
                            HStack(spacing: GWS.md) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.gwCritical)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Suspicious Configuration Injection")
                                        .font(.gwHeadline)
                                        .foregroundStyle(.gwCritical)
                                    Text(WatchlistMonitor.shared.category(for: event.filePath))
                                        .font(.gwBody)
                                        .foregroundStyle(.gwText2)
                                    Text("This type of write can be used to make an app launch automatically or intercept browser communications.")
                                        .font(.gwCaption)
                                        .foregroundStyle(.gwText3)
                                }
                                Spacer()
                            }
                            .padding(GWS.lg)
                            .background(Color.gwCritical.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: GWR.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: GWR.md, style: .continuous)
                                    .strokeBorder(Color.gwCritical.opacity(0.30), lineWidth: 0.75)
                            )
                        }

                        // Process card
                        detailCard(title: "Process") {
                            detailGrid([
                                ("Name",        event.process.name),
                                ("PID",         "\(event.process.pid)"),
                                ("Binary",      event.process.binaryPath),
                                ("Signing ID",  event.process.signingIdentity ?? "None (unsigned)"),
                                ("Signature",   event.process.isSignatureValid ? "Valid ✓" : "Invalid ✗"),
                            ])
                        }

                        // File activity card
                        detailCard(title: "File Activity") {
                            detailGrid([
                                ("Action",      friendlyAction),
                                ("Path",        event.filePath),
                                event.destinationPath.map { ("Destination", $0) },
                                ("Time",        event.timestamp.formatted(.dateTime)),
                                ("Severity",    event.severity.label),
                            ].compactMap { $0 })
                        }
                    }
                    .padding(GWS.xl)
                }
            }
        }
        .frame(width: 540, height: 520)
        .preferredColorScheme(.dark)
    }

    private var eventTitle: String {
        switch event.eventType {
        case .fileCreate:            return "File Created"
        case .fileRename:            return "File Renamed"
        case .fileDelete:            return "File Deleted"
        case .mmapExecutable:        return "Executable Memory Mapped"
        case .launchAgentInstall:    return "Launch Agent Installed"
        case .privilegedHelperWrite: return "Privileged Helper Written"
        case .nativeMessagingHost:   return "Browser Host Installed"
        }
    }

    private var friendlyAction: String {
        switch event.eventType {
        case .fileCreate:            return "Created"
        case .fileRename:            return "Renamed / Moved"
        case .fileDelete:            return "Deleted"
        case .mmapExecutable:        return "Memory-mapped (executable)"
        case .launchAgentInstall:    return "Launch Agent installed"
        case .privilegedHelperWrite: return "Privileged helper written"
        case .nativeMessagingHost:   return "Native messaging host installed"
        }
    }

    private func detailCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        GlassmorphicCard(cornerRadius: GWR.md, padding: GWS.lg) {
            VStack(alignment: .leading, spacing: GWS.md) {
                Text(title.uppercased())
                    .font(.gwCaptionMed)
                    .foregroundStyle(.gwText3)
                    .tracking(0.8)
                GlassDivider()
                content()
            }
        }
    }

    private func detailGrid(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: GWS.sm) {
            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .top, spacing: GWS.md) {
                    Text(label)
                        .font(.gwCaptionMed)
                        .foregroundStyle(.gwText3)
                        .frame(width: 80, alignment: .leading)
                    Text(value)
                        .font(.gwMono)
                        .foregroundStyle(.gwText1)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }
}
