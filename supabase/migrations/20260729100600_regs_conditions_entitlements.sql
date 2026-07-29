-- ============================================================================
-- OFFINGCUE FOUNDATION 0006 — regulations, conditions, maritime, entitlements
--
-- Laws encoded:
--   * Regulations always carry an official source and cannot become current
--     without a named human reviewer (CHECK). Client copy must always say
--     "verify with CDFW".
--   * Conditions carry source, model, issued_at, valid_at, fetched_at and a
--     computed stale flag. Model guidance is never labeled measured truth —
--     the kind/source fields make the provenance explicit.
--   * Maritime layers are pinned not-for-navigation at the schema level.
--   * Free tier never shrinks: current conditions, approved reports, counts,
--     rules, waypoints, zones, species are all readable by anon. The ONLY
--     entitlement-gated read in this schema is conditions HISTORY (> 48 h).
--     Privacy is never entitlement-checked anywhere.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Regulations (versioned, human-reviewed)
-- ---------------------------------------------------------------------------
create table public.regulation_versions (
  id            bigint generated always as identity primary key,
  species_id    bigint references public.species (id),
  scope_label   text not null,
  method        text,
  season_note   text,
  season_open   date,
  season_close  date,
  bag_limit     text,
  size_limit    text,
  gear_note     text,
  depth_limit   text,
  effective_from date,
  effective_to  date,
  source_url    text not null,
  source_kind   text not null default 'cdfw',
  reviewed_by   uuid references auth.users (id),
  reviewed_at   timestamptz,
  is_current    boolean not null default false,
  version_no    integer not null default 1,
  created_at    timestamptz not null default now(),
  constraint regs_current_requires_review check (not is_current or reviewed_by is not null)
);

create index regulation_versions_species_idx on public.regulation_versions (species_id, is_current);

alter table public.regulation_versions enable row level security;
revoke all on table public.regulation_versions from public;
revoke all on table public.regulation_versions from anon, authenticated;
grant select on table public.regulation_versions to anon, authenticated;
grant insert, update on table public.regulation_versions to authenticated;
grant select, insert, update, delete on table public.regulation_versions to service_role;

create policy regs_select_all on public.regulation_versions
  for select to anon, authenticated using (true);
create policy regs_insert_operator on public.regulation_versions
  for insert to authenticated with check (app.is_operator());
create policy regs_update_operator on public.regulation_versions
  for update to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Entitlements (RevenueCat writes arrive later via service_role webhook).
-- Offline never lapses mid-trip → reads keep a 72 h grace window past
-- current_period_end, and 'grace' is an entitled status.
-- ---------------------------------------------------------------------------
create table public.entitlements (
  id                 bigint generated always as identity primary key,
  user_id            uuid not null references auth.users (id) on delete cascade,
  product            text not null check (product in ('pro')),
  status             public.entitlement_status not null,
  source             text not null default 'revenuecat',
  external_ref       text,
  current_period_end timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (user_id, product)
);

create trigger entitlements_touch
  before update on public.entitlements
  for each row execute function app.touch_updated_at();

alter table public.entitlements enable row level security;
revoke all on table public.entitlements from public;
revoke all on table public.entitlements from anon, authenticated;
grant select on table public.entitlements to authenticated;
grant select, insert, update, delete on table public.entitlements to service_role;

create policy entitlements_select_own on public.entitlements
  for select to authenticated
  using (user_id = auth.uid() or app.is_operator());

create or replace function app.has_entitlement(p_product text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = auth.uid()
      and e.product = p_product
      and e.status in ('active', 'trial', 'grace')
      and (e.current_period_end is null
           or e.current_period_end > now() - interval '72 hours')
  );
$$;
revoke execute on function app.has_entitlement(text) from public;
grant execute on function app.has_entitlement(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Condition snapshots
-- ---------------------------------------------------------------------------
create table public.condition_snapshots (
  id               bigint generated always as identity primary key,
  kind             public.condition_kind not null,
  source           text not null,       -- 'noaa_coops' | 'ndbc' | 'nws' | 'open_meteo' | 'coastwatch'
  station_or_model text,
  location         extensions.geography(Point, 4326),
  issued_at        timestamptz,
  valid_at         timestamptz not null,
  fetched_at       timestamptz not null default now(),
  payload          jsonb not null,
  created_at       timestamptz not null default now()
);

create index condition_snapshots_kind_idx on public.condition_snapshots (kind, valid_at desc);
create index condition_snapshots_fetched_idx on public.condition_snapshots (fetched_at desc);

alter table public.condition_snapshots enable row level security;
revoke all on table public.condition_snapshots from public;
revoke all on table public.condition_snapshots from anon, authenticated;
grant select on table public.condition_snapshots to anon, authenticated;
grant insert on table public.condition_snapshots to authenticated;
grant select, insert, update, delete on table public.condition_snapshots to service_role;

-- Free tier: everything fetched in the last 48 hours (current conditions).
-- Pro: full history (SST/chlorophyll/condition history is a Pro feature).
create policy conditions_select_current on public.condition_snapshots
  for select to anon, authenticated
  using (
    fetched_at >= now() - interval '48 hours'
    or app.has_entitlement('pro')
    or app.is_operator()
  );

create policy conditions_insert_operator on public.condition_snapshots
  for insert to authenticated with check (app.is_operator());

-- Read helper view exposing the required staleness flag alongside provenance.
create view public.conditions_current
with (security_invoker = on) as
select
  id, kind, source, station_or_model, location,
  issued_at, valid_at, fetched_at, payload,
  (fetched_at < now() - interval '3 hours') as is_stale
from public.condition_snapshots;

revoke all on public.conditions_current from public;
grant select on public.conditions_current to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Maritime layers — official geometry only, versioned, never for navigation.
-- No geometry is seeded here; preview lines stay in the preview.
-- ---------------------------------------------------------------------------
create table public.maritime_layers (
  id                 bigint generated always as identity primary key,
  slug               text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  name               text not null,
  kind               text not null check (kind in ('us_mx_boundary', 'mx_12nm', 'enc_chart', 'other')),
  authority          text not null,
  version_manifest   text not null,
  effective_date     date,
  geom               extensions.geography,
  production_ready   boolean not null default false,
  not_for_navigation boolean not null default true check (not_for_navigation),
  created_at         timestamptz not null default now()
);

alter table public.maritime_layers enable row level security;
revoke all on table public.maritime_layers from public;
revoke all on table public.maritime_layers from anon, authenticated;
grant select on table public.maritime_layers to anon, authenticated;
grant insert, update on table public.maritime_layers to authenticated;
grant select, insert, update, delete on table public.maritime_layers to service_role;

create policy maritime_select_all on public.maritime_layers
  for select to anon, authenticated using (true);
create policy maritime_insert_operator on public.maritime_layers
  for insert to authenticated with check (app.is_operator());
create policy maritime_update_operator on public.maritime_layers
  for update to authenticated using (app.is_operator()) with check (app.is_operator());
