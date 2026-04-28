// MARK: - Intent Card View
// Non-blocking floating overlay shown top-right when a new unknown connection
// attempt requires user action. Cards stack vertically for multiple simultaneous
// pending flows. Each card has a configurable auto-dismiss timeout that defaults
// to blocking (Jail) if the user does not respond.
//
// Design goals:
//   • Must NOT freeze UI or stall the system (NE has its own timeout).
//   • Should be legible at a glance: who, where, what.
//   • Four clear decision buttons with distinct colours + icons.

import SwiftUI

// ── Intent Card Overlay — manages the queue of pending flows ──────────────────

struct IntentCardOverlay: View {

    @EnvironmentObject private var engine: PolicyEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: GWSpacing.md) {
            ForEach(engine.pendingFlows.prefix(4)) { event in
                IntentCardView(event: event)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
            }
            if engine.pendingFlows.count > 4 {
                Text("+\(engine.pendingFlows.count - 4) more pending…")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
                    .padding(.horizontal, GWSpacing.md)
            }
        }
        .animation(.gwSpring, value: engine.pendingFlows.count)
        .padding(GWSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(true)
    }
}

// ── Single Intent Card ────────────────────────────────────────────────────────

struct IntentCardView: View {

    let event: ConnectionEvent
    @EnvironmentObject private var engine: PolicyEngine

    @State private var timeRemaining: Int = Int(GlassWall.flowDecisionTimeoutSeconds)
    @State private var timerActive: Bool  = true
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GlassmorphicCard(
            cornerRadius: GWRadius.xl,
            borderColor: .gwBorderAccent,
            glowColor: .gwAccent,
            padding: GWSpacing.lg
        ) {
            VStack(alignment: .leading, spacing: GWSpacing.md) {
                header
                Divider().overlay(Color.gwBorderSubtle)
                connectionInfo
                Divider().overlay(Color.gwBorderSubtle)
                decisionButtons
                timerBar
            }
        }
        .frame(width: 340)
        .onReceive(timer) { _ in
            guard timerActive else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // Auto-dismiss with Jail verdict on timeout.
                dismiss(kind: .jail)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header
    // ─────────────────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: GWSpacing.sm) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.gwAccent)
                .glowPulse(color: .gwAccent, radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Request")
                    .font(.gwHeadline)
                    .foregroundStyle(.gwTextPrimary)
                Text("Requires your decision")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextSecondary)
            }

            Spacer()

            Button {
                dismiss(kind: .jail)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gwTextTertiary)
                    .padding(GWSpacing.xs)
                    .background(Color.gwSurfaceSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Connection Info
    // ─────────────────────────────────────────────────────────────────────────

    private var connectionInfo: some View {
        VStack(spacing: GWSpacing.sm) {
            infoRow(icon: "app.fill",
                    label: "Process",
                    value: event.process.name,
                    mono: false)
            infoRow(icon: "externaldrive.fill",
                    label: "Binary",
                    value: (event.process.binaryPath as NSString).lastPathComponent,
                    mono: true)
            infoRow(icon: "network",
                    label: "Destination",
                    value: "\(event.remoteHost):\(event.remotePort)",
                    mono: true)
            infoRow(icon: "arrow.triangle.branch",
                    label: "Protocol",
                    value: event.proto.rawValue,
                    mono: false)

            if let sigID = event.process.signingIdentity {
                infoRow(icon: "checkmark.seal",
                        label: "Signing ID",
                        value: sigID,
                        mono: true)
            } else {
                HStack(spacing: GWSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.gwWarning)
                    Text("Unsigned or ad-hoc signed binary")
                        .font(.gwCaption)
                        .foregroundStyle(.gwWarning)
                }
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String, mono: Bool) -> some View {
        HStack(spacing: GWSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.gwTextTertiary)
                .frame(width: 16)

            Text(label)
                .font(.gwCaption)
                .foregroundStyle(.gwTextTertiary)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(mono ? .gwMono : .gwBody)
                .foregroundStyle(.gwTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Decision Buttons
    // ─────────────────────────────────────────────────────────────────────────

    private var decisionButtons: some View {
        VStack(spacing: GWSpacing.sm) {
            HStack(spacing: GWSpacing.sm) {
                decisionButton(.whitelist)
                decisionButton(.incognito)
            }
            HStack(spacing: GWSpacing.sm) {
                decisionButton(.jail)
                decisionButton(.blacklist)
            }
        }
    }

    private func decisionButton(_ kind: RuleKind) -> some View {
        Button {
            dismiss(kind: kind)
        } label: {
            HStack(spacing: GWSpacing.xs) {
                Image(systemName: kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(kind.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(kind.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, GWSpacing.sm)
            .background(kind.color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: GWRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GWRadius.sm, style: .continuous)
                    .strokeBorder(kind.color.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Countdown Timer Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var timerBar: some View {
        VStack(spacing: GWSpacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gwSurfaceSecondary)
                        .frame(height: 3)
                    Capsule()
                        .fill(timerColor)
                        .frame(
                            width: geo.size.width * CGFloat(timeRemaining) /
                                   CGFloat(GlassWall.flowDecisionTimeoutSeconds),
                            height: 3
                        )
                        .animation(.linear(duration: 1), value: timeRemaining)
                }
            }
            .frame(height: 3)

            HStack {
                Text("Auto-blocks in")
                    .font(.gwCaption)
                    .foregroundStyle(.gwTextTertiary)
                Spacer()
                Text("\(timeRemaining)s")
                    .font(.gwCaption)
                    .foregroundStyle(timerColor)
                    .monospacedDigit()
            }
        }
    }

    private var timerColor: Color {
        let ratio = Double(timeRemaining) / GlassWall.flowDecisionTimeoutSeconds
        if ratio > 0.5 { return .gwAllow }
        if ratio > 0.2 { return .gwWarning }
        return .gwBlock
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Dismiss
    // ─────────────────────────────────────────────────────────────────────────

    private func dismiss(kind: RuleKind) {
        timerActive = false
        engine.applyDecision(kind: kind, for: event)
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    let engine = PolicyEngine()
    let ctx    = ProcessContext(pid: 1234, name: "Google Chrome",
                                binaryPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                                signingIdentity: "EQHXZ8M8AV",
                                isSignatureValid: true)
    let event  = ConnectionEvent(process: ctx,
                                 remoteHost: "clients4.google.com",
                                 remotePort: 443)

    return ZStack {
        LinearGradient(colors: [.gwBgTop, .gwBgBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        IntentCardView(event: event)
            .environmentObject(engine)
            .padding()
    }
    .preferredColorScheme(.dark)
    .frame(width: 400, height: 600)
}
