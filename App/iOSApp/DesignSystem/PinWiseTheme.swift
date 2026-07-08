import SwiftUI
import UIKit

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

    /// A color that resolves to `light` or `dark` (hex) based on the active interface style,
    /// so a single token adapts across light and dark mode.
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            UIColor(hexValue: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hexValue: UInt) {
        self.init(
            red: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// User-selectable appearance, stored via `@AppStorage("appearance")`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    /// nil = follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
    static func from(_ raw: String) -> AppearanceMode { AppearanceMode(rawValue: raw) ?? .dark }
}

/// Forces the host window to a single interface style so BOTH SwiftUI-native views and the
/// dynamic-`UIColor`-backed `BrandColor` tokens resolve to the SAME appearance. Without this,
/// `.preferredColorScheme` (which drives SwiftUI defaults) can disagree with the trait the
/// dynamic tokens read — leaving light-colored native text on light token backgrounds
/// (invisible) across every screen.
struct AppearanceApplier: UIViewRepresentable {
    let mode: AppearanceMode

    func makeUIView(context: Context) -> StyleView {
        let v = StyleView()
        v.isHidden = true
        v.isUserInteractionEnabled = false
        v.style = mode.uiStyle
        return v
    }

    func updateUIView(_ uiView: StyleView, context: Context) {
        uiView.style = mode.uiStyle
        uiView.apply()
    }

    /// Applies the style both when it first attaches to a window (cold launch) and on updates.
    final class StyleView: UIView {
        var style: UIUserInterfaceStyle = .unspecified
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }
        func apply() { window?.overrideUserInterfaceStyle = style }
    }
}

// Measured WCAG contrast ratios (audited 2026-07, small-text target 4.5:1):
//   white/background 20.1 · white/surface 18.7 · textSecondary/dark 7.9 · accentText/dark 7.6
//   white-on-accent 7.6 · accent-on-white 7.6 · light success-on-white 5.0 · light
//   warning-on-white 5.4 · danger 4.8 (chip) · data-on-white 4.95 · data-on-dark-surface 10.0
// Badge ink: every semantic fill holds ≥4.5:1 with `onBadge` in BOTH modes — dark fills +
// near-black ink 6.2–12.1, light fills + white ink 4.8–5.4. The previous light success
// (0x0E9E63 → 3.45) and warning (0xB26A00 → 4.24) failed 4.5:1 as small text on white;
// both are darkened (0x0C8052 / 0x9A5B00) so the light set genuinely holds ≥4.5:1 now.
// The deep `accent` as text on dark is only 2.6:1 — so text/links on dark use `accentText`.
// Each token adapts per interface style: dark keeps the Enhanced-style deep blue-black; light
// is a clean blue-biased near-white. Light values are chosen to hold small-text contrast ≥4.5:1
// (deep accent, darker semantic hues); dark values are the previously audited set.
enum BrandColor {
    // 60% — dominant neutral. Dark: deep blue-black. Light: blue-white.
    static let background = Color(light: 0xF4F6FC, dark: 0x04050B)
    // 30% — secondary surfaces / cards.
    static let surface = Color(light: 0xFFFFFF, dark: 0x0F1120)
    static let surfaceElevated = Color(light: 0xEEF1F9, dark: 0x171A2C)
    static let stroke = Color(light: 0xDCE0EC, dark: 0x272B45)     // hairline

    // Deep blue used in hero gradients. Light mode uses a soft periwinkle so the mesh stays subtle.
    static let deepBlue = Color(light: 0x8FA0FF, dark: 0x0C1A66)

