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
    @State private var auth = AuthManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Reward layer: highest streak milestone already celebrated (so each one fires once per
    // run), a one-time silent seed so the update doesn't retroactively celebrate a streak the
    // user already had, and the milestone currently being celebrated (nil = none).
    @AppStorage("celebratedStreakMilestone") private var celebratedMilestone = 0
    @AppStorage("didSeedStreakMilestone") private var didSeedStreakMilestone = false
    @State private var celebratingMilestone: Int?

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

    /// On-time dose streak across every active protocol — consecutive scheduled doses taken
    /// with no miss (current), and the best run ever (longest). Same "taken = logged that day"
    /// rule as the adherence % above; today's not-yet-taken dose is pending, never a miss.
    private var streak: StreakCalculator.Result {
        let cal = Calendar.current
        let now = Date()
        var events: [StreakCalculator.DoseEvent] = []
        for p in activeProtocols {
            let logs = recent.filter { p.compoundNames.contains($0.compoundName) }.map(\.timestamp)
            let r = AdherenceCalculator.evaluate(schedule: p.schedule, start: p.startDate,
                                                 end: now, logDates: logs, calendar: cal)
            events += StreakCalculator.events(from: r, asOf: now, calendar: cal)
        }
        return StreakCalculator.compute(events: events)
    }

    private var nextDoseDate: Date? { activeProtocols.compactMap { $0.nextDose() }.min() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header.entrance(0)
                    // Dosing leads; the (optional) health snapshot sits below it.
                    if !activeProtocols.isEmpty {
                        heroActive.entrance(1)
                        stackCard.entrance(2)
                        bentoGrid.entrance(3)
                    } else if !recent.isEmpty {
                        heroActivity.entrance(1)
                        bentoGrid.entrance(3)
                    } else {
                        emptyState
                    }
                    // Extra breathing room where "your dosing" ends and reference sections begin
                    // (the root VStack already contributes Space.xl of the Space.xxxl gap).
                    HomeHealthCard()
                        .padding(.top, Space.xxxl - Space.xl)
                        .entrance(4)
                    if !recent.isEmpty { recentSection.entrance(5) }
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
                MenuAvatarButton(showMenu: $showMenu)

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

            VStack(alignment: .leading, spacing: Space.xs) {
                // Date eyebrow — the instrument micro-register above the display greeting.
                MicroLabel(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                Text(greeting ?? "Track your protocol.\nKnow the science.")
                    .font(Typo.screenTitle)
                    .foregroundStyle(BrandColor.textPrimary)
                    .minimumScaleFactor(0.7).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Time-aware greeting by first name; nil (falls back to the tagline) when no name is set.
    private var greeting: String? {
        guard let name = auth.displayName?.split(separator: " ").first, !name.isEmpty else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 5 ? "Up late" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(salutation),\n\(name)."
    }

    // MARK: Hero

    private var heroActive: some View {
        Card(style: .hero, padding: Space.xl) {
            HStack(spacing: Space.lg) {
                AdherenceRing(fraction: adherenceFraction, size: 112)
                VStack(alignment: .leading, spacing: Space.lg) {
                    heroStat("Next pin", nextDoseText)
                    streakStat
                }
                Spacer(minLength: 0)
            }
        }
        // A crossed milestone celebrates once (per run): a solid flame chip springs in, a
        // success haptic fires, and it clears itself after a few seconds. Reduce Motion keeps
        // the chip but drops the spring.
        .overlay(alignment: .topTrailing) {
            if let m = celebratingMilestone {
                milestoneBadge(m)
                    .padding(Space.md)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onAppear { checkMilestone() }
        .onChange(of: streak.current) { checkMilestone() }
        .sensoryFeedback(.success, trigger: celebratingMilestone) { _, new in new != nil }
        .task(id: celebratingMilestone) {
            guard celebratingMilestone != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation { celebratingMilestone = nil }
        }
    }

    /// The reward stat: current on-time streak with a lit flame, and the best run beneath.
    private var streakStat: some View {
        VStack(alignment: .leading, spacing: 2) {
            MicroLabel("On-time streak")
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(streak.current > 0 ? BrandColor.warning : BrandColor.textSecondary)
                    .accessibilityHidden(true)
                Text("\(streak.current)").font(Typo.statValue).foregroundStyle(BrandColor.textPrimary)
                Text(streak.current == 1 ? "dose" : "doses")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            if streak.longest > 0 {
                Text("Best \(streak.longest)").font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On-time streak: \(streak.current) \(streak.current == 1 ? "dose" : "doses") in a row. Best \(streak.longest).")
    }

    private func milestoneBadge(_ m: Int) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "flame.fill")
            Text("\(m)-dose streak!")
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, Space.sm).padding(.vertical, Space.xs)
        .background(BrandColor.warning, in: Capsule())
        .foregroundStyle(BrandColor.onBadge)
        .accessibilityLabel("Milestone reached: \(m) doses on track.")
    }

    /// Fire a milestone celebration when the streak first crosses one. Silently adopt the
    /// user's current standing on first run so the update doesn't celebrate a pre-existing
    /// streak; re-arm (no celebration) if the streak later drops below a milestone.
    private func checkMilestone() {
        let earned = StreakCalculator.earnedMilestone(for: streak.current)
        if !didSeedStreakMilestone {
            celebratedMilestone = earned
            didSeedStreakMilestone = true
            return
        }
        if earned > celebratedMilestone {
            celebratedMilestone = earned
            withAnimation(reduceMotion ? nil : Motion.emphasis) { celebratingMilestone = earned }
        } else if earned < celebratedMilestone {
            celebratedMilestone = earned
        }
    }

    private var heroActivity: some View {
        Card(style: .hero, padding: Space.xl) {
            HStack(alignment: .center, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(thisWeekCount)").font(Typo.numberHero).foregroundStyle(BrandColor.textPrimary)
                    MicroLabel("Doses logged this week")
                }
                Spacer(minLength: 0)
                Image(systemName: "syringe.fill").font(.system(size: 40)).foregroundStyle(BrandColor.accentText)
            }
        }
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MicroLabel(label)
            Text(value).font(Typo.statValue).foregroundStyle(BrandColor.textPrimary)
        }
    }

    // MARK: Your stack (personalization)

    private var stackCard: some View {
        Button {
            // This card lists protocols — land on the My Protocols panel, not the vials default.
            UserDefaults.standard.set("protocols", forKey: "stackRequestedPanel")
            selected = .protocols
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        SectionHeader(title: "Your protocols")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                    }
                    ForEach(Array(activeProtocols.prefix(4).enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider().frame(height: 1).overlay(BrandColor.stroke.opacity(0.5)) }
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            StatusDot(color: statusTint(p), glows: p.displayStatus == .dueToday)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.body.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                                (Text("\(p.cadenceText) · ") + nextPinShort(p))
                                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                            }
                            Spacer()
                            Text(p.effectiveDose.displayString).font(Typo.statValue).foregroundStyle(BrandColor.accentText)
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

    /// Status color for a protocol row — the dot's hue IS the information (success = active,
    /// warning = due today, textSecondary = paused; per the design-system status language).
    private func statusTint(_ p: SavedProtocol) -> Color {
        switch p.displayStatus {
        case .active: return BrandColor.success
        case .dueToday: return BrandColor.warning
        case .paused: return BrandColor.textSecondary
        }
    }

    /// Compact next-pin fragment for stack rows: "Today" carries the warning tint (the one
    /// urgency signal on the card), then "Tomorrow", then an abbreviated date; "—" as-needed.
    private func nextPinShort(_ p: SavedProtocol) -> Text {
        guard let next = p.nextDose() else { return Text("—") }
        if Calendar.current.isDateInToday(next) {
            return Text("Today").foregroundStyle(BrandColor.warning)
        }
        if Calendar.current.isDateInTomorrow(next) { return Text("Tomorrow") }
        return Text(next, format: .dateTime.weekday(.abbreviated).month().day())
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
                MicroLabel(label)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        }
    }

    // MARK: Recent / empty

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Recent")
            ForEach(Array(recent.prefix(4)), id: \.id) { entry in
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
                // Rows soften as they leave the viewport; scale is dropped under Reduce Motion.
                .scrollTransition(axis: .vertical) { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.8)
                        .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.98))
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
