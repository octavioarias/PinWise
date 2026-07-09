import SwiftUI
import SwiftData
import PeptideKit

/// Create or edit a dosing protocol in plain language: which of your vials, how much, how
/// often. One protocol shares a schedule and can hold several vials (a stack). Presented as
/// a sheet. Protocols draw from vials you own — compounds aren't added here directly.
struct ProtocolBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \CustomCompound.name) private var customCompounds: [CustomCompound]

    private struct ItemEntry: Identifiable {
        let id = UUID()
        var compound: Compound
        var doseText: String
        var doseUnit: MassUnit
        var vialID: UUID? = nil
    }

    @State private var name: String = ""
    @State private var items: [ItemEntry] = []
    @State private var kind: DoseSchedule.Kind = .specificWeekdays
    @State private var intervalDays: Int = 2
    @State private var weekdays: Set<Int> = [2]   // default Monday (week starts Monday)
    @State private var startDate: Date = Date()
    @State private var isActive: Bool = true
    @State private var notes: String = ""
    @State private var remindersOn = false
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    private let editing: SavedProtocol?

    init(editing: SavedProtocol? = nil) {
        self.editing = editing
        guard let p = editing else { return }
        _name = State(initialValue: p.name)
        let entries = p.items.map { item -> ItemEntry in
            // Custom compounds aren't queryable in init — a placeholder by name keeps legacy
            // and custom-compound protocols editable (the name is all that's persisted).
            let comp = CompoundCatalog.all.first { $0.name == item.compoundName }
                ?? Compound(name: item.compoundName, category: .metabolic, regulatoryStatus: .researchOnly, evidenceTier: .preclinicalOrFailed)
            // Reopen the line in the unit the user saved it in (falls back to the compound default).
            let unit = item.doseUnit ?? comp.preferredDoseUnit
            let val = Mass(micrograms: item.doseMicrograms).value(in: unit)
            return ItemEntry(compound: comp, doseText: val == val.rounded() ? String(Int(val)) : String(val), doseUnit: unit, vialID: item.vialID)
        }
        _items = State(initialValue: entries)
        _kind = State(initialValue: p.scheduleKind)
        _intervalDays = State(initialValue: p.intervalDays)
        _weekdays = State(initialValue: Set(p.weekdays))
        _startDate = State(initialValue: p.startDate)
        _isActive = State(initialValue: p.isActive)
        _notes = State(initialValue: p.notes)
        _remindersOn = State(initialValue: p.remindersOn)
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: p.reminderHour, minute: p.reminderMinute, second: 0, of: Date()) ?? Date())
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    /// Every line needs a valid dose — saving must never silently drop a half-edited line.
    private var canSave: Bool {
        !items.isEmpty && items.allSatisfy { ($0.doseText.decimalValue ?? 0) > 0 }
    }

    private func resolveCompound(_ name: String) -> Compound {
        CompoundCatalog.all.first { $0.name == name }
            ?? customCompounds.first { $0.name == name }?.asCompound
            ?? Compound(name: name, category: .metabolic, regulatoryStatus: .researchOnly, evidenceTier: .preclinicalOrFailed)
    }

    /// Add a line from one of the user's vials — carrying its nickname link, compound, and
    /// per-shot dose. Protocols always reference vials, never raw catalog compounds. For a
    /// blend the line's compound/dose anchor on the PRIMARY API; every other compound in the
    /// vial rides along at a fixed mass ratio (see `blendBreakdown`) and is shown in the row.
    private func addVial(_ vial: StoredVial) {
        let comp = resolveCompound(vial.primaryAPI?.name ?? "")
        // Default the line to the vial's own unit so the protocol inherits it (user can change it).
        let unit = vial.doseUnit
        let v = vial.perDose.value(in: unit)
        let entry = ItemEntry(compound: comp,
                              doseText: v > 0 ? (v == v.rounded() ? String(Int(v)) : String(v)) : "",
                              doseUnit: unit, vialID: vial.id)
        items.append(entry)
        if trimmedName.isEmpty { name = vial.displayName }
    }

    /// One compound delivered by a blend line, with its per-shot dose.
    private struct BlendLine: Identifiable { let name: String; let dose: Mass; var id: String { name } }

    /// The full compound scope a vial-backed line delivers per shot. A blend vial draws all its
    /// APIs together in one shot, so each rides along at `apiMass / primaryMass × primaryDose`
    /// (the solvent volume cancels — the ratio is purely mass-based). Returns nil for a
    /// non-vial line or a single-compound vial (nothing extra to break out).
    private func blendBreakdown(for item: ItemEntry) -> [BlendLine]? {
        guard let vid = item.vialID, let vial = vials.first(where: { $0.id == vid }),
              vial.isBlend, let primary = vial.primaryAPI, primary.massMicrograms > 0,
              let entered = item.doseText.decimalValue, entered > 0 else { return nil }
        let primaryDose = Mass(entered, item.doseUnit).micrograms
        return vial.apis.map { api in
            BlendLine(name: api.name,
                      dose: Mass(micrograms: api.massMicrograms / primary.massMicrograms * primaryDose))
        }
    }

    /// The full-scope title for a line: every compound in the linked vial (a blend shows all of
    /// them), falling back to the single compound name for non-vial lines.
    private func lineTitle(for item: ItemEntry) -> String {
        if let vid = item.vialID, let vial = vials.first(where: { $0.id == vid }), !vial.apiNames.isEmpty {
            return vial.apiNames.joined(separator: " + ")
        }
        return item.compound.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        FieldRow("Name this protocol", hint: "So you can spot it quickly, e.g. \"Weekly Tirz\" or \"Recovery stack\".") {
                            TextField("Name", text: $name).pinwiseField()
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            Text("What's in this protocol?").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            Text("Protocols schedule doses from your vials. One vial is a single protocol; add more to build a stack — they share the schedule below.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)

                            ForEach($items) { $item in
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            // Full scope: a blend vial shows every compound it holds,
                                            // not just the primary.
                                            Text(lineTitle(for: item))
                                                .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                            if let vid = item.vialID, let v = vials.first(where: { $0.id == vid }) {
                                                Label("From \(v.displayName)", systemImage: "cross.vial.fill")
                                                    .font(.caption2).foregroundStyle(BrandColor.accentText)
                                            }
                                        }
                                        Spacer()
                                        Button { items.removeAll { $0.id == item.id } } label: {
                                            Image(systemName: "minus.circle").foregroundStyle(BrandColor.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(lineTitle(for: item))")
                                    }
                                    HStack {
                                        // For a blend the typed value sets the PRIMARY; name it so the
                                        // single field isn't read as "the dose of all compounds".
                                        TextField("Dose of \(item.compound.name)", text: $item.doseText).keyboardType(.decimalPad).pinwiseField()
                                        Picker("", selection: $item.doseUnit) {
                                            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                        }
                                        .pickerStyle(.segmented).frame(width: 120)
                                    }
                                    // For a blend, break out what each compound delivers per shot — the
                                    // dose above sets the primary; the rest scale by their vial mass ratio.
                                    if let breakdown = blendBreakdown(for: item) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Each shot delivers")
                                                .font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                                            ForEach(breakdown) { line in
                                                HStack {
                                                    Text(line.name).font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                                    Spacer()
                                                    Text(line.dose.displayString(in: item.doseUnit))
                                                        .font(.caption2).foregroundStyle(BrandColor.textPrimary)
                                                }
                                            }
                                        }
                                        .padding(Space.sm)
                                        .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                    }
                                }
                                .padding(.bottom, Space.xs)
                            }

                            if vials.isEmpty {
                                Text("No vials yet — add one under My Vials first. Protocols schedule doses from the vials you own.")
                                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            } else {
                                // Exclude vials already on the protocol — adding the same physical
                                // vial twice would double-count one injection.
                                let available = vials.filter { v in !items.contains { $0.vialID == v.id } }
                                Menu {
                                    ForEach(available) { v in Button(v.displayName) { addVial(v) } }
                                } label: {
                                    Label(items.isEmpty ? "Choose a vial" : "Add another vial", systemImage: "plus")
                                        .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                                }
                                .disabled(available.isEmpty)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("How often?", hint: "How often you take this — shared across every compound above.") {
                                Picker("Schedule", selection: $kind) {
                                    Text("Every day").tag(DoseSchedule.Kind.daily)
                                    Text("Every few days").tag(DoseSchedule.Kind.everyNDays)
                                    Text("Certain weekdays").tag(DoseSchedule.Kind.specificWeekdays)
                                    Text("As needed").tag(DoseSchedule.Kind.asNeeded)
                                }
                                .pickerStyle(.menu).tint(BrandColor.accentText)
                            }
                            if kind == .everyNDays {
                                Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...30)
                                    .foregroundStyle(BrandColor.textPrimary)
                            } else if kind == .specificWeekdays || kind == .weekly {
                                Text("Which days?").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                weekdayPicker
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Start date") {
                                DatePicker("", selection: $startDate, displayedComponents: [.date]).labelsHidden()
                            }
                            Toggle("Active", isOn: $isActive).tint(BrandColor.accent)
                            Toggle("Remind me", isOn: $remindersOn)
                                .tint(BrandColor.accent)
                                .onChange(of: remindersOn) { _, on in
                                    if on { Task { await NotificationManager.requestAuthorization() } }
                                }
                            if remindersOn {
                                FieldRow("What time?") {
                                    DatePicker("", selection: $reminderTime, displayedComponents: [.hourAndMinute]).labelsHidden()
                                }
                            }
                            FieldRow("Notes", hint: "Optional.") {
                                TextField("Anything worth remembering", text: $notes, axis: .vertical).pinwiseField()
                            }
                        }
                    }

                    PrimaryButton(title: editing == nil ? "Save protocol" : "Save changes", systemImage: "checkmark") { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                    if editing != nil {
                        Button(role: .destructive) { deleteProtocol() } label: {
                            Label("Delete protocol", systemImage: "trash")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Space.md)
                        }
                        .foregroundStyle(BrandColor.danger)
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle(editing == nil ? "New protocol" : "Edit protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // Custom compounds aren't queryable in init — swap placeholders for the real thing.
            .onAppear {
                items = items.enumerated().map { idx, entry in
                    var e = entry
                    e.compound = resolveCompound(e.compound.name)
                    // Align the picker to what Home/Stack display for this line (the linked vial's
                    // unit for a legacy line that never stored its own), AND recompute the NUMBER in
                    // that unit from the stored micrograms so the mass is preserved. Setting the unit
                    // WITHOUT recomputing would leave a number formatted for the old unit under the
                    // new one, and Save would corrupt the dose (e.g. 500 mcg → "0.5" + mcg → 0.5 mcg).
                    if let editing, editing.items.indices.contains(idx) {
                        let u = editing.doseUnit(forItemAt: idx, vials: vials)
                        let val = Mass(micrograms: editing.items[idx].doseMicrograms).value(in: u)
                        e.doseUnit = u
                        e.doseText = val == val.rounded() ? String(Int(val)) : String(val)
                    }
                    return e
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            // Monday-first order; labels match the cadence display (Su M T W Th F S).
            ForEach(SavedProtocol.mondayFirst([1, 2, 3, 4, 5, 6, 7]), id: \.self) { d in
                SelectableChip(title: SavedProtocol.shortWeekdayLabel(d),
                               isSelected: weekdays.contains(d),
                               shape: .rounded(8),
                               fillWidth: true) {
                    if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: weekdays)
    }

    private func save() {
        let built = items.compactMap { e -> ProtocolItem? in
            guard let d = e.doseText.decimalValue, d > 0 else { return nil }
            return ProtocolItem(compoundName: e.compound.name, doseMicrograms: Mass(d, e.doseUnit).micrograms,
                                vialID: e.vialID, doseUnitRaw: e.doseUnit.rawValue)
        }
        guard !built.isEmpty else { return }
        let usesWeekdays = (kind == .specificWeekdays || kind == .weekly)
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let target = editing ?? SavedProtocol()
        target.name = trimmedName.isEmpty ? (items.first?.compound.name ?? "Protocol") : trimmedName
        target.items = built
        target.scheduleKindRaw = kind.rawValue
        target.intervalDays = intervalDays
        target.weekdays = usesWeekdays ? weekdays.sorted() : []
        target.startDate = startDate
        target.isActive = isActive
        target.notes = notes
        target.remindersOn = remindersOn
        target.reminderHour = time.hour ?? 9
        target.reminderMinute = time.minute ?? 0
        if editing == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }

    private func deleteProtocol() {
        if let p = editing {
            context.delete(p)
            try? context.save()
        }
        dismiss()
    }
}
