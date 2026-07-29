-- ============================================================================
-- OFFINGCUE FOUNDATION 0004 — source registry, rights gate, ingest skeleton
--
-- Laws encoded:
--   * No source adapter without documented rights, health checks, and a kill
--     switch: source_rights.enabled has a CHECK against rights_status, and a
--     trigger blocks adapter-origin rows for disabled sources.
--   * Normalized facts only — source_facts carries structured payloads,
--     response hashes, source URL and timestamps. Never source prose/images.
--   * Manual fallback is a first-class path (entry_kind = 'manual').
--   * Data always shows its source and timestamp: public rows carry
--     source_id + fetched_at.
-- NOTE: no adapters are built or scheduled here. Schema only.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Public source directory (safe columns only)
-- ---------------------------------------------------------------------------
create table public.sources (
  id               bigint generated always as identity primary key,
  slug             text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  name             text not null,
  kind             public.source_kind not null,
  url              text,
  publisher        text,       -- credited publisher when it differs from the site
  attribution_text text,
  trust_tier       smallint not null default 3 check (trust_tier between 1 and 5),
  created_at       timestamptz not null default now()
);

alter table public.sources enable row level security;
revoke all on table public.sources from public;
revoke all on table public.sources from anon, authenticated;
grant select on table public.sources to anon, authenticated;
grant insert, update on table public.sources to authenticated;
grant select, insert, update, delete on table public.sources to service_role;

create policy sources_select_all on public.sources
  for select to anon, authenticated using (true);
create policy sources_insert_operator on public.sources
  for insert to authenticated with check (app.is_operator());
create policy sources_update_operator on public.sources
  for update to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Rights registry + kill switch (operator-only)
-- ---------------------------------------------------------------------------
create table public.source_rights (
  source_id       bigint primary key references public.sources (id) on delete cascade,
  rights_status   public.rights_status not null default 'unknown',
  rights_evidence text,        -- where the permission/terms are documented
  enabled         boolean not null default false,
  kill_note       text,        -- why the switch was thrown, when applicable
  updated_by      uuid references auth.users (id),
  updated_at      timestamptz not null default now(),
  constraint source_enable_requires_rights check (
    not enabled or rights_status in ('permitted', 'not_required')
  )
);

alter table public.source_rights enable row level security;
revoke all on table public.source_rights from public;
revoke all on table public.source_rights from anon, authenticated;
grant select, insert, update on table public.source_rights to authenticated;
grant select, insert, update, delete on table public.source_rights to service_role;

create policy source_rights_operator on public.source_rights
  for all to authenticated using (app.is_operator()) with check (app.is_operator());

create trigger source_rights_touch
  before update on public.source_rights
  for each row execute function app.touch_updated_at();

create or replace function app.source_is_enabled(p_source bigint)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select sr.enabled from public.source_rights sr where sr.source_id = p_source),
    false
  );
