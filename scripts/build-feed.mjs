#!/usr/bin/env node
// Builds PinWise's News feed.json — HYBRID model:
//   • a CURATED evergreen base (the polished, hand-verified items that ship in the app's
//     NewsFeed.sampleJSON) is read straight from the Swift source so there's ONE source of
//     truth, and
//   • FRESH items fetched daily from public sources (ClinicalTrials.gov v2 + PubMed) for the
//     active-news compounds, deduped against the curated base and filtered to recent events.
//
// The curated base carries the prose quality (the hero/Top-story items); the fresh items keep
// the feed current in the "Latest" stream. Neutral, cited summaries only — no recommendations.
// Fresh items are then rewritten by a small LLM step (Claude Haiku) into short, punchy,
// plain-language headlines + a key finding + a clean summary — accuracy-first (facts only, never
// fabricated results), and it falls back to the raw extracted text if ANTHROPIC_API_KEY is unset
// or a call fails, so the build never depends on it. Only the three prose fields are touched;
// compounds, sources, and dates stay deterministic. Matches the NewsFeed contract in
// App/Sources/PeptideKit/News/NewsFeed.swift.
//
// Usage:  node scripts/build-feed.mjs   ->  writes feed/feed.json
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dir = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dir, "..");
const CURATED_SWIFT = resolve(REPO, "App/Sources/PeptideKit/News/NewsFeed.swift");
const COMPOUNDS_CONFIG = resolve(REPO, "scripts/news-content/compounds.json");

const DISCLAIMER =
  "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician.";

// Fresh items must be at least this recent to be appended (older developments are already
// framed by the curated base). ~9 months keeps the "Latest" stream current on daily runs.
const FRESH_MAX_AGE_DAYS = 270;
// Only fetch fresh news for the actively-moving compounds (priority ≤ this in compounds.json);
// niche peptides rarely have fresh trial/journal news and the curated base already covers them.
const FRESH_PRIORITY_MAX = 2;
const MAX_FRESH = 15; // cap appended fresh items so the feed stays scannable
const MIN_SUMMARY = 60; // drop fresh items with no real abstract/description (thin content)
const HEADLINE_CAP = 56; // headlines must fit a phone news card on ~2 lines without truncating
const NOW = Date.now();
// ISO-8601 without fractional seconds, to match the feed contract (YYYY-MM-DDTHH:MM:SSZ).
const ISO_NOW = new Date(NOW).toISOString().replace(/\.\d{3}Z$/, "Z");

