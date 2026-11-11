# Contributing to Slugg Fishing

Thanks for looking at the project. It is an early, single-maintainer preview. Jay Minakhom reviews changes. There is no separate review team and no turnaround promise.

## Run the preview

From the repository root:

```bash
python3 -m http.server 8080
```

Open [http://localhost:8080/app/](http://localhost:8080/app/).

Use a local server. Opening `app/index.html` as a file can block the weather requests and the location prompt.

## What to edit

| Change | Where |
|---|---|
| Name, colors, home port, demo profile, official links, empty Supabase URL | [`app/site.config.js`](app/site.config.js) |
| Spots, waypoints, piers, lakes, species notes, sample reports | [`app/index.html`](app/index.html) (`ZONES`, `WAYPOINTS`, `CATPINS`, `SPECIES_FULL`, and the `seed(...)` calls) |
| Database shape (not connected to a hosted project) | `supabase/migrations/` |

`app/site.config.js` is the brand config. The `:root` color block in `app/index.html` repeats the same defaults so the page still has its colors if that file fails to load. If you change a color, change it in `site.config.js`. That file wins when the page runs.

Keep the existing layout. A fork for another shop should look like the same app with different words, colors, and places, not a redesign.

## Before you open a pull request

- Describe what you actually changed. Do not write that the app finds fish, recommends times, or coordinates trips unless the code does that.
- Sample catches, boat names, profile counts, scores, and the "146 MB" offline-pack line are placeholders. Do not replace them with invented user numbers.
- Waypoint coordinates in the preview are public-reference marks. Leave the "not for navigation" wording in place.
- Regulation text in the species list is a summary. Do not present it as the official rule. Links should stay pointed at the agency pages in `site.config.js`.
- Do not commit API keys, service-role keys, passwords, or personal phone numbers or email addresses. The Supabase anon key field is for a public client key only, and it should stay empty until a project exists.

## Scope that is easy to review

The runnable UI is one HTML file. A good change is a bugfix, a config hook, or a small screen fix with a note on how you checked it in a browser.

`handoff/` is internal planning context. `scaffold/` is an older SwiftUI sketch and is not the running app. `preview/offingcue-preview.html` is an earlier web preview. Prefer `app/index.html` unless you are specifically fixing one of those.

## Reporting issues

Use the bug and feature templates. For a feature, check the Roadmap (planned) section of the README first.

Conduct reports go to the maintainer through GitHub, as described in [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Do not post private incident details in a public issue.
