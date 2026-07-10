# PinWise

A privacy-first iOS app for tracking peptide / GLP-1 / multi-injectable dosing protocols —
and the source of truth for the science around them. This repo holds the **advisory knowledge
base** (research, strategy, specs) and the **app** (a CI-validated v1).

Repo: `github.com/TavioTheScientist/PinWise` · CI: GitHub Actions (compiles + tests every push).

## Layout
```
PeptideTrackingApp/
├── Knowledge/KnowledgeBase_v2/     # fact-checked KB — START HERE (00 report, 12 build status)
├── App/
│   ├── Package.swift               # PeptideKit library + pk-verify + tests
│   ├── Sources/PeptideKit/         # verified domain core (models, calculators, catalog, safety, news contract)
│   ├── Sources/pk-verify/          # runnable verification harness (66 checks)
│   ├── Tests/PeptideKitTests/      # swift-testing suite (runs in Xcode/CI)
│   ├── iOSApp/                     # SwiftUI app (Onboarding, Home, Log, Protocols+Inventory, News, Tools)
│   └── project.yml                 # XcodeGen spec
├── scripts/build-feed.mjs          # News feed generator (ClinicalTrials.gov + PubMed)
├── feed/feed.json                  # generated News feed
└── .github/workflows/              # ci.yml (build+test) · news-feed.yml (daily feed)
```

## Run it
```sh
brew install xcodegen        # once
cd App && xcodegen generate && open PinWise.xcodeproj   # then ⌘R
swift run pk-verify          # domain-core check (no Xcode needed)
```

## What's built (v1)
A complete, CI-validated free-tier MVP — see **`Knowledge/KnowledgeBase_v2/12_v1_Build_Status_and_Next_Iteration.md`** for the full status + next-iteration backlog.
- **Onboarding** + gated 18+ disclaimer acceptance.
- **Home** — live adherence ring, next dose, recent activity.
- **Log** — fast logging (quick-fill from protocols, site suggestion, backfill, haptics); decrements inventory.
- **Protocols & Inventory** — protocol builder with reminders; vials with run-out/cost/expiry; compound library.
- **News** — neutral, cited editorial feed (live pipeline + bundled fallback).
- **Tools** — verified reconstitution calculator.
- Deep-blue design system (60-30-10, WCAG-audited), reminders, SwiftData (CloudKit-safe), local-first.

## Ground rules baked into the design
PinWise is a **passive record-keeper**: it never recommends a dose or titration (FDA CDS
guidance; Apple Guideline 1.4.2). Calculators are personal converters, titration ladders are
user-configured templates, insights are neutral display. Local-first; privacy language lives
only in agreements/disclaimers. **Not medical or legal advice** — the clinical catalog and
regulatory posture require licensed-clinician and licensed-attorney review before launch.
