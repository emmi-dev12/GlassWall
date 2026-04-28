// MARK: - Neon Status Indicator
// Animated glowing dot that represents connection or security state.
// Supports pulsing animation for pending/active states.

import SwiftUI

struct NeonIndicator: View {

    let color: Color
    var size: CGFloat     = 8
    var isAnimating: Bool = false

    @State private var glowScale: CGFloat  = 1.0
    @State private var glowOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(glowOpacity * 0.4))
                .frame(width: size * 2.5, height: size * 2.5)
                .scaleEffect(glowScale)
                .blur(radius: size * 0.6)

            // Mid glow ring
            Circle()
                .fill(color.opacity(glowOpacity * 0.6))
                .frame(width: size * 1.6, height: size * 1.6)

            // Core dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.gwGlowPulse) {
                glowScale   = 1.25
                glowOpacity = 1.0
            }
        }
        .onChange(of: isAnimating) { _, animating in
            if animating {
                withAnimation(.gwGlowPulse) { glowScale = 1.25; glowOpacity = 1.0 }
            } else {
                withAnimation(.gwFast)      { glowScale = 1.0;  glowOpacity = 0.6 }
            }
        }
    }
}

// ── Verdict-convenience initialiser ──────────────────────────────────────────

extension NeonIndicator {
    init(verdict: Verdict, size: CGFloat = 8) {
        self.init(color: verdict.color,
                  size: size,
                  isAnimating: verdict == .pending)
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    HStack(spacing: 24) {
        NeonIndicator(verdict: .allow,   size: 10)
        NeonIndicator(verdict: .block,   size: 10)
        NeonIndicator(verdict: .pending, size: 10)
        NeonIndicator(color: .gwAccent,  size: 10, isAnimating: true)
    }
    .padding(40)
    .background(Color.gwBgTop)
}
