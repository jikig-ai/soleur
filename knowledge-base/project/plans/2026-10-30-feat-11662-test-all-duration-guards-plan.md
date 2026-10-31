---
title: "feat: test-all anti-regrow guards — drift gate, corpus weight budget, always-on ceiling, dead-registration census"
date: 2026-10-30
slug: feat-11662-test-all-duration-guards
branch: feat-11662-test-all-duration-guards
issue: 11662
closes: 11662
type: enhancement
lane: cross-domain
requires_cpo_signoff: false
---

## Overview

The local `scripts/test-all.sh` battery regressed to ~3 h wall-clock and grew without a
guard. This plan ships the anti-regrow guard set on committed weights: an aggregate drift
gate at the regeneration chokepoint, a whole-corpus per-suite weight budget with an
exemptions ledger, an always-on count ceiling plus a machine-checked justification ledger,
and a registration→file dead-registration census.

## Research Insights

**Premise Validation (Phase 0.6).** Cited refs checked: #11662 OPEN (verified);
#11561 OPEN unmerged (carries the two dominant atomic suites — deferrals stand);
#11648/#11564 OPEN (coordination targets); ADR-133, ADR-240, ADR-242, ADR-276 read —
no proposal sits in a rejected-alternatives table under the committed-weight reframing.
Issue claims verified stale: "no runner lock" (tc_acquire exists, ADR-133), "fixed n=3"
(n=8 duration-aware), "no always-on cap" (10s/300s committed-weight cap exists).

**Property List.** P1: corpus duration weight cannot grow without an explicit ack.
P2: no suite's committed weight can exceed its budget without a recorded exemption.
P3: the always-on set cannot exceed a bounded headroom above its derived floor, and
every member carries a checked justification. P4: a registration pointing at a file
that no longer exists fails statically, not only at runtime.

**Cut List.** (a) Wall-clock per-suite `timeout` enforcement → P2 → committed-weight
budget already covers it without flake risk (`test-all-fast-tier-budget.test.sh:13`).
(b) Blocking runner lock → out of scope → `tc_acquire` exists; queue-timeout→exit-4
deferred to #11679 per operator decision. (c) Shard-count scaling → out of scope →
manifest already n=8 (ADR-240). (d) watch/soak nightly tier → deferred → #11679.
(e) Meta-suite shallow mode → deferred → #11679.

**Key files.** `scripts/regenerate-shard-manifest.py` (866 lines; `die` exit-2 refusal
shape exists; prints `total: {sum}ms` today, never gates). `scripts/suite-durations.tsv`
(`label<TAB>ms<TAB>src`, src∈measured|floor; light group, n=8 manifest sibling).
`scripts/test-all-fast-tier-budget.test.sh` (the sanctioned committed-weight pattern:
value-pinned caps, closed unmeasured allowlist, mutation arms M1–M3, anti-vacuity floor).
`scripts/lint-orphan-test-suites.sh` (1,374 lines; 6-surface census; derived live-floor
at :1104-1108; ALWAYS_ON staleness arm; file→registration direction complete, the
registration→file gap is real: `comm -12` drops dead paths silently). `scripts/test-all.sh`
(7,729 lines; `_MIN_ALWAYS_ON_DECLARED=115` floor at :4163; `run_suite` is the single
registration chokepoint; every edit pays `AFFECTED_FALLBACK reason=runner-changed`).

**Institutional learnings applied.** Committed-weight vs wall-clock tradeoff (fast-tier
header verbatim); ratchets need totality check on scan population + merge-base baseline +
ack-edit exemptions + exact-line registration pins; a guard that never fails is untested —
synthetic red+green fixtures mandatory; missing weight rows must red, not pass;
`why-always-on` must NOT live in `test-affected-paths.sh` comments (INDEX-ANCHOR
degradation → full battery).

