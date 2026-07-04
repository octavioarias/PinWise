import Foundation

/// How much human evidence backs a compound's use. Drives the app's disclaimer posture
/// so the UI can be honest about the (large) gap between an FDA-approved drug and a
/// "research chemical." Derived from the clinical research review (see
/// Knowledge/.../09_Clinical_Compound_Catalog_and_Safety_Data.md).
public enum EvidenceTier: String, Codable, CaseIterable, Sendable {
    /// FDA-approved for at least one human indication (e.g. semaglutide, tesamorelin).
    case fdaApproved
    /// Published human-trial dosing exists, but the compound is not FDA-approved
    /// (e.g. CJC-1295, ipamorelin).
    case humanTrialsUnapproved
    /// Preclinical / animal data, or failed/halted human trials; scant human data
    /// (e.g. BPC-157, TB-500 fragment).
    case preclinicalOrFailed
    /// Evidence is for a topical form or a metabolic precursor, but it is used off-label
    /// by injection (e.g. injectable GHK-Cu, NAD+).
    case precursorOffLabel

    /// Short badge letter for compact UI.
    public var letter: String {
        switch self {
        case .fdaApproved: return "A"
        case .humanTrialsUnapproved: return "B"
        case .preclinicalOrFailed: return "C"
        case .precursorOffLabel: return "D"
        }
    }

    public var label: String {
        switch self {
        case .fdaApproved: return "FDA-approved (human)"
        case .humanTrialsUnapproved: return "Human trials, not approved"
        case .preclinicalOrFailed: return "Preclinical / no completed human trials"
        case .precursorOffLabel: return "Precursor/topical evidence, injected off-label"
        }
    }

    /// Whether the app should surface the strong research-use disclaimer for this tier.
    public var needsStrongDisclaimer: Bool { self != .fdaApproved }
}
