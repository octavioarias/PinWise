import SwiftUI

/// First-run experience, shown once after sign-in + disclaimer acceptance: a short 3-slide
/// walkthrough of the real workflow — add a vial → build a protocol → log — using on-brand
/// previews of the actual screens, then it drops the user on Home. Skippable, and replayable
/// from the side menu ("Show me around"). No upfront questions (kept friction-free).
struct IntroTourView: View {
    @AppStorage("completedIntroTour") private var completedIntroTour = false
    @State private var page = 0
    private let lastPage = 2

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
                                text: "Under Stack ▸ My Inventory — log a compound or a blend (like Wolverine) and nickname it.").tag(0)
                    screenSlide("OnboardProtocol", step: 2, title: "Build a protocol",
                                text: "Under Stack ▸ My Protocols — build from a vial; it links back to it and pulls your dose.").tag(1)
                    screenSlide("OnboardLog", step: 3, title: "Log every dose",
                                text: "From the Log tab — one tap from a protocol, or a quick one-time log.").tag(2)
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
}