**Related issues/PRs.** #11561 (atomic-suite split, unmerged — re-price TSVs after it
lands); #11564 (`ci-shard-balance-watch` — sibling drift probe, cross-link);
#11648 (always-on drift demotion — cross-link); #11679 (filed follow-on: usability half);
epic #11556 (sibling — CI required-check surface).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "committed weights cap only the always-on tier" | Confirmed — fast-tier-budget covers `ALWAYS_ON_SUITES` only | Corpus budget covers all `suite-durations*.tsv` rows |
| "nothing gates weight at regen" | Confirmed — all `die` refusals are shape checks | Add drift-gate refusal in regenerator |
| "registration→file gap" | Confirmed — `comm -12` in lint-orphan surface 1 drops dead paths | New census arm keyed on `run_suite` argv target |

## Scope Check

Ask→plan mapping: issue proposals 1→G2 (reframed committed-weight), 2→G1, 3→G3,
8→G4. Proposals 4/5/6/7 → deferred #11679 (operator-approved). No `inferred` items —
every phase maps to an issue proposal or a gate schema (Guard Contract, ADR, Observability).

## Implementation Phases

### Phase 1 — Regen-time drift gate (`regenerate-shard-manifest.py`)

Add a weight-drift refusal in the generator, evaluated before any `--write`:

- New flag `--allow-growth` (the documented escape); without it, `--write` refuses
  (exit 2, `die`) when EITHER: (a) any `src=measured` row's new weight exceeds
  `DRIFT_SUITE_FACTOR`× its committed weight (pinned literal, start 1.5×), OR (b) total
  measured weight grows more than `DRIFT_TOTAL_PCT` (start 10%) vs committed.
- Count growth (new registrations) is reported, never gated — suites legitimately accrete.
- Floor rows excluded from the drift comparison (estimates distort); a floor→measured
  transition is reported, not gated.
- Applies to `--incremental` and `--runs` modes alike; the check reads the committed
  `suite-durations*.tsv` at merge-base semantics (the file in-tree vs the table being
  written), not a moving remote.
- Mutation arms live in `plugins/soleur/test/regenerate-shard-manifest.test.sh` — the
  fixture seams (`--timings-dir`/`--registered-file`/`--manifest`/`--durations`) already
  exist; no new suite file needed for this guard.

### Phase 2 — Corpus weight budget suite + exemptions ledger

New `scripts/test-all-corpus-weight-budget.test.sh` mirroring the fast-tier pattern:

- Every label in `suite-durations.tsv` + `suite-durations-heavy.tsv` must have committed
  weight ≤ `CORPUS_SUITE_CAP_MS` (pinned, start 600_000) OR appear in
  `scripts/suite-weight-exemptions.tsv` (`label<TAB>cap_ms<TAB>reason`).
- A label with no duration row reds (unmeasured ≠ exempt — the #9763
  three-direction-closed allowlist shape for the ≤2 expected cases).
- Exemptions ledger is WORM-shaped: removing a line without removing the suite reds;
  caps can only be raised via ack-edit (the `INVENTORY_REMOVALS_ACK` precedent).
  Reuse `check_tier` (`test-all-fast-tier-budget.test.sh:50-101`) and the
  `KNOWN_UNMEASURED_ALWAYS_ON` three-direction-closed allowlist idiom. Seed the
  ledger from actual committed-weight violators only — `_suite_budget_ms` is a
  WALL-CLOCK budget, not commensurable; verify at work time (top-20 committed
  weights: nothing in the light/heavy tables exceeds 600s; the infra table's
  `workspaces-boot-unlock` 661500ms is the only in-scope day-one row — or empty
  ledger if infra stays out of scope).
- Registered in `test-all.sh` via one `run_suite` line + `ALWAYS_ON_SUITES` entry +
  `suite-durations.tsv` floor row (fast, pure TSV math — well under 10s). Auto-enrolled
  in `guard-vacuity-floor.test.sh` and `check_durations` keys==keys — anti-vacuity floor
  and conservation check are mandatory, not optional.

### Phase 3 — Always-on ceiling + why-always-on ledger

- New `scripts/always-on-justifications.tsv` (`label<TAB>reason`), keys-parity lint vs
  `ALWAYS_ON_SUITES` — every entry needs a justification row, checked the way durations
  keys-parity is checked today.
