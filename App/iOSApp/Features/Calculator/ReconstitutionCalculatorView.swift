import SwiftUI
import Observation
import PeptideKit

// NOTE: iOS-app source for the Xcode project. Math delegates to the verified PeptideKit core.

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

    // Reconstitute inputs
    var vialMassText = "5"
    var vialMassUnit: MassUnit = .milligram
    var solventText = "2"

    // Pre-mixed inputs (concentration in mg/mL; total volume optional)
    var concentrationText = "2.5"
    var totalVolumeText = ""

    // Shared
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
                                        solventVolumeMilliliters: solvent, desiredDose: desired, syringe: syringe)
                )
                result = DoseDisplay(units: r.syringeUnits, volumeMilliliters: r.drawVolumeMilliliters,
                                     concentrationMcgPerMl: r.concentrationMcgPerMl, dosesPerVial: r.dosesPerVial)
            case .premixed:
                guard let mgPerMl = Double(concentrationText) else {
                    errorMessage = "Enter the concentration (mg/mL)."; return
                }
                let total = Double(totalVolumeText)   // optional
                let r = try DosingCalculator.draw(dose: desired, concentration: .mgPerMl(mgPerMl),
                                                  totalVolumeMilliliters: total, syringe: syringe)
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Dose calculator")
                        .font(Typo.displayL).textCase(.uppercase)
                        .foregroundStyle(BrandColor.textPrimary)
                        .minimumScaleFactor(0.7).lineLimit(1)

                    Picker("", selection: $model.mode) {
                        ForEach(DoseCalculatorViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if model.mode == .reconstitute { vialCard } else { concentrationCard }
                    doseCard
                    if let r = model.result { resultCard(r) }
                    if let error = model.errorMessage { errorCard(error) }
                    DisclaimerBanner(text: Disclaimer.calculator)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Tools")
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
    }

    private var vialCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Vial (powder)")
                HStack {
                    TextField("Amount", text: $model.vialMassText).keyboardType(.decimalPad).pinwiseField()
                    Picker("", selection: $model.vialMassUnit) {
                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 120)
                }
                HStack {
                    TextField("Bacteriostatic water", text: $model.solventText).keyboardType(.decimalPad).pinwiseField()
                    Text("mL").font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private var concentrationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Pre-mixed (from pharmacy)")
                HStack {
                    TextField("Concentration", text: $model.concentrationText).keyboardType(.decimalPad).pinwiseField()
                    Text("mg/mL").font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }
                HStack {
                    TextField("Total volume (optional)", text: $model.totalVolumeText).keyboardType(.decimalPad).pinwiseField()
                    Text("mL").font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }
                Text("Enter the strength printed on the label (e.g. 2.5 mg/mL). Total volume gives doses per vial.")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
        }
    }

    private var doseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Desired dose")
                HStack {
                    TextField("Dose", text: $model.doseText).keyboardType(.decimalPad).pinwiseField()
                    Picker("", selection: $model.doseUnit) {
                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 120)
                }
                Picker("Syringe", selection: $model.syringe) {
                    ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).tint(BrandColor.accentText)
            }
        }
    }

    private func resultCard(_ r: DoseDisplay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.lg) {
                SectionHeader(title: "Draw to")
                HStack(spacing: Space.lg) {
                    StatTile(label: "Syringe units", value: String(format: "%.1f", r.units), emphasized: true)
                    StatTile(label: "Volume", value: String(format: "%.3f mL", r.volumeMilliliters))
                }
                HStack(spacing: Space.lg) {
                    StatTile(label: "Concentration", value: String(format: "%.0f mcg/mL", r.concentrationMcgPerMl))
                    if let doses = r.dosesPerVial {
                        StatTile(label: "Doses / vial", value: "\(doses)")
                    } else {
                        StatTile(label: "Doses / vial", value: "—")
                    }
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
