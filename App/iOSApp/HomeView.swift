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
    @Query private var vials: [StoredVial]
    @State private var auth = AuthManager.shared
    // The "Your health" card can be dismissed from Home and re-shown from menu → Connections.
    // Shared key: this gate and the card's own hide action read/write the same default.
    @AppStorage("hideHomeHealthCard") private var hideHealthCard = false
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

    /// Adherence is judged over the last N SCHEDULED DOSES (not a fixed run of calendar days),
    /// so a weekly and a daily protocol are measured on the same footing and one miss is a
    /// small, predictable dip (~1/N) that recovers as new on-time doses push it out of the
    /// window. A dose logged up to `graceDays` late still counts (people don't dose to the
    /// minute). Both constants are the single tuning point.
    private static let adherenceWindow = 22
    private static let graceDays = 2

    /// Every past-due scheduled dose across all active protocols, tagged taken/missed with the
    /// grace rule, sorted chronologically. The one basis both the streak and the adherence %
    /// read, so they can never disagree. (Today's not-yet-taken dose is pending, not a miss.)
    private var doseEvents: [StreakCalculator.DoseEvent] {
        let cal = Calendar.current
        let now = Date()
        var events: [StreakCalculator.DoseEvent] = []
        for p in activeProtocols {
            let logs = recent.filter { p.compoundNames.contains($0.compoundName) }.map(\.timestamp)
            let r = AdherenceCalculator.evaluate(schedule: p.schedule, start: p.startDate,
                                                 end: now, logDates: logs,
                                                 graceDays: Self.graceDays, calendar: cal)
            events += StreakCalculator.events(from: r, asOf: now, calendar: cal)
        }
        return events.sorted { $0.date < $1.date }
    }

    /// Fraction of the last `adherenceWindow` scheduled doses that were taken (0 if none due yet).
    private var adherenceFraction: Double {
        let window = doseEvents.suffix(Self.adherenceWindow)
        guard !window.isEmpty else { return 0 }
        return Double(window.filter(\.taken).count) / Double(window.count)
    }

    /// On-time dose streak: consecutive scheduled doses taken with no miss (current) + best run
    /// ever (longest), over the same grace-aware event basis as the adherence %.
    private var streak: StreakCalculator.Result { StreakCalculator.compute(events: doseEvents) }

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
                    if !hideHealthCard {
                        HomeHealthCard()
                            .padding(.top, Space.xxxl - Space.xl)
                            .entrance(4)
                    }
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
        let isLate = hour < 5
        let salutation = isLate ? "Up late" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        // "Up late" is a question ("Up late, Alex?"); the rest are statements.
        return "\(salutation),\n\(name)\(isLate ? "?" : ".")"
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
                Text("Personal Best \(streak.longest)").font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On-time streak: \(streak.current) \(streak.current == 1 ? "dose" : "doses") in a row. Personal Best \(streak.longest).")
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
                            Text(p.effectiveDose.displayString(in: p.doseUnit(vials: vials))).font(Typo.statValue).foregroundStyle(BrandColor.accentText)
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

    // MARK: Empty

    private var emptyState: some View {
        // Reflect how far the user actually is: no vials yet → add one; a vial exists but no
        // protocol → build one. (This branch only shows when there's no active protocol and no
        // logged dose, so a vial-but-no-protocol state must invite the protocol, not re-ask for
        // a vial the user already added.)
        let hasVial = !vials.isEmpty
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Get started")
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(hasVial ? "Build your first protocol" : "Add your first vial")
                        .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(hasVial
                         ? "Nice — you've got a vial in your Stack. Build a protocol from it to set your cadence, then log your doses. Home fills in with your adherence and health as you go."
                         : "Head to Stack ▸ My Vials — add a compound or blend, build a protocol from it, then log. Home fills in with your adherence and health as you go.")
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
    // Same key HomeView gates on — setting it here removes the card from Home; menu → Connections
    // flips it back on.
    @AppStorage("hideHomeHealthCard") private var hidden = false
    @State private var health = HealthManager.shared
    @State private var requesting = false
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
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                // Header: title + an options menu (dismiss). Kept OUTSIDE any NavigationLink so the
                // menu and connect button get their own taps.
                HStack {
                    SectionHeader(title: "Your health")
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            withAnimation { hidden = true }
                        } label: { Label("Hide from Home", systemImage: "eye.slash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                            .frame(width: 32, height: 32, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Health card options")
                }

                if metrics.isEmpty {
                    Text("Connect Apple Health to see your weight, resting heart rate, HRV, sleep, and steps here — including anything Oura, Whoop, or Apple Fitness write to Health.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Space.md) {
                        if health.isAvailable && !health.authorized {
                            Button {
                                Task { requesting = true; await health.requestAuthorization(); requesting = false }
                            } label: {
                                Label(requesting ? "Connecting…" : "Connect Apple Health", systemImage: "heart.text.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrandColor.onAccent)
                                    .padding(.vertical, Space.sm).padding(.horizontal, Space.md)
                                    .background(BrandColor.accent, in: Capsule())
                            }
                            .buttonStyle(.plain).disabled(requesting)
                        }
                        NavigationLink { BiomarkersView() } label: {
                            HStack(spacing: 4) {
                                Text("Log a Metric")
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.accentText)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    NavigationLink { BiomarkersView() } label: {
                        HStack(alignment: .top) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)], spacing: Space.md) {
                                ForEach(metrics) { m in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.label.uppercased()).font(Typo.caption).tracking(0.6).foregroundStyle(BrandColor.textSecondary)
                                        Text(m.value).font(Typo.numberMD).foregroundStyle(BrandColor.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .task { if health.authorized { await health.refresh() } }
    }
}
