import SwiftUI
import SwiftData
import PeptideKit

/// The dashboard. A personalized greeting, one prominent hero (adherence + next dose), a bento
/// grid of secondary stats, quick actions, and recent activity — an editorial rhythm rather than
/// a uniform stack of cards. Reflects real logged data via verified PeptideKit logic.
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

    /// Aggregate adherence over the last 14 days across active protocols.
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
                    if !activeProtocols.isEmpty {
                        heroActive
                        bentoGrid
                    } else if !recent.isEmpty {
                        heroActivity
                        bentoGrid
                    } else {
                        emptyState
                    }
                    quickActions
                    if !recent.isEmpty { recentSection }
                    DisclaimerBanner(text: Disclaimer.calculator)
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

    // MARK: Bento

    private var bentoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)],
                  spacing: Space.md) {
            bentoTile("Sites in rotation", "\(sitesInRotation)", "circle.grid.3x3.fill")
            if activeProtocols.isEmpty {
                bentoTile("Doses logged", "\(recent.count)", "syringe.fill")
            } else {
                bentoTile("Active protocols", "\(activeProtocols.count)", "list.bullet.rectangle.fill")
            }
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

    // MARK: Quick actions / recent

    private var quickActions: some View {
        HStack(spacing: Space.md) {
            QuickAction(title: "Log a dose", systemImage: "plus.circle.fill") { selected = .log }
            QuickAction(title: "How much to draw", systemImage: "syringe.fill") { selected = .tools }
        }
    }

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
                    Text("Log your first dose").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text("Tap below (or the ＋ in the tab bar) to record your first dose.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    PrimaryButton(title: "Log a dose", systemImage: "plus") { selected = .log }
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
/// and distinct from the flat bento tiles below it. Adapts with the scheme via theme tokens.
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

/// A tappable quick-action tile.
private struct QuickAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Space.lg)
            .background(
                LinearGradient(colors: [BrandColor.surface, BrandColor.surfaceElevated.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}
