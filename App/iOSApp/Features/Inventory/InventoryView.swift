import SwiftUI
import SwiftData
import PeptideKit

/// Inventory panel — embedded inside the Protocols tab's NavigationStack (no stack of its
/// own). Lists vials with supply bars, run-out/cost projections, and a quick "used a dose".
struct InventoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showBuilder = false

    /// The schedule to project a vial against: a matching active protocol, else as-needed.
    private func schedule(for vial: StoredVial) -> DoseSchedule {
        protocols.first { $0.isActive && $0.compoundName == vial.compoundName }?.schedule
            ?? DoseSchedule(kind: .asNeeded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PrimaryButton(title: "Add vial", systemImage: "plus") { showBuilder = true }

            if vials.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("No vials yet").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Text("Add a vial to track remaining doses, run-out date, cost per dose, and expiry.")
                            .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    }
                }
            } else {
                ForEach(vials, id: \.id) { vial in
                    VialRow(vial: vial, projection: vial.projection(schedule: schedule(for: vial)),
                            onUseDose: { useDose(vial) })
                        .contextMenu {
                            Button(role: .destructive) { context.delete(vial) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showBuilder) { VialBuilderView() }
    }

    private func useDose(_ vial: StoredVial) {
        vial.dosesTaken += 1
        try? context.save()
    }
}

struct VialRow: View {
    let vial: StoredVial
    let projection: InventoryEstimator.Projection
    let onUseDose: () -> Void

    private var barColor: Color {
        if projection.needsReorder { return BrandColor.danger }
        if vial.fractionRemaining < 0.5 { return BrandColor.warning }
        return BrandColor.success
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(vial.label.isEmpty ? vial.compoundName : vial.label)
                        .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Spacer()
                    if projection.needsReorder { TagChip(text: "Low", color: BrandColor.danger) }
                    if let e = vial.expiryState, (e.isWarning || e.isError) {
                        TagChip(text: e.isError ? "Expired" : "Expiring", color: e.isError ? BrandColor.danger : BrandColor.warning)
                    }
                }

                ProgressView(value: vial.fractionRemaining).tint(barColor)

                HStack {
                    Text("\(projection.wholeDosesRemaining) of \(vial.totalDoses) doses left")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    Spacer()
                    Button(action: onUseDose) {
                        Label("Used a dose", systemImage: "minus.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                    }
                    .buttonStyle(.plain)
                    .disabled(projection.wholeDosesRemaining <= 0)
                    .accessibilityLabel("Record a used dose from \(vial.compoundName)")
                }

                metaLine
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: Space.md) {
            if let mgml = vial.concentrationMgPerMl {
                Label(String(format: "%.2f mg/mL", mgml), systemImage: "drop")
            }
            if let days = projection.daysOfSupply, let out = projection.projectedRunOutDate {
                Label("~\(Int(days.rounded()))d · out \(out.formatted(.dateTime.month().day()))",
                      systemImage: "calendar")
            }
            if let cpd = projection.costPerDose {
                Label(costText(cpd), systemImage: "dollarsign.circle")
            }
            if let e = vial.expiryState, !e.isWarning, !e.isError {
                Label(e.label, systemImage: "hourglass")
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(BrandColor.textSecondary)
    }

    private func costText(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        return String(format: "$%.2f/dose", n)
    }
}

/// Add a vial. Presented as a sheet.
struct VialBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]

    @State private var compound: Compound = CompoundCatalog.semaglutide
    @State private var label = ""
    @State private var massText = ""
    @State private var massUnit: MassUnit = .milligram
    @State private var solventText = ""
    @State private var doseText = ""
    @State private var doseUnit: MassUnit = .microgram
    @State private var costText = ""
    @State private var hasExpiration = false
    @State private var expiration = Date()
    @State private var prep: Prep = .reconstituted
    @State private var concentrationText = ""
    @State private var totalVolumeText = ""
    private enum Prep: Hashable { case reconstituted, premixed }

    private var contentsValid: Bool {
        switch prep {
        case .reconstituted: return (Double(massText) ?? 0) > 0
        case .premixed: return (Double(concentrationText) ?? 0) > 0 && (Double(totalVolumeText) ?? 0) > 0
        }
    }
    private var canSave: Bool { contentsValid && (Double(doseText) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Which compound?") {
                                Picker("Compound", selection: $compound) {
                                    ForEach(CompoundCatalog.all, id: \.id) { c in Text(c.name).tag(c) }
                                }
                                .pickerStyle(.menu).tint(BrandColor.accentText)
                            }
                            FieldRow("Nickname", hint: "Optional — e.g. \"Batch 3\".") {
                                TextField("Nickname", text: $label).pinwiseField()
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("How did it come?", hint: "A powder you mix with water, or a ready-to-use liquid.") {
                                Picker("", selection: $prep) {
                                    Text("Powder").tag(Prep.reconstituted)
                                    Text("Pre-mixed").tag(Prep.premixed)
                                }
                                .pickerStyle(.segmented)
                            }
                            if prep == .reconstituted {
                                FieldRow("How much is in the vial?", hint: "The amount on the label.") {
                                    HStack {
                                        TextField("e.g. 10", text: $massText).keyboardType(.decimalPad).pinwiseField()
                                        unitPicker($massUnit)
                                    }
                                }
                                FieldRow("How much water did you add?") {
                                    HStack {
                                        TextField("e.g. 2", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                                        Text("mL").foregroundStyle(BrandColor.textSecondary)
                                    }
                                }
                            } else {
                                FieldRow("What's the concentration?", hint: "On the pharmacy label, e.g. 2.5 mg/mL.") {
                                    HStack {
                                        TextField("e.g. 2.5", text: $concentrationText).keyboardType(.decimalPad).pinwiseField()
                                        Text("mg/mL").foregroundStyle(BrandColor.textSecondary)
                                    }
                                }
                                FieldRow("How much liquid in the vial?", hint: "Total volume — lets us estimate doses.") {
                                    HStack {
                                        TextField("e.g. 4", text: $totalVolumeText).keyboardType(.decimalPad).pinwiseField()
                                        Text("mL").foregroundStyle(BrandColor.textSecondary)
                                    }
                                }
                            }
                            FieldRow("How much per dose?") {
                                HStack {
                                    TextField("e.g. 2.5", text: $doseText).keyboardType(.decimalPad).pinwiseField()
                                    unitPicker($doseUnit)
                                }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Cost", hint: "Optional — used to show cost per dose.") {
                                HStack {
                                    Text("$").foregroundStyle(BrandColor.textSecondary)
                                    TextField("e.g. 200", text: $costText).keyboardType(.decimalPad).pinwiseField()
                                }
                            }
                            Toggle("Has an expiration date", isOn: $hasExpiration).tint(BrandColor.accent)
                            if hasExpiration {
                                FieldRow("Expires") {
                                    DatePicker("", selection: $expiration, displayedComponents: [.date]).labelsHidden()
                                }
                            }
                        }
                    }

                    PrimaryButton(title: "Add vial", systemImage: "checkmark") { save() }
                        .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("New vial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { applyDefaults() }
            .onChange(of: compound) { _, _ in applyDefaults() }
        }
    }

    private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
        Picker("", selection: binding) {
            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(width: 120)
    }

    private func applyDefaults() {
        doseUnit = compound.preferredDoseUnit
        // Prefill per-dose from a matching active protocol, if any.
        if let p = protocols.first(where: { $0.isActive && $0.compoundName == compound.name }) {
            let v = p.dose.value(in: doseUnit)
            if doseText.isEmpty { doseText = v == v.rounded() ? String(Int(v)) : String(v) }
        }
    }

    private func save() {
        guard canSave, let d = Double(doseText), d > 0 else { return }

        let massMicrograms: Double
        let solventMilliliters: Double
        switch prep {
        case .reconstituted:
            massMicrograms = Mass(Double(massText) ?? 0, massUnit).micrograms
            solventMilliliters = Double(solventText) ?? 0
        case .premixed:
            let volume = Double(totalVolumeText) ?? 0
            massMicrograms = Concentration(mgPerMl: Double(concentrationText) ?? 0).microgramsPerMilliliter * volume
            solventMilliliters = volume
        }

        let vial = StoredVial(
            compoundName: compound.name,
            label: label,
            massMicrograms: massMicrograms,
            solventVolumeMilliliters: solventMilliliters,
            perDoseMicrograms: Mass(d, doseUnit).micrograms,
            cost: Double(costText) ?? 0,
            expirationDate: hasExpiration ? expiration : nil,
            isPremixed: prep == .premixed
        )
        context.insert(vial)
        try? context.save()
        dismiss()
    }
}
