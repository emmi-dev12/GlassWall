// MARK: - Glassmorphic Card
// Reusable glass-effect container used throughout GlassWall's UI.
// Composes .ultraThinMaterial with a translucent border and optional glow.

import SwiftUI

struct GlassmorphicCard<Content: View>: View {

    var cornerRadius: CGFloat   = GWRadius.lg
    var borderColor: Color      = .gwBorderSubtle
    var glowColor: Color?       = nil
    var glowRadius: CGFloat     = 12
    var padding: CGFloat        = GWSpacing.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(border)
            .shadow(color: glowColor?.opacity(0.25) ?? .clear, radius: glowRadius)
    }

    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.gwSurfacePrimary)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [borderColor, borderColor.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }
}

// ── Convenience modifier ──────────────────────────────────────────────────────

extension View {
    func glassmorphic(
        cornerRadius: CGFloat = GWRadius.lg,
        borderColor: Color    = .gwBorderSubtle,
        glowColor: Color?     = nil,
        padding: CGFloat      = GWSpacing.lg
    ) -> some View {
        GlassmorphicCard(
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            glowColor: glowColor,
            padding: padding
        ) { self }
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    ZStack {
        LinearGradient(colors: [.gwBgTop, .gwBgBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GlassmorphicCard(glowColor: .gwAccent) {
            VStack(alignment: .leading, spacing: GWSpacing.sm) {
                Text("GlassWall").font(.gwTitle).foregroundStyle(.gwTextPrimary)
                Text("Glassmorphic card demo").font(.gwBody).foregroundStyle(.gwTextSecondary)
            }
        }
        .frame(width: 280)
    }
    .preferredColorScheme(.dark)
}
