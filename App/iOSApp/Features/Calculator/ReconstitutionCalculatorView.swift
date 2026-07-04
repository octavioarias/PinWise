import SwiftUI
import Observation
import PeptideKit

// NOTE: iOS-app source. Math delegates to the verified PeptideKit core. Pushed from ToolsView.

/// Shared, mode-agnostic result the view renders.
struct DoseDisplay: Equatable {
    let units: Double
    let volumeMilliliters: Double
    let concentrationMcgPerMl: Double
    let dosesPerVial: Int?
}

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
    var totalVolumeText = ""

    var doseText = "250"
    var doseUnit: MassUnit = .microgram
    var syringe: SyringeScale = .u100

    private(set) var result: DoseDisplay?
    private(set) var errorMessage: String?

    func recalculate() {
        errorMessage = nil
        result = nil
        guard let dose = Double(doseText) else { errorMessage = "Enter a dose."; return }
        let desired = Mass(dose, doseUnit)
        do {
            switch mode {
            case .reconstitute:
                guard let vialMass = Double(vialMassText), let solvent = Double(solventText) else {
                    errorMessage = "Enter the vial amount and water volume."; return
                }
                let r = try ReconstitutionCalculator.calculate(
                    ReconstitutionInput(vialMass: Mass(vialMass, vialMassUnit),
                                        solventVolumeMilliliters: solvent, desiredDose: desired, syringe: syringe))
                result = DoseDisplay(units: r.syringeUnits, volumeMilliliters: r.drawVolumeMilliliters,
                                     concentrationMcgPerMl: r.concentrationMcgPerMl, dosesPerVial: r.dosesPerVial)
            case .premixed:
                guard let mgPerMl = Double(concentrationText) else {
                    errorMessage = "Enter the concentration (mg/mL)."; return
                }
                let r = try DosingCalculator.draw(dose: desired, concentration: .mgPerMl(mgPerMl),
                                                  totalVolumeMilliliters: Double(totalVolumeText), syringe: syringe)
                result = DoseDisplay(units: r.syringeUnits, volumeMilliliters: r.drawVolumeMilliliters,
                                     concentrationMcgPerMl: r.concentrationMcgPerMl, dosesPerVial: r.dosesPerVial)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Find out how much to draw into your syringe.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Picker("", selection: $model.mode) {
                    Text("Powder + water").tag(DoseCalculatorViewModel.Mode.reconstitute)
                    Text("Pre-mixed").tag(DoseCalculatorViewModel.Mode.premixed)
                }
                .pickerStyle(.segmented)

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        if model.mode == .reconstitute {
                            FieldRow("How much peptide is in the vial?", hint: "The amount printed on the vial label.") {
                                HStack {
                                    TextField("e.g. 5", text: $model.vialMassText).keyboardType(.decimalPad).pinwiseField()
                                    unitPicker($model.vialMassUnit)
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
                                    Text("mg/mL").foregroundStyle(BrandColor.textSecondary)
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
                                TextField("e.g. 250", text: $model.doseText).keyboardType(.decimalPad).pinwiseField()
                                unitPicker($model.doseUnit)
                            }
                        }
                    }
                }

                advancedCard
                if let r = model.result { resultCard(r) }
                if let error = model.errorMessage { errorCard(error) }
                DisclaimerBanner(text: Disclaimer.calculator)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("How much to draw")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.recalculate() }
        .onChange(of: model.mode) { _, _ in model.recalculate() }
        .onChange(of: model.vialMassText) { _, _ in model.recalculate() }
        .onChange(of: model.solventText) { _, _ in model.recalculate() }
        .onChange(of: model.concentrationText) { _, _ in model.recalculate() }
        .onChange(of: model.totalVolumeText) { _, _ in model.recalculate() }
        .onChange(of: model.doseText) { _, _ in model.recalculate() }
        .onChange(of: model.vialMassUnit) { _, _ in model.recalculate() }
        .onChange(of: model.doseUnit) { _, _ in model.recalculate() }
        .onChange(of: model.syringe) { _, _ in model.recalculate() }
    }

    private var advancedCard: some View {
        Card {
            DisclosureGroup {
                Picker("Syringe type", selection: $model.syringe) {
                    ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Most insulin syringes are U-100. Only change this if yours says otherwise.")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary).padding(.top, Space.xs)
            } label: {
                Text("Advanced — syringe type").font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            .tint(BrandColor.accentText)
        }
    }

    private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
        Picker("", selection: binding) {
            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(width: 120)
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private func resultCard(_ r: DoseDisplay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("DRAW TO").font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
                Text("\(fmt(r.units)) units")
                    .font(Typo.numberXL).foregroundStyle(BrandColor.accentText)
                Text("= \(String(format: "%.2f", r.volumeMilliliters)) mL on the syringe")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                if let doses = r.dosesPerVial {
                    Text("About \(doses) doses in this vial.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BrandColor.warning)
            Text(message).font(.footnote).foregroundStyle(BrandColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(BrandColor.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
