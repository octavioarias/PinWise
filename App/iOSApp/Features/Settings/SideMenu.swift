import SwiftUI

/// A left-anchored slide-in navigation drawer (Oura-style): tap the ☰ on Home and the panel
/// pans in from the left to ~85% width over a dimmed page. Hosts the account/config
/// destinations that don't belong in the tab bar. Rendered at the root, above the tab bar.
struct SideMenuDrawer: View {
    @Binding var isOpen: Bool
    @State private var route: MenuRoute?
    @State private var auth = AuthManager.shared
    @AppStorage("completedIntroTour") private var completedIntroTour = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.85
            let topInset = geo.safeAreaInsets.top
            // Nothing renders while closed — the drawer is fully absent until opened, then it
            // slides in from the left and stops at 85% width, leaving the dimmed page beyond it.
            ZStack(alignment: .leading) {
                if isOpen {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen = false }
                        .transition(.opacity)

                    panel(topInset: topInset)
                        .frame(width: width, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(BrandColor.surface)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(BrandColor.stroke).frame(width: 0.5)
                        }
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.45), radius: 24, x: 8)
                        .transition(.move(edge: .leading))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isOpen)
        }
        .allowsHitTesting(isOpen)
        .sheet(item: $route) { $0.view }
    }

    private func panel(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PinWise")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Button { isOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }
            .padding(.top, topInset + Space.md)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.sm)

            HStack(spacing: Space.sm) {
                Image(systemName: auth.isGuest ? "person.crop.circle.dashed" : "person.crop.circle.fill")
                    .foregroundStyle(BrandColor.accentText)
                Text(auth.accountLabel)
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row("person", "My Profile", .profile)
                    row("slider.horizontal.3", "Settings", .settings)
                    row("heart.text.square", "Connections", .health)
                    Divider().overlay(BrandColor.stroke).padding(.vertical, Space.sm)
                    row("info.circle", "About & Legal", .about)
                    actionRow("sparkles", "Show me around") { completedIntroTour = false; isOpen = false }
                    Divider().overlay(BrandColor.stroke).padding(.vertical, Space.sm)
                    actionRow(auth.isGuest ? "arrow.right.square" : "rectangle.portrait.and.arrow.right",
                              auth.isGuest ? "Sign in" : "Sign out") {
                        isOpen = false
                        auth.signOut()
                    }
                }
                .padding(.horizontal, Space.lg)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionRow(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.lg) {
                Image(systemName: icon).font(.title3).frame(width: 26).foregroundStyle(BrandColor.textSecondary)
                Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Spacer()
            }
            .padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func row(_ icon: String, _ title: String, _ dest: MenuRoute) -> some View {
        Button {
            isOpen = false
            route = dest
        } label: {
            HStack(spacing: Space.lg) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 26)
                    .foregroundStyle(BrandColor.accentText)
                Text(title)
                    .font(Typo.headline)
                    .foregroundStyle(BrandColor.textPrimary)
                Spacer()
            }
            .padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Destinations reachable from the side menu. Presented as sheets from the drawer.
enum MenuRoute: String, Identifiable {
    case profile, settings, health, about
    var id: String { rawValue }

    @ViewBuilder var view: some View {
        switch self {
        case .profile: ProfileView()
        case .settings: SettingsView()
        case .health: HealthConnectionsView()
        case .about: AboutView()
        }
    }
}

/// Small helper for a modal screen presented from the menu.
private struct MenuSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) { content() }
                    .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ProfileView: View {
    @AppStorage("profileName") private var name = ""
    @AppStorage("bodyGender") private var bodyGenderRaw = "male"

    var body: some View {
        MenuSheet(title: "My Profile") {
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: "Profile")
                    FieldRow("Your name", hint: "Optional — used to personalize the app.") {
                        TextField("Name", text: $name).pinwiseField()
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: "Injection map body")
                    Picker("", selection: $bodyGenderRaw) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    .pickerStyle(.segmented)
                    Text("Which body the injection map draws.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }
}

struct HealthConnectionsView: View {
    @State private var health = HealthManager.shared

    var body: some View {
        MenuSheet(title: "Connections") {
            Text("PinWise syncs through Apple Health. Connect once and the metrics that matter — weight, resting heart rate, HRV, sleep, and activity — flow in, including whatever your Oura Ring, Whoop, Apple Fitness, or Garmin write to Apple Health. No separate logins.")
                .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
            HealthWidget()
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: "Sources")
                    sourceRow("Apple Health", "heart.fill", health.authorized ? "Connected — the hub for everything below." : "The hub — connect above to sync.", on: health.authorized)
                    sourceRow("Apple Fitness", "figure.run", "Workouts, move & exercise minutes — via Apple Health.")
                    sourceRow("Oura Ring", "circle.circle", "Sleep, HRV, readiness — turn on Apple Health sharing in the Oura app.")
                    sourceRow("Whoop", "bolt.heart.fill", "Recovery, strain, sleep — turn on Apple Health sharing in the Whoop app.")
                    sourceRow("Garmin", "figure.outdoor.cycle", "Activity & sleep — enable Apple Health in Garmin Connect.")
                }
            }
            if health.authorized {
                Button(role: .destructive) { health.disconnect() } label: {
                    Label("Disconnect Apple Health", systemImage: "xmark.circle")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, Space.sm)
                }
                .foregroundStyle(BrandColor.danger)
            }
        }
    }

    private func sourceRow(_ name: String, _ icon: String, _ note: String, on: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon).font(.title3).frame(width: 26).foregroundStyle(BrandColor.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Text(note).font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            Spacer(minLength: 0)
            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(BrandColor.success) }
        }
    }
}

struct AboutView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        MenuSheet(title: "About") {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("PinWise").font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                    Text("The source of truth for peptides and dose tracking — transparent about where the evidence stands.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    HStack {
                        Text("Version").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                        Spacer()
                        Text(appVersion).font(.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                    .padding(.top, Space.sm)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Important")
                    Text("PinWise is for tracking and education. It doesn't provide medical advice, diagnosis, or treatment. Talk to a licensed clinician about your health decisions.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }
}
