#!/usr/bin/env node
// PinWise News — feed validator (the "validate" step of the content iteration cycle).
//
// Checks a feed against BOTH the NewsFeed Codable contract and PinWise's editorial rules,
// so a regenerated feed can't silently drift (missing citation, hype language, broken date,
// over-long teaser, unknown compound name, placeholder URL, …).
//
// Usage:
//   node scripts/news-content/validate-feed.mjs                 # validates the bundled sampleJSON
//   node scripts/news-content/validate-feed.mjs path/to/feed.json
//   node scripts/news-content/validate-feed.mjs path/to/NewsFeed.swift
//
// Exit code 0 = clean (warnings allowed), 1 = at least one hard error (or bad input).
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dir = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dir, "../..");
const SWIFT_FEED = resolve(REPO, "App/Sources/PeptideKit/News/NewsFeed.swift");
const CATALOG = resolve(REPO, "App/Sources/PeptideKit/Data/CompoundCatalog.swift");

const CATEGORIES = new Set(["Trial results", "Regulatory", "Safety", "New compound", "Guidance", "General"]);
const KINDS = new Set(["trial", "journal", "preprint", "regulatory", "news"]);
// Compounds worth covering in news that are intentionally NOT in the on-device catalog.
const EXTRA_COMPOUNDS = new Set(["Orforglipron"]);
const TEASER_WARN = 100; // editorial target
const TEASER_MAX = 110; // hard ceiling (matches pk-verify)
// Neutrality lint — the app informs, it never recommends or hypes.
const HYPE = [
  /\bmiracle\b/i, /\bcure[sd]?\b/i, /\bguarantee/i, /\bbreakthrough\b/i,
  /\bsafe and effective\b/i, /\byou should\b/i, /\brisk[- ]free\b/i,
  /\bwonder drug\b/i, /\bgame[- ]?changer\b/i, /\bmust[- ]try\b/i,
];

const errors = [];
const warns = [];
const err = (m) => errors.push(m);
const warn = (m) => warns.push(m);

const glyphs = (s) => Array.from(s ?? "").length; // code-point count ~ Swift Character count
const isHttps = (u) => /^https?:\/\/\S+$/.test(u);
const isISODate = (s) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(s) && !Number.isNaN(Date.parse(s));

function extractSampleJSON(swift) {
  const marker = swift.indexOf("sampleJSON");
  const start = swift.indexOf('#"""', marker);
  const end = swift.indexOf('"""#', start);
  if (start < 0 || end < 0) throw new Error("could not locate the sampleJSON raw-string literal in NewsFeed.swift");
  return swift.slice(start + 4, end);
}

async function loadCatalogNames() {
  try {
    const src = await readFile(CATALOG, "utf8");
    const names = [...src.matchAll(/name:\s*"([^"]+)"/g)].map((m) => m[1]);
    return new Set(names);
  } catch {
    warn(`could not read CompoundCatalog for compound-name cross-check (${CATALOG})`);
    return null;
  }
}

async function loadFeed(path) {
  const raw = await readFile(path, "utf8");
  const json = path.endsWith(".swift") ? extractSampleJSON(raw) : raw;
  return JSON.parse(json);
}