- Count ceiling in the new justifications suite (`scripts/always-on-ledger.test.sh` or an
  arm of an existing guard): `count(ALWAYS_ON \ live_named) ≤ NON_LIVE_CAP` — bounds
  *non-live* membership (~86 today), pinned `NON_LIVE_CAP=95` first-draft (calibrate at
  work time against `--enumerate-commands`). **NOT** `count ≤ live_floor + N` — spec-flow
  P0-2: live_floor ≈ 40–55 live-named registrations, so that form reds at birth
  (~120 ≤ ~70). `live_floor` itself is single-sourced from
  `lint-orphan-test-suites.sh:1104` — reuse or parity-pin the derivation, never
  re-implement (the "ask the producer" doctrine).
- **Coexistence with the existing band (must document, not duplicate):**
  `_MIN_ALWAYS_ON_DECLARED=115` + `test-all-affected.test.sh` row f1 already enforce
  `floor ≤ count ≤ floor+5` — that band bounds *pin-vs-list drift*. The new ceiling
  bounds *organic non-live membership* — a different property; the suite header must
  state the distinction and not re-implement f1's check. Escape is HEADROOM-ack
  (edit `NON_LIVE_CAP`), never a "floor bump" (the floor is derived).
- Interaction with #11648 (always-on demotion): the cap is sized against post-demotion
  membership only if #11648 lands first — declare the ordering at work time.
- Backfill the ~120 justification rows from existing provenance comments (#9307, #9763,
  Round-N audit notes) — mechanical extraction.

### Phase 4 — Registration→file dead-target census arm

Extend `scripts/lint-orphan-test-suites.sh` with surface 7:

- Extract every `run_suite "label" <interpreter> <path>` argv target from
  `scripts/test-all.sh` (bash/sh/python3/path-shaped forms); assert each target file
  exists (tracked or on disk). RED on registration→dead-target.
- Also covers `run_suite` argv forms with env-prefixes (`env FOO=1 bash x.sh`) — strip
  env-assign prefixes before extracting the path token — and the non-bash command
  shapes the `_aff_classify_runner_diff` grammar enumerates (`python3 -m`, `bun test`,
  `node --test`; `test-all.sh:2727-2730`).
- Reuse surface-1's extractor + `_tracked_member`/`_TRACKED_SET` — the missing piece is
  only the RED on dead `run_suite` targets, not a new arm family.

### Phase 5 — ADR + docs

- **ADR** (new, provisional next-free ordinal — verify `origin/main` at work time):
  "Committed-weight enforcement is corpus-wide; duration weight enters the tree only
  through a gated generator." Amendment context: extends ADR-242's always-on weight-cap
  precedent and ADR-240's generator-owns-the-ledger model. Alternatively expressed as an
  ADR-242 amendment if the ordinal is taken — decide at work time.
- Update the test-all runbook (`local-gate-parallel-mode.md` or sibling) with the guard
  behavior: what reds, what the `--allow-growth` escape is for, how to exempt.

## Files to Create

- `scripts/test-all-corpus-weight-budget.test.sh`
- `scripts/suite-weight-exemptions.tsv`
- `scripts/always-on-justifications.tsv`
- `scripts/always-on-ledger.test.sh` (name may consolidate into an existing ledger suite)
- `knowledge-base/engineering/architecture/decisions/ADR-<provisional>-committed-weight-enforcement-corpus-wide.md`

## Files to Edit

- `scripts/regenerate-shard-manifest.py` — drift-gate refusal + `--allow-growth`
- `plugins/soleur/test/regenerate-shard-manifest.test.sh` — drift-gate mutation arms
  (fixture seams exist)
- `scripts/lint-orphan-test-suites.sh` — surface 7 (registration→file)
- `scripts/test-all.sh` — `run_suite` registrations + `ALWAYS_ON_SUITES` entries only
  (minimal — every edit pays runner-changed fallback)
- `scripts/test-all-fast-tier-budget.test.sh` — possibly, only if Phase 3 folds in
  (decide at work time)
- `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` — guard docs

## Acceptance Criteria

