-- ============================================================================
-- OFFINGCUE FOUNDATION 0002 — zones, species, landings, waypoints
-- Laws encoded:
--   * No production waypoint without captain + current-chart verification
--     (CHECK constraint + RLS: public sees captain_verified only).
--   * Every waypoint change is versioned (append-only waypoint_versions).
--   * Datum is pinned to WGS84 at the schema level.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Zones — the display unit for 'zone' privacy and for 'general' context.
-- Seed geometry is placeholder-grade and flagged production_ready = false.
-- ---------------------------------------------------------------------------
create table public.zones (
  id               bigint generated always as identity primary key,
  slug             text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  name             text not null,
  kind             public.zone_kind not null,
  geom             extensions.geography(MultiPolygon, 4326),
  centroid         extensions.geography(Point, 4326),
  production_ready boolean not null default false,
  notes            text,
  created_at       timestamptz not null default now()
);

create index zones_geom_gix on public.zones using gist (geom);

alter table public.zones enable row level security;
revoke all on table public.zones from public;
revoke all on table public.zones from anon, authenticated;
grant select on table public.zones to anon, authenticated;
grant insert, update on table public.zones to authenticated;
grant select, insert, update, delete on table public.zones to service_role;

create policy zones_select_all on public.zones
  for select to anon, authenticated using (true);
create policy zones_write_operator on public.zones
  for insert to authenticated with check (app.is_operator());
create policy zones_update_operator on public.zones
  for update to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Species — seeded from the 30-species catalog. regs_note is display copy
-- that the client must always pair with "verify with CDFW".
-- ---------------------------------------------------------------------------
create table public.species (
  id          bigint generated always as identity primary key,
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,80}$'),
  common_name text not null,
  latin_name  text,
  grouping    text,
  water       text,
  season_note text,
  baits_lures text,
  spot_types  text,
  regs_note   text,
  icon_key    text,
  created_at  timestamptz not null default now()
);

alter table public.species enable row level security;
revoke all on table public.species from public;
revoke all on table public.species from anon, authenticated;
grant select on table public.species to anon, authenticated;
grant insert, update on table public.species to authenticated;
grant select, insert, update, delete on table public.species to service_role;

create policy species_select_all on public.species
  for select to anon, authenticated using (true);
create policy species_write_operator on public.species
  for insert to authenticated with check (app.is_operator());
create policy species_update_operator on public.species
  for update to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Landings — public directory entities for Dock Totals. Rights to any FEED
-- live in source_rights (migration 0004); a landing existing here implies
-- nothing about ingestion permission.
-- ---------------------------------------------------------------------------
create table public.landings (
  id               bigint generated always as identity primary key,
  slug             text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  name             text not null,
  website_url      text,
  attribution_text text,
  created_at       timestamptz not null default now()
);

alter table public.landings enable row level security;
revoke all on table public.landings from public;
revoke all on table public.landings from anon, authenticated;
grant select on table public.landings to anon, authenticated;
grant insert, update on table public.landings to authenticated;
grant select, insert, update, delete on table public.landings to service_role;

create policy landings_select_all on public.landings
  for select to anon, authenticated using (true);
create policy landings_write_operator on public.landings
  for insert to authenticated with check (app.is_operator());
create policy landings_update_operator on public.landings
  for update to authenticated using (app.is_operator()) with check (app.is_operator());

