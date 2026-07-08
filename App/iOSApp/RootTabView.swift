import SwiftUI
import SwiftData

/// The five app sections. Order is deliberate: Log sits in the center to make logging a
/// dose the most reachable action.
enum AppTab: Hashable {
    case home, tools, log, protocols, news
}

/// Root shell with a compact custom bottom bar. Four tabs share one quiet monochrome
/// register; the center Log tab is the deliberate exception (a Strava-style record
/// button): larger, crested above the hairline, and the only color in the chrome.
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
            case .log: LogView(selected: $selected)
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
        .task(id: reminderSignature) {
            await NotificationManager.reschedule(protocols: protocols)
        }
    }
}

/// Compact bottom bar — brand-tinted ultra-thin glass flush to the screen's bottom edge.
/// Five equal-width, center-aligned tabs; Log is a flat accent disc with a white glyph
/// that crests above the hairline — visual emphasis only, the bar's metrics are unchanged.
private struct PinWiseTabBar: View {
    @Binding var selected: AppTab

    // A fixed icon-row height keeps every tab (including the Log chip) on one baseline.
    private let iconRow: CGFloat = 30

    // Haptic trigger for ACTUAL taps only. `selected` also changes programmatically
    // (post-save auto-return Home, stackCard deep link) and those must not buzz.
    @State private var tapCount = 0

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
        // Hairline drawn within the bar's frame...
        .background(alignment: .top) {
            Rectangle().fill(BrandColor.stroke).frame(height: 0.5)
        }
        // ...and the glass fill extends into the home-indicator area WITHOUT changing the bar's
        // layout height. The bar is hosted as a bottom overlay and scroll content reserves its
        // space via tabBarClearance(90), so content stops exactly at the bar's top edge (never
        // underneath it). Tint is declared BEFORE the material: later .background modifiers
        // stack BEHIND earlier ones, so the brand tint renders in front of the blur while
        // content still shimmers through underneath.
        .background(BrandColor.background.opacity(0.55), ignoresSafeAreaEdges: .bottom)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        .sensoryFeedback(.selection, trigger: tapCount)
    }

    @ViewBuilder
    private func tab(_ item: AppTab, icon: String, label: String, prominent: Bool = false) -> some View {
        let isSelected = selected == item
        Button {
            selected = item
            tapCount += 1
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if prominent {
                        Circle()
                            .fill(BrandColor.accent)
                            .frame(width: 44, height: 44)
                            .shadow(color: BrandColor.accent.opacity(0.4), radius: 12, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? BrandColor.textPrimary : BrandColor.textSecondary)
                    }
                }
                .frame(height: iconRow)
                // Offset AFTER the frame: the disc keeps its 30pt layout slot (bar metrics
                // and the 90pt tabBarClearance contract untouched) but visually crests
                // above the hairline together with its glyph.
                .offset(y: prominent ? -7 : 0)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? BrandColor.textPrimary : BrandColor.textSecondary)
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
