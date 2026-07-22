import Foundation

/// A single conversation turn sent to the backend.
struct CloudAIMessage: Codable {
    let role: String     // "user" | "assistant"
    let content: String
}

enum CloudAIError: Error {
    case notConfigured          // Supabase credentials not filled in yet
    case notSignedIn            // no Supabase session
    case limitReached(limit: Int)
    case http(Int)
    case stream(String)
}

/// Talks to the `ai-chat` Supabase Edge Function: sends the conversation + the user-data context,
/// authenticated with the current Supabase access token, and streams the assistant's reply back as
/// tokens. The provider key lives only on the server — this client never sees it. Extends the
/// app's existing async-URLSession style (`NewsFeedLoader`) with a bearer token + SSE parsing.
@MainActor
final class CloudAIClient {
    private struct RequestBody: Encodable {
        let messages: [CloudAIMessage]
        let context: String
    }
    private struct SSEEvent: Decodable {
        let type: String
        let text: String?
        let message: String?
    }
    private struct LimitBody: Decodable { let limit: Int }

    /// Streams assistant text deltas. `messages` is the full history ending in the latest user
    /// turn; `context` is the bounded user-data snapshot. The stream finishes on `done`, or throws
    /// a `CloudAIError` (notably `.limitReached` for the quota upsell).
    func stream(messages: [CloudAIMessage], context: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let work = Task { @MainActor in
                do {
                    guard AppConfig.isBackendConfigured else { throw CloudAIError.notConfigured }
                    // Self-heal: if there's no Supabase session yet (e.g. a user who signed in
                    // before this backend existed, or a fresh guest), start an anonymous one so the
                    // assistant works at the free/trial tier without forcing a re-login.
                    var token = await SupabaseService.shared.accessToken()
                    if token == nil {
                        try? await SupabaseService.shared.signInAnonymously()
                        token = await SupabaseService.shared.accessToken()
                    }
                    guard let token else { throw CloudAIError.notSignedIn }

                    var req = URLRequest(url: AppConfig.aiChatURL)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try JSONEncoder().encode(RequestBody(messages: messages, context: context))

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else { throw CloudAIError.stream("no response") }

                    guard http.statusCode == 200 else {
                        // Non-200 bodies are plain JSON, not SSE — drain and interpret.
                        var raw = ""
                        for try await line in bytes.lines { raw += line }
                        if http.statusCode == 429, let d = raw.data(using: .utf8),
                           let info = try? JSONDecoder().decode(LimitBody.self, from: d) {
                            throw CloudAIError.limitReached(limit: info.limit)
                        }
                        throw CloudAIError.http(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !json.isEmpty, let data = json.data(using: .utf8),
                              let evt = try? JSONDecoder().decode(SSEEvent.self, from: data) else { continue }
                        switch evt.type {
                        case "delta":
                            if let t = evt.text { continuation.yield(t) }
                        case "done":
                            continuation.finish()
                            return
                        case "error":
                            throw CloudAIError.stream(evt.message ?? "error")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}
