# PROJECT OFFINGCUE // PRODUCT RESET, ARCHITECTURE, BRAND SCREEN, AND LAUNCH PATH

Portable export of Hyperagent document `cmrtnl66t05sl07adstsrr758`, version 3.

## Executive recommendation

Position Project OffingCue as the San Diego fishing decision system: one place to decide where to fish, whether the ride is workable, what is being caught, and what is legal.

Defensible bundle:
1. Captain-verified permanent waypoints with real coordinates and version history
2. Offline spot pages, rules, and map packs with zero signal
3. Human-moderated exact/general/zone report privacy enforced in PostGIS/RLS
4. Stocking plus AIS, strengthened by landing counts and local human intel

Build order:
- Now: neutral-brand page-by-page web preview
- Next: narrow San Diego TestFlight beta
- Later: East County, Riverside, tribal partnerships, AIS, Android, and deeper satellite history
- Not now: Los Angeles, patents, Windy production API, auto-published reports

Business gate: use a new 50-50 app LLC with operating agreement and founder IP assignments. Do not place finished app IP into a DBA owned through only one partner's existing entity.

## P0 and P1 audit

| Priority | Issue | Required resolution |
|---|---|---|
| P0 | Auto-publish after two hours | Never auto-publish; remind at 60, backup at 90, expire at 120 |
| P0 | Landing direct-source assumption | Obtain landing or publisher permission; facts only; manual fallback |
| P0 | AI rewording | Extract facts and create original factual digest; no images or source expression |
| P0 | App Store content rights | Maintain source-rights register and authorization file |
| P0 | Entity | New 50-50 LLC, deadlock rules, vesting, IP assignment, brand license, exit terms |
| P0 | Waypoint coordinates | Captain and current-chart validation before production publication |
| P0 | Mexican-water copy | Separate maritime boundary and 12 NM line; point to official authorities |
| P0 | Navigation liability | Official data, source/version, and not-for-navigation treatment |
| P1 | Neutral identity | Preserve Dock Totals and Catch Print; clear final mark before paid media |
| P1 | Pricing | Free never shrinks; Pro is $9.99/month or $99/year |
| P1 | Annual conversion | First $9.99 counts toward annual if upgraded within 30 days |
| P1 | Windy | Later paid evaluation; NOAA and commercial Open-Meteo for V1 |
| P1 | Geography | Deep launch in San Diego/coast plus five named lakes |
| P1 | Timeline | Web preview and narrow TestFlight first; Android/AIS/deep expansion later |
| P1 | Patent | Skip; prioritize trademark, data rights, contracts, and operations |

Product thesis: OffingCue tells a San Diego angler what the water is doing, what is being caught, and what is legal, with every mark sourced, every private location protected, and the trip plan available offline.

## Information architecture

Public:
- Home — Map and Reports first; conditions, latest intel, counts, rule alert
- Map — ocean/lake, NOAA chart context, boundaries, SST/chlorophyll, swell, current, wind, waypoints, freshness, crosshair
- Reports — source, trust, time, privacy, one-tap Map/Count links
- Dock Totals — landing, boat, trip, passengers, species, count, source, fetched time
- Regulations — species/region/method, dates, bag, size, gear, depth, official source, verify with CDFW
- You — offline packs, saved spots, alerts, privacy defaults, purchases, terms, support

Private operator:
- Approval Queue — reports, Telegram drafts, landing/lake facts, regulation changes
- Source Health — run status, parser, hash, unchanged interval, permissions, kill switch
- Waypoint Registry — coordinates, datum, alias, source, verifier, version history

Navigation: Home opens first. Mobile primary is Map, Reports, Count, Rules, You. Operator is access-controlled.

## Production architecture

Core stack:
- SwiftUI iOS 17+
- Mapbox iOS offline behind a map-provider abstraction
- Supabase Postgres, PostGIS, RLS, Storage, Auth, Edge Functions, scheduled jobs
- GRDB/SQLite mirror, versioned deltas, map packs, regulation snapshots, condition cache, report outbox
- RevenueCat for App Store and allowed web entitlements
- PostHog; operational alerts through email/Telegram initially

Execution planes:
1. Content — waypoints, lakes, species, regulations, counts, approved reports
2. Community — local-first reports, photos, EXIF stripping, privacy, moderation
3. Live — tides, observations, forecasts, advisories, cached/stale states
4. Ingest — source adapters, Telegram, health checks, rights registry, kill switches, fact extraction

Database additions:
- sources
- source_runs
- source_facts
- fish_counts and fish_count_items
- intel_drafts
- moderation_actions
- waypoint_versions
- regulation_versions
- condition_snapshots
- maritime_layers
- entitlements

Source adapter contract: fetch, extractFacts, validate, health. Empty or unchanged for 48 hours alerts. Never republish old data as fresh. Store normalized facts and response hashes, not source prose.

Conditions service merges NOAA CO-OPS, NDBC, NWS, and commercial Open-Meteo. Every response contains source, model, issued_at, valid_at, fetched_at, and is_stale.

