// MARK: - Status Dot
// Minimal animated status indicator. Animates only when `isAnimating` is true
// so static states don't waste CPU on the render thread.

import SwiftUI

struct StatusDot: View {

    let color: Color
    var size: CGFloat     = 8
    var isAnimating: Bool = false

    @State private var scale: CGFloat  = 1.0
    @State private var opacity: Double = 0.5

    var body: some View {
        ZStack {
            // Outer pulse ring (animated only)
            Circle()
                .fill(color.opacity(opacity * 0.35))
                .frame(width: size * 2.8, height: size * 2.8)
                .scaleEffect(scale)
                .blur(radius: size * 0.5)

            // Core
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .gwGlowShadow(color: color, radius: size * 0.9)
        }
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.gwPulse) { scale = 1.3; opacity = 0.9 }
        }
        .onChange(of: isAnimating) { _, on in
            withAnimation(on ? .gwPulse : .gwFade) {
                scale   = on ? 1.3 : 1.0
                opacity = on ? 0.9 : 0.5
            }
        }
    }
}

extension StatusDot {
    init(verdict: Verdict, size: CGFloat = 8) {
        self.init(color: verdict.color, size: size,
                  isAnimating: verdict == .pending)
    }
}

// ── Verdict pill badge ────────────────────────────────────────────────────────

struct VerdictBadge: View {
    let verdict: Verdict
    var compact: Bool = false

    var body: some View {
        HStack(spacing: GWS.xs) {
            StatusDot(verdict: verdict, size: compact ? 5 : 6)
            if !compact {
                Text(verdict.label)
                    .font(.gwCaptionMed)
            }
        }
        .foregroundStyle(verdict.color)
        .padding(.horizontal, compact ? GWS.xs : GWS.sm)
        .padding(.vertical, compact ? 2 : 3)
        .background(verdict.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// ── Rule kind pill ────────────────────────────────────────────────────────────

struct RuleKindBadge: View {
    let kind: RuleKind

    var body: some View {
        HStack(spacing: GWS.xs) {
            Image(systemName: kind.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(kind.shortLabel)
                .font(.gwCaptionMed)
        }
        .foregroundStyle(kind.color)
        .padding(.horizontal, GWS.sm)
        .padding(.vertical, 3)
        .background(kind.color.opacity(0.12))
        .clipShape(Capsule())
    }
}