    // 10% — functional accent: deep royal-electric blue (trust). Same in both modes → for FILLS.
    static let accent = Color(hex: 0x2536E6)
    static let onAccent = Color(hex: 0xFFFFFF)
    // Accent TEXT/ICONS: the deep accent reads well on light; on dark it needs the lighter blue.
    static let accentText = Color(light: 0x2536E6, dark: 0x8A97FF)
    /// Badge ink — text on solid semantic badge fills: white on the deep light-mode fills,
    /// near-black on the bright dark-mode fills (the Spotify black-on-green register).
    static let onBadge = Color(light: 0xFFFFFF, dark: 0x04050B)

    // Semantic (separate from the accent). Light variants darkened for contrast on white.
    static let success = Color(light: 0x0C8052, dark: 0x18E39A)   // green — progress / health
    static let warning = Color(light: 0x9A5B00, dark: 0xFFB020)   // amber — attention
    static let danger  = Color(light: 0xD92D2D, dark: 0xFF4D4D)   // red — urgency / destructive
    static let mint = success                                     // alias kept for call sites

    // DOMAIN hue — objective health data (Labs & metrics tile + future data accents). The
    // Oura-readiness teal family. A domain color, NOT a status color: it never means
    // "ok/attention/stop" and never appears in badges. Audited (2026-07): light 0x0E7C86
    // on white 4.95:1 (text-safe); dark 0x4FD1C5 on surface 10.0:1. As icon-on-own-tint
    // (0.16 ground): 3.98:1 light / 7.40:1 dark — ≥3:1 graphics floor in both modes.
    static let data = Color(light: 0x0E7C86, dark: 0x4FD1C5)

    // Text
    static let textPrimary = Color(light: 0x0B0D16, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x5A6478, dark: 0x9AA3B8)
}

/// Type ramp — system font (SF), monospaced figures. `.black` is reserved for the number
/// ramp (the number is the headline); titles and chrome top out at `.bold`.
enum Typo {
    /// Screen/tab titles — bold, sentence case rather than all-caps.
    static let screenTitle = Font.system(size: 34, weight: .bold)
    static let title = Font.system(size: 28, weight: .bold)
    static let headline = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 13, weight: .medium)
    // Rounded design for vital numbers — the Apple Health/Fitness signature; reads as a
    // considered product choice rather than default system type.
    static let numberXL = Font.system(size: 40, weight: .black, design: .rounded).monospacedDigit()
    static let numberLG = Font.system(size: 30, weight: .black, design: .rounded).monospacedDigit()
    static let numberMD = Font.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    // Instrument data voice — uppercase micro-labels over tabular values (Whoop/Strava/Oura).
    static let microLabel = Font.system(size: 11, weight: .semibold)
    static let microTracking: CGFloat = 1.1          // pair with .tracking() at call sites
    /// 3-up stat-grid value register (Strava: 11pt caps label over 17/700 tabular value).
    static let statValue = Font.system(size: 17, weight: .bold, design: .rounded).monospacedDigit()
    /// "The number is the headline" hero figure (Home activity hero).
    static let numberHero = Font.system(size: 48, weight: .black, design: .rounded).monospacedDigit()
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48   // hero breathing room — between Home's hero block and reference sections
}

enum Radius {
    static let card: CGFloat = 18
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}

/// Named motion — one vocabulary for the whole app. Every USE must be gated on
/// `@Environment(\.accessibilityReduceMotion)` (fall back to opacity-only or nil).
enum Motion {
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.7)      // existing PressableStyle value
    static let emphasis = Animation.spring(response: 0.45, dampingFraction: 0.8)  // card/sheet arrivals
    static let reveal = Animation.easeOut(duration: 0.9)                          // ring sweep + count-up (Oura ~900ms)
    static let entrance = Animation.easeOut(duration: 0.35)                       // staggered list entrances
    static let drawer = Animation.spring(response: 0.38, dampingFraction: 0.9)    // existing drawer value
    static let stagger: Double = 0.04                                             // 40ms/row (Oura)
}

