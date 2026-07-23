-- RAG knowledge base for the assistant (Natt). Stores vetted corpus chunks + their embeddings and
-- exposes a top-k semantic-search function. Embeddings are 384-dim (Supabase-native gte-small,
-- generated in the Edge Functions via Supabase.ai). Only the service-role Edge Functions touch this
-- table — there is no client RLS policy, so users can neither read nor write the corpus directly.

create extension if not exists vector;

create table if not exists public.kb_chunks (
    id         bigint generated always as identity primary key,
    source     text        not null,          -- corpus file / origin (e.g. "compounds:Retatrutide")
    title      text        not null,          -- short human label, shown to the model as the citation
    content    text        not null,          -- the chunk text that gets embedded + retrieved
    embedding  vector(384),                    -- gte-small; null until ingested
    metadata   jsonb       not null default '{}'::jsonb,   -- {category, needsReview, ...}
    created_at timestamptz not null default now()
);

alter table public.kb_chunks enable row level security;
-- Intentionally NO policy: only the service role (Edge Functions) may read/write. Clients can't
-- reach the corpus, so there's no way to scrape or tamper with it from the app.

-- Approximate-nearest-neighbor index for cosine similarity.
create index if not exists kb_chunks_embedding_idx
    on public.kb_chunks using hnsw (embedding vector_cosine_ops);

-- Top-k semantic search: returns chunks whose cosine similarity to the query embedding is at least
-- `min_similarity`, most-similar first. Called by the ai-chat Edge Function (service role).
create or replace function public.match_kb_chunks(
    query_embedding vector(384),
    match_count     int   default 5,
    min_similarity  float default 0.4
)
returns table (id bigint, source text, title text, content text, similarity float)
language sql
stable
security definer
set search_path = public, extensions
as $$
    select c.id, c.source, c.title, c.content,
           1 - (c.embedding <=> query_embedding) as similarity
    from public.kb_chunks c
    where c.embedding is not null
      and 1 - (c.embedding <=> query_embedding) >= min_similarity
    order by c.embedding <=> query_embedding
    limit greatest(match_count, 1);
$$;
