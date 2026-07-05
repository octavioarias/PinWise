import SwiftUI
import SwiftData
import PeptideKit

/// Inventory panel — embedded inside the Protocols tab's NavigationStack. A vial is a
/// *formula* of one or more APIs (single-compound or a blend).
struct InventoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showBuilder = false

    /// Project a vial against a matching active protocol (matched on any of its APIs), else as-needed.
    private func schedule(for vial: StoredVial) -> DoseSchedule {
        protocols.first { p in p.isActive && p.compoundNames.contains(where: { vial.apiNames.contains($0) }) }?.schedule
            ?? DoseSchedule(kind: .asNeeded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PrimaryButton(title: "Add vial", systemImage: "plus") { showBuilder = true }

            if vials.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("No vials yet").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Text("Add a vial to track remaining doses, run-out date, cost per dose, and expiry. A vial can hold one API or several (a blend).")
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
                    Text(vial.displayName).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    if vial.isBlend { TagChip(text: "Blend", color: BrandColor.accentText) }
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
                    .accessibilityLabel("Record a used dose from \(vial.displayName)")
                }

                if let breakdown = vial.doseBreakdown() {
                    Text("Per shot: " + breakdown.map { "\($0.name) \($0.deliveredDose.displayString)" }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                }

                metaLine
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: Space.md) {
            if let mgml = vial.primaryConcentrationMgPerMl {
                Label(String(format: "%.2f mg/mL", mgml), systemImage: "drop")
            }
            if let days = projection.daysOfSupply, let out = projection.projectedRunOutDate {
                Label("~\(Int(days.rounded()))d · out \(out.formatted(.dateTime.month().day()))", systemImage: "calendar")
            }
            if let cpd = projection.costPerDose {
                Label(costText(cpd), systemImage: "dollarsign.circle")
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(BrandColor.textSecondary)
    }

    private func costText(_ d: Decimal) -> String {
        String(format: "$%.2f/dose", NSDecimalNumber(decimal: d).doubleValue)
    }
}

/// Add a vial by building its formula: one or more APIs (single-compound or a blend).
struct VialBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private struct APIEntry: Identifiable {
        let id = UUID()
        var compound: Compound
        var amountText: String
        var unit: MassUnit
    }

    @State private var label = ""
    @State private var entries: [APIEntry] = [APIEntry(compound: CompoundCatalog.semaglutide, amountText: "", unit: .milligram)]
    @State private var solventText = ""
    @State private var isPremixed = false
    @State private var doseText = ""
    @State private var doseUnit: MassUnit = .milligram
    @State private var costText = ""
    @State private var hasExpiration = false
    @State private var expiration = Date()

    private var validEntries: [APIEntry] { entries.filter { ($0.amountText as NSString).doubleValue > 0 } }
    private var canSave: Bool { !validEntries.isEmpty && (Double(doseText) ?? 0) > 0 }
    private var primaryName: String { entries.first?.compound.name ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        FieldRow("Nickname", hint: "Optional — e.g. \"Batch 3\" or \"Wolverine\".") {
                            TextField("Nickname", text: $label).pinwiseField()
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            Text("What's in the vial?").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            Text("One ingredient = a single-compound vial. Add more to make a blend.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)

                            ForEach($entries) { $entry in
                                VStack(spacing: Space.sm) {
                                    HStack {
                                        Picker("", selection: $entry.compound) {
                                            ForEach(CompoundCatalog.allSorted, id: \.id) { c in Text(c.name).tag(c) }
                                        }
                                        .pickerStyle(.menu).tint(BrandColor.accentText)
                                        Spacer()
                                        if entries.count > 1 {
                                            Button { entries.removeAll { $0.id == entry.id } } label: {
                                                Image(systemName: "minus.circle").foregroundStyle(BrandColor.textSecondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    HStack {
                                        TextField("Amount in vial", text: $entry.amountText).keyboardType(.decimalPad).pinwiseField()
                                        unitPicker($entry.unit)
                                    }
                                }
                                .padding(.bottom, Space.xs)
                            }

                            HStack {
                                Button { entries.append(APIEntry(compound: CompoundCatalog.bpc157, amountText: "", unit: .milligram)) } label: {
                                    Label("Add ingredient", systemImage: "plus").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Menu {
                                    ForEach(BlendPresets.all, id: \.id) { b in
                                        Button(b.name) { applyPreset(b) }
                                    }
                                } label: {
                                    Label("Use a blend preset", systemImage: "square.grid.2x2").font(.caption).foregroundStyle(BrandColor.accentText)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("How much liquid?", hint: "Water you added, or the amount in a pre-mixed vial. Leave blank if not mixed yet.") {
                                HStack {
                                    TextField("e.g. 2", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                                    Text("mL").foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            Toggle("Came pre-mixed from a pharmacy", isOn: $isPremixed).tint(BrandColor.accent)
                            FieldRow(primaryName.isEmpty ? "Dose per shot" : "Dose of \(primaryName) per shot",
                                     hint: entries.count > 1 ? "The rest of the blend scales with this." : "The dose you take each time.") {
                                HStack {
                                    TextField("e.g. 250", text: $doseText).keyboardType(.decimalPad).pinwiseField()
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
            .onAppear { if let first = entries.first { doseUnit = first.compound.preferredDoseUnit } }
        }
    }

    private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
        Picker("", selection: binding) {
            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(width: 120)
    }

    private func applyPreset(_ blend: Blend) {
        entries = blend.components.map { comp in
            let c = CompoundCatalog.all.first { $0.name == comp.name || $0.name.hasPrefix(comp.name) || $0.aliases.contains(comp.name) } ?? CompoundCatalog.bpc157
            let mg = comp.massPerVial.milligrams
            return APIEntry(compound: c, amountText: mg == mg.rounded() ? String(Int(mg)) : String(mg), unit: .milligram)
        }
        if label.isEmpty { label = blend.name }
    }

    private func save() {
        let apis = entries.compactMap { e -> VialAPI? in
            guard let amt = Double(e.amountText), amt > 0 else { return nil }
            return VialAPI(name: e.compound.name, massMicrograms: Mass(amt, e.unit).micrograms)
        }
        guard !apis.isEmpty, let pd = Double(doseText), pd > 0 else { return }
        let vial = StoredVial(
            label: label,
            apis: apis,
            solventVolumeMilliliters: Double(solventText) ?? 0,
            perDoseMicrograms: Mass(pd, doseUnit).micrograms,
            cost: Double(costText) ?? 0,
            expirationDate: hasExpiration ? expiration : nil,
            isPremixed: isPremixed
        )
        context.insert(vial)
        try? context.save()
        dismiss()
    }
}
