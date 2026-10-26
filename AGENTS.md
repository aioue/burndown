# AGENTS.md

Native Swift macOS 26 menu bar app, SwiftPM only (no `.xcodeproj`).

- `Sources/BurndownCore`: pure logic (rules, store, scheduler, expirer). Keep it UI-free and unit tested.
- `Sources/Burndown`: app shell (AppModel, watchers, toast panel, menu, settings).
- `make test` runs the Swift Testing suite; `make run` builds and launches the app bundle.
- Keep it event-driven and light: no polling loops, no image caches.
- Conventional commits (`feat:`, `fix:`, `docs:`...). No em-dashes in docs; use ` - `.
- `TODO.md` holds deferred ideas.
