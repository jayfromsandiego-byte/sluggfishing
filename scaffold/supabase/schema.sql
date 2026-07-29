-- SluggFishing schema v0.1 // Postgres (Supabase) + PostGIS
create extension if not exists postgis;

-- ===== enums =====
create type water_type as enum ('freshwater','salt_shore','pier','bay','lake','offshore');
create type privacy_level as enum ('exact','general','zone');
create type report_status as enum ('pending','approved','rejected','flagged');
create type waypoint_type as enum ('reef','kelp','wreck','drop','flat','jetty','hole','other');

-- ===== identity =====
create table profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text unique not null,
  avatar_url text,
  home_region text default 'san_diego',
  is_moderator boolean not null default false,
  created_at timestamptz not null default now()
);

-- ===== geography =====
create table zones (
  id bigint generated always as identity primary key,
  name text not null,                      -- e.g. 'Point Loma Kelp', 'Mission Bay'
  water water_type not null,
  geom geometry(Polygon, 4326) not null
);

create table locations (
  id bigint generated always as identity primary key,
  name text not null,
  slug text unique not null,
  water water_type not null,
  geom geometry(Point, 4326) not null,
  zone_id bigint references zones(id),
  description text,
  depth_structure text,
  access_notes text,
  parking text,
  fees text,
  regulations text,
  status text not null default 'active',   -- active | hidden
  updated_at timestamptz not null default now()
);
create index locations_geom_idx on locations using gist (geom);

-- MOAT #1 // permanent curated waypoints. Never auto-generated.
create table waypoints (
  id bigint generated always as identity primary key,
  location_id bigint references locations(id) on delete cascade,
  name text not null,
  geom geometry(Point, 4326) not null,
  wp_type waypoint_type not null default 'other',
  depth_ft int,
  notes text,
  source text not null default 'curated', -- curated | promoted_report
  updated_at timestamptz not null default now()
);
create index waypoints_geom_idx on waypoints using gist (geom);

-- ===== species intel =====
create table species (
  id bigint generated always as identity primary key,
  common_name text not null,
  scientific_name text,
  icon_key text,
  regs_note text
);

create table location_species (
  location_id bigint references locations(id) on delete cascade,
  species_id bigint references species(id) on delete cascade,
  best_seasons text[],
  best_times text,
  quality int check (quality between 1 and 5),
  baits text[],
  techniques text[],
  primary key (location_id, species_id)
);

-- ===== community reports =====
create table reports (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(user_id),
  location_id bigint references locations(id),
  exact_geom geometry(Point, 4326),        -- ALWAYS stored, served per privacy_level only
  privacy privacy_level not null default 'general',
  species_id bigint references species(id),
  length_in numeric,
  weight_lb numeric,
  bait text,
  technique text,
  body text,
  caught_at timestamptz,
  status report_status not null default 'pending',
  moderated_by uuid references profiles(user_id),
  moderated_at timestamptz,
  created_at timestamptz not null default now()
);

create table report_photos (
  id bigint generated always as identity primary key,
  report_id bigint not null references reports(id) on delete cascade,
  storage_path text not null,
  exif_stripped boolean not null default false
);

create table moderation_actions (
  id bigint generated always as identity primary key,
  report_id bigint not null references reports(id),
  action text not null,                    -- approve | reject | flag
  reason text,
  actor_id uuid references profiles(user_id),
  created_at timestamptz not null default now()
);

-- MOAT #3 // stocking schedules
create table stocking_events (
  id bigint generated always as identity primary key,
  location_id bigint not null references locations(id),
  species_id bigint references species(id),
  stock_date date not null,
  quantity_lbs numeric,
  source text,
  source_url text
);

-- computed bite ratings (cron edge function)
create table bite_ratings (
  location_id bigint primary key references locations(id),
  score int check (score between 1 and 5),
  inputs jsonb,
  computed_at timestamptz not null default now()
);

-- ===== AIS add-on (V1.1) =====
create table boats (
  id bigint generated always as identity primary key,
  name text not null,
  mmsi text unique not null,
  operator text,
  home_port text
);
create table boat_positions (
  mmsi text not null,
  geom geometry(Point, 4326) not null,
  sog numeric, cog numeric,
  ts timestamptz not null,
  primary key (mmsi, ts)
);
create table boat_follows (
  user_id uuid references profiles(user_id) on delete cascade,
  boat_id bigint references boats(id) on delete cascade,
  notify boolean not null default true,
  primary key (user_id, boat_id)
);

-- ===== subscriptions (RevenueCat webhook mirror) =====
create table subscription_events (
  id bigint generated always as identity primary key,
  user_id uuid references profiles(user_id),
  product_id text,
  event_type text,
  expires_at timestamptz,
  raw jsonb,
  created_at timestamptz not null default now()
);

-- ===== RLS sketch (tighten in Sprint 1) =====
alter table reports enable row level security;
-- owner + moderators see everything incl. exact_geom
create policy reports_owner_all on reports
  for select using (auth.uid() = user_id or exists (
    select 1 from profiles p where p.user_id = auth.uid() and p.is_moderator));
-- public reads approved reports ONLY via the privacy-respecting view below
create policy reports_insert_own on reports
  for insert with check (auth.uid() = user_id);

-- privacy-respecting public view // exact only when privacy='exact',
-- 1km-grid snap for 'general', zone centroid handled app-side for 'zone'
create view public_reports as
select
  r.id, r.location_id, r.species_id, r.length_in, r.weight_lb,
  r.bait, r.technique, r.body, r.caught_at, r.privacy, r.created_at,
  case r.privacy
    when 'exact'   then r.exact_geom
    when 'general' then st_snaptogrid(r.exact_geom, 0.01)  -- ~1km
    else null
  end as public_geom
from reports r
where r.status = 'approved';
