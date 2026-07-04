import SwiftUI
import PeptideKit

/// The Tools tab — a grid of calculators, each backed by verified PeptideKit logic.
struct ToolsView: View {
    private let columns = [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header
                    LazyVGrid(columns: columns, spacing: Space.md) {
                        ToolCard(title: "Reconstitution", subtitle: "Powder or pre-mixed → units", systemImage: "syringe.fill") {
                            ReconstitutionCalculatorView()
                        }
                        ToolCard(title: "Reverse dose", subtitle: "Units drawn → dose", systemImage: "arrow.uturn.backward") {
                            ReverseDoseView()
                        }
                        ToolCard(title: "Blend", subtitle: "One draw → each component", systemImage: "circle.grid.2x2.fill") {
                            BlendCalculatorView()
                        }
                        ToolCard(title: "Titration", subtitle: "GLP-1 escalation schedule", systemImage: "chart.line.uptrend.xyaxis") {
                            TitrationPreviewView()
                        }
                    }
                    DisclaimerBanner(text: Disclaimer.calculator)
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
                .font(Typo.displayL).textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
            Text("Calculators for accurate, confident dosing.")
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
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Reverse dose (units drawn → dose)

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
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Vial")
                        HStack {
                            TextField("Amount", text: $massText).keyboardType(.decimalPad).pinwiseField()
                            unitPicker($massUnit)
                        }
                        HStack {
                            TextField("Water", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                            Text("mL").foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Drawn")
                        HStack {
                            TextField("Units", text: $unitsText).keyboardType(.decimalPad).pinwiseField()
                            Text("units").foregroundStyle(BrandColor.textSecondary)
                        }
                        Picker("Syringe", selection: $syringe) {
                            ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu).tint(BrandColor.accentText)
                    }
                }
                if let d = dose {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "That's about")
                            StatTile(label: "Dose", value: d.displayString, emphasized: true)
                        }
                    }
                }
                DisclaimerBanner(text: Disclaimer.calculator)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Reverse dose")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unitPicker(_ binding: Binding<MassUnit>) -> some View {
        Picker("", selection: binding) {
            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(width: 120)
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
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Blend")
                        Picker("Blend", selection: $blend) {
                            ForEach(BlendPresets.all, id: \.id) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.menu).tint(BrandColor.accentText)
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
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Mix & draw")
                        HStack {
                            TextField("Water", text: $solventText).keyboardType(.decimalPad).pinwiseField()
                            Text("mL").foregroundStyle(BrandColor.textSecondary)
                        }
                        HStack {
                            TextField("Draw", text: $unitsText).keyboardType(.decimalPad).pinwiseField()
                            Text("units").foregroundStyle(BrandColor.textSecondary)
                        }
                        Picker("Syringe", selection: $syringe) {
                            ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu).tint(BrandColor.accentText)
                    }
                }
                if let r = result {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Each dose delivers")
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
                DisclaimerBanner(text: Disclaimer.researchCompound)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Blend")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Titration schedule preview

struct TitrationPreviewView: View {
    @State private var template: TitrationTemplate = TitrationTemplates.wegovy
    @State private var startDate = Date()

    private var phases: [TitrationPlanner.Phase] {
        TitrationPlanner.plan(steps: template.steps, startDate: startDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Template")
                        Picker("Template", selection: $template) {
                            ForEach(TitrationTemplates.all, id: \.id) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.menu).tint(BrandColor.accentText)
                        DatePicker("Start date", selection: $startDate, displayedComponents: [.date])
                            .tint(BrandColor.accentText)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Schedule")
                        ForEach(phases) { phase in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.dose.displayString).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                    Text("\(phase.startDate.formatted(.dateTime.month().day())) – \(phase.endDate.formatted(.dateTime.month().day()))")
                                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                                }
                                Spacer()
                                if template.initiationOnlyStepIndices.contains(phase.id) {
                                    TagChip(text: "Initiation", color: BrandColor.warning)
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
        .navigationTitle("Titration")
        .navigationBarTitleDisplayMode(.inline)
    }
}
