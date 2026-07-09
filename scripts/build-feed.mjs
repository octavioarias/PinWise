#!/usr/bin/env node
// Builds PinWise's News feed.json from public sources (ClinicalTrials.gov v2 + PubMed).
// Neutral, cited summaries only — no recommendations. Matches the NewsFeed contract in
// App/Sources/PeptideKit/News/NewsFeed.swift. Fully deterministic: no API keys, no LLM.
// Summaries are built from real source text (ClinicalTrials briefSummary + primary outcome,
// PubMed abstracts via a batched efetch) with graceful template fallbacks when a source
// omits the field, so no item is ever contentless.
//
// Usage:  node scripts/build-feed.mjs   ->  writes feed/feed.json
import { mkdir, writeFile } from "node:fs/promises";

const COMPOUNDS = ["semaglutide", "tirzepatide", "retatrutide", "tesamorelin", "BPC-157"];
const DISCLAIMER =
  "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician.";

// -------------------------------------------------------------------------------------
// Text helpers — sentence/word-boundary aware (replaces the old mid-word `cap`).
// -------------------------------------------------------------------------------------
const clean = (s) =>
  (s || "")
    .replace(/<[^>]+>/g, " ") // strip HTML/XML tags
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();

// Word-boundary cap with an ellipsis; never cuts mid-word.
function wordCap(s, n) {
  s = clean(s);
  if (s.length <= n) return s;
  const cut = s.slice(0, n);
  const sp = cut.lastIndexOf(" ");
  return (sp > 0 ? cut.slice(0, sp) : cut).replace(/[\s.,;:]+$/, "") + "…";
}

// Take the first `maxSentences` sentences, staying under `maxChars`, on sentence boundaries.
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

// ≤100-char scannable teaser from a body of text.
const teaserFrom = (body) => wordCap(firstSentences(body, 1, 100), 100);

const cap1 = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

// -------------------------------------------------------------------------------------
// Date normalization (L) — PubMed sortpubdate "YYYY/MM/DD", ClinicalTrials "YYYY-MM-DD".
// Returns a real ISO instant or null (callers fall back to now() only as a last resort).
// -------------------------------------------------------------------------------------
function toISO(raw) {
  const m = String(raw || "").match(/(\d{4})[-/](\d{2})[-/](\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}T00:00:00Z` : null;
}

// -------------------------------------------------------------------------------------
// Deterministic category classification (K) — first match wins.
// Result is always one of the NewsCategory raw strings the Swift decoder accepts.
// -------------------------------------------------------------------------------------
function classify(text, sourceKind) {
  const t = (text || "").toLowerCase();
  // Safety: high-precision safety-news signals only. Deliberately EXCLUDES bare "adverse"/
  // "death" — those are routine efficacy endpoints (MACE, cardiovascular death) and were
  // mislabeling ordinary trials as safety alerts.
  if (
    /\b(recall\w*|boxed warning|black[- ]box|contaminat\w*|counterfeit\w*|adulterat\w*|overdose\w*|poisoning|fatalit\w*|safety alert|safety signal|serious safety|life-threatening|withdrawn from (the )?market|unregulated (peptide|compound|drug)|performance-enhancing)\b/.test(
      t
    )
  )
    return "Safety";
  // Regulatory: name a regulator or a concrete regulatory action, not just "approved comparator".
  if (
    /\b(fda|ema|mhra|503a|503b|compounding pharmac\w*|marketing auth\w*|granted approval|newly approved|drug approval|regulatory action|import alert)\b/.test(
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
// Compound extraction (K) — known names + aliases, hyphen-tolerant word-boundary scan.
// -------------------------------------------------------------------------------------
const KNOWN = {
  Semaglutide: ["semaglutide", "ozempic", "wegovy", "rybelsus"],
  Tirzepatide: ["tirzepatide", "mounjaro", "zepbound", "ly3298176"],
  Retatrutide: ["retatrutide", "ly3437943"],
  Tesamorelin: ["tesamorelin", "egrifta"],
  "BPC-157": ["bpc-157", "bpc157", "bpc 157"],
  Bimagrumab: ["bimagrumab"],
  Dulaglutide: ["dulaglutide", "trulicity"],
  Liraglutide: ["liraglutide", "victoza", "saxenda"],
  Cagrilintide: ["cagrilintide"],
  Survodutide: ["survodutide"],
  Orforglipron: ["orforglipron"],
  Mazdutide: ["mazdutide"],
  Exenatide: ["exenatide", "byetta", "bydureon"],
};

function extractCompounds(text, fallbackTerm) {
  const t = (text || "").toLowerCase();
  const hits = [];
  for (const [name, aliases] of Object.entries(KNOWN)) {
    const matched = aliases.some((a) => {
      // aliases are plain lowercase names; only hyphens/spaces vary in the wild.
      const pat = a.replace(/[-\s]/g, "[-\\s]?");
      return new RegExp(`(^|[^a-z0-9])${pat}([^a-z0-9]|$)`).test(t);
    });
    if (matched) hits.push(name);
  }
  return hits.length ? [...new Set(hits)] : [cap1(fallbackTerm)];
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// -------------------------------------------------------------------------------------
// ClinicalTrials.gov v2 (I) — request description + outcomes so summaries carry real text.
// -------------------------------------------------------------------------------------
async function fromClinicalTrials(term) {
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
        "protocolSection.armsInterventionsModule",
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
    // Template fallback when the description module is absent.
    const context =
      `${phase ? phase.replace(/_/g, " ") + " " : ""}` +
      `${conditions ? "trial in " + conditions + ". " : "trial. "}` +
      `According to ClinicalTrials.gov, its status is ${status || "unknown"}${date ? `, last updated ${date}` : ""}.`;
    const lede = firstSentences(brief || context, 2, 320);
    const body = lede + (outcome ? ` Primary outcome: ${wordCap(outcome, 120)}.` : "");
    const classText = `${title} ${brief} ${outcome} ${phase} ${conditions} ${status}`;
    return {
      id: `ct-${nct}`,
      headline: (title || "Clinical trial").replace(/\.$/, ""),
      summary: body,
      teaser: teaserFrom(body),
      category: classify(classText, "trial"),
      compounds: extractCompounds(`${title} ${brief}`, term),
      sources: [
        { name: `ClinicalTrials.gov (${nct})`, url: `https://clinicaltrials.gov/study/${nct}`, kind: "trial" },
      ],
      publishedAt: toISO(date) || new Date().toISOString(),
      disclaimer: DISCLAIMER,
    };
  });
}

