// MARK: - Intent Card v2
// Non-blocking floating overlay using plain-English prompts.
// "Safari is trying to connect to example.com" — no jargon, four clear choices.

import SwiftUI
import AppKit

// ── Overlay manager — stacks cards ────────────────────────────────────────────

struct IntentCardOverlay: View {
    @EnvironmentObject private var engine: PolicyEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: GWS.md) {
            ForEach(engine.pendingFlows.prefix(3)) { event in
                IntentCardView(event: event)
                    .transition(.gwSlideIn)
            }
            if engine.pendingFlows.count > 3 {
                Text("+\(engine.pendingFlows.count - 3) more waiting")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
                    .padding(.horizontal, GWS.lg)
            }
        }
        .animation(.gwSpring, value: engine.pendingFlows.count)
        .padding(GWS.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(true)
    }
}

// ── Single Intent Card ────────────────────────────────────────────────────────

struct IntentCardView: View {

    let event: ConnectionEvent
    @EnvironmentObject private var engine: PolicyEngine

    private let total = Int(GlassWall.flowDecisionTimeoutSeconds)
    @State private var remaining: Int
    @State private var timerRunning = true
    @State private var appIcon: NSImage? = nil
    @State private var showDetails = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(event: ConnectionEvent) {
        self.event   = event
        _remaining   = State(initialValue: Int(GlassWall.flowDecisionTimeoutSeconds))
    }

