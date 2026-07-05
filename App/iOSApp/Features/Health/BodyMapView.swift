import SwiftUI
import SwiftData
import PeptideKit

/// A body heat map of injection-site frequency over a blue "x-ray glow" front-facing figure
/// (dark translucent body + glowing blue edge, on black — per the reference): warmer, larger
/// blooms mark sites used more often. Doubles as a rotation aid. Native shapes, no assets.
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

    // MARK: Figure (blue x-ray glow)

    private var figure: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headSize = CGSize(width: w * 0.155, height: h * 0.12)
            let headCenter = CGPoint(x: w * 0.5, y: h * 0.075)
            let body = MaleBodyShape()
            ZStack {
                // Black backdrop so the blue glow reads (per the reference).
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x0A1530), .black],
                                         center: .center, startRadius: 10, endRadius: max(w, h) * 0.7))

                // Outer glow — layered blurred strokes (neon x-ray edge).
                body.stroke(Color(hex: 0x3E8CFF), lineWidth: 7).blur(radius: 20).opacity(0.55)
                Ellipse().stroke(Color(hex: 0x3E8CFF), lineWidth: 7).blur(radius: 20).opacity(0.55)
                    .frame(width: headSize.width, height: headSize.height).position(headCenter)
                body.stroke(Color(hex: 0x4FA8FF), lineWidth: 3).blur(radius: 9).opacity(0.9)
                Ellipse().stroke(Color(hex: 0x4FA8FF), lineWidth: 3).blur(radius: 9).opacity(0.9)
                    .frame(width: headSize.width, height: headSize.height).position(headCenter)

                // Translucent blue body + head (x-ray).
                Group {
                    body.fill(bodyFill(w, h))
                    Ellipse().fill(RadialGradient(colors: [Color(hex: 0x2E63E6).opacity(0.5), Color(hex: 0x07122E).opacity(0.55)],
                                                  center: UnitPoint(x: 0.5, y: 0.4), startRadius: 2, endRadius: headSize.width * 0.7))
                        .frame(width: headSize.width, height: headSize.height).position(headCenter)
                }

                // Heat blooms (warm, glow over the blue body).
                heatLayer(w, h).blendMode(.screen).clipShape(body)

                // Crisp bright rim.
                body.stroke(edgeGradient, lineWidth: 1.4)
                Ellipse().stroke(edgeGradient, lineWidth: 1.4)
                    .frame(width: headSize.width, height: headSize.height).position(headCenter)

                // Faint locators for every site.
                ForEach(InjectionSite.allCases) { site in
                    let p = position(for: site)
                    Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                        .frame(width: 8, height: 8)
                        .position(x: p.x * w, y: p.y * h)
                }
            }
        }
        .frame(height: 440)
        .frame(maxWidth: .infinity)
    }

    private func bodyFill(_ w: CGFloat, _ h: CGFloat) -> RadialGradient {
        RadialGradient(colors: [
            Color(hex: 0x2E63E6).opacity(0.50),
            Color(hex: 0x14286E).opacity(0.55),
            Color(hex: 0x07122E).opacity(0.55),
        ], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 6, endRadius: max(w, h) * 0.55)
    }

    private var edgeGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xBFD9FF), Color(hex: 0x5C8CFF)], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private func heatLayer(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach(InjectionSite.allCases) { site in
            let c = counts[site] ?? 0
            if c > 0 {
                let t = intensity(c)
                let radius = 26 + 36 * t
                let p = position(for: site)
                Circle()
                    .fill(RadialGradient(colors: [heatColor(t).opacity(0.95), heatColor(t).opacity(0)],
                                         center: .center, startRadius: 0, endRadius: radius))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: p.x * w, y: p.y * h)
                    .blur(radius: 8)
            }
        }
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
        case .armLeft:           return CGPoint(x: 0.32, y: 0.34)
        case .armRight:          return CGPoint(x: 0.68, y: 0.34)
        case .abdomenUpperLeft:  return CGPoint(x: 0.44, y: 0.34)
        case .abdomenUpperRight: return CGPoint(x: 0.56, y: 0.34)
        case .abdomenLowerLeft:  return CGPoint(x: 0.44, y: 0.45)
        case .abdomenLowerRight: return CGPoint(x: 0.56, y: 0.45)
        case .gluteLeft:         return CGPoint(x: 0.44, y: 0.53)
        case .gluteRight:        return CGPoint(x: 0.56, y: 0.53)
        case .thighLeft:         return CGPoint(x: 0.45, y: 0.68)
        case .thighRight:        return CGPoint(x: 0.55, y: 0.68)
        }
    }
}

/// A smooth front-facing body outline (torso + arms + legs) in normalized proportions.
/// Landmark points are rounded into a continuous curve (quad curves through midpoints).
/// Symmetric; head is drawn separately.
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
