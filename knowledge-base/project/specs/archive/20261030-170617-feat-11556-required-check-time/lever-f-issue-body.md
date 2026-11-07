Deferred from #11556 during brainstorm on 2026-10-29 (Lever F placeholder — commitment device per CPO).

Mandated-By: wg-when-deferring-a-capability-create-a

## What was deferred

Epic #11556's Lever F — "our users' CI": ship a reference CI layout in the plugin (sharding by measured time, affected-test selection with full battery in the merge queue, caches, fail-fast ordering) and have `soleur:ship`/`soleur:preflight` recommend it when a user's required-check wall-clock exceeds a budget; make the affected-test gate contract usable in a user repository without our test runner; document the budget and how it is measured.

## Why deferred

The epic's internal levers (A–E) come first; F is a commitment device so the epic's "for our users" half survives A landing. CPO flag: `plugins/soleur/scripts/affected-tests.sh` is already built for "ANY repository" (stack adapters + `.soleur-test-gate.json` contract) — verify what "usable without our test runner" still lacks before sizing this. Also open: no mechanism today observes a user's CI wall-clock on self-hosted/BYOK installs — F's trigger ("when a user's required-check wall-clock exceeds a budget") needs a measurement story.

## Re-evaluation criteria

When the epic's internal p90 lands ≤ ~30 min and remains stable, or when a second alpha user reports CI-time friction — whichever first. Epic: #11556. Brainstorm: `knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md`.
