import Foundation

/// Broad grouping used for UI organization and, importantly, for surfacing the
/// right safety/disclaimer posture (FDA-approved drugs vs. research-only peptides).
public enum CompoundCategory: String, Codable, CaseIterable, Sendable {
    case glp1 = "GLP-1 / incretin"
    case healingRecovery = "Healing / recovery"
    case growthHormoneSecretagogue = "GH secretagogue"
    case cosmeticLongevity = "Cosmetic / longevity"
    case metabolic = "Metabolic / other"
    case blend = "Blend"
}

/// Regulatory status drives which disclaimers and claim-restrictions the app must apply.
public enum RegulatoryStatus: String, Codable, Sendable {
    /// Has an FDA-approved product for at least one indication (e.g. semaglutide).
    case fdaApproved
    /// Available only as a compounded preparation (e.g. compounded tirzepatide).
    case compoundedOnly
    /// Sold as a "research chemical"; not approved for human use.
    case researchOnly
}

/// A substance the user can track. Not tied to a specific physical vial — see ``Vial``.
public struct Compound: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Alternate names / abbreviations users search by (e.g. "Tirz", "BPC").
    public var aliases: [String]
    public var category: CompoundCategory
    public var regulatoryStatus: RegulatoryStatus
    /// How much human evidence backs the compound — drives disclaimer strength.
    public var evidenceTier: EvidenceTier
    /// Preferred display unit for doses of this compound (GLP-1s in mg, most peptides in mcg).
    public var preferredDoseUnit: MassUnit
    /// Terminal half-life in hours, when a credible value exists (drives PK visualizations).
    public var halfLifeHours: Double?
    /// On the WADA Prohibited List (relevant to tested athletes).
    public var wadaProhibited: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        category: CompoundCategory,
        regulatoryStatus: RegulatoryStatus,
        evidenceTier: EvidenceTier,
        preferredDoseUnit: MassUnit = .milligram,
        halfLifeHours: Double? = nil,
        wadaProhibited: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.regulatoryStatus = regulatoryStatus
        self.evidenceTier = evidenceTier
        self.preferredDoseUnit = preferredDoseUnit
        self.halfLifeHours = halfLifeHours
        self.wadaProhibited = wadaProhibited
        self.notes = notes
    }

    /// Whether the app must present research-use / not-medical-advice framing prominently.
    public var requiresResearchDisclaimer: Bool {
        regulatoryStatus == .researchOnly || evidenceTier.needsStrongDisclaimer
    }
}
