import SwiftUI
import SwiftData
import PeptideKit

/// The dashboard — a personalized overview of *your* setup: how on-track you are, the stack
/// you're running, and your connected health metrics. Actions (logging, calculators) live in
/// their own tabs; Home is about what the app understands about you.
struct HomeView: View {
    @Binding var selected: AppTab
    @Binding var showMenu: Bool
    @Binding var showAssistant: Bool
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recent.filter { $0.timestamp >= weekAgo }.count
    }
    private var sitesInRotation: Int { Set(recent.prefix(30).compactMap { $0.site }).count }

    private var adherenceFraction: Double {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: end)) ?? end
        var expected = 0, taken = 0
        for p in activeProtocols {
            let logDates = recent.filter { p.compoundNames.contains($0.compoundName) }.map(\.timestamp)
            let r = AdherenceCalculator.evaluate(schedule: p.schedule,
                                                 start: max(start, cal.startOfDay(for: p.startDate)),
                                                 end: end, logDates: logDates, calendar: cal)
            expected += r.expectedCount
            taken += r.takenCount
        }
        return expected == 0 ? 0 : Double(taken) / Double(expected)
    }
    private var nextDoseDate: Date? { activeProtocols.compactMap { $0.nextDose() }.min() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    // Dosing leads; the (optional) health snapshot sits below it.
                    if !activeProtocols.isEmpty {
                        heroActive
                        stackCard
                        bentoGrid
                    } else if !recent.isEmpty {
                        heroActivity
                        bentoGrid
                    } else {
                        emptyState
                    }
                    HomeHealthCard()
                    if !recent.isEmpty { recentSection }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Button { showMenu = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BrandColor.textPrimary)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Menu — profile, settings, and health connections")

                Spacer()

                Button { showAssistant = true } label: {
                    Image(systemName: "sparkles")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BrandColor.accentText)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Assistant")
            }

            Text("Track your protocol.\nKnow the science.")
                .font(Typo.screenTitle)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero

    private var heroActive: some View {
        HStack(spacing: Space.lg) {
            AdherenceRing(fraction: adherenceFraction, size: 96)
            VStack(alignment: .leading, spacing: Space.lg) {
                heroStat("Next dose", nextDoseText)
                heroStat("This week", "\(thisWeekCount) logged")
            }
            Spacer(minLength: 0)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HeroSurface())
    }

    private var heroActivity: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(thisWeekCount)").font(Typo.numberXL).foregroundStyle(BrandColor.textPrimary)
                Text("Doses logged this week").font(Typo.body).foregroundStyle(BrandColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "syringe.fill").font(.system(size: 40)).foregroundStyle(BrandColor.accentText)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HeroSurface())
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
            Text(value).font(Typo.numberMD).foregroundStyle(BrandColor.textPrimary)
        }
    }

    // MARK: Your stack (personalization)

    private var stackCard: some View {
        Button { selected = .protocols } label: {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        SectionHeader(title: "Your protocols")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                    }
                    ForEach(activeProtocols.prefix(4), id: \.id) { p in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.body.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                                Text("\(p.contentsSummary) · \(p.cadenceText)")
                                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                            }
                            Spacer()
                            Text(p.effectiveDose.displayString).font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                        }
                    }
                    if activeProtocols.count > 4 {
                        Text("+\(activeProtocols.count - 4) more").font(.caption2).foregroundStyle(BrandColor.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Bento

    private var bentoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)],
                  spacing: Space.md) {
            bentoTile("Sites in rotation", "\(sitesInRotation)", "circle.grid.3x3.fill")
            // Total doses logged — not shown elsewhere (the hero shows "this week"); the stack
            // card already lists active protocols, so don't repeat that count here.
            bentoTile("Doses logged", "\(recent.count)", "syringe.fill")
        }
    }

    private func bentoTile(_ label: String, _ value: String, _ icon: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: icon).font(.title3).foregroundStyle(BrandColor.accentText)
                Spacer(minLength: Space.sm)
                Text(value).font(Typo.numberLG).foregroundStyle(BrandColor.textPrimary)
                Text(label.uppercased()).font(Typo.caption).tracking(0.6).foregroundStyle(BrandColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        }
    }

    // MARK: Recent / empty

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Recent")
            ForEach(Array(recent.prefix(4)), id: \.id) { entry in
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
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Get started")
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Add your first vial").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text("Head to Stack ▸ My Vials — add a compound or blend, build a protocol from it, then log. Home fills in with your adherence and health as you go.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    PrimaryButton(title: "Go to Stack", systemImage: "square.stack.3d.up.fill") { selected = .protocols }
                        .padding(.top, Space.sm)
                }
            }
        }
    }

    private var nextDoseText: String {
        guard let d = nextDoseDate else { return "—" }
        return d.formatted(.dateTime.weekday(.abbreviated).month().day())
    }
}

