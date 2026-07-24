import SwiftUI

/// A left-anchored slide-in navigation drawer (Oura-style): tap the ☰ on Home and the panel
/// pans in from the left to ~85% width over a dimmed page. Hosts the account/config
/// destinations that don't belong in the tab bar. Rendered at the root, above the tab bar.
struct SideMenuDrawer: View {
    @Binding var isOpen: Bool
    @State private var route: MenuRoute?
    @State private var auth = AuthManager.shared
    @State private var photos = ProfilePhotoStore.shared
    @State private var showSignOut = false
    @Environment(\.colorScheme) private var scheme

    private var headerName: String { auth.displayName ?? "" }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.85
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            // Nothing renders while closed — the drawer is fully absent until opened, then it
            // slides in from the left and stops at 85% width, leaving the dimmed page beyond it.
            ZStack(alignment: .leading) {
                if isOpen {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen = false }
                        .transition(.opacity)

                    panel(topInset: topInset, bottomInset: bottomInset)
                        .frame(width: width, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        // Tinted glass over the dimmed app content — the 0.55 scrim also dims what
                        // the blur samples. Scheme-split tint: 0.7 on dark is bounded (scrim +
                        // dark material cap the backdrop), but LIGHT mode needs 0.92 — there the
                        // black scrim works AGAINST a bright panel and no ultraThin tint below
                        // ~0.9 holds textSecondary at 4.5:1 over dark content behind the drawer.
                        .background(BrandColor.background.opacity(scheme == .dark ? 0.7 : 0.92))
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(BrandColor.stroke).frame(width: 0.5)
                        }
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.45), radius: 24, x: 8)
                        .transition(.move(edge: .leading))
                }
            }
            .animation(Motion.drawer, value: isOpen)
        }
        .allowsHitTesting(isOpen)
        .sheet(item: $route) { $0.view }
    }

    private func panel(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PinWise")
                    .font(.system(size: 26, weight: .bold))
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

            // Identity header — avatar + name, tappable straight into Your profile (Oura-style).
            Button {
                isOpen = false
                route = .profile
            } label: {
                HStack(spacing: Space.md) {
                    ProfileAvatar(name: headerName, size: 44, photo: photos.image)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headerName.isEmpty ? "Set up your profile" : headerName)
                            .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                            .lineLimit(1)
                        Text(auth.accountSubtitle)
                            .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Keep the account identity audible — VoiceOver users check guest vs signed-in here.
            .accessibilityLabel("Your profile — \(headerName.isEmpty ? "not set up" : headerName), \(auth.accountSubtitle)")
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Connections, About & Legal, and Software info now live inside Settings.
                    row("slider.horizontal.3", "Settings", .settings)
                    Divider().overlay(BrandColor.stroke).padding(.vertical, Space.sm)
                    actionRow(auth.isGuest ? "arrow.right.square" : "rectangle.portrait.and.arrow.right",
                              auth.isGuest ? "Sign in" : "Sign out") {
                        // Guest upgrading to an account keeps their name/photo; real sign-out asks first.
                        if auth.isGuest { auth.beginAccountUpgrade(); isOpen = false } else { showSignOut = true }
                    }
                }
                .padding(.horizontal, Space.lg)
            }
            Spacer(minLength: Space.md)
            socialFooter(bottomInset: bottomInset)
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                auth.signOut()
                ProfilePhotoStore.shared.clear()   // don't leave the previous user's face behind
                // Reset personal details so the next account personalizes fresh instead of
                // inheriting this user's profile.
                let d = UserDefaults.standard
                d.removeObject(forKey: "profileBirthday")
                d.removeObject(forKey: "profileHeightCm")
                d.set("male", forKey: "bodyGender")
                isOpen = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your protocols, doses, and vials stay on this device. Your profile — name, photo, and personal details — is removed.")
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

    /// Pinned to the bottom of the drawer: follow / community outlets. Brand logo to the LEFT of
    /// each handle. Pure outbound `Link`s (no in-app browser, no tracking) — consistent with the
    /// local-first, no-analytics posture; these inform/point out, they don't advise.
    private func socialFooter(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Divider().overlay(BrandColor.stroke)
            Text("Follow along")
                .font(Typo.caption).fontWeight(.semibold).tracking(1.2)
                .foregroundStyle(BrandColor.textSecondary)
            socialLink("SocialX", "@PinWiseApp", "https://x.com/PinWiseApp")
            socialLink("SocialInstagram", "@PinWiseApp", "https://instagram.com/PinWiseApp")
            socialLink("SocialTikTok", "@PinWiseApp", "https://tiktok.com/@PinWiseApp")
            socialLink("SocialReddit", "u/TavioTheScientist", "https://reddit.com/user/TavioTheScientist")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.sm)
        // Panel ignores the safe area, so pad the bottom inset manually (mirrors the top).
        .padding(.bottom, bottomInset + Space.md)
    }

    @ViewBuilder
    private func socialLink(_ asset: String, _ handle: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: Space.md) {
                    Image(asset)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(handle).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .padding(.vertical, Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(handle) on \(asset.replacingOccurrences(of: "Social", with: ""))")
        }
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

/// Small helper for a modal screen presented from the menu (also used by ProfileView).
struct MenuSheet<Content: View>: View {
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

struct HealthConnectionsView: View {
    @State private var health = HealthManager.shared
    // Mirror of HomeView's gate — the source of truth is the "hideHomeHealthCard" default.
    @AppStorage("hideHomeHealthCard") private var hideHomeHealthCard = false

    var body: some View {
        MenuSheet(title: "Connections") {
            Text("PinWise reads your data from Apple Health — it never connects to your ring or watch directly. Your Oura, Whoop, Apple Watch, or Garmin writes into Apple Health, and PinWise reads it back out. Both sides need Apple Health sharing turned on, or nothing flows. You'll see standard metrics — weight, resting heart rate, HRV, sleep, steps — not app-specific scores like Oura Readiness. No separate logins.")
                .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
            HealthWidget()
            Card {
                Toggle(isOn: Binding(get: { !hideHomeHealthCard }, set: { hideHomeHealthCard = !$0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show on Home").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Text("Keep the health card at the top of your Home tab.")
                            .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                    }
                }
                .tint(BrandColor.accent)
            }
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: "Sources")
                    sourceRow("Apple Health", "heart.fill", health.authorized ? "Connected — the hub for everything below." : "The hub — connect above to sync.", on: health.authorized)
                    sourceRow("Apple Fitness", "figure.run", "Steps & activity — via Apple Health.")
                    sourceRow("Oura Ring", "circle.circle", "Sleep & HRV — turn on Apple Health sharing in the Oura app.")
                    sourceRow("Whoop", "bolt.heart.fill", "Sleep & HRV — turn on Apple Health sharing in the Whoop app.")
                    sourceRow("Garmin", "figure.outdoor.cycle", "Steps & sleep — enable Apple Health in Garmin Connect.")
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
    @State private var showTerms = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        MenuSheet(title: "About & Legal") {
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
            Button { showTerms = true } label: {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(BrandColor.accentText)
                    Text("Terms of Service & Privacy Policy").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                .padding(Space.lg)
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showTerms) { LegalDocumentView() }
        }
    }
}
