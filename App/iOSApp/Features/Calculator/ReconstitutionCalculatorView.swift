import SwiftUI
import SwiftData
import Observation
import PeptideKit

// NOTE: iOS-app source. Math delegates to the verified PeptideKit core. Pushed from ToolsView.

/// Observable state for the dose calculator. Two modes:
/// - **Reconstitute**: lyophilized powder + water (derives concentration).
/// - **Already mixed**: a known concentration (e.g. a compounded-pharmacy vial in mg/mL).
@MainActor
@Observable
final class DoseCalculatorViewModel {
    enum Mode: String, CaseIterable { case reconstitute = "Reconstitute", premixed = "Already mixed" }

    var mode: Mode = .reconstitute

    var vialMassText = "5"
    var vialMassUnit: MassUnit = .milligram
    var solventText = "2"

    var concentrationText = "2.5"
    /// Strength unit for the premixed concentration input + the Strength readout (mg/mL or mcg/mL).
    var concentrationUnit: MassUnit = .milligram
    var totalVolumeText = ""

    var doseText = "2.5"
    var doseUnit: MassUnit = .milligram
    var syringe: SyringeScale = .u100

    /// The domain result verbatim — `ReconstitutionResult` or `PreparedDoseResult`, both of
    /// which conform to `DoseDrawResult`. No view-local wrapper.
    private(set) var result: (any DoseDrawResult)?
    private(set) var errorMessage: String?

    func recalculate() {
        errorMessage = nil
        result = nil
        guard let dose = doseText.decimalValue else { errorMessage = "Enter a dose."; return }
        let desired = Mass(dose, doseUnit)
        do {
            switch mode {
            case .reconstitute:
                guard let vialMass = vialMassText.decimalValue, let solvent = solventText.decimalValue else {
                    errorMessage = "Enter the vial amount and water volume."; return
                }
                result = try ReconstitutionCalculator.calculate(
                    ReconstitutionInput(vialMass: Mass(vialMass, vialMassUnit),
                                        solventVolumeMilliliters: solvent, desiredDose: desired, syringe: syringe))
            case .premixed:
                guard let strength = concentrationText.decimalValue else {
                    errorMessage = "Enter the concentration (\(concentrationUnit.rawValue)/mL)."; return
                }
                let conc = Concentration(microgramsPerMilliliter: Mass(strength, concentrationUnit).micrograms)
                result = try DosingCalculator.draw(dose: desired, concentration: conc,
                                                   totalVolumeMilliliters: totalVolumeText.decimalValue, syringe: syringe)
            }
        } catch let e as ReconstitutionError {
            errorMessage = Self.message(for: e)
        } catch let e as DosingError {
            errorMessage = Self.message(for: e)
        } catch {
            errorMessage = "Something went wrong."
        }
    }

    private static func message(for error: ReconstitutionError) -> String {
        switch error {
        case .nonPositiveVialMass: return "Vial amount must be greater than zero."
        case .nonPositiveSolventVolume: return "Water volume must be greater than zero."
        case .nonPositiveDose: return "Dose must be greater than zero."
        case .doseExceedsVialContents: return "That dose is larger than the whole vial."
        }
    }
    private static func message(for error: DosingError) -> String {
        switch error {
        case .nonPositiveConcentration: return "Concentration must be greater than zero."
        case .nonPositiveDose: return "Dose must be greater than zero."
        case .nonPositiveVolume: return "Total volume must be greater than zero."
        }
    }
}

