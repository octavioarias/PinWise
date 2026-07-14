import Foundation

/// Decides when to surface an App Store review request based on how long someone has used the
/// app. PinWise asks at tenure milestones — day 8, 30, 60 — and never more than once per
/// milestone. Apple itself still throttles the real prompt (max 3/year, and the system decides
/// whether to actually display it), so these are *requests*, not guaranteed dialogs.
public enum ReviewPrompt {
    /// Days-of-use milestones at which to request a review.
    public static let milestones = [8, 30, 60]

    /// The milestone to fire now, or nil if none is due. Returns the HIGHEST reached-but-not-yet-
    /// fired milestone, so a user who opens the app after a long gap gets a single request, not a
    /// backlog of them. `lastFired` is the most recent milestone already requested (0 = none).
    public static func due(daysSinceInstall: Int, lastFired: Int, milestones: [Int] = milestones) -> Int? {
        milestones.filter { $0 <= daysSinceInstall && $0 > lastFired }.max()
    }
}
