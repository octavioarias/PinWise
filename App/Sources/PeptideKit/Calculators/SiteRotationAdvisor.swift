import Foundation

/// Suggests the next injection site to reduce lipohypertrophy / site overuse — a
/// concrete safety feature and a top-requested visual (body-map heatmap).
///
/// Strategy: among candidate sites, prefer those in a *different region* than the last
/// injection, then pick the least-recently-used site. Never-used sites rank first.
public enum SiteRotationAdvisor {

    /// - Parameters:
    ///   - candidates: sites in play (e.g. protocol's preferred sites, or all sites).
    ///   - history: past doses (any order); only `site` and `timestamp` are used.
    /// - Returns: the recommended next site, or `nil` if no candidates.
    public static func suggestNext(
        candidates: [InjectionSite] = InjectionSite.allCases,
        history: [DoseLog]
    ) -> InjectionSite? {
        guard !candidates.isEmpty else { return nil }

        // Most-recent use timestamp per site.
        var lastUsed: [InjectionSite: Date] = [:]
        for log in history {
            guard let site = log.site else { continue }
            if let existing = lastUsed[site] {
                if log.timestamp > existing { lastUsed[site] = log.timestamp }
            } else {
                lastUsed[site] = log.timestamp
            }
        }

        let lastRegion = history
            .filter { $0.site != nil }
            .max(by: { $0.timestamp < $1.timestamp })?
            .site?.region

        // Rank: (1) different region than last injection, (2) least-recently-used
        // (never-used sorts before any used, via distantPast).
        func score(_ site: InjectionSite) -> (Bool, Date) {
            let differentRegion = (lastRegion == nil) ? true : site.region != lastRegion
            let recency = lastUsed[site] ?? .distantPast
            return (differentRegion, recency)
        }

        return candidates.min { a, b in
            let sa = score(a), sb = score(b)
            if sa.0 != sb.0 { return sa.0 && !sb.0 }   // prefer different-region == true
            return sa.1 < sb.1                          // then least-recently-used
        }
    }
}
