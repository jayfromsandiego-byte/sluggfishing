-- ============================================================================
-- OFFINGCUE FOUNDATION 0003 — reports + the three-tier location privacy model
--
-- Design (see docs/privacy-model.md for the threat model):
--   * public.reports NEVER contains exact geometry. It carries display_geom,
--     derived server-side from the angler's privacy choice:
--       exact   → display_geom = true point
--       general → true point projected by a per-report random offset,
--                 300–1000 m, azimuth random — generated ONCE and stored
--                 privately, so repeated reads can't be averaged and the
--                 offset can't be recomputed from public data
--       zone    → display_geom = NULL; only the zone is shown
--   * app_private.report_locations holds the exact point + the stored jitter.
--     No API role has schema USAGE. RLS is enabled with zero policies.
--   * Inserts only via public.submit_report() (no INSERT grant on the table).
--   * display_geom is recomputed by trigger on every write path — clients can
--     never set it.
--   * Approval can only happen through moderate_report() (migration 0005);
--     the guard trigger blocks status → 'approved' on every other path,
--     including table-owner and service_role writes. Reports never auto-publish.
-- ============================================================================

create table public.reports (
  id                   uuid primary key default gen_random_uuid(),
  author_id            uuid not null references auth.users (id) on delete cascade,
  origin               public.report_origin not null default 'angler',
  contributor_label    text,          -- display label for intel-origin reports
  zone_id              bigint not null references public.zones (id),
  species_id           bigint references public.species (id),
  fish_count           integer check (fish_count is null or fish_count between 0 and 500),
  body                 text check (body is null or char_length(body) <= 2000),
  caught_at            timestamptz,
  privacy_level        public.report_privacy not null default 'general',
  status               public.report_status not null default 'draft',
  display_geom         extensions.geography(Point, 4326),
  photo_path           text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  submitted_at         timestamptz,
  sla_reminded_at      timestamptz,
  sla_backup_routed_at timestamptz,
  sla_expired_at       timestamptz,
  approved_at          timestamptz,
  moderated_by         uuid references auth.users (id)
);

create index reports_status_idx on public.reports (status);
create index reports_author_idx on public.reports (author_id);
create index reports_zone_idx on public.reports (zone_id);
create index reports_queue_idx on public.reports (submitted_at) where status = 'submitted';
create index reports_display_gix on public.reports using gist (display_geom);

-- ---------------------------------------------------------------------------
-- The private location vault
-- ---------------------------------------------------------------------------
create table app_private.report_locations (
  report_id         uuid primary key references public.reports (id) on delete cascade,
  exact_geom        extensions.geography(Point, 4326) not null,
  jitter_azimuth_rad double precision not null,
  jitter_distance_m double precision not null
                    check (jitter_distance_m >= 300 and jitter_distance_m <= 1000),
  created_at        timestamptz not null default now()
);

-- Belt and braces: even if a grant ever leaked, RLS with no policies denies.
alter table app_private.report_locations enable row level security;
revoke all on table app_private.report_locations from public;
revoke all on table app_private.report_locations from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Display derivation (SECURITY DEFINER — the only reader of the vault
-- besides the author/operator RPCs below). Never granted to API roles.
-- ---------------------------------------------------------------------------
create or replace function app.compute_display_geom(p_report uuid, p_privacy public.report_privacy)
returns extensions.geography
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  loc app_private.report_locations%rowtype;
begin
  select * into loc from app_private.report_locations where report_id = p_report;
  if not found then
    return null;
  end if;
  return case p_privacy
    when 'exact'   then loc.exact_geom
    when 'general' then extensions.ST_Project(loc.exact_geom, loc.jitter_distance_m, loc.jitter_azimuth_rad)
    else null
  end;
end;
$$;
revoke execute on function app.compute_display_geom(uuid, public.report_privacy) from public;
revoke execute on function app.compute_display_geom(uuid, public.report_privacy)
  from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Write-path guard. Context is carried in a transaction-local GUC set only
