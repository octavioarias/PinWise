import SwiftUI
import AuthenticationServices

/// First-launch sign-in gate. Sign in with Apple works on-device; Google & Email are present
/// and route through `AuthManager` (pending backend). "Continue without an account" keeps the
/// app usable locally. On-brand: dark, hero mesh, the PW mark up top.
struct WelcomeView: View {
    @State private var auth = AuthManager.shared

    private let brandBlue = Color(red: 0.227, green: 0.357, blue: 0.937)
    private let brandMint = Color(red: 0.094, green: 0.890, blue: 0.604)

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()
            HeroMesh()
                .frame(height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.lg) {
                Spacer()
                markTile
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Welcome to PinWise")
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(BrandColor.textPrimary)
                    Text("Sign in to save your protocols, doses, and progress — and sync them across your devices.")
                        .font(Typo.body)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()

                VStack(spacing: Space.md) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { auth.completeAppleSignIn($0) }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                    providerButton("Continue with Google", systemImage: "globe") { auth.signInWithGoogle() }
                    providerButton("Continue with email", systemImage: "envelope.fill") { auth.startEmailSignIn() }

                    Button { auth.continueAsGuest() } label: {
                        Text("Continue without an account")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.sm)
                    }
                    .buttonStyle(.plain)
                }

                Text("By continuing you agree to PinWise's terms and acknowledge it is not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .tint(BrandColor.accent)
        .alert("Almost there", isPresented: Binding(get: { auth.notice != nil }, set: { if !$0 { auth.notice = nil } })) {
            Button("OK", role: .cancel) { auth.notice = nil }
        } message: { Text(auth.notice ?? "") }
    }

    private var markTile: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [brandBlue, brandMint], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 84, height: 84)
            .overlay(
                Text("PW")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            )
            .shadow(color: brandBlue.opacity(0.4), radius: 18, y: 10)
    }

    private func providerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(BrandColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(BrandColor.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
