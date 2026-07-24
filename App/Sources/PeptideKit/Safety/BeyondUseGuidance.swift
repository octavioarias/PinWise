import Foundation

/// Recommended beyond-use / discard window (days after reconstitution) by compound. These are
/// EDITABLE SUGGESTIONS, never enforced — the vial editor offers this as the default discard window
/// when a compound is chosen, and the user can always override it. Grounded in community + stability
/// guidance: most peptides use the ~28-day USP multi-dose microbial-safety window; a few are notably
/// less stable once mixed and warrant a shorter default. Nothing here is a potency guarantee.
public enum BeyondUseGuidance {
    /// The default USP multi-dose microbial-safety window, used for anything not called out below.
    public static let defaultDays = 28

    /// Case-insensitive, alias-tolerant lookup keyed by the compound name. Falls back to `defaultDays`.
    public static func recommendedDays(forCompound name: String) -> Int {
        let key = name.lowercased()
        // Less stable once reconstituted → a shorter suggested window (still user-editable).
        if key.contains("glutathione") { return 14 }                 // notoriously unstable
        if key.contains("ghk") { return 21 }                         // GHK-Cu (copper peptide)
        if key.contains("igf") { return 21 }                         // IGF-1 LR3 — oxidation-sensitive
        if key.contains("cjc") || key.contains("ipamorelin")
            || key.contains("sermorelin") || key.contains("tesamorelin") {
            return 21                                                // GH secretagogues — heat-sensitive
        }
        return defaultDays                                           // GLP-1s, BPC-157, TB-500, etc.
    }
}
