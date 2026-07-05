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
//   white-on-accent 7.6 · accent-on-white 7.6 · success 8.1 · warning 7.6 · danger 4.8 (chip)
// The deep `accent` as text on dark is only 2.6:1 — so text/links on dark use `accentText`.
// Each token adapts per interface style: dark keeps the Enhanced-style deep blue-black; light
// is a clean blue-biased near-white. Light values are chosen to hold small-text contrast ≥4.5:1
// (deep accent, darker semantic hues); dark values are the previously audited set.
enum BrandColor {
    // 60% — dominant neutral. Dark: deep blue-black so the edge glow pops. Light: blue-white.
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

    // Semantic (separate from the accent). Light variants darkened for contrast on white.
    static let success = Color(light: 0x0E9E63, dark: 0x18E39A)   // green — progress / health
    static let warning = Color(light: 0xB26A00, dark: 0xFFB020)   // amber — attention
    static let danger  = Color(light: 0xD92D2D, dark: 0xFF4D4D)   // red — urgency / destructive
    static let mint = success                                     // alias kept for call sites

    // Text
    static let textPrimary = Color(light: 0x0B0D16, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x5A6478, dark: 0x9AA3B8)
}

/// Type ramp — system font (SF), heavy weights, uppercase display, monospaced figures.
enum Typo {
    static let displayXL = Font.system(size: 44, weight: .black)
    static let displayL = Font.system(size: 34, weight: .black)
    /// Screen/tab titles — heavy weight (as before), but sentence case rather than all-caps.
    static let screenTitle = Font.system(size: 34, weight: .black)
    static let title = Font.system(size: 28, weight: .bold)
    static let headline = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 13, weight: .medium)
    // Rounded design for vital numbers — the Apple Health/Fitness signature; reads as a
    // considered product choice rather than default system type.
    static let numberXL = Font.system(size: 40, weight: .black, design: .rounded).monospacedDigit()
    static let numberLG = Font.system(size: 30, weight: .black, design: .rounded).monospacedDigit()
    static let numberMD = Font.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
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
    /// that reserves no layout space). No-op on non-scrolling screens.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 90, for: .scrollContent)
    }

    /// Flat brand canvas (used by utility/detail screens).
    func screenBackground() -> some View {
        tabBarClearance()
            .background(BrandColor.background.ignoresSafeArea())
    }

    /// A soft accent glow hugging the screen edges — ambient, non-interactive. Mirrors the
    /// glow around the device previews. Apply once at the app root.
    // Uses the LIGHTER accent (`accentText`) — the deep accent on near-black is ~2.6:1 and
    // reads as invisible once blurred. A dedicated bright glow tone shows on the dark edges.
    func edgeGlow() -> some View {
        overlay { EdgeGlowOverlay() }
    }

    /// Subtle film-grain texture across the screen — a premium, tactile cue that breaks up
    /// flat fills. Non-interactive; applied once at the app root.
    func grain(_ opacity: Double = 0.035) -> some View {
        overlay {
            Grain.image
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.softLight)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// Canvas with an ambient deep-blue mesh at the top, faded into the background.
    func heroScreen() -> some View {
        tabBarClearance()
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

/// The ambient accent glow hugging the screen edges. Scheme-aware: bold on the dark canvas,
/// softened on light so the blue halo reads as a highlight rather than a heavy border.
private struct EdgeGlowOverlay: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 52, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [BrandColor.accentText, BrandColor.accentText.opacity(0.45), BrandColor.accentText.opacity(0.9)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 4
            )
            .blur(radius: 11)
            .opacity(scheme == .dark ? 0.95 : 0.5)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// A cached, deterministic monochrome noise tile for the film-grain overlay. Built once with an
/// xorshift PRNG (no Date/random dependency, so it's stable across launches).
enum Grain {
    static let image: Image = {
        let size = 128
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        var seed: UInt64 = 88172645463325252
        for i in 0..<(size * size) {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let v = UInt8(truncatingIfNeeded: seed)
            let o = i * 4
            pixels[o] = v; pixels[o + 1] = v; pixels[o + 2] = v; pixels[o + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else {
            return Image(systemName: "circle.fill")
        }
        return Image(decorative: cg, scale: 1, orientation: .up)
    }()
}

/// Plain button style that adds a springy press-scale — tactile feedback used across tappable
/// cards, so the app feels responsive rather than static.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
