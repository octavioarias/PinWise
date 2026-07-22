import Foundation
#if canImport(Supabase)
import Supabase
#endif

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

    /// Start (or resume) an anonymous session so guests get a small AI quota tracked server-side.
    func signInAnonymously() async throws {
        guard let client else { return }
        // If a session already exists (anonymous or real), keep it.
        if (try? await client.auth.session) != nil { return }
        _ = try await client.auth.signInAnonymously()
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
    func accessToken() async -> String? { nil }
    func signOut() async {}
    #endif
}
