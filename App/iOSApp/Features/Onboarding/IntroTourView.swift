import SwiftUI

/// First-run experience, shown once after sign-in + disclaimer acceptance: two quick
/// personalization questions (commitment bias → a workspace tailored to what the user tracks),
/// then a short 3-slide workflow carousel (add a vial → build a protocol → log), then it drops
/// the user on Home. Replayable from the side menu ("Show me around"). Progressive profiling:
/// we ask little up front and can gather more over time.

/// A tappable onboarding choice (shared UI for both question pages).
protocol OnboardOption: Identifiable {
    var rawValue: String { get }
    var icon: String { get }
    var title: String { get }
}

enum OnboardFocus: String, CaseIterable, OnboardOption {
    case glp1, blends, gh, everything
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glp1: return "GLP-1 / weight"
        case .blends: return "Peptide blends"
        case .gh: return "GH secretagogues"
        case .everything: return "A bit of everything"
        }
    }
    var icon: String {
        switch self {
        case .glp1: return "scalemass.fill"
        case .blends: return "bandage.fill"
        case .gh: return "bolt.heart.fill"
        case .everything: return "square.grid.2x2.fill"
        }
    }
    /// Seeds the vial/log default compound so the workspace feels tailored immediately.
    var defaultCompoundName: String? {
        switch self {
        case .glp1: return "Semaglutide"
        case .blends: return "BPC-157"
        case .gh: return "CJC-1295 (no DAC)"
        case .everything: return nil
        }
    }
}

enum OnboardGoal: String, CaseIterable, OnboardOption {
    case weight, recovery, performance, longevity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: return "Weight & metabolic"
        case .recovery: return "Recovery & healing"
        case .performance: return "Performance"
        case .longevity: return "Longevity & wellness"
        }
    }
    var icon: String {
        switch self {
        case .weight: return "figure.walk"
        case .recovery: return "heart.fill"
        case .performance: return "bolt.fill"
        case .longevity: return "leaf.fill"
        }
    }
}

struct IntroTourView: View {
    @AppStorage("completedIntroTour") private var completedIntroTour = false
    @AppStorage("onboardFocus") private var focusRaw = ""
    @AppStorage("onboardGoal") private var goalRaw = ""
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
                    focusPage.tag(0)
                    goalPage.tag(1)
                    screenSlide("OnboardVial", step: 1, title: "Add your vials",
                                text: "Log what you have — one compound or a blend. Nickname it so it's easy to grab.").tag(2)
                    screenSlide("OnboardProtocol", step: 2, title: "Build a protocol",
                                text: "Pick a vial, set your dose and how often. Titration ramps are built in.").tag(3)
                    screenSlide("OnboardLog", step: 3, title: "Log every dose",
                                text: "One tap from a protocol, or a quick one-time log.").tag(4)
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

    private func finish() { withAnimation { completedIntroTour = true } }

    // MARK: Personalization questions

    private var focusPage: some View {
        questionScaffold(title: "What are you tracking?",
                         subtitle: "We'll tailor your setup — change it anytime.") {
            optionGrid(OnboardFocus.allCases, selected: focusRaw) { opt in
                focusRaw = opt.rawValue
                withAnimation { page = 1 }
            }
        }
    }

    private var goalPage: some View {
        questionScaffold(title: "Your main goal?",
                         subtitle: "Just so the app speaks your language.") {
            optionGrid(OnboardGoal.allCases, selected: goalRaw) { opt in
                goalRaw = opt.rawValue
                withAnimation { page = 2 }
            }
        }
    }

    private func questionScaffold<Content: View>(title: String, subtitle: String,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(.system(size: 30, weight: .black)).foregroundStyle(BrandColor.textPrimary)
                Text(subtitle).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func optionGrid<T: OnboardOption>(_ options: [T], selected: String,
                                              pick: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)],
                  spacing: Space.md) {
            ForEach(options) { opt in
                let isSel = opt.rawValue == selected
                Button { pick(opt) } label: {
                    VStack(spacing: Space.sm) {
                        Image(systemName: opt.icon).font(.title)
                            .foregroundStyle(isSel ? BrandColor.onAccent : BrandColor.accentText)
                        Text(opt.title).font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isSel ? BrandColor.onAccent : BrandColor.textPrimary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 108)
                    .background(isSel ? BrandColor.accent : BrandColor.surfaceElevated,
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(BrandColor.stroke, lineWidth: isSel ? 0 : 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Workflow carousel (real screen previews)

    private func screenSlide(_ image: String, step: Int, title: String, text: String) -> some View {
        VStack(spacing: Space.lg) {
            Spacer(minLength: 0)
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            VStack(spacing: Space.sm) {
                Text("Step \(step)").font(.caption.weight(.bold)).tracking(1).foregroundStyle(BrandColor.accentText)
                Text(title).font(.system(size: 26, weight: .black)).foregroundStyle(BrandColor.textPrimary)
                Text(text).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 330)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
