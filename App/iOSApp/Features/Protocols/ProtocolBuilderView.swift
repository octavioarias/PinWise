import SwiftUI
import SwiftData
import PeptideKit

/// Create or edit a dosing protocol in plain language: what compound(s), how much, how often.
/// One protocol shares a schedule and can hold several compounds (a stack). Presented as a sheet.
/// It's a schedule you configure — never a recommendation (disclaimer shown).
struct ProtocolBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private struct ItemEntry: Identifiable {
        let id = UUID()
        var compound: Compound
        var doseText: String
        var doseUnit: MassUnit
    }

    @State private var name: String = ""
    @State private var items: [ItemEntry] = [ItemEntry(compound: CompoundCatalog.semaglutide, doseText: "", doseUnit: .milligram)]
    @State private var kind: DoseSchedule.Kind = .specificWeekdays
    @State private var intervalDays: Int = 2
    @State private var weekdays: Set<Int> = [1]
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
            let comp = CompoundCatalog.all.first { $0.name == item.compoundName } ?? CompoundCatalog.semaglutide
            let unit = comp.preferredDoseUnit
            let val = Mass(micrograms: item.doseMicrograms).value(in: unit)
            return ItemEntry(compound: comp, doseText: val == val.rounded() ? String(Int(val)) : String(val), doseUnit: unit)
        }
        _items = State(initialValue: entries.isEmpty
            ? [ItemEntry(compound: CompoundCatalog.semaglutide, doseText: "", doseUnit: .milligram)]
            : entries)
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
    private var canSave: Bool { items.contains { (Double($0.doseText) ?? 0) > 0 } }
    private var needsResearchNote: Bool { items.contains { $0.compound.requiresResearchDisclaimer } }

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
                            Text("One compound is a single protocol. Add more to build a stack — they'll share the schedule below.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)

                            ForEach($items) { $item in
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    HStack {
                                        Picker("", selection: $item.compound) {
                                            ForEach(CompoundCatalog.all, id: \.id) { c in Text(c.name).tag(c) }
                                        }
                                        .pickerStyle(.menu).tint(BrandColor.accentText)
                                        Spacer()
                                        if items.count > 1 {
                                            Button { items.removeAll { $0.id == item.id } } label: {
                                                Image(systemName: "minus.circle").foregroundStyle(BrandColor.textSecondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    HStack {
                                        TextField("Dose per shot", text: $item.doseText).keyboardType(.decimalPad).pinwiseField()
                                        Picker("", selection: $item.doseUnit) {
                                            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                        }
                                        .pickerStyle(.segmented).frame(width: 120)
                                    }
                                    HStack(spacing: Space.sm) {
                                        EvidenceBadge(tier: item.compound.evidenceTier)
                                        if item.compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                                        Spacer()
                                    }
                                }
                                .padding(.bottom, Space.xs)
                            }

                            Button { items.append(ItemEntry(compound: CompoundCatalog.bpc157, doseText: "", doseUnit: .milligram)) } label: {
                                Label("Add compound", systemImage: "plus").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                            }
                            .buttonStyle(.plain)

                            if needsResearchNote {
                                Text(Disclaimer.researchCompound).font(.caption).foregroundStyle(BrandColor.textSecondary)
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

                    DisclaimerBanner(text: "A protocol is a personal schedule you configure — not medical advice or a recommendation.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle(editing == nil ? "New protocol" : "Edit protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { d in
                let on = weekdays.contains(d)
                Button {
                    if on { weekdays.remove(d) } else { weekdays.insert(d) }
                } label: {
                    Text(weekdaySymbol(d))
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.sm)
                        .background(on ? BrandColor.accent : BrandColor.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(on ? BrandColor.onAccent : BrandColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekdaySymbol(_ d: Int) -> String {
        let s = Calendar.current.shortWeekdaySymbols
        return (1...7).contains(d) ? String(s[d - 1].prefix(1)) : "?"
    }

    private func save() {
        let built = items.compactMap { e -> ProtocolItem? in
            guard let d = Double(e.doseText), d > 0 else { return nil }
            return ProtocolItem(compoundName: e.compound.name, doseMicrograms: Mass(d, e.doseUnit).micrograms)
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
