# PinWise

A privacy-first iOS app for tracking peptide / GLP-1 / multi-injectable dosing protocols.
This repo holds both the **advisory knowledge base** (research, strategy, specs) and the
**app itself** (early-stage).

## Layout
```
PeptideTrackingApp/
├── Knowledge/
│   └── KnowledgeBase_v2/                                   # optimized, fact-checked KB — START HERE
│                                                           # (supersedes the original zip'd KB, now removed)
│       ├── 00_KB_Optimization_Report_and_Changelog.md      #   ← the audit: what changed & why
│       ├── 00_Team_Overview_and_Mandate.md
│       ├── 01..08 advisor docs   ├── 09 clinical catalog   ├── 10 competitive matrix
│       └── 99_Synthesis_Master_App_Spec_and_Roadmap.md
└── App/                                                    # the app (Swift)
    ├── Package.swift              # PeptideKit library + pk-verify harness + test target
    ├── Sources/PeptideKit/        # verified domain core (models, calculators, catalog, safety)
    ├── Sources/pk-verify/         # runnable verification harness
    ├── Tests/PeptideKitTests/     # swift-testing suite (runs in Xcode)
    └── iOSApp/                    # SwiftUI sources (app shell + reconstitution calculator)
```

## Where to start
- **Strategy / product:** read `Knowledge/KnowledgeBase_v2/00_KB_Optimization_Report_and_Changelog.md`, then `99_...Roadmap.md`.
- **Code:** `cd App && swift run pk-verify` — runs the domain-logic verification (58 checks). Then see `App/iOSApp/README.md` to wire the SwiftUI layer into Xcode.

## What's built and verified
The domain core (`PeptideKit`) is pure, platform-agnostic Swift with **58 passing checks**:
- **Reconstitution calculator** (vial mg + water mL + dose → syringe units, concentration, doses/vial) and its inverse (units → dose).
- **Blend calculator** (one injection volume → every component's dose, for Wolverine/GLOW-style blends).
- **Inventory** run-out/cost-per-dose projection, **adherence** %, **titration** planner, **site-rotation** advisor.
- **Compounded-dose safety guard** — blocks unit/volume dosing of compounded products until a concentration is on record (prevents the FDA-documented 5–20× overdose pattern).
- **Seeded compound catalog** with evidence tiers, half-lives, regulatory/WADA status, and label-exact GLP-1 titration templates.

## Ground rules baked into the design
PinWise is a **passive record-keeper**: it never recommends a dose or titration (FDA CDS
guidance; Apple Guideline 1.4.2). Calculators are personal unit/volume converters,
titration ladders are user-configured dated templates, insights are neutral display.
Local-first, no PHI in iCloud. **Not medical or legal advice** — the clinical catalog and
regulatory posture require licensed-clinician and licensed-attorney review before launch.
