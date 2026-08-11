-- ============================================================================
-- OFFINGCUE FOUNDATION 0008 — offline-first GPS tracks (change order §5)
-- Own-position tracking is device-side (GNSS, no connectivity needed).
-- The backend's job: durable, PRIVATE track storage synced when the boat
-- gets signal back (report-outbox pattern). Tracks are never public and
-- never entitlement-gated. AIS vessel positions are a SEPARATE feed served
-- with a deliberate ~60-minute delay buffer (see ais_positions.delayed_until).
-- ============================================================================

create table public.tracks (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users (id) on delete cascade,
  started_at   timestamptz not null,
  ended_at     timestamptz,
  distance_nm  numeric check (distance_nm is null or distance_nm >= 0),
  point_count  integer not null default 0,
  device_ref   text,               -- client-generated id for offline dedupe
  synced_at    timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  unique (owner_id, device_ref)
);

create table public.track_points (
  id        bigint generated always as identity primary key,
  track_id  uuid not null references public.tracks (id) on delete cascade,
  fixed_at  timestamptz not null,
  geom      extensions.geography(Point, 4326) not null,
  speed_kn  numeric,
  accuracy_m numeric
);
create index track_points_track_idx on public.track_points (track_id, fixed_at);
create index track_points_gix on public.track_points using gist (geom);

-- Tracks are the owner's private data. Full stop. No public policy exists.
alter table public.tracks enable row level security;
alter table public.track_points enable row level security;
revoke all on table public.tracks from public; revoke all on table public.tracks from anon, authenticated;
revoke all on table public.track_points from public; revoke all on table public.track_points from anon, authenticated;
grant select, insert, update, delete on table public.tracks to authenticated;
grant select, insert, delete on table public.track_points to authenticated;
grant select, insert, update, delete on table public.tracks to service_role;
grant select, insert, delete on table public.track_points to service_role;

create policy tracks_owner on public.tracks
  for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy track_points_owner on public.track_points
  for all to authenticated
  using (track_id in (select id from public.tracks where owner_id = auth.uid()))
  with check (track_id in (select id from public.tracks where owner_id = auth.uid()));

-- Batched offline sync: client uploads a whole recorded track in one call.
create or replace function public.sync_track(
  p_device_ref text,
  p_started_at timestamptz,
  p_ended_at   timestamptz,
  p_points     jsonb   -- [[lon,lat,epoch_ms,speed_kn,accuracy_m], ...]
) returns uuid
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid; v_n integer; v_dist numeric;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  insert into public.tracks (owner_id, device_ref, started_at, ended_at)
  values (v_uid, p_device_ref, p_started_at, p_ended_at)
  on conflict (owner_id, device_ref) do update set ended_at = excluded.ended_at, synced_at = now()
  returning id into v_id;
  delete from public.track_points where track_id = v_id;
  insert into public.track_points (track_id, fixed_at, geom, speed_kn, accuracy_m)
  select v_id,
         to_timestamp((e->>2)::double precision / 1000.0),
         extensions.ST_SetSRID(extensions.ST_MakePoint((e->>0)::double precision,(e->>1)::double precision),4326)::extensions.geography,
         nullif(e->>3,'')::numeric, nullif(e->>4,'')::numeric
  from jsonb_array_elements(p_points) e;
  get diagnostics v_n = row_count;
  select coalesce(extensions.ST_Length(extensions.ST_MakeLine(geom::extensions.geometry order by fixed_at)::extensions.geography)/1852.0,0)
    into v_dist from public.track_points where track_id = v_id;
  update public.tracks set point_count = v_n, distance_nm = round(v_dist,3) where id = v_id;
  return v_id;
end; $$;
revoke execute on function public.sync_track(text,timestamptz,timestamptz,jsonb) from public;
grant execute on function public.sync_track(text,timestamptz,timestamptz,jsonb) to authenticated;

-- AIS delay buffer skeleton: positions become servable only after the
-- deliberate delay window (default 60 min). Regional bbox enforced on ingest.
create table public.ais_positions (
  id bigint generated always as identity primary key,
  mmsi text not null,
  vessel_name text,
  kind text,
  geom extensions.geography(Point,4326) not null,
  course numeric, speed_kn numeric,
  observed_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index ais_positions_mmsi_idx on public.ais_positions (mmsi, observed_at desc);
alter table public.ais_positions enable row level security;
revoke all on table public.ais_positions from public; revoke all on table public.ais_positions from anon, authenticated;
grant select on table public.ais_positions to anon, authenticated;
grant select, insert, delete on table public.ais_positions to service_role;
-- The delay is enforced IN THE POLICY: nothing newer than the 60-min buffer is readable.
create policy ais_delayed_read on public.ais_positions
  for select to anon, authenticated using (observed_at <= now() - interval '60 minutes');