-- inside SECURITY DEFINER functions, after their permission checks pass.
-- ---------------------------------------------------------------------------
create or replace function app.reports_guard()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  ctx text := coalesce(current_setting('app.write_ctx', true), '');
begin
  if tg_op = 'INSERT' then
    if ctx not in ('submit_rpc', 'intel_publish') then
      raise exception 'Reports are created through submit_report() only';
    end if;
    -- Server owns lifecycle fields regardless of what was passed in.
    new.status := 'draft';
    new.display_geom := null;
    new.submitted_at := null;
    new.sla_reminded_at := null;
    new.sla_backup_routed_at := null;
    new.sla_expired_at := null;
    new.approved_at := null;
    new.moderated_by := null;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  -- UPDATE ---------------------------------------------------------------
  -- LAW: reports never auto-publish. The only path to 'approved' is
  -- moderate_report(), which sets ctx = 'moderation' after verifying a
  -- named operator. This fires for every role, including the table owner.
  if new.status = 'approved' and old.status is distinct from 'approved'
     and ctx <> 'moderation' then
    raise exception 'Reports never auto-publish: approval requires moderate_report() by a named operator';
  end if;

  if ctx = 'moderation' then
    -- Moderation touches lifecycle only; content and privacy stay the author's.
    new.author_id := old.author_id;
    new.origin := old.origin;
    new.contributor_label := old.contributor_label;
    new.zone_id := old.zone_id;
    new.species_id := old.species_id;
    new.fish_count := old.fish_count;
    new.body := old.body;
    new.caught_at := old.caught_at;
    new.privacy_level := old.privacy_level;
    new.photo_path := old.photo_path;
    new.created_at := old.created_at;
  elsif ctx = 'privacy_rpc' then
    -- Only the privacy level may move; everything else is pinned.
    new.author_id := old.author_id;
    new.origin := old.origin;
    new.contributor_label := old.contributor_label;
    new.zone_id := old.zone_id;
    new.species_id := old.species_id;
    new.fish_count := old.fish_count;
    new.body := old.body;
    new.caught_at := old.caught_at;
    new.status := old.status;
    new.photo_path := old.photo_path;
    new.created_at := old.created_at;
    new.submitted_at := old.submitted_at;
    new.sla_reminded_at := old.sla_reminded_at;
    new.sla_backup_routed_at := old.sla_backup_routed_at;
    new.sla_expired_at := old.sla_expired_at;
    new.approved_at := old.approved_at;
    new.moderated_by := old.moderated_by;
  else
    -- Direct author edit path (RLS has already restricted rows/statuses).
    if old.status in ('approved', 'rejected') then
      raise exception 'Approved or rejected reports change only via set_report_privacy()';
    end if;
    new.author_id := old.author_id;
    new.origin := old.origin;
    new.contributor_label := old.contributor_label;
    new.created_at := old.created_at;
    new.approved_at := old.approved_at;
    new.moderated_by := old.moderated_by;
    new.sla_reminded_at := old.sla_reminded_at;
    new.sla_backup_routed_at := old.sla_backup_routed_at;
    new.sla_expired_at := old.sla_expired_at;

    if new.status is distinct from old.status then
      if not (old.status in ('draft', 'needs_changes', 'expired_queue', 'submitted')
              and new.status in ('draft', 'submitted')) then
        raise exception 'Illegal status transition % -> %', old.status, new.status;
      end if;
    end if;
    if new.status = 'submitted' and old.status is distinct from 'submitted' then
      new.submitted_at := now();
      new.sla_reminded_at := null;
      new.sla_backup_routed_at := null;
      new.sla_expired_at := null;
    end if;
  end if;

  -- display_geom is always server-derived; no path may set it directly.
  new.display_geom := app.compute_display_geom(new.id, new.privacy_level);
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function app.reports_guard() from public;

create trigger reports_guard_biu
  before insert or update on public.reports
  for each row execute function app.reports_guard();

-- ---------------------------------------------------------------------------
-- RLS + grants
-- ---------------------------------------------------------------------------
alter table public.reports enable row level security;
revoke all on table public.reports from public;
revoke all on table public.reports from anon, authenticated;
grant select on table public.reports to anon, authenticated;
grant update, delete on table public.reports to authenticated;  -- no INSERT: RPC only
grant select, update on table public.reports to service_role;   -- no INSERT either

create policy reports_select_public on public.reports
  for select to anon, authenticated
  using (status = 'approved');

create policy reports_select_own on public.reports
  for select to authenticated
  using (author_id = auth.uid());

create policy reports_select_operator on public.reports
  for select to authenticated
  using (app.is_operator());

create policy reports_update_author on public.reports
  for update to authenticated
  using (author_id = auth.uid()
         and status in ('draft', 'needs_changes', 'expired_queue', 'submitted'))
  with check (author_id = auth.uid()
              and status in ('draft', 'submitted'));

create policy reports_update_operator on public.reports
  for update to authenticated
  using (app.is_operator())
  with check (app.is_operator());

create policy reports_delete_author on public.reports
  for delete to authenticated
  using (author_id = auth.uid()
         and status in ('draft', 'needs_changes', 'expired_queue'));

