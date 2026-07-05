import Foundation
import SwiftUI
import AuthenticationServices

/// Which method the current session was created with.
enum AuthProvider: String, Codable, Sendable { case apple, google, email, guest }

/// App-wide sign-in state. Sign in with Apple works fully on-device with no backend.
/// Google + Email are wired through here too, but require a backend (see `signInWithGoogle` /
/// `startEmailSignIn`) — recommended setup is a Supabase project + a Google OAuth client ID.
/// State persists in UserDefaults so a signed-in user isn't re-prompted on launch.
@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    private enum K {
        static let provider = "auth.provider", uid = "auth.uid", name = "auth.name", email = "auth.email"
    }
    private let store = UserDefaults.standard

    private(set) var providerRaw: String? { didSet { store.set(providerRaw, forKey: K.provider) } }
    private(set) var userID: String?      { didSet { store.set(userID, forKey: K.uid) } }
    private(set) var displayName: String? { didSet { store.set(displayName, forKey: K.name) } }
    private(set) var email: String?       { didSet { store.set(email, forKey: K.email) } }

    /// Transient message the sign-in screen surfaces (errors or "coming soon" notices).
    var notice: String?

    var isAuthenticated: Bool { providerRaw != nil }
    var provider: AuthProvider? { providerRaw.flatMap(AuthProvider.init) }
    var isGuest: Bool { provider == .guest }
    /// A friendly label for menus ("Signed in with Apple", the name, or the email).
    var accountLabel: String {
        if isGuest { return "Guest — not signed in" }
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return provider.map { "Signed in with \($0.rawValue.capitalized)" } ?? "Signed in"
    }

    private init() {
        providerRaw = store.string(forKey: K.provider)   // note: init assignment doesn't fire didSet
        userID = store.string(forKey: K.uid)
        displayName = store.string(forKey: K.name)
        email = store.string(forKey: K.email)
    }

    // MARK: Sign in with Apple (native, no backend)

    /// Handles the result from SwiftUI's `SignInWithAppleButton`. Apple returns the name/email
    /// only on the *first* authorization, so we only overwrite those when present.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                notice = "Couldn't read the Apple credential — try again."; return
            }
            let parts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
            set(provider: .apple, uid: cred.user,
                name: parts.isEmpty ? nil : parts.joined(separator: " "),
                email: cred.email)
        case .failure:
            notice = nil   // user canceled — don't nag
        }
    }

    func continueAsGuest() { set(provider: .guest, uid: "guest", name: nil, email: nil) }

    // MARK: Google / Email (pending backend)

    func signInWithGoogle() {
        // TODO(backend): add the GoogleSignIn SPM package + a GIDClientID (Info.plist) and call
        // GIDSignIn.sharedInstance.signIn(...), then exchange the token with the backend.
        notice = "Google sign-in is almost ready — it needs the Google client ID + backend to finish. For now, use Apple or continue without an account."
    }

    func startEmailSignIn() {
        // TODO(backend): email/password accounts require a backend (Supabase Auth recommended).
        notice = "Email accounts are almost ready — they need the backend to finish. For now, use Apple or continue without an account."
    }

    func signOut() { set(provider: nil, uid: nil, name: nil, email: nil) }

    // MARK: -

    private func set(provider: AuthProvider?, uid: String?, name: String?, email: String?) {
        userID = uid
        if let name { displayName = name } else if provider == nil { displayName = nil }
        if let email { self.email = email } else if provider == nil { self.email = nil }
        providerRaw = provider?.rawValue
        notice = nil
    }
}
