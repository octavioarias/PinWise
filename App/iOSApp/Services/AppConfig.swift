import Foundation

/// App-wide configuration constants.
enum AppConfig {
    /// URL of the published `feed.json` for live News. `nil` = use the bundled sample feed.
    /// Published daily by `scripts/build-feed.mjs` + `.github/workflows/news-feed.yml` to the
    /// public PinWise-NewsFeed repo. The app fetches best-effort and falls back to the bundled
    /// sample (and its on-disk cache) whenever this is unreachable.
    static let newsFeedURL: URL? = URL(string: "https://raw.githubusercontent.com/TavioTheScientist/PinWise-NewsFeed/main/feed.json")
}
