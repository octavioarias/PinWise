import Foundation

/// App-wide configuration constants.
enum AppConfig {
    /// URL of the published `feed.json` for live News. `nil` = use the bundled sample feed.
    /// Published daily by `scripts/build-feed.mjs` + `.github/workflows/news-feed.yml` to the
    /// public PinWise-NewsFeed repo. The app fetches best-effort and falls back to the bundled
    /// sample (and its on-disk cache) whenever this is unreachable.
    static let newsFeedURL: URL? = URL(string: "https://raw.githubusercontent.com/TavioTheScientist/PinWise-NewsFeed/main/feed.json")

    // MARK: Supabase (hosted AI backend)
    // From the Supabase dashboard → Project Settings → API. The anon/publishable key is safe to
    // ship (it's public by design; Row-Level Security protects the data). Fill these in after
    // creating the project (see supabase/README.md). Until set, `isBackendConfigured` is false and
    // the assistant shows a "not configured" state instead of calling out.
    static let supabaseURL = URL(string: "https://spgslwppcoughfsyzccc.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwZ3Nsd3BwY291Z2hmc3l6Y2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2ODQ1NzYsImV4cCI6MjEwMDI2MDU3Nn0.UfRx33z6ft1RdSSU_o1mQYpUrCF_OnA2BhXb6p2Xfqk"

    /// The `ai-chat` Edge Function endpoint.
    static var aiChatURL: URL { supabaseURL.appendingPathComponent("functions/v1/ai-chat") }

    /// True once real Supabase credentials have been filled in above.
    static var isBackendConfigured: Bool {
        !supabaseAnonKey.hasPrefix("YOUR-") && !(supabaseURL.host ?? "").hasPrefix("YOUR-")
    }
}
