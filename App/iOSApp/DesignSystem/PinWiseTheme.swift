import SwiftUI

// PinWise design system. Color strategy (founder-directed):
//  • Deep blue = brand + trust + primary CTA (the Enhanced-style deep royal blue).
//  • 60-30-10: 60% blue-biased near-black background, 30% elevated surfaces + muted text,
//    10% the accent on interactive elements only.
//  • Saturation hierarchy: saturated blue for interactive fills; desaturated blue-grays elsewhere.
//  • Semantic colors (green=success/progress, red=urgency/destructive, amber=attention) are
//    SEPARATE from the accent and signal meaning, not brand.
//  • WCAG ≥ 4.5:1: white-on-accent fills pass (~8:1); the deep blue fails as text on black
//    (~2.5:1), so `accentText` (a lighter blue, ~7:1) is used for links/emphasis on dark.

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// Measured WCAG contrast ratios (audited 2026-07, small-text target 4.5:1):
//   white/background 20.1 · white/surface 18.7 · textSecondary/dark 7.9 · accentText/dark 7.6
//   white-on-accent 7.6 · accent-on-white 7.6 · success 8.1 · warning 7.6 · danger 4.8 (chip)
// The deep `accent` as text on dark is only 2.6:1 — so text/links on dark use `accentText`.
enum BrandColor {
    // 60% — dominant neutral: a deliberately blue-biased near-black (not gray).
    static let background = Color(hex: 0x06070E)
    // 30% — secondary surfaces / cards.
    static let surface = Color(hex: 0x0F1120)
    static let surfaceElevated = Color(hex: 0x171A2C)
    static let stroke = Color(hex: 0x272B45)          // blue-tinted hairline

    // Deep blue used in hero gradients — evokes the Enhanced imagery.
    static let deepBlue = Color(hex: 0x0C1A66)

    // 10% — functional accent: deep royal-electric blue (trust). Saturated → for FILLS.
    static let accent = Color(hex: 0x2536E6)
    static let onAccent = Color(hex: 0xFFFFFF)
    // Lighter blue for accent TEXT/ICONS on dark grounds (WCAG-safe, ~7:1).
    static let accentText = Color(hex: 0x8A97FF)

    // Semantic (separate from the accent).
    static let success = Color(hex: 0x18E39A)   // green — progress / health / completed
    static let warning = Color(hex: 0xFFB020)   // amber — attention, used sparingly
    static let danger  = Color(hex: 0xFF4D4D)   // red — urgency / destructive / safety block
    static let mint = success                    // alias kept for existing call sites

    // Text
    static let textPrimary = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0x9AA3B8) // low-saturation blue-gray
}

/// Type ramp — system font (SF), heavy weights, uppercase display, monospaced figures.
enum Typo {
    static let displayXL = Font.system(size: 44, weight: .black)
    static let displayL = Font.system(size: 34, weight: .black)
    static let title = Font.system(size: 28, weight: .bold)
    static let headline = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 13, weight: .medium)
    static let numberXL = Font.system(size: 40, weight: .black).monospacedDigit()
    static let numberLG = Font.system(size: 30, weight: .black).monospacedDigit()
    static let numberMD = Font.system(size: 22, weight: .bold).monospacedDigit()
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let card: CGFloat = 18
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}

/// Ambient deep-blue mesh used behind hero areas (iOS 18). Native — no image assets.
struct HeroMesh: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2<Float>(0, 0),   SIMD2<Float>(0.5, 0),   SIMD2<Float>(1, 0),
                SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1, 0.5),
                SIMD2<Float>(0, 1),   SIMD2<Float>(0.5, 1),   SIMD2<Float>(1, 1)
            ],
            colors: [
                BrandColor.deepBlue,            BrandColor.accent,     BrandColor.deepBlue,
                BrandColor.accent.opacity(0.7), BrandColor.deepBlue,   BrandColor.accent.opacity(0.5),
                BrandColor.background,          BrandColor.background, BrandColor.background
            ]
        )
    }
}

extension View {
    /// Flat brand canvas (used by utility screens).
    func screenBackground() -> some View {
        background(BrandColor.background.ignoresSafeArea())
    }

    /// A soft accent glow hugging the screen edges — ambient, non-interactive. Mirrors the
    /// glow around the device previews. Apply once at the app root.
    // Uses the LIGHTER accent (`accentText`) — the deep accent on near-black is ~2.6:1 and
    // reads as invisible once blurred. A dedicated bright glow tone shows on the dark edges.
    func edgeGlow(_ color: Color = BrandColor.accentText, strength: Double = 0.85) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [color, color.opacity(0.5), color.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 3
                )
                .blur(radius: 9)
                .opacity(strength)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// Canvas with an ambient deep-blue mesh at the top, faded into the background.
    func heroScreen() -> some View {
        self
            .background(alignment: .top) {
                HeroMesh()
                    .frame(height: 340)
                    .mask {
                        LinearGradient(
                            colors: [.black, .black.opacity(0.2), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .top)
            }
            .background(BrandColor.background.ignoresSafeArea())
    }
}
