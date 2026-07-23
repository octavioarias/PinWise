// Ingest the vetted corpus into kb_chunks with gte-small embeddings. Admin-only, idempotent
// (clears + reinserts). Run after any corpus change:
//   curl -X POST "https://<ref>.supabase.co/functions/v1/kb-ingest" \
//        -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
// The corpus JSON is bundled via imports, so no separate upload step.
import { createClient } from "jsr:@supabase/supabase-js@2";
import compounds from "../../kb/compounds.json" with { type: "json" };
import docs from "../../kb/docs.json" with { type: "json" };

// `Supabase.ai` is injected by the Edge runtime (on-device gte-small embeddings; no external key).
declare const Supabase: {
  ai: { Session: new (model: string) => { run(input: string, opts?: Record<string, unknown>): Promise<number[]> } };
};

interface Chunk { source: string; title: string; content: string; metadata: Record<string, unknown>; }

function buildChunks(): Chunk[] {
  const out: Chunk[] = [];
  for (const c of compounds as Array<Record<string, any>>) {
    const half = c.halfLifeHours != null ? ` Half-life about ${c.halfLifeHours} hours.` : "";
    const wada = c.wadaProhibited ? " WADA-prohibited." : "";
    const aliases = Array.isArray(c.aliases) && c.aliases.length ? ` (also known as: ${c.aliases.join(", ")})` : "";
    out.push({
      source: `compound:${c.name}`,
      title: c.name,
      content: `${c.name}${aliases}. Category: ${c.category}. Regulatory status: ${c.regulatory}. Evidence: ${c.evidence}.${half}${wada} ${c.notes}`,
      metadata: { category: "compound" },
    });
  }
  for (const d of docs as Array<Record<string, any>>) {
    out.push({
      source: `doc:${d.title}`,
      title: d.title,
      content: `${d.title}. ${d.content}`,
      metadata: { category: d.category, needsReview: !!d.needsReview },
    });
  }
  return out;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

  // Admin gate. Primary path: a dedicated KB_INGEST_TOKEN passed in a custom `x-kb-admin` header —
  // kept OFF the Authorization header on purpose, so it never collides with the platform gateway's
  // own apikey/JWT validation (the gateway rejects non-JWT bearers before our code even runs, and the
  // injected service-role key isn't reliably equal to any key the CLI can hand us once keys rotate).
  // Fallback path: the legacy service-role bearer, for backward compat with older invocations.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminToken = Deno.env.get("KB_INGEST_TOKEN") ?? "";
  const viaToken = adminToken.length > 0 && req.headers.get("x-kb-admin") === adminToken;
  const viaBearer = (req.headers.get("Authorization") ?? "") === `Bearer ${serviceKey}`;
  if (!viaToken && !viaBearer) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey, { auth: { persistSession: false } });
  const model = new Supabase.ai.Session("gte-small");

  // Batched to stay under the edge worker's compute ceiling: embedding the whole corpus + a bulk
  // insert in one invocation trips WORKER_RESOURCE_LIMIT on smaller instances. Each call handles a
  // slice [start, start+count); the caller loops until `done`. start===0 clears the table first, so
  // the full loop is still an idempotent refresh.
  const url = new URL(req.url);
  const start = Math.max(0, parseInt(url.searchParams.get("start") ?? "0", 10) || 0);
  const count = Math.max(1, parseInt(url.searchParams.get("count") ?? "8", 10) || 8);
  try {
    const chunks = buildChunks();
    const total = chunks.length;
    const slice = chunks.slice(start, start + count);
    const rows = [];
    for (const ch of slice) {
      const embedding = await model.run(ch.content, { mean_pool: true, normalize: true });
      // pgvector's text input format is "[a,b,c]" — JSON.stringify of the array matches it exactly,
      // which PostgREST casts to vector reliably (passing a raw array can be read as a PG array).
      rows.push({ ...ch, embedding: JSON.stringify(embedding) });
    }
    // Idempotent full refresh: clear only on the first slice, then append each slice.
    if (start === 0) await supabase.from("kb_chunks").delete().neq("id", 0);
    if (rows.length) {
      const { error } = await supabase.from("kb_chunks").insert(rows);
      if (error) return json({ error: error.message }, 500);
    }
    const to = start + slice.length;
    return json({ ingested: rows.length, from: start, to, total, done: to >= total });
  } catch (e) {
    return json({ error: String(e).slice(0, 500) }, 500);
  }
});
