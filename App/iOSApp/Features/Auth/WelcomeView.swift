import SwiftUI
import AuthenticationServices
import PeptideKit

/// First-launch sign-in gate. Sign in with Apple works on-device; Google & Email are marked
/// "Soon" (pending backend). "Continue without an account" keeps the app usable locally.
/// On-brand: dark, hero mesh. Terms/Privacy are reachable before authenticating.
struct WelcomeView: View {
    @State private var auth = AuthManager.shared
    @State private var showLegal = false

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
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Welcome to PinWise")
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(BrandColor.textPrimary)
                    Text("Sign in to save your protocols, doses, and progress — or continue as a guest.")
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

                    providerButton("Continue with Google", systemImage: "globe", soon: true) { auth.signInWithGoogle() }
                    providerButton("Continue with email", systemImage: "envelope.fill", soon: true) { auth.startEmailSignIn() }

                    Button { auth.continueAsGuest() } label: {
                        Text("Continue without an account")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.sm)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 3) {
                    Button { showLegal = true } label: {
                        Text("Terms & Privacy").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .tint(BrandColor.accent)
        .alert("Almost there", isPresented: Binding(get: { auth.notice != nil }, set: { if !$0 { auth.notice = nil } })) {
            Button("OK", role: .cancel) { auth.notice = nil }
        } message: { Text(auth.notice ?? "") }
        .sheet(isPresented: $showLegal) { LegalDocumentView() }
    }

    private func providerButton(_ title: String, systemImage: String, soon: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                Text(title).fontWeight(.semibold)
                if soon {
                    Text("SOON").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(BrandColor.textSecondary.opacity(0.22), in: Capsule())
                }
            }
            .foregroundStyle(soon ? BrandColor.textSecondary : BrandColor.textPrimary)
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

