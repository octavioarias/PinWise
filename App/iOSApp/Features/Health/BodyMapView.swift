import SwiftUI
import SwiftData
import PeptideKit

/// A body heat map of injection-site frequency, drawn over a gray front-facing male figure:
/// warmer, larger blooms mark sites you use more often. Doubles as a rotation aid (the app
/// suggests the least-recently-used site). Native shapes — no image assets. Mirror-style.
struct BodyMapView: View {
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var doses: [LoggedDose]

    private var counts: [InjectionSite: Int] {
        var d: [InjectionSite: Int] = [:]
        for dose in doses { if let s = dose.site { d[s, default: 0] += 1 } }
        return d
    }
    private var maxCount: Int { counts.values.max() ?? 0 }
    private var totalPlaced: Int { counts.values.reduce(0, +) }
    private var suggested: InjectionSite? {
        SiteRotationAdvisor.suggestNext(history: doses.map { $0.asDomain() })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Where you've been injecting. Warmer, larger blooms are used more often — rotating toward the cooler areas gives tissue time to recover.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(spacing: Space.md) {
                        figure
                        legend
                        Text("Shown mirror-style — left and right are your own body's sides.")
                            .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                    }
                }

                if let s = suggested, totalPlaced > 0 {
                    Card {
                        HStack(spacing: Space.md) {
                            Image(systemName: "sparkles").font(.title3).foregroundStyle(BrandColor.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Suggested next site").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Text(s.displayName).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                            }
                            Spacer()
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader(title: "By site")
                        ForEach(InjectionSite.allCases) { site in
                            let c = counts[site] ?? 0
                            HStack(spacing: Space.sm) {
                                Circle().fill(c > 0 ? heatColor(intensity(c)) : BrandColor.surfaceElevated)
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().strokeBorder(BrandColor.stroke, lineWidth: 0.5))
                                Text(site.displayName).font(.caption).foregroundStyle(BrandColor.textPrimary)
                                Spacer()
                                Text("\(c)").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                    }
                }

                if totalPlaced == 0 {
                    Text("Log a dose with an injection site to start building your map.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }

                DisclaimerBanner(text: "Rotation guidance is general education, not medical advice.")
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Injection map")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Figure + heat

    private var figure: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Gray male body: torso/arms/legs shape + head, shaded for a little dimension.
                MaleBodyShape()
                    .fill(bodyGradient)
                MaleBodyShape()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                Ellipse()
                    .fill(bodyGradient)
                    .frame(width: w * 0.15, height: h * 0.11)
                    .position(x: w * 0.5, y: h * 0.075)

                // Heat blooms, clipped to the body so warmth sits on the figure.
                ZStack {
                    ForEach(InjectionSite.allCases) { site in
                        let c = counts[site] ?? 0
                        if c > 0 {
                            let t = intensity(c)
                            let radius = 24 + 34 * t
                            let p = position(for: site)
                            Circle()
                                .fill(RadialGradient(
                                    colors: [heatColor(t).opacity(0.9), heatColor(t).opacity(0)],
                                    center: .center, startRadius: 0, endRadius: radius))
                                .frame(width: radius * 2, height: radius * 2)
                                .position(x: p.x * w, y: p.y * h)
                                .blur(radius: 9)
                        }
                    }
                }
                .frame(width: w, height: h)
                .clipShape(MaleBodyShape())

                // Faint locators so every site is findable even at zero uses.
                ForEach(InjectionSite.allCases) { site in
                    let p = position(for: site)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 9, height: 9)
                        .position(x: p.x * w, y: p.y * h)
                }
            }
        }
        .frame(height: 420)
        .frame(maxWidth: .infinity)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(colors: [Color(white: 0.46), Color(white: 0.30)], startPoint: .top, endPoint: .bottom)
    }

    private var legend: some View {
        HStack(spacing: Space.sm) {
            Text("Less").font(.caption2).foregroundStyle(BrandColor.textSecondary)
            Capsule()
                .fill(LinearGradient(colors: [heatColor(0.12), heatColor(0.5), heatColor(0.92)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            Text("More").font(.caption2).foregroundStyle(BrandColor.textSecondary)
        }
    }

    // MARK: Heat helpers

    private func intensity(_ count: Int) -> Double {
        guard maxCount > 0 else { return 0 }
        return max(0, min(1, Double(count) / Double(maxCount)))
    }

    /// Smooth green → amber → red thermal ramp.
    private func heatColor(_ t: Double) -> Color {
        let x = max(0, min(1, t))
        func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
        if x < 0.5 {
            let u = x / 0.5
            return Color(red: lerp(0.10, 1.00, u), green: lerp(0.78, 0.69, u), blue: lerp(0.55, 0.13, u))
        } else {
            let u = (x - 0.5) / 0.5
            return Color(red: lerp(1.00, 0.87, u), green: lerp(0.69, 0.20, u), blue: lerp(0.13, 0.20, u))
        }
    }

    /// Normalized (0…1) marker positions over the figure, mirror-style.
    private func position(for site: InjectionSite) -> CGPoint {
        switch site {
        case .armLeft:           return CGPoint(x: 0.31, y: 0.30)
        case .armRight:          return CGPoint(x: 0.69, y: 0.30)
        case .abdomenUpperLeft:  return CGPoint(x: 0.44, y: 0.33)
        case .abdomenUpperRight: return CGPoint(x: 0.56, y: 0.33)
        case .abdomenLowerLeft:  return CGPoint(x: 0.44, y: 0.44)
        case .abdomenLowerRight: return CGPoint(x: 0.56, y: 0.44)
        case .gluteLeft:         return CGPoint(x: 0.44, y: 0.53)
        case .gluteRight:        return CGPoint(x: 0.56, y: 0.53)
        case .thighLeft:         return CGPoint(x: 0.45, y: 0.67)
        case .thighRight:        return CGPoint(x: 0.55, y: 0.67)
        }
    }
}

/// A simple front-facing male body outline (torso + arms + legs) in normalized proportions.
/// Symmetric: the right half is authored and mirrored. Head is drawn separately.
struct MaleBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        // Right-side outline from neck base, out along the shoulder/arm, down the torso and leg
        // to the crotch center. Mirrored for the left side.
        let right: [(CGFloat, CGFloat)] = [
            (0.50, 0.150), (0.565, 0.150), (0.605, 0.180), (0.700, 0.240),
            (0.690, 0.400), (0.662, 0.520), (0.668, 0.565), (0.620, 0.552),
            (0.600, 0.400), (0.585, 0.258), (0.575, 0.420), (0.628, 0.500),
            (0.600, 0.620), (0.575, 0.740), (0.575, 0.860), (0.552, 0.955),
            (0.566, 0.985), (0.516, 0.978), (0.520, 0.860), (0.526, 0.740),
            (0.505, 0.600), (0.500, 0.585),
        ]
        var p = Path()
        p.move(to: pt(right[0].0, right[0].1))
        for q in right.dropFirst() { p.addLine(to: pt(q.0, q.1)) }
        for q in right.reversed() { p.addLine(to: pt(1 - q.0, q.1)) }
        p.closeSubpath()
        return p
    }
}