- AC1: `python3 scripts/regenerate-shard-manifest.py --incremental --write` refuses with
  exit 2 when a fixture doubles one measured suite's weight; passes with `--allow-growth`.
- AC2: `scripts/test-all-corpus-weight-budget.test.sh` reds on a synthetic 700s-weight
  unexempted fixture; greens on the same weight with a ledger row; reds on a missing
  duration row outside the pinned allowlist.
- AC3: always-on ledger suite reds when a label is added to `ALWAYS_ON_SUITES` without a
  justifications row, and when `count(ALWAYS_ON \ live_named)` exceeds `NON_LIVE_CAP`
  without an explicit cap ack-edit.
- AC4: `lint-orphan-test-suites.sh` reds on a `run_suite` registration whose target file
  is deleted; greens when the file exists.
- AC5: Every new guard suite has ≥3 mutation rows (incl. one mutating the guard's own
  dispatch) and ≥1 must-pass non-canonical row, per `## Guard Contract`.
- AC6: The legal-control suite set is untouched: no TOM-4/PA-22/lint-legal/art30/
  dpa-register/gdpr-gate-glob-liveness registration is removed or demoted.
- AC7: New ADR committed; runbook updated; `Ref #11662` in PR body.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** (CTO, brainstorm carry-forward) Genuinely new: drift gate, count ceiling
(`live_floor+N`), registration→file census, corpus budget. Already built: advisory lock,
n=8 manifest, fast-tier weight cap, whole-run ceiling. `test-all.sh` is the hottest file —
edits minimized to registration lines; new verdict classes must be additive.

### Product

**Status:** reviewed
**Assessment:** (CPO, carry-forward) Internal machinery; ranked drift gate first —
committed-weight enforcement is the proven non-flaky shape. `--jobs=auto` docs nudge
noted as cheap relief; sibling epic to #11556 — land first to avoid TSV regen collisions.

### Legal

**Status:** reviewed
**Assessment:** (CLO, carry-forward) No legal blockers. One constraint (now FR5/AC6):
the named legal-control suite set is protected — exempt from census removal and
blocking-path demotion.

## User-Brand Impact

- **If this lands broken, the user experiences:** the local gate flakes (false-red a
  healthy suite) or stays silent (corpus regrows unguarded) — the operator is the user;
  a false-red trains `--no-verify`, stripping every pre-commit hook including
  secret-scanning.
- **If this leaks, the user's workflow is exposed via:** no data exposure — dev tooling;
  the residual vector is a guard that never fires, reading as coverage it isn't.
- **Brand-survival threshold:** none — CPO-ruled internal tooling, no end-user surface;
  the internal analogue (bypass habituation) is covered by AC5's anti-vacuity requirement.

## Observability

```yaml
liveness_signal:    # what: new guard suites registered + green in CI test-scripts leg / cadence: every merge / alert_target: ci.yml required `test` context / configured_in: suite registrations in test-all.sh
error_reporting:    # destination: suite [FAIL] output → CI check + local epilogue / fail_loud: yes (refusals are exit 2/[FAIL], never silent)
failure_modes:      # [
  {mode: drift-gate silently disabled (flag typo), detection: mutation arm drives synthetic weight-doubling red, alert_route: suite failure},
  {mode: exemption ledger swallows new suites (keys-parity drift), detection: parity lint vs duration TSV keys, alert_route: suite failure},
  {mode: vacuous harness (0 checked exits 0), detection: anti-vacuity floor + mutation of own dispatch, alert_route: suite failure}]
logs:               # suite stdout in CI logs + TEST_TIMING_LOG / retention: GHA default
discoverability_test:
  command: grep -c "allow-growth" scripts/regenerate-shard-manifest.py
  expected_output: ">=1"
```

## Architecture Decision (ADR/C4)

### ADR

