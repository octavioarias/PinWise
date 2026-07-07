import SwiftUI
import PeptideKit

/// One-time onboarding + disclaimer acceptance. Three focused pages ending in a gated
/// agreement (18+ confirmation required). Sets the accepted disclaimer version so it shows
/// only once. On-brand: dark, hero mesh, edge glow, a success haptic on accept.
struct OnboardingView: View {
    @Binding var acceptedVersion: Int
    @AppStorage("bodyGender") private var bodyGenderRaw = "male"
    @State private var page = 0
    @State private var is18 = false
    @State private var acceptTrigger = 0
    @State private var showTerms = false

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()
            HeroMesh()
                .frame(height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            TabView(selection: $page) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                agreementPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .tint(BrandColor.accent)
        .sensoryFeedback(.success, trigger: acceptTrigger)
    }

    private var welcomePage: some View {
        pageScaffold {
            Spacer()
            Text("PinWise")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(BrandColor.textPrimary)
            Text("The source of truth for peptides and dose tracking.")
                .font(Typo.title)
                .foregroundStyle(BrandColor.textPrimary)
            Text("Track your protocol, get the math right, and stay current on what the science actually says.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
            Spacer()
            PrimaryButton(title: "Continue", systemImage: "arrow.right") { withAnimation { page = 1 } }
        }
    }

    private var featuresPage: some View {
        pageScaffold {
            Spacer()
            Text("Everything in one place")
                .font(Typo.title).textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
            VStack(alignment: .leading, spacing: Space.lg) {
                featureRow("syringe.fill", "Track doses & protocols", "Log in a couple taps; see how on-track you are and what's next.")
                featureRow("function", "Accurate dosing math", "Reconstitution, blends, and units — done right.")
                featureRow("newspaper.fill", "Neutral, cited News", "Trials, results, and regulatory updates in plain language.")
            }
            Spacer()
            PrimaryButton(title: "Continue", systemImage: "arrow.right") { withAnimation { page = 2 } }
        }
    }

    private var agreementPage: some View {
        pageScaffold {
            Text("Before you start")
                .font(Typo.title).textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
            Text("PinWise is a personal record-keeping tool — it isn't a medical device and doesn't give medical advice. Your records stay on your device.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { showTerms = true } label: {
                Text("Read the Terms of Service & Privacy Policy")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandColor.accentText)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showTerms) { LegalDocumentView() }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Body for your injection map").font(.footnote.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                Picker("", selection: $bodyGenderRaw) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
                .pickerStyle(.segmented)
                Text("Used to draw your body map — change it anytime in My Profile.")
                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            Toggle("I'm 18 or older and I agree to the Terms of Service and Privacy Policy.", isOn: $is18)
                .tint(BrandColor.accent)
                .font(.footnote)
                .foregroundStyle(BrandColor.textPrimary)
            PrimaryButton(title: "Agree & continue", systemImage: "checkmark") {
                acceptTrigger += 1
                withAnimation(.easeInOut(duration: 0.55)) { acceptedVersion = Disclaimer.currentVersion }
            }
            .disabled(!is18)
            .opacity(is18 ? 1 : 0.5)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BrandColor.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
        }
    }

    private func pageScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            content()
        }
        .padding(Space.xl)
        .padding(.bottom, Space.xxl) // clear the page-dots
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
