import SwiftUI
import SwiftData
import Charts

/// Labs & body metrics people track alongside a protocol. Stored as BiomarkerEntry.typeRaw.
enum BiomarkerType: String, CaseIterable, Identifiable {
    case weight = "Weight"
    case a1c = "A1c"
    case glucose = "Fasting glucose"
    case totalChol = "Total cholesterol"
    case ldl = "LDL"
    case hdl = "HDL"
    case triglycerides = "Triglycerides"
    case systolic = "Systolic BP"
    case diastolic = "Diastolic BP"
    case waist = "Waist"
    var id: String { rawValue }

    func unit(pounds: Bool) -> String {
        switch self {
        case .weight: return pounds ? "lb" : "kg"
        case .a1c: return "%"
        case .glucose, .totalChol, .ldl, .hdl, .triglycerides: return "mg/dL"
        case .systolic, .diastolic: return "mmHg"
        case .waist: return pounds ? "in" : "cm"
        }
    }
    var placeholder: String {
        switch self {
        case .weight: return "e.g. 180"
        case .a1c: return "e.g. 5.4"
        case .glucose: return "e.g. 92"
        case .totalChol: return "e.g. 170"
        case .ldl: return "e.g. 90"
        case .hdl: return "e.g. 55"
        case .triglycerides: return "e.g. 110"
        case .systolic: return "e.g. 118"
        case .diastolic: return "e.g. 76"
        case .waist: return "e.g. 34"
        }
    }
}

/// Log labs and body metrics and watch them move as your protocol goes on.
struct BiomarkersView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("weightInPounds") private var weightInPounds = true
    @Query(sort: \BiomarkerEntry.timestamp, order: .reverse) private var entries: [BiomarkerEntry]

    @State private var selected: BiomarkerType = .weight
    @State private var valueText = ""
    @State private var note = ""
    @State private var savedCount = 0

    private var seriesForSelected: [BiomarkerEntry] {
        entries.filter { $0.typeRaw == selected.rawValue }.sorted { $0.timestamp < $1.timestamp }
    }
    private var canSave: Bool { (Double(valueText) ?? 0) > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Log labs and body metrics — A1c, glucose, lipids, blood pressure, weight — and watch them trend with your protocol.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                Card {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        FieldRow("Which metric?") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Space.sm) {
                                    ForEach(BiomarkerType.allCases) { t in chip(t) }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        FieldRow("Value") {
                            HStack {
                                TextField(selected.placeholder, text: $valueText).keyboardType(.decimalPad).pinwiseField()
                                Text(selected.unit(pounds: weightInPounds)).foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                        FieldRow("Note", hint: "Optional — e.g. \"fasting\", \"post-workout\".") {
                            TextField("Anything worth remembering", text: $note, axis: .vertical).pinwiseField()
                        }
                        PrimaryButton(title: "Log \(selected.rawValue)", systemImage: "plus") { save() }
                            .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                    }
                }

                if seriesForSelected.count >= 2 {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "\(selected.rawValue) trend")
                            Chart(seriesForSelected, id: \.id) { e in
                                LineMark(x: .value("Date", e.timestamp), y: .value(selected.rawValue, e.value))
                                    .foregroundStyle(BrandColor.accentText)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Date", e.timestamp), y: .value(selected.rawValue, e.value))
                                    .foregroundStyle(BrandColor.accentText)
                            }
                            .frame(height: 200)
                        }
                    }
                } else if !seriesForSelected.isEmpty {
                    Text("Log \(selected.rawValue) at least twice to see a trend.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }

                if !entries.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Recent")
                            ForEach(Array(entries.prefix(14)), id: \.id) { e in
                                let type = BiomarkerType(rawValue: e.typeRaw)
                                HStack {
                                    Text(e.typeRaw).font(.body).foregroundStyle(BrandColor.textPrimary)
                                    Spacer()
                                    Text(format(e.value) + " " + (type?.unit(pounds: weightInPounds) ?? ""))
                                        .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                                    Text(e.timestamp, format: .dateTime.month().day())
                                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(e); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                } else {
                    Text("No metrics logged yet.").font(.caption).foregroundStyle(BrandColor.textSecondary)
                }

                DisclaimerBanner(text: "A personal record of your numbers — not medical advice. Discuss results with a clinician.")
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Labs & metrics")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    private func chip(_ t: BiomarkerType) -> some View {
        let isOn = selected == t
        return Button { selected = t } label: {
            Text(t.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(isOn ? BrandColor.accent : BrandColor.surfaceElevated, in: Capsule())
                .foregroundStyle(isOn ? BrandColor.onAccent : BrandColor.textSecondary)
                .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private func save() {
        guard let v = Double(valueText), v > 0 else { return }
        context.insert(BiomarkerEntry(typeRaw: selected.rawValue, value: v, notes: note))
        try? context.save()
        valueText = ""
        note = ""
        savedCount += 1
    }
}
