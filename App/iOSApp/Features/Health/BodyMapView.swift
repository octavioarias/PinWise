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
            let headSize = CGSize(width: w * 0.115, height: h * 0.116)
            let headCenter = CGPoint(x: w * 0.5, y: h * 0.070)
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
        case .armLeft:           return CGPoint(x: 0.345, y: 0.320)
        case .armRight:          return CGPoint(x: 0.655, y: 0.320)
        case .abdomenUpperLeft:  return CGPoint(x: 0.452, y: 0.315)
        case .abdomenUpperRight: return CGPoint(x: 0.548, y: 0.315)
        case .abdomenLowerLeft:  return CGPoint(x: 0.452, y: 0.420)
        case .abdomenLowerRight: return CGPoint(x: 0.548, y: 0.420)
        case .gluteLeft:         return CGPoint(x: 0.435, y: 0.490)
        case .gluteRight:        return CGPoint(x: 0.565, y: 0.490)
        case .thighLeft:         return CGPoint(x: 0.440, y: 0.605)
        case .thighRight:        return CGPoint(x: 0.560, y: 0.605)
        }
    }
}

/// A front-facing male body — torso+legs as one subpath and each arm as its own subpath, so the
/// natural gap between arm and torso shows through. Dense landmark points trace the true silhouette
/// (sloping traps, rounded deltoids, chest, V-tapered waist, hip flare, thigh/calf bulges, slim
/// ankles, splayed feet) and are joined with a closed Catmull-Rom spline (emitted as cubic Béziers)
/// so the curve passes *through* every point. Head is drawn separately as an ellipse. All subpaths
/// are wound the same way so overlaps (shoulder ↔ deltoid) fill solid instead of cancelling.
struct MaleBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ p: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(x: rect.minX + p.0 * rect.width, y: rect.minY + p.1 * rect.height)
        }
        func mirror(_ p: (CGFloat, CGFloat)) -> (CGFloat, CGFloat) { (1 - p.0, p.1) }

        // Right half of torso+legs: top-center of the neck → clockwise down the right side
        // (trap → deltoid root → chest → waist → hip → outer thigh → knee → calf → ankle → foot)
        // → up the inner right leg to the crotch center. The left half is the mirror (reversed,
        // minus the two shared on-axis endpoints), giving one symmetric closed loop.
        let torsoRight: [(CGFloat, CGFloat)] = [
            (0.500, 0.118),  // neck top center [axis]
            (0.538, 0.128),  // neck (right)
            (0.556, 0.164),  // neck base / trapezius
            (0.598, 0.181),  // trapezius slope
            (0.632, 0.198),  // acromion / shoulder top (arm overlaps here)
            (0.620, 0.250),  // side under deltoid (armpit)
            (0.614, 0.300),  // side of chest
            (0.606, 0.352),  // lower ribs
            (0.600, 0.392),  // waist (narrowest)
            (0.610, 0.442),  // iliac crest / hip rising
            (0.628, 0.482),  // hip widest (greater trochanter)
            (0.632, 0.525),  // upper outer thigh (bulge)
            (0.622, 0.590),  // mid outer thigh
            (0.600, 0.658),  // lower thigh (above knee)
            (0.574, 0.716),  // knee (outer)
            (0.570, 0.748),  // below knee
            (0.596, 0.795),  // calf outer bulge
            (0.572, 0.855),  // lower calf taper
            (0.560, 0.898),  // ankle (outer)
            (0.560, 0.930),  // outer heel / foot
            (0.598, 0.960),  // toe tip (forward + slightly out)
            (0.520, 0.958),  // inner toe / medial foot
            (0.524, 0.900),  // inner ankle
            (0.526, 0.855),  // inner lower calf
            (0.528, 0.798),  // inner calf
            (0.522, 0.748),  // inner below knee
            (0.520, 0.716),  // inner knee
            (0.516, 0.650),  // inner lower thigh
            (0.510, 0.580),  // inner mid thigh (legs nearly together)
            (0.506, 0.525),  // inner upper thigh
            (0.500, 0.508),  // crotch center [axis]
        ]
        let torso = torsoRight + torsoRight.reversed().dropFirst().dropLast().map(mirror)

        // Right arm as its own loop: overlaps the shoulder cap (so it reads connected) then hangs
        // slightly out with its inner edge clearing the torso side → a visible gap below the armpit.
        // Outer edge (deltoid → triceps → elbow → forearm → hand) down, inner edge back up to armpit.
        let armRight: [(CGFloat, CGFloat)] = [
            (0.626, 0.194),  // shoulder cap (overlaps torso acromion)
            (0.678, 0.240),  // deltoid (outer max)
            (0.672, 0.300),  // upper arm / triceps (outer)
            (0.658, 0.392),  // elbow (outer)
            (0.664, 0.440),  // forearm outer bulge
            (0.646, 0.520),  // forearm taper
            (0.636, 0.560),  // wrist (outer)
            (0.642, 0.600),  // hand / knuckles (outer)
            (0.618, 0.636),  // fingertips
            (0.598, 0.612),  // hand (inner)
            (0.606, 0.560),  // wrist (inner)
            (0.622, 0.500),  // forearm (inner)
            (0.636, 0.395),  // inner elbow
            (0.624, 0.300),  // inner upper arm
            (0.612, 0.246),  // armpit
            (0.606, 0.210),  // inner shoulder
        ]
        let armLeft = armRight.map(mirror)

        var path = Path()
        addLoop(&path, torso.map(pt))
        addLoop(&path, armRight.map(pt))
        addLoop(&path, armLeft.map(pt))
        return path
    }

    /// Add a smooth closed loop through the given landmark points using a uniform Catmull-Rom
    /// spline expressed as cubic Béziers, so the curve interpolates (passes through) every point.
    /// Winding is normalized to a consistent direction so overlapping subpaths union (fill solid)
    /// instead of punching holes.
    private func addLoop(_ path: inout Path, _ raw: [CGPoint]) {
        let pts = normalizedWinding(raw)
        let n = pts.count
        guard n > 2 else { return }
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n]
            let p1 = pts[i]
            let p2 = pts[(i + 1) % n]
            let p3 = pts[(i + 2) % n]
            // Catmull-Rom → cubic Bézier control points (uniform, tension 1/6).
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
    }

    private func normalizedWinding(_ pts: [CGPoint]) -> [CGPoint] {
        var area: CGFloat = 0
        for i in pts.indices {
            let j = (i + 1) % pts.count
            area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return area < 0 ? Array(pts.reversed()) : pts
    }
}