    var body: some View {
        GlassmorphicCard(
            cornerRadius: GWR.lg,
            padding: 0,
            borderOpacity: 1.4,
            glowColor: .gwTeal,
            glowRadius: 14
        ) {
            VStack(spacing: 0) {
                cardHeader
                GlassDivider()
                questionSection
                GlassDivider()
                decisionButtons
                GlassDivider()
                timerStrip
            }
        }
        .frame(width: 360)
        .gwCardShadow()
        .onReceive(tick) { _ in tickDown() }
        .task { appIcon = loadIcon(path: event.process.binaryPath) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header
    // ─────────────────────────────────────────────────────────────────────────

    private var cardHeader: some View {
        HStack(spacing: GWS.md) {
            // App icon
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = appIcon {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 22))
                            .foregroundStyle(.gwText3)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.gwBorder, lineWidth: 0.75)
                )

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.gwPending)
                    .background(Circle().fill(Color.gwBgBase).padding(1))
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Connection Request")
                    .font(.gwCaptionMed)
                    .foregroundStyle(.gwText3)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(event.process.name)
                    .font(.gwTitle2)
                    .foregroundStyle(.gwText1)
                    .lineLimit(1)
            }

            Spacer()

            Button { dismiss(kind: .jail) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gwText3)
                    .padding(GWS.sm)
                    .background(Color.gwSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss (blocks for this session)")
        }
        .padding(GWS.lg)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Question Section
    // ─────────────────────────────────────────────────────────────────────────

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: GWS.md) {
            // Human-readable question
            Group {
                Text("\(event.process.name) ")
                    .font(.gwHeadline)
                    .foregroundStyle(.gwText1)
                + Text("wants to connect to")
                    .font(.gwBody)
                    .foregroundStyle(.gwText2)
            }

            // Destination chip
            HStack(spacing: GWS.sm) {
                Image(systemName: "network")
                    .font(.system(size: 12))
                    .foregroundStyle(.gwTeal)
                Text("\(event.remoteHost):\(event.remotePort)")
                    .font(.gwMono)
                    .foregroundStyle(.gwTeal)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(event.proto.rawValue)
                    .font(.gwCaptionMed)
                    .foregroundStyle(.gwText3)
                    .padding(.horizontal, GWS.sm)
                    .padding(.vertical, 2)
                    .background(Color.gwSurface)
                    .clipShape(Capsule())
            }
            .padding(GWS.md)
            .background(Color.gwTeal.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: GWR.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GWR.sm, style: .continuous)
                    .strokeBorder(Color.gwTeal.opacity(0.22), lineWidth: 0.75)
            )

            // Signature warning if unsigned
            if !event.process.isSignatureValid {
                HStack(spacing: GWS.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.gwWarning)
                    Text("This app is not signed by a trusted developer.")
                        .font(.gwCaption)
                        .foregroundStyle(.gwWarning)
                }
            }

            // Expandable technical details
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: GWS.xs) {
                    detailLine("Binary", (event.process.binaryPath as NSString).lastPathComponent)
                    detailLine("Full path", event.process.binaryPath)
                    detailLine("Signing ID", event.process.signingIdentity ?? "None")
                    detailLine("PID", "\(event.process.pid)")
                }
                .padding(.top, GWS.sm)
            } label: {
                Text("Technical details")
                    .font(.gwCaption)
                    .foregroundStyle(.gwText3)
            }
            .disclosureGroupStyle(CompactDisclosureStyle())
        }
        .padding(GWS.lg)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.gwCaptionMed)
                .foregroundStyle(.gwText3)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.gwMonoSmall)
                .foregroundStyle(.gwText2)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Decision Buttons
    // ─────────────────────────────────────────────────────────────────────────

    private var decisionButtons: some View {
        VStack(spacing: GWS.sm) {
            // Primary choices
            HStack(spacing: GWS.sm) {
                DecisionButton(kind: .whitelist,  isProminent: true)  { dismiss(kind: .whitelist) }
                DecisionButton(kind: .incognito,  isProminent: false) { dismiss(kind: .incognito) }
            }
            // Secondary choices
            HStack(spacing: GWS.sm) {
                DecisionButton(kind: .jail,       isProminent: false) { dismiss(kind: .jail) }
                DecisionButton(kind: .blacklist,  isProminent: false) { dismiss(kind: .blacklist) }
            }
        }
        .padding(GWS.lg)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Timer Strip
    // ─────────────────────────────────────────────────────────────────────────

    private var timerStrip: some View {
        HStack(spacing: GWS.md) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gwSurface).frame(height: 3)
                    Capsule()
                        .fill(timerColor)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(remaining) / CGFloat(total)),
                            height: 3
                        )
                        .animation(.linear(duration: 1), value: remaining)
                }
            }
            .frame(height: 3)

            Text("\(remaining)s")
                .font(.gwMonoSmall)
                .foregroundStyle(timerColor)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, GWS.lg)
        .padding(.vertical, GWS.sm + 2)
    }

    private var timerColor: Color {
        let ratio = Double(remaining) / Double(total)
        if ratio > 0.5 { return .gwAllow }
        if ratio > 0.2 { return .gwPending }
        return .gwBlock
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func tickDown() {
        guard timerRunning else { return }
        if remaining > 0 { remaining -= 1 } else { dismiss(kind: .jail) }
    }

    private func dismiss(kind: RuleKind) {
        timerRunning = false
        engine.applyDecision(kind: kind, for: event)
    }

    private func loadIcon(path: String) -> NSImage? {
        guard path != "unknown", !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        while url.pathExtension != "app", url.pathComponents.count > 2 {
            url = url.deletingLastPathComponent()
        }
        if url.pathExtension == "app" {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

// ── Decision button ───────────────────────────────────────────────────────────

struct DecisionButton: View {
    let kind: RuleKind
    var isProminent: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: GWS.xs) {
                HStack(spacing: GWS.xs) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(kind.label)
                        .font(.gwBodyMed)
                }
                .foregroundStyle(isProminent ? .white : kind.color)

                Text(kind.description)
                    .font(.gwCaption)
                    .foregroundStyle(isProminent ? .white.opacity(0.75) : kind.color.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GWS.md)
            .padding(.horizontal, GWS.sm)
            .background(
                isProminent
                    ? kind.color.opacity(isHovered ? 0.95 : 0.85)
                    : kind.color.opacity(isHovered ? 0.16 : 0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: GWR.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GWR.sm, style: .continuous)
                    .strokeBorder(
                        isProminent ? Color.clear : kind.color.opacity(0.30),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.gwFade, value: isHovered)
    }
}

// ── Compact disclosure group style ───────────────────────────────────────────

struct CompactDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: GWS.xs) {
            Button {
                withAnimation(.gwFade) { configuration.$isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: GWS.xs) {
                    configuration.label
                    Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.gwText3)
                }
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .transition(.gwFadeIn)
            }
        }
    }
}
