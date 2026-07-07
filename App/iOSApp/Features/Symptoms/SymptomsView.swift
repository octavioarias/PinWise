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

/// Log side effects with a severity and see how they trend over the last month — the most-
/// requested capability most trackers skip.
struct SymptomsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var entries: [SymptomEntry]

    @State private var selected: SymptomType = .nausea
    @State private var severity: Double = 3
    @State private var note = ""
    @State private var savedCount = 0

    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast }
    private var recentWindow: [SymptomEntry] { entries.filter { $0.timestamp >= cutoff } }

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
                        }
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack {
                                Text("How strong?").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Spacer()
                                Text("\(Int(severity)) / 10").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                            }
                            Slider(value: $severity, in: 0...10, step: 1).tint(BrandColor.accent)
                        }
                        FieldRow("Note", hint: "Optional.") {
                            TextField("Anything worth remembering", text: $note, axis: .vertical).pinwiseField()
                        }
                        PrimaryButton(title: "Log symptom", systemImage: "plus") { save() }
                    }
                }

                if !recentWindow.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Last 30 days")
                            Chart(recentWindow) { e in
                                PointMark(
                                    x: .value("Day", e.timestamp),
                                    y: .value("Severity", e.severity)
                                )
                                .foregroundStyle(by: .value("Symptom", e.symptomRaw))
                                .symbolSize(60)
                            }
                            .chartYScale(domain: 0...10)
                            .chartForegroundStyleScale(range: chartColors)
                            .frame(height: 200)
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
                                        Text(e.symptomRaw).font(.body).foregroundStyle(BrandColor.textPrimary)
                                        if !e.notes.isEmpty {
                                            Text(e.notes).font(.caption2).foregroundStyle(BrandColor.textSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("\(e.severity)/10").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
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

    private var chartColors: [Color] {
        [BrandColor.accentText, BrandColor.success, BrandColor.warning, BrandColor.danger,
         Color(hex: 0x8A97FF), Color(hex: 0x18E39A), Color(hex: 0xFFB020), Color(hex: 0xFF7AB0), Color(hex: 0x7FB4FF)]
    }

    private func chip(_ s: SymptomType) -> some View {
        let isOn = selected == s
        return Button { selected = s } label: {
            Label(s.rawValue, systemImage: s.icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(isOn ? BrandColor.accent : BrandColor.surfaceElevated, in: Capsule())
                .foregroundStyle(isOn ? BrandColor.onAccent : BrandColor.textSecondary)
                .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let e = SymptomEntry(symptomRaw: selected.rawValue, severity: Int(severity), notes: note)
        context.insert(e)
        try? context.save()
        note = ""
        savedCount += 1
    }
}
