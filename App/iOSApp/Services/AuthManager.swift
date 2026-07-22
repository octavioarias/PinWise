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
        static let since = "auth.since"
    }
    private let store = UserDefaults.standard

    private(set) var providerRaw: String? { didSet { store.set(providerRaw, forKey: K.provider) } }
    private(set) var userID: String?      { didSet { store.set(userID, forKey: K.uid) } }
    private(set) var displayName: String? { didSet { store.set(displayName, forKey: K.name) } }
    private(set) var email: String?       { didSet { store.set(email, forKey: K.email) } }
    /// When this session was first created — the profile's "member since" date.
    private(set) var memberSince: Date?   { didSet { store.set(memberSince, forKey: K.since) } }

    /// Transient message the sign-in screen surfaces (errors or "coming soon" notices).
    var notice: String?

    var isAuthenticated: Bool { providerRaw != nil }
    var provider: AuthProvider? { providerRaw.flatMap(AuthProvider.init) }
    var isGuest: Bool { provider == .guest }

    /// User-facing name of the sign-in method — shared by the profile screen and menus.
    var providerLabel: String {
        switch provider {
        case .apple: return "Apple ID"
        case .google: return "Google"
        case .email: return "Email"
        case .guest: return "Guest — not signed in"
        case .none: return isAuthenticated ? "Signed in" : "Not signed in"
        }
    }

    /// Second line under the user's name in menus: the account itself.
    var accountSubtitle: String {
        if isGuest { return "Guest — not signed in" }
        if let email, !email.isEmpty { return email }
        if provider == .apple { return "Signed in with Apple" }
        return isAuthenticated ? "Signed in" : "Tap to view your profile"
    }

    private init() {
        providerRaw = store.string(forKey: K.provider)   // note: init assignment doesn't fire didSet
        userID = store.string(forKey: K.uid)
        displayName = store.string(forKey: K.name)
        email = store.string(forKey: K.email)
        memberSince = store.object(forKey: K.since) as? Date
        // One-time migration: the profile name used to live under its own AppStorage key.
        // The legacy value wins even over an Apple-provided name — it was the user's most
        // recent explicit edit in the old UI. The key is always removed so it can't linger.
        if let legacy = store.string(forKey: "profileName") {
            let trimmed = legacy.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { displayName = trimmed }
            store.removeObject(forKey: "profileName")
        }
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
            // Bridge to the backend: exchange Apple's identity token for a Supabase session so the
            // hosted AI can authenticate the user. Best-effort — the on-device session set above
            // stands regardless, and this is a no-op until the backend is configured.
            if let tokenData = cred.identityToken, let idToken = String(data: tokenData, encoding: .utf8) {
                Task { try? await SupabaseService.shared.signInWithApple(idToken: idToken) }
            }
        case .failure:
            notice = nil   // user canceled — don't nag
        }
    }

    func continueAsGuest() {
        set(provider: .guest, uid: "guest", name: nil, email: nil)
        // Anonymous Supabase session so guests get a small server-tracked AI quota.
        Task { try? await SupabaseService.shared.signInAnonymously() }
    }

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

    func signOut() {
        set(provider: nil, uid: nil, name: nil, email: nil)
        Task { await SupabaseService.shared.signOut() }
    }

    /// Guest tapped "Sign in": drop the guest session so the welcome screen shows, but keep
    /// the typed name (and memberSince) so they survive the upgrade to a real account.
    func beginAccountUpgrade() {
        providerRaw = nil
        userID = nil
    }

    /// Lets the profile screen edit the name shown across the app (drawer, greetings).
    /// Ignores empty input so an accidental field-clear can't destroy the Apple-provided
    /// name — Apple only delivers it on the first authorization, so it's unrecoverable.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else { return }
        displayName = trimmed
    }

    // MARK: -

    private func set(provider: AuthProvider?, uid: String?, name: String?, email: String?) {
        userID = uid
        if let name { displayName = name } else if provider == nil { displayName = nil }
        if let email { self.email = email } else if provider == nil { self.email = nil }
        providerRaw = provider?.rawValue
        if provider == nil {
            memberSince = nil
        } else if memberSince == nil {
            memberSince = Date()
        }
        notice = nil
    }
}