Satellite/chart pipeline:
- NOAA CoastWatch ERDDAP SST/chlorophyll subsets
- Scheduled regional raster tiles plus compact value grid
- NOAA ENC display/MBTiles
- Official maritime data with version manifest
- Not-for-navigation treatment everywhere

Portability: migrations, seed scripts, environment templates, fixtures, and monorepo. No secrets in client code.

## Connection status as of 2026-07-21

Connected in preview:
- Esri Ocean tiles
- Open-Meteo model swell and water temperature
- Open-Meteo model current velocity and direction
- Animated current vectors and current crosshair path
- Animated curved swell wavefront field and swell crosshair path
- Official reference links

Animated current behavior:
- Ocean-only fetched grid
- Directional arrowheads and moving dash flow
- Model time and vector count
- Cached model field offline

Animated swell behavior:
- Ocean-only Open-Meteo grid
- 5 by 9 viewport sampling, typically about 25 cells
- Height, period, and coming-from direction fetched
- Direction converted by 180 degrees to travel direction
- Curved wave trains whose spacing, opacity, and speed are model-driven
- Model time and cell count
- Cached field offline

Reviewed static official data:
- Three CDFW species cards with official links

Staged/sample:
- Reports, landing counts, fleet marks
- Tide/NWS summary
- Operator queue/source health
- Purchases, alerts, offline-pack size
- Public-reference coordinates and maritime geometry

Not connected:
- Supabase/PostGIS/RLS/auth/storage
- Telegram webhook and Joseph agreement
- Source adapters and rights registry
- Automated CDFW ingest
- NOAA CO-OPS/NDBC/NWS/WCOFS production pipelines
- Mapbox/GRDB offline packs
- RevenueCat, notifications, analytics, admin auth

Truth statement: model data is real fetched model guidance, not measured truth or navigation data. NOAA WCOFS is the preferred production current-nowcast source when model-data access is available.

Recommended next connector: Supabase/PostGIS/RLS/auth.

## Telegram and moderation

Joseph flow:
1. Telegram message
2. Webhook stores short-retention inbound record
3. Parser extracts coordinates, species, time, facts, confidence
4. Region, duplicate, and safety checks
5. Default general approximately 1 km privacy
6. Original factual draft
7. Human sees source, facts, draft, privacy, agreement status
8. Named approve/edit/reject/clarify action
9. Privacy-safe publication with audit record

SLA: 60 remind, 90 backup, 120 expire. Never auto-publish.

Joseph agreement must cover compensation, content/coordinate license, confidentiality, safety, privacy, attribution, termination, and no publication guarantee.

## Data source decisions

| Source | Decision |
|---|---|
| NOAA CO-OPS | Use now |
| NDBC | Use now |
| NWS | Use now |
| NOAA ENC | Use now |
| NOAA CoastWatch | Use now |
| CDFW Open Data | Use now |
| CDFW pages/PDF | Use with human review |
| Open-Meteo Marine | Use after commercial subscription |
| Windy Map API | Later |
| Raw WaveWatch III | Later |
| Stormglass | Avoid for V1 |
| WorldTides | Avoid for San Diego |
| AISstream | V1.1 after terms confirmation |
| Landing pages | Permission gate |
| Lake sites/Instagram | Permission/manual-entry gate |

Landing-source finding: Seaforth and Fisherman's pages credit third-party publishers. Clear publisher/landing rights before ingestion.

## Neutral brand screen

Working codename: Project OffingCue. Not legal clearance.

Shortlist:
1. OffingCue — best fit, low exact collision in preliminary screen; review OFFING apparel filing
2. Saltspan — broad and short; SALT is crowded
3. Brinescope — clear intelligence position
4. OffingIndex — analytical, less consumer-friendly
5. Bightwise — Southern California story but higher BIGHT mark risk

Clearance sequence: USPTO similar marks, common-law web, app stores, domains/socials, trademark attorney, intent-to-use filing before paid media.

## Pricing and six-week path

Free: map, waypoints, current reports, Dock Totals, current rules, privacy, Catch Prints.

Pro: $9.99/month or $99/year; full playbooks, offline packs, alerts, SST/chlorophyll history, advanced crosshair/planning, stocking alerts.

Week 1 reset/chart proof; Week 2 map/conditions; Week 3 reports/counts; Week 4 rules/offline; Week 5 money/ops; Week 6 closed beta.

Budget facts: California LLC annual tax $800; Apple $99/year; domain about $12; production Open-Meteo from roughly $29/month; Windy Map API roughly EUR 990/year; post-launch infrastructure estimated $150–400/month before labor.

## Required safety copy

Map: NOT FOR NAVIGATION. Verify current official charts, GPS, weather products, and authorities.

Rules: Verify with CDFW before fishing. Rules can change in season.

Mexico: Verify current CONAPESCA, INM, consular, captain, and landing requirements. The app does not determine legal status.

Primary references are indexed in root `project-manifest.json`.
