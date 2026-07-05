import SwiftUI
import SwiftData
import PeptideKit
import MuscleMap

/// Injection-site heat map over a professionally-drawn anatomical body (MuscleMap, MIT). Our
/// 10 sites map onto muscle regions and render as a native SwiftUI heatmap; front/back toggle
/// (glutes live on the back). Doubles as a rotation aid. No image assets, no WebView.
struct BodyMapView: View {
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var doses: [LoggedDose]
    @State private var side: BodySide = .front

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

    /// Map each injection site to a MuscleMap region + side.
    private func target(for site: InjectionSite) -> (Muscle, MuscleSide) {
        switch site {
        case .armLeft:           return (.deltoids, .left)
        case .armRight:          return (.deltoids, .right)
        case .abdomenUpperLeft:  return (.upperAbs, .left)
        case .abdomenUpperRight: return (.upperAbs, .right)
        case .abdomenLowerLeft:  return (.lowerAbs, .left)
        case .abdomenLowerRight: return (.lowerAbs, .right)
        case .gluteLeft:         return (.gluteal, .left)
        case .gluteRight:        return (.gluteal, .right)
        case .thighLeft:         return (.quadriceps, .left)
        case .thighRight:        return (.quadriceps, .right)
        }
    }

    private var intensities: [MuscleIntensity] {
        let m = Double(maxCount)
        guard m > 0 else { return [] }
        return InjectionSite.allCases.compactMap { site in
            let c = counts[site] ?? 0
            guard c > 0 else { return nil }
            let (muscle, mside) = target(for: site)
            return MuscleIntensity(muscle: muscle, intensity: Double(c) / m, side: mside)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Where you've been injecting. Warmer regions are used more often — rotate toward the cooler ones to give tissue time to recover.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(spacing: Space.md) {
                        Picker("", selection: $side) {
                            Text("Front").tag(BodySide.front)
                            Text("Back").tag(BodySide.back)
                        }
                        .pickerStyle(.segmented)

                        BodyView(gender: .male, side: side)
                            .heatmap(intensities, colorScale: .thermalSmooth)
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)

                        legend
                    }
                }

                if let s = suggested, totalPlaced > 0 {
                    Card {
                        HStack(spacing: Space.md) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundStyle(BrandColor.success)
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

    private func intensity(_ count: Int) -> Double {
        guard maxCount > 0 else { return 0 }
        return max(0, min(1, Double(count) / Double(maxCount)))
    }

    /// Thermal ramp for the per-site legend dots (matches the body heatmap's feel).
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
}
