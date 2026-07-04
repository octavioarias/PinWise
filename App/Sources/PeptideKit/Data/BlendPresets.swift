import Foundation

/// Common community "blend" vials seeded as presets. Component masses reflect the most
/// widely sold formulations; users can edit. Blends are research-only and mostly
/// preclinical — see the clinical catalog doc.
public enum BlendPresets {

    /// "Wolverine" — BPC-157 10 mg + TB-500 10 mg per vial.
    public static let wolverine = Blend(
        name: "Wolverine (BPC-157 + TB-500)",
        components: [
            BlendComponent(name: "BPC-157", massPerVial: .mg(10)),
            BlendComponent(name: "TB-500", massPerVial: .mg(10)),
        ],
        notes: "Research-only; both components are preclinical and WADA-prohibited."
    )

    /// "GLOW" — GHK-Cu 50 mg + TB-500 10 mg + BPC-157 10 mg per vial.
    public static let glow = Blend(
        name: "GLOW (GHK-Cu + TB-500 + BPC-157)",
        components: [
            BlendComponent(name: "GHK-Cu", massPerVial: .mg(50)),
            BlendComponent(name: "TB-500", massPerVial: .mg(10)),
            BlendComponent(name: "BPC-157", massPerVial: .mg(10)),
        ],
        notes: "Research-only. One injection volume sets all three component doses at once."
    )

    public static let all: [Blend] = [wolverine, glow]
}
