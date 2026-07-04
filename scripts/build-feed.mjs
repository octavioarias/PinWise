#!/usr/bin/env node
// Builds PinWise's News feed.json from public sources (ClinicalTrials.gov v2 + PubMed).
// Neutral, cited summaries only — no recommendations. Matches the NewsFeed contract in
// App/Sources/PeptideKit/News/NewsFeed.swift. Optional LLM rewrite is a documented next step;
// this version uses attributed, template summaries so it runs with zero API keys.
//
// Usage:  node scripts/build-feed.mjs   ->  writes feed/feed.json
import { mkdir, writeFile } from "node:fs/promises";

const COMPOUNDS = ["semaglutide", "tirzepatide", "retatrutide", "tesamorelin", "BPC-157"];
const DISCLAIMER =
  "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician.";
const cap = (s, n) => (s && s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s || "");
const iso = (d) => (/^\d{4}-\d{2}-\d{2}/.test(d || "") ? d : new Date().toISOString());

async function fromClinicalTrials(term) {
  const url =
    "https://clinicaltrials.gov/api/v2/studies?" +
    new URLSearchParams({ "query.term": term, pageSize: "3", sort: "LastUpdatePostDate:desc" });
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
    return {
      id: `ct-${nct}`,
      headline: cap(title, 90),
      summary: cap(
        `${phase ? phase.replace(/_/g, " ") + " " : ""}trial${conditions ? " for " + conditions : ""}. ` +
          `According to ClinicalTrials.gov, its status is ${status || "unknown"}${date ? `, last updated ${date}` : ""}.`,
        220
      ),
      category: "Trial results",
      compounds: [cap(term[0].toUpperCase() + term.slice(1), 40)],
      sources: [{ name: `ClinicalTrials.gov (${nct})`, url: `https://clinicaltrials.gov/study/${nct}`, kind: "trial" }],
      publishedAt: iso(date),
      disclaimer: DISCLAIMER,
    };
  });
}

async function fromPubMed(term) {
  const esearch =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" +
    new URLSearchParams({ db: "pubmed", term, retmode: "json", retmax: "2", sort: "date" });
  const ids = (await (await fetch(esearch)).json())?.esearchresult?.idlist || [];
  if (!ids.length) return [];
  const esummary =
    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?" +
    new URLSearchParams({ db: "pubmed", id: ids.join(","), retmode: "json" });
  const result = (await (await fetch(esummary)).json())?.result || {};
  return ids
    .filter((id) => result[id])
    .map((id) => {
      const r = result[id];
      return {
        id: `pm-${id}`,
        headline: cap(r.title?.replace(/\.$/, "") || "Study", 90),
        summary: cap(`Published in ${r.source || "a journal"}${r.pubdate ? ` (${r.pubdate})` : ""}. See the source for details.`, 200),
        category: "General",
        compounds: [cap(term[0].toUpperCase() + term.slice(1), 40)],
        sources: [{ name: `PubMed (${id})`, url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`, kind: "journal" }],
        publishedAt: iso(r.sortpubdate?.slice(0, 10)),
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
