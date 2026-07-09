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
    /// Trailing window for the trend chart. `all` (the default) preserves the original
    /// full-history behavior; the shorter windows are Oura-style trailing slices.
    private enum ChartRange: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "All"
        var id: String { rawValue }
        /// nil = no cutoff (full history).
        var days: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .all: return nil
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("weightInPounds") private var weightInPounds = true
    @Query(sort: \BiomarkerEntry.timestamp, order: .reverse) private var entries: [BiomarkerEntry]

    @State private var selected: BiomarkerType = .weight
    @State private var valueText = ""
    @State private var note = ""
    @State private var savedCount = 0
    @State private var range: ChartRange = .all
    @State private var scrubDate: Date?
    @State private var health = HealthManager.shared

    private var seriesForSelected: [BiomarkerEntry] {
        entries.filter { $0.typeRaw == selected.rawValue }.sorted { $0.timestamp < $1.timestamp }
    }

    /// The chart's slice of the series — the selected trailing window.
    private var chartSeries: [BiomarkerEntry] {
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return seriesForSelected
        }
        return seriesForSelected.filter { $0.timestamp >= cutoff }
    }

    /// Scrub target: the charted entry nearest the touched x-position's date.
    private var scrubbedEntry: BiomarkerEntry? {
        guard let date = scrubDate else { return nil }
        return chartSeries.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }

    /// Latest-vs-previous difference across the FULL series. Deliberately neutral: whether
    /// "down" is good is unknowable per user (weight down is a GLP-1 goal but a bulking-phase
    /// loss), so the delta chip never wears a status color.
    private var deltaVsPrevious: Double? {
        guard seriesForSelected.count >= 2 else { return nil }
        return seriesForSelected[seriesForSelected.count - 1].value
            - seriesForSelected[seriesForSelected.count - 2].value
    }

    private var canSave: Bool { (valueText.decimalValue ?? 0) > 0 }

    /// Y domain fitted to the charted window with headroom — a 170–190 lb weight series reads
    /// as its own range, not a sliver above zero. Position (not bar area) encodes the value on
    /// a line chart, so the axis doesn't need to include zero.
    private var yDomain: ClosedRange<Double> {
        let values = chartSeries.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = (hi - lo) > 0 ? (hi - lo) * 0.15 : Swift.max(hi * 0.05, 1)
        return Swift.max(0, lo - pad)...(hi + pad)
    }

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
                            VStack(alignment: .leading, spacing: Space.sm) {
                                HStack {
                                    TextField(selected.placeholder, text: $valueText).keyboardType(.decimalPad).pinwiseField()
                                    Text(selected.unit(pounds: weightInPounds)).foregroundStyle(BrandColor.textSecondary)
                                }
                                healthPrefillButton
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
                    trendCard
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
                                        .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.data)
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

            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Labs & metrics")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: savedCount)
        .task { await health.refreshIfConnected() }
        .onChange(of: selected) { scrubDate = nil }
        .onChange(of: range) { scrubDate = nil }
    }

    // MARK: - Trend card

    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                trendHero
                trendChart
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: range)
            }
        }
    }

    /// Latest reading as the headline — the number is the headline; the chart supports it.
    /// Pinned to the full series: range switches and scrubbing never move it.
    private var trendHero: some View {
        let latest = seriesForSelected.last?.value ?? 0
        return VStack(alignment: .leading, spacing: Space.xs) {
            MicroLabel(selected.rawValue)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(format(latest))
                    .font(Typo.numberLG)
                    .foregroundStyle(BrandColor.data)
                    .contentTransition(.numericText(value: latest))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: latest)
                Text(selected.unit(pounds: weightInPounds))
                    .font(.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                if let delta = deltaVsPrevious {
                    deltaChip(delta)
                        .padding(.leading, Space.xs)
                }
            }
        }
    }

    /// Neutral delta vs the previous entry (A7) — direction glyph + magnitude, no status color.
    private func deltaChip(_ delta: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: delta < 0 ? "arrow.down" : "arrow.up")
                .font(.system(size: 9, weight: .semibold))
            Text(format(abs(delta)) + " " + selected.unit(pounds: weightInPounds))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(BrandColor.textSecondary)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(BrandColor.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: 1))
    }

    /// Single-series trend in the labs domain teal. Interpolation is `.monotone`, not
    /// catmullRom — overshoot between sparse lab points would fabricate dips that never
    /// happened. Single series → no legend.
    private var trendChart: some View {
        Chart {
            ForEach(chartSeries, id: \.id) { e in
                AreaMark(
                    x: .value("Date", e.timestamp),
                    yStart: .value("Base", yDomain.lowerBound),
                    yEnd: .value(selected.rawValue, e.value)
                )
                .foregroundStyle(BrandColor.data.opacity(0.16))
                .interpolationMethod(.monotone)
                LineMark(x: .value("Date", e.timestamp), y: .value(selected.rawValue, e.value))
                    .foregroundStyle(BrandColor.data)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", e.timestamp), y: .value(selected.rawValue, e.value))
                    .foregroundStyle(BrandColor.data)
                    .symbolSize(36)
            }
            if let s = scrubbedEntry {
                RuleMark(x: .value("Date", s.timestamp))
                    .foregroundStyle(BrandColor.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", s.timestamp), y: .value(selected.rawValue, s.value))
                    .foregroundStyle(BrandColor.data)
                    .symbolSize(90)
                    .annotation(position: .top) { scrubBadge(for: s) }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $scrubDate)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(BrandColor.stroke)
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(BrandColor.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(BrandColor.stroke)
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(BrandColor.textSecondary)
            }
        }
        .frame(height: 200)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: range)
    }

    /// Value + short date over the scrubbed point. Real-time and deliberately silent — chart
    /// scrubbing gets NO haptic (the Strava rule; see the haptic vocabulary in PinWiseTheme).
    private func scrubBadge(for e: BiomarkerEntry) -> some View {
        HStack(spacing: Space.xs) {
            Text(format(e.value))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(BrandColor.textPrimary)
            Text(e.timestamp, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(BrandColor.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: 1))
    }

    // MARK: - Health prefill (A9)

    /// One-tap prefill from Apple Health — weight only, only when Health is connected and has
    /// a reading. Converts kg → lb to match the user's display unit.
    @ViewBuilder
    private var healthPrefillButton: some View {
        if selected == .weight, health.authorized, let kg = health.latestWeightKg {
            let display = weightInPounds ? kg * 2.20462 : kg
            Button { valueText = format(display) } label: {
                Text("Use Health weight — \(format(display)) \(selected.unit(pounds: weightInPounds))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.data)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Pieces

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
        guard let v = valueText.decimalValue, v > 0 else { return }
        context.insert(BiomarkerEntry(typeRaw: selected.rawValue, value: v, notes: note))
        try? context.save()
        valueText = ""
        note = ""
        savedCount += 1
    }
}
