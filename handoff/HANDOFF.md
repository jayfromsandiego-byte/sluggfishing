# PROJECT OFFINGCUE // AUTHORITATIVE HANDOFF

Updated 2026-07-29. The root `project-manifest.json` is the machine-readable source of truth. This document is the human-readable companion.

## Product

Project OffingCue is the neutral working codename for an all-in-one San Diego fishing intelligence product. It helps an angler decide where to fish, whether conditions are workable, what is being caught, and what is legal. The final brand is not yet cleared.

Partners:
- Jay — backend, engineering, automation, landing page, ads, infrastructure, and technical operations
- Tommy — fishing shop owner, fishing-domain expert, design/content approval, distribution, partner network, and waypoint verification

Recommended legal structure: a new 50-50 app LLC with an operating agreement and IP assignments. A DBA under only Tommy's existing company does not establish Jay's equal ownership.

## Defensible bundle

Protect these in every tradeoff:

1. Captain-verified permanent waypoints with real coordinates and version history
2. Offline spot pages, rules, and map packs that remain useful with zero signal
3. Human-moderated reports with exact, general approximately 1 km, or zone-only privacy enforced in PostGIS/RLS
4. The stocking plus AIS bundle, strengthened by landing counts and local human intel

Dock Totals remains the fish-count interface. Catch Print remains the earned proof-of-catch artifact. Free contribution and privacy are never paywalled.

## Current decisions

Identity:
- Current working codename: Project OffingCue
- SluggFishing is superseded as the customer-facing app name
- Dock Totals and Catch Print are preserved mechanics
- Final trademark clearance remains open

Geography:
- Deep launch coverage: San Diego ocean/coastal waters; Miramar; Poway; San Vicente; Dixon; Barrett
- Los Angeles is removed from the current roadmap
- East County, Riverside, and tribal waters require validation or partnership before deep build

Pricing:
- Free tier: baseline map, public waypoints, current approved reports, daily counts, current rules, privacy controls, Catch Prints
- Pro: $9.99/month or $99/year
- Conversion copy: upgrade within 30 days and the first $9.99 counts toward annual
- The free tier never shrinks

Moderation:
- Reports never auto-publish
- 60 minutes: remind primary reviewer
- 90 minutes: route to backup reviewer
- 120 minutes: expire from freshness queue, remain a draft
- Exact source geometry is stored but never served contrary to the angler's privacy choice

Conditions stack:
- V1 preview: Open-Meteo Marine model data
- V1 production recommendation: NOAA CO-OPS, NDBC, NWS, NOAA ENC, NOAA CoastWatch, CDFW, commercial Open-Meteo plan
- Windy is not a V1 dependency; its Map API is a later paid evaluation
- NOAA WCOFS is the preferred production current-nowcast source when its model-data access is available

## Latest preview

Source: `preview/offingcue-preview.html`
Public review URL: https://hyperagent.com/s/WtwpIqoVY0OA442wmEv6Bw
Original Hyperagent artifact ID: cmrtnt3nb063m07ad47e1r12b
Latest recorded artifact version: 11

Implemented in the preview:
- Responsive desktop and 390-pixel mobile layouts
- Home, Map, Reports, Dock Totals, Regulations, You/Pricing, and Operator pages
- Esri Ocean basemap with GEBCO/NOAA attribution
- Live Open-Meteo model swell, water temperature, current velocity, and current direction
- Animated ocean-only current vectors with arrowheads and moving dash flow
- Animated ocean-only curved swell wavefronts driven by model height, period, and direction
- Swell direction converted from coming-from direction into visible travel direction
- Map status with source, model time, and grid/vector count
- Water crosshair paths for swell height/period or current velocity/heading
- Cached model fields when preview is toggled offline
- Public-reference waypoint numbers and freshness encoding
- U.S.-Mexico boundary and Mexico 12 NM preview overlays
- Exact/general/zone report privacy selector
- Privacy-correct pending Catch Print
- Sample Dock Totals, sourced regulation cards, pricing, source-health, and moderation-queue surfaces

Important truth: model data is guidance, not measured truth and not suitable for navigation.

## Connected versus staged

Connected in preview:
- Esri Ocean map tiles
- Open-Meteo model swell, water temperature, current velocity, and current direction
- Live model wave and current fields
- External official reference links
- All local preview UI interactions

Reviewed static official data:
- Three CDFW species regulation cards with official source links

Staged/sample:
- Community and Joseph reports
- Landing counts and fleet marks
- Tide and NWS alert summaries
- Operator queue and source health
- Purchases, offline-pack size, alerts, and account data
- Public-reference coordinates and maritime geometry

Not production-connected:
- Supabase/PostGIS/RLS/auth/storage
- Telegram webhook and Joseph source agreement
- Landing/lake adapters and permission registry
- Automated CDFW regulations/stocking ingest
- NOAA CO-OPS/NDBC/NWS/WCOFS production pipelines
- Mapbox iOS offline packs and GRDB mirror
- RevenueCat/App Store/web entitlements
- Push notifications, analytics, and production admin authentication

## Source-rights finding

Using a landing's domain does not guarantee the landing owns the published feed. Seaforth credits Sportfishingreport.com; Fisherman's credits SanDiegoFishReports.com. Automated production ingestion remains blocked until permission or source terms are documented. Store normalized facts only; never republish source prose or images without a license.

## Waypoint and boundary status

Public-reference coordinates in the preview are not production navigation data. Tommy or an approved captain must verify the exact mark, chart datum, alias, and source. Rockfish 32 and Pyramid Head remain unresolved. “Lohue Canyon” was normalized to La Jolla Canyon and “Tana Bank” to Tanner Bank pending Tommy confirmation.

Maritime boundaries in the preview are illustrative. Production must use current official NOAA and Mexican sources and remain labeled not for navigation.

## Current blockers and gates

P0:
1. Sign or replace the 50-50 operating/IP agreement before major native production work
2. Obtain source permissions for landing/lake feeds before automated ingestion
3. Obtain captain verification for production waypoint coordinates
4. Finalize a legally cleared neutral brand before paid launch media

Technical next action after Jay approval:
- Build Supabase migrations, PostGIS geography, RLS privacy policies, auth, and moderation audit foundation
- Then connect NOAA conditions and official boundary layers
- Then build real reports and operator queue

## Validation already completed

- Original package integrity and manifest references passed
- Preview JavaScript syntax passed
- Open-Meteo multi-location wave and current requests returned live data
- Desktop and 390-pixel mobile render passed
- Swells to Currents and Currents to Swells switching passed
- Offline cached model status passed
- Privacy selection correctly propagates to Catch Print
- External links include safe target/rel attributes

## Do not do on boot

- Do not revive SluggFishing as the product name
- Do not restore Los Angeles to MVP
- Do not restore the old $2.99/$19.99 ladder
- Do not auto-publish reports
- Do not call model guidance measured truth
- Do not ingest competitor content or third-party source prose
- Do not publish unverified coordinates
- Do not create a GitHub repository unless Jay asks