// Glow rules: a colored glow means "live/active" — never gray, never decorative. The only
// sanctioned glows are the PrimaryButton accent, the tab bar's Log chip, and StatusDot
// (its own status color, radius 6). Nothing else glows.
// Neutral-black STRUCTURAL shadows are not glows: the two drawer shadows (0.45/24) and
// Elevation.chrome under the floating tab bar.

/// Scheme-aware drop shadow — the design system's only shadow recipe. On dark, elevation
/// comes from surface lightness + the hairline stroke, so only `.hero` and `.chrome` cast
/// shadows (large/soft/very-dark — the Spotify rule); `.card` shadows exist in light mode
/// only (small/faint — the Apple Music rule). `.hero` marks the one headline surface on a
/// screen, `.chrome` floating chrome over live content (the tab bar — one register quieter
/// than the transient drawers), `.card` regular content cards, `.none` flat rows.
struct Elevation: ViewModifier {
    enum Level { case hero, chrome, card, none }
    let level: Level
    @Environment(\.colorScheme) private var scheme

    // (opacity, radius, y) per level — dark: hero 0.50/28/14 · chrome 0.35/18/8 · card 0/0/0
    // (dark elevation is surface lightness + hairline); light: hero 0.10/20/10 ·
    // chrome 0.10/14/6 · card 0.08/16/8; none draws no shadow.
    private var values: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch (level, scheme == .dark) {
        case (.hero, true): return (0.50, 28, 14)
        case (.chrome, true): return (0.35, 18, 8)
        case (.card, true): return (0, 0, 0)
        case (.hero, false): return (0.10, 20, 10)
        case (.chrome, false): return (0.10, 14, 6)
        case (.card, false): return (0.08, 16, 8)
        case (.none, _): return (0, 0, 0)
        }
    }

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(values.opacity), radius: values.radius, y: values.y)
    }
}

extension View {
    /// Applies the design-system shadow for an elevation level (scheme-aware; `.none` is flat).
    func elevation(_ level: Elevation.Level) -> some View {
        modifier(Elevation(level: level))
    }
}

/// Ambient blue mesh behind hero areas (iOS 18). Native — no image assets. Scheme-aware:
/// deep saturated blue on dark; a soft blue wash on light so dark titles stay readable on top.
struct HeroMesh: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // On light, replace the deep `accent` with a pale blue so near-black titles keep contrast.
        let deep = BrandColor.deepBlue               // adaptive: navy on dark, periwinkle on light
        let glow = scheme == .dark ? BrandColor.accent : Color(hex: 0xBAC6FF)
        let base = BrandColor.background
        return MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2<Float>(0, 0),   SIMD2<Float>(0.5, 0),   SIMD2<Float>(1, 0),
                SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1, 0.5),
                SIMD2<Float>(0, 1),   SIMD2<Float>(0.5, 1),   SIMD2<Float>(1, 1)
            ],
            colors: [
                deep,             glow,          deep,
                glow.opacity(0.7), deep,         glow.opacity(0.5),
                base,             base,          base
            ]
        )
    }
}

extension View {
    /// Bottom clearance so scrollable content always clears the floating tab bar (an overlay
    /// that reserves no layout space). 90 = bar content height 65 (top pad 12 + iconRow 30 +
    /// spacing 3 + label ≈12 + bottom pad 8) + 8 bottom float + 17 breathing gap. No-op on
    /// non-scrolling screens.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 90, for: .scrollContent)
    }

    /// Flat brand canvas (used by utility/detail screens).
    func screenBackground() -> some View {
        tabBarClearance()
            .background(BrandColor.background.ignoresSafeArea())
    }

    /// Flat brand canvas for tab-level screens (identical to `screenBackground()`; the name
    /// is kept for its call sites). The ambient mesh survives only on the four pre-auth
    /// covers that use `HeroMesh()` directly.
    func heroScreen() -> some View {
        screenBackground()
    }
}

/// Plain button style that adds a springy press-scale — tactile feedback used across tappable
/// cards, so the app feels responsive rather than static.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
