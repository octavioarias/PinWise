import SwiftUI
import SwiftData
import PeptideKit

/// Create a dosing protocol: compound + dose + schedule. Presented as a sheet.
/// It's a user-configured schedule — never a recommendation (disclaimer shown).
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
                    nameCard
                    compoundCard
                    doseCard
                    scheduleCard
                    startCard

                    PrimaryButton(title: "Save protocol", systemImage: "checkmark") { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                    DisclaimerBanner(text: "A protocol is a personal schedule you configure — not medical advice or a recommendation.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("New protocol")
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

    private var nameCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Name")
                TextField("Protocol name", text: $name).pinwiseField()
            }
        }
    }

    private var compoundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Compound")
                Picker("Compound", selection: $compound) {
                    ForEach(CompoundCatalog.all, id: \.id) { c in Text(c.name).tag(c) }
                }
                .pickerStyle(.menu)
                .tint(BrandColor.accentText)
                HStack(spacing: Space.sm) {
                    EvidenceBadge(tier: compound.evidenceTier)
                    if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                    Spacer()
                }
            }
        }
    }

    private var doseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Dose")
                HStack {
                    TextField("Amount", text: $doseText).keyboardType(.decimalPad).pinwiseField()
                    Picker("", selection: $doseUnit) {
                        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
        }
    }

    private var scheduleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Schedule")
                Picker("Schedule", selection: $kind) {
                    Text("Daily").tag(DoseSchedule.Kind.daily)
                    Text("Every N days").tag(DoseSchedule.Kind.everyNDays)
                    Text("Weekly").tag(DoseSchedule.Kind.specificWeekdays)
                    Text("As needed").tag(DoseSchedule.Kind.asNeeded)
                }
                .pickerStyle(.menu)
                .tint(BrandColor.accentText)

                if kind == .everyNDays {
                    Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...30)
                        .foregroundStyle(BrandColor.textPrimary)
                } else if kind == .specificWeekdays || kind == .weekly {
                    weekdayPicker
                }
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

    private var startCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Details")
                DatePicker("Start date", selection: $startDate, displayedComponents: [.date])
                    .tint(BrandColor.accentText)
                Toggle("Active", isOn: $isActive).tint(BrandColor.accent)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
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
        let entry = SavedProtocol(
            name: trimmedName.isEmpty ? compound.name : trimmedName,
            compoundName: compound.name,
            doseMicrograms: Mass(d, doseUnit).micrograms,
            scheduleKindRaw: kind.rawValue,
            intervalDays: intervalDays,
            weekdays: usesWeekdays ? weekdays.sorted() : [],
            startDate: startDate,
            isActive: isActive,
            notes: notes
        )
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}
