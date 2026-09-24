# Decision challenges — feat-one-shot-7761-flip-probe-post-cutover-answer-key

These are Taste decisions from the headless plan review (ADR-084) that were **not** auto-applied.
They are recorded here so they can be audited outside the session; `ship` renders this file into
the PR body.

---

## DC-1 — Keep the derived-boundary arm of the #7761 probe

**Date:** 2026-09-24
**Classification:** Taste (plan-review DHH finding 6)
**Source:** `knowledge-base/project/plans/2026-09-24-fix-7761-flip-rollout-probe-post-cutover-answer-key-plan.md` §Plan Review Disposition

### What the reviewer proposed

Delete the probe's telemetry-derived boundary arm: `mine_dt`, the pinned-digest parse, and the
derived-provenance cap in `verdict_fail`. That is about 130 lines plus about 12 tests. The argument
is that this plan commits the authoritative `.after` sidecar, which leaves the derived arm dead code
for the rest of the probe's life. Its derivation also lands on the wrong machine: `08:19:11Z` on the
replaced host, against a real replace at `19:36:32Z`.

### What the plan does instead, and why

The plan keeps the arm unchanged, apart from giving `DERIVE_WINDOW` its own `24h` default now that
`DRIFT_WINDOW` is removed. Three reasons:

- Deleting the arm widens a diff whose job is to re-key the answer key.
- The arm is the documented fallback if the sidecar is ever removed.
- Its tests pin #7695's provenance-cap work: a derived boundary must never FAIL.

Neither choice is unsafe. Keeping the arm costs code nobody will execute. Deleting it costs a
fallback that is unlikely to be needed before #7761 closes.

### Operator decision needed

Either accept, or ask for the deletion as a follow-up once #7761 closes and the probe retires.
