import Foundation

/// Common community "blend" vials seeded as presets. Component masses reflect widely sold
/// formulations; users can edit. Blends are research-only and mostly preclinical — see the
/// clinical catalog doc. Component names match catalog compound names so builders can link them.
public enum BlendPresets {

    /// "Wolverine" — the classic recovery pair.
    public static let wolverine = Blend(
        name: "Wolverine (BPC-157 + TB-500)",
        components: [
            BlendComponent(name: "BPC-157", massPerVial: .mg(10)),
            BlendComponent(name: "TB-500", massPerVial: .mg(10)),
        ],
        notes: "Research-only; both components are preclinical and WADA-prohibited."
    )

    /// "GLOW" — recovery/skin blend.
    public static let glow = Blend(
        name: "GLOW (GHK-Cu + BPC-157 + TB-500)",
        components: [
            BlendComponent(name: "GHK-Cu", massPerVial: .mg(50)),
            BlendComponent(name: "BPC-157", massPerVial: .mg(10)),
            BlendComponent(name: "TB-500", massPerVial: .mg(10)),
        ],
        notes: "Research-only. One injection volume sets all three component doses at once."
    )

    /// "KLOW" — GLOW plus KPV; a widely-cited "super healing" blend.
    public static let klow = Blend(
        name: "KLOW (GHK-Cu + KPV + BPC-157 + TB-500)",
        components: [
            BlendComponent(name: "GHK-Cu", massPerVial: .mg(50)),
            BlendComponent(name: "KPV", massPerVial: .mg(10)),
            BlendComponent(name: "BPC-157", massPerVial: .mg(10)),
            BlendComponent(name: "TB-500", massPerVial: .mg(10)),
        ],
        notes: "Research-only; all components preclinical. KLOW = GLOW + KPV."
    )

    /// The classic GH-secretagogue pairing.
    public static let cjcIpamorelin = Blend(
        name: "CJC-1295 + Ipamorelin",
        components: [
            BlendComponent(name: "CJC-1295 (no DAC)", massPerVial: .mg(5)),
            BlendComponent(name: "Ipamorelin", massPerVial: .mg(5)),
        ],
        notes: "Common GHRH + ghrelin-mimetic combo. Research-only; WADA-prohibited."
    )

    /// GHRH + ghrelin-mimetic GH combo.
    public static let sermorelinIpamorelin = Blend(
        name: "Sermorelin + Ipamorelin",
        components: [
            BlendComponent(name: "Sermorelin", massPerVial: .mg(5)),
            BlendComponent(name: "Ipamorelin", massPerVial: .mg(5)),
        ],
        notes: "Common GH-secretagogue pairing. Research-only; WADA-prohibited."
    )

    /// Investigational amylin + GLP-1 combination.
    public static let cagriSema = Blend(
        name: "CagriSema (Cagrilintide + Semaglutide)",
        components: [
            BlendComponent(name: "Cagrilintide", massPerVial: .mg(10)),
            BlendComponent(name: "Semaglutide", massPerVial: .mg(10)),
        ],
        notes: "INVESTIGATIONAL amylin + GLP-1 combo (roughly 1:1). Not FDA-approved."
    )

    public static let all: [Blend] = [
        wolverine, glow, klow, cjcIpamorelin, sermorelinIpamorelin, cagriSema,
    ]
}
