import SwiftUI

/// First-run experience, shown once after sign-in + acceptance + profile setup: the core
/// workflow (add a vial → build a protocol → log) followed by a guide to the rest of the
/// app — the Tools kit and the News tab. Skippable, and replayable from the side menu
/// ("Show me around"). No upfront questions (kept friction-free).
struct IntroTourView: View {
    @AppStorage("completedIntroTour") private var completedIntroTour = false
    @State private var page = 0
    private let lastPage = 4

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()
            HeroMesh()
                .frame(height: 460)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                        .padding(Space.lg)
                }

                TabView(selection: $page) {
                    screenSlide("OnboardVial", step: 1, title: "Add your vials",
                                text: "Under Stack ▸ My Vials — add a compound or a blend (like Wolverine) and nickname it.").tag(0)
                    screenSlide("OnboardProtocol", step: 2, title: "Build a protocol",
                                text: "Under Stack ▸ My Protocols — build from a vial; it links back to it and pulls your dose.").tag(1)
                    screenSlide("OnboardLog", step: 3, title: "Log every dose",
                                text: "From the Log tab — one tap from a protocol, or a quick one-time pin.").tag(2)
                    featureSlide(step: 4, title: "Your toolkit", icon: "function",
                                 features: [
                                    ("syringe", "Reconstitution math", "How much water, how much to draw — done right."),
                                    ("chart.xyaxis.line", "Labs & metrics", "Weight, A1c, lipids, BP — trended over time."),
                                    ("figure.stand", "Injection map", "See site rotation on your body, front and back."),
                                    ("face.smiling", "Symptom journal", "How you feel, next to what you took.")
                                 ],
                                 text: "The Tools tab is your kit — calculators, trends, and your body map.").tag(3)
                    featureSlide(step: 5, title: "Stay current", icon: "newspaper.fill",
                                 features: [
                                    ("doc.text.magnifyingglass", "Cited summaries", "Trials and regulatory updates in plain language."),
                                    ("checkmark.seal", "Evidence tiers", "Every compound labeled by how much human data exists."),
                                    ("link", "Primary sources", "Each story links to the original paper or filing.")
                                 ],
                                 text: "The News tab keeps you current on what the science actually says.").tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                PrimaryButton(title: page >= lastPage ? "Enter PinWise" : "Continue",
                              systemImage: page >= lastPage ? "checkmark" : "arrow.right") {
                    if page >= lastPage { finish() } else { withAnimation { page += 1 } }
                }
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.xl)
            }
        }
        .tint(BrandColor.accent)
    }

    private func finish() { withAnimation(.easeInOut(duration: 0.5)) { completedIntroTour = true } }

    /// One slide: an on-brand preview of the real screen + a short caption.
    private func screenSlide(_ image: String, step: Int, title: String, text: String) -> some View {
        VStack(spacing: Space.lg) {
            Spacer(minLength: 0)
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            VStack(spacing: Space.sm) {
                Text("Step \(step)").font(.caption.weight(.bold)).tracking(1).foregroundStyle(BrandColor.accentText)
                Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(BrandColor.textPrimary)
                Text(text).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A slide with a feature list instead of a screenshot — used for the Tools/News guides.
    private func featureSlide(step: Int, title: String, icon: String,
                              features: [(String, String, String)], text: String) -> some View {
        VStack(spacing: Space.lg) {
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(BrandColor.accentText)
                .frame(width: 96, height: 96)
                .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(features, id: \.1) { f in
                    HStack(alignment: .top, spacing: Space.md) {
                        Image(systemName: f.0).font(.body).frame(width: 24).foregroundStyle(BrandColor.accentText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.1).font(.subheadline.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                            Text(f.2).font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 340)
            .background(BrandColor.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            VStack(spacing: Space.sm) {
                Text("Step \(step)").font(.caption.weight(.bold)).tracking(1).foregroundStyle(BrandColor.accentText)
                Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(BrandColor.textPrimary)
                Text(text).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
