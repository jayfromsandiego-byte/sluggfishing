-- ============================================================================
-- OFFINGCUE FOUNDATION 0007 — self-verifying privacy posture
--
-- This migration contains no schema. It ASSERTS the security posture and
-- fails the deploy if any earlier migration (or manual change) weakened it.
-- Run it last, and re-run it after any future migration.
-- ============================================================================

do $$
declare
  offender text;
begin
  ------------------------------------------------------------------
  -- 1. No API role can enter app_private at all.
  ------------------------------------------------------------------
  if has_schema_privilege('anon', 'app_private', 'usage')
     or has_schema_privilege('authenticated', 'app_private', 'usage')
     or has_schema_privilege('service_role', 'app_private', 'usage') then
    raise exception 'POSTURE FAILURE: an API role has USAGE on app_private';
  end if;

  ------------------------------------------------------------------
  -- 2. No API role holds any privilege on the location vault tables.
  ------------------------------------------------------------------
  if has_table_privilege('anon', 'app_private.report_locations', 'select')
     or has_table_privilege('authenticated', 'app_private.report_locations', 'select')
     or has_table_privilege('service_role', 'app_private.report_locations', 'select')
     or has_table_privilege('anon', 'app_private.intel_payloads', 'select')
     or has_table_privilege('authenticated', 'app_private.intel_payloads', 'select')
     or has_table_privilege('service_role', 'app_private.intel_payloads', 'select') then
    raise exception 'POSTURE FAILURE: an API role can select from an app_private table';
  end if;

  ------------------------------------------------------------------
  -- 3. Every table in public has row level security enabled.
  ------------------------------------------------------------------
  select string_agg(c.relname, ', ') into offender
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity;
  if offender is not null then
    raise exception 'POSTURE FAILURE: RLS disabled on public tables: %', offender;
  end if;

  ------------------------------------------------------------------
  -- 4. No column named like exact geometry is reachable by API roles
  --    anywhere in the database.
  ------------------------------------------------------------------
  select string_agg(format('%s.%s.%s', n.nspname, c.relname, a.attname), ', ')
    into offender
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where a.attname ilike 'exact%'
    and a.attnum > 0 and not a.attisdropped
    and c.relkind in ('r', 'v', 'm')
    and n.nspname not in ('pg_catalog', 'information_schema')
    and (
      has_column_privilege('anon', c.oid, a.attname, 'select')
      or has_column_privilege('authenticated', c.oid, a.attname, 'select')
    );
  if offender is not null then
    raise exception 'POSTURE FAILURE: exact-geometry column reachable by API roles: %', offender;
  end if;

  ------------------------------------------------------------------
  -- 5. No API role can INSERT into reports directly (RPC only).
  ------------------------------------------------------------------
  if has_table_privilege('anon', 'public.reports', 'insert')
     or has_table_privilege('authenticated', 'public.reports', 'insert')
     or has_table_privilege('service_role', 'public.reports', 'insert') then
    raise exception 'POSTURE FAILURE: direct INSERT on public.reports is granted to an API role';
  end if;

  ------------------------------------------------------------------
  -- 6. The never-auto-publish guard and audit immutability triggers exist.
  ------------------------------------------------------------------
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'reports'
      and t.tgname = 'reports_guard_biu' and not t.tgisinternal
  ) then
    raise exception 'POSTURE FAILURE: reports guard trigger is missing';
  end if;

  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'moderation_actions'
      and t.tgname = 'moderation_actions_immutable' and not t.tgisinternal
  ) then
    raise exception 'POSTURE FAILURE: moderation audit immutability trigger is missing';
  end if;

  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'waypoint_versions'
      and t.tgname = 'waypoint_versions_immutable' and not t.tgisinternal
  ) then
    raise exception 'POSTURE FAILURE: waypoint version immutability trigger is missing';
  end if;

  ------------------------------------------------------------------
  -- 7. The vault-reading derivation function is not executable by
  --    any API role.
  ------------------------------------------------------------------
  if has_function_privilege('anon', 'app.compute_display_geom(uuid, public.report_privacy)', 'execute')
     or has_function_privilege('authenticated', 'app.compute_display_geom(uuid, public.report_privacy)', 'execute')
     or has_function_privilege('service_role', 'app.compute_display_geom(uuid, public.report_privacy)', 'execute') then
    raise exception 'POSTURE FAILURE: compute_display_geom is executable by an API role';
  end if;

  raise notice 'Privacy posture verification: PASS (vault sealed, RLS universal, no exact-geometry exposure, publish gate armed)';
end;
$$;
