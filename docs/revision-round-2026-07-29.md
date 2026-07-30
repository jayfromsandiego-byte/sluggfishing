# Revision Round — 2026-07-29 (map accuracy · nav restructure · reports consolidation · offline research)

Applied to the live build (`app/index.html`). The SwiftUI scaffold is untouched; this spec transfers 1:1 when the native phase starts (post partnership gate).

## 1. Map data accuracy — sources

**Boundaries (official, cited):**
- Source: NOAA **US Maritime Limits & Boundaries v4.1**, maritimeboundaries.noaa.gov ArcGIS MapServer, retrieved 2026-07-29.
- 12 NM Territorial Sea: layer 1, BOUND_ID B0148 — legal authority *Presidential Proclamation No. 5928 (Dec 1988)*. 94 vertices clipped to the operating region.
- US/Mexico maritime boundary: layer 3, chained segments **B0053 → B0051 → B0057 → B0052** — legal authority *US/Mexico Maritime Boundary Treaty, 1970*. Starts at the land terminus 32.53428°N, -117.12467°W. 136 vertices.
- Rendering: US/MX = red 2.6px over white 6px casing (outer/inner stroke pair, reads at all zooms); 12 NM = white dash over dark casing. Both labeled with "· NOAA".
- Data embedded as `BOUNDARIES` const with source + retrieval date. Still marked **not for navigation**.

**Waypoints (geocoding audit):** every named destination re-resolved via the Google Geocoding API (place IDs recorded in-code). Corrections applied:
| Place | Status |
|---|---|
| Lake Poway, Miramar, San Vicente, Dixon, Barrett | Verified + corrected (Dixon & Barrett were MISSING — added; all 5 launch lakes now pinned) |
| Oceanside / Crystal / Imperial Beach piers | Verified + added |
| Ocean Beach Pier | Partially verified (geocoder returns the pier-entrance street address; pier extends seaward) |
| Oceanside Harbor, Shelter Island launch | Verified + corrected |
| La Jolla Cove, Mission Bay, Coronado Is., San Clemente Is. | Verified + corrected |
| **Del Mar "pier" (old sample pin)** | **REMOVED — no such pier exists. Audit catch.** |
| Numbered offshore marks (43 Fathom, 115…302, Tanner, etc.) | **NOT geocodable** — not POIs in any places DB. Remain public-reference, pending captain verification per waypoint policy. |

Zoom behavior kept: numbers-only zoomed out; names fade in at zoom ≥10 (waypoints) / ≥9 (destinations).

## 2. Navigation restructure
- Bottom bar reduced to **Map · Reports · Species · AIS**. Post/Shop/Profile removed from bar.
- **Shop deleted from the build** (screen + tab + references). Profile lives in the menu.
- Top-bar controls (menu, notifications) moved to a **bottom-right Apple-Maps-style floating stack**: Search, Species Filter, Notifications, Menu.
- **Post button top-left** with My Location + Conditions. AIS chip removed (AIS is a tab), species-filter chip removed (dedicated button in the stack).
- New **Species tab**: searchable 30-species reference (art, latin, water, season, limit summary + verify-with-CDFW).

## 3. Reports & conditions consolidation
- Reports is now the primary destination: live conditions strip (swell/wind/next tide) + "Full Conditions →" at top of the Reports screen.
- Report filters: All · **Ocean** · **Lakes** · Hot Bite · Nearby. Lakes are first-class: dedicated filter, lake report seeds, and a CDFW fish-planting card linking the official schedule (wildlife.ca.gov/Fishing/Inland/Fish-Plants).
- **Government feeds, live + auto-updating (10-min cycle, stamped):**
  - Tides: **NOAA CO-OPS station 9410170 (San Diego)** official predictions — next-tide tile, full tide table, waypoint tide card.
  - Marine forecast: **NWS CWF product (SGX)** via api.weather.gov — official synopsis in Conditions.
  - Alerts: **NWS active alerts** by point — banner in Conditions.
  - Numeric model tiles remain Open-Meteo and are labeled model guidance (production plan: NDBC/CO-OPS ingestion server-side per architecture doc).
- Swell view optimized: **interactive 48-h swell chart** (drag to read ft / period s / direction), correct units, cached fetch.
- **Toggleable wind-lines overlay** on the map (Map Layers → Wind Lines): live wind field arrows colored by speed, mph labels, refreshed on the auto-cycle.
- Landing fish counts remain **sample-labeled**: automated landing ingestion stays blocked until source permissions are documented (P0 rights gate). Approved-sources-only rule enforced in the source registry schema.

## 4. Offline & tracking research (summary — full table in report)
- **GPS needs no connectivity** — iPhone GNSS is receive-only; ~4.9 m typical accuracy, better offshore. What breaks offline is tiles/feeds, not positioning. Satellite comms (iPhone 14+ Globalstar, Garmin inReach, Starlink) are a safety/comms layer, not positioning.
- **Offline tiles**: Mapbox iOS `TileStore` offline packs — $0 at 1k MAU (25k free MAU tier), 3–5 dev-days. MapKit and Google Maps SDK confirmed **no third-party offline API**. MapLibre+PMTiles is the $0 fallback (8–15 days). NOAA ENC charts convertible for a depth/hazard overlay.
- **Live tracking**: CoreLocation continuous + background mode + smoothing, fully offline on cached tiles, 4–6 days.
- **Bottom line**: ship Mapbox offline + live tracking (~7–11 person-days) in the native phase — matches the locked stack.

## Could not verify
1. Numbered offshore marks — no geocoding source exists; captain verification remains the gate (Rockfish 32 and Pyramid Head still unresolved with Tommy).
2. Ocean Beach Pier — entrance address only; seaward extent approximated.
3. Landing report feeds — rights not yet granted; counts stay sample until permissions are documented.
4. NWS marine zone id (PZZ775) returned 404 on the zones API — worked around via the official CWF/SGX product + point-based alerts (both live and official).
5. Point Loma kelp line — natural feature, not a geocodable POI; zone anchor unchanged.
