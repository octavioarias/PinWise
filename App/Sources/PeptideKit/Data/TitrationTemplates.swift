import Foundation

/// A named, label-derived escalation template the user can APPLY to build a dated,
/// editable schedule. It is explicitly **not a recommendation** — the app renders the
/// FDA-labeled ladder as a starting calendar the user configures for their own records.
public struct TitrationTemplate: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let compoundName: String
    public let steps: [TitrationPlanner.Step]
    /// Steps at these (0-based) indices are label "initiation / dose-escalation" doses that
    /// are explicitly NOT intended as maintenance/therapeutic doses (surface a note in UI).
    public let initiationOnlyStepIndices: Set<Int>
    public let note: String

    public init(id: String, name: String, compoundName: String, steps: [TitrationPlanner.Step], initiationOnlyStepIndices: Set<Int> = [], note: String) {
        self.id = id
        self.name = name
        self.compoundName = compoundName
        self.steps = steps
        self.initiationOnlyStepIndices = initiationOnlyStepIndices
        self.note = note
    }
}

/// Label-exact GLP-1 escalation ladders as dated templates. Every ladder step is a
/// 4-week (28-day) phase per the products' labeling. NOT medical advice.
public enum TitrationTemplates {

    private static let disclaimer =
        "User-configurable template derived from the product's FDA label. Not a recommendation. Your clinician sets your actual schedule."

    /// Ozempic (semaglutide, T2D): 0.25 → 0.5 → (1) → (2) mg, ≥4 weeks per step.
    public static let ozempic = TitrationTemplate(
        id: "ozempic-t2d",
        name: "Ozempic (semaglutide) — T2D ladder",
        compoundName: "Semaglutide",
        steps: [
            .weeks(4, dose: .mg(0.25)),
            .weeks(4, dose: .mg(0.5)),
            .weeks(4, dose: .mg(1.0)),
            .weeks(4, dose: .mg(2.0)),
        ],
        initiationOnlyStepIndices: [0], // 0.25 mg is initiation-only, non-therapeutic
        note: disclaimer
    )

    /// Wegovy (semaglutide, obesity): 0.25 → 0.5 → 1.0 → 1.7 → 2.4 mg at weeks 1/5/9/13/17.
    public static let wegovy = TitrationTemplate(
        id: "wegovy-obesity",
        name: "Wegovy (semaglutide) — obesity ladder",
        compoundName: "Semaglutide",
        steps: [
            .weeks(4, dose: .mg(0.25)),
            .weeks(4, dose: .mg(0.5)),
            .weeks(4, dose: .mg(1.0)),
            .weeks(4, dose: .mg(1.7)),
            .weeks(4, dose: .mg(2.4)),
        ],
        initiationOnlyStepIndices: [0],
        note: disclaimer + " A 7.2 mg high-dose tier also exists."
    )

    /// Mounjaro / Zepbound (tirzepatide): 2.5 → 5 → 7.5 → 10 → 12.5 → 15 mg, +2.5 mg ≥4 weeks apart.
    public static let tirzepatide = TitrationTemplate(
        id: "tirzepatide-ladder",
        name: "Mounjaro / Zepbound (tirzepatide) ladder",
        compoundName: "Tirzepatide",
        steps: [
            .weeks(4, dose: .mg(2.5)),
            .weeks(4, dose: .mg(5.0)),
            .weeks(4, dose: .mg(7.5)),
            .weeks(4, dose: .mg(10.0)),
            .weeks(4, dose: .mg(12.5)),
            .weeks(4, dose: .mg(15.0)),
        ],
        initiationOnlyStepIndices: [0], // 2.5 mg is initiation-only, non-therapeutic
        note: disclaimer
    )

    public static let all: [TitrationTemplate] = [ozempic, wegovy, tirzepatide]
}
