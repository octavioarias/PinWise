import SwiftUI
import SwiftData
import PeptideKit

private enum LogMode: String, CaseIterable { case protocolBased = "Protocol", compound = "One-Time Pin" }

/// The Log tab — record a dose against a protocol (all its compounds at once) or a one-time
/// pin. Opens on Protocol whenever protocols exist. A grouped front/back picker keeps
/// injection sites compact; a success haptic confirms the save; logging draws down matching
/// vials; after a save the app returns Home (with a beat to tap "Log another dose").
struct LogView: View {
    @Binding var selected: AppTab
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \CustomCompound.name) private var customCompounds: [CustomCompound]

    @State private var mode: LogMode = .protocolBased   // protocol-first every time the tab opens
    @State private var selectedProtocolID: UUID?
    @State private var postSaveNav: Task<Void, Never>?
    @State private var compound: Compound = CompoundCatalog.semaglutide
    @State private var doseText: String = ""
    @State private var doseUnit: MassUnit = .milligram
    @State private var site: InjectionSite?
    @State private var showBack = false
    @State private var timestamp: Date = Date()
    @State private var notes: String = ""
    @State private var showMetrics = false
    @State private var energy: Double = 5
    @State private var sideEffect: Double = 0
    @State private var savedConfirmation = false
    @State private var savedCount = 0
    /// One-time mode: the vial the user chose to log from (nil = pick any compound).
    @State private var selectedVialID: UUID?

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var selectedProtocol: SavedProtocol? { activeProtocols.first { $0.id == selectedProtocolID } }
    private var doseValue: Double? {
        guard let d = Double(doseText), d > 0 else { return nil }
        return d
    }
    /// Catalog + the user's own compounds — the same list the vial builder offers.
    private var allCompounds: [Compound] {
        (CompoundCatalog.allSorted + customCompounds.map(\.asCompound))
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Resolve a stored compound name: catalog, then custom compounds, then a name-only
    /// placeholder — never an unrelated compound.
    private func resolveCompound(_ name: String) -> Compound {
        CompoundCatalog.all.first { $0.name == name }
            ?? customCompounds.first { $0.name == name }?.asCompound
            ?? Compound(name: name, category: .metabolic, regulatoryStatus: .researchOnly, evidenceTier: .preclinicalOrFailed)
    }

    /// Picker options always include the current selection so a vial/protocol referencing a
    /// deleted custom compound still shows its real name instead of a blank menu.
    private func pickerOptions(including current: Compound) -> [Compound] {
        if allCompounds.contains(where: { $0.id == current.id }) { return allCompounds }
        return (allCompounds + [current]).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// The compound driving the site suggestion (protocol's primary, or the picked compound).
    private var activeCompound: Compound {
        if mode == .protocolBased, let name = selectedProtocol?.compoundName, !name.isEmpty {
            return resolveCompound(name)
        }
        return compound
    }
    private var suggestedSite: InjectionSite? {
        SiteRotationAdvisor.suggestNext(for: activeCompound, history: recent.map { $0.asDomain() })
    }
    private var siteRationale: String {
        switch activeCompound.category {
        case .healingRecovery: return "Healing peptides are often placed near the area you're treating."
        default: return "Abdomen is the usual first choice for \(activeCompound.name); rotate to avoid irritation."
        }
    }
    private var canSave: Bool {
        switch mode {
        case .compound: return doseValue != nil
        case .protocolBased: return !(selectedProtocol?.items.isEmpty ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Log a dose")
                        .font(Typo.screenTitle)
                        .foregroundStyle(BrandColor.textPrimary)
                        .minimumScaleFactor(0.7).lineLimit(1)

                    if !activeProtocols.isEmpty {
                        Picker("", selection: $mode) {
                            ForEach(LogMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    if mode == .protocolBased && !activeProtocols.isEmpty {
                        protocolCard
                    } else {
                        compoundCard
                    }

                    siteCard
                    feelCard

                    PrimaryButton(title: savedConfirmation ? "Logged ✓" : saveTitle,
                                  systemImage: savedConfirmation ? "checkmark" : "plus") { save() }
                        .disabled(!canSave || savedConfirmation)
                        .opacity(canSave ? 1 : 0.5)
                        .scaleEffect(savedConfirmation ? 1.02 : 1)
                        .animation(reduceMotion ? nil : Motion.emphasis, value: savedConfirmation)

                    if savedConfirmation {
                        Button {
                            postSaveNav?.cancel()
                            savedConfirmation = false
                        } label: {
                            Text("Log another dose")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(BrandColor.accentText)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }

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
                // Protocol-first: only fall back to a one-time pin when there are no protocols.
                if activeProtocols.isEmpty { mode = .compound }
                else if selectedProtocolID == nil { selectedProtocolID = activeProtocols.first?.id }
                doseUnit = compound.preferredDoseUnit
                // Do NOT auto-fill the site: a log must record where you ACTUALLY injected, not a
                // rotation suggestion. The "Suggested" hint below applies the pick on tap.
            }
            .onChange(of: compound) { _, newValue in
                doseUnit = newValue.preferredDoseUnit
                // Drop the vial link if the user switches to a compound that vial doesn't hold,
                // so the "From <vial>" label and prefilled dose don't go stale.
                if let id = selectedVialID, let v = vials.first(where: { $0.id == id }), v.primaryAPI?.name != newValue.name {
                    selectedVialID = nil
                }
            }
            .onChange(of: doseText) { _, _ in
                postSaveNav?.cancel()
                savedConfirmation = false
            }
            .onDisappear { postSaveNav?.cancel() }
        }
    }

    private var saveTitle: String {
        if mode == .protocolBased, let p = selectedProtocol, p.items.count > 1 { return "Log \(p.items.count) doses" }
        return "Log dose"
    }

    // MARK: Protocol mode

    private var protocolCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Which protocol?").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(activeProtocols, id: \.id) { p in
                            SelectableChip(title: p.name, isSelected: selectedProtocolID == p.id) {
                                selectedProtocolID = p.id
                            }
                        }
                    }
                }
                // Condition form: the onAppear default-seed (nil → first id) is programmatic,
                // not a tap — only buzz once a selection already existed.
                .sensoryFeedback(.selection, trigger: selectedProtocolID) { old, _ in old != nil }
                if let p = selectedProtocol {
                    Divider().overlay(BrandColor.stroke)
                    ForEach(Array(p.items.enumerated()), id: \.offset) { i, item in
                        HStack {
                            Text(item.compoundName).font(.body).foregroundStyle(BrandColor.textPrimary)
                            Spacer()
                            Text(doseFor(i, in: p).displayString).font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                        }
                    }
                    Text(p.items.count > 1 ? "Logs all \(p.items.count) compounds at once." : "\(p.cadenceText).")
                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private func doseFor(_ index: Int, in p: SavedProtocol) -> Mass {
        index == 0 ? p.effectiveDose : Mass(micrograms: p.items[index].doseMicrograms)
    }

    // MARK: Compound mode

    private var selectedVialName: String? {
        guard let id = selectedVialID, let v = vials.first(where: { $0.id == id }) else { return nil }
        return "From \(v.displayName)"
    }

    /// One-time log from a vial: pull the primary compound + its per-shot dose and link the vial
    /// so the draw-down hits the right one. (Protocols remain the way to log a full stack at once.)
    private func applyVial(_ v: StoredVial) {
        if let name = v.primaryAPI?.name, !name.isEmpty { compound = resolveCompound(name) }
        doseUnit = compound.preferredDoseUnit
        let dose = v.perDose.value(in: doseUnit)
        doseText = dose == dose.rounded() ? String(Int(dose)) : String(dose)
        selectedVialID = v.id
    }

    private var compoundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.lg) {
                if !vials.isEmpty {
                    // Log straight from a vial you own (by nickname) — or pick any compound below.
                    Menu {
                        Button("Any compound (no vial)") { selectedVialID = nil }
                        Divider()
                        ForEach(vials) { v in Button(v.displayName) { applyVial(v) } }
                    } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: "cross.vial.fill")
                            Text(selectedVialName ?? "Log from one of your vials").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .foregroundStyle(BrandColor.accentText)
                        .padding(.vertical, Space.sm).padding(.horizontal, Space.md)
                        .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                    }
                }
                FieldRow("What did you take?", hint: vials.isEmpty ? "The compound you're logging." : "Pick a vial above, or choose any compound.") {
                    CompoundMenu(selection: $compound, options: pickerOptions(including: compound))
                }
                HStack(spacing: Space.sm) {
                    EvidenceBadge(tier: compound.evidenceTier)
                    if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                    Spacer()
                }
                FieldRow("How much?", hint: "The dose you took this time.") {
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
    }

    // MARK: Site / when / notes (shared)

    private var siteCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.lg) {
                FieldRow("Where did you inject?", hint: "Front or back, then a spot. These match your injection map.") {
                    siteSelector
                }
                if let suggested = suggestedSite, suggested != site {
                    Button { site = suggested; showBack = suggested.isBack } label: {
                        Label("Suggested: \(suggested.displayName)", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(BrandColor.accentText)
                    }
                }
                Text(siteRationale).font(.caption2).foregroundStyle(BrandColor.textSecondary)
                FieldRow("When?", hint: "Now by default — change it to log an earlier dose.") {
                    DatePicker("", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                FieldRow("Notes", hint: "Optional.") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical).pinwiseField()
                }
            }
        }
    }

    private var siteSelector: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Picker("", selection: $showBack) {
                Text("Front").tag(false)
                Text("Back").tag(true)
            }
            .pickerStyle(.segmented)
            ForEach(regionsOnFace, id: \.self) { region in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(region.label.uppercased()).font(.caption2).tracking(0.6).foregroundStyle(BrandColor.textSecondary)
                    HStack(spacing: Space.sm) {
                        ForEach(sites(in: region)) { s in
                            // Tapping the selected spot clears it — a log must never carry a
                            // silently-wrong location.
                            SelectableChip(title: s.shortName,
                                           isSelected: site == s,
                                           shape: .rounded(Radius.control),
                                           fillWidth: true) {
                                site = site == s ? nil : s
                            }
                            .accessibilityLabel(s.displayName)
                        }
                    }
                }
            }
        }
        // Condition form: finishSave() clears the site programmatically right after the
        // success haptic — buzz only on selections, never on clears.
        .sensoryFeedback(.selection, trigger: site) { _, new in new != nil }
    }

    private var regionsOnFace: [InjectionSite.Region] {
        var seen = Set<InjectionSite.Region>()
        return InjectionSite.allCases.filter { $0.isBack == showBack }.map(\.region).filter { seen.insert($0).inserted }
    }
    private func sites(in region: InjectionSite.Region) -> [InjectionSite] {
        InjectionSite.allCases.filter { $0.isBack == showBack && $0.region == region }
    }

    // MARK: Feel

    private var feelCard: some View {
        Card {
            DisclosureGroup(isExpanded: $showMetrics) {
                VStack(alignment: .leading, spacing: Space.md) {
                    labeledSlider("Energy", value: $energy)
                    labeledSlider("Side effects", value: $sideEffect)
                }
                .padding(.top, Space.sm)
            } label: {
                Text("How do you feel? (optional)").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            }
            .tint(BrandColor.accentText)
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).font(.caption).foregroundStyle(BrandColor.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue)) / 10").font(.caption).foregroundStyle(BrandColor.textPrimary)
            }
            Slider(value: value, in: 0...10, step: 1).tint(BrandColor.accent)
        }
    }

    private func recentRow(_ entry: LoggedDose) -> some View {
        Card(style: .flat) {
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
            Button(role: .destructive) {
                // Restore the vial only for the record that actually decremented it (so a blend
                // stack — one decrement, several records — gives back exactly one dose).
                if entry.didDecrement, let vid = entry.vialID,
                   let vial = vials.first(where: { $0.id == vid }), vial.dosesTaken > 0 {
                    vial.dosesTaken -= 1
                }
                context.delete(entry)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Save

    private func save() {
        switch mode {
        case .compound: saveCompound()
        case .protocolBased: saveProtocol()
        }
    }

    private func saveCompound() {
        guard let d = doseValue else { return }
        // Draw down the vial the user picked (if it still contains this compound), else name-match.
        let vial = selectedVialID.flatMap { id in vials.first { $0.id == id && $0.apiNames.contains(compound.name) } }
            ?? resolveVial(for: compound.name)
        insertDose(compoundName: compound.name, doseMicrograms: Mass(d, doseUnit).micrograms,
                   vial: vial, decrement: vial != nil)
        try? context.save()
        doseText = ""
        finishSave()
    }

    private func saveProtocol() {
        guard let p = selectedProtocol, !p.items.isEmpty else { return }
        // Draw down each DISTINCT vial once per session, even when several stack items resolve
        // to the same blend vial (one physical injection) — prevents double-counting.
        var decremented = Set<UUID>()
        for (i, item) in p.items.enumerated() {
            // Prefer the vial the protocol is explicitly linked to; fall back to a name match.
            let vial = item.vialID.flatMap { id in vials.first { $0.id == id } } ?? resolveVial(for: item.compoundName)
            let firstForThisVial = vial.map { decremented.insert($0.id).inserted } ?? false
            insertDose(compoundName: item.compoundName, doseMicrograms: doseFor(i, in: p).micrograms,
                       vial: vial, decrement: firstForThisVial)
        }
        try? context.save()
        finishSave()
    }

    /// The vial a logged compound draws from: the newest non-depleted vial containing that API.
    private func resolveVial(for compoundName: String) -> StoredVial? {
        vials.first { $0.apiNames.contains(compoundName) && $0.dosesTaken < $0.totalDoses }
    }

    private func insertDose(compoundName: String, doseMicrograms: Double, vial: StoredVial?, decrement: Bool) {
        let willDecrement = decrement && (vial.map { $0.dosesTaken < $0.totalDoses } ?? false)
        let entry = LoggedDose(
            timestamp: timestamp,
            compoundName: compoundName,
            doseMicrograms: doseMicrograms,
            siteRaw: site?.rawValue,
            notes: notes,
            vialID: vial?.id,
            didDecrement: willDecrement,
            energy: showMetrics ? energy : nil,
            sideEffectSeverity: showMetrics ? sideEffect : nil
        )
        context.insert(entry)
        if decrement, let vial, vial.dosesTaken < vial.totalDoses {
            vial.dosesTaken += 1
        }
    }

    private func finishSave() {
        notes = ""
        timestamp = Date()
        site = nil          // clear so the next log starts unselected (no silently-wrong location)
        showBack = false
        selectedVialID = nil
        savedConfirmation = true
        savedCount += 1
        // Return Home after a beat — long enough to read "Logged ✓" and tap "Log another dose".
        postSaveNav?.cancel()
        postSaveNav = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            selected = .home
            savedConfirmation = false
        }
    }
}
