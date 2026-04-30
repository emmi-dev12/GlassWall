// MARK: - GlassWall Design Tokens v2
// Refined palette: deep navy backgrounds, teal accent, clear semantic colours.
// Prioritises legibility and calm over aggressive neon.

import SwiftUI

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Colour Palette
// ──────────────────────────────────────────────────────────────────────────────

extension Color {

    // ── App backgrounds ───────────────────────────────────────────────────────
    static let gwBgBase     = Color(hex: "#08101E")   // deepest background
    static let gwBgElevated = Color(hex: "#0D1828")   // slightly raised surfaces

    // ── Brand / accent ────────────────────────────────────────────────────────
    static let gwTeal       = Color(hex: "#2DD4BF")   // primary teal accent
    static let gwBlue       = Color(hex: "#38BDF8")   // sky blue secondary
    static let gwIndigo     = Color(hex: "#818CF8")   // indigo for variety

    // ── Semantic ──────────────────────────────────────────────────────────────
    static let gwAllow      = Color(hex: "#10B981")   // emerald — allowed
    static let gwBlock      = Color(hex: "#EF4444")   // red — blocked
    static let gwPending    = Color(hex: "#F59E0B")   // amber — waiting
    static let gwWarning    = Color(hex: "#F97316")   // orange — warning
    static let gwCritical   = Color(hex: "#EF4444")   // same as block (high severity)
    static let gwInfo       = Color(hex: "#60A5FA")   // blue — informational

    // ── Panic mode ────────────────────────────────────────────────────────────
    static let gwPanic      = Color(hex: "#F43F5E")   // rose
    static let gwPanicBg    = Color(hex: "#F43F5E").opacity(0.10)

    // ── Glass surfaces ────────────────────────────────────────────────────────
    static let gwSurface    = Color.white.opacity(0.055)
    static let gwSurfaceHover = Color.white.opacity(0.085)
    static let gwBorder     = Color.white.opacity(0.10)
    static let gwBorderFocus = Color(hex: "#2DD4BF").opacity(0.50)

    // ── Text ──────────────────────────────────────────────────────────────────
    static let gwText1      = Color.white.opacity(0.94)   // primary
    static let gwText2      = Color.white.opacity(0.58)   // secondary
    static let gwText3      = Color.white.opacity(0.32)   // tertiary / placeholder
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Semantic Colour Mappings
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
    var icon: String {
        switch self {
        case .allow:   return "checkmark.circle.fill"
        case .block:   return "xmark.circle.fill"
        case .pending: return "clock.fill"
        }
    }
}

extension RuleKind {
    var color: Color {
        switch self {
        case .whitelist:  return .gwAllow
        case .incognito:  return .gwTeal
        case .jail:       return .gwWarning
        case .blacklist:  return .gwBlock
        }
    }
    // User-friendly labels (no technical jargon)
    var label: String {
        switch self {
        case .whitelist:  return "Always Allow"
        case .incognito:  return "Allow 1 Hour"
        case .jail:       return "Block Session"
        case .blacklist:  return "Always Block"
        }
    }
    var shortLabel: String {
        switch self {
        case .whitelist:  return "Trusted"
        case .incognito:  return "Timed"
        case .jail:       return "Session Block"
        case .blacklist:  return "Blocked"
        }
    }
    var icon: String {
        switch self {
        case .whitelist:  return "checkmark.shield.fill"
        case .incognito:  return "timer"
        case .jail:       return "lock.fill"
        case .blacklist:  return "nosign"
        }
    }
    var description: String {
        switch self {
        case .whitelist:  return "Always let this app connect here"
        case .incognito:  return "Allow for the next 60 minutes, then ask again"
        case .jail:       return "Block until you restart or change this rule"
        case .blacklist:  return "Never let this app connect anywhere"
        }
    }
}

extension BehaviorSeverity {
    var color: Color {
        switch self {
        case .info:     return .gwInfo
        case .warning:  return .gwWarning
        case .critical: return .gwCritical
        }
    }
    var icon: String {
        switch self {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.shield.fill"
        }
    }
    var label: String {
        switch self {
        case .info:     return "Info"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Typography
// ──────────────────────────────────────────────────────────────────────────────

extension Font {
    static let gwLargeTitle  = Font.system(size: 26, weight: .bold,     design: .rounded)
    static let gwTitle       = Font.system(size: 19, weight: .semibold,  design: .rounded)
    static let gwTitle2      = Font.system(size: 16, weight: .semibold,  design: .rounded)
    static let gwHeadline    = Font.system(size: 14, weight: .semibold,  design: .default)
    static let gwBody        = Font.system(size: 13, weight: .regular,   design: .default)
    static let gwBodyMed     = Font.system(size: 13, weight: .medium,    design: .default)
    static let gwCaption     = Font.system(size: 11, weight: .regular,   design: .default)
    static let gwCaptionMed  = Font.system(size: 11, weight: .medium,    design: .default)
    static let gwMono        = Font.system(size: 12, weight: .regular,   design: .monospaced)
    static let gwMonoSmall   = Font.system(size: 11, weight: .regular,   design: .monospaced)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Spacing & Corner Radii
// ──────────────────────────────────────────────────────────────────────────────

enum GWS {   // spacing
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum GWR {   // corner radius
    static let xs:  CGFloat = 6
    static let sm:  CGFloat = 10
    static let md:  CGFloat = 14
    static let lg:  CGFloat = 18
    static let xl:  CGFloat = 22
    static let pill: CGFloat = 999
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Animations
// ──────────────────────────────────────────────────────────────────────────────

extension Animation {
    static let gwSpring    = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let gwSnappy    = Animation.spring(response: 0.28, dampingFraction: 0.85)
    static let gwFade      = Animation.easeOut(duration: 0.18)
    static let gwSlow      = Animation.easeInOut(duration: 0.45)
    static let gwPulse     = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    static let gwBreath    = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: Shadow Styles
// ──────────────────────────────────────────────────────────────────────────────

extension View {
    func gwCardShadow() -> some View {
        self.shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
    func gwGlowShadow(color: Color, radius: CGFloat = 10) -> some View {
        self.shadow(color: color.opacity(0.40), radius: radius, x: 0, y: 0)
    }
    func gwSubtleShadow() -> some View {
        self.shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 2)
    }
}
