import Foundation
#if canImport(Supabase)
import Supabase
#endif

/// The signed-in user returned after an email-code verification.
struct SupabaseAuthedUser { let id: String; let email: String? }

enum SupabaseAuthError: Error { case notConfigured }

/// Thin wrapper around the Supabase Swift SDK, used for AUTH only — Apple id-token sign-in,
/// anonymous (guest) sessions, and token refresh. The SDK persists + refreshes the session in the
/// Keychain for us. The actual AI streaming call is hand-rolled in `CloudAIClient` (the SDK's
/// function-invoke doesn't stream SSE), authenticated with the access token this service exposes.
///
/// A no-op when `AppConfig.isBackendConfigured` is false (placeholder credentials), so the app
/// still builds and runs before the founder wires up the Supabase project.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    #if canImport(Supabase)
    private let client: SupabaseClient?

    private init() {
        client = AppConfig.isBackendConfigured
            ? SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)
            : nil
    }

    /// Exchange an Apple identity token (the JWT from Sign in with Apple) for a Supabase session.
    func signInWithApple(idToken: String) async throws {
        guard let client else { return }
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
        )
    }

    /// Start (or resume) an anonymous session. (Currently unused — the assistant requires a real
    /// account — kept for potential future use.)
    func signInAnonymously() async throws {
        guard let client else { return }
        if (try? await client.auth.session) != nil { return }
        _ = try await client.auth.signInAnonymously()
    }

    /// Send a one-time login code to the given email (creates the account if new).
    func sendEmailCode(_ email: String) async throws {
        guard let client else { throw SupabaseAuthError.notConfigured }
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    /// Verify the emailed code and establish a session. Returns the signed-in user.
    func verifyEmailCode(email: String, code: String) async throws -> SupabaseAuthedUser {
        guard let client else { throw SupabaseAuthError.notConfigured }
        _ = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        guard let user = client.auth.currentUser else { throw SupabaseAuthError.notConfigured }
        return SupabaseAuthedUser(id: user.id.uuidString, email: user.email)
    }

    /// A valid access token for the current session, refreshing if needed. `nil` if not signed in
    /// or the backend isn't configured.
    func accessToken() async -> String? {
        guard let client else { return nil }
        return try? await client.auth.session.accessToken
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
    }
    #else
    private init() {}
    func signInWithApple(idToken: String) async throws {}
    func signInAnonymously() async throws {}
    func sendEmailCode(_ email: String) async throws { throw SupabaseAuthError.notConfigured }
    func verifyEmailCode(email: String, code: String) async throws -> SupabaseAuthedUser { throw SupabaseAuthError.notConfigured }
    func accessToken() async -> String? { nil }
    func signOut() async {}
    #endif
}
