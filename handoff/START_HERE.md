# PROJECT OFFINGCUE HANDOFF // START HERE

Updated 2026-07-29. This package is self-contained and does not require GitHub access.

## Read in this order

1. `project-manifest.json` — authoritative machine-readable project state and complete migration payload
2. `HANDOFF.md` — human-readable product state, decisions, risks, and next action
3. `SUPERSEDED.md` — old SluggFishing decisions that must not be treated as current
4. `docs/product-reset-architecture.md` — architecture, data rights, roadmap, and connection matrix
5. `docs/tommy-review-sheet.md` — partner review worksheet
6. `preview/offingcue-preview.html` — latest interactive web preview source
7. `scaffold/` — historical SwiftUI, Supabase, and seed-data scaffold requiring reset before production

## First message to the receiving Hyperagent

Paste this after uploading the zip:

> Read START_HERE.md, then parse project-manifest.json as the authoritative state, then read HANDOFF.md and SUPERSEDED.md. Confirm the latest working identity, pricing, geography, moderation policy, connected versus staged systems, open gates, and exact next action. Do not use old SluggFishing decisions unless the current handoff explicitly preserves them. Do not create a GitHub repository or begin a major native build until I approve.

## Current truth in one paragraph

Project OffingCue is the neutral working codename for a San Diego fishing decision system. The latest deliverable is a responsive HTML preview with live Open-Meteo model swell, water temperature, and current data; animated current vectors; animated wavefronts; waypoint and boundary previews; report privacy; Catch Prints; Dock Totals; regulations; pricing; and operator workflows. Most production systems are not connected yet. The recommended next technical connector is Supabase/PostGIS/RLS/auth, but major native work remains gated by the 50-50 operating/IP agreement and source permissions.

## Package rules

- `project-manifest.json` wins if another file conflicts.
- `historical/sluggfishing-app/` is reference history, not current product truth.
- The public preview link is `https://hyperagent.com/s/WtwpIqoVY0OA442wmEv6Bw`.
- No credentials or secrets belong in this package.
- Public-reference waypoint coordinates and maritime lines are not production navigation data.
