import SwiftUI
import Observation
import PeptideKit

// NOTE: iOS-app source for the Xcode project. Math delegates to the verified PeptideKit core.

/// Observable state for the reconstitution calculator screen.
@MainActor
@Observable
final class ReconstitutionViewModel {
    var vialMassText: String = "5"
    var vialMassUnit: MassUnit = .milligram
    var solventText: String = "2"
    var doseText: String = "250"
    var doseUnit: MassUnit = .microgram
    var syringe: SyringeScale = .u100

    private(set) var result: ReconstitutionResult?
    private(set) var errorMessage: String?

    func recalculate() {
        errorMessage = nil
        result = nil
        guard let vialMass = Double(vialMassText),
              let solvent = Double(solventText),
              let dose = Double(doseText) else {
            errorMessage = "Enter numbers in all fields."
            return
        }
        let input = ReconstitutionInput(
            vialMass: Mass(vialMass, vialMassUnit),
            solventVolumeMilliliters: solvent,
            desiredDose: Mass(dose, doseUnit),
            syringe: syringe
        )
        do {
            result = try ReconstitutionCalculator.calculate(input)
        } catch let e as ReconstitutionError {
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
}

struct ReconstitutionCalculatorView: View {
    @State private var model = ReconstitutionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Reconstitution")
                        .font(Typo.displayL)
                        .textCase(.uppercase)
                        .foregroundStyle(BrandColor.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    vialCard
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
            .onChange(of: model.vialMassText) { _, _ in model.recalculate() }
            .onChange(of: model.solventText) { _, _ in model.recalculate() }
            .onChange(of: model.doseText) { _, _ in model.recalculate() }
            .onChange(of: model.vialMassUnit) { _, _ in model.recalculate() }
            .onChange(of: model.doseUnit) { _, _ in model.recalculate() }
            .onChange(of: model.syringe) { _, _ in model.recalculate() }
        }
    }

    private var vialCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Vial")
                HStack {
                    TextField("Amount", text: $model.vialMassText)
                        .keyboardType(.decimalPad)
                        .pinwiseField()
                    Picker("", selection: $model.vialMassUnit) {
                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                HStack {
                    TextField("Bacteriostatic water", text: $model.solventText)
                        .keyboardType(.decimalPad)
                        .pinwiseField()
                    Text("mL").font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private var doseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Desired dose")
                HStack {
                    TextField("Dose", text: $model.doseText)
                        .keyboardType(.decimalPad)
                        .pinwiseField()
                    Picker("", selection: $model.doseUnit) {
                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                Picker("Syringe", selection: $model.syringe) {
                    ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(BrandColor.accentText)
            }
        }
    }

    private func resultCard(_ r: ReconstitutionResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.lg) {
                SectionHeader(title: "Draw to")
                HStack(spacing: Space.lg) {
                    StatTile(label: "Syringe units", value: String(format: "%.1f", r.syringeUnits), emphasized: true)
                    StatTile(label: "Volume", value: String(format: "%.3f mL", r.drawVolumeMilliliters))
                }
                HStack(spacing: Space.lg) {
                    StatTile(label: "Concentration", value: String(format: "%.0f mcg/mL", r.concentrationMcgPerMl))
                    StatTile(label: "Doses / vial", value: "\(r.dosesPerVial)")
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
