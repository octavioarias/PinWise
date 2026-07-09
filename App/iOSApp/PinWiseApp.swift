import SwiftUI
import SwiftData
import PeptideKit

// App entry point for the iOS target. Add this file (and the rest of App/iOSApp/)
// to the Xcode app project that links the PeptideKit Swift package.
// Fastest setup: `cd App && xcodegen generate` (see App/iOSApp/README.md).
@main
struct PinWiseApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // Local-first store. To enable iCloud private-database sync later, add the iCloud
        // + CloudKit capability and a ModelConfiguration(cloudKitDatabase:) — the model is
        // already CloudKit-safe (see LoggedDose).
        .modelContainer(for: [LoggedDose.self, SavedProtocol.self, StoredVial.self, SymptomEntry.self, BiomarkerEntry.self, CustomCompound.self, PhysiquePhoto.self])
    }
}

/// Gates the app behind sign-in, then one-time onboarding + disclaimer acceptance.
struct RootView: View {
    @AppStorage("acceptedDisclaimerVersion") private var acceptedVersion = 0
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage("weightInPounds") private var weightInPounds = true
    @AppStorage("didInitWeightUnit") private var didInitWeightUnit = false
    @AppStorage("completedIntroTour") private var completedIntroTour = false
    @AppStorage("completedProfileSetup") private var completedProfileSetup = false
    @AppStorage("didMigrateProfileSetup") private var didMigrateProfileSetup = false
    @State private var auth = AuthManager.shared

    /// The app starts the week on MONDAY — so every calendar/date-picker grid lays out
    /// Mon-first. Display only: stored weekday numbers stay absolute (1 = Sun … 7 = Sat) and
    /// all scheduling math uses `Calendar.current`, unaffected by this environment override.
    private static var mondayFirstCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        ZStack {
            RootTabView()
            // First-run gates, shown one at a time in order: sign-in → disclaimer → profile
            // personalization (optional, skippable) → the intro tour → the app (Home).
            if !auth.isAuthenticated {
                WelcomeView()
                    .transition(.opacity)
                    .zIndex(4)
            } else if acceptedVersion < Disclaimer.currentVersion {
                OnboardingView(acceptedVersion: $acceptedVersion)
                    .transition(.opacity)
                    .zIndex(3)
            } else if !completedProfileSetup {
                ProfileSetupView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if !completedIntroTour {
                IntroTourView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Slow, eased cross-dissolves between gates so the hand-off feels premium (not abrupt).
        .animation(.easeInOut(duration: 0.55), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.55), value: acceptedVersion)
        .animation(.easeInOut(duration: 0.55), value: completedProfileSetup)
        .animation(.easeInOut(duration: 0.55), value: completedIntroTour)
        // One-time: seed the weight unit from the device region (user can override in Settings).
        .task {
            if !didInitWeightUnit {
                weightInPounds = Locale.current.measurementSystem != .metric
                didInitWeightUnit = true
            }
            // ONE-TIME migration: existing users (tour already done) shouldn't be interrupted
            // by the new profile-setup gate. Must not repeat — sign-out re-arms the gate on
            // purpose, and a repeating migration would immediately disarm it again.
            if !didMigrateProfileSetup {
                if completedIntroTour && !completedProfileSetup { completedProfileSetup = true }
                didMigrateProfileSetup = true
            }
            // If Health was connected in a past session, refresh silently — no re-prompt.
            await HealthManager.shared.refreshIfConnected()
        }
        .preferredColorScheme(AppearanceMode.from(appearanceRaw).colorScheme)
        // Also force the window's UIKit style so dynamic BrandColor tokens resolve to the same
        // appearance as SwiftUI-native views (prevents invisible native text on mismatch).
        .background(AppearanceApplier(mode: AppearanceMode.from(appearanceRaw)))
        // Week starts on Monday everywhere the app renders a calendar grid.
        .environment(\.calendar, Self.mondayFirstCalendar)
    }
}
