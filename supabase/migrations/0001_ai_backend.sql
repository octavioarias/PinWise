-- PinWise hosted-AI backend: per-user tier + daily usage quota.
--
-- Design notes:
--  * `profiles.tier` is SERVER-CONTROLLED. Clients can read their own row but never write it —
--    the tier is set to 'pro' later by the StoreKit → App Store Server Notifications webhook.
--  * `ai_usage` is written ONLY by the Edge Function using the service-role key (which bypasses
--    RLS). No client-writable policy exists, so a user can't fake their remaining quota.
--  * A profile row is auto-created for every new auth user (including anonymous/guest sessions),
--    so the Edge Function can always look up a tier.

-- ---------------------------------------------------------------------------
-- profiles: one row per auth user, holding the entitlement tier.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
    id         uuid primary key references auth.users (id) on delete cascade,
    tier       text        not null default 'free' check (tier in ('free', 'trial', 'pro')),
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A user may read (only) their own profile. No insert/update/delete policy ⇒ clients can't change
-- their tier; the service role (Edge Function / webhook) bypasses RLS to manage it.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
    on public.profiles for select
    using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- ai_usage: per-user, per-day tally used to enforce the quota.
-- ---------------------------------------------------------------------------
create table if not exists public.ai_usage (
    user_id       uuid        not null references auth.users (id) on delete cascade,
    usage_date    date        not null default (now() at time zone 'utc')::date,
    message_count integer     not null default 0,
    token_count   bigint      not null default 0,
    primary key (user_id, usage_date)
);

alter table public.ai_usage enable row level security;

-- A user may read their own usage (so the app can show "N left today"). No client write policy —
-- only the Edge Function (service role) increments it.
drop policy if exists "ai_usage_select_own" on public.ai_usage;
create policy "ai_usage_select_own"
    on public.ai_usage for select
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Auto-create a profile whenever a new auth user (real or anonymous) is created.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Atomic usage increment, callable by the Edge Function (service role). Keeps the read-check-write
-- race out of the function: one statement upserts today's row and bumps the counters.
-- ---------------------------------------------------------------------------
create or replace function public.increment_ai_usage(
    p_user_id uuid,
    p_tokens  bigint
)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.ai_usage (user_id, usage_date, message_count, token_count)
    values (p_user_id, (now() at time zone 'utc')::date, 1, greatest(p_tokens, 0))
    on conflict (user_id, usage_date) do update
        set message_count = public.ai_usage.message_count + 1,
            token_count   = public.ai_usage.token_count + greatest(p_tokens, 0);
$$;
