import Foundation

// The News feature's data contract. The app and the backend agree ONLY on this shape:
// a backend pipeline publishes a `feed.json` matching `NewsFeed`; the app fetches and
// renders it. Editorial rules (enforced in review + testable here): every item is a
// NEUTRAL summary, carries at least one source citation, and carries a disclaimer.
// The app never editorializes or recommends — it informs and links out.

public enum NewsCategory: String, Codable, CaseIterable, Sendable {
    case trialResults = "Trial results"
    case regulatory = "Regulatory"
    case safety = "Safety"
    case newCompound = "New compound"
    case guidance = "Guidance"
    case general = "General"
}

/// A citation backing a news item — the transparency guarantee.
public struct NewsSource: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case trial, journal, preprint, regulatory, news
    }
    public var name: String
    public var url: String
    public var kind: Kind
    public var id: String { url }

    public init(name: String, url: String, kind: Kind) {
        self.name = name
        self.url = url
        self.kind = kind
    }
}

/// One curated feed item — a neutral, cited, dated summary.
public struct NewsItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var headline: String
    public var summary: String
    public var category: NewsCategory
    /// Compounds referenced, for per-compound filtering (e.g. "Retatrutide").
    public var compounds: [String]
    public var sources: [NewsSource]
    /// ISO-8601 timestamp (kept as String to stay portable/Codable without date strategies).
    public var publishedAt: String
    /// Editorial ranking score for the "Popular / Trending" view.
    public var popularity: Int
    /// Drives an opt-in push and a badge (major trial/regulatory/safety events).
    public var isMajorUpdate: Bool
    /// Per-item disclaimer, shown on every card and detail view.
    public var disclaimer: String
    /// Optional lead-image URL the pipeline attaches (e.g. an Open Graph image). Rendered as
    /// an Apple-News-style thumbnail; the card falls back to a branded gradient when nil.
    public var imageURL: String?
    /// Short scannable teaser (≤~100 chars) for list cards; falls back to `summary` when nil.
    public var teaser: String?

    public init(
        id: String, headline: String, summary: String, category: NewsCategory,
        compounds: [String], sources: [NewsSource], publishedAt: String,
        popularity: Int, isMajorUpdate: Bool, disclaimer: String,
        imageURL: String? = nil, teaser: String? = nil
    ) {
        self.id = id; self.headline = headline; self.summary = summary; self.category = category
        self.compounds = compounds; self.sources = sources; self.publishedAt = publishedAt
        self.popularity = popularity; self.isMajorUpdate = isMajorUpdate; self.disclaimer = disclaimer
        self.imageURL = imageURL; self.teaser = teaser
    }

    /// Text for list/summary contexts: the teaser when present, else the full summary.
    public var listText: String { teaser ?? summary }
}

/// The published feed document the app fetches.
public struct NewsFeed: Codable, Hashable, Sendable {
    public var version: Int
    public var generatedAt: String
    public var items: [NewsItem]

    public init(version: Int, generatedAt: String, items: [NewsItem]) {
        self.version = version; self.generatedAt = generatedAt; self.items = items
    }

    /// "Popular" view — items ranked by editorial score, high to low.
    public var trending: [NewsItem] { items.sorted { $0.popularity > $1.popularity } }

    /// Items mentioning a given compound (for the per-compound news filter).
    public func items(mentioning compound: String) -> [NewsItem] {
        items.filter { $0.compounds.contains(compound) }
    }

    /// Major updates only (push / badges).
    public var majorUpdates: [NewsItem] { items.filter(\.isMajorUpdate) }
}

