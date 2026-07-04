import SwiftUI
import SwiftData
import PeptideKit

/// Create a dosing protocol in plain language: what, how much, how often. Presented as a sheet.
/// It's a schedule you configure — never a recommendation (disclaimer shown).
struct ProtocolBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var compound: Compound = CompoundCatalog.semaglutide
    @State private var doseText: String = ""
    @State private var doseUnit: MassUnit = .milligram
    @State private var kind: DoseSchedule.Kind = .specificWeekdays
    @State private var intervalDays: Int = 2
    @State private var weekdays: Set<Int> = [1]
    @State private var startDate: Date = Date()
    @State private var isActive: Bool = true
    @State private var notes: String = ""
    @State private var remindersOn = false
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    /// The protocol being edited, or nil when creating a new one.
    private let editing: SavedProtocol?

    init(editing: SavedProtocol? = nil) {
        self.editing = editing
        guard let p = editing else { return }
        let comp = CompoundCatalog.all.first { $0.name == p.compoundName } ?? CompoundCatalog.semaglutide
        let unit = comp.preferredDoseUnit
        let doseVal = p.dose.value(in: unit)
        _name = State(initialValue: p.name)
        _compound = State(initialValue: comp)
        _doseText = State(initialValue: doseVal == doseVal.rounded() ? String(Int(doseVal)) : String(doseVal))
        _doseUnit = State(initialValue: unit)
        _kind = State(initialValue: p.scheduleKind)
        _intervalDays = State(initialValue: p.intervalDays)
        _weekdays = State(initialValue: Set(p.weekdays))
        _startDate = State(initialValue: p.startDate)
        _isActive = State(initialValue: p.isActive)
        _notes = State(initialValue: p.notes)
        _remindersOn = State(initialValue: p.remindersOn)
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: p.reminderHour, minute: p.reminderMinute, second: 0, of: Date()) ?? Date())
    }

    private var doseValue: Double? {
        guard let d = Double(doseText), d > 0 else { return nil }
        return d
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { doseValue != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Name this protocol", hint: "So you can spot it quickly, e.g. \"Weekly Tirz\".") {
                                TextField("Name", text: $name).pinwiseField()
                            }
                            FieldRow("Which compound?") {
                                Picker("Compound", selection: $compound) {
                                    ForEach(CompoundCatalog.all, id: \.id) { c in Text(c.name).tag(c) }
                                }
                                .pickerStyle(.menu).tint(BrandColor.accentText)
                            }
                            HStack(spacing: Space.sm) {
                                EvidenceBadge(tier: compound.evidenceTier)
                                if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                                Spacer()
                            }
                            FieldRow("How much per dose?") {
                                HStack {
                                    TextField("e.g. 2.5", text: $doseText).keyboardType(.decimalPad).pinwiseField()
                                    Picker("", selection: $doseUnit) {
                                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    .pickerStyle(.segmented).frame(width: 120)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("How often?", hint: "How often you take this dose.") {
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
            .onAppear {
                doseUnit = compound.preferredDoseUnit
                if trimmedName.isEmpty { name = compound.name }
            }
            .onChange(of: compound) { _, c in
                doseUnit = c.preferredDoseUnit
                if trimmedName.isEmpty { name = c.name }
            }
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
        guard let d = doseValue else { return }
        let usesWeekdays = (kind == .specificWeekdays || kind == .weekly)
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let target = editing ?? SavedProtocol()
        target.name = trimmedName.isEmpty ? compound.name : trimmedName
        target.compoundName = compound.name
        target.doseMicrograms = Mass(d, doseUnit).micrograms
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
