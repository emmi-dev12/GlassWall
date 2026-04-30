// MARK: - Animation Utilities v2

import SwiftUI

// ── Breathing glow modifier (idle system animation) ───────────────────────────

struct BreathingGlow: ViewModifier {
    let color: Color
    var radius: CGFloat = 8
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(on ? 0.55 : 0.15),
                    radius: on ? radius : radius * 0.3)
            .onAppear { withAnimation(.gwBreath) { on = true } }
    }
}

extension View {
    func breathingGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        modifier(BreathingGlow(color: color, radius: radius))
    }
}

// ── Expanding ring (used for watchlist hit alerts) ────────────────────────────

struct ExpandingRing: View {
    let color: Color
    @State private var scale: CGFloat   = 0.6
    @State private var opacity: Double  = 0.8

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1.5)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    scale = 2.2; opacity = 0
                }
            }
    }
}

// ── Scan line (subtle texture for empty states) ───────────────────────────────

struct ScanLine: View {
    var color: Color = .gwTeal

    @State private var offset: CGFloat = -80

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, color.opacity(0.18), color.opacity(0.30),
                         color.opacity(0.18), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 80)
            .offset(y: offset)
            .onAppear {
                withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                    offset = geo.size.height + 80
                }
            }
        }
        .clipped()
    }
}

// ── Panic mode flashing border ────────────────────────────────────────────────

struct PanicFlashBorder: ViewModifier {
    var radius: CGFloat = GWR.md
    @State private var bright = false

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.gwPanic.opacity(bright ? 0.80 : 0.25), lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: bright)
        )
        .onAppear { bright = true }
    }
}

extension View {
    func panicFlash(radius: CGFloat = GWR.md) -> some View {
        modifier(PanicFlashBorder(radius: radius))
    }
}

// ── Slide + fade transition preset ───────────────────────────────────────────

extension AnyTransition {
    static var gwSlideIn: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        )
    }
    static var gwFadeIn: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }
}