-- ---------------------------------------------------------------------------
-- Waypoints — the curated permanent marks. Public app surface sees ONLY
-- captain_verified rows. Everything else stays operator-side.
-- ---------------------------------------------------------------------------
create table public.waypoints (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null check (char_length(name) between 2 and 80),
  aliases             text[] not null default '{}',
  kind                text,
  zone_id             bigint references public.zones (id),
  geom                extensions.geography(Point, 4326),
  depth_m             numeric check (depth_m is null or depth_m between 0 and 4000),
  datum               text not null default 'WGS84' check (datum = 'WGS84'),
  verification_status public.verification_status not null default 'unverified',
  verified_by         text,
  verified_on         date,
  source_evidence     text,
  current_version     integer not null default 1,
  notes               text,
  created_by          uuid references auth.users (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint waypoints_verified_requires_evidence check (
    verification_status <> 'captain_verified'
    or (verified_by is not null
        and verified_on is not null
        and source_evidence is not null
        and geom is not null)
  )
);

create index waypoints_geom_gix on public.waypoints using gist (geom);
create index waypoints_zone_idx on public.waypoints (zone_id);
create unique index waypoints_name_lower_key on public.waypoints (lower(name));

create table public.waypoint_versions (
  id                  bigint generated always as identity primary key,
  waypoint_id         uuid not null references public.waypoints (id) on delete cascade,
  version_no          integer not null,
  name                text not null,
  aliases             text[],
  kind                text,
  zone_id             bigint,
  geom                extensions.geography(Point, 4326),
  depth_m             numeric,
  datum               text,
  verification_status public.verification_status,
  verified_by         text,
  verified_on         date,
  source_evidence     text,
  change_note         text,
  changed_by          uuid,
  created_at          timestamptz not null default now(),
  unique (waypoint_id, version_no)
);

-- Version bump + snapshot
create or replace function app.waypoints_version_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.current_version := old.current_version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;
revoke execute on function app.waypoints_version_trigger() from public;

create or replace function app.waypoints_snapshot_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  insert into public.waypoint_versions
    (waypoint_id, version_no, name, aliases, kind, zone_id, geom, depth_m, datum,
     verification_status, verified_by, verified_on, source_evidence,
     change_note, changed_by)
  values
    (new.id, new.current_version, new.name, new.aliases, new.kind, new.zone_id,
     new.geom, new.depth_m, new.datum, new.verification_status, new.verified_by,
     new.verified_on, new.source_evidence,
     nullif(current_setting('app.change_note', true), ''),
     auth.uid());
  return new;
end;
$$;
revoke execute on function app.waypoints_snapshot_trigger() from public;

create trigger waypoints_version_biu
  before update on public.waypoints
  for each row execute function app.waypoints_version_trigger();

create trigger waypoints_snapshot_aiu
  after insert or update on public.waypoints
  for each row execute function app.waypoints_snapshot_trigger();

-- Append-only audit: versions can never be edited or deleted through any role.
create or replace function app.forbid_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;
revoke execute on function app.forbid_mutation() from public;

create trigger waypoint_versions_immutable
  before update or delete on public.waypoint_versions
  for each row execute function app.forbid_mutation();

alter table public.waypoints enable row level security;
revoke all on table public.waypoints from public;
revoke all on table public.waypoints from anon, authenticated;
grant select on table public.waypoints to anon, authenticated;
grant insert, update, delete on table public.waypoints to authenticated;
grant select, insert, update, delete on table public.waypoints to service_role;

create policy waypoints_select_public on public.waypoints
  for select to anon, authenticated
  using (verification_status = 'captain_verified' or app.is_operator());
create policy waypoints_insert_operator on public.waypoints
  for insert to authenticated with check (app.is_operator());
create policy waypoints_update_operator on public.waypoints
  for update to authenticated using (app.is_operator()) with check (app.is_operator());
create policy waypoints_delete_operator on public.waypoints
  for delete to authenticated using (app.is_operator());

alter table public.waypoint_versions enable row level security;
revoke all on table public.waypoint_versions from public;
revoke all on table public.waypoint_versions from anon, authenticated;
grant select on table public.waypoint_versions to authenticated;
grant select on table public.waypoint_versions to service_role;

create policy waypoint_versions_select_operator on public.waypoint_versions
  for select to authenticated using (app.is_operator());

-- ---------------------------------------------------------------------------
-- Waypoint import staging + contract (see docs/seed-import-contract.md).
-- Rows without the full verification trio import as pending_verification.
-- ---------------------------------------------------------------------------
create table public.waypoint_import_staging (
  id              bigint generated always as identity primary key,
  batch_id        uuid not null,
  name            text,
  aliases_raw     text,          -- pipe-separated: "Lohue Canyon|The Canyon"
  kind            text,
  zone_slug       text,
  lat             double precision,
  lon             double precision,
  datum           text,
  depth_m         numeric,
  source_evidence text,
  verified_by     text,
  verified_on     date,
  notes           text,
  status          text not null default 'pending'
                  check (status in ('pending', 'imported', 'rejected')),
  reject_reason   text,
  created_at      timestamptz not null default now()
);

alter table public.waypoint_import_staging enable row level security;
revoke all on table public.waypoint_import_staging from public;
revoke all on table public.waypoint_import_staging from anon, authenticated;
grant select, insert, update, delete on table public.waypoint_import_staging to authenticated;
grant select, insert, update, delete on table public.waypoint_import_staging to service_role;

create policy wp_staging_operator on public.waypoint_import_staging
  for all to authenticated using (app.is_operator()) with check (app.is_operator());

create or replace function public.import_waypoints(p_batch uuid)
returns table (imported integer, rejected integer)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  r         record;
  v_zone_id bigint;
  v_aliases text[];
  v_status  public.verification_status;
  n_ok      integer := 0;
  n_bad     integer := 0;
begin
  if not app.is_operator() then
    raise exception 'Operator role required';
  end if;

  for r in
    select * from public.waypoint_import_staging
    where batch_id = p_batch and status = 'pending'
    order by id
  loop
    begin
      if r.name is null or char_length(trim(r.name)) < 2 then
        raise exception 'name required';
      end if;
      if coalesce(upper(r.datum), '') <> 'WGS84' then
        raise exception 'datum must be WGS84 (got %)', coalesce(r.datum, 'blank');
      end if;
      if r.lat is null or r.lon is null then
        raise exception 'coordinates required';
      end if;
      -- San Diego operating box (ocean out to Tanner/Cortes, five lakes inland)
      if r.lat not between 31.0 and 33.8 or r.lon not between -121.5 and -116.0 then
        raise exception 'coordinates outside San Diego operating box';
      end if;
      if exists (select 1 from public.waypoints w where lower(w.name) = lower(trim(r.name))) then
        raise exception 'duplicate waypoint name';
      end if;

      v_zone_id := null;
      if r.zone_slug is not null then
        select z.id into v_zone_id from public.zones z where z.slug = r.zone_slug;
        if not found then
          raise exception 'unknown zone_slug %', r.zone_slug;
        end if;
      end if;

      v_aliases := coalesce(
        (select array_agg(trim(a)) from unnest(string_to_array(r.aliases_raw, '|')) a
          where trim(a) <> ''),
        '{}'
      );

      if r.verified_by is not null and r.verified_on is not null
         and r.source_evidence is not null then
        v_status := 'captain_verified';
      else
        v_status := 'pending_verification';
      end if;

      insert into public.waypoints
        (name, aliases, kind, zone_id, geom, depth_m, datum,
         verification_status, verified_by, verified_on, source_evidence,
         notes, created_by)
      values
        (trim(r.name), v_aliases, r.kind, v_zone_id,
         extensions.ST_SetSRID(extensions.ST_MakePoint(r.lon, r.lat), 4326)::extensions.geography,
         r.depth_m, 'WGS84', v_status, r.verified_by, r.verified_on,
         r.source_evidence, r.notes, auth.uid());

      update public.waypoint_import_staging
        set status = 'imported', reject_reason = null where id = r.id;
      n_ok := n_ok + 1;
    exception when others then
      update public.waypoint_import_staging
        set status = 'rejected', reject_reason = sqlerrm where id = r.id;
      n_bad := n_bad + 1;
    end;
  end loop;

  return query select n_ok, n_bad;
end;
$$;
revoke execute on function public.import_waypoints(uuid) from public;
grant execute on function public.import_waypoints(uuid) to authenticated, service_role;
