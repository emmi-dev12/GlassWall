// MARK: - GlassWall Design Tokens
// Single source of truth for colours, typography, spacing, and animation
// parameters used across the glassmorphism UI.

import SwiftUI

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Colour Palette
// ──────────────────────────────────────────────────────────────────────────────

extension Color {

    // ── Brand ─────────────────────────────────────────────────────────────────
    static let gwAccent      = Color(hex: "#00D4FF")   // electric cyan — primary accent
    static let gwAccentWarm  = Color(hex: "#7B61FF")   // violet — secondary accent

    // ── Semantic status colours ───────────────────────────────────────────────
    static let gwAllow       = Color(hex: "#00FF9C")   // neon green
    static let gwBlock       = Color(hex: "#FF3B5C")   // vivid red
    static let gwPending     = Color(hex: "#FFB800")   // amber
    static let gwWarning     = Color(hex: "#FF8C00")   // orange
    static let gwCritical    = Color(hex: "#FF3B5C")   // same as block — high severity

    // ── Panic Mode ────────────────────────────────────────────────────────────
    static let gwPanic       = Color(hex: "#FF3B5C")
    static let gwPanicDim    = Color(hex: "#FF3B5C").opacity(0.18)

    // ── Glass surfaces ────────────────────────────────────────────────────────
    static let gwSurfacePrimary   = Color.white.opacity(0.06)
    static let gwSurfaceSecondary = Color.white.opacity(0.03)
    static let gwBorderSubtle     = Color.white.opacity(0.10)
    static let gwBorderAccent     = Color(hex: "#00D4FF").opacity(0.35)

    // ── Text ──────────────────────────────────────────────────────────────────
    static let gwTextPrimary   = Color.white
    static let gwTextSecondary = Color.white.opacity(0.60)
    static let gwTextTertiary  = Color.white.opacity(0.35)

    // ── Background gradient stops ─────────────────────────────────────────────
    static let gwBgTop    = Color(hex: "#0A0E1A")
    static let gwBgBottom = Color(hex: "#050810")
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64(0)
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Verdict → Colour Mapping
// ──────────────────────────────────────────────────────────────────────────────

extension Verdict {
    var color: Color {
        switch self {
        case .allow:   return .gwAllow
        case .block:   return .gwBlock
        case .pending: return .gwPending
        }
    }

    var label: String {
        switch self {
        case .allow:   return "Allowed"
        case .block:   return "Blocked"
        case .pending: return "Pending"
        }
    }
}

extension RuleKind {
    var color: Color {
        switch self {
        case .whitelist:  return .gwAllow
        case .incognito:  return .gwAccent
        case .jail:       return .gwWarning
        case .blacklist:  return .gwBlock
        }
    }

    var label: String {
        switch self {
        case .whitelist:  return "Whitelist"
        case .incognito:  return "Incognito"
        case .jail:       return "Jail"
        case .blacklist:  return "Blacklist"
        }
    }

    var icon: String {
        switch self {
        case .whitelist:  return "checkmark.shield.fill"
        case .incognito:  return "timer"
        case .jail:       return "lock.fill"
        case .blacklist:  return "xmark.shield.fill"
        }
    }
}

extension BehaviorSeverity {
    var color: Color {
        switch self {
        case .info:     return .gwTextSecondary
        case .warning:  return .gwWarning
        case .critical: return .gwCritical
        }
    }

    var icon: String {
        switch self {
        case .info:     return "info.circle"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.shield.fill"
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Typography
// ──────────────────────────────────────────────────────────────────────────────

extension Font {
    static let gwTitle    = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let gwHeadline = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let gwBody     = Font.system(size: 13, weight: .regular,  design: .default)
    static let gwCaption  = Font.system(size: 11, weight: .regular,  design: .monospaced)
    static let gwMono     = Font.system(size: 12, weight: .medium,   design: .monospaced)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Spacing & Radius
// ──────────────────────────────────────────────────────────────────────────────

enum GWSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

enum GWRadius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let pill: CGFloat = 999
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Animations
// ──────────────────────────────────────────────────────────────────────────────

extension Animation {
    static let gwSpring     = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let gwFast       = Animation.easeOut(duration: 0.15)
    static let gwGlowPulse  = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
}