// -------------------------------------------------------------------------------------
// Text helpers — sentence/word-boundary aware.
// -------------------------------------------------------------------------------------
const clean = (s) =>
  (s || "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();

function wordCap(s, n) {
  s = clean(s);
  if (s.length <= n) return s;
  const cut = s.slice(0, n);
  const sp = cut.lastIndexOf(" ");
  return (sp > 0 ? cut.slice(0, sp) : cut).replace(/[\s.,;:]+$/, "") + "…";
}

function firstSentences(text, maxSentences = 2, maxChars = 320) {
  const t = clean(text);
  if (!t) return "";
  const parts = t.match(/[^.!?]+[.!?]+(?:\s|$)/g) || [t];
  let out = "";
  for (const s of parts.slice(0, maxSentences)) {
    if (out && (out + s).length > maxChars) break;
    out += s;
  }
  out = out.trim();
  return out || wordCap(t, maxChars);
}

const teaserFrom = (body) => wordCap(firstSentences(body, 1, 100), 100);
const cap1 = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

function toISO(raw) {
  const m = String(raw || "").match(/(\d{4})[-/](\d{2})[-/](\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}T00:00:00Z` : null;
}

const ageDays = (iso) => (NOW - Date.parse(iso)) / 86_400_000;

// -------------------------------------------------------------------------------------
// Deterministic category classification — first match wins.
// -------------------------------------------------------------------------------------
function classify(text, sourceKind) {
  const t = (text || "").toLowerCase();
  if (
    /\b(recall\w*|boxed warning|black[- ]box|contaminat\w*|counterfeit\w*|adulterat\w*|overdose\w*|poisoning|fatalit\w*|safety alert|safety signal|serious safety|life-threatening|withdrawn from (the )?market|unregulated (peptide|compound|drug)|performance-enhancing)\b/.test(
      t
    )
  )
    return "Safety";
  if (
    /\b(fda|ema|mhra|503a|503b|compounding pharmac\w*|marketing auth\w*|granted approval|newly approved|drug approval|regulatory action|import alert|dea|controlled substance|reschedul\w*|scheduling (decision|action|notice)|advisory committee|adcom|pdufa|complete response letter|federal register|warning letter|form 483|orphan[- ]drug designation|breakthrough therapy|fast[- ]track|de novo (clearance|authorization)|biosimilar approval)\b/.test(
      t
    )
  )
    return "Regulatory";
  if (/\b(guideline\w*|clinical practice recommendation|consensus statement|position statement|expert consensus)\b/.test(t))
    return "Guidance";
  if (/\b(first-in-human|first in human|phase\s*1\b|novel (agent|compound|analog|analogue|peptide)|investigational new drug)\b/.test(t))
    return "New compound";
  if (
    sourceKind === "trial" ||
    /\b(phase\s*[234]|trial\w*|randomi[sz]\w*|placebo|efficacy|endpoint\w*|primary outcome|meta-analysis|network meta|cohort\w*)\b/.test(t)
  )
    return "Trial results";
  return "General";
}

// -------------------------------------------------------------------------------------
// Compound extraction — known catalog names + aliases, hyphen-tolerant word-boundary scan.
// Names here MUST match CompoundCatalog.swift so the app's "My compounds" filter lines up.
// -------------------------------------------------------------------------------------
const KNOWN = {
  Semaglutide: ["semaglutide", "ozempic", "wegovy", "rybelsus"],
  Tirzepatide: ["tirzepatide", "mounjaro", "zepbound", "ly3298176"],
  Retatrutide: ["retatrutide", "ly3437943"],
  Cagrilintide: ["cagrilintide", "cagrisema"],
  Survodutide: ["survodutide", "bi 456906"],
  Mazdutide: ["mazdutide", "ibi362", "ly3305677"],
  Orforglipron: ["orforglipron", "ly3502970", "foundayo"],
  Tesamorelin: ["tesamorelin", "egrifta"],
  "MK-677": ["mk-677", "mk 677", "ibutamoren"],
  Sermorelin: ["sermorelin", "geref"],
  Ipamorelin: ["ipamorelin"],
  "BPC-157": ["bpc-157", "bpc157", "bpc 157"],
  "TB-500": ["tb-500", "tb500", "tb 500"],
  "Thymosin Beta-4": ["thymosin beta-4", "thymosin beta 4", "tβ4", "rgn-259"],
  "Thymosin Alpha-1": ["thymosin alpha-1", "thymosin alpha 1", "thymalfasin", "zadaxin"],
  "PT-141": ["bremelanotide", "vyleesi", "pt-141", "pt 141"],
  "NAD+": ["nicotinamide riboside", "nicotinamide mononucleotide", " nmn ", " nad+"],
  Liraglutide: ["liraglutide", "victoza", "saxenda"],
  Dulaglutide: ["dulaglutide", "trulicity"],
};

function extractCompounds(text, fallbackName) {
  const t = (text || "").toLowerCase();
  const hits = [];
  for (const [name, aliases] of Object.entries(KNOWN)) {
    const matched = aliases.some((a) => {
      const pat = a.trim().replace(/[-\s]/g, "[-\\s]?");
      return new RegExp(`(^|[^a-z0-9])${pat}([^a-z0-9]|$)`).test(t);
    });
    if (matched) hits.push(name);
  }
  return hits.length ? [...new Set(hits)] : [fallbackName];
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// -------------------------------------------------------------------------------------
// ClinicalTrials.gov v2 — description + outcomes so summaries carry real text.
// `fallbackName` is the catalog compound name, used to tag items and as a summary fallback.
// -------------------------------------------------------------------------------------
async function fromClinicalTrials(term, fallbackName) {
  const url =
    "https://clinicaltrials.gov/api/v2/studies?" +
    new URLSearchParams({
      "query.term": term,
      pageSize: "3",
      sort: "LastUpdatePostDate:desc",
      fields: [
        "protocolSection.identificationModule",
        "protocolSection.statusModule",
        "protocolSection.designModule",
        "protocolSection.conditionsModule",
        "protocolSection.descriptionModule",
        "protocolSection.outcomesModule",
      ].join(","),
    });
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`CT ${res.status}`);
  const json = await res.json();
  return (json.studies || []).map((s) => {
    const p = s.protocolSection || {};
    const nct = p.identificationModule?.nctId || "";
    const title = p.identificationModule?.briefTitle || "Clinical trial";
    const status = p.statusModule?.overallStatus || "";
    const date = p.statusModule?.lastUpdatePostDateStruct?.date || "";
    const phase = (p.designModule?.phases || []).join("/");
    const conditions = (p.conditionsModule?.conditions || []).slice(0, 2).join(", ");
    const brief = clean(p.descriptionModule?.briefSummary || "");
    const outcome = clean(
      (p.outcomesModule?.primaryOutcomes || []).map((o) => o?.measure).filter(Boolean).join("; ")
    );
    const context =
      `${phase ? phase.replace(/_/g, " ") + " " : ""}` +
      `${conditions ? "trial in " + conditions + ". " : "trial. "}` +
      `According to ClinicalTrials.gov, its status is ${status || "unknown"}${date ? `, last updated ${date}` : ""}.`;
    const lede = firstSentences(brief || context, 2, 320);
    const body = lede + (outcome ? ` Primary outcome: ${wordCap(outcome, 120)}.` : "");
    const classText = `${title} ${brief} ${outcome} ${phase} ${conditions} ${status}`;
    return {
      id: `ct-${nct}`,
      headline: wordCap((title || "Clinical trial").replace(/\.$/, ""), HEADLINE_CAP),
      summary: body,
      teaser: teaserFrom(body),
      category: classify(classText, "trial"),
      compounds: extractCompounds(`${title} ${brief}`, fallbackName),
      sources: [
        { name: `ClinicalTrials.gov (${nct})`, url: `https://clinicaltrials.gov/study/${nct}`, kind: "trial" },
      ],
      publishedAt: toISO(date) || ISO_NOW,
      disclaimer: DISCLAIMER,
    };
  });
}

