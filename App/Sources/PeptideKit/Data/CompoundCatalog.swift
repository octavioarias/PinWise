import Foundation

/// Seed catalog of commonly tracked compounds with verified metadata.
///
/// Facts (evidence tier, regulatory status, half-life, WADA flag) are drawn from the
/// clinical research review — see
/// Knowledge/KnowledgeBase_v2/09_Clinical_Compound_Catalog_and_Safety_Data.md.
/// This data feeds presets and, importantly, the disclaimer/safety posture. It is
/// reference metadata for personal record-keeping — NOT dosing guidance. Requires
/// licensed-clinician review before shipping.
public enum CompoundCatalog {

    // Stable IDs so user protocols keep referring to the same catalog entry across launches.
    private static func id(_ s: String) -> UUID { UUID(uuidString: s)! }

    // MARK: GLP-1 / incretin (FDA-approved unless noted)

    public static let semaglutide = Compound(
        id: id("00000000-0000-0000-0000-000000000001"),
        name: "Semaglutide",
        aliases: ["Ozempic", "Wegovy", "Rybelsus", "Sema"],
        category: .glp1,
        regulatoryStatus: .fdaApproved,
        evidenceTier: .fdaApproved,
        preferredDoseUnit: .milligram,
        halfLifeHours: 168, // ~1 week; once-weekly SC
        notes: "FDA-approved (T2D/obesity). Compounded versions exist but are no longer covered by shortage enforcement discretion (2025)."
    )

    public static let tirzepatide = Compound(
        id: id("00000000-0000-0000-0000-000000000002"),
        name: "Tirzepatide",
        aliases: ["Mounjaro", "Zepbound", "Tirz"],
        category: .glp1,
        regulatoryStatus: .fdaApproved,
        evidenceTier: .fdaApproved,
        preferredDoseUnit: .milligram,
        halfLifeHours: 120, // ~5 days; once-weekly SC
        notes: "GIP/GLP-1 dual agonist. FDA-approved (T2D/obesity)."
    )

    public static let retatrutide = Compound(
        id: id("00000000-0000-0000-0000-000000000003"),
        name: "Retatrutide",
        aliases: ["LY3437943", "Reta"],
        category: .glp1,
        regulatoryStatus: .researchOnly,
        evidenceTier: .humanTrialsUnapproved,
        preferredDoseUnit: .milligram,
        halfLifeHours: 144, // ~6 days; once-weekly SC
        notes: "INVESTIGATIONAL — not FDA-approved as of 2026-07. Phase 3 TRIUMPH-1 positive topline (May 2026). Any preset is research-only, based on Phase 2 (NCT04881760: 1/4/8/12 mg weekly)."
    )

    // MARK: GH secretagogues

    public static let tesamorelin = Compound(
        id: id("00000000-0000-0000-0000-000000000004"),
        name: "Tesamorelin",
        aliases: ["Egrifta", "Egrifta SV", "Egrifta WR"],
        category: .growthHormoneSecretagogue,
        regulatoryStatus: .fdaApproved,
        evidenceTier: .fdaApproved,
        preferredDoseUnit: .milligram,
        halfLifeHours: 0.5, // ~26–38 min
        wadaProhibited: true,
        notes: "The ONLY FDA-approved molecule in the peptide stack (HIV-associated lipodystrophy). Labeled once-daily SC: Egrifta 2 mg / Egrifta SV 1.4 mg / Egrifta WR 1.28 mg."
    )

    public static let cjc1295DAC = Compound(
        id: id("00000000-0000-0000-0000-000000000005"),
        name: "CJC-1295 (DAC)",
        aliases: ["CJC-1295 with DAC", "DAC:GRF"],
        category: .growthHormoneSecretagogue,
        regulatoryStatus: .researchOnly,
        evidenceTier: .humanTrialsUnapproved,
        preferredDoseUnit: .milligram,
        halfLifeHours: 168, // ~6–8 days (drug affinity complex extends half-life)
        wadaProhibited: true,
        notes: "GHRH analog with Drug Affinity Complex. Long-acting; ~1–2 mg weekly in community use. Distinct from no-DAC."
    )

