// MARK: - Glassmorphic Card v2
// Cleaner composition: one background layer, one border, optional accent glow.
// The padding parameter is kept so callers can opt for zero-padding layouts.

import SwiftUI

struct GlassmorphicCard<Content: View>: View {

    var cornerRadius: CGFloat  = GWR.md
    var padding: CGFloat       = GWS.lg
    var borderOpacity: Double  = 1.0
    var glowColor: Color?      = nil
    var glowRadius: CGFloat    = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(border)
            .gwCardShadow()
            .gwGlowShadow(color: glowColor ?? .clear, radius: glowRadius)
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.gwSurface)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16 * borderOpacity),
                        Color.white.opacity(0.05 * borderOpacity),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }
}

// ── Convenience modifier ──────────────────────────────────────────────────────

extension View {
    func glassCard(
        radius: CGFloat  = GWR.md,
        padding: CGFloat = GWS.lg,
        glow: Color?     = nil
    ) -> some View {
        GlassmorphicCard(
            cornerRadius: radius,
            padding: padding,
            glowColor: glow
        ) { self }
    }
}

// ── Divider that fits the glass aesthetic ─────────────────────────────────────

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.gwBorder)
            .frame(height: 0.5)
    }
}