function validateItem(it, i, catalog) {
  const where = `item[${i}] "${it.id ?? "?"}"`;
  if (!it.id) err(`${where}: missing id`);
  if (!it.headline) err(`${where}: missing headline`);
  else if (glyphs(it.headline) > 62) warn(`${where}: headline ${glyphs(it.headline)} chars (aim ≤60)`);
  if (!it.summary || glyphs(it.summary) < 40) err(`${where}: summary missing or too short`);
  if (!CATEGORIES.has(it.category)) err(`${where}: invalid category "${it.category}"`);
  if (!Array.isArray(it.compounds) || it.compounds.length === 0) err(`${where}: no compounds listed`);
  if (typeof it.popularity !== "number") err(`${where}: popularity must be a number`);
  if (typeof it.isMajorUpdate !== "boolean") err(`${where}: isMajorUpdate must be a bool`);
  if (!it.disclaimer) err(`${where}: missing disclaimer`);

  // Teaser — every item ships one; keep it scannable.
  if (it.teaser == null) err(`${where}: missing teaser`);
  else if (glyphs(it.teaser) > TEASER_MAX) err(`${where}: teaser ${glyphs(it.teaser)} chars > ${TEASER_MAX}`);
  else if (glyphs(it.teaser) > TEASER_WARN) warn(`${where}: teaser ${glyphs(it.teaser)} chars (target ≤${TEASER_WARN})`);

  // Dates
  if (!isISODate(it.publishedAt)) err(`${where}: publishedAt "${it.publishedAt}" is not ISO-8601 (YYYY-MM-DDTHH:MM:SSZ)`);

  // Sources — the transparency guarantee.
  if (!Array.isArray(it.sources) || it.sources.length === 0) {
    err(`${where}: MUST carry ≥1 source citation`);
  } else {
    for (const s of it.sources) {
      if (!s.name) err(`${where}: a source is missing a name`);
      if (!s.url || !isHttps(s.url)) err(`${where}: source "${s.name}" has a missing/invalid url`);
      else if (/example\.com|placeholder|TODO/i.test(s.url)) err(`${where}: source "${s.name}" uses a placeholder url`);
      if (!KINDS.has(s.kind)) err(`${where}: source "${s.name}" has invalid kind "${s.kind}"`);
    }
  }

  // Neutrality lint
  for (const rx of HYPE) {
    if (rx.test(it.headline) || rx.test(it.summary) || rx.test(it.teaser ?? "")) {
      warn(`${where}: possible non-neutral language matching ${rx}`);
    }
  }

  // Compound-name cross-check (so the "My compounds" filter actually matches the catalog).
  if (catalog) {
    for (const c of it.compounds ?? []) {
      if (!catalog.has(c) && !EXTRA_COMPOUNDS.has(c)) {
        warn(`${where}: compound "${c}" is not in CompoundCatalog (won't match "My compounds"; add to allowlist if intentional)`);
      }
    }
  }
}

async function main() {
  const arg = process.argv[2];
  const path = arg ? resolve(process.cwd(), arg) : SWIFT_FEED;
  let feed;
  try {
    feed = await loadFeed(path);
  } catch (e) {
    console.error(`✗ could not load/parse feed at ${path}: ${e.message}`);
    process.exit(1);
  }

  const catalog = await loadCatalogNames();

  if (typeof feed.version !== "number") err("feed.version must be a number");
  if (!isISODate(feed.generatedAt)) err(`feed.generatedAt "${feed.generatedAt}" is not ISO-8601`);
  if (!Array.isArray(feed.items) || feed.items.length === 0) {
    err("feed.items is empty");
  } else {
    const ids = new Set();
    feed.items.forEach((it, i) => {
      if (it.id && ids.has(it.id)) err(`duplicate id "${it.id}"`);
      if (it.id) ids.add(it.id);
      validateItem(it, i, catalog);
    });
  }

  const n = feed.items?.length ?? 0;
  const majors = (feed.items ?? []).filter((x) => x.isMajorUpdate).length;
  const compounds = new Set((feed.items ?? []).flatMap((x) => x.compounds ?? []));
  console.log(`PinWise feed: ${n} items, ${majors} major, ${compounds.size} distinct compounds covered.`);
  console.log(`Source: ${path}`);
  for (const w of warns) console.log(`  ⚠ ${w}`);
  for (const e of errors) console.log(`  ✗ ${e}`);

  if (errors.length) {
    console.error(`\n✗ FAIL — ${errors.length} error(s), ${warns.length} warning(s).`);
    process.exit(1);
  }
  console.log(`\n✓ PASS — 0 errors, ${warns.length} warning(s).`);
}

main();