// -------------------------------------------------------------------------------------
// PubMed — esearch -> esummary -> one BATCHED efetch for abstracts (throttled).
// -------------------------------------------------------------------------------------
function parseAbstractsByPMID(xml) {
  const byId = {};
  const articles = xml.match(/<PubmedArticle\b[\s\S]*?<\/PubmedArticle>/g) || [];
  for (const art of articles) {
    const pmid = (art.match(/<PMID[^>]*>(\d+)<\/PMID>/) || [])[1];
    if (!pmid) continue;
    const segs = [...art.matchAll(/<AbstractText\b[^>]*>([\s\S]*?)<\/AbstractText>/g)].map((m) =>
      clean(m[1])
    );
    const abstract = segs.filter(Boolean).join(" ").trim();
    if (abstract) byId[pmid] = abstract;
  }
  return byId;
}

async function fromPubMed(term, fallbackName) {
  const esearch =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" +
    new URLSearchParams({ db: "pubmed", term, retmode: "json", retmax: "2", sort: "date" });
  const ids = (await (await fetch(esearch)).json())?.esearchresult?.idlist || [];
  if (!ids.length) return [];
  await sleep(350);

  const esummary =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?" +
    new URLSearchParams({ db: "pubmed", id: ids.join(","), retmode: "json" });
  const result = (await (await fetch(esummary)).json())?.result || {};
  await sleep(350);

  let abstractsById = {};
  try {
    const efetch =
      "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?" +
      new URLSearchParams({ db: "pubmed", id: ids.join(","), rettype: "abstract", retmode: "xml" });
    const xml = await (await fetch(efetch)).text();
    abstractsById = parseAbstractsByPMID(xml);
    await sleep(350);
  } catch (e) {
    console.error(`efetch(${term}) failed, using summary fallback: ${e.message}`);
  }

  return ids
    .filter((id) => result[id])
    .map((id) => {
      const r = result[id];
      const abstract = abstractsById[id] || "";
      const body =
        firstSentences(abstract, 2, 320) ||
        `Published in ${r.source || "a journal"}${r.pubdate ? ` (${r.pubdate})` : ""}.`;
      const classText = `${r.title || ""} ${abstract}`;
      return {
        id: `pm-${id}`,
        headline: wordCap((r.title || "Study").replace(/\.$/, ""), HEADLINE_CAP),
        summary: body,
        teaser: teaserFrom(body),
        category: classify(classText, "journal"),
        compounds: extractCompounds(classText, fallbackName),
        sources: [
          { name: `PubMed (${id})`, url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`, kind: "journal" },
        ],
        publishedAt: toISO(r.sortpubdate) || toISO(r.pubdate) || ISO_NOW,
        disclaimer: DISCLAIMER,
      };
    });
}

// -------------------------------------------------------------------------------------
// Federal Register — real US regulatory documents (FDA rules & notices: approvals, compounding,
// advisory-committee actions, scheduling). Public API, no key. Feeds the Regulatory category.
// -------------------------------------------------------------------------------------
async function fromFederalRegister(term, fallbackName) {
  const params = new URLSearchParams({
    "conditions[term]": term,
    "conditions[agencies][]": "food-and-drug-administration",
    per_page: "3",
    order: "newest",
  });
  for (const f of ["title", "abstract", "html_url", "publication_date", "document_number", "type"]) {
    params.append("fields[]", f);
  }
  const res = await fetch(`https://www.federalregister.gov/api/v1/documents.json?${params}`, {
    headers: { accept: "application/json" },
  });
  if (!res.ok) throw new Error(`FR ${res.status}`);
  const json = await res.json();
  return (json.results || []).map((d) => {
    const body = firstSentences(clean(d.abstract || d.title || ""), 2, 320);
    const classText = `${d.title} ${d.abstract || ""} ${d.type || ""} federal register fda regulatory`;
    return {
      id: `fr-${d.document_number}`,
      headline: wordCap((d.title || "Regulatory notice").replace(/\.$/, ""), HEADLINE_CAP),
      summary: body || firstSentences(clean(d.title || ""), 1, 200),
      teaser: teaserFrom(body || d.title || ""),
      category: classify(classText, "regulatory"),
      compounds: extractCompounds(`${d.title || ""} ${d.abstract || ""}`, fallbackName),
      sources: [
        { name: `U.S. Federal Register (${d.type || "document"})`, url: d.html_url, kind: "regulatory" },
      ],
      publishedAt: toISO(d.publication_date) || ISO_NOW,
      disclaimer: DISCLAIMER,
    };
  });
}

// -------------------------------------------------------------------------------------
// Curated base — read the shipping sampleJSON straight from the Swift source (one truth).
// -------------------------------------------------------------------------------------
async function loadCuratedBase() {
  const swift = await readFile(CURATED_SWIFT, "utf8");
  const marker = swift.indexOf("sampleJSON");
  const start = swift.indexOf('#"""', marker);
  const end = swift.indexOf('"""#', start);
  if (start < 0 || end < 0) throw new Error("could not extract curated sampleJSON from NewsFeed.swift");
  const feed = JSON.parse(swift.slice(start + 4, end));
  return feed.items || [];
}

async function loadFreshTerms() {
  const cfg = JSON.parse(await readFile(COMPOUNDS_CONFIG, "utf8"));
  // One search term per active-news compound: first alias, tagged with the catalog name.
  return (cfg.focus || [])
    .filter((f) => (f.priority ?? 99) <= FRESH_PRIORITY_MAX)
    .map((f) => ({ term: f.aliases?.[0] || f.name, name: f.name }));
}

// -------------------------------------------------------------------------------------
// LLM rewrite (Claude Haiku) — turn raw clinical titles/abstracts into short, punchy,
// plain-language copy. Applied ONLY to fresh items. Accuracy-first: the model may use ONLY facts
// present in the source and must never invent results. Requires ANTHROPIC_API_KEY; without it, or
// on any per-item error, the item keeps its deterministic raw text (the build never fails here).
// Never touches compounds/sources/dates — only headline, teaser (key finding), and summary.
// -------------------------------------------------------------------------------------
const REWRITE_MODEL = process.env.NEWS_REWRITE_MODEL || "claude-haiku-4-5";
const REWRITE_SYSTEM = `You rewrite biomedical news items for PinWise, a peptide/GLP-1 dose-tracking app. Turn a raw clinical-trial or journal title and summary into clear, engaging, ACCURATE copy for an informed layperson.
Hard rules:
- Use ONLY facts present in the provided text. NEVER invent numbers, percentages, outcomes, drug names, approvals, dates, or any claim that is not there.
- If the source is a trial registration or has no results yet, describe what the study IS (its phase, population, and what it tests) — do NOT fabricate findings.
- Neutral and factual, not clickbait or hype. No medical advice, no recommendations, do not address the reader as "you".
- Plain language: explain or avoid jargon.
Return ONLY a JSON object (no prose, no code fences) with exactly these keys:
{"headline": string, aim for ~48 characters and NEVER exceed 56 — it must fit a phone news card on two short lines without being cut off; make it punchy, specific, and human (lead with the finding or subject, not "A study of…"); no trailing period;
 "keyFinding": string, ONE short sentence, 110 characters or fewer, the single most important takeaway in plain language;
 "summary": string, 2-4 sentences expanding on the findings or on what the study is}`;

async function rewriteOne(item, apiKey) {
  const prompt = `Category: ${item.category}
Compounds: ${item.compounds.join(", ") || "n/a"}
Raw headline: ${item.headline}
Raw summary: ${item.summary}`;
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model: REWRITE_MODEL,
      max_tokens: 400,
      temperature: 0.3,
      system: REWRITE_SYSTEM,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`anthropic ${res.status}`);
  const json = await res.json();
  const text = (json.content || []).map((b) => b.text || "").join("").trim();
  const a = text.indexOf("{"), b = text.lastIndexOf("}");
  if (a < 0 || b < 0) throw new Error("no JSON in response");
  const obj = JSON.parse(text.slice(a, b + 1));
  const headline = clean(obj.headline || "");
  const keyFinding = clean(obj.keyFinding || "");
  const summary = clean(obj.summary || "");
  if (!headline || !keyFinding || !summary) throw new Error("empty rewritten field");
  // Safety caps in case the model overruns: headline stays short; teaser MUST be <=110 chars or the
  // feed validator hard-fails and refuses to publish (wordCap returns the string unchanged when it's
  // already within the limit, so a well-behaved one-sentence finding is untouched).
  return {
    ...item,
    headline: wordCap(headline.replace(/\.$/, ""), HEADLINE_CAP),
    teaser: wordCap(keyFinding, 108),
    summary,
  };
}

async function rewriteFresh(items) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.warn("ANTHROPIC_API_KEY not set — skipping LLM rewrite; using raw extracted text.");
    return items;
  }
  const out = [];
  let ok = 0;
  for (const item of items) {
    try {
      out.push(await rewriteOne(item, apiKey));
      ok++;
    } catch (e) {
      console.error(`rewrite failed for ${item.id}, keeping raw: ${e.message}`);
      out.push(item);
    }
    await sleep(200); // gentle pacing; ~15 items/run
  }
  console.log(`LLM rewrite: ${ok}/${items.length} items rewritten (rest kept raw).`);
  return out;
}

