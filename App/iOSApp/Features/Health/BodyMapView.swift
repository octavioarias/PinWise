import SwiftUI
import SwiftData
import PeptideKit

/// A body heat map of injection-site frequency: warmer spots are used more often. Doubles as a
/// rotation aid — the app suggests the least-recently-used site. Sites are shown mirror-style
/// (your own left/right). Built from logged doses; drawn with native shapes (no image assets).
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
                Text("Where you've been injecting. Warmer spots are used more often — rotating toward the cooler ones gives tissue time to recover.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(spacing: Space.md) {
                        bodyDiagram
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
                            HStack(spacing: Space.sm) {
                                Circle().fill(heatColor(for: counts[site] ?? 0))
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().strokeBorder(BrandColor.stroke, lineWidth: 0.5))
                                Text(site.displayName).font(.caption).foregroundStyle(BrandColor.textPrimary)
                                Spacer()
                                Text("\(counts[site] ?? 0)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
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

    // MARK: Diagram

    private var bodyDiagram: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                silhouette(w: w, h: h)
                ForEach(InjectionSite.allCases) { site in
                    let p = position(for: site)
                    marker(for: site).position(x: p.x * w, y: p.y * h)
                }
            }
        }
        .frame(height: 360)
        .frame(maxWidth: .infinity)
    }

    private func silhouette(w: CGFloat, h: CGFloat) -> some View {
        let fill = BrandColor.surfaceElevated.opacity(0.55)
        return ZStack {
            Circle().fill(fill).frame(width: w * 0.17, height: w * 0.17).position(x: w * 0.5, y: h * 0.09)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(fill).frame(width: w * 0.44, height: h * 0.44).position(x: w * 0.5, y: h * 0.40)
            Capsule().fill(fill).frame(width: w * 0.11, height: h * 0.34).position(x: w * 0.21, y: h * 0.36)
            Capsule().fill(fill).frame(width: w * 0.11, height: h * 0.34).position(x: w * 0.79, y: h * 0.36)
            Capsule().fill(fill).frame(width: w * 0.17, height: h * 0.40).position(x: w * 0.40, y: h * 0.80)
            Capsule().fill(fill).frame(width: w * 0.17, height: h * 0.40).position(x: w * 0.60, y: h * 0.80)
        }
    }

    private func marker(for site: InjectionSite) -> some View {
        let c = counts[site] ?? 0
        return ZStack {
            Circle()
                .fill(heatColor(for: c))
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(BrandColor.background.opacity(0.5), lineWidth: 1.5))
            if c > 0 {
                Text("\(c)").font(.caption2.weight(.bold)).foregroundStyle(BrandColor.background)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .accessibilityLabel("\(site.displayName): \(c) doses")
    }

    /// Normalized (0…1) marker positions over the silhouette, mirror-style.
    private func position(for site: InjectionSite) -> CGPoint {
        switch site {
        case .armLeft:           return CGPoint(x: 0.21, y: 0.30)
        case .armRight:          return CGPoint(x: 0.79, y: 0.30)
        case .abdomenUpperLeft:  return CGPoint(x: 0.42, y: 0.33)
        case .abdomenUpperRight: return CGPoint(x: 0.58, y: 0.33)
        case .abdomenLowerLeft:  return CGPoint(x: 0.42, y: 0.46)
        case .abdomenLowerRight: return CGPoint(x: 0.58, y: 0.46)
        case .gluteLeft:         return CGPoint(x: 0.39, y: 0.60)
        case .gluteRight:        return CGPoint(x: 0.61, y: 0.60)
        case .thighLeft:         return CGPoint(x: 0.40, y: 0.80)
        case .thighRight:        return CGPoint(x: 0.60, y: 0.80)
        }
    }

    /// Relative heat: none → surface; then low/medium/high vs the most-used site.
    private func heatColor(for count: Int) -> Color {
        guard count > 0, maxCount > 0 else { return BrandColor.surfaceElevated }
        let frac = Double(count) / Double(maxCount)
        if frac <= 0.34 { return BrandColor.success }
        if frac <= 0.67 { return BrandColor.warning }
        return BrandColor.danger
    }

    private var legend: some View {
        HStack(spacing: Space.md) {
            legendDot(BrandColor.surfaceElevated, "None")
            legendDot(BrandColor.success, "Low")
            legendDot(BrandColor.warning, "Medium")
            legendDot(BrandColor.danger, "High")
            Spacer()
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(BrandColor.stroke, lineWidth: 0.5))
            Text(label).font(.caption2).foregroundStyle(BrandColor.textSecondary)
        }
    }
}
