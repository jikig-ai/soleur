# Tasks: Actions cache cap + rehearsal skip monitor

Plan: `knowledge-base/project/plans/2026-10-25-fix-release-cache-cap-and-skip-monitor-plan.md`. Two PRs; PR A and PR B are independent and can land in either order.

## Phase 1 — PR A: release cache (#10917)

- 1.1 Measure before changing: cache usage bytes and entries, latest release build and export durations, per-layer sizes, `:latest` manifest type. Record in the PR body.
  - 1.1.1 Settle which layer is the 776 MB one.
- 1.2 Local-registry proof of inline cache with `provenance: false` (toy two-stage Dockerfile). Record output, or state that Docker was unavailable.
- 1.3 Edit `.github/workflows/reusable-release.yml`: `cache-from` registry on `<image>:latest`, `cache-to: type=inline`, `provenance: false`, drop `scope=`, reword the Buildx and secret-safety comments.
  - 1.3.1 Update the stale gha-scope comment in `.github/workflows/ci.yml` (~L1173).
- 1.4 Add one regression assertion (no `type=gha`, `type=inline`, `provenance: false`) to an existing suite that parses `reusable-release.yml`.
- 1.5 Write `scripts/followthroughs/actions-cache-usage-10917.sh` (exit 0 under 8e9, 1 over, 2 on API failure).
- 1.6 Write ADR-299 (short, accepted) via `soleur:architecture`; re-check the ordinal against `origin/main`.
- 1.7 Open PR A with `Ref #10917`; state the cold first build and the revert path in the body.
- 1.8 Post-merge: add the follow-through directive to #10917 with `earliest=<merge date + 8d>`; run `soleur:postmerge` on the first release (AC8); check AC9 by the second release or 14 days.

## Phase 2 — PR B: skip monitor (#8856 + #10918)

- 2.1 Tests first: extend the `gh` stub in `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` (per-run logs, `--limit`, conclusions, call log); add the rate, early-stop, two-arms-one-run, none-observed, source-2 and rc 3 cases. Confirm they fail.
- 2.2 Probe: `LIST_LIMIT=40`, `OBSERVE_TARGET=20`, `BOUND_DENOM=20`; `break` at 20 observed; per-log `skip_runs`; verdict `skip_runs * BOUND_DENOM > observed`; within-bound PASS message.
- 2.3 Probe: escalation exits rc 3; add the rc 3 row to the header's exit-code contract.
- 2.4 Workflow: reword the `broken` body and the 0/1/2 contract comment for rc 3 and 126/127; replace the "image owed" text (L315).
- 2.5 Wiring case in `scripts/monitor-streak-state.test.sh` (or the suite that owns workflow wiring): extracted `case` blocks, rc 0/1/2/3/127.
- 2.6 Replace "pre-baked image owed" text in the probe and its tests; add the ADR-188 amendment (cut image, sampling change, bound now implemented).
- 2.7 Run `c4-count-parity.test.sh` and the C4 validation tests; read the three `.c4` files and confirm no C4 impact.
- 2.8 Open PR B with `Closes #10918` and `Ref #8856`.
- 2.9 Post-merge: dispatch the monitor, record verdict and `observed` on #8856 (AC11); close #8856 only once the monitor is honest.
