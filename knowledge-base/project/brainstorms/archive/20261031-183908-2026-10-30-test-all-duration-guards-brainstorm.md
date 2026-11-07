---
date: 2026-10-30
topic: test-all-duration-guards
issue: 11662
branch: feat-11662-test-all-duration-guards
lane: cross-domain
brand_survival_threshold: single-user incident
---

# #11662 — test-all duration budgets + selection caps (anti-regrow guards)

## What We're Building

The local `scripts/test-all.sh` battery regressed from a ~20–60 min experience to ~3 h
wall-clock (issue measured 2026-10-30: 704 registrations, ~121 min serial committed weight,
~3 h observed on the operator's host). The issue proposes eight checks and balances;
premise validation (below) found several already shipped. The surviving deltas, staged per
operator decision:

**This PR — anti-regrow guards on committed weights** (the "can't regrow silently" half):

1. **Aggregate drift gate in `regenerate-shard-manifest.py`** — refuse `--write` when a
   per-suite weight jump or total-corpus growth exceeds a threshold (measured rows only;
   `--allow-growth` escape). Today every refusal is a shape check; nothing gates weight.
2. **Whole-battery per-suite committed-weight budget** — extend the fast-tier pattern
   (`test-all-fast-tier-budget`, committed weights, value-pinned caps) beyond
   `ALWAYS_ON_SUITES` to the corpus, with an exemptions ledger. Never wall-clock — the
   tradeoff is recorded: *"a wall-clock budget would flake; a committed-weight budget
   cannot"* (`test-all-fast-tier-budget.test.sh:13`).
3. **Always-on count ceiling + why-always-on ledger** — ceiling expressed as
   `live_floor + N` (the floor is derived, not static). Justification lives in a sidecar
   TSV, never in `test-affected-paths.sh` comments — an added comment line is an
   INDEX-ANCHOR finding that degrades `--affected` to the full battery.
4. **Dead-registration census** — extend `lint-orphan-test-suites` with the
   registration→file direction: a `run_suite ... bash <path>` whose target vanished is
   invisible statically today (dropped by `comm -12`, loud only at runtime).

**Follow-on issue (post-#11561) — full-battery usability**: watch/soak scheduled tier,
meta-suite cost, queue-timeout→exit-4 for `--full`, ceiling default-on, parallel-default
revisit after #7376.

## Premise validation — what the issue got stale

| Proposal | Live state |
|---|---|
| #7 "no runner lock" | Stale — `tc_acquire` advisory lock exists (ADR-133); ship recipe's `TC_LOCK_TIMEOUT=14400` + queue-timeout→`LOCK_CONTENDED_PROCEEDING` explains the 4 h co-run |
| #6 "fixed n=3" | Stale — manifest is n=8, duration-aware sticky-LPT (ADR-240) |
| #3 ratchet ceiling | Partially exists — 10 s/suite + 300 s total committed-weight cap on always-on only |
| #1 per-suite budget | Advisory only — one `_suite_budget_ms` entry; `TC_RUNTIME_CEILING_S` is whole-run, disabled-by-default |
| #4 nightly tier | Precedent exists (`scheduled-integration-suites.yml`) but vitest-only; no bash-suite home |
| #8 dead census | `lint-orphan-test-suites` covers file→registration; registration→file gap confirmed |
| #2 drift gate | `WEIGHT_DRIFT` emits warn-only lines; generator never gates |

## Why This Approach

- **Committed-weight enforcement is the house-sanctioned shape** — converged by all three
  leaders + learnings corpus: CI weights don't flake, wall-clock kills do (load moves
  suites ~1.9–2.4×). Drift gating happens at the one chokepoint where weight enters the
  tree (regeneration).
- **Guards-first staging** matches the operator's "both, staged" answer and avoids the two
  highest-entanglement items (demotion's 7th-registration-surface + live-floor-lint
  coupling; meta-suite shallow mode's row-tiling requirement) while #11561 is unmerged.
- **Blast radius**: guards land mostly in `regenerate-shard-manifest.py`, `lint-orphan`,
  and sidecar TSVs — not inside `test-all.sh` (7,729 lines, ~368 `run_suite` sites; every
  edit triggers `AFFECTED_FALLBACK reason=runner-changed` → pays the full battery).
- **Coordination**: #11648 owns fast-tier drift demotion; #11564 owns the balance-watch
  probe; TSV regen churn collides with the live `feat-11556-required-check-time` worktree —
  land this PR first (smaller), cross-link both.

## Key Decisions

| Decision | Detail |
|---|---|
| Scope | New deltas only — lock-upgrade and shard-scaling deferred (ADR-133 recorded rejection; manifest already n=8) |
| Enforcement unit | Committed weights from `suite-durations*.tsv`; per-suite cap = `max(default, k×committed_weight)`, exemptions ledger for declared-big suites |
| Staging | Affected-tier guards in this PR; full-battery usability as a follow-on issue filed at brainstorm end |
| Watch/soak demotion | Deferred to follow-on — needs a new scheduled leg + selection-decline class + `suite-shard-legs.tsv`/orphan-lint parity in one commit |
| Meta-suite shallow mode | Deferred — must keep ≥1 full-corpus arm (ordinal-map property exists only at corpus scale); cheap adjacent win: relevance-gate `test-all-infra-coverage-notice` |
| Lock | Deferred — ADR-133 rejects abort-on-timeout; sanctioned delta is queue-timeout→exit-4 for `--full` + ceiling default-on (follow-on) |
| Legal protected set | ~10 legal-control suites (TOM-4 RLS, PA-22, lint-legal-*, art30, dpa-register, gdpr-gate-glob-liveness) exempt from census removal and demotion — CLO requirement |
| Coordination | Cross-link #11648, #11564; land before the #11556 worktree's TSV regen |

## Open Questions

1. Whether the 3 h run's log carried `LOCK_QUEUE_TIMEOUT`/`LOCK_CONTENDED_PROCEEDING` and
   `TC_LOCK_TIMEOUT=14400` (ship recipe) — pins the queue-wait vs execution split; the 4 h
   figure matches the recipe exactly. *(parked — the run's log is not retrievable; the
   mechanism is confirmed either way)*
2. Exact drift-gate thresholds (per-suite jump %, total growth %) — plan-time decision on
   measured distribution.
3. Whether `why-always-on` sidecar is `label|reason` TSV or a per-suite-declared token —
   plan-time; needs a keys-parity lint either way.
4. Follow-on sizing: does the watch/soak scheduled leg reuse `main-health-monitor.yml`'s
   Inngest-dispatched sharded legs or `scheduled-integration-suites.yml`'s GHA shape?

## User-Brand Impact

- **Artifact:** the local `scripts/test-all.sh` battery and the pre-commit hook that runs it.
- **Vector:** a gate too slow to run trains `--no-verify`, which strips every hook
  (secret-scan, skill-security-scan) — a real regression or a credential reaches a PR
  unseen. Worst case for the named artifact is bypass habituation, not data exposure.
- **Threshold:** `single-user incident` (auto, per #5175). CPO assessment: does not meet
  the end-user threshold — meets its internal analogue (measured: 4 `--no-verify` bypasses
  on PR #7866; staged-scope exists precisely because commits crossed the ceiling).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Internal machinery; the gate's product value is already ~zero at 3 h — a
bypassed gate costs wall-clock while producing false confidence. The ~3 h is queue +
fallback degradation, not just suite weight. Ranked: drift gate first (highest value/lowest
risk), demotion paired with census, committed-weight per-suite budget over wall-clock,
`--jobs=auto` docs nudge as a missed cheap lever. Sibling epic to #11556; share the
durations substrate, land this first to avoid TSV regen collisions.

### Legal

**Summary:** No legal blockers. One planning constraint: a named set of legal-control
suites cited as evidence in DPAs/Art. 30 records is protected — exempt from census removal
and blocking-path demotion; exceptions route to soleur:legal:clo. GDPR gate not required —
no regulated-data surfaces.

### Engineering

**Summary:** Genuinely new: drift gate, count ceiling (as `live_floor+N`), registration→file
census, per-suite enforcement. Already built: advisory lock, n=8 manifest, fast-tier weight
cap, whole-run ceiling. Hottest file in repo — a new verdict class must be additive;
two ADR candidates flagged (enforced per-suite budget; queue-timeout→refusal as ADR-133
addendum). Demotion is the weakest cost-benefit and most entangled piece.
