* **Test behavior, not implementation:** assert outcomes (what’s shown/moved/deleted), not internal details.
* **Keep a testable core:** move app rules (next/prev, keep/trash/undo, year grouping, bulk-delete set) out of UI into small, pure components.
* **Deterministic tests via dependency injection:** use fakes for photo source, clock, and storage—no real Photos library, real time, or randomness in unit tests.
* **Small fixtures + edge cases:** cover tricky datasets (empty year, last item, missing metadata, duplicates, already-trashed items, asset removed).
* **Persisted state is covered:** trash/undo/indexing survive app restart; cache/schema versioning doesn’t break existing data.
* **Permissions & Limited Library are covered:** denied/limited/full access, permission changes while the app is running, graceful fallback.
* **Minimal UI smoke tests only:** 2–5 end-to-end flows (open → review year → swipe keep/trash → open trash → bulk delete confirm).
* **Add a regression test per bug:** every fixed bug gets a test so it can’t come back.
