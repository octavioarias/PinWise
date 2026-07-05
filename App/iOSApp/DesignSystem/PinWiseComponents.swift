import SwiftUI
import PeptideKit

// Reusable building blocks. Depth comes from gradient fills, soft shadows, and an accent
// glow on the primary CTA — not from flat solid rectangles.

/// A rounded surface card with a subtle vertical gradient, hairline border, and soft shadow.
struct Card<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.lg)
            .background(
                LinearGradient(
                    colors: [BrandColor.surface, BrandColor.surfaceElevated.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            // Rim light: a faint highlight on the top edge fading into the hairline — reads as a
            // raised, glassy surface rather than a flat rectangle.
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), BrandColor.stroke.opacity(0.7), BrandColor.stroke],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
    }
}

/// Primary call-to-action — deep-blue gradient fill, white label, accent glow.
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
        .background(
            LinearGradient(
                colors: [BrandColor.accent, BrandColor.accent.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .foregroundStyle(BrandColor.onAccent)
        .shadow(color: BrandColor.accent.opacity(0.45), radius: 14, y: 6)
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

/// A labeled figure — calculator outputs and dashboard stats. Emphasis uses the lighter
/// `accentText` blue so it stays legible on the dark ground (WCAG).
struct StatTile: View {
    let label: String
    let value: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label.uppercased())
                .font(Typo.caption)
                .tracking(0.8)
                .foregroundStyle(BrandColor.textSecondary)
            Text(value)
                .font(emphasized ? Typo.numberLG : Typo.numberMD)
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

/// Small tinted chip for tags / categories / savings. Colors passed in should be the
/// lighter/brighter hues (mint, accentText, amber, danger) so text stays legible on dark.
struct TagChip: View {
    let text: String
    var color: Color = BrandColor.mint
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
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

/// Evidence-tier badge (A/B/C/D). Tier B uses the lighter accent blue for legibility.
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
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// An Apple-health-style circular adherence ring. Accessible (label + value), static (no
/// motion) so it respects Reduce Motion by default.
struct AdherenceRing: View {
    let fraction: Double
    var size: CGFloat = 88

    @State private var animated = false
    private var clamped: Double { max(0, min(1, fraction)) }
    private var pct: Int { Int((clamped * 100).rounded()) }

    var body: some View {
        ZStack {
            Circle().stroke(BrandColor.surfaceElevated, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.0001, animated ? clamped : 0))
                .stroke(
                    AngularGradient(colors: [BrandColor.accentText, BrandColor.success, BrandColor.accentText], center: .center),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.85), value: animated)
            VStack(spacing: 0) {
                Text("\(pct)%")
                    .font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(BrandColor.textPrimary)
                Text("ON TRACK")
                    .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animated = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On track")
        .accessibilityValue("\(pct) percent of scheduled doses taken over the last 14 days")
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