public extension NewsFeed {
    /// A realistic seed feed — bundled for previews/offline first-launch and used as the
    /// decode fixture that validates the contract. Content mirrors the verified research.
    static let sampleJSON: String = #"""
    {
      "version": 1,
      "generatedAt": "2026-07-04T12:00:00Z",
      "items": [
        {
          "id": "reta-triumph1-2026-05",
          "headline": "Retatrutide clears Phase 3 in obesity",
          "summary": "Eli Lilly reported positive Phase 3 (TRIUMPH-1) topline results for retatrutide in obesity in May 2026. Retatrutide is investigational and not FDA-approved. Phase 2 dosing (1/4/8/12 mg weekly) was published in NEJM (2023).",
          "category": "Trial results",
          "compounds": ["Retatrutide"],
          "sources": [
            {"name": "ClinicalTrials.gov (Phase 2, NCT04881760)", "url": "https://clinicaltrials.gov/study/NCT04881760", "kind": "trial"},
            {"name": "NEJM 2023", "url": "https://www.nejm.org/", "kind": "journal"}
          ],
          "publishedAt": "2026-05-21T00:00:00Z",
          "imageURL": "https://example.com/retatrutide.jpg",
          "teaser": "Eli Lilly's retatrutide hit its Phase 3 obesity endpoints (TRIUMPH-1). Still investigational.",
          "popularity": 95,
          "isMajorUpdate": true,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "fda-503b-bulks-2026-04",
          "headline": "FDA moves to curb compounded GLP-1s",
          "summary": "On April 30, 2026 the FDA proposed keeping semaglutide, tirzepatide, and liraglutide off the 503B bulk drug substances list — a pending proposal, not a final ban. Shortage-based compounding enforcement discretion ended in 2025.",
          "category": "Regulatory",
          "compounds": ["Semaglutide", "Tirzepatide"],
          "sources": [
            {"name": "U.S. FDA", "url": "https://www.fda.gov/", "kind": "regulatory"}
          ],
          "publishedAt": "2026-04-30T00:00:00Z",
          "popularity": 88,
          "isMajorUpdate": true,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "compounded-glp1-units-safety",
          "headline": "FDA warns of compounded GLP-1 dosing errors",
          "summary": "The FDA has warned that non-standardized compounded GLP-1 concentrations have led to dosing errors, with some patients self-administering 5–20x the intended dose when dosing by 'units.' Always confirm the mg/mL concentration on the label.",
          "category": "Safety",
          "compounds": ["Semaglutide", "Tirzepatide"],
          "sources": [
            {"name": "U.S. FDA alert", "url": "https://www.fda.gov/", "kind": "regulatory"}
          ],
          "publishedAt": "2026-02-15T00:00:00Z",
          "popularity": 72,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "bpc157-review-2026",
          "headline": "BPC-157's human evidence stays thin",
          "summary": "A 2026 narrative review (Pharmaceutics) summarized BPC-157's biopharmaceutical challenges and translational barriers. Human evidence remains limited — no completed Phase II trial and fewer than 30 subjects across uncontrolled studies. BPC-157 is not FDA-approved.",
          "category": "General",
          "compounds": ["BPC-157"],
          "sources": [
            {"name": "Pharmaceutics 2026 (MDPI 18(5):625)", "url": "https://www.mdpi.com/1999-4923/18/5/625", "kind": "journal"}
          ],
          "publishedAt": "2026-03-10T00:00:00Z",
          "popularity": 60,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "reta-phase2-obesity-2023",
          "headline": "Retatrutide drove ~24% weight loss in Phase 2",
          "summary": "In a Phase 2 obesity trial (NEJM 2023), retatrutide produced dose-dependent weight loss up to about 24% at 48 weeks (12 mg weekly), with improvements in blood sugar and blood pressure. Retatrutide is investigational and not FDA-approved; nausea and other GI effects were the most common side effects.",
          "category": "Trial results",
          "compounds": ["Retatrutide"],
          "sources": [
            {"name": "NEJM 2023 (Phase 2)", "url": "https://www.nejm.org/doi/full/10.1056/NEJMoa2301972", "kind": "journal"},
            {"name": "ClinicalTrials.gov NCT04881760", "url": "https://clinicaltrials.gov/study/NCT04881760", "kind": "trial"}
          ],
          "publishedAt": "2026-06-20T00:00:00Z",
          "popularity": 92,
          "isMajorUpdate": true,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "reta-prediabetes-reversion-2026",
          "headline": "Retatrutide reversed prediabetes for most in Phase 2",
          "summary": "In the Phase 2 obesity trial (NEJM 2023), most participants who had prediabetes at baseline returned to normal blood sugar by 48 weeks on retatrutide — a large absolute improvement over placebo, where far fewer normalized. Retatrutide is investigational and not FDA-approved; these are secondary glycemic findings, and formal diabetes-prevention outcomes await the Phase 3 (TRIUMPH) program.",
          "category": "Trial results",
          "compounds": ["Retatrutide"],
          "sources": [
            {"name": "NEJM 2023 (Phase 2)", "url": "https://www.nejm.org/doi/full/10.1056/NEJMoa2301972", "kind": "journal"},
            {"name": "ClinicalTrials.gov NCT04881760", "url": "https://clinicaltrials.gov/study/NCT04881760", "kind": "trial"}
          ],
          "publishedAt": "2026-06-25T00:00:00Z",
          "popularity": 90,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "reta-liver-fat-2024",
          "headline": "Retatrutide cut liver fat in early data",
          "summary": "A Phase 2 sub-study reported large reductions in liver fat in people with metabolic dysfunction-associated steatotic liver disease (MASLD). Findings are early and investigational; retatrutide is not approved for any use.",
          "category": "Trial results",
          "compounds": ["Retatrutide"],
          "sources": [
            {"name": "The Lancet 2024", "url": "https://www.thelancet.com/", "kind": "journal"}
          ],
          "publishedAt": "2026-06-05T00:00:00Z",
          "popularity": 78,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "sema-select-cv-2024",
          "headline": "Wegovy label adds heart-risk benefit",
          "summary": "After the SELECT trial showed roughly a 20% reduction in major cardiovascular events in adults with obesity and established cardiovascular disease, the Wegovy label was updated to include cardiovascular risk reduction. Applies to the FDA-approved product, not compounded versions.",
          "category": "Regulatory",
          "compounds": ["Semaglutide"],
          "sources": [
            {"name": "U.S. FDA", "url": "https://www.fda.gov/", "kind": "regulatory"},
            {"name": "NEJM (SELECT)", "url": "https://www.nejm.org/", "kind": "journal"}
          ],
          "publishedAt": "2026-05-10T00:00:00Z",
          "popularity": 80,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "tirz-osa-approval",
          "headline": "Zepbound approved for sleep apnea",
          "summary": "The FDA approved tirzepatide for moderate-to-severe obstructive sleep apnea in adults with obesity, based on trials showing a reduced apnea-hypopnea index alongside weight loss. A labeled indication for the approved product.",
          "category": "Regulatory",
          "compounds": ["Tirzepatide"],
          "sources": [
            {"name": "U.S. FDA", "url": "https://www.fda.gov/", "kind": "regulatory"}
          ],
          "publishedAt": "2026-04-15T00:00:00Z",
          "popularity": 74,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "glp1-lean-mass-2026",
          "headline": "GLP-1 weight loss comes with muscle loss",
          "summary": "Reviews note that a meaningful share of weight lost on GLP-1 medicines is lean mass, not just fat. Adequate protein and resistance training are commonly discussed to help preserve muscle. General context, not a dosing recommendation.",
          "category": "Guidance",
          "compounds": ["Semaglutide", "Tirzepatide", "Retatrutide"],
          "sources": [
            {"name": "Lancet Diabetes & Endocrinology", "url": "https://www.thelancet.com/journals/landia/home", "kind": "journal"}
          ],
          "publishedAt": "2026-03-25T00:00:00Z",
          "popularity": 66,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "tesamorelin-visceral-fat",
          "headline": "Tesamorelin, an approved GHRH analog, cut visceral fat",
          "summary": "Tesamorelin (Egrifta) is FDA-approved for excess visceral abdominal fat in people with HIV. Phase 3 trials showed meaningful reductions in visceral fat over about six months (NEJM 2007), and later research reported reduced liver fat (JAMA 2014). It works by raising the body's own growth hormone; uses outside HIV-associated lipodystrophy are off-label or investigational.",
          "category": "Trial results",
          "compounds": ["Tesamorelin"],
          "sources": [
            {"name": "NEJM 2007 (Falutz, tesamorelin)", "url": "https://www.nejm.org/doi/full/10.1056/NEJMoa072375", "kind": "journal"},
            {"name": "JAMA 2014 (Stanley, liver fat)", "url": "https://pubmed.ncbi.nlm.nih.gov/25038357/", "kind": "journal"},
            {"name": "U.S. FDA — Egrifta", "url": "https://www.fda.gov/", "kind": "regulatory"}
          ],
          "publishedAt": "2026-06-12T00:00:00Z",
          "popularity": 68,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "cjc1295-ipamorelin-evidence",
          "headline": "CJC-1295 raised IGF-1 in an early trial; data stay thin",
          "summary": "CJC-1295, a long-acting GHRH analog, increased growth hormone and IGF-1 for several days in a small early human study (JCEM 2006). Ipamorelin, the selective GH secretagogue it is often paired with, has limited published human data and was investigated for other uses without approval. Neither is FDA-approved, and evidence for body-composition or anti-aging claims remains sparse.",
          "category": "General",
          "compounds": ["CJC-1295 (no DAC)", "CJC-1295 (DAC)", "Ipamorelin", "Sermorelin"],
          "sources": [
            {"name": "JCEM 2006 (Teichman, CJC-1295)", "url": "https://academic.oup.com/jcem/article-abstract/91/3/799/2843281", "kind": "journal"}
          ],
          "publishedAt": "2026-05-30T00:00:00Z",
          "popularity": 58,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "healing-blends-evidence",
          "headline": "Healing blends (Wolverine, GLOW) lack human trials",
          "summary": "Popular recovery blends — Wolverine (BPC-157 + TB-500) and GLOW (which adds GHK-Cu) — have no clinical trials of the combinations themselves. The individual components are mostly preclinical: BPC-157's human data are minimal, TB-500 (thymosin beta-4) is largely animal-stage, and GHK-Cu is best studied as a topical cosmetic ingredient. None are FDA-approved, and the benefits and risks of injecting these blends are not established.",
          "category": "General",
          "compounds": ["BPC-157", "TB-500", "GHK-Cu (injectable)", "KPV", "Thymosin Beta-4"],
          "sources": [
            {"name": "Pharmaceutics 2026 (MDPI 18(5):625)", "url": "https://www.mdpi.com/1999-4923/18/5/625", "kind": "journal"},
            {"name": "GHK-Cu review (Pickart, Int. J. Mol. Sci.)", "url": "https://pubmed.ncbi.nlm.nih.gov/29986520/", "kind": "journal"}
          ],
          "publishedAt": "2026-05-18T00:00:00Z",
          "popularity": 62,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        },
        {
          "id": "cagrisema-phase3",
          "headline": "CagriSema posts Phase 3 weight-loss results",
          "summary": "The amylin analog cagrilintide combined with semaglutide (CagriSema) reported Phase 3 weight-loss results. Both are dosed weekly; cagrilintide is investigational and CagriSema is not FDA-approved.",
          "category": "Trial results",
          "compounds": ["Cagrilintide", "Semaglutide"],
          "sources": [
            {"name": "ClinicalTrials.gov", "url": "https://clinicaltrials.gov/", "kind": "trial"}
          ],
          "publishedAt": "2026-05-28T00:00:00Z",
          "popularity": 70,
          "isMajorUpdate": false,
          "disclaimer": "Neutral informational summary. Not medical advice. Read the linked sources and consult a clinician."
        }
      ]
    }
    """#

    /// Decodes the bundled sample feed. Throws if the fixture ever drifts from the model.
    static func decodeSample() throws -> NewsFeed {
        try JSONDecoder().decode(NewsFeed.self, from: Data(sampleJSON.utf8))
    }
}
