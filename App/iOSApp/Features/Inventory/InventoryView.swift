import SwiftUI
import SwiftData
import PeptideKit

/// Inventory panel — embedded inside the Stack tab's NavigationStack. A vial is a
/// *formula* of one or more APIs (single-compound or a blend). Tap a vial to edit it.
struct InventoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    // Needed so a vial delete can null the soft `vialID` links on every dose that drew from it.
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var logs: [LoggedDose]
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
                    let projection = vial.projection(schedule: schedule(for: vial))
                    VStack(spacing: Space.sm) {
                        Button { editTarget = EditTarget(vial: vial) } label: {
                            VialRow(vial: vial, projection: projection)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button { editTarget = EditTarget(vial: vial) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) { vial.reconcileDelete(in: context, doses: logs, protocols: protocols) } label: {
                                Label("Depleted — remove", systemImage: "trash.slash")
                            }
                        }
                        // Empty (or expired) vials get a one-tap way out of the inventory.
                        if projection.wholeDosesRemaining == 0 || (vial.expiryState?.isError ?? false) {
                            Button(role: .destructive) { vial.reconcileDelete(in: context, doses: logs, protocols: protocols) } label: {
                                Label(projection.wholeDosesRemaining == 0 ? "Depleted — remove from inventory"
                                                                          : "Expired — remove from inventory",
                                      systemImage: "trash.slash")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Space.sm)
                            }
                            .foregroundStyle(BrandColor.danger)
                            .background(BrandColor.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        }
                    }
                }
            }

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
                    Spacer()
                    if projection.needsReorder { TagChip(text: "Low", color: BrandColor.danger) }
                    if let e = vial.expiryState, (e.isWarning || e.isError) {
                        TagChip(text: e.isError ? "Expired" : "Expiring", color: e.isError ? BrandColor.danger : BrandColor.warning)
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                }

                ProgressView(value: vial.fractionRemaining).tint(barColor)

                Text(supplyLine)
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)

                if let conc = vial.concentrationSummary {
                    Text(conc).font(.caption2.weight(.medium)).foregroundStyle(BrandColor.textPrimary)
                }

                if let perShot = vial.perShotSummary {
                    Text("Per shot: " + perShot)
                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                }

                metaLine

                // Advisory beyond-use line — soft, never disables the vial (per USP/community:
                // 28 days is a microbial-safety guideline, not a potency cliff).
                if let bud = projection.beyondUseDate {
                    Text(bud < Date()
                         ? "Past its 28-day discard guideline — inspect before use."
                         : "Discard guideline: \(bud.formatted(.dateTime.month().day())) · 28-day mixed-vial window")
                        .font(.caption2)
                        .foregroundStyle(bud < Date() ? BrandColor.warning : BrandColor.textSecondary)
                }
            }
        }
    }

    /// Doses line — shows doses left, but when the EXPIRATION date binds before the doses run out
    /// it shows how many are actually usable before it expires (the doses-vs-expiration synergy).
    private var supplyLine: String {
        let whole = projection.wholeDosesRemaining
        if projection.limitingFactor == .expiration, projection.usableWholeDoses < whole {
            return "\(projection.usableWholeDoses) of \(whole) doses usable before it expires"
        }
        return "\(whole) of \(vial.totalDoses) doses left"
    }

    private var metaLine: some View {
        HStack(spacing: Space.md) {
            if let end = projection.effectiveEndDate {
                let expires = projection.limitingFactor == .expiration
                Label(expires ? "expires \(end.formatted(.dateTime.month().day()))"
                              : "out \(end.formatted(.dateTime.month().day()))",
                      systemImage: expires ? "exclamationmark.circle" : "calendar")
                    .foregroundStyle(expires ? BrandColor.warning : BrandColor.textSecondary)
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
    // Needed to detach any logs/protocols that reference this vial before deleting it.
    @Query private var logs: [LoggedDose]
    @Query private var protocols: [SavedProtocol]
    @State private var showDeleteConfirm = false

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
    /// Strength unit for a pre-mixed vial: mg ⇒ mg/mL, mcg ⇒ mcg/mL.
    @State private var concentrationUnit: MassUnit
    @State private var costText: String
    @State private var hasExpiration: Bool
    @State private var expiration: Date
    @State private var expandExtras: Bool
    @State private var coaAssayText: String
    @State private var coaContentText: String
    @State private var coaPurityText: String
    /// Free-text notes on the vial (e.g. a scanned lot/batch number). Round-trips through save.
    @State private var notes: String
    @State private var showScanner = false
    @State private var showVoice = false
    /// Set for one cycle when a scan flips the pre-mixed/powder segment itself, so the
    /// `onChange(of: isPremixed)` unit converter doesn't re-scale the value the scan just wrote.
    @State private var suppressModeConversion = false
    /// The ingredient the user "doses by" in a blend — its dose is the number they type, and every
    /// other compound scales to it. nil = the first ingredient. Tracked by id so it survives
    /// add/remove/reorder.
    @State private var anchorID: UUID? = nil
    /// Set when a blend preset autofilled the nickname: the name it wrote + the formula it
    /// described. If the ingredients later diverge, the autofill is cleared (a "GLOW" label
    /// on a hand-rolled formula would be wrong) — unless the user typed their own name over it.
    @State private var appliedPreset: (label: String, names: [String])?

    /// USP guidance for multi-dose injectables: discard ~28 days after opening/reconstitution to
    /// limit bacterial or fungal growth. New vials default to this recommended beyond-use date
    /// (pre-filled and on); users can extend it.
    static let recommendedBeyondUseDays = 28

    init(editing: StoredVial? = nil) {
        self.editing = editing
        guard let v = editing else {
            _label = State(initialValue: "")
            _entries = State(initialValue: [APIEntry(compound: CompoundCatalog.semaglutide, amountText: "", unit: .milligram)])
            _solventText = State(initialValue: "")
            _isPremixed = State(initialValue: false)
            _doseText = State(initialValue: "")
            _doseUnit = State(initialValue: .milligram)
            _concentrationUnit = State(initialValue: .milligram)
            _costText = State(initialValue: "")
            // Default a new vial to the USP 28-day beyond-use date (recommended), pre-filled and on.
            _hasExpiration = State(initialValue: true)
            _expiration = State(initialValue: Calendar.current.date(byAdding: .day, value: Self.recommendedBeyondUseDays, to: Date()) ?? Date())
            _expandExtras = State(initialValue: true)
            _coaAssayText = State(initialValue: "")
            _coaContentText = State(initialValue: "")
            _coaPurityText = State(initialValue: "")
            _notes = State(initialValue: "")
            return
        }
        let vol = v.solventVolumeMilliliters ?? 0
        _label = State(initialValue: v.label)
        // A pre-mixed vial saved without a volume (older builds allowed it) has no derivable
        // strength — open it in powder mode so its total mass round-trips unchanged.
        _isPremixed = State(initialValue: v.isPremixed && vol > 0)
        _solventText = State(initialValue: vol > 0 ? Self.fmt(vol) : "")
        // Reopen a pre-mixed vial's strength in the unit it was entered in.
        let cu: MassUnit = v.concentrationUnit
        _concentrationUnit = State(initialValue: cu)
        _entries = State(initialValue: v.apis.map { api in
            if v.isPremixed && vol > 0 {
                // Back out the label strength (in the vial's concentration unit) from stored mass.
                return APIEntry(compound: Self.resolve(api.name),
                                amountText: Self.fmt((api.massMicrograms / cu.microgramsPerUnit) / vol),
                                unit: cu)
            }
            let unit: MassUnit = api.massMicrograms >= 1_000 ? .milligram : .microgram
            return APIEntry(compound: Self.resolve(api.name),
                            amountText: Self.fmt(Mass(micrograms: api.massMicrograms).value(in: unit)),
                            unit: unit)
        })
        let perDoseMcg = v.perDoseMicrograms ?? 0
        // Reopen the vial in the unit it was saved in (falls back to the magnitude heuristic for
        // legacy vials with no stored choice).
        let du: MassUnit = v.doseUnit
        _doseUnit = State(initialValue: du)
        _doseText = State(initialValue: perDoseMcg > 0 ? Self.fmt(v.perDose.value(in: du)) : "")
        // nil cost = unknown → empty field; a stored 0 = a genuine free/comped vial → shows "0".
        _costText = State(initialValue: v.cost.map { Self.fmt(NSDecimalNumber(decimal: $0).doubleValue) } ?? "")
        _hasExpiration = State(initialValue: v.expirationDate != nil)
        _expiration = State(initialValue: v.expirationDate ?? Date())
        _expandExtras = State(initialValue: v.expirationDate != nil)
        _coaAssayText = State(initialValue: v.coaAssayPercent.map(Self.fmt) ?? "")
        _coaContentText = State(initialValue: v.coaContentPercent.map(Self.fmt) ?? "")
        _coaPurityText = State(initialValue: v.coaPurityPercent.map(Self.fmt) ?? "")
        _notes = State(initialValue: v.notes)
    }

    /// Catalog + the user's own compounds, one alphabetical list for the ingredient picker.
    private var allCompounds: [Compound] {
        (CompoundCatalog.allSorted + customCompounds.map(\.asCompound))
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Picker options always include the entry's current compound — a vial can reference a
    /// custom compound that was later deleted, and its line must stay visible and intact.
    private func pickerOptions(including current: Compound) -> [Compound] {
        if allCompounds.contains(where: { $0.id == current.id }) { return allCompounds }
        return (allCompounds + [current]).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var validEntries: [APIEntry] { entries.filter { ($0.amountText.decimalValue ?? 0) > 0 } }
    private var canSave: Bool {
        guard !validEntries.isEmpty, (doseText.decimalValue ?? 0) > 0 else { return false }
        // Pre-mixed math needs the volume: total content = strength × mL.
        return !isPremixed || (solventText.decimalValue ?? 0) > 0
    }
    private var primaryName: String { entries.first?.compound.name ?? "" }

    /// The id that actually anchors the dose right now — the tapped one, or the first ingredient
    /// when unset / the anchored ingredient was removed.
    private var effectiveAnchorID: UUID? { (entries.first { $0.id == anchorID }?.id) ?? entries.first?.id }
    private var anchorEntry: APIEntry? { entries.first { $0.id == effectiveAnchorID } }
    /// The compound whose dose the user types ("dose by"); the rest scale to it.
    private var anchorName: String { anchorEntry?.compound.name ?? "" }

    /// For a multi-compound (blend) vial, what a single shot delivers of EACH compound. They share
    /// one solution, so the ANCHOR's dose fixes the rest by the mass ratio (the solvent cancels —
    /// no volume needed). Recomputed live as ingredients/dose/anchor change. nil unless there are
    /// 2+ ingredients with amounts and an anchor dose entered.
    private var liveBlendBreakdown: [(name: String, dose: Mass)]? {
        guard entries.count > 1, let pd = doseText.decimalValue, pd > 0 else { return nil }
        guard let anchor = anchorEntry, let anchorMass = relativeMass(anchor), anchorMass > 0 else { return nil }
        let anchorDose = Mass(pd, doseUnit).micrograms
        return entries.compactMap { e in
            relativeMass(e).map { (e.compound.name, Mass(micrograms: $0 / anchorMass * anchorDose)) }
        }
    }

    /// Relative mass of an ingredient for ratio math — the solvent cancels, so for a pre-mixed
    /// vial the per-mL strength stands in for mass. nil when the amount isn't a positive number.
    private func relativeMass(_ e: APIEntry) -> Double? {
        guard let amt = e.amountText.decimalValue, amt > 0 else { return nil }
        return isPremixed ? Mass(amt, concentrationUnit).micrograms : Mass(amt, e.unit).micrograms
    }

    /// The escape hatch for a blend, in the app's own vocabulary (Stack ▸ My Vials / My Protocols).
    /// A pre-mixed vial can't be separated — its compounds arrive combined from the pharmacy — so
    /// the advice differs from a powder you mix yourself.
    private var separateVialsSuggestion: String {
        isPremixed
        ? "A pre-mixed vial can't be split — these compounds come combined from the pharmacy. To dose each on its own, you'd need a separate pre-mixed vial for each one."
        : "Want to dose each compound on its own? Add them as separate vials (Stack ▸ My Vials), then run them together as a protocol (Stack ▸ My Protocols)."
    }

    /// The blend "hero": what one shot actually delivers of every compound (live), the anchor
    /// highlighted, plus the ratio explanation and the separate-vials escape hatch.
    private var blendHero: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Image(systemName: "syringe.fill").font(.caption).foregroundStyle(BrandColor.accent)
                Text("This shot delivers").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
            }
            if let breakdown = liveBlendBreakdown {
                ForEach(breakdown, id: \.name) { line in
                    let isAnchor = line.name == anchorName
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(line.name).font(.subheadline).foregroundStyle(BrandColor.textPrimary)
                        if isAnchor {
                            Text("you set this").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                        }
                        Spacer()
                        Text(line.dose.displayString(in: doseUnit))
                            .font(Typo.numberMD)
                            .foregroundStyle(isAnchor ? BrandColor.accentText : BrandColor.textPrimary)
                    }
                }
            } else {
                Text("Enter each ingredient's amount and a dose to see the split.")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            Divider().overlay(BrandColor.stroke)
            Text("Everything is mixed in one vial, so a shot always pulls this exact ratio. Choose which compound to dose by above — the rest follow.")
                .font(.caption).foregroundStyle(BrandColor.textSecondary)
            Label {
                Text(separateVialsSuggestion)
            } icon: {
                Image(systemName: isPremixed ? "info.circle" : "square.stack.3d.up")
            }
            .font(.caption).foregroundStyle(BrandColor.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(BrandColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.accent.opacity(0.3), lineWidth: 1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        FieldRow("Nickname (optional)") {
                            TextField("e.g. GLOW or Wolverine 3/3", text: $label).pinwiseField()
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

                    // Fill from a photo or by voice — available in both modes. What's read decides
                    // pre-mixed vs powder, so a scan/voice result routes to the right mode itself.
                    HStack(spacing: Space.md) {
                        captureButton("Scan", icon: "text.viewfinder") { showScanner = true }
                        captureButton("Speak", icon: "mic.fill") { showVoice = true }
                    }
                    Text("Snap the label or say the details — PinWise fills in what it can, on your device.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            Text("What's in the vial?").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            Text(isPremixed
                                 ? "Enter each ingredient's strength from the label. One ingredient = a single-compound vial; add more for a blend."
                                 : "One ingredient = a single-compound vial. Add more to make a blend.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)

                            if isPremixed {
                                HStack {
                                    Text("Strength unit").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                    Spacer()
                                    concentrationUnitPicker
                                }
                            }

                            if entries.count > 1 {
                                Text("Tap a circle to choose which compound you dose by — the rest scale to it.")
                                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                            }
                            ForEach($entries) { $entry in
                                VStack(spacing: Space.sm) {
                                    HStack {
                                        if entries.count > 1 {
                                            let isAnchor = entry.id == effectiveAnchorID
                                            Button { anchorID = entry.id } label: {
                                                Image(systemName: isAnchor ? "largecircle.fill.circle" : "circle")
                                                    .foregroundStyle(isAnchor ? BrandColor.accent : BrandColor.textSecondary)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(isAnchor ? "Dosing by \(entry.compound.name)" : "Dose by \(entry.compound.name)")
                                        }
                                        CompoundMenu(selection: $entry.compound,
                                                     options: pickerOptions(including: entry.compound))
                                        Spacer(minLength: Space.sm)
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
                                            Text("\(concentrationUnit.rawValue)/mL").foregroundStyle(BrandColor.textSecondary)
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
                            FieldRow(entries.count > 1
                                     ? (anchorName.isEmpty ? "Dose per shot" : "Dose of \(anchorName) per shot")
                                     : (primaryName.isEmpty ? "Dose per shot" : "Dose of \(primaryName) per shot"),
                                     hint: entries.count > 1 ? "You set \(anchorName)'s dose — everything else scales to it." : "The dose you intend to inject each time.") {
                                HStack {
                                    TextField("e.g. 2.5", text: $doseText).keyboardType(.decimalPad).pinwiseField()
                                    unitPicker($doseUnit)
                                }
                            }

                            // HERO: for a blend, the numbers do the explaining (extracted to keep
                            // this large view's body within the type-checker's reach).
                            if entries.count > 1 { blendHero }
                        }
                    }

                    if let editing, editing.dosesTaken > 0 {
                        Card {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                SectionHeader(title: "Refill")
                                Text("Finished this vial? Start a fresh one with the same specs — same compound, concentration, and dose — without re-entering anything. This vial is replaced with a full one; your logged doses are kept.")
                                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Button { refill() } label: {
                                    Label("Refill — new vial, same specs", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(BrandColor.accentText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // COA correction is only for powder you reconstitute — a pre-mixed vial's
                    // stated strength is already corrected by the pharmacy.
                    if !isPremixed { coaCard }

                    Card {
                        DisclosureGroup(isExpanded: $expandExtras) {
                            VStack(alignment: .leading, spacing: Space.lg) {
                                Toggle("Set a discard (beyond-use) date", isOn: $hasExpiration).tint(BrandColor.accent)
                                if hasExpiration {
                                    FieldRow("Discard by") {
                                        DatePicker("", selection: $expiration, displayedComponents: [.date]).labelsHidden()
                                    }
                                    Text("US Pharmacopeia (USP) recommends discarding a multi-dose vial about 28 days after opening or mixing, to limit bacterial or fungal growth. Extended expiration dates are not advised.")
                                        .font(.caption2)
                                        .foregroundStyle(BrandColor.textSecondary)
                                    Button {
                                        expiration = Calendar.current.date(byAdding: .day, value: Self.recommendedBeyondUseDays, to: Date()) ?? Date()
                                    } label: {
                                        Label("Use recommended 28-day date", systemImage: "arrow.counterclockwise")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(BrandColor.accentText)
                                    }
                                    .buttonStyle(.plain)
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
                            Text("Discard date & cost").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                        }
                        .tint(BrandColor.accentText)
                    }

                    PrimaryButton(title: editing == nil ? "Add vial" : "Save changes", systemImage: "checkmark") { save() }
                        .disabled(!canSave).opacity(canSave ? 1 : 0.5)

                    if editing != nil {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete vial", systemImage: "trash")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, Space.sm)
                                .foregroundStyle(BrandColor.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle(editing == nil ? "New vial" : "Edit vial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Delete this vial?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete vial", role: .destructive) {
                    if let editing {
                        editing.reconcileDelete(in: context, doses: logs, protocols: protocols)
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the vial from your Stack. Doses you've already logged are kept, and any protocol using it keeps its schedule but loses the vial link.")
            }
            // A preset-autofilled nickname is only honest while the formula still matches the
            // preset — drop it the moment the ingredient list diverges.
            .onChange(of: entries.map(\.compound.name)) { _, names in
                if let p = appliedPreset, names != p.names {
                    if label == p.label { label = "" }
                    appliedPreset = nil
                }
            }
            // The amount fields mean different things per mode (total mass vs mg/mL strength) —
            // convert entered values on toggle so flipping the segment never rescales the vial.
            .onChange(of: isPremixed) { _, premixed in
                // A scan-driven mode flip already wrote values in the target mode's meaning — skip
                // the conversion once so it isn't double-applied.
                if suppressModeConversion { suppressModeConversion = false; return }
                let vol = solventText.decimalValue ?? 0
                entries = entries.map { e in
                    var e = e
                    guard let amt = e.amountText.decimalValue, amt > 0 else { return e }
                    if premixed {
                        // total mass (in the entry's unit) → per-mL strength in the chosen conc. unit
                        e.amountText = vol > 0 ? Self.fmt(Mass(amt, e.unit).value(in: concentrationUnit) / vol) : ""
                    } else {
                        // per-mL strength (in concentrationUnit) → total mass, shown in mg
                        e.amountText = vol > 0 ? Self.fmt(Mass(amt, concentrationUnit).micrograms * vol / 1_000) : ""
                        e.unit = .milligram
                    }
                    return e
                }
            }
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
            .sheet(isPresented: $showScanner) {
                LabelScannerView(extraCompoundNames: customCompounds.map(\.name)) { applyScan($0) }
            }
            .sheet(isPresented: $showVoice) {
                VoiceInputView(extraCompoundNames: customCompounds.map(\.name)) { applyScan($0) }
            }
        }
    }

    /// Photo/voice capture button — shared style for the "Scan" and "Speak" entry points.
    private func captureButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                .foregroundStyle(BrandColor.accentText)
        }
        .buttonStyle(.plain)
    }

    /// Fill the form from an on-device label scan (user confirmed). Everything stays editable.
    /// The scanned strength decides the mode: a per-mL concentration is a pre-mixed vial; a bare
    /// total mass is powder. A bare mass is never treated as a concentration (that would be a large
    /// dosing error), so the reader's mass/concentration distinction is honored here 1:1.
    private func applyScan(_ r: ScannedLabel) {
        guard !entries.isEmpty else { return }
        if let name = r.compoundName, let c = allCompounds.first(where: { $0.name == name }) {
            entries[0].compound = c
        }
        switch r.strength {
        case .concentrationMgPerMl(let conc):
            setPremixed(true)
            // Scanned strength is mg/mL — force the strength unit so the value is read correctly.
            concentrationUnit = .milligram
            entries[0].amountText = Self.fmt(conc)
            entries[0].unit = .milligram
        case .massMilligrams(let mg):
            setPremixed(false)          // bare total mass ⇒ powder you reconstitute
            entries[0].amountText = Self.fmt(mg)
            entries[0].unit = .milligram
        case nil:
            break
        }
        if let vol = r.volumeMl { solventText = Self.fmt(vol) }
        if let exp = r.expiration { hasExpiration = true; expiration = exp }
        if let lot = r.lotNumber, !lot.isEmpty {
            let tag = "Lot \(lot)"
            if !notes.localizedCaseInsensitiveContains(tag) {
                notes = notes.isEmpty ? tag : notes + "\n" + tag
            }
        }
    }

    /// Flip the pre-mixed/powder segment from a scan, suppressing the unit converter for that one
    /// change so the value the scan is about to write isn't re-scaled. No-op if already in `v`.
    private func setPremixed(_ v: Bool) {
        guard isPremixed != v else { return }
        suppressModeConversion = true
        isPremixed = v
    }

    /// Strength-unit chooser for pre-mixed vials: "mcg/mL" | "mg/mL".
    private var concentrationUnitPicker: some View {
        HStack(spacing: 4) {
            ForEach(MassUnit.allCases, id: \.self) { u in
                Button { concentrationUnit = u } label: {
                    Text("\(u.rawValue)/mL")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                        .frame(minWidth: 60)
                        .background(concentrationUnit == u ? BrandColor.accent : BrandColor.surfaceElevated, in: Capsule())
                        .foregroundStyle(concentrationUnit == u ? BrandColor.onAccent : BrandColor.textSecondary)
                        .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: concentrationUnit == u ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
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
        if label.isEmpty {
            label = blend.name
            appliedPreset = (blend.name, entries.map(\.compound.name))
        } else {
            appliedPreset = nil
        }
    }

    /// Live COA correction factor from the entered fields (1.0 when none) — for the editor readout.
    private var coaFactorPreview: Double {
        COACorrection.factor(assayPercent: coaAssayText.decimalValue,
                             contentPercent: coaContentText.decimalValue,
                             purityPercent: coaPurityText.decimalValue)
    }
    private var hasAnyCOAEntered: Bool {
        [coaAssayText, coaContentText, coaPurityText].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    /// Concrete correction readout: shows the entered label amount → true active amount (so the
    /// correction is visible right here), falling back to the percentage before an amount exists.
    private var coaCorrectedReadout: String {
        let pct = pctText(coaFactorPreview)
        if let first = entries.first, let amt = first.amountText.decimalValue, amt > 0 {
            let label = Mass(amt, first.unit)
            let corrected = Mass(micrograms: label.micrograms * coaFactorPreview)
            return "Label \(label.displayString(in: first.unit)) → true active ≈ \(corrected.displayString(in: first.unit)) (\(pct))."
        }
        return "True active ≈ \(pct) of the label weight."
    }

    /// COA card — enter assay / content / purity (any subset) to correct the vial's true active
    /// concentration, so doses aren't computed off the (higher) label amount. Shown for every vial.
    private var coaCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Certificate of Analysis (COA)")
                    .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Text("A peptide vial is labeled by total powder weight — but only part of that is active peptide. The rest is salt and water left over from how peptides are made and freeze-dried, so a “10 mg” vial is often only about 7–9 mg of actual peptide. If you dose off the label, you take a little less than you intend. Your COA reports the true fraction; enter whatever it lists and PinWise doses off the corrected amount — the most accurate way to reconstitute.")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
                FieldRow("Assay %") {
                    HStack { TextField("e.g. 99.5", text: $coaAssayText).keyboardType(.decimalPad).pinwiseField()
                             Text("%").foregroundStyle(BrandColor.textSecondary) }
                }
                FieldRow("Content %") {
                    HStack { TextField("e.g. 88", text: $coaContentText).keyboardType(.decimalPad).pinwiseField()
                             Text("%").foregroundStyle(BrandColor.textSecondary) }
                }
                FieldRow("Purity %") {
                    HStack { TextField("e.g. 99.8", text: $coaPurityText).keyboardType(.decimalPad).pinwiseField()
                             Text("%").foregroundStyle(BrandColor.textSecondary) }
                }
                Text("Enter any your COA lists. Content = how much is peptide vs. salt/water (the one that changes your dose most). Purity = the right peptide vs. related impurities. Assay = a potency check (labs define it differently).")
                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                if hasAnyCOAEntered {
                    Label("\(coaCorrectedReadout) Your doses are calculated from this corrected amount, not the label.",
                          systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.success)
                } else {
                    Label("No COA entered — doses will use the full label weight. A peptide vial is typically only ~70–90% active peptide, so that likely means dosing a little low.",
                          systemImage: "info.circle.fill")
                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }
    private func pctText(_ f: Double) -> String { String(format: "%.1f%%", f * 100) }

    private func save() {
        let target = editing ?? StoredVial()
        guard applyForm(to: target) else { return }
        // Keep inventory math coherent after an edit: never more doses taken than the vial now holds.
        target.dosesTaken = min(target.dosesTaken, target.totalDoses)
        if editing == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }

    /// Refill: start a FRESH, full vial with the SAME specs as the one being edited (mg of powder,
    /// concentration, intended dose, units, COA…), then remove the depleted one — so a user swapping
    /// in an identical vial never re-enters its details. The old vial's logged doses are preserved:
    /// `reconcileDelete` only unlinks them, it never deletes a `LoggedDose`.
    private func refill() {
        guard let old = editing else { return }
        let fresh = StoredVial()
        guard applyForm(to: fresh) else { return }
        fresh.dosesTaken = 0
        fresh.dateAcquired = .now
        context.insert(fresh)
        old.reconcileDelete(in: context, doses: logs, protocols: protocols)
        try? context.save()
        dismiss()
    }

    /// Populate a vial from the current form fields; returns false (leaving the vial untouched) if
    /// the form is incomplete, matching Save's validation. Shared by save() and refill().
    private func applyForm(to vial: StoredVial) -> Bool {
        let vol = solventText.decimalValue ?? 0
        // Store the "dose by" anchor FIRST so it becomes the primary API — `perDoseMicrograms` is
        // defined as the primary's dose, and every downstream breakdown scales off apis.first.
        var ordered = entries
        if let idx = ordered.firstIndex(where: { $0.id == effectiveAnchorID }), idx != 0 {
            ordered.insert(ordered.remove(at: idx), at: 0)
        }
        let apis = ordered.compactMap { e -> VialAPI? in
            guard let amt = e.amountText.decimalValue, amt > 0 else { return nil }
            // Pre-mixed entries are a label strength in `concentrationUnit` per mL: total content
            // = strength × volume. Powder entries are a total mass in the entry's own unit.
            let micrograms = isPremixed ? Mass(amt, concentrationUnit).micrograms * vol : Mass(amt, e.unit).micrograms
            return VialAPI(name: e.compound.name, massMicrograms: micrograms)
        }
        guard !apis.isEmpty, let pd = doseText.decimalValue, pd > 0, !isPremixed || vol > 0 else { return false }
        vial.label = label
        vial.apis = apis
        vial.solventVolumeMilliliters = vol > 0 ? vol : nil
        vial.perDoseMicrograms = Mass(pd, doseUnit).micrograms
        // Remember the unit the user dosed in so every display of this vial (and any protocol
        // drawing from it) shows the same unit rather than auto-switching by magnitude.
        vial.doseUnitRaw = doseUnit.rawValue
        // Pre-mixed vials carry an explicit strength unit (mg/mL vs mcg/mL); powder vials leave it
        // nil so their concentration display follows the dose unit.
        vial.concentrationUnitRaw = isPremixed ? concentrationUnit.rawValue : nil
        vial.cost = costText.decimalValue.map { Decimal($0) }
        // COA correction applies only to powder vials — a pre-mixed vial's strength is already
        // corrected, so clear any COA values when the vial is pre-mixed.
        vial.coaAssayPercent = isPremixed ? nil : coaAssayText.decimalValue
        vial.coaContentPercent = isPremixed ? nil : coaContentText.decimalValue
        vial.coaPurityPercent = isPremixed ? nil : coaPurityText.decimalValue
        vial.expirationDate = hasExpiration ? expiration : nil
        vial.notes = notes
        vial.isPremixed = isPremixed
        // Provenance: a powder vial mixed with solvent is reconstituted now. Preserve an existing
        // date across edits; clear it if the vial isn't a reconstituted powder (premixed / no water).
        vial.dateReconstituted = (!isPremixed && vol > 0) ? (vial.dateReconstituted ?? .now) : nil
        return true
    }

    private static func resolve(_ name: String) -> Compound {
        CompoundCatalog.all.first { $0.name == name }
            ?? Compound(name: name, category: .metabolic, regulatoryStatus: .researchOnly, evidenceTier: .preclinicalOrFailed)
    }

    /// Formats to up to 4 decimals with trailing zeros trimmed — enough that pharmacy strengths
    /// like 0.625 mg/mL and back-computed values survive an edit round-trip unrounded.
    private static func fmt(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