-- ---------------------------------------------------------------------------
-- submit_report — the single entry point for creating a report.
-- The exact position goes straight into the vault; the jitter is drawn once.
-- ---------------------------------------------------------------------------
create or replace function public.submit_report(
  p_zone_slug    text,
  p_lat          double precision,
  p_lon          double precision,
  p_privacy      public.report_privacy default null,
  p_species_slug text default null,
  p_fish_count   integer default null,
  p_body         text default null,
  p_caught_at    timestamptz default null,
  p_submit       boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid        uuid := auth.uid();
  v_zone_id    bigint;
  v_species_id bigint;
  v_privacy    public.report_privacy;
  v_id         uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  perform public.ensure_profile();

  select id into v_zone_id from public.zones where slug = p_zone_slug;
  if not found then
    raise exception 'Unknown zone %', p_zone_slug;
  end if;

  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then
    raise exception 'Valid coordinates are required (they are stored privately; display always honors your privacy choice)';
  end if;

  if p_species_slug is not null then
    select id into v_species_id from public.species where slug = p_species_slug;
    if not found then
      raise exception 'Unknown species %', p_species_slug;
    end if;
  end if;

  v_privacy := coalesce(p_privacy, app.my_default_privacy());

  perform set_config('app.write_ctx', 'submit_rpc', true);

  insert into public.reports
    (author_id, zone_id, species_id, fish_count, body, caught_at, privacy_level)
  values
    (v_uid, v_zone_id, v_species_id, p_fish_count, p_body, p_caught_at, v_privacy)
  returning id into v_id;

  insert into app_private.report_locations
    (report_id, exact_geom, jitter_azimuth_rad, jitter_distance_m)
  values
    (v_id,
     extensions.ST_SetSRID(extensions.ST_MakePoint(p_lon, p_lat), 4326)::extensions.geography,
     random() * 2 * pi(),
     300 + random() * 700);

  -- Re-derive display now that the vault row exists.
  update public.reports set privacy_level = v_privacy where id = v_id;

  if p_submit then
    update public.reports set status = 'submitted' where id = v_id;
  end if;

  perform set_config('app.write_ctx', '', true);
  return v_id;
end;
$$;
revoke execute on function public.submit_report(text, double precision, double precision, public.report_privacy, text, integer, text, timestamptz, boolean) from public;
grant execute on function public.submit_report(text, double precision, double precision, public.report_privacy, text, integer, text, timestamptz, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- set_report_privacy — the angler's choice, changeable at any time, any
-- status, in any direction. Privacy is never for sale and never stuck.
-- Uses the STORED jitter, so flipping levels can't be used to average
-- multiple obfuscated points.
-- ---------------------------------------------------------------------------
create or replace function public.set_report_privacy(p_report uuid, p_privacy public.report_privacy)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_old public.report_privacy;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  select privacy_level into v_old
    from public.reports where id = p_report and author_id = v_uid;
  if not found then
    raise exception 'Report not found or not yours';
  end if;

  perform set_config('app.write_ctx', 'privacy_rpc', true);
  update public.reports set privacy_level = p_privacy where id = p_report;
  perform set_config('app.write_ctx', '', true);

  insert into public.moderation_actions
    (report_id, actor_kind, actor_id, action, note)
  values
    (p_report, 'author', v_uid, 'privacy_change',
     format('privacy %s -> %s', v_old, p_privacy));
end;
$$;
-- moderation_actions is created in 0005; grant there. Function body is only
-- parsed at call time, so the forward reference is safe.
revoke execute on function public.set_report_privacy(uuid, public.report_privacy) from public;
grant execute on function public.set_report_privacy(uuid, public.report_privacy) to authenticated;

-- ---------------------------------------------------------------------------
-- Exact-location access: the author (their own data) and operators
-- (review context). Nobody else, no other path.
-- ---------------------------------------------------------------------------
create or replace function public.report_exact_location(p_report uuid)
returns table (lat double precision, lon double precision)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_author uuid;
begin
  select author_id into v_author from public.reports where id = p_report;
  if not found then
    raise exception 'Report not found';
  end if;
  if v_uid is null or (v_uid <> v_author and not app.is_operator()) then
    raise exception 'Exact location is visible only to the report author and operators';
  end if;
  return query
    select extensions.ST_Y(l.exact_geom::extensions.geometry),
           extensions.ST_X(l.exact_geom::extensions.geometry)
    from app_private.report_locations l
    where l.report_id = p_report;
end;
$$;
revoke execute on function public.report_exact_location(uuid) from public;
grant execute on function public.report_exact_location(uuid) to authenticated;
