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
        .modelContainer(for: [LoggedDose.self, SavedProtocol.self, StoredVial.self])
    }
}

/// Gates the app behind one-time onboarding + disclaimer acceptance.
struct RootView: View {
    @AppStorage("acceptedDisclaimerVersion") private var acceptedVersion = 0
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.dark.rawValue

    var body: some View {
        ZStack {
            RootTabView()
            if acceptedVersion < Disclaimer.currentVersion {
                OnboardingView(acceptedVersion: $acceptedVersion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(AppearanceMode.from(appearanceRaw).colorScheme)
    }
}
