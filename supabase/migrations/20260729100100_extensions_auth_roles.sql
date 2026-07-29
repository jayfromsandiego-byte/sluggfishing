-- ============================================================================
-- OFFINGCUE FOUNDATION 0001 — extensions, schemas, enums, roles, profiles
-- Target: Supabase (Postgres 15+). Also runs on plain Postgres with
-- tests/00_local_shim.sql applied first (provides auth schema + API roles).
-- Laws encoded here and throughout:
--   * Privacy is never for sale — privacy controls live on the free tier.
--   * Reports never auto-publish — enforced by trigger, not convention.
--   * Exact geometry is stored but never served against the angler's choice.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Schemas
--   public       → API-exposed (PostgREST). Everything here is deliberate.
--   app          → SQL helper functions. NOT in PostgREST exposed schemas.
--   app_private  → sensitive data (exact geometry, raw intel). No API grants.
-- ---------------------------------------------------------------------------
create schema if not exists extensions;
create schema if not exists app;
create schema if not exists app_private;

create extension if not exists postgis with schema extensions;

grant usage on schema extensions to anon, authenticated, service_role;

-- app: RLS policy expressions run as the querying role, so the API roles need
-- USAGE on the schema. Individual functions are granted one by one.
grant usage on schema app to anon, authenticated, service_role;

-- app_private: no API role ever gets in. Not even service_role — the raw API
-- surface must be provably unable to reach exact geometry.
revoke all on schema app_private from public;
revoke all on schema app_private from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.report_privacy as enum ('exact', 'general', 'zone');

create type public.report_status as enum
  ('draft', 'submitted', 'approved', 'rejected', 'needs_changes', 'expired_queue');

create type public.moderation_action_kind as enum
  ('submit', 'remind_primary', 'route_backup', 'expire_freshness',
   'approve', 'reject', 'request_changes', 'clarify', 'privacy_change', 'edit');

create type public.actor_kind as enum ('author', 'operator', 'system');

create type public.app_role as enum ('angler', 'operator', 'admin');

create type public.verification_status as enum
  ('unverified', 'pending_verification', 'captain_verified');

create type public.rights_status as enum
  ('unknown', 'requested', 'permitted', 'denied', 'not_required');

create type public.source_kind as enum
  ('landing_counts', 'lake_page', 'cdfw_regulations', 'cdfw_stocking',
   'noaa_coops', 'ndbc', 'nws', 'noaa_enc', 'noaa_coastwatch',
   'open_meteo', 'telegram_contact', 'manual_operator', 'other');

create type public.run_status as enum ('success', 'empty', 'unchanged', 'failed');

create type public.entitlement_status as enum
  ('active', 'trial', 'grace', 'expired', 'revoked');

create type public.zone_kind as enum ('ocean', 'bay', 'lake', 'offshore', 'pier');

create type public.entry_kind as enum ('manual', 'adapter');

create type public.condition_kind as enum
  ('tide', 'buoy_obs', 'marine_forecast', 'alert', 'sst', 'chlorophyll',
   'current', 'swell');

create type public.intel_status as enum
  ('pending', 'approved', 'rejected', 'needs_clarification', 'expired');

create type public.report_origin as enum ('angler', 'intel');

-- ---------------------------------------------------------------------------
-- Generic updated_at touch
-- ---------------------------------------------------------------------------
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function app.touch_updated_at() from public;

-- ---------------------------------------------------------------------------
-- Role registry
-- ---------------------------------------------------------------------------
create table public.user_roles (
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.app_role not null,
  granted_by uuid references auth.users (id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

alter table public.user_roles enable row level security;

revoke all on table public.user_roles from public;
revoke all on table public.user_roles from anon, authenticated;
grant select on table public.user_roles to authenticated;
grant select, insert, update, delete on table public.user_roles to service_role;

create or replace function app.is_operator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role in ('operator', 'admin')
  );
$$;
revoke execute on function app.is_operator() from public;
grant execute on function app.is_operator() to anon, authenticated, service_role;

create policy user_roles_select_own on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or app.is_operator());

-- ---------------------------------------------------------------------------
-- Profiles
-- default_privacy is intentionally NOT column-granted to the API roles:
-- read it through app.my_default_privacy(), change it through
-- public.set_default_privacy(). Privacy prefs are user-scoped data.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  handle          text not null check (handle ~ '^[A-Za-z0-9_]{3,24}$'),
  display_name    text check (display_name is null or char_length(display_name) <= 60),
  default_privacy public.report_privacy not null default 'general',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create unique index profiles_handle_lower_key on public.profiles (lower(handle));

alter table public.profiles enable row level security;

revoke all on table public.profiles from public;
revoke all on table public.profiles from anon, authenticated;
-- Public directory columns only. default_privacy is excluded on purpose.
grant select (id, handle, display_name, created_at) on public.profiles to anon, authenticated;
grant update (handle, display_name) on public.profiles to authenticated;
grant select, insert, update on table public.profiles to service_role;

create policy profiles_select_all on public.profiles
  for select to anon, authenticated
  using (true);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create trigger profiles_touch
  before update on public.profiles
  for each row execute function app.touch_updated_at();

-- Auto-create a profile for each new auth user. Guarded: if the project
-- forbids triggers on auth.users, fall back to public.ensure_profile().
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, handle)
  values (new.id, 'angler_' || substr(replace(new.id::text, '-', ''), 1, 12))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function app.handle_new_user() from public;

do $$
begin
  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function app.handle_new_user();
exception when others then
  raise notice 'Could not attach trigger to auth.users (%). Clients should call public.ensure_profile() after sign-in.', sqlerrm;
end;
$$;

create or replace function public.ensure_profile()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  insert into public.profiles (id, handle)
  values (v_uid, 'angler_' || substr(replace(v_uid::text, '-', ''), 1, 12))
  on conflict (id) do nothing;
  return v_uid;
end;
$$;
revoke execute on function public.ensure_profile() from public;
grant execute on function public.ensure_profile() to authenticated;

create or replace function app.my_default_privacy()
returns public.report_privacy
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select default_privacy from public.profiles where id = auth.uid()),
    'general'::public.report_privacy
  );
$$;
revoke execute on function app.my_default_privacy() from public;
grant execute on function app.my_default_privacy() to authenticated;

create or replace function public.set_default_privacy(p_privacy public.report_privacy)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  update public.profiles set default_privacy = p_privacy where id = auth.uid();
  if not found then
    raise exception 'Profile not found; call ensure_profile() first';
  end if;
end;
$$;
revoke execute on function public.set_default_privacy(public.report_privacy) from public;
grant execute on function public.set_default_privacy(public.report_privacy) to authenticated;
