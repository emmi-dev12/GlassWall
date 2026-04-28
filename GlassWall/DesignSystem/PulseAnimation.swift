// MARK: - Pulse Animation Utilities
// Reusable animation modifiers for the live-pulse feed and panic mode banner.

import SwiftUI

// ── Ripple effect — expanding ring for new critical events ────────────────────

struct RippleEffect: View {

    let color: Color
    var count: Int      = 2
    var duration: Double = 1.8

    @State private var triggered = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(triggered ? 0 : 0.6), lineWidth: 1.5)
                    .scaleEffect(triggered ? 2.4 : 0.8)
                    .animation(
                        .easeOut(duration: duration).delay(Double(i) * 0.3).repeatForever(),
                        value: triggered
                    )
            }
        }
        .onAppear { triggered = true }
    }
}

// ── Heartbeat / scanner sweep ─────────────────────────────────────────────────

struct ScanlineEffect: View {

    var color: Color = .gwAccent

    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 40)
                .offset(y: offset)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        offset = geo.size.height
                    }
                }
        }
        .clipped()
    }
}

// ── Glow pulse modifier ───────────────────────────────────────────────────────

struct GlowPulse: ViewModifier {

    let color: Color
    var radius: CGFloat = 8
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(on ? 0.9 : 0.2), radius: on ? radius : radius * 0.4)
            .onAppear {
                withAnimation(.gwGlowPulse) { on = true }
            }
    }
}

extension View {
    func glowPulse(color: Color, radius: CGFloat = 8) -> some View {
        modifier(GlowPulse(color: color, radius: radius))
    }
}

// ── Panic mode border flash ───────────────────────────────────────────────────

struct PanicBorderFlash: ViewModifier {

    @State private var bright = false

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: GWRadius.lg, style: .continuous)
                .strokeBorder(Color.gwPanic.opacity(bright ? 0.85 : 0.3), lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: bright)
        )
        .onAppear { bright = true }
    }
}

extension View {
    func panicBorderFlash() -> some View {
        modifier(PanicBorderFlash())
    }
}
