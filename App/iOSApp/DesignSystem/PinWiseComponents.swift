import SwiftUI
import PeptideKit

// Reusable building blocks. Depth is a flat surface-step system: background → surface →
// surfaceElevated lightness steps bounded by hairline strokes — not gradient fills. The one
// sanctioned gradient is the hero card; the one accent glow is the primary CTA.

/// A rounded surface card: flat fill, sober hairline rim, elevation by register.
/// `.hero` is the app's ONE gradient surface (deep-blue diagonal wash) and carries the one
/// dark shadow; `.standard` (default) and `.flat` are flat surfaces separated from the
/// ground by the same hairline — `.standard` for regular content cards, `.flat` for dense
/// reference rows.
struct Card<Content: View>: View {
    enum Style { case hero, standard, flat }

    private let style: Style
    private let padding: CGFloat
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(style: Style = .standard, padding: CGFloat = Space.lg, @ViewBuilder content: () -> Content) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    // Every style resolves to the SAME LinearGradient type: `.standard` and `.flat` use
    // degenerate [surface, surface] gradients that rasterize as flat fills. Keeping the fill
    // type uniform means style values never change the card's structural identity — only
    // `.hero` carries a real gradient.
    private var fillGradient: LinearGradient {
        switch style {
        case .hero:
            // 0.65 only on dark, where the flat canvas would otherwise swallow the wash.
            // Light stays at 0.5: the periwinkle ground at 0.65 drops the hero's
            // textSecondary micro-labels below the 4.5:1 small-text floor the theme promises.
            return LinearGradient(
                colors: [BrandColor.deepBlue.opacity(scheme == .dark ? 0.65 : 0.5), BrandColor.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .standard:
            return LinearGradient(
                colors: [BrandColor.surface, BrandColor.surface],
                startPoint: .top, endPoint: .bottom
            )
        case .flat:
            return LinearGradient(
                colors: [BrandColor.surface, BrandColor.surface],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // Rim: every register wears the same sober flat hairline. The degenerate 3× stroke
    // gradient keeps the strokeBorder's LinearGradient type, so the rim never changes the
    // card's structural identity either.
    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [BrandColor.stroke, BrandColor.stroke, BrandColor.stroke],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var elevationLevel: Elevation.Level {
        switch style {
        case .hero: return .hero
        case .standard: return .card
        case .flat: return .none
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(fillGradient, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(rimGradient, lineWidth: 1)
            )
            .elevation(elevationLevel)
    }
}

/// Primary call-to-action — flat accent fill, white label, the app's one accent glow.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title.uppercased()).fontWeight(.bold).tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.lg)
        }
        .background(BrandColor.accent, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .foregroundStyle(BrandColor.onAccent)
        .shadow(color: BrandColor.accent.opacity(0.35), radius: 12, y: 5)
    }
}

/// Secondary CTA — white fill, deep-blue label (legible: dark text on light).
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title.uppercased()).fontWeight(.bold).tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.lg)
        }
        .background(BrandColor.textPrimary, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .foregroundStyle(BrandColor.accent)
    }
}

/// The uppercase tracked micro-label of the instrument "data voice" (Whoop/Strava/Oura
/// register). Use it wherever a small caps caption sits over or beside a stat value — the
/// single `@ScaledMetric` adoption point, so the 11pt caps grow with Dynamic Type.
struct MicroLabel: View {
    private let text: String
    private let color: Color
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 11

    init(_ text: String, color: Color = BrandColor.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(Typo.microTracking)
            .foregroundStyle(color)
    }
}

/// A labeled figure — calculator outputs and dashboard stats. Emphasis uses the lighter
/// `accentText` blue so it stays legible on the dark ground (WCAG). `compact` drops the
/// value to the 17pt stat-grid register (`Typo.statValue`) for 3-up stat strips (Strava);
/// `emphasized` still overrides the value color to `accentText` in either size.
struct StatTile: View {
    let label: String
    let value: String
    var emphasized: Bool = false
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            MicroLabel(label)
            Text(value)
                .font(compact ? Typo.statValue : (emphasized ? Typo.numberLG : Typo.numberMD))
                .foregroundStyle(emphasized ? BrandColor.accentText : BrandColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A guided input: a plain-language question, an optional one-line hint about what to enter
/// and why, then the control. Keeps the calculators understandable without prior knowledge.
struct FieldRow<Content: View>: View {
    let title: String
    let hint: String?
    let content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            content.padding(.top, 2)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Typo.caption)
            .fontWeight(.semibold)
            .tracking(1.2)
            .foregroundStyle(BrandColor.textSecondary)
    }
}