async function main() {
  const curated = await loadCuratedBase();
  console.log(`Curated base: ${curated.length} items.`);

  // Dedupe keys drawn from the curated base: ids, and any NCT/PMID identifiers in source URLs.
  const seenIds = new Set(curated.map((it) => it.id));
  const seenRefs = new Set();
  for (const it of curated) {
    for (const s of it.sources || []) {
      const m = String(s.url).match(/(NCT\d{8})|pubmed\.ncbi\.nlm\.nih\.gov\/(\d+)/i);
      if (m) seenRefs.add((m[1] || m[2]).toUpperCase());
    }
  }
  const refOf = (it) => {
    for (const s of it.sources || []) {
      const m = String(s.url).match(/(NCT\d{8})|pubmed\.ncbi\.nlm\.nih\.gov\/(\d+)/i);
      if (m) return (m[1] || m[2]).toUpperCase();
    }
    return null;
  };

  const terms = await loadFreshTerms();
  const collected = [];
  for (const { term, name } of terms) {
    for (const fn of [fromClinicalTrials, fromPubMed, fromFederalRegister]) {
      try {
        collected.push(...(await fn(term, name)));
      } catch (e) {
        console.error(`skip ${fn.name}(${term}): ${e.message}`);
      }
    }
  }

  // Keep fresh items that are: parseable-dated, recent, and not already in the curated base.
  const freshSeen = new Set();
  const fresh = collected
    .filter((it) => it.headline && it.summary && it.summary.length >= MIN_SUMMARY)
    .filter((it) => {
      if (seenIds.has(it.id) || freshSeen.has(it.id)) return false;
      const ref = refOf(it);
      if (ref && seenRefs.has(ref)) return false; // same trial/paper as a curated item
      if (ageDays(it.publishedAt) > FRESH_MAX_AGE_DAYS) return false;
      freshSeen.add(it.id);
      if (ref) seenRefs.add(ref);
      return true;
    })
    .sort((a, b) => (a.publishedAt < b.publishedAt ? 1 : -1))
    .slice(0, MAX_FRESH)
    // Fresh items rank BELOW the curated hero (so the Top story stays curated) but their recent
    // dates float them to the top of the date-sorted "Latest" stream.
    .map((it, i) => ({ ...it, popularity: Math.max(20, 44 - i * 2), isMajorUpdate: false }));

  console.log(`Fresh items collected: ${fresh.length}.`);

  // Rewrite the fresh items into punchy, plain-language copy (the curated base is already
  // hand-written, so it's left untouched). Best-effort — falls back to raw text per item.
  const rewritten = await rewriteFresh(fresh);

  const items = [...curated, ...rewritten];
  const feed = { version: 1, generatedAt: ISO_NOW, items };
  await mkdir(resolve(REPO, "feed"), { recursive: true });
  await writeFile(resolve(REPO, "feed/feed.json"), JSON.stringify(feed, null, 2) + "\n");
  console.log(`Wrote feed/feed.json with ${items.length} items (${curated.length} curated + ${fresh.length} fresh).`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
