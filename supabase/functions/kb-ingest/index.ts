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

  // Admin gate: require the service-role key as the bearer (only the operator has it).
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if ((req.headers.get("Authorization") ?? "") !== `Bearer ${serviceKey}`) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey, { auth: { persistSession: false } });
  const model = new Supabase.ai.Session("gte-small");

  try {
    const chunks = buildChunks();
    const rows = [];
    for (const ch of chunks) {
      const embedding = await model.run(ch.content, { mean_pool: true, normalize: true });
      // pgvector's text input format is "[a,b,c]" — JSON.stringify of the array matches it exactly,
      // which PostgREST casts to vector reliably (passing a raw array can be read as a PG array).
      rows.push({ ...ch, embedding: JSON.stringify(embedding) });
    }
    // Idempotent full refresh.
    await supabase.from("kb_chunks").delete().neq("id", 0);
    const { error } = await supabase.from("kb_chunks").insert(rows);
    if (error) return json({ error: error.message }, 500);
    return json({ ingested: rows.length });
  } catch (e) {
    return json({ error: String(e).slice(0, 500) }, 500);
  }
});