New ADR (provisional next-free ordinal — re-verify against `origin/main` at work time;
sibling PRs claim ordinals concurrently): "Committed-weight enforcement is corpus-wide;
duration weight enters the tree only through a gated generator." Frames: extends
ADR-242's fast-tier weight-cap precedent corpus-wide, ADR-240's generator-as-ledger-owner
model gains a refusal path. If the design converges on an ADR-242 amendment instead
(always-on machinery stays in one record), decide at work time — the deliverable is a
committed record either way, never a follow-up issue.

### C4 views

No C4 impact. Enumeration checked: (a) no external human actor (operator-only dev
tooling); (b) no external system/vendor (all changes are in-repo scripts); (c) no new
container/data-store (TSV ledgers are repo files, not stores); (d) no
actor↔surface access-relationship change. `grep -c "test-all" model.c4` = 0 — the test
runner is not a modeled element; nothing exists to falsify.

### Sequencing

Not sequential — the decision is true on merge; ADR authored in this PR, `status: active`.

## Guard Contract

### Guard 1 — Regen drift gate

**Property.** Committed duration weight entering `suite-durations*.tsv` cannot exceed
the per-suite or total growth thresholds without an explicit `--allow-growth` flag.

**Assembly.** Every weight write flows through `regenerate-shard-manifest.py`'s
`--write` path (`--incremental` and `--runs` — the only producers of the committed
table; `write_durations_delta` + the `--runs` medians path are the chokepoints).
Consumers: every `test-all.sh` run, `_shard_selects`, CI matrix regen.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Double one `src=measured` row's weight in fixture durations | RED (per-suite factor) |
| M2 | Grow total measured weight +15% across rows | RED (total pct) |
| M3 | Same as M1 but pass `--allow-growth` | GREEN (escape honored) |
| M4 | Grow only `src=floor` rows 5× | GREEN (floors excluded) |
| M5 | Add 50 new registrations at baseline weight | GREEN (count growth reported, not gated) |
| M6 | Neuter the check: stub the comparison to always-pass | RED (own-dispatch arm — a fixture where drift exists MUST still red) |

**Anchor.** Thresholds are value-pinned literals in the suite file — a weakening edit
must change the pinned constant AND the fixture; the suite asserts the literal's value,
not its presence.

### Guard 2 — Corpus weight budget

**Property.** No registered suite's committed weight exceeds `CORPUS_SUITE_CAP_MS`
unless recorded in `suite-weight-exemptions.tsv`; no registration lacks a weight row.