$$;
revoke execute on function app.source_is_enabled(bigint) from public;
grant execute on function app.source_is_enabled(bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Run log + health (operator-only)
-- ---------------------------------------------------------------------------
create table public.source_runs (
  id              bigint generated always as identity primary key,
  source_id       bigint not null references public.sources (id) on delete cascade,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  status          public.run_status,
  http_status     integer,
  response_hash   text,
  facts_extracted integer,
  error           text,
  created_at      timestamptz not null default now()
);

create index source_runs_source_idx on public.source_runs (source_id, started_at desc);

alter table public.source_runs enable row level security;
revoke all on table public.source_runs from public;
revoke all on table public.source_runs from anon, authenticated;
grant select, insert, update on table public.source_runs to authenticated;
grant select, insert, update, delete on table public.source_runs to service_role;

create policy source_runs_operator on public.source_runs
  for all to authenticated using (app.is_operator()) with check (app.is_operator());

-- Health rollup: alert when a source is failing, or empty/unchanged >= 48 h.
create view public.source_health
with (security_invoker = on) as
select
  s.id as source_id,
  s.slug,
  s.name,
  s.kind,
  coalesce(sr.rights_status, 'unknown'::public.rights_status) as rights_status,
  coalesce(sr.enabled, false) as enabled,
  lr.started_at   as last_run_at,
  lr.status       as last_status,
  lr.response_hash as last_hash,
  fresh.last_change_at,
  round(extract(epoch from (now() - fresh.last_change_at)) / 3600.0, 1) as hours_since_change,
  (coalesce(sr.enabled, false) and (
     lr.status = 'failed'
     or fresh.last_change_at is null
     or fresh.last_change_at < now() - interval '48 hours'
  )) as needs_attention
from public.sources s
left join public.source_rights sr on sr.source_id = s.id
left join lateral (
  select r.* from public.source_runs r
  where r.source_id = s.id order by r.started_at desc limit 1
) lr on true
left join lateral (
  select max(r.started_at) as last_change_at
  from public.source_runs r
  where r.source_id = s.id and r.status = 'success'
) fresh on true
where app.is_operator();

revoke all on public.source_health from public;
revoke all on public.source_health from anon;
grant select on public.source_health to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Normalized facts layer (operator-only; publication happens into typed
-- public tables such as fish_counts after review/transform)
-- ---------------------------------------------------------------------------
create table public.source_facts (
  id          bigint generated always as identity primary key,
  source_id   bigint not null references public.sources (id) on delete cascade,
  run_id      bigint references public.source_runs (id) on delete set null,
  fact_type   text not null,          -- e.g. 'fish_count', 'stocking_event'
  payload     jsonb not null,         -- normalized fields ONLY, never prose
  fact_hash   text not null unique,   -- dedupe: never republish old data as fresh
  source_url  text,
  observed_on date,
  fetched_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create index source_facts_source_idx on public.source_facts (source_id, fetched_at desc);
create index source_facts_type_idx on public.source_facts (fact_type);

-- Rights gate at the data layer: adapter-origin facts cannot land for a
-- source that is not enabled (which itself requires documented rights).
create or replace function app.facts_rights_gate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not app.source_is_enabled(new.source_id) then
    raise exception 'Source % is not enabled: rights gate (document permission and enable in source_rights first)', new.source_id;
  end if;
  return new;
end;
$$;
revoke execute on function app.facts_rights_gate() from public;

create trigger source_facts_rights_gate
  before insert on public.source_facts
  for each row execute function app.facts_rights_gate();

alter table public.source_facts enable row level security;
revoke all on table public.source_facts from public;
revoke all on table public.source_facts from anon, authenticated;
grant select, insert on table public.source_facts to authenticated;
grant select, insert, update, delete on table public.source_facts to service_role;

create policy source_facts_operator on public.source_facts
  for all to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Dock Totals — public, free, forever. Facts only, with source + timestamp.
-- ---------------------------------------------------------------------------
create table public.fish_counts (
  id             bigint generated always as identity primary key,
  landing_id     bigint not null references public.landings (id),
  boat           text not null,
  trip_type      text,
  anglers        integer check (anglers is null or anglers between 0 and 500),
  trip_date      date not null,
  entry_kind     public.entry_kind not null default 'manual',
  source_id      bigint references public.sources (id),
  source_fact_id bigint references public.source_facts (id),
  entered_by     uuid references auth.users (id),
  fetched_at     timestamptz,
  created_at     timestamptz not null default now(),
  constraint fish_counts_adapter_requires_source check (
    entry_kind <> 'adapter' or (source_id is not null and source_fact_id is not null)
  )
);

create index fish_counts_date_idx on public.fish_counts (trip_date desc, landing_id);

create table public.fish_count_items (
  id            bigint generated always as identity primary key,
  fish_count_id bigint not null references public.fish_counts (id) on delete cascade,
  species_id    bigint references public.species (id),
  species_label text not null,
  qty           integer not null check (qty >= 0)
);

create index fish_count_items_parent_idx on public.fish_count_items (fish_count_id);

create or replace function app.fish_counts_rights_gate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.entry_kind = 'adapter' and not app.source_is_enabled(new.source_id) then
    raise exception 'Adapter-entered counts require an enabled (rights-cleared) source';
  end if;
  return new;
end;
$$;
revoke execute on function app.fish_counts_rights_gate() from public;

create trigger fish_counts_rights_gate
  before insert or update on public.fish_counts
  for each row execute function app.fish_counts_rights_gate();

alter table public.fish_counts enable row level security;
revoke all on table public.fish_counts from public;
revoke all on table public.fish_counts from anon, authenticated;
grant select on table public.fish_counts to anon, authenticated;
grant insert, update, delete on table public.fish_counts to authenticated;
grant select, insert, update, delete on table public.fish_counts to service_role;

create policy fish_counts_select_all on public.fish_counts
  for select to anon, authenticated using (true);
create policy fish_counts_write_operator on public.fish_counts
  for insert to authenticated with check (app.is_operator());
create policy fish_counts_update_operator on public.fish_counts
  for update to authenticated using (app.is_operator()) with check (app.is_operator());
create policy fish_counts_delete_operator on public.fish_counts
  for delete to authenticated using (app.is_operator());

alter table public.fish_count_items enable row level security;
revoke all on table public.fish_count_items from public;
revoke all on table public.fish_count_items from anon, authenticated;
grant select on table public.fish_count_items to anon, authenticated;
grant insert, update, delete on table public.fish_count_items to authenticated;
grant select, insert, update, delete on table public.fish_count_items to service_role;

create policy fci_select_all on public.fish_count_items
  for select to anon, authenticated using (true);
create policy fci_write_operator on public.fish_count_items
  for insert to authenticated with check (app.is_operator());
create policy fci_update_operator on public.fish_count_items
  for update to authenticated using (app.is_operator()) with check (app.is_operator());
create policy fci_delete_operator on public.fish_count_items
  for delete to authenticated using (app.is_operator());

-- ---------------------------------------------------------------------------
-- Intel drafts (Joseph / Telegram) — operator-only surface.
-- Raw inbound text and exact coordinates live in app_private with short
-- retention. Publication is a named-operator action (migration 0005) and is
-- additionally gated on a signed contributor agreement.
-- ---------------------------------------------------------------------------
create table public.intel_drafts (
  id                     uuid primary key default gen_random_uuid(),
  channel                text not null default 'telegram',
  contributor_label      text not null default 'Joseph',
  agreement_status       text not null default 'missing'
                         check (agreement_status in ('missing', 'draft', 'signed')),
  received_at            timestamptz not null default now(),
  species_id             bigint references public.species (id),
  zone_id                bigint references public.zones (id),
  privacy_level          public.report_privacy not null default 'general',
  confidence             numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  region_check_passed    boolean,
  duplicate_check_passed boolean,
  safety_check_passed    boolean,
  draft_text             text check (draft_text is null or char_length(draft_text) <= 2000),
  status                 public.intel_status not null default 'pending',
  reviewed_by            uuid references auth.users (id),
  reviewed_at            timestamptz,
  published_report_id    uuid references public.reports (id),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index intel_drafts_status_idx on public.intel_drafts (status, received_at);

create trigger intel_drafts_touch
  before update on public.intel_drafts
  for each row execute function app.touch_updated_at();

alter table public.intel_drafts enable row level security;
revoke all on table public.intel_drafts from public;
revoke all on table public.intel_drafts from anon, authenticated;
grant select, insert, update on table public.intel_drafts to authenticated;
grant select, insert, update, delete on table public.intel_drafts to service_role;

create policy intel_drafts_operator on public.intel_drafts
  for all to authenticated using (app.is_operator()) with check (app.is_operator());

create table app_private.intel_payloads (
  intel_id    uuid primary key references public.intel_drafts (id) on delete cascade,
  raw_text    text,                                  -- short retention
  exact_geom  extensions.geography(Point, 4326),
  meta        jsonb,
  received_at timestamptz not null default now(),
  purge_after date not null default (current_date + 30)
);

alter table app_private.intel_payloads enable row level security;
revoke all on table app_private.intel_payloads from public;
revoke all on table app_private.intel_payloads from anon, authenticated, service_role;

-- Short-retention policy: raw inbound text is wiped after purge_after;
-- coordinates of terminal (non-pending) drafts are wiped 7 days after review.
-- Schedule via pg_cron in production (see README); callable by operators.
create or replace function public.purge_intel_payloads()
returns table (raw_wiped integer, coords_wiped integer)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  n_raw integer;
  n_geo integer;
begin
  if auth.uid() is not null and not app.is_operator() then
    raise exception 'Operator role required';
  end if;
  update app_private.intel_payloads
     set raw_text = null
   where raw_text is not null and purge_after < current_date;
  get diagnostics n_raw = row_count;

  update app_private.intel_payloads p
     set exact_geom = null
    from public.intel_drafts d
   where d.id = p.intel_id
     and p.exact_geom is not null
     and d.status <> 'pending'
     and d.reviewed_at is not null
     and d.reviewed_at < now() - interval '7 days';
  get diagnostics n_geo = row_count;

  return query select n_raw, n_geo;
end;
$$;
revoke execute on function public.purge_intel_payloads() from public;
grant execute on function public.purge_intel_payloads() to authenticated, service_role;
