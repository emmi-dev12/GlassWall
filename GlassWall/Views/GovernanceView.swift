// MARK: - Governance View v2
// Rule management: grouped by app, searchable, with inline editing.

import SwiftUI
import AppKit

struct GovernanceView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText      = ""
    @State private var kindFilter: RuleKind? = nil

    private var grouped: [(key: String, rules: [PolicyRule])] {
        let filtered = engine.ruleStore.rules.filter { rule in
            let matchKind = kindFilter == nil || rule.kind == kindFilter
            guard matchKind else { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return rule.binaryPath.lowercased().contains(q)
                || (rule.domain?.lowercased().contains(q) ?? false)
        }
        let byApp = Dictionary(grouping: filtered) {
            ($0.binaryPath as NSString).lastPathComponent
        }
        return byApp
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (key: $0.key, rules: $0.value.sorted { $0.kind.precedence < $1.kind.precedence }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GlassDivider()
            if engine.ruleStore.rules.isEmpty {
                emptyState
            } else if grouped.isEmpty {
                noResultsState
            } else {
                ruleList
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: GWS.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rules")
                    .font(.gwTitle)
                    .foregroundStyle(.gwText1)
                Text("\(engine.ruleStore.rules.count) rule\(engine.ruleStore.rules.count == 1 ? "" : "s") saved")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
            }

            Spacer()

            SearchField(text: $searchText, placeholder: "Search app or domain…")
                .frame(width: 220)

            // Kind filter menu
            Menu {
                Button("All Rules") { kindFilter = nil }
                Divider()
                ForEach(RuleKind.allCases, id: \.self) { k in
                    Button {
                        kindFilter = k
                    } label: {
                        Label(k.label, systemImage: k.icon)
                    }
                }
            } label: {
                HStack(spacing: GWS.xs) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13))
                    Text(kindFilter?.shortLabel ?? "Filter")
                        .font(.gwBodyMed)
                }
                .foregroundStyle(.gwText2)
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
        .padding(.horizontal, GWS.xl)
        .padding(.vertical, GWS.lg)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Rule List
    // ─────────────────────────────────────────────────────────────────────────

    private var ruleList: some View {
        ScrollView {
            LazyVStack(spacing: GWS.lg, pinnedViews: []) {
                ForEach(grouped, id: \.key) { group in
                    AppRuleGroup(
                        appName: group.key,
                        rules:   group.rules,
                        onDelete: { id in
                            withAnimation(.gwFade) { engine.ruleStore.remove(id: id) }
                        },
                        onDeleteAll: {
                            if let first = group.rules.first {
                                withAnimation(.gwFade) {
                                    engine.ruleStore.removeAll(forBinaryPath: first.binaryPath)
                                }
                            }
                        }
                    )
                }
            }
            .padding(GWS.xl)
            .animation(.gwFade, value: grouped.count)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Empty States
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: GWS.xl) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.gwText3)

            VStack(spacing: GWS.sm) {
                Text("No rules yet")
                    .font(.gwTitle2)
                    .foregroundStyle(.gwText2)
                Text("Rules appear here after you respond to a connection request.\nYou can always come back and change them.")
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
            Text("No matching rules")
                .font(.gwHeadline)
                .foregroundStyle(.gwText2)
            Button("Clear filter") { searchText = ""; kindFilter = nil }
                .buttonStyle(.plain)
                .foregroundStyle(.gwTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: App Rule Group
// ─────────────────────────────────────────────────────────────────────────────

struct AppRuleGroup: View {

    let appName:    String
    let rules:      [PolicyRule]
    let onDelete:   (RuleID) -> Void
    let onDeleteAll: () -> Void

    @State private var appIcon: NSImage? = nil
    @State private var isExpanded = true

    var body: some View {
        GlassmorphicCard(cornerRadius: GWR.md, padding: 0) {
            VStack(spacing: 0) {
                // Group header
                HStack(spacing: GWS.md) {
                    // App icon
                    Group {
                        if let img = appIcon {
                            Image(nsImage: img).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 18))
                                .foregroundStyle(.gwText3)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appName)
                            .font(.gwHeadline)
                            .foregroundStyle(.gwText1)
                        Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                            .font(.gwCaption)
                            .foregroundStyle(.gwText3)
                    }

                    Spacer()

                    // Rule kind summary dots
                    HStack(spacing: GWS.xs) {
                        ForEach(rules.prefix(4)) { rule in
                            Circle()
                                .fill(rule.kind.color)
                                .frame(width: 7, height: 7)
                        }
                    }

                    Button {
                        withAnimation(.gwFade) { onDeleteAll() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.gwText3)
                    }
                    .buttonStyle(.plain)
                    .help("Remove all rules for \(appName)")

                    Button {
                        withAnimation(.gwSnappy) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.gwText3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(GWS.lg)

                if isExpanded {
                    GlassDivider()
                    VStack(spacing: 0) {
                        ForEach(rules) { rule in
                            RuleRow(rule: rule) { onDelete(rule.id) }
                            if rule.id != rules.last?.id {
                                GlassDivider().padding(.leading, GWS.xl + GWS.md)
                            }
                        }
                    }
                    .transition(.gwFadeIn)
                }
            }
        }
        .task {
            if let path = rules.first?.binaryPath {
                appIcon = loadIcon(for: path)
            }
        }
    }

    private func loadIcon(for path: String) -> NSImage? {
        var url = URL(fileURLWithPath: path)
        while url.pathExtension != "app", url.pathComponents.count > 2 {
            url = url.deletingLastPathComponent()
        }
        return url.pathExtension == "app"
            ? NSWorkspace.shared.icon(forFile: url.path)
            : NSWorkspace.shared.icon(forFile: path)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Rule Row
// ─────────────────────────────────────────────────────────────────────────────

struct RuleRow: View {

    let rule:     PolicyRule
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GWS.lg) {
            // Kind colour bar
            RoundedRectangle(cornerRadius: 2)
                .fill(rule.kind.color)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                RuleKindBadge(kind: rule.kind)
                if let domain = rule.domain {
                    Text(domain)
                        .font(.gwMono)
                        .foregroundStyle(.gwText2)
                        .lineLimit(1)
                } else {
                    Text("All connections")
                        .font(.gwCaption)
                        .foregroundStyle(.gwText3)
                        .italic()
                }
            }

            Spacer()

            // Expiry for incognito rules
            if let exp = rule.expiresAt {
                expiryView(exp)
            }

            // Created at
            Text(rule.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.gwMonoSmall)
                .foregroundStyle(.gwText3)
                .monospacedDigit()

            // Delete button (shows on hover)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.gwBlock)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.gwFade, value: isHovered)
            .help("Delete this rule")
        }
        .padding(.horizontal, GWS.lg)
        .padding(.vertical, GWS.md)
        .background(isHovered ? Color.gwSurfaceHover : Color.clear)
        .onHover { isHovered = $0 }
    }

    private func expiryView(_ date: Date) -> some View {
        let expired = date < Date()
        return Label(
            expired
                ? "Expired"
                : "Expires \(date.formatted(.relative(presentation: .named)))",
            systemImage: expired ? "clock.badge.xmark" : "clock"
        )
        .font(.gwCaption)
        .foregroundStyle(expired ? .gwBlock : .gwPending)
        .labelStyle(.titleAndIcon)
    }
}