/// The hero surface — a deep-blue gradient wash + rim light so the focal card reads as elevated
/// and distinct from the flat bento tiles below it.
private struct HeroSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(colors: [BrandColor.deepBlue.opacity(0.5), BrandColor.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.16), BrandColor.stroke.opacity(0.6), BrandColor.stroke],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
    }
}

/// A unified health snapshot — the top card on Home. Merges connector metrics (Apple Health:
/// weight, resting HR, HRV, sleep, steps) with the user's logged biomarkers (A1c, glucose, BP,
/// LDL, weight). Always visible: shows a metrics grid when there's data, otherwise a one-line
/// invite to connect a wearable or log a lab. Tap to open Labs & metrics; connecting Health
/// lives in the menu.
struct HomeHealthCard: View {
    @AppStorage("weightInPounds") private var pounds = true
    @State private var health = HealthManager.shared
    @Query(sort: \BiomarkerEntry.timestamp, order: .reverse) private var biomarkers: [BiomarkerEntry]

    private struct Metric: Identifiable { let id = UUID(); let label: String; let value: String }

    private func latest(_ type: BiomarkerType) -> BiomarkerEntry? { biomarkers.first { $0.typeRaw == type.rawValue } }

    private var metrics: [Metric] {
        var out: [Metric] = []
        if health.authorized {
            if let kg = health.latestWeightKg {
                out.append(.init(label: "Weight", value: String(format: pounds ? "%.0f" : "%.1f", pounds ? kg * 2.20462 : kg) + (pounds ? " lb" : " kg")))
            }
            if let hr = health.restingHeartRate { out.append(.init(label: "Resting HR", value: "\(Int(hr.rounded())) bpm")) }
            if let hrv = health.hrvMilliseconds { out.append(.init(label: "HRV", value: "\(Int(hrv.rounded())) ms")) }
            if let sleep = health.sleepHoursLastNight { out.append(.init(label: "Sleep", value: String(format: "%.1f h", sleep))) }
            if let steps = health.stepsToday { out.append(.init(label: "Steps", value: Int(steps).formatted())) }
        }
        let haveWeight = out.contains { $0.label == "Weight" }
        for type in [BiomarkerType.weight, .a1c, .glucose, .systolic, .ldl] {
            if type == .weight && haveWeight { continue }
            if let e = latest(type) {
                let v = e.value == e.value.rounded() ? String(Int(e.value)) : String(format: "%.1f", e.value)
                out.append(.init(label: type.rawValue, value: v + " " + type.unit(pounds: pounds)))
            }
        }
        return Array(out.prefix(6))
    }

    var body: some View {
        NavigationLink { BiomarkersView() } label: {
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack {
                        SectionHeader(title: "Your health")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                    }
                    if metrics.isEmpty {
                        Text("Connect a wearable (menu → Connections) or log a lab, and your weight, HRV, sleep, and more show up here.")
                            .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)], spacing: Space.md) {
                            ForEach(metrics) { m in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.label.uppercased()).font(Typo.caption).tracking(0.6).foregroundStyle(BrandColor.textSecondary)
                                    Text(m.value).font(Typo.numberMD).foregroundStyle(BrandColor.textPrimary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .task { if health.authorized { await health.refresh() } }
    }
}
