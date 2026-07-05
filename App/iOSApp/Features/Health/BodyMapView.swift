import SwiftUI
import SwiftData
import PeptideKit

/// A body heat map of injection-site frequency over a glassy, translucent front-facing figure
/// (skeleton hinted inside, à la body-composition apps): warmer, larger blooms mark sites used
/// more often. Doubles as a rotation aid. Native shapes — no image assets. Mirror-style.
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

    // MARK: Figure

    private var figure: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headSize = CGSize(width: w * 0.15, height: h * 0.115)
            let headCenter = CGPoint(x: w * 0.5, y: h * 0.075)
            ZStack {
                // Cool backdrop glow so the glassy body reads against the card.
                RadialGradient(colors: [Color(hex: 0x123840).opacity(0.55), .clear],
                               center: .center, startRadius: 10, endRadius: h * 0.62)

                // Glassy translucent body + head.
                MaleBodyShape().fill(bodyGlass)
                Ellipse().fill(bodyGlass).frame(width: headSize.width, height: headSize.height).position(headCenter)

                // Hinted skeleton (spine, ribs, collarbones, pelvis), clipped to the torso.
                SkeletonLines()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .clipShape(MaleBodyShape())

                // Heat blooms, clipped to the body and screen-blended so warmth glows.
                ZStack {
                    ForEach(InjectionSite.allCases) { site in
                        let c = counts[site] ?? 0
                        if c > 0 {
                            let t = intensity(c)
                            let radius = 26 + 36 * t
                            let p = position(for: site)
                            Circle()
                                .fill(RadialGradient(
                                    colors: [heatColor(t).opacity(0.95), heatColor(t).opacity(0)],
                                    center: .center, startRadius: 0, endRadius: radius))
                                .frame(width: radius * 2, height: radius * 2)
                                .position(x: p.x * w, y: p.y * h)
                                .blur(radius: 8)
                        }
                    }
                }
                .frame(width: w, height: h)
                .blendMode(.screen)
                .clipShape(MaleBodyShape())

                // Rim light on the body + head edges.
                MaleBodyShape().stroke(rimGradient, lineWidth: 1.2)
                Ellipse().stroke(rimGradient, lineWidth: 1.2).frame(width: headSize.width, height: headSize.height).position(headCenter)

                // Faint locators so every site is findable even at zero uses.
                ForEach(InjectionSite.allCases) { site in
                    let p = position(for: site)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 8, height: 8)
                        .position(x: p.x * w, y: p.y * h)
                }
            }
        }
        .frame(height: 440)
        .frame(maxWidth: .infinity)
    }

    private var bodyGlass: LinearGradient {
        LinearGradient(colors: [
            Color(hex: 0x49E0C6).opacity(0.30),
            Color(hex: 0x2FB6D6).opacity(0.20),
            Color(hex: 0x3E7FD0).opacity(0.26),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var rimGradient: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.5), Color(hex: 0x49E0C6).opacity(0.35), Color.white.opacity(0.15)],
                       startPoint: .top, endPoint: .bottom)
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
            return Color(red: lerp(0.10, 1.00, u), green: lerp(0.82, 0.69, u), blue: lerp(0.55, 0.13, u))
        } else {
            let u = (x - 0.5) / 0.5
            return Color(red: lerp(1.00, 0.90, u), green: lerp(0.69, 0.20, u), blue: lerp(0.13, 0.20, u))
        }
    }

    /// Normalized (0…1) marker positions over the figure, mirror-style.
    private func position(for site: InjectionSite) -> CGPoint {
        switch site {
        case .armLeft:           return CGPoint(x: 0.34, y: 0.32)
        case .armRight:          return CGPoint(x: 0.66, y: 0.32)
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

/// A smooth front-facing body outline (torso + arms + legs) in normalized proportions.
/// Landmark points are rounded into a continuous curve (quad curves through midpoints) so the
/// silhouette reads organically rather than angular. Symmetric; head is drawn separately.
struct MaleBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let rightNorm: [(CGFloat, CGFloat)] = [
            (0.50, 0.150), (0.565, 0.150), (0.605, 0.180), (0.700, 0.240),
            (0.690, 0.400), (0.662, 0.520), (0.668, 0.565), (0.620, 0.552),
            (0.600, 0.400), (0.585, 0.258), (0.575, 0.420), (0.628, 0.500),
            (0.600, 0.620), (0.575, 0.740), (0.575, 0.860), (0.552, 0.955),
            (0.566, 0.985), (0.516, 0.978), (0.520, 0.860), (0.526, 0.740),
            (0.505, 0.600), (0.500, 0.585),
        ]
        var points = rightNorm.map { pt($0.0, $0.1) }
        points += rightNorm.reversed().map { pt(1 - $0.0, $0.1) }

        var p = Path()
        guard points.count > 2 else { return p }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(points[points.count - 1], points[0]))
        for i in 0..<points.count {
            let curr = points[i]
            let next = points[(i + 1) % points.count]
            p.addQuadCurve(to: mid(curr, next), control: curr)
        }
        p.closeSubpath()
        return p
    }
}

/// Faint anatomical hints (spine + vertebrae, ribs, collarbones, pelvis) for the "glassy x-ray"
/// look. Drawn in normalized proportions; stroked lightly and clipped to the body.
struct SkeletonLines: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        // Spine
        p.move(to: pt(0.5, 0.170)); p.addLine(to: pt(0.5, 0.520))
        // Vertebrae ticks
        var y: CGFloat = 0.190
        while y < 0.515 { p.move(to: pt(0.480, y)); p.addLine(to: pt(0.520, y)); y += 0.035 }
        // Ribs (both sides)
        for ry in [CGFloat(0.235), 0.280, 0.325, 0.370] {
            p.move(to: pt(0.5, ry)); p.addQuadCurve(to: pt(0.585, ry + 0.05), control: pt(0.575, ry))
            p.move(to: pt(0.5, ry)); p.addQuadCurve(to: pt(0.415, ry + 0.05), control: pt(0.425, ry))
        }
        // Collarbones
        p.move(to: pt(0.5, 0.188)); p.addQuadCurve(to: pt(0.63, 0.205), control: pt(0.565, 0.188))
        p.move(to: pt(0.5, 0.188)); p.addQuadCurve(to: pt(0.37, 0.205), control: pt(0.435, 0.188))
        // Pelvis
        p.move(to: pt(0.42, 0.495)); p.addQuadCurve(to: pt(0.5, 0.560), control: pt(0.46, 0.548))
        p.move(to: pt(0.58, 0.495)); p.addQuadCurve(to: pt(0.5, 0.560), control: pt(0.54, 0.548))
        return p
    }
}
