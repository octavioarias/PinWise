import Foundation

/// Corrects a vial's *labeled* amount to its true active content using a Certificate of Analysis
/// (COA). A COA reports up to three percentages — **assay**, net **content**, and **purity** — and
/// the true active fraction is their product. A "10 mg" peptide vial is rarely 10 mg of active
/// compound: the lyophilized mass also holds water and counterion salts (TFA/acetate), so net
/// content is often only ~80–90%. Dosing off the label therefore silently under-doses.
///
/// Not every COA lists all three values (some show two, or one) — whichever are provided are
/// applied and the rest are treated as 100% (no effect). The percentages are compound-agnostic:
/// they describe whatever the vial actually contains (a peptide, a vitamin, etc.), so no
/// compound-specific assumptions are baked in.
public enum COACorrection {
    /// Net active fraction (0–1) from whichever of assay/content/purity percentages are provided.
    /// Returns 1.0 when none are provided — the label is then taken at face value (uncorrected).
    /// Example: assay 99.5%, content 88%, purity 99.8% → 0.995 × 0.88 × 0.998 ≈ 0.8738, so a
    /// 10 mg label is ≈ 8.74 mg of active compound.
    public static func factor(assayPercent: Double? = nil,
                              contentPercent: Double? = nil,
                              purityPercent: Double? = nil) -> Double {
        var f = 1.0
        for percent in [assayPercent, contentPercent, purityPercent] {
            if let percent, percent > 0 { f *= percent / 100 }
        }
        return f
    }

    /// A labeled mass corrected to its true active mass via the COA percentages.
    public static func correctedMass(_ label: Mass,
                                     assayPercent: Double? = nil,
                                     contentPercent: Double? = nil,
                                     purityPercent: Double? = nil) -> Mass {
        Mass(micrograms: label.micrograms * factor(assayPercent: assayPercent,
                                                   contentPercent: contentPercent,
                                                   purityPercent: purityPercent))
    }
}
