# SluggFishing App (working codename: Project OffingCue)

San Diego fishing intelligence and trip decision system. Two partners: Jay (technical) and Tommy (fishing domain, shop, distribution).

**Status: 2026-07-29.** UI build per the Jul 29 mockups + Supabase privacy foundation (schema-verified locally). No cloud environment is provisioned yet; the business/rights/waypoint/brand P0 gates in `HANDOFF.md` still apply.

## Repository map

| Path | What it is |
|---|---|
| `app/index.html` | Front-end build matching the Jul 29 UI mockups exactly (phone-frame web preview). Live Open-Meteo conditions; talks to the backend through a swap-in adapter (`BACKEND_CONFIG`): `mock` mode now, `supabase` mode when the cloud project exists. |
| `supabase/migrations/` | The privacy foundation, 7 migrations: PostGIS, roles/profiles, reports + three-tier location privacy (exact / general ~1 km / zone) with a sealed `app_private` vault, sources + rights kill switch, never-auto-publish moderation (60/90/120), regulations/conditions/entitlements, and a self-verifying privacy-posture migration. |
| `supabase/tests/00_local_shim.sql` | Emulates Supabase runtime (roles, `auth.uid()`) so everything runs on plain Postgres+PostGIS. Never run on Supabase. |
| `preview/offingcue-preview.html` | Prior neutral-brand product preview (v11 baseline, Dock Totals design system). |
| `handoff/` | Ground-truth handoff package docs: `HANDOFF.md`, `SUPERSEDED.md`, `project-manifest.json`, architecture, review sheets. **The manifest is authoritative.** |
| `scaffold/` | Historical SwiftUI/Supabase scaffold (reference only — requires reset before production). |

## Backend contract (what the UI speaks)

- `rpc submit_report(p_zone_slug, p_lat, p_lon, p_privacy, p_species_slug, ...)` — the ONLY way to create a report. Exact coordinates go straight to `app_private.report_locations`; a per-report random offset (300–1000 m) is drawn once and stored, so display points are stable (no averaging attacks) and never derivable from public data.
- `rpc set_report_privacy(report, level)` — the angler's choice, any time, any direction; display re-derives from the stored offset.
- `rpc moderate_report(report, action)` — named-operator approval. A trigger blocks `status → approved` on every other path, including table owner and service_role. **Reports never auto-publish.** SLA: 60 min remind → 90 min backup → 120 min expire (draft retained).
- `reports` — anon/authenticated see approved rows only; `display_geom` is server-derived; no exact-geometry column is reachable by any API role (asserted by migration 0007).

## Run the backend locally

```bash
createdb offingcue_test
psql -d offingcue_test -c "alter database offingcue_test set search_path = public, extensions, app;"
psql -d offingcue_test -v ON_ERROR_STOP=1 -f supabase/tests/00_local_shim.sql
for f in supabase/migrations/*.sql; do psql -d offingcue_test -v ON_ERROR_STOP=1 -f "$f"; done
```

Requires PostgreSQL 15+ with PostGIS. Migration 0007 fails the deploy if the privacy posture ever weakens.

## Deploy to Supabase (when approved)

1. Create the Supabase project (P1 gate — Jay's call, after the 50-50 agreement is acknowledged).
2. `supabase link` then apply `supabase/migrations/` in order (skip the local shim).
3. Point `BACKEND_CONFIG` in `app/index.html` at the project URL + anon key and set `mode:'supabase'`.
4. Schedule `run_moderation_escalations()` and `purge_intel_payloads()` with pg_cron.

## Open gates (do not bypass)

1. 50-50 operating/IP agreement — blocks major native production work and revenue.
2. Source permissions — blocks automated landing/lake ingestion (schema enforces this: sources cannot enable without documented rights).
3. Captain waypoint verification — public-reference numbers in the UI are **not for navigation**.
4. Final brand clearance — "SluggFishing" appears in this UI per the Jul 29 mockups; the recorded product decision (neutral brand pending trademark clearance) still stands for store identity and paid media. See `handoff/SUPERSEDED.md`.
