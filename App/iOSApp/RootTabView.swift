import SwiftUI
import SwiftData

/// The five app sections. Order is deliberate: Log sits in the center to make logging a
/// dose the most reachable action.
enum AppTab: Hashable {
    case home, tools, log, protocols, news
}

/// Root shell with a compact custom bottom bar. All tabs are the same size and baseline;
/// the center Log tab is emphasized only through color + fill + a soft glow (never size or
/// vertical offset), so the bar stays standard-height and aligned.
struct RootTabView: View {
    @State private var selected: AppTab = .home
    @State private var showMenu = false
    @State private var showAssistant = false
    @Query(sort: \SavedProtocol.startDate) private var protocols: [SavedProtocol]

    /// Changes whenever a reminder-relevant field changes, re-triggering scheduling.
    private var reminderSignature: String {
        protocols.map { "\($0.id.uuidString)|\($0.remindersOn)|\($0.isActive)|\($0.reminderHour):\($0.reminderMinute)|\($0.scheduleKindRaw)|\($0.intervalDays)|\($0.weekdays)" }.joined()
    }

    var body: some View {
        Group {
            switch selected {
            case .home: HomeView(selected: $selected, showMenu: $showMenu, showAssistant: $showAssistant)
            case .tools: ToolsView()
            case .log: LogView()
            case .protocols: ProtocolsView()
            case .news: NewsView()
            }
        }
        .overlay(alignment: .bottom) {
            PinWiseTabBar(selected: $selected)
        }
        // Drawers sit above the tab bar so they cover the full screen when open.
        .overlay {
            SideMenuDrawer(isOpen: $showMenu)
        }
        .overlay {
            AssistantDrawer(isOpen: $showAssistant)
        }
        .tint(BrandColor.accent)
        .grain()    // subtle film-grain texture across the app
        .edgeGlow() // ambient accent glow around the screen edges (scheme-aware)
        .task(id: reminderSignature) {
            await NotificationManager.reschedule(protocols: protocols)
        }
    }
}

/// Compact bottom bar — a solid, elevated dark surface flush to the screen's bottom edge.
/// Five equal, center-aligned tabs; Log is a filled accent chip with a white glyph so it
/// stays high-contrast on any background without changing size or leaving the row.
private struct PinWiseTabBar: View {
    @Binding var selected: AppTab

    // A fixed icon-row height keeps every tab (including the Log chip) on one baseline.
    private let iconRow: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tab(.home, icon: "house.fill", label: "Home")
            tab(.tools, icon: "function", label: "Tools")
            tab(.log, icon: "plus", label: "Log", prominent: true)
            tab(.protocols, icon: "square.stack.3d.up.fill", label: "Stack")
            tab(.news, icon: "newspaper.fill", label: "News")
        }
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity)
        // Sheen + hairline drawn within the bar's frame...
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [BrandColor.accent.opacity(0.12), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(BrandColor.stroke).frame(height: 0.5)
            }
        }
        // ...and the solid fill extends into the home-indicator area WITHOUT changing the bar's
        // layout height, so safeAreaInset reserves the correct space and scroll content stops
        // exactly at the bar's top edge (never underneath it).
        .background(BrandColor.surface, ignoresSafeAreaEdges: .bottom)
        .shadow(color: .black.opacity(0.25), radius: 6, y: -1)
    }

    @ViewBuilder
    private func tab(_ item: AppTab, icon: String, label: String, prominent: Bool = false) -> some View {
        let isSelected = selected == item
        Button {
            selected = item
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if prominent {
                        Circle()
                            .fill(LinearGradient(colors: [BrandColor.accent, BrandColor.accent.opacity(0.85)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: 30)
                            .shadow(color: BrandColor.accent.opacity(0.55), radius: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? BrandColor.accentText : BrandColor.textSecondary)
                    }
                }
                .frame(height: iconRow)
                Text(label)
                    .font(.system(size: 10, weight: prominent ? .bold : .medium))
                    .foregroundStyle(prominent || isSelected ? BrandColor.accentText : BrandColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item == .log ? "Log a dose" : label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Themed placeholder for sections not yet built out.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.md) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                Text(subtitle)
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .heroScreen()
            .navigationTitle(title)
        }
    }
}