/// Small solid chip for tags / categories / savings — a premium badge, no translucency.
/// Pass the semantic tokens (success/warning/danger/accentText/textSecondary): they are
/// scheme-adaptive fills (bright on dark, deep on light), and the `BrandColor.onBadge` ink
/// resolves scheme-correct against them automatically.
struct TagChip: View {
    let text: String
    var color: Color = BrandColor.mint
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: Space.xs) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(color, in: Capsule())
        .foregroundStyle(BrandColor.onBadge)
    }
}

/// Frosted category badge for imagery (the Fitness+ register) — the ONE sanctioned on-image
/// badge, for photographs only, where real pixels pass beneath the blur. The black 0.6 tint
/// in front of the material bounds white text at >=4.5:1 even over a pure-white photo region
/// through the LIGHT-mode material (0.4 measured ~2.9-3.2:1 there — the light plate passes
/// white straight through). Never use on flat surfaces: material over a solid fill is fake glass.
struct FrostedTagChip: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.6), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// An 8pt dot whose color IS the information (success = active, warning = due, textSecondary
/// = paused). The same-color glow marks "live" states per the glow rules — pass
/// `glows: false` for dormant ones.
struct StatusDot: View {
    let color: Color
    var glows: Bool = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: glows ? color.opacity(0.5) : .clear, radius: 6)
    }
}

/// A selectable filter/option chip — the one recipe for chip groups (Log protocol + site
/// pickers, builder weekdays, News filters). Compact visual box, full 44pt hit target.
/// Haptics are deliberately NOT here: attach one `.sensoryFeedback(.selection, trigger:)`
/// per chip GROUP at the container (per-chip would double-fire on reselection).
struct SelectableChip: View {
    enum ChipShape { case capsule, rounded(CGFloat) }

    let title: String
    let isSelected: Bool
    var shape: ChipShape = .capsule
    var fillWidth: Bool = false
    let action: () -> Void

