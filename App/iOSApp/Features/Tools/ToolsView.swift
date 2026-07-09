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
                        ToolCard(title: "How much to draw", subtitle: "Get your syringe amount", systemImage: "syringe.fill", hue: BrandColor.accentText) {
                            ReconstitutionCalculatorView()
                        }
                        ToolCard(title: "Check a dose", subtitle: "What a draw equals", systemImage: "arrow.uturn.backward", hue: BrandColor.accentText) {
                            ReverseDoseView()
                        }
                        ToolCard(title: "Blend", subtitle: "Doses in a mixed vial", systemImage: "circle.grid.2x2.fill", hue: BrandColor.accentText) {
                            BlendCalculatorView()
                        }
                        ToolCard(title: "Ramp-up plan", subtitle: "Typical label ladder (reference)", systemImage: "chart.line.uptrend.xyaxis", hue: BrandColor.accentText) {
                            TitrationPreviewView()
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
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Tools")
                .font(Typo.screenTitle)
                .foregroundStyle(BrandColor.textPrimary)
            Text("Simple calculators — pick one and answer a couple of questions.")
                .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
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

// MARK: - Blend (one draw → each component's dose)

struct BlendCalculatorView: View {
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @State private var blend: Blend = BlendPresets.wolverine
    @State private var solventText = "2"
    @State private var unitsText = "20"
    @State private var syringe: SyringeScale = .u100

    /// The user's own multi-compound vials — a real blend beats any preset.
    private var blendVials: [StoredVial] { vials.filter { $0.apis.count > 1 } }

    /// Preset list, plus the current blend when it came from a vial (so the picker's
    /// selection always matches one of its options).
    private var blendOptions: [Blend] {
        BlendPresets.all.contains(where: { $0.id == blend.id }) ? BlendPresets.all : [blend] + BlendPresets.all
    }

    private func applyVial(_ v: StoredVial) {
        blend = Blend(name: v.displayName,
                      components: v.apis.map { BlendComponent(name: $0.name, massPerVial: Mass(micrograms: $0.massMicrograms)) })
        if let s = v.solventVolumeMilliliters, s > 0 {
            solventText = s == s.rounded() ? String(Int(s)) : String(format: "%.2f", s)
        }
    }

    private var result: BlendDoseResult? {
        guard let s = solventText.decimalValue, let u = unitsText.decimalValue else { return nil }
        return try? BlendCalculator.dose(blend: blend, solventVolumeMilliliters: s, syringeUnits: u, syringe: syringe)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("A vial with more than one peptide? See how much of each you get per shot.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if !blendVials.isEmpty {
                            Menu {
                                ForEach(blendVials) { v in Button(v.displayName) { applyVial(v) } }
                            } label: {
                                Label("Use one of your blend vials", systemImage: "cross.vial")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandColor.accentText)
                                    .lineLimit(1)
                            }
                        }
                        FieldRow("Which blend?", hint: blendVials.isEmpty ? "Pick a common blend, or the closest match." : "From your vials above, or a common preset.") {
                            Menu {
                                ForEach(blendOptions, id: \.id) { b in Button(b.name) { blend = b } }
                            } label: {
                                HStack(spacing: Space.xs) {
                                    Text(blend.name).lineLimit(1).truncationMode(.tail)
                                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                                }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BrandColor.accentText)
                            }
                        }
                        ForEach(blend.components) { c in
                            HStack {
                                Text(c.name).font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Spacer()
                                Text(c.massPerVial.displayString).font(.caption).foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("How much water did you add?", hint: "The water you mixed the vial with.") {
                            HStack {
                                TextField("e.g. 2", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                                Text("mL").foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                        FieldRow("How many units do you draw?", hint: "The mark you fill to on the syringe.") {
                            HStack {
                                TextField("e.g. 20", text: $unitsText).keyboardType(.decimalPad).pinwiseField()
                                Text("units").foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                    }
                }
                SyringeAdvancedCard(selection: $syringe)

                // Result stays BELOW the inputs — a deliberate asymmetry with the other
                // dose calculators: this card's height varies with 2–4 component rows (top
                // placement would bounce the pickers), and the primary flow here starts
                // with menu selection, not typing.
                if let r = result {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            // Draw hero: what to pull, restated in mL, then the barrel.
                            VStack(alignment: .leading, spacing: Space.xs) {
                                MicroLabel("Draw to")
                                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                                    Text(fmt(r.syringeUnits))
                                        .font(Typo.numberXL)
                                        .foregroundStyle(BrandColor.accentText)
                                    Text("units")
                                        .font(Typo.caption)
                                        .foregroundStyle(BrandColor.textSecondary)
                                }
                                Text("= \(String(format: "%.2f", r.drawVolumeMilliliters)) mL")
                                    .font(Typo.caption)
                                    .foregroundStyle(BrandColor.textSecondary)
                            }
                            SyringeGauge(units: r.syringeUnits, syringe: syringe)
                            Divider().overlay(BrandColor.stroke)
                            MicroLabel("Each shot gives you")
                            ForEach(r.components) { comp in
                                HStack {
                                    Text(comp.name).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                                    Spacer()
                                    Text(comp.deliveredDose.displayString).font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .sensoryFeedback(.selection, trigger: syringe)
        .sensoryFeedback(.selection, trigger: blend.id)
        .navigationTitle("Blend")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Whole draws render bare ("20"), fractional draws keep one decimal ("12.5").
    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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