**Assembly.** Keys of `suite-durations.tsv` ∪ `suite-durations-heavy.tsv` ∪
`apps/web-platform/infra/suite-durations.tsv` reconciled against the registration
population — `--enumerate` SUITE_REGISTRATION labels for the light+heavy groups
and `apps/web-platform/infra/run-registered-suites.sh --enumerate` for the infra
set (never `git ls-files`: durations keys are labels, not paths — R2). Exemptions
ledger is the single exemption surface.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Insert fixture suite with committed weight 700s, no ledger row | RED |
| M2 | Same + ledger row `cap=900s` | GREEN (exemption honored, cap respected) |
| M3 | Same + ledger row `cap=500s` | RED (exemption below actual weight) |
| M4 | Delete a suite's duration row, keep registration | RED (unmeasured ≠ exempt) |
| M5 | Remove a ledger line while suite stays at 700s | RED (WORM — can't un-exempt) |
| M6 | Stub the keys-parity reconciliation to skip one suite | RED (scan-population totality) |

**Anchor.** `CORPUS_SUITE_CAP_MS` is a pinned literal; the ledger is a committed file —
weakening requires editing both the cap and the ledger in one reviewed diff.

### Guard 3 — Always-on ceiling + justifications parity

**Property.** `count(ALWAYS_ON_SUITES \ live_named) ≤ NON_LIVE_CAP` (bounded
non-live membership — spec-flow P0-2; the `count ≤ live_floor + N` form reds at
birth), and every always-on label has a `why-always-on` row in
`always-on-justifications.tsv`.

**Assembly.** `ALWAYS_ON_SUITES` array in `scripts/lib/test-affected-paths.sh` (the one
declaration site — index-sourced, not text-scraped); `live_floor` derived via the
lint-orphan formula (`*-live` registrations + declared edges); justifications TSV is the
single justification surface.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Add label to `ALWAYS_ON_SUITES` without a justifications row | RED (parity) |
| M2 | Add label + justifications row, non-live count at NON_LIVE_CAP boundary | GREEN at ≤, RED at > |
| M3 | Add `*-live` suite raising derived floor | GREEN (live members don't consume non-live headroom) |
| M4 | Empty the justifications file | RED (parity) |
| M5 | Gut the live-named derivation to return 0 | RED (own-dispatch) |
| M6 | Rename an always-on label, update TSV but not array | RED (set-identity, not cardinality) |

**Anchor.** `NON_LIVE_CAP=95` pinned (calibrate at work time); justifications keys
parity is two-directional — a weakening requires editing array + TSV + suite in
one diff. Coexistence: `_MIN_ALWAYS_ON_DECLARED=115` + f1 already enforce
`floor ≤ count ≤ floor+5` (pin-vs-list drift); this cap bounds organic non-live
membership — the suite header must state the distinction and not re-implement f1.

### Guard 4 — Registration→file census arm

**Property.** Every `run_suite` registration's command target exists on disk — a dead
registration fails statically, not only at runtime (rc 127).

**Assembly.** `run_suite` argv extraction across `scripts/test-all.sh` (all ~368 call
sites — the single registration chokepoint); argv shapes: `bash <path>`, `sh -c`,
`python3 <path>`, `env VAR=v bash <path>`.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Register `run_suite "x" bash deleted.test.sh` in fixture | RED |
| M2 | Register `run_suite "x" env FOO=1 bash exists.test.sh` | GREEN (env-prefix stripped) |
| M3 | Register `run_suite "x" bash exists.test.sh` | GREEN (canonical pass) |
| M4 | Neuter the argv extractor to return empty | RED (own-dispatch vacuity) |
| M5 | Target is a directory under an interpreter-class argv0 (`bun test plugins/soleur/`) | GREEN (R7 — directories are legitimate interpreter operands) |
| M5b | Target is a directory under a non-interpreter argv0 | RED (file, not dir) |

**Anchor.** Population derived from the registration stream itself (enumerate mode or
grep of `run_suite` lines) — a new call shape the extractor misses must red, not skip.

## Test Scenarios

| Scenario | Method |
|---|---|
| Fixture-driven mutation arms per `## Guard Contract` matrices | bash fixture suites |
| Drift gate on real `--incremental` regen after a suite is added | synthetic suite + regen |
| End-to-end: `test-all.sh --affected` stays green with all guards armed | local run |

## Open Code-Review Overlap

1 hit: **#7942** — "Two mutation batteries in plugins/soleur/test/ are named
*.mutation.sh and run in no gate" (body references `scripts/test-all.sh`).
**Disposition: Acknowledge** — different concern (orphaned `*.mutation.sh` naming/gating
in `plugins/soleur/test/`), not the registration-census direction this plan adds.
Scope-out remains open; revisit if Phase 4's census should also enumerate
`plugins/soleur/test/` — note for work-time evaluation.

## Spec-Flow Revisions (folded 2026-10-30)

Resolutions to spec-flow findings — these amend the phases above:

- **R1 (P0-1) Baseline = merge-base blob, with a recorded ack.** The drift comparison is
  `new table − merge-base blob` (per-PR ratchet; catches slow regrow that incumbent-diff
  misses, since `--incremental` passes measured rows byte-identical). An `--allow-growth`
  ack is RECORDED (`# growth-acked=<ts>` header stamp or ledger row) so repeat regens on
  the same branch don't re-fire — the unrecorded ack is what makes merge-base double-fire.
  Absent-baseline bootstrap (first-ever table) is an explicit carve-out, not a fail-close.
- **R2 (P0-3) G2 population = `--enumerate` registration labels for the light+heavy
  groups only.** Durations keys are labels, not paths — `git ls-files` reconciliation is
  wrong (labels like `tests/scripts/lint-rule-ids` aren't files). Reference =
  `bash scripts/test-all.sh --enumerate` SUITE_REGISTRATION (same producer
  `scripts-shard-manifest.test.sh:159-161` uses). Scope: labels in
  `suite-durations.tsv` + `suite-durations-heavy.tsv`; bun/webplat/infra registrations
  (no duration tables) are declared out-of-scope v1 — NOT folded into the unmeasured
  allowlist (it would be 10–20 entries, not ≤2). `apps/web-platform/infra/suite-durations.tsv`
  included in scope.
- **R3 (P1-1) Transition semantics.** floor→measured: exempt from the per-suite factor
  (no fair baseline) but COUNTS toward total-measured growth (else batch floor→measure
  is an unbounded accretion channel). measured→floor (a suite that stops producing timing
  rows — e.g., now hangs): named report line; persistent floor-recycling is a finding.
- **R4 (P1-2) Per-suite factor is conjunctive:** `new > 1.5× committed AND new−committed
  > 10_000ms` (the WEIGHT_DRIFT precedent — factor-only fires on 80ms→200ms jitter).
- **R5 (P1-3) Gate lives in the shared `--write` path** covering `--incremental`,
  `--runs`, AND the `--durations <table> --write` injection arm; fires only on
  committed-table writes (`manifest_path == default`), never redirected emissions.
- **R6 (P1-6) Exemptions ledger rules:** `reason` must carry a `#NNN` tracking ref
  (lint-orphan doctrine); minimal-ledger invariant — a row whose suite fits the default
  cap reds (no permanent exemptions); slack bounded (`cap_ms` ≤ ~1.3× current weight —
  a 700s suite exempted to 900s can't regrow ungated); stale-key parity (row for a
  deleted/renamed label reds); legal-control labels' rows route to CLO review.
- **R7 (P1-8) G4 producer = `--enumerate-commands` stream** (resolved argv — covers the
  `run_suite "$f" bash "$f"` glob loop, env-prefixes, `${VAR:-}`), never grep. Directory
  operands ALLOWED for interpreter-class argv0 (`bun test plugins/soleur/` is legitimate
  — fixes M5). `python3 -m unittest X.Y` translates module→path. Unknown argv0 (outside
  `bash|sh|python3|env|node|bun`) reds. `SUITE_COMMAND_DECLINED` field 3 is a rerun
  string, not argv — excluded from the check. Trackedness via `_tracked_member`.
- **R8 (P2) Self-registration dogfood:** new guard suites need explicit `run_suite`
  (SUITE_GLOBS excludes `scripts/*.test.sh`), always-on ≤10s weight, a justifications
  row, and manifest+durations rows via `--incremental` — which exercises G1 on the
  landing commit. Guard suites go in ALWAYS_ON (verdicts are corpus properties — must
  run under every bounded selection). Stray `scripts/*.tsv.n` files: verify
  tracked-or-delete at work time; G2 pins exact table names, never `suite-durations*` glob.
- **R9 (P1-4) Hand-edited weights are an accepted residual hole** for v1 — G1 rate-limits
  the sanctioned flow; G2's absolute cap is the level guard. The ADR claim is written as
  "sanctioned regeneration flow," not "only path" — a provenance/checksum pin is a
  named non-goal unless plan-review calls for it.
- **R10 (P2-8) No absolute total-corpus cap in v1** — legitimate suite accretion is
  intentionally unbounded; per-suite cap + growth-rate gate carry the invariant. Confirm
  deliberate at review.

## Open Questions

1. Exact drift literals (`DRIFT_SUITE_FACTOR` 1.5×, `DRIFT_ABS_MS` 10s, `DRIFT_TOTAL_PCT`
   10%) — confirm against the 6-week growth distribution at work time.
2. `NON_LIVE_CAP` calibration — measure `count(ALWAYS_ON \ live_named)` against
   `--enumerate-commands` at work time (first-draft 95).
3. Whether Phase 3's ledger suite folds into `test-all-fast-tier-budget.test.sh` or
   stands alone — work-time decision on suite-file layout.
4. Corpus cap start value (600s) — validate against top-20 committed weights; verify no
   legit suite sits in the 600s band before pinning.
