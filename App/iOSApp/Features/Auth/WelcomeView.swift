import SwiftUI
import AuthenticationServices
import PeptideKit

/// First-launch sign-in gate. Cinematic hero: two stainless-steel vials (Retatrutide + GLOW)
/// over a teal→blue glow on pitch black, then the PinWise mark, tagline, and auth. Sign in with
/// Apple works on-device; "Continue as guest" keeps the app usable locally; "Log in" routes to
/// the (backend-pending) email path. Terms/Privacy reachable before authenticating.
struct WelcomeView: View {
    @State private var auth = AuthManager.shared
    @State private var showLegal = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Teal → blue glow, strictly behind the vials.
            RadialGradient(
                colors: [Color(hex: 0x22E0B0).opacity(0.34), Color(hex: 0x1E9CC8).opacity(0.22), .clear],
                center: .center, startRadius: 0, endRadius: 260
            )
            .frame(width: 460, height: 460)
            .blur(radius: 75)
            .offset(y: -160)
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                Image("VialsHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.top, 20)
                    .accessibilityHidden(true)

                Spacer(minLength: 4)

                VStack(spacing: Space.md) {
                    Text("PinWise")
                        .font(.system(size: 33, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Real science for peptides.\nThe source of truth for dose tracking.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BrandColor.textSecondary)
                        .padding(.bottom, Space.xs)

                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { auth.completeAppleSignIn($0) }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(Capsule())

                    Button { auth.continueAsGuest() } label: {
                        Text("Continue as guest")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 5) {
                        Text("Have an account?")
                            .foregroundStyle(BrandColor.textSecondary)
                        Button { auth.startEmailSignIn() } label: {
                            Text("Log in").fontWeight(.semibold).foregroundStyle(BrandColor.accentText)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 14))
                    .padding(.top, Space.xs)

                    Button { showLegal = true } label: {
                        Text("Terms & Privacy")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.lg)
            }
        }
        .tint(BrandColor.accent)
        .alert("Almost there", isPresented: Binding(get: { auth.notice != nil }, set: { if !$0 { auth.notice = nil } })) {
            Button("OK", role: .cancel) { auth.notice = nil }
        } message: { Text(auth.notice ?? "") }
        .sheet(isPresented: $showLegal) { LegalDocumentView() }
    }
}
