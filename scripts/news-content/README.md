# PinWise News — content iteration cycle

This folder holds the repeatable process for **enhancing the News tab's articles and
summaries**. The News feature is a fetched-JSON feed with a bundled offline fallback; today
the app ships the fallback (`AppConfig.newsFeedURL` is `nil`), so **what users actually see is
`App/Sources/PeptideKit/News/NewsFeed.swift` → `NewsFeed.sampleJSON`**. That curated fixture
is the thing this cycle regenerates.

There are two content paths in the repo — don't confuse them:

| Path | File | Writer | Quality |
| --- | --- | --- | --- |
| **Bundled sample** (shipping today) | `News/NewsFeed.swift` `sampleJSON` | this cycle (research + human/LLM writing) | curated, polished |
| Live cron feed (not wired up) | `scripts/build-feed.mjs` → `feed/feed.json` | deterministic, no-LLM GitHub Action | mechanical |

The cron pipeline is deliberately LLM-free (no API keys), so **reader-quality writing has to
come from this cycle**, not the cron job.

## The cycle

Run this whenever the flagship research moves (new Phase 3 readout, FDA action, safety signal)
or on a periodic refresh. It's an agent-run loop, not a single script — the research tools are
Claude-side MCP servers (PubMed, ClinicalTrials.gov, ChEMBL, bioRxiv).

1. **Scope** — read `compounds.json`. `focus[]` is the flagship + notable set we source news
   for; `catalogCompounds[]` mirrors `CompoundCatalog.swift` (the names the app's *My
   compounds* filter matches). Names in a feed item's `compounds` array should be catalog names
   (or an entry in `extraCompounds`) or they won't surface under *My compounds*.

2. **Research** — for each focus compound, query the connected research tools using its
   `aliases` as search terms:
   - **ClinicalTrials.gov** (`search_trials`, `get_trial_details`) — trial phase, endpoints,
     status, NCT id, dates.
   - **PubMed** (`search_articles`, `get_article_metadata`, `get_full_text_article`) — pivotal
     papers, PMIDs/DOIs, abstracts.
   - **FDA** (WebSearch/WebFetch a real `fda.gov` URL) — approvals, label updates, compounding
     actions.
   - ChEMBL / bioRxiv as needed for mechanism / preprints.
   Fan these out in parallel (one agent per compound cluster is a good grain). Demand **real
   citations only** — every NCT id, PMID, DOI, and date must come from a retrieved record, not
   memory. Capture honest evidence caveats (thin data, investigational, preclinical).

3. **Write** — synthesize into `NewsItem`s that satisfy the **editorial contract** below.
   Rank by `popularity` (highest = the "Top story"); flag the few most consequential/timely as
   `isMajorUpdate`. Prefer a crafted `teaser` on every item.

4. **Verify (adversarial)** — before anything lands, fact-check each drafted summary against
   its cited source: numbers, dates, approval status, and that the URL resolves to the claim.
   Kill or soften anything you can't stand behind. Accuracy is paramount — this is a health app.

5. **Validate (mechanical)** — run the validator; it enforces the contract so drift can't slip
   through:
   ```sh
   node scripts/news-content/validate-feed.mjs                    # checks the bundled sampleJSON
   node scripts/news-content/validate-feed.mjs feed/feed.json     # or a candidate JSON
   ```

6. **Contract test + CI** — `cd App && swift run pk-verify` (the News-feed section asserts item
   count, major count, citations, disclaimers, teasers). If you changed the item/major counts,
   update those asserts in `App/Sources/pk-verify/main.swift`. Then commit → push → watch CI.

Loop back to step 2 for anything the verify/validate steps reject.

## Editorial contract (every item)

- **Neutral & non-recommending.** Inform and link out; never advise, hype, or rank. The
  validator lints for hype language.
- **≥1 real source citation** with a working `https` URL and a valid `kind`
  (`trial|journal|preprint|regulatory|news`). No placeholder/`example.com` URLs.
- **A disclaimer** (the standard "Neutral informational summary…" line).
- **Approval status stated** wherever it applies — say plainly when something is
  investigational / not FDA-approved / preclinical. Honesty about *thin* evidence is content,
  not a gap.
- **A `teaser`** ≤100 chars (hard ceiling 110) — the scannable list/card copy.
- **`summary`** ≈ 2–3 sentences, layperson-readable.
- **`publishedAt`** ISO-8601 (`YYYY-MM-DDT00:00:00Z`), the real date of the result/action.
- **`compounds`** using catalog names (or `extraCompounds`), so *My compounds* matches.
- **`id`** stable and unique (reuse the id when updating an existing story).
- Images: the bundled sample omits `imageURL` and relies on the branded-gradient fallback —
  don't add fragile external image URLs to the shipping fixture.

## Files

- `compounds.json` — scope config (focus set + aliases, catalog mirror, extras allowlist).
- `validate-feed.mjs` — the mechanical gate (step 5). Reads `NewsFeed.swift` directly (extracts
  the `sampleJSON` literal) or any feed `.json`. Exit 1 on any hard error.
- `README.md` — this playbook.
