import SwiftUI
import SwiftData
import PeptideKit

/// Inventory panel — embedded inside the Stack tab's NavigationStack. A vial is a
/// *formula* of one or more APIs (single-compound or a blend). Tap a vial to edit it.
struct InventoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showBuilder = false
    @State private var editTarget: EditTarget?
    /// Identifiable wrapper so a tapped vial can drive `.sheet(item:)` (same pattern as protocols).
    private struct EditTarget: Identifiable { let id = UUID(); let vial: StoredVial }

    /// Project a vial against its protocol. Prefer the protocol explicitly LINKED to this vial
    /// (ProtocolItem.vialID), and only fall back to a compound-name match when nothing is linked.
    private func schedule(for vial: StoredVial) -> DoseSchedule {
        let linked = protocols.first { $0.isActive && $0.items.contains { $0.vialID == vial.id } }
        let named = protocols.first { $0.isActive && $0.compoundNames.contains { vial.apiNames.contains($0) } }
        return (linked ?? named)?.schedule ?? DoseSchedule(kind: .asNeeded)
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
                    Button { editTarget = EditTarget(vial: vial) } label: {
                        VialRow(vial: vial, projection: vial.projection(schedule: schedule(for: vial)))
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button { editTarget = EditTarget(vial: vial) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { context.delete(vial) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            NavigationLink { CompoundsView() } label: {
                HStack {
                    Image(systemName: "books.vertical.fill").foregroundStyle(BrandColor.accentText)
                    Text("Compound library").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                .padding(Space.lg)
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showBuilder) { VialBuilderView() }
        .sheet(item: $editTarget) { VialBuilderView(editing: $0.vial) }
    }
}

struct VialRow: View {
    let vial: StoredVial
    let projection: InventoryEstimator.Projection

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
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                }

                ProgressView(value: vial.fractionRemaining).tint(barColor)

                Text("\(projection.wholeDosesRemaining) of \(vial.totalDoses) doses left · log a dose to draw down")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)

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

/// Add or edit a vial by building its formula: one or more APIs (single-compound or a blend).
/// Pre-mixed vials are entered the way the label reads — strength (mg/mL) + volume; powder
/// vials as total mass + the volume you mix in.
struct VialBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomCompound.name) private var customCompounds: [CustomCompound]

    private struct APIEntry: Identifiable {
        let id = UUID()
        var compound: Compound
        /// Powder: total mass in `unit`. Pre-mixed: label strength in mg/mL.
        var amountText: String
        var unit: MassUnit
    }

    private let editing: StoredVial?

    @State private var label: String
    @State private var entries: [APIEntry]
    @State private var solventText: String
    @State private var isPremixed: Bool
    @State private var doseText: String
    @State private var doseUnit: MassUnit
    @State private var costText: String
    @State private var hasExpiration: Bool
    @State private var expiration: Date
    @State private var showScanner = false

    init(editing: StoredVial? = nil) {
        self.editing = editing
        guard let v = editing else {
            _label = State(initialValue: "")
            _entries = State(initialValue: [APIEntry(compound: CompoundCatalog.semaglutide, amountText: "", unit: .milligram)])
            _solventText = State(initialValue: "")
            _isPremixed = State(initialValue: false)
            _doseText = State(initialValue: "")
            _doseUnit = State(initialValue: .milligram)
            _costText = State(initialValue: "")
            _hasExpiration = State(initialValue: false)
            _expiration = State(initialValue: Date())
            return
        }
        let vol = v.solventVolumeMilliliters
        _label = State(initialValue: v.label)
        _isPremixed = State(initialValue: v.isPremixed)
        _solventText = State(initialValue: vol > 0 ? Self.fmt(vol) : "")
        _entries = State(initialValue: v.apis.map { api in
            if v.isPremixed && vol > 0 {
                // Back out the label strength from the stored total mass.
                return APIEntry(compound: Self.resolve(api.name),
                                amountText: Self.fmt((api.massMicrograms / 1_000) / vol),
                                unit: .milligram)
            }
            let unit: MassUnit = api.massMicrograms >= 1_000 ? .milligram : .microgram
            return APIEntry(compound: Self.resolve(api.name),
                            amountText: Self.fmt(Mass(micrograms: api.massMicrograms).value(in: unit)),
                            unit: unit)
        })
        let du: MassUnit = v.perDoseMicrograms >= 1_000 ? .milligram : .microgram
        _doseUnit = State(initialValue: du)
        _doseText = State(initialValue: v.perDoseMicrograms > 0 ? Self.fmt(v.perDose.value(in: du)) : "")
        _costText = State(initialValue: v.cost > 0 ? Self.fmt(v.cost) : "")
        _hasExpiration = State(initialValue: v.expirationDate != nil)
        _expiration = State(initialValue: v.expirationDate ?? Date())
    }

    /// Catalog + the user's own compounds, one alphabetical list for the ingredient picker.
    private var allCompounds: [Compound] {
        (CompoundCatalog.allSorted + customCompounds.map(\.asCompound))
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var validEntries: [APIEntry] { entries.filter { ($0.amountText as NSString).doubleValue > 0 } }
    private var canSave: Bool {
        guard !validEntries.isEmpty, (Double(doseText) ?? 0) > 0 else { return false }
        // Pre-mixed math needs the volume: total content = strength × mL.
        return !isPremixed || (Double(solventText) ?? 0) > 0
    }
    private var primaryName: String { entries.first?.compound.name ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        FieldRow("Nickname (optional)", hint: "What you'll see everywhere — e.g. \"GLOW\" or \"Wolverine 3/3\".") {
                            TextField("GLOW", text: $label).pinwiseField()
                        }
                    }

                    Picker("", selection: $isPremixed) {
                        Text("Pre-mixed").tag(true)
                        Text("Powder").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(isPremixed ? "Ready-to-use liquid from a pharmacy — enter it the way the label reads." : "A powder you mix with water yourself.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isPremixed {
                        Button { showScanner = true } label: {
                            Label("Scan the pharmacy label", systemImage: "text.viewfinder")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                                .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                                .foregroundStyle(BrandColor.accentText)
                        }
                        .buttonStyle(.plain)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            Text("What's in the vial?").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            Text(isPremixed
                                 ? "Enter each ingredient's strength from the label. One ingredient = a single-compound vial; add more for a blend."
                                 : "One ingredient = a single-compound vial. Add more to make a blend.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)

                            ForEach($entries) { $entry in
                                VStack(spacing: Space.sm) {
                                    HStack {
                                        Picker("", selection: $entry.compound) {
                                            ForEach(allCompounds, id: \.id) { c in Text(c.name).tag(c) }
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
                                    if isPremixed {
                                        HStack {
                                            TextField("Strength", text: $entry.amountText).keyboardType(.decimalPad).pinwiseField()
                                            Text("mg/mL").foregroundStyle(BrandColor.textSecondary)
                                        }
                                    } else {
                                        HStack {
                                            TextField("Amount in vial", text: $entry.amountText).keyboardType(.decimalPad).pinwiseField()
                                            unitPicker($entry.unit)
                                        }
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
                                if !isPremixed {
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
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Liquid volume",
                                     hint: isPremixed ? "Total mL in the vial (from the label)." : "Total mL once mixed — more liquid means more dilute.") {
                                HStack {
                                    TextField("e.g. 2", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                                    Text("mL").foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            FieldRow(primaryName.isEmpty ? "Dose per shot" : "Dose of \(primaryName) per shot",
                                     hint: entries.count > 1 ? "The rest of the blend scales with this." : "The dose you intend to inject each time.") {
                                HStack {
                                    TextField("e.g. 2.5", text: $doseText).keyboardType(.decimalPad).pinwiseField()
                                    unitPicker($doseUnit)
                                }
                            }
                        }
                    }

                    Card {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: Space.lg) {
                                Toggle("Add an expiration date", isOn: $hasExpiration).tint(BrandColor.accent)
                                if hasExpiration {
                                    FieldRow("Expires") {
                                        DatePicker("", selection: $expiration, displayedComponents: [.date]).labelsHidden()
                                    }
                                }
                                FieldRow("Cost", hint: "Optional — shows cost per dose.") {
                                    HStack {
                                        Text("$").foregroundStyle(BrandColor.textSecondary)
                                        TextField("e.g. 200", text: $costText).keyboardType(.decimalPad).pinwiseField()
                                    }
                                }
                            }
                            .padding(.top, Space.sm)
                        } label: {
                            Text("Optional — expiry & cost").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                        }
                        .tint(BrandColor.accentText)
                    }

                    PrimaryButton(title: editing == nil ? "Add vial" : "Save changes", systemImage: "checkmark") { save() }
                        .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle(editing == nil ? "New vial" : "Edit vial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if editing == nil, let first = entries.first { doseUnit = first.compound.preferredDoseUnit }
                // Custom compounds aren't queryable in init — re-resolve names against the full
                // list here so an edited vial's picker selection matches its option identity.
                entries = entries.map { e in
                    var e = e
                    if let match = allCompounds.first(where: { $0.name == e.compound.name }) { e.compound = match }
                    return e
                }
            }
            .sheet(isPresented: $showScanner) { LabelScannerView { applyScan($0) } }
        }
    }

    /// Fill the form from an on-device label scan (user confirmed). Everything stays editable.
    /// Only reachable in pre-mixed mode, so strength maps straight onto the entry field.
    private func applyScan(_ r: ScannedLabel) {
        guard !entries.isEmpty else { return }
        if let name = r.compoundName, let c = allCompounds.first(where: { $0.name == name }) {
            entries[0].compound = c
        }
        if let conc = r.concentrationMgPerMl {
            entries[0].amountText = Self.fmt(conc)
            entries[0].unit = .milligram
        }
        if let vol = r.volumeMl { solventText = Self.fmt(vol) }
        if let exp = r.expiration { hasExpiration = true; expiration = exp }
    }

    /// Bold unit chooser — the selected unit is accent-filled so the mg default is obvious.
    private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
        HStack(spacing: 4) {
            ForEach(MassUnit.allCases, id: \.self) { u in
                Button { binding.wrappedValue = u } label: {
                    Text(u.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                        .frame(minWidth: 46)
                        .background(binding.wrappedValue == u ? BrandColor.accent : BrandColor.surfaceElevated, in: Capsule())
                        .foregroundStyle(binding.wrappedValue == u ? BrandColor.onAccent : BrandColor.textSecondary)
                        .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: binding.wrappedValue == u ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applyPreset(_ blend: Blend) {
        entries = blend.components.map { comp in
            let c = CompoundCatalog.all.first { $0.name == comp.name || $0.name.hasPrefix(comp.name) || $0.aliases.contains(comp.name) } ?? CompoundCatalog.bpc157
            return APIEntry(compound: c, amountText: Self.fmt(comp.massPerVial.milligrams), unit: .milligram)
        }
        if label.isEmpty { label = blend.name }
    }

    private func save() {
        let vol = Double(solventText) ?? 0
        let apis = entries.compactMap { e -> VialAPI? in
            guard let amt = Double(e.amountText), amt > 0 else { return nil }
            // Pre-mixed entries are label strength (mg/mL): total content = strength × volume.
            let micrograms = isPremixed ? amt * vol * 1_000 : Mass(amt, e.unit).micrograms
            return VialAPI(name: e.compound.name, massMicrograms: micrograms)
        }
        guard !apis.isEmpty, let pd = Double(doseText), pd > 0, !isPremixed || vol > 0 else { return }
        let target = editing ?? StoredVial()
        target.label = label
        target.apis = apis
        target.solventVolumeMilliliters = vol
        target.perDoseMicrograms = Mass(pd, doseUnit).micrograms
        target.cost = Double(costText) ?? 0
        target.expirationDate = hasExpiration ? expiration : nil
        target.isPremixed = isPremixed
        if editing == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }

    private static func resolve(_ name: String) -> Compound {
        CompoundCatalog.all.first { $0.name == name }
            ?? Compound(name: name, category: .metabolic, regulatoryStatus: .researchOnly, evidenceTier: .preclinicalOrFailed)
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}
