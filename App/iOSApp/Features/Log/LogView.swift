import SwiftUI
import SwiftData
import PeptideKit

/// The Log tab — the fastest path to record a dose. Quick-fill chips pull from active
/// protocols; sensible defaults (preferred unit, auto-suggested site, "now" timestamp with
/// backfill) keep it to a couple taps. A success haptic confirms the save.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]

    @State private var compound: Compound = CompoundCatalog.semaglutide
    @State private var doseText: String = ""
    @State private var doseUnit: MassUnit = .milligram
    @State private var site: InjectionSite?
    @State private var timestamp: Date = Date()
    @State private var notes: String = ""
    @State private var showMetrics = false
    @State private var energy: Double = 5
    @State private var sideEffect: Double = 0
    @State private var savedConfirmation = false
    @State private var savedCount = 0

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var doseValue: Double? {
        guard let d = Double(doseText), d > 0 else { return nil }
        return d
    }
    private var suggestedSite: InjectionSite? {
        SiteRotationAdvisor.suggestNext(history: recent.map { $0.asDomain() })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Log a dose")
                        .font(Typo.displayL).textCase(.uppercase)
                        .foregroundStyle(BrandColor.textPrimary)
                        .minimumScaleFactor(0.7).lineLimit(1)

                    if !activeProtocols.isEmpty { quickFill }
                    compoundCard
                    doseCard
                    siteCard
                    whenCard
                    metricsCard

                    PrimaryButton(title: savedConfirmation ? "Logged ✓" : "Log dose",
                                  systemImage: savedConfirmation ? "checkmark" : "plus") { save() }
                        .disabled(doseValue == nil)
                        .opacity(doseValue == nil ? 0.5 : 1)

                    if !recent.isEmpty {
                        SectionHeader(title: "Recent")
                        ForEach(Array(recent.prefix(12)), id: \.id) { entry in recentRow(entry) }
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.success, trigger: savedCount)
            .onAppear {
                doseUnit = compound.preferredDoseUnit
                if site == nil { site = suggestedSite }
            }
            .onChange(of: compound) { _, newValue in doseUnit = newValue.preferredDoseUnit }
            .onChange(of: doseText) { _, _ in savedConfirmation = false }
        }
    }

    private var quickFill: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Quick-fill from protocol")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(activeProtocols, id: \.id) { p in
                        Button { prefill(from: p) } label: {
                            Text("\(p.name) · \(p.dose.displayString)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                                .background(BrandColor.surfaceElevated, in: Capsule())
                                .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: 1))
                                .foregroundStyle(BrandColor.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills the form from this protocol")
                    }
                }
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
                .pickerStyle(.menu).tint(BrandColor.accentText)
                HStack(spacing: Space.sm) {
                    EvidenceBadge(tier: compound.evidenceTier)
                    if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                    Spacer()
                }
                if compound.requiresResearchDisclaimer {
                    Text(Disclaimer.researchCompound).font(.caption).foregroundStyle(BrandColor.textSecondary)
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
                    .pickerStyle(.segmented).frame(width: 120)
                }
            }
        }
    }

    private var siteCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Injection site")
                Picker("Site", selection: $site) {
                    Text("Not set").tag(Optional<InjectionSite>.none)
                    ForEach(InjectionSite.allCases) { s in Text(s.displayName).tag(Optional(s)) }
                }
                .pickerStyle(.menu).tint(BrandColor.accentText)
                if let suggested = suggestedSite, suggested != site {
                    Button { site = suggested } label: {
                        Label("Suggest: \(suggested.displayName)", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(BrandColor.accentText)
                    }
                }
            }
        }
    }

    private var whenCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "When")
                DatePicker("Date & time", selection: $timestamp, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .tint(BrandColor.accentText)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
            }
        }
    }

    private var metricsCard: some View {
        Card {
            DisclosureGroup(isExpanded: $showMetrics) {
                VStack(alignment: .leading, spacing: Space.md) {
                    labeledSlider("Energy", value: $energy)
                    labeledSlider("Side-effect severity", value: $sideEffect)
                }
                .padding(.top, Space.sm)
            } label: {
                SectionHeader(title: "How you feel (optional)")
            }
            .tint(BrandColor.accentText)
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).font(.caption).foregroundStyle(BrandColor.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue))").font(.caption).foregroundStyle(BrandColor.textPrimary)
            }
            Slider(value: value, in: 0...10, step: 1).tint(BrandColor.accent)
        }
    }

    private func recentRow(_ entry: LoggedDose) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.compoundName).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(entry.dose.displayString + (entry.site.map { " · \($0.displayName)" } ?? ""))
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()
                Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
        }
        .contextMenu {
            Button(role: .destructive) { context.delete(entry) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func prefill(from p: SavedProtocol) {
        if let c = CompoundCatalog.all.first(where: { $0.name == p.compoundName }) {
            compound = c
            doseUnit = c.preferredDoseUnit
        }
        let v = p.dose.value(in: doseUnit)
        doseText = v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func save() {
        guard let d = doseValue else { return }
        let entry = LoggedDose(
            timestamp: timestamp,
            compoundName: compound.name,
            doseMicrograms: Mass(d, doseUnit).micrograms,
            siteRaw: site?.rawValue,
            notes: notes,
            energy: showMetrics ? energy : nil,
            sideEffectSeverity: showMetrics ? sideEffect : nil
        )
        context.insert(entry)
        // Cohesion: draw this dose from a matching vial that still has doses left.
        if let vial = vials.first(where: { $0.compoundName == compound.name && $0.dosesTaken < $0.totalDoses }) {
            vial.dosesTaken += 1
        }
        try? context.save()

        doseText = ""
        notes = ""
        timestamp = Date()
        site = suggestedSite
        savedConfirmation = true
        savedCount += 1   // triggers the success haptic
    }
}
