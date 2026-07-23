import SwiftUI
import SwiftData
import PeptideKit

/// The Tools tab — a grid of plain-language calculators, each backed by verified PeptideKit.
struct ToolsView: View {
    private let columns = [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header
                    // Grid order groups the domains: rows 1-2 = the blue dose family,
                    // then body (green) + feel (amber), then data (teal).
                    LazyVGrid(columns: columns, spacing: Space.md) {
                        ToolCard(title: "Compound library", subtitle: "Look up peptides & evidence", systemImage: "books.vertical.fill", hue: BrandColor.data) {
                            CompoundsView()
                        }
                        ToolCard(title: "Dose calculator", subtitle: "How much to draw into your syringe", systemImage: "syringe.fill", hue: BrandColor.accentText) {
                            ReconstitutionCalculatorView()
                        }
                        ToolCard(title: "Check a dose", subtitle: "What a draw equals", systemImage: "arrow.uturn.backward", hue: BrandColor.accentText) {
                            ReverseDoseView()
                        }
                        ToolCard(title: "Ramp-up plan", subtitle: "Build a dose ladder for a protocol", systemImage: "chart.line.uptrend.xyaxis", hue: BrandColor.accentText) {
                            RampUpPlannerView()
                        }
                        ToolCard(title: "Dose history", subtitle: "Review or undo logged doses", systemImage: "clock.arrow.circlepath", hue: BrandColor.accentText) {
                            DoseHistoryView()
                        }
                        ToolCard(title: "Injection map", subtitle: "Where you've been pinning", systemImage: "figure.stand", hue: BrandColor.success) {
                            BodyMapView()
                        }
                        ToolCard(title: "Progress photos", subtitle: "Track your physique over time", systemImage: "camera.fill", hue: BrandColor.success) {
                            PhysiqueView()
                        }
                        ToolCard(title: "How you feel", subtitle: "Track side effects over time", systemImage: "heart.text.square", hue: BrandColor.warning) {
                            SymptomsView()
                        }
                        ToolCard(title: "Labs & metrics", subtitle: "Weight, A1c, lipids, BP trends", systemImage: "chart.xyaxis.line", hue: BrandColor.data) {
                            BiomarkersView()
                        }
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .scrollsToTopOnReselect(.tools)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Tools")
                .font(Typo.screenTitle)
                .foregroundStyle(BrandColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    /// Domain hue (Oura-style color-as-information): accentText = dose, success = body,
    /// warning = subjective tracking, data = objective health data. Tints the icon chip
    /// and icon only — text stays neutral. No default: every tool declares its domain.
    let hue: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    // Tinted icon chip — the Apple Health container register (an icon
                    // GROUND, distinct from the solid badge register).
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(hue)
                        .frame(width: 44, height: 44)
                        .background(hue.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    Spacer(minLength: Space.md)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary).multilineTextAlignment(.leading)
                    }
                }
                // minHeight on the INNER content keeps grid tiles equal-height (Card pads
                // outside); 140 gives the bottom-anchored text block visible air below the chip.
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Check a dose (units drawn → dose)

struct ReverseDoseView: View {
    @State private var massText = "5"
    @State private var massUnit: MassUnit = .milligram
    @State private var solventText = "2"
    @State private var unitsText = "10"
    @State private var syringe: SyringeScale = .u100

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dose: Mass? {
        guard let m = massText.decimalValue, let s = solventText.decimalValue, let u = unitsText.decimalValue else { return nil }
        return try? ReconstitutionCalculator.dose(forUnits: u, vialMass: Mass(m, massUnit),
                                                  solventVolumeMilliliters: s, syringe: syringe)
    }

    /// The typed draw restated as a volume — computed locally in the view (PeptideKit
    /// untouched; the `dose` call above already carries the verified math).
    private var volumeString: String {
        guard let u = unitsText.decimalValue, u >= 0 else { return "—" }
        return String(format: "%.2f mL", u / syringe.unitsPerMilliliter)
    }

    /// Vial strength from the two vial inputs; em-dash until both parse. Strength is derived by
    /// the domain `Concentration` (mass dissolved in a volume), not a hand-rolled formula.
    private var strengthString: String {
        guard let m = massText.decimalValue, m >= 0,
              let s = solventText.decimalValue, s > 0 else { return "—" }
        let mgml = Concentration(mass: Mass(m, massUnit), inMilliliters: s).milligramsPerMilliliter
        return String(format: "%.1f mg/mL", mgml)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Already drew a dose? See how much that actually is.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                // Hero result ABOVE the inputs: the decimal pad covers the bottom of the
                // screen and this recomputes per keystroke — the top is the one region the
                // keyboard can never occlude. Always present (em-dash when inputs don't
                // parse) so the form never bounces under the user's finger. No SyringeGauge
                // here: units are the INPUT — a gauge would echo the question, not answer it.
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        MicroLabel("You drew about")
                        Text(dose?.displayString ?? "—")
                            .font(Typo.numberXL)
                            .foregroundStyle(BrandColor.accentText)
                            .contentTransition(.numericText(value: dose?.micrograms ?? 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: dose?.micrograms)
                        HStack(spacing: Space.md) {
                            StatTile(label: "Volume", value: volumeString, compact: true)
                            StatTile(label: "Strength", value: strengthString, compact: true)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("How much peptide was in the vial?", hint: "The amount on the vial label.") {
                            HStack {
                                TextField("e.g. 5", text: $massText).keyboardType(.decimalPad).pinwiseField()
                                MassUnitPicker(selection: $massUnit)
                            }
                        }
                        FieldRow("How much water was added?", hint: "The water it was mixed with.") {
                            HStack {
                                TextField("e.g. 2", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                                Text("mL").foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                        FieldRow("How many units did you draw?", hint: "The mark you filled to on the syringe.") {
                            HStack {
                                TextField("e.g. 10", text: $unitsText).keyboardType(.decimalPad).pinwiseField()
                                Text("units").foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                    }
                }

                SyringeAdvancedCard(selection: $syringe)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: massUnit)
        .sensoryFeedback(.selection, trigger: syringe)
        .navigationTitle("Check a dose")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ramp-up plan (titration schedule)

struct TitrationPreviewView: View {
    @State private var template: TitrationTemplate = TitrationTemplates.wegovy
    @State private var startDate = Date()

    private var phases: [TitrationPlanner.Phase] {
        TitrationPlanner.plan(steps: template.steps, startDate: startDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Example only — the manufacturer's typical label ladder. Informational, not a recommendation or prescription. Discuss any dose with your clinician.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("Which plan?", hint: "Based on each product's label.") {
                            Picker("Plan", selection: $template) {
                                ForEach(TitrationTemplates.all, id: \.id) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.menu).tint(BrandColor.accentText)
                        }
                        FieldRow("Starting when?") {
                            DatePicker("", selection: $startDate, displayedComponents: [.date])
                                .labelsHidden().tint(BrandColor.accentText)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        TitrationLadderBar(phases: phases)
                        SectionHeader(title: "Example ladder")
                        ForEach(phases) { phase in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.dose.displayString).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                    Text("\(phase.startDate.formatted(.dateTime.month().day())) – \(phase.endDate.formatted(.dateTime.month().day())) · \(weeks(phase.durationDays)) wks")
                                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                                }
                                Spacer()
                                if template.initiationOnlyStepIndices.contains(phase.id) {
                                    TagChip(text: "Starter", color: BrandColor.warning)
                                }
                            }
                        }
                    }
                }
                DisclaimerBanner(text: template.note)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .sensoryFeedback(.selection, trigger: template)
        .sensoryFeedback(.selection, trigger: startDate)
        .navigationTitle("Ramp-up plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func weeks(_ days: Int) -> Int {
        Int((Double(days) / 7).rounded())
    }
}

/// A proportional plan-timeline bar for the titration ladder: one segment per phase, width
/// proportional to the phase's share of the full plan; the phase containing today wears the
/// accent fill (none when the plan is entirely past or future). Display-only; a single
/// accessibility element.
private struct TitrationLadderBar: View {
    let phases: [TitrationPlanner.Phase]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private static let gap: CGFloat = 3
    private static let barHeight: CGFloat = 30
    /// Minimum segment width that can carry a dose label without smearing.
    private static let labelMinWidth: CGFloat = 34

    private var currentID: Int? { TitrationPlanner.phase(on: Date(), in: phases)?.id }
    private var totalDays: Int { phases.reduce(0) { $0 + $1.durationDays } }

    var body: some View {
        GeometryReader { geo in
            let available = max(geo.size.width - Self.gap * CGFloat(max(phases.count - 1, 0)), 0)
            HStack(spacing: Self.gap) {
                ForEach(phases) { phase in
                    segment(phase, width: available * CGFloat(phase.durationDays) / CGFloat(max(totalDays, 1)))
                }
            }
        }
        .frame(height: Self.barHeight)
        // Left-anchored grow-in on arrival; instant under Reduce Motion.
        .scaleEffect(x: revealed ? 1 : 0, anchor: .leading)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { revealed = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan timeline")
        .accessibilityValue(summary)
    }

    private func segment(_ phase: TitrationPlanner.Phase, width: CGFloat) -> some View {
        let isCurrent = phase.id == currentID
        return RoundedRectangle(cornerRadius: 4)
            .fill(isCurrent ? BrandColor.accent : BrandColor.surfaceElevated)
            .overlay {
                if !isCurrent {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(BrandColor.stroke, lineWidth: 1)
                }
            }
            .overlay {
                // Dose label only where it fits — squeezed segments stay clean.
                if width > Self.labelMinWidth {
                    Text(phase.dose.displayString)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCurrent ? BrandColor.onAccent : BrandColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: Self.barHeight)
    }

    private var summary: String {
        let base = "\(phases.count) phases over \(Int((Double(totalDays) / 7).rounded())) weeks"
        if let current = TitrationPlanner.phase(on: Date(), in: phases) {
            return base + "; today: \(current.dose.displayString)"
        }
        if let first = phases.first {
            return base + "; starts \(first.startDate.formatted(.dateTime.month().day()))"
        }
        return base
    }
}

// MARK: - Ramp-up plan (user-built, attached to a protocol)

/// Build a custom dose ladder for one of your protocols. Each phase is a dose held for a number
/// of weeks; once saved, the protocol's dose auto-advances to the next phase as time passes, so
/// logging always uses the current step. Informational planning aid — not a prescription.
struct RampUpPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]

    @State private var selectedID: UUID?
    @State private var startDate = Date()
    @State private var phases: [EditablePhase] = []

    private struct EditablePhase: Identifiable {
        let id = UUID()
        var doseText: String
        var unit: MassUnit
        var weeksText: String
    }

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var selected: SavedProtocol? { activeProtocols.first { $0.id == selectedID } }

    private var canSave: Bool {
        selected != nil && !phases.isEmpty && phases.allSatisfy {
            ($0.doseText.decimalValue ?? 0) > 0 && (Int($0.weeksText) ?? 0) > 0
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Build your own ramp-up. Pick a protocol, set each dose and how long it lasts — your protocol's dose steps up on its own as each phase ends, so logging always uses the right amount.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                if activeProtocols.isEmpty {
                    Card {
                        Text("Add an active protocol first, then come back to build its ramp-up plan.")
                            .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    protocolPickerCard
                    if selected != nil {
                        phasesCard
                        if !phases.isEmpty { previewCard }
                        PrimaryButton(title: (selected?.hasRampPlan ?? false) ? "Update ramp-up plan" : "Start ramp-up plan",
                                      systemImage: "chart.line.uptrend.xyaxis") { save() }
                            .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                        if selected?.hasRampPlan == true {
                            Button(role: .destructive) { removePlan() } label: {
                                Label("Remove ramp-up plan", systemImage: "trash")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, Space.sm)
                                    .foregroundStyle(BrandColor.danger)
                            }
                        }
                    }
                }

                Text("Informational planning aid, not medical advice. Discuss any dose change with your clinician.")
                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Ramp-up plan")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedID) { _, _ in loadForSelection() }
    }

    private var protocolPickerCard: some View {
        Card {
            FieldRow("Which protocol?") {
                Menu {
                    ForEach(activeProtocols) { p in Button(p.name) { selectedID = p.id } }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(selected?.name ?? "Select a protocol").lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.body.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                }
            }
        }
    }

    private var phasesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.lg) {
                FieldRow("Start on") {
                    DatePicker("", selection: $startDate, displayedComponents: [.date])
                        .labelsHidden().tint(BrandColor.accentText)
                }
                Divider().overlay(BrandColor.stroke)
                ForEach($phases) { $phase in
                    HStack(spacing: Space.sm) {
                        TextField("dose", text: $phase.doseText).keyboardType(.decimalPad).pinwiseField().frame(maxWidth: 84)
                        MassUnitPicker(selection: $phase.unit)
                        Text("for").font(.caption).foregroundStyle(BrandColor.textSecondary)
                        TextField("4", text: $phase.weeksText).keyboardType(.numberPad).pinwiseField().frame(maxWidth: 44)
                        Text("wks").font(.caption).foregroundStyle(BrandColor.textSecondary)
                        Spacer(minLength: 0)
                        if phases.count > 1 {
                            Button { phases.removeAll { $0.id == phase.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(BrandColor.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { addPhase() } label: {
                    Label("Add a phase", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Preview")
                ForEach(Array(computedRanges.enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(r.dose).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Spacer()
                        Text(r.range).font(.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                }
            }
        }
    }

    /// Cumulative date ranges for the phases as currently edited (for the preview).
    private var computedRanges: [(dose: String, range: String)] {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: startDate)
        var out: [(String, String)] = []
        for phase in phases {
            let weeks = max(Int(phase.weeksText) ?? 0, 0)
            let end = cal.date(byAdding: .day, value: weeks * 7, to: cursor) ?? cursor
            let doseStr = phase.doseText.decimalValue.map { Mass($0, phase.unit).displayString(in: phase.unit) } ?? "—"
            let rangeStr = "\(cursor.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
            out.append((doseStr, rangeStr))
            cursor = end
        }
        return out
    }

    private func unit(for p: SavedProtocol) -> MassUnit { p.primaryItem?.doseUnit ?? .milligram }

    private func addPhase() {
        let last = phases.last
        phases.append(EditablePhase(doseText: last?.doseText ?? "", unit: last?.unit ?? .milligram, weeksText: "4"))
    }

    private func loadForSelection() {
        guard let p = selected else { phases = []; return }
        let u = unit(for: p)
        if p.hasRampPlan {
            startDate = p.rampStartDate ?? Date()
            phases = p.rampPhases.map {
                EditablePhase(doseText: Self.numText(Mass(micrograms: $0.doseMicrograms).value(in: u)),
                              unit: u, weeksText: String(max($0.durationDays / 7, 1)))
            }
        } else {
            startDate = Date()
            phases = [EditablePhase(doseText: Self.numText(p.effectiveDose.value(in: u)), unit: u, weeksText: "4")]
        }
    }

    private func save() {
        guard let p = selected else { return }
        p.rampPhases = phases.compactMap { ph in
            guard let d = ph.doseText.decimalValue, d > 0, let w = Int(ph.weeksText), w > 0 else { return nil }
            return RampPhase(doseMicrograms: Mass(d, ph.unit).micrograms, durationDays: w * 7)
        }
        p.rampStartDate = Calendar.current.startOfDay(for: startDate)
        try? context.save()
        dismiss()
    }

    private func removePlan() {
        guard let p = selected else { return }
        p.rampPhases = []
        p.rampStartDate = nil
        try? context.save()
        dismiss()
    }

    private static func numText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}