    private var cornerRadius: CGFloat {
        switch shape {
        case .capsule: return Radius.pill
        case .rounded(let radius): return radius
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? BrandColor.onAccent : BrandColor.textPrimary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .background(
                    isSelected ? BrandColor.accent : BrandColor.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? Color.clear : BrandColor.stroke, lineWidth: 1)
                )
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The persistent, non-alarming disclaimer strip used across dosing/calculator surfaces.
struct DisclaimerBanner: View {
    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: systemImage).foregroundStyle(BrandColor.textSecondary)
            Text(text).font(.footnote).foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// A safety advisory row colored by severity — surfaces `CompoundedDoseSafety`.
struct AdvisoryRow: View {
    let advisory: CompoundedDoseSafety.Advisory

    private var color: Color {
        switch advisory.severity {
        case .block: return BrandColor.danger
        case .warning: return BrandColor.warning
        case .info: return BrandColor.textSecondary
        }
    }
    private var icon: String {
        switch advisory.severity {
        case .block: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icon).foregroundStyle(color)
            Text(advisory.message).font(.footnote).foregroundStyle(BrandColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Evidence-tier badge (A/B/C/D) — solid semantic fill per tier, `BrandColor.onBadge` ink.
struct EvidenceBadge: View {
    let tier: EvidenceTier
    private var color: Color {
        switch tier {
        case .fdaApproved: return BrandColor.mint
        case .humanTrialsUnapproved: return BrandColor.accentText
        case .preclinicalOrFailed: return BrandColor.warning
        case .precursorOffLabel: return BrandColor.danger
        }
    }
    var body: some View {
        Text("TIER \(tier.letter)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(color, in: Capsule())
            .foregroundStyle(BrandColor.onBadge)
    }
}

/// An Apple-health-style circular adherence ring with an Oura-style coupled reveal: one
/// `Motion.reveal` drives the arc sweep and the rolling center count-up so they land
/// together (~900ms). The hue IS the read — amber behind, blue on pace, green ahead — over
/// an own-color track. Accessible (label + value); Reduce Motion skips the sweep entirely.
struct AdherenceRing: View {
    let fraction: Double
    var size: CGFloat = 88

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    private var clamped: Double { max(0, min(1, fraction)) }
    private var pct: Int { Int((progress * 100).rounded()) }

    // Value-driven single hue: the color carries the adherence verdict, not decoration.
    private var ringColor: Color {
        switch clamped {
        case ..<0.5: return BrandColor.warning
        case ..<0.8: return BrandColor.accentText
        default: return BrandColor.success
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(ringColor.opacity(0.22), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.0001, progress))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(pct)%")
                    .font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: progress))
                    .foregroundStyle(BrandColor.textPrimary)
                // Domain label, not a verdict — the ring hue carries the verdict (amber
                // behind / blue on pace / green ahead), so a static "ON TRACK" would lie.
                Text("ADHERENCE")
                    .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .frame(width: size, height: size)
        // Explicit withAnimation drives ONLY the trim + count-up — a value-scoped .animation
        // here also animated the ring's initial layout position, making it fly in from
        // offscreen. Under Reduce Motion the value is set directly, no sweep.
        .onAppear {
            if reduceMotion {
                progress = clamped
            } else {
                progress = 0
                withAnimation(Motion.reveal) { progress = clamped }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adherence")
        .accessibilityValue("\(pct) percent of scheduled doses taken over the last 14 days")
    }
}

/// One-shot staggered entrance for list/section arrivals: fade + 12pt rise, delayed by
/// `index` × `Motion.stagger`. Apply from a ForEach (or ordered siblings) as `.entrance(i)`.
/// Reduce Motion collapses it to a quick opacity-only fade with no offset or stagger.
struct Entrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                let anim = reduceMotion
                    ? Animation.easeOut(duration: 0.2)
                    : Motion.entrance.delay(Double(index) * Motion.stagger)
                withAnimation(anim) { shown = true }
            }
    }
}

extension View {
    /// Staggered entrance reveal — `index` is the view's position in its arriving group.
    func entrance(_ index: Int) -> some View {
        modifier(Entrance(index: index))
    }
}

extension String {
    /// Parses a user-typed decimal, accepting both "." and "," — the decimal pad inserts the
    /// locale's separator, and `Double.init` only understands the dot.
    var decimalValue: Double? { Double(replacingOccurrences(of: ",", with: ".")) }
}

/// Trailing-window selector shared by the trend charts (Labs & Symptoms). `.all` = full history
/// (nil cutoff). Superset of both former view-local copies; each view iterates only the options
/// it offers — Symptoms omits `.all`, Labs includes it — so this is a pure definition-dedup, not
/// a behavior change.
enum ChartRange: String, CaseIterable, Identifiable {
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
    case all = "All"
    var id: String { rawValue }
    /// Trailing-window length in days; nil = no cutoff (full history).
    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .all: return nil
        }
    }
    /// Section-header phrasing (Symptoms); "All time" for the full-history option.
    var title: String { days.map { "Last \($0) days" } ?? "All time" }
}

/// Menu-style compound chooser with a single-line, truncating label. A bare `.menu` Picker
/// lets long names ("GHK-Cu (injectable)") overflow into neighboring fields — this never does.
struct CompoundMenu: View {
    @Binding var selection: Compound
    let options: [Compound]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { c in
                Button(c.name) { selection = c }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(selection.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(BrandColor.accentText)
        }
    }
}

extension View {
    /// Styles a text/number field as a themed input (elevated surface, hairline border).
    func pinwiseField() -> some View {
        padding(.horizontal, Space.md)
            .padding(.vertical, Space.md - 2)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(BrandColor.stroke, lineWidth: 1)
            )
    }
}

/// A feed image area: an `AsyncImage` layered over a branded gradient that shows while
/// loading, on failure, or when no image URL is provided. Caller sizes and clips it.
struct FeedImage: View {
    let urlString: String?
    var tint: Color = BrandColor.accent

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.55), BrandColor.deepBlue, BrandColor.background],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
    }
}
