// MARK: - Content View v2
// NavigationSplitView gives a proper macOS sidebar + detail layout.
// The Intent Card overlay floats above everything via a ZStack.

import SwiftUI

enum GWSection: String, CaseIterable, Identifiable {
    case overview   = "Overview"
    case pulse      = "Live Activity"
    case governance = "Rules"
    case behavior   = "Behavior"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:   return "shield.lefthalf.filled"
        case .pulse:      return "waveform.path.ecg"
        case .governance: return "list.bullet.rectangle.portrait.fill"
        case .behavior:   return "eye.trianglebadge.exclamationmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview:   return .gwTeal
        case .pulse:      return .gwAllow
        case .governance: return .gwBlue
        case .behavior:   return .gwWarning
        }
    }
}

struct ContentView: View {

    @EnvironmentObject private var engine: PolicyEngine
    @State private var selection: GWSection = .overview
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
            } detail: {
                detailPane
            }
            .background(Color.gwBgBase)

            // Intent Card overlay — always on top
            if !engine.pendingFlows.isEmpty {
                IntentCardOverlay()
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Sidebar
    // ─────────────────────────────────────────────────────────────────────────

    private var sidebar: some View {
        VStack(spacing: 0) {

            // Brand header
            HStack(spacing: GWS.sm) {
                Image("AppIcon") // shows the app icon if resolvable
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.gwBorder, lineWidth: 0.5)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("GlassWall")
                        .font(.gwTitle2)
                        .foregroundStyle(.gwText1)
                    Text("Privacy Firewall")
                        .font(.gwMonoSmall)
                        .foregroundStyle(.gwText3)
                }
                Spacer()
            }
            .padding(.horizontal, GWS.lg)
            .padding(.top, GWS.xl)
            .padding(.bottom, GWS.lg)

            GlassDivider().padding(.horizontal, GWS.md)
            Spacer().frame(height: GWS.md)

            // Navigation items
            ForEach(GWSection.allCases) { section in
                SidebarItem(
                    section:   section,
                    isActive:  selection == section,
                    badge:     badge(for: section)
                ) {
                    withAnimation(.gwSnappy) { selection = section }
                }
            }

            Spacer()
            GlassDivider().padding(.horizontal, GWS.md)

            // Panic mode toggle
            panicModeButton
                .padding(.horizontal, GWS.md)
                .padding(.vertical, GWS.md)

            // Status footer
            statusFooter
                .padding(.horizontal, GWS.lg)
                .padding(.bottom, GWS.lg)
        }
        .frame(width: 220)
        .background(Color.gwBgElevated)
        .navigationSplitViewColumnWidth(220)
    }

    private func badge(for section: GWSection) -> Int? {
        switch section {
        case .pulse:    return engine.pendingFlows.isEmpty ? nil : engine.pendingFlows.count
        case .behavior: return engine.behaviorEvents.filter { $0.isWatchlistHit && $0.severity == .critical }.count > 0
                                ? engine.behaviorEvents.filter { $0.isWatchlistHit }.count : nil
        default:        return nil
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Detail Pane
    // ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var detailPane: some View {
        Group {
            switch selection {
            case .overview:   OverviewView(onSetup: { showOnboarding = true })
            case .pulse:      LivePulseView()
            case .governance: GovernanceView()
            case .behavior:   BehaviorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gwBgBase)
        // Show panic banner across the top of the detail pane
        .safeAreaInset(edge: .top, spacing: 0) {
            if engine.panicMode.isEnabled {
                PanicBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.gwSpring, value: engine.panicMode.isEnabled)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Panic Mode Button
    // ─────────────────────────────────────────────────────────────────────────

    private var panicModeButton: some View {
        let active = engine.panicMode.isEnabled
        return Button {
            withAnimation(.gwSpring) { engine.setPanicMode(!active) }
        } label: {
            HStack(spacing: GWS.sm) {
                Image(systemName: active ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? .gwPanic : .gwText2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clean Room")
                        .font(.gwBodyMed)
                        .foregroundStyle(active ? .gwPanic : .gwText1)
                    Text(active ? "Active — all blocked" : "Block all outbound")
                        .font(.gwCaption)
                        .foregroundStyle(active ? .gwPanic.opacity(0.7) : .gwText3)
                }
                Spacer()
                Circle()
                    .fill(active ? Color.gwPanic : Color.gwText3)
                    .frame(width: 8, height: 8)
                    .breathingGlow(active ? .gwPanic : .clear)
            }
            .padding(GWS.md)
            .background(active ? Color.gwPanicBg : Color.gwSurface)
            .clipShape(RoundedRectangle(cornerRadius: GWR.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GWR.sm, style: .continuous)
                    .strokeBorder(active ? Color.gwPanic.opacity(0.4) : Color.gwBorder,
                                  lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .if(active) { $0.panicFlash(radius: GWR.sm) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Status Footer
    // ─────────────────────────────────────────────────────────────────────────

    private var statusFooter: some View {
        HStack(spacing: GWS.sm) {
            StatusDot(color: .gwAllow, size: 6, isAnimating: true)
            Text("Extension Active")
                .font(.gwCaption)
                .foregroundStyle(.gwText3)
            Spacer()
            Text("\(engine.connectionEvents.count)")
                .font(.gwMonoSmall)
                .foregroundStyle(.gwText3)
                .monospacedDigit()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Sidebar Item
// ─────────────────────────────────────────────────────────────────────────────

struct SidebarItem: View {

    let section:  GWSection
    let isActive: Bool
    let badge:    Int?
    let action:   () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: GWS.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: GWR.xs, style: .continuous)
                        .fill(isActive ? section.tint.opacity(0.18) : Color.clear)
                        .frame(width: 28, height: 28)
                    Image(systemName: section.icon)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? section.tint : .gwText2)
                }

                Text(section.rawValue)
                    .font(isActive ? .gwBodyMed : .gwBody)
                    .foregroundStyle(isActive ? .gwText1 : .gwText2)

                Spacer()

                if let count = badge, count > 0 {
                    Text("\(min(count, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(section.tint)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, GWS.lg)
            .padding(.vertical, GWS.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: GWR.sm, style: .continuous)
                    .fill(isActive
                          ? section.tint.opacity(0.10)
                          : (isHovered ? Color.gwSurface : .clear))
                    .padding(.horizontal, GWS.sm)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Panic Banner
// ─────────────────────────────────────────────────────────────────────────────

struct PanicBanner: View {
    @EnvironmentObject private var engine: PolicyEngine

    var body: some View {
        HStack(spacing: GWS.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.gwPanic)

            VStack(alignment: .leading, spacing: 1) {
                Text("Digital Clean Room is Active")
                    .font(.gwBodyMed)
                    .foregroundStyle(.gwPanic)
                Text("Only Apple system services can connect. All other traffic is blocked.")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText2)
            }

            Spacer()

            Button("Turn Off") {
                withAnimation(.gwSpring) { engine.setPanicMode(false) }
            }
            .buttonStyle(.plain)
            .font(.gwBodyMed)
            .foregroundStyle(.gwPanic)
            .padding(.horizontal, GWS.md)
            .padding(.vertical, GWS.sm)
            .background(Color.gwPanic.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gwPanic.opacity(0.35), lineWidth: 0.75))
        }
        .padding(.horizontal, GWS.xl)
        .padding(.vertical, GWS.sm + 2)
        .background(Color.gwPanicBg)
        .panicFlash(radius: 0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Conditional modifier helper
// ─────────────────────────────────────────────────────────────────────────────

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool,
                               transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}
