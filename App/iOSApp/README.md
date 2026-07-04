# PinWise — iOS app sources

These SwiftUI files are the **iOS app layer**. They are deliberately kept *outside*
`App/Sources/` so the `PeptideKit` Swift package stays buildable and testable on any
machine (and CI) without an iOS SDK or simulator. All dosing math lives in `PeptideKit`
and is verified independently (`swift run pk-verify`).

## Fastest path — generate the project (recommended)
A checked-in [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec (`App/project.yml`)
builds the whole app project in one command — no manual clicking:
```sh
brew install xcodegen        # once
cd App
xcodegen generate           # creates PinWise.xcodeproj (git-ignored)
open PinWise.xcodeproj      # then ⌘R on a simulator
```
This wires the local `PeptideKit` package, compiles `iOSApp/`, and applies `iOSApp/Info.plist`
(HealthKit usage string, encryption exemption). Prefer the manual route? It's below.

## First run — once Xcode finishes installing
1. `cd App && xcodegen generate` (already generated; re-run only if `project.yml` changed).
2. `open PinWise.xcodeproj`.
3. Pick an **iPhone simulator** in the toolbar (e.g. iPhone 16), then press **⌘R**. The first
   build compiles `PeptideKit` + the app. **Simulator runs need no signing.**
4. Expect the dark PinWise shell + a working reconstitution calculator
   (5&nbsp;mg / 2&nbsp;mL / 250&nbsp;mcg → 10 units).

### Run on your own iPhone (optional, free)
- Plug in the device and select it as the run destination.
- App target → **Signing & Capabilities** → check **Automatically manage signing** → pick your
  Apple ID team (add it under **Xcode ▸ Settings ▸ Accounts** first if needed). A free Apple ID
  gives a 7-day provisioning profile.

### If the first build complains
- **Missing iOS 18 SDK / no simulators** → **Xcode ▸ Settings ▸ Components** (or Platforms), install
  the iOS runtime; confirm Xcode 16+.
- **"PeptideKit" not found / package error** → **File ▸ Packages ▸ Reset Package Caches**, rebuild.
- **Signing error** → only affects *device* runs, not the simulator — start on a simulator.
- **A Swift compile error** → copy the first one or two and send them over. The app target runs in
  Swift 5 language mode specifically to keep these rare during early iteration.

## Why it's split this way
- `App/Sources/PeptideKit` — pure domain core (models + calculators). Buildable with the
  Command Line Tools toolchain; no UI, no platform frameworks.
- `App/iOSApp` — SwiftUI views + app entry point. Requires the iOS SDK (full Xcode) to
  build and run. Links `PeptideKit` as a local package dependency.

## Wiring it into Xcode (one-time)
1. In Xcode: **File ▸ New ▸ Project… ▸ iOS App**, product name `PinWise`, interface
   SwiftUI, language Swift. Delete the auto-generated `ContentView.swift` and the
   `App` struct.
2. **File ▸ Add Package Dependencies… ▸ Add Local…** and select the `App/` folder
   (the one containing `Package.swift`). Add the `PeptideKit` library to the app target.
3. Drag the contents of `App/iOSApp/` into the app target (check "Copy items if needed"
   off if you want them to stay in this repo location; add as folder references or
   groups as you prefer).
4. Set the deployment target to **iOS 17** (the code uses `@Observable` / Observation).
5. Build & run on a simulator.

## What's implemented so far
- `PinWiseApp.swift` — `@main` entry point.
- `DesignSystem/` — the brand design system: `PinWiseTheme.swift` (color, type, spacing,
  radius; dark + electric-accent) and `PinWiseComponents.swift` (`Card`, `PrimaryButton`,
  `StatTile`, `SectionHeader`, `DisclaimerBanner`, `AdvisoryRow`, `EvidenceBadge`).
- `RootTabView.swift` — the dark-first, accent-tinted 5-tab shell.
- `HomeView.swift` — branded dashboard (quick actions, today summary, disclaimer).
- `Features/Calculator/ReconstitutionCalculatorView.swift` — reconstitution calculator
  backed by the verified `ReconstitutionCalculator`.

Log, Protocols, and Insights are themed placeholders, built out next
(see the roadmap in `/Knowledge/KnowledgeBase_v2/99_...`).

> Note: these SwiftUI sources compile only in Xcode (iOS SDK). The design-system colors
> use a swappable electric accent (`BrandColor.accent`) — change one line to match final brand.