// -------------------------------------------------------------------------------------
// PubMed (I) — esearch -> esummary -> one BATCHED efetch for abstracts (throttled).
// -------------------------------------------------------------------------------------
function parseAbstractsByPMID(xml) {
  const byId = {};
  // Split into per-article blocks so AbstractText is attributed to the right PMID.
  const articles = xml.match(/<PubmedArticle\b[\s\S]*?<\/PubmedArticle>/g) || [];
  for (const art of articles) {
    const pmid = (art.match(/<PMID[^>]*>(\d+)<\/PMID>/) || [])[1];
    if (!pmid) continue;
    // Concatenate all AbstractText segments in document order (may be labeled parts).
    const segs = [...art.matchAll(/<AbstractText\b[^>]*>([\s\S]*?)<\/AbstractText>/g)].map((m) =>
      clean(m[1])
    );
    const abstract = segs.filter(Boolean).join(" ").trim();
    if (abstract) byId[pmid] = abstract;
  }
  return byId;
}

async function fromPubMed(term) {
  const esearch =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" +
    new URLSearchParams({ db: "pubmed", term, retmode: "json", retmax: "2", sort: "date" });
  const ids = (await (await fetch(esearch)).json())?.esearchresult?.idlist || [];
  if (!ids.length) return [];
  await sleep(350); // polite throttle (~3 req/s, no API key)

  const esummary =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?" +
    new URLSearchParams({ db: "pubmed", id: ids.join(","), retmode: "json" });
  const result = (await (await fetch(esummary)).json())?.result || {};
  await sleep(350);

  // One batched efetch for all abstracts in this term's result set.
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
        headline: (r.title || "Study").replace(/\.$/, ""),
        summary: body,
        teaser: teaserFrom(body),
        category: classify(classText, "journal"),
        compounds: extractCompounds(classText, term),
        sources: [
          { name: `PubMed (${id})`, url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`, kind: "journal" },
        ],
        publishedAt: toISO(r.sortpubdate) || toISO(r.pubdate) || new Date().toISOString(),
        disclaimer: DISCLAIMER,
      };
    });
}

async function main() {
  const collected = [];
  for (const term of COMPOUNDS) {
    for (const fn of [fromClinicalTrials, fromPubMed]) {
      try {
        collected.push(...(await fn(term)));
      } catch (e) {
        console.error(`skip ${fn.name}(${term}): ${e.message}`);
      }
    }
  }
  // Dedupe by id, sort newest first, rank popularity, flag the top items as major.
  const seen = new Set();
  const items = collected
    .filter((it) => it.headline && (seen.has(it.id) ? false : seen.add(it.id)))
    .sort((a, b) => (a.publishedAt < b.publishedAt ? 1 : -1))
    .slice(0, 14)
    .map((it, i) => ({ ...it, popularity: Math.max(20, 100 - i * 5), isMajorUpdate: i < 2 }));

  const feed = { version: 1, generatedAt: new Date().toISOString(), items };
  await mkdir("feed", { recursive: true });
  await writeFile("feed/feed.json", JSON.stringify(feed, null, 2) + "\n");
  console.log(`Wrote feed/feed.json with ${items.length} items.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
