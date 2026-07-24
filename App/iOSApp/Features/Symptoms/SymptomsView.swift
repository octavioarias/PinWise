import SwiftUI
import SwiftData
import Charts

/// Common side effects people track on peptides / GLP-1s. Stored as SymptomEntry.symptomRaw.
enum SymptomType: String, CaseIterable, Identifiable {
    case nausea = "Nausea"
    case fatigue = "Fatigue"
    case giUpset = "GI upset"
    case constipation = "Constipation"
    case injectionSite = "Injection-site reaction"
    case appetite = "Appetite change"
    case headache = "Headache"
    case mood = "Mood"
    case sleep = "Sleep"
    var id: String { rawValue }
    /// User-facing label. Decoupled from the stored `rawValue` (the permanent storage key) so
    /// future copy edits never rewrite stored data. Returns today's strings verbatim.
    var displayName: String {
        switch self {
        case .nausea: return "Nausea"
        case .fatigue: return "Fatigue"
        case .giUpset: return "GI upset"
        case .constipation: return "Constipation"
        case .injectionSite: return "Injection-site reaction"
        case .appetite: return "Appetite change"
        case .headache: return "Headache"
        case .mood: return "Mood"
        case .sleep: return "Sleep"
        }
    }
    var icon: String {
        switch self {
        case .nausea: return "face.dashed"
        case .fatigue: return "battery.25"
        case .giUpset, .constipation: return "wind"
        case .injectionSite: return "bandage"
        case .appetite: return "fork.knife"
        case .headache: return "brain.head.profile"
        case .mood: return "face.smiling"
        case .sleep: return "bed.double"
        }
    }
}

/// Chart encoding: nine symptoms on ChartPalette's five categorical colors — the palette
/// repeats after index 4 and the symbol SHAPE becomes the secondary encoding (circles for
/// the first pass, squares for the repeat) so repeated hues stay distinguishable. Declared
/// in `allCases` order and applied through explicit chart scales, so the mapping never
/// depends on the order data arrives in.
extension SymptomType {
    private var caseIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var chartColor: Color { ChartPalette.categorical[caseIndex % ChartPalette.categorical.count] }
    var chartSymbol: BasicChartSymbolShape { caseIndex < ChartPalette.categorical.count ? .circle : .square }
}

/// Log side effects with a severity and see how they trend over the last month — the most-
/// requested capability most trackers skip.
struct SymptomsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var entries: [SymptomEntry]

    @State private var selected: SymptomType = .nausea
    @State private var severity: Double = 3
    @State private var note = ""
    @State private var savedCount = 0
    @State private var range: ChartRange = .thirtyDays

    /// The windows this view offers — the shared `ChartRange` also carries `.all`, which Symptoms
    /// deliberately omits (this list, not `allCases`, drives the picker so behavior is unchanged).
    private let rangeOptions: [ChartRange] = [.sevenDays, .thirtyDays, .ninetyDays]

    /// Widest selectable window — gates the chart card, so narrowing the range to an empty
    /// week can never make the range control itself disappear. (`.ninetyDays.days` is never nil.)
    private var chartCutoff: Date { Calendar.current.date(byAdding: .day, value: -(ChartRange.ninetyDays.days ?? 90), to: Date()) ?? .distantPast }
    private var chartableEntries: [SymptomEntry] { entries.filter { $0.timestamp >= chartCutoff } }
    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -(range.days ?? 90), to: Date()) ?? .distantPast }
    private var recentWindow: [SymptomEntry] { entries.filter { $0.timestamp >= cutoff } }
    private var distinctSymptomCount: Int { Set(recentWindow.map(\.symptomRaw)).count }
    /// Only the symptoms actually plotted in the window — an explicit scale domain fixes
    /// the LEGEND to the whole domain, so passing allCases would render nine legend
    /// entries (seven of them dead) for a two-symptom chart. Filtering allCases (not the
    /// window's order of appearance) keeps each symptom's fixed color/shape identity.
    private var plottedSymptoms: [SymptomType] {
        let present = Set(recentWindow.map(\.symptomRaw))
        return SymptomType.allCases.filter { present.contains($0.rawValue) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Log how you're feeling — nausea, fatigue, GI, injection-site reactions and more — and watch it trend as your protocol goes on.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("What are you feeling?") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Space.sm) {
                                    ForEach(SymptomType.allCases) { s in
                                        chip(s)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .sensoryFeedback(.selection, trigger: selected)
                        }
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack {
                                Text("How strong?").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Spacer()
                                Text("\(Int(severity)) / 10").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                            }
                            Slider(value: $severity, in: 0...10, step: 1).tint(BrandColor.accent)
                                .sensoryFeedback(.selection, trigger: Int(severity))
                        }
                        FieldRow("Note", hint: "Optional.") {
                            TextField("Anything worth remembering", text: $note, axis: .vertical).pinwiseField()
                        }
                        PrimaryButton(title: "Log symptom", systemImage: "plus") { save() }
                    }
                }

                if !chartableEntries.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: range.title)
                            Chart(recentWindow) { e in
                                PointMark(
                                    x: .value("Day", e.timestamp),
                                    y: .value("Severity", e.severity)
                                )
                                .foregroundStyle(by: .value("Symptom", e.symptomRaw))
                                .symbol(by: .value("Symptom", e.symptomRaw))
                                .symbolSize(60)
                            }
                            .chartYScale(domain: 0...10)
                            // Both scales share the "Symptom" plottable value and the same
                            // domain (plotted symptoms only), so Swift Charts merges color +
                            // shape into one legend entry per PLOTTED symptom — while each
                            // symptom's color/shape stays fixed by its allCases index.
                            .chartForegroundStyleScale(domain: plottedSymptoms.map(\.rawValue), range: plottedSymptoms.map(\.chartColor))
                            .chartSymbolScale(domain: plottedSymptoms.map(\.rawValue), range: plottedSymptoms.map(\.chartSymbol))
                            .chartLegend(position: .bottom)
                            .chartLegend(distinctSymptomCount > 1 ? .visible : .hidden)
                            .chartXAxis {
                                AxisMarks { _ in
                                    AxisGridLine().foregroundStyle(BrandColor.stroke.opacity(0.5))
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        .font(.system(size: 10))
                                        .foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { _ in
                                    AxisGridLine().foregroundStyle(BrandColor.stroke.opacity(0.5))
                                    AxisValueLabel()
                                        .font(.system(size: 10))
                                        .foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            .frame(height: 200)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: range)

                            Picker("Chart range", selection: $range) {
                                ForEach(rangeOptions) { r in
                                    Text(r.rawValue).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)
                            .sensoryFeedback(.selection, trigger: range)
                        }
                    }
                }

                if !entries.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Recent")
                            ForEach(Array(entries.prefix(12)), id: \.id) { e in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(SymptomType(rawValue: e.symptomRaw)?.displayName ?? e.symptomRaw).font(.body).foregroundStyle(BrandColor.textPrimary)
                                        if !e.notes.isEmpty {
                                            Text(e.notes).font(.caption2).foregroundStyle(BrandColor.textSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("\(e.severity)/10").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                                    Text(e.timestamp.relativeLabel())
                                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(e); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                } else {
                    Text("No symptoms logged yet.").font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("How you feel")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    private func chip(_ s: SymptomType) -> some View {
        SelectableChip(title: s.displayName, isSelected: selected == s, systemImage: s.icon) { selected = s }
    }

    private func save() {
        let e = SymptomEntry(symptomRaw: selected.rawValue, severity: Int(severity), notes: note)
        context.insert(e)
        try? context.save()
        note = ""
        savedCount += 1
    }
}