struct ReconstitutionCalculatorView: View {
    @State private var model = DoseCalculatorViewModel()
    /// Set when the chosen vial is a blend (2+ APIs) — drives the per-compound breakdown so this
    /// one tool covers a vial with one OR more compounds.
    @State private var selectedBlendVial: StoredVial?
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]

    /// What each compound in the selected blend delivers for the current draw: its concentration
    /// (mass ÷ water) × the computed draw volume. Reconstitute mode only (powder blends).
    private var blendBreakdown: [(name: String, dose: Mass)]? {
        guard let v = selectedBlendVial, v.apis.count > 1, model.mode == .reconstitute,
              let r = model.result, let vol = model.solventText.decimalValue, vol > 0 else { return nil }
        return v.apis.map { ($0.name, Mass(micrograms: $0.massMicrograms / vol * r.drawVolumeMilliliters)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Find out how much to draw into your syringe — for a single peptide or a blend vial.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Picker("", selection: $model.mode) {
                    Text("Powder + water").tag(DoseCalculatorViewModel.Mode.reconstitute)
                    Text("Pre-mixed").tag(DoseCalculatorViewModel.Mode.premixed)
                }
                .pickerStyle(.segmented)

                // Live readout ABOVE the inputs: the calculator recomputes on every
                // keystroke, and the top of the screen is the one region the decimal pad
                // can never cover. Always present — an em-dash hero when there's nothing
                // to show — so the form never bounces under the user's finger.
                DoseHeroCard(result: model.result, errorMessage: model.errorMessage, syringe: model.syringe, concentrationUnit: model.concentrationUnit)

                // For a blend vial, restate what that single draw delivers per compound.
                if let breakdown = blendBreakdown {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            MicroLabel("Each shot delivers")
                            ForEach(Array(breakdown.enumerated()), id: \.offset) { _, comp in
                                HStack {
                                    Text(comp.name).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                                    Spacer()
                                    Text(comp.dose.displayString(in: selectedBlendVial?.doseUnit ?? .milligram))
                                        .font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                                }
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        if !vials.isEmpty {
                            Menu {
                                ForEach(vials) { v in Button(v.displayName) { applyVial(v) } }
                            } label: {
                                Label("Use one of your vials", systemImage: "cross.vial")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandColor.accentText)
                                    .lineLimit(1)
                            }
                        }
                        if model.mode == .reconstitute {
                            FieldRow("How much peptide is in the vial?", hint: "The amount printed on the vial label.") {
                                HStack {
                                    TextField("e.g. 5", text: $model.vialMassText).keyboardType(.decimalPad).pinwiseField()
                                    MassUnitPicker(selection: $model.vialMassUnit)
                                }
                            }
                            FieldRow("How much water did you add?", hint: "The bacteriostatic or sterile water you mixed in.") {
                                HStack {
                                    TextField("e.g. 2", text: $model.solventText).keyboardType(.decimalPad).pinwiseField()
                                    Text("mL").foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                        } else {
                            FieldRow("What's the concentration?", hint: "On the pharmacy label, e.g. 2.5 mg/mL.") {
                                HStack {
                                    TextField("e.g. 2.5", text: $model.concentrationText).keyboardType(.decimalPad).pinwiseField()
                                    MassUnitPicker(selection: $model.concentrationUnit)
                                    Text("/mL").foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            FieldRow("Vial size (optional)", hint: "Total liquid in the vial — lets us estimate how many doses it holds.") {
                                HStack {
                                    TextField("e.g. 4", text: $model.totalVolumeText).keyboardType(.decimalPad).pinwiseField()
                                    Text("mL").foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                        }
                        FieldRow("What dose do you want?", hint: "The dose you're aiming for this injection.") {
                            HStack {
                                TextField("e.g. 2.5", text: $model.doseText).keyboardType(.decimalPad).pinwiseField()
                                MassUnitPicker(selection: $model.doseUnit)
                            }
                        }
                    }
                }

                SyringeAdvancedCard(selection: $model.syringe)

                // Dilution education, demoted from the old result card to a screen footnote.
                Text("Doses depend on the peptide amount and your dose — not the water. More water just dilutes it, so you draw a larger volume for the same dose.")
                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: model.mode)
        .sensoryFeedback(.selection, trigger: model.vialMassUnit)
        .sensoryFeedback(.selection, trigger: model.concentrationUnit)
        .sensoryFeedback(.selection, trigger: model.doseUnit)
        .sensoryFeedback(.selection, trigger: model.syringe)
        .heroScreen()
        .navigationTitle("Dose calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.recalculate() }
        .onChange(of: model.mode) { _, _ in model.recalculate() }
        .onChange(of: model.vialMassText) { _, _ in model.recalculate() }
        .onChange(of: model.solventText) { _, _ in model.recalculate() }
        .onChange(of: model.concentrationText) { _, _ in model.recalculate() }
        .onChange(of: model.concentrationUnit) { _, _ in model.recalculate() }
        .onChange(of: model.totalVolumeText) { _, _ in model.recalculate() }
        .onChange(of: model.doseText) { _, _ in model.recalculate() }
        .onChange(of: model.vialMassUnit) { _, _ in model.recalculate() }
        .onChange(of: model.doseUnit) { _, _ in model.recalculate() }
        .onChange(of: model.syringe) { _, _ in model.recalculate() }
    }

    /// Prefills the form from a stored vial. Premixed vials with a recoverable label
    /// strength land in premixed mode; everything else (including legacy premixed rows
    /// with no solvent volume) prefills reconstitute mode. The existing `.onChange`
    /// wiring recalculates automatically.
    private func applyVial(_ v: StoredVial) {
        // Remember whether this is a blend so the per-compound breakdown shows (cleared for singles).
        selectedBlendVial = v.apis.count > 1 ? v : nil
        // Open the dose + concentration in the vial's chosen units, so this calc agrees with the
        // vial's Stack row instead of always reading mg/mL.
        model.doseUnit = v.doseUnit
        model.concentrationUnit = v.concentrationUnit
        if v.isPremixed, let mgPerMl = v.primaryConcentrationMgPerMl {
            model.mode = .premixed
            // Fill the strength in the vial's concentration unit (mgPerMl → mg/mL or mcg/mL).
            model.concentrationText = Self.numberText(Mass(mgPerMl, .milligram).value(in: v.concentrationUnit))
            model.totalVolumeText = v.solventVolumeMilliliters.map(Self.numberText) ?? ""
        } else {
            model.mode = .reconstitute
            if let api = v.primaryAPI {
                if api.massMicrograms >= 1_000 {
                    model.vialMassUnit = .milligram
                    model.vialMassText = Self.numberText(api.massMicrograms / 1_000)
                } else {
                    model.vialMassUnit = .microgram
                    model.vialMassText = Self.numberText(api.massMicrograms)
                }
            }
            if let vol = v.solventVolumeMilliliters, vol > 0 {
                model.solventText = Self.numberText(vol)
            }
        }
        // Seed the target dose from the vial's per-dose (the anchor compound) so a blend's
        // per-compound breakdown reads sensibly the moment the vial is chosen.
        if v.apis.count > 1, let pd = v.perDoseMicrograms, pd > 0 {
            model.doseText = Self.numberText(Mass(micrograms: pd).value(in: v.doseUnit))
        }
    }

    /// Int-if-whole else two decimals — mirrors Blend's `applyVial` formatting.
    private static func numberText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}

/// The always-present live readout: eyebrow → hero units figure → syringe gauge → a 3-up
/// stat strip (or the error message in the strip's slot, so the card never changes shape
/// per keystroke). Renders an em-dash hero and a 0-fill gauge when there's no result yet.
private struct DoseHeroCard: View {
    let result: (any DoseDrawResult)?
    let errorMessage: String?
    let syringe: SyringeScale
    /// Unit for the Strength readout — the model's concentration unit (seeded from a vial's chosen
    /// concentration unit when the form was opened from one), so it reads mg/mL or mcg/mL
    /// consistently with that vial's Stack row.
    var concentrationUnit: MassUnit = .milligram

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                MicroLabel("Draw to")
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(result.map { fmt($0.syringeUnits) } ?? "—")
                        .font(Typo.numberXL)
                        .foregroundStyle(BrandColor.accentText)
                        .contentTransition(.numericText(value: result?.syringeUnits ?? 0))
                        // Short per-keystroke roll — an appearance reveal would lag live edits.
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: result?.syringeUnits)
                    Text("units")
                        .font(Typo.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                SyringeGauge(units: result?.syringeUnits ?? 0, syringe: syringe)

                if let errorMessage {
                    HStack(alignment: .top, spacing: Space.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                    }
                    .font(.caption)
                    .foregroundStyle(BrandColor.warning)
                } else {
                    HStack(alignment: .top, spacing: Space.md) {
                        StatTile(label: "Volume",
                                 value: result.map { String(format: "%.2f mL", $0.drawVolumeMilliliters) } ?? "—",
                                 compact: true)
                        StatTile(label: "Strength",
                                 value: result.map { "\(fmtConc($0.concentrationMcgPerMl, in: concentrationUnit)) \(concentrationUnit.rawValue)/mL" } ?? "—",
                                 compact: true)
                        StatTile(label: "Doses/vial",
                                 value: (result?.exactDosesPerVialOrNil).map(fmt) ?? "—",
                                 compact: true)
                    }
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func fmtConc(_ mcgPerMl: Double, in unit: MassUnit) -> String {
        let perMl = mcgPerMl / unit.microgramsPerUnit
        if perMl == perMl.rounded() { return String(Int(perMl)) }
        let s = String(format: "%.2f", perMl)
        return s.hasSuffix("0") ? String(s.dropLast()) : s   // 2.50 → "2.5", 2.55 stays
    }
}
