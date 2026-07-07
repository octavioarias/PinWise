import SwiftUI
import PeptideKit

/// The Tools tab — a grid of plain-language calculators, each backed by verified PeptideKit.
struct ToolsView: View {
    private let columns = [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header
                    LazyVGrid(columns: columns, spacing: Space.md) {
                        ToolCard(title: "How much to draw", subtitle: "Get your syringe amount", systemImage: "syringe.fill") {
                            ReconstitutionCalculatorView()
                        }
                        ToolCard(title: "Check a dose", subtitle: "What a draw equals", systemImage: "arrow.uturn.backward") {
                            ReverseDoseView()
                        }
                        ToolCard(title: "Blend", subtitle: "Doses in a mixed vial", systemImage: "circle.grid.2x2.fill") {
                            BlendCalculatorView()
                        }
                        ToolCard(title: "Ramp-up plan", subtitle: "Typical label ladder (reference)", systemImage: "chart.line.uptrend.xyaxis") {
                            TitrationPreviewView()
                        }
                        ToolCard(title: "Injection map", subtitle: "Where you've been pinning", systemImage: "figure.stand") {
                            BodyMapView()
                        }
                        ToolCard(title: "How you feel", subtitle: "Track side effects over time", systemImage: "heart.text.square") {
                            SymptomsView()
                        }
                        ToolCard(title: "Labs & metrics", subtitle: "Weight, A1c, lipids, BP trends", systemImage: "chart.xyaxis.line") {
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
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .padding(Space.lg)
            .background(
                LinearGradient(colors: [BrandColor.surface, BrandColor.surfaceElevated.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
    Picker("", selection: binding) {
        ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented).frame(width: 120)
}

// MARK: - Check a dose (units drawn → dose)

struct ReverseDoseView: View {
    @State private var massText = "5"
    @State private var massUnit: MassUnit = .milligram
    @State private var solventText = "2"
    @State private var unitsText = "10"
    @State private var syringe: SyringeScale = .u100

    private var dose: Mass? {
        guard let m = Double(massText), let s = Double(solventText), let u = Double(unitsText) else { return nil }
        return try? ReconstitutionCalculator.dose(forUnits: u, vialMass: Mass(m, massUnit),
                                                  solventVolumeMilliliters: s, syringe: syringe)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Already drew a dose? See how much that actually is.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("How much peptide was in the vial?", hint: "The amount on the vial label.") {
                            HStack {
                                TextField("e.g. 5", text: $massText).keyboardType(.decimalPad).pinwiseField()
                                unitPicker($massUnit)
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

                syringeAdvanced($syringe)

                if let d = dose {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("YOU DREW ABOUT").font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
                            Text(d.displayString).font(Typo.numberXL).foregroundStyle(BrandColor.accentText)
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Check a dose")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Blend (one draw → each component's dose)

struct BlendCalculatorView: View {
    @State private var blend: Blend = BlendPresets.wolverine
    @State private var solventText = "2"
    @State private var unitsText = "20"
    @State private var syringe: SyringeScale = .u100

    private var result: BlendDoseResult? {
        guard let s = Double(solventText), let u = Double(unitsText) else { return nil }
        return try? BlendCalculator.dose(blend: blend, solventVolumeMilliliters: s, syringeUnits: u, syringe: syringe)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("A vial with more than one peptide? See how much of each you get per shot.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        FieldRow("Which blend?", hint: "Pick a common blend, or the closest match.") {
                            Picker("Blend", selection: $blend) {
                                ForEach(BlendPresets.all, id: \.id) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.menu).tint(BrandColor.accentText)
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
                syringeAdvanced($syringe)

                if let r = result {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("EACH SHOT GIVES YOU").font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
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
        .navigationTitle("Blend")
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
                        SectionHeader(title: "Example ladder")
                        ForEach(phases) { phase in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.dose.displayString).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                    Text("\(phase.startDate.formatted(.dateTime.month().day())) – \(phase.endDate.formatted(.dateTime.month().day()))")
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
        .navigationTitle("Ramp-up plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared "Advanced — syringe type" disclosure (hidden by default; most people use U-100).
private func syringeAdvanced(_ binding: Binding<SyringeScale>) -> some View {
    Card {
        DisclosureGroup {
            Picker("Syringe type", selection: binding) {
                ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Most insulin syringes are U-100. Only change this if yours says otherwise.")
                .font(.caption).foregroundStyle(BrandColor.textSecondary).padding(.top, Space.xs)
        } label: {
            Text("Advanced — syringe type").font(.caption).foregroundStyle(BrandColor.textSecondary)
        }
        .tint(BrandColor.accentText)
    }
}
