// MARK: - Governance View
// Rule management tab: search, inspect, and delete persisted allow/deny rules.

import SwiftUI

struct GovernanceView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var searchText      = ""
    @State private var selectedKind: RuleKind? = nil
    @State private var ruleToDelete: PolicyRule? = nil

    private var filtered: [PolicyRule] {
        engine.ruleStore.rules
            .filter { rule in
                let matchesKind = selectedKind == nil || rule.kind == selectedKind
                guard matchesKind else { return false }
                guard !searchText.isEmpty else { return true }
                let q = searchText.lowercased()
                return rule.binaryPath.lowercased().contains(q) ||
                    (rule.domain?.lowercased().contains(q) ?? false)
            }
            .sorted { $0.kind.precedence < $1.kind.precedence }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.gwBorderSubtle)
            if filtered.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Toolbar
    // ─────────────────────────────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: GWSpacing.md) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .foregroundStyle(.gwAccent)
                .font(.system(size: 15, weight: .semibold))

            Text("Governance")
                .font(.gwTitle)
                .foregroundStyle(.gwTextPrimary)

            Spacer()

            // Search
            HStack(spacing: GWSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.gwTextTertiary)
                TextField("Search by app or domain…", text: $searchText)
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

            // Kind filter
            Menu {
                Button("All") { selectedKind = nil }
                Divider()
                ForEach(RuleKind.allCases, id: \.self) { kind in
                    Button(kind.label) { selectedKind = kind }
                }
            } label: {
                HStack(spacing: GWSpacing.xs) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedKind?.label ?? "Filter")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gwTextSecondary)
                .padding(.horizontal, GWSpacing.md)
                .padding(.vertical, GWSpacing.xs)
                .background(Color.gwSurfaceSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.gwBorderSubtle, lineWidth: 0.5))
            }

            Text("\(filtered.count) rule\(filtered.count == 1 ? "" : "s")")
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Rule List
    // ─────────────────────────────────────────────────────────────────────────

    private var ruleList: some View {
        ScrollView {
            LazyVStack(spacing: GWSpacing.sm, pinnedViews: []) {
                // Group by kind
                ForEach(RuleKind.allCases, id: \.self) { kind in
                    let kindRules = filtered.filter { $0.kind == kind }
                    if !kindRules.isEmpty {
                        Section {
                            ForEach(kindRules) { rule in
                                RuleRow(rule: rule) {
                                    withAnimation(.gwFast) {
                                        engine.ruleStore.remove(id: rule.id)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        } header: {
                            kindSectionHeader(kind)
                        }
                    }
                }
            }
            .animation(.gwFast, value: filtered.count)
            .padding(GWSpacing.lg)
        }
    }

    private func kindSectionHeader(_ kind: RuleKind) -> some View {
        HStack(spacing: GWSpacing.sm) {
            Image(systemName: kind.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind.color)
            Text(kind.label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(kind.color)
            Rectangle()
                .fill(kind.color.opacity(0.25))
                .frame(height: 0.5)
        }
        .padding(.top, GWSpacing.sm)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Empty State
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: GWSpacing.lg) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.gwAccent.opacity(0.5))
            Text(searchText.isEmpty ? "No rules yet" : "No matching rules")
                .font(.gwHeadline)
                .foregroundStyle(.gwTextSecondary)
            Text("Decisions you make in Intent Cards will appear here.")
                .font(.gwBody)
                .foregroundStyle(.gwTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GWSpacing.xxl)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Rule Row
// ─────────────────────────────────────────────────────────────────────────────

struct RuleRow: View {

    let rule: PolicyRule
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: GWSpacing.md) {

            // Kind indicator
            Image(systemName: rule.kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(rule.kind.color)
                .frame(width: 24)

            // Binary name
            VStack(alignment: .leading, spacing: 2) {
                Text((rule.binaryPath as NSString).lastPathComponent)
                    .font(.gwHeadline)
                    .foregroundStyle(.gwTextPrimary)
                    .lineLimit(1)
                Text(rule.binaryPath)
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Domain badge
            if let domain = rule.domain {
                Text(domain)
                    .font(.gwMono)
                    .foregroundStyle(rule.kind.color)
                    .padding(.horizontal, GWSpacing.sm)
                    .padding(.vertical, 3)
                    .background(rule.kind.color.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Text("All domains")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
            }

            // Expiry badge for incognito rules
            if let exp = rule.expiresAt {
                expiryBadge(exp)
            }

            // Delete button (shown on hover)
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.gwBlock)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, GWSpacing.lg)
        .padding(.vertical, GWSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: GWRadius.md, style: .continuous)
                .fill(isHovered ? Color.gwSurfaceSecondary : Color.gwSurfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GWRadius.md, style: .continuous)
                .strokeBorder(Color.gwBorderSubtle, lineWidth: 0.5)
        )
        .animation(.gwFast, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func expiryBadge(_ date: Date) -> some View {
        let expired = date < Date()
        let label   = expired ? "Expired" : "Expires \(date.formatted(.relative(presentation: .numeric)))"
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(expired ? .gwBlock : .gwWarning)
            .padding(.horizontal, GWSpacing.sm)
            .padding(.vertical, 2)
            .background((expired ? Color.gwBlock : Color.gwWarning).opacity(0.12))
            .clipShape(Capsule())
    }
}
