# Decision Challenges — feat-one-shot-dependabot-medium-low-batch

Pipeline context: one-shot → plan → deepen-plan (headless; no Task/agent spawn
capability in this harness, so no CTO/advisor consult could be executed. Rows
that would carry `pending - assumed` under technical-ruling-delegation.md are
classified `taste` — `technical-ruling-gate.sh` rejects unruled `technical`
rows, and each choice below is a verifiable mechanical default with a named
fallback rather than a fork requiring a binding ruling).

| Item | Class | Ruling |
|------|-------|--------|
| Blanket vs scoped `overrides` for `minimatch` in `apps/web-platform` — GHSA-g3hv-75wg-m249 names EVERY version `< 11.0.1` vulnerable and eight-plus parents pin `< 11`; scoped per-parent would enumerate today only | taste | Blanket `"minimatch": "^11.0.1"` — the advisory covers every installed major, so there is no legitimately-vulnerable-free old line a blanket would over-reach; any future addition resolving <11 is then caught at resolve time rather than by the drain sweep after the fact. Fallback: if a loaded call path breaks (the compat audit says none does), drop to per-parent scoped entries and dismiss any copy no compatible resolution can reach, with a tracking issue — the zod-residual precedent |
| Scoped vs blanket `overrides` for `glob` in `apps/web-platform` — GHSA-3g3m covers only `>=9.0.0 <=14.0.1`, not all majors | taste | Scoped `"rimraf": {"glob": "^14.0.2"}` + `"@sentry/bundler-plugins": {"glob": "^14.0.2"}` — matching the zod idiom; a blanket would drag a legitimately-fine glob<9 copy a future dep might pin |
| Fallback if the minimatch@11 override breaks a loaded call path (the callable-v3 callers are installed-but-unloaded per the audit) | taste | Default: scoped exclusion where the subtree is eliminable, else Dependabot `dismiss` (tolerable-risk, dev-only) + tracking issue — never silently leave the alert open and never keep a vulnerable copy the guard cannot see (the completeness sweep reds any watched-package major with no row) |
| `pen-cli` minimatch pin shape — exact `"11.0.1"` vs `"^11.0.1"` | taste | Exact `"11.0.1"`, matching the `undici: "8.12.2"` precedent for the engine-pinned lockfile; bump only after a green `engine-contract-probe.sh` |
| Split assessment trips the >=4-subsystem-roots threshold (`apps`, `plugins`, `scripts`, repo-root manifests) | taste | Single PR — the multi-root shape IS the deliverable (grouped bump per #11646/#11780; the merge queue merges one entry per ~50-min cycle so splitting multiplies the cost the batch avoids). Non-lockfile diff ~80 lines |
| Brand-survival threshold `none` for a security batch | taste | Declared `none` — the change removes advisory vectors and adds no data path; worst-case breakage (lint/vitest/build red under forced re-resolution) is revertible and suite-gated before merge, below the single-user-incident bar |
| `@hono/node-server` major-1 FLOOR_ANCHOR disposition after the 1.x line is evacuated | taste | Delete the anchor with a comment (GHSA-rmxm has no patched 1.x — the line is evacuated, not patched); the anchor's own check REDs on an anchor no row covers, so the delete is deliberate and documented rather than a silent drop |
| Pillow alert #302 disposition | taste | Verify-only — detail endpoint shows `state: fixed` (Pillow==13.0.0 merged via #11646); the drain guard is npm-lockfile-scoped so there is no pip row to ratchet; noted in the PR body per AC-11 |