    public static let cjc1295NoDAC = Compound(
        id: id("00000000-0000-0000-0000-000000000006"),
        name: "CJC-1295 (no DAC)",
        aliases: ["Mod-GRF(1-29)", "Modified GRF 1-29", "CJC without DAC"],
        category: .growthHormoneSecretagogue,
        regulatoryStatus: .researchOnly,
        evidenceTier: .humanTrialsUnapproved,
        preferredDoseUnit: .microgram,
        halfLifeHours: 0.5, // ~30 min
        wadaProhibited: true,
        notes: "Short-acting GHRH analog; ~100–300 mcg 1–3×/day in community use. Distinct from the DAC version."
    )

    public static let ipamorelin = Compound(
        id: id("00000000-0000-0000-0000-000000000007"),
        name: "Ipamorelin",
        aliases: ["Ipa"],
        category: .growthHormoneSecretagogue,
        regulatoryStatus: .researchOnly,
        evidenceTier: .humanTrialsUnapproved,
        preferredDoseUnit: .microgram,
        halfLifeHours: 2,
        wadaProhibited: true,
        notes: "Ghrelin-receptor/GH secretagogue. Per FDA it is 503A Category 1 — a different status than the 12 peptides removed from Category 2 in April 2026."
    )

    // MARK: Healing / recovery (preclinical)

    public static let bpc157 = Compound(
        id: id("00000000-0000-0000-0000-000000000008"),
        name: "BPC-157",
        aliases: ["Body Protection Compound-157", "BPC"],
        category: .healingRecovery,
        regulatoryStatus: .researchOnly,
        evidenceTier: .preclinicalOrFailed,
        preferredDoseUnit: .microgram,
        halfLifeHours: 0.4, // sub-30-min plasma half-life
        wadaProhibited: true,
        notes: "No completed Phase II trial; human data from <30 subjects across uncontrolled studies. Removed from FDA 503A Category 2 (April 2026, procedural)."
    )

    public static let tb500 = Compound(
        id: id("00000000-0000-0000-0000-000000000009"),
        name: "TB-500",
        aliases: ["Thymosin Beta-4 fragment", "TB4 fragment", "Ac-LKKTETQ"],
        category: .healingRecovery,
        regulatoryStatus: .researchOnly,
        evidenceTier: .preclinicalOrFailed,
        preferredDoseUnit: .milligram,
        halfLifeHours: nil, // poorly characterized in humans
        wadaProhibited: true,
        notes: "CORRECTION: TB-500 is the synthetic Ac-LKKTETQ fragment, NOT full-length thymosin β-4. Preclinical only. WADA-prohibited."
    )

    // MARK: Cosmetic / metabolic (precursor / topical evidence, injected off-label)

    public static let ghkCu = Compound(
        id: id("00000000-0000-0000-0000-00000000000a"),
        name: "GHK-Cu (injectable)",
        aliases: ["Copper peptide", "GHK copper"],
        category: .cosmeticLongevity,
        regulatoryStatus: .researchOnly,
        evidenceTier: .precursorOffLabel,
        preferredDoseUnit: .milligram,
        halfLifeHours: nil,
        notes: "Human evidence is largely for TOPICAL GHK-Cu; injectable use is off-label/unstudied."
    )

    public static let nadPlus = Compound(
        id: id("00000000-0000-0000-0000-00000000000b"),
        name: "NAD+",
        aliases: ["Nicotinamide adenine dinucleotide"],
        category: .metabolic,
        regulatoryStatus: .researchOnly,
        evidenceTier: .precursorOffLabel,
        preferredDoseUnit: .milligram,
        halfLifeHours: nil,
        notes: "CORRECTION: NAD+ is a dinucleotide, NOT a peptide. Injected doses are large (tens of mg) and often cause flushing/discomfort if pushed fast."
    )

    /// Everything, for seeding a searchable picker.
    public static let all: [Compound] = [
        semaglutide, tirzepatide, retatrutide,
        tesamorelin, cjc1295DAC, cjc1295NoDAC, ipamorelin,
        bpc157, tb500, ghkCu, nadPlus,
    ]
}
