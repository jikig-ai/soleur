---
title: "ci: re-price replay arm -a post-#12296 and pace arm -b (row_scan_ops mutation-site cost)"
type: chore
date: 2026-11-08
slug: ci-replay-b-pacer
branch: feat-one-shot-ci-replay-b-pacer
issue: 11556
lane: cross-domain
---

# ci: re-price replay arm -a post-#12296 and pace arm -b

## Enhancement Summary

**Deepened on:** 2026-11-08
**Sections enhanced:** Observability (probe re-verified live), Technical
Considerations (precedent note), Research Insights (gate ledger).

### Deepen-plan gate ledger (all resolved at deepen time)

- **4.5 network-outage:** `timeout` tokens fired the checklist trigger;
  evaluated and N/A — every `timeout` in this plan is a bash bound on a
  synthesized fixture (run_sut `timeout 30`, `REPLAY_SUT_TIMEOUT`), never a
  network-connectivity hypothesis. Telemetry emitted.
- **4.6 User-Brand Impact:** present, threshold `none` + scope-out reason;
  no Files-to-Edit path matches the sensitive-path regex — PASS.
- **4.7 Observability:** section present; `discoverability_test.command`
  re-verified live (`grep -c 'replay-a' scripts/suite-durations.tsv` → `1`,
  allowlisted verb, <1 s, no banned metacharacters, no suite/test-shaped
  tokens) — PASS.
- **4.8 PAT:** no PAT-shaped variable/literal — PASS.
- **4.9 UI wireframe:** no UI-surface files — skip.
- **4.10 Encryption posture:** no store/connection introduced — skip.
- **4.11 Guard Contract:** `scripts/lint-guard-contract.py` green (3 guard
  entries, matrices ≥3 rows); adequacy read: assemblies name chokepoints
  (`mutate`/`mutant_outcome` dispatch, `check_corpus`, `run_sut:249`), not
  member snapshots — PASS.
- **4.12 Scope Check:** exactly one unfenced section; all asks mapped; the
  two `inferred` items carry justifications — PASS.
- **4.13 Task Design:** no new autonomous-task surface — skip.
- **4.4 precedent-diff:** `REPLAY_SUT_TIMEOUT` follows the file's own
  env-knob family (`PR_AFFECTED_REPLAY_GH_TIMEOUT`,
  `PR_AFFECTED_REPLAY_GIT_TIMEOUT`, `PR_AFFECTED_REPLAY_SELECT_TIMEOUT`) —
  same "env var consulted at the bounded call" pattern; no novel shape.
- **4.45 verify-the-negative:** negative claims re-grepped —
  `REPLAY_SUT_TIMEOUT` setters confined to `run_sut` + `row_sym` (matrix row
  3 enforces it); pristine-vs-give_up headroom verified by the instrumented
  local run (RATIOS 0.29–1.01 vs 3x bounds).
- **Subagent fan-out:** this environment exposes no Task/spawn tool; skill
  agents, learnings agents, and the Phase 5 review-agent panel could not be
  spawned. Research ran inline (site-cost table, instrumented row timing,
  ledger-code read, PR #12412 diff inspection, sharp-edges catalogue pass).
  Residual risk is bounded to the pending technical rulings in
  `decision-challenges.md`.

## Overview

Epic #11556 (cut PR required-check time toward 20 min) residual work after the
#12296 observation-window retirement. Two coupled items land in ONE PR:

- **Item A (ledger):** `plugins/soleur/test/ci-pr-affected-replay-a` is still
  priced at the pre-retirement 1033094 ms in `scripts/suite-durations.tsv`
  while post-retirement green `merge_group` medians put it at ~160 s (now the
  fastest arm). The stale price makes its
  `scripts/suite-weight-exemptions.tsv` row (cap 1343022) ledger-inconsistent:
  the ledger's slack bound requires `cap_ms <= ~1.3x committed weight`, and
  1343022 is ~8.4x the true weight. Re-price the row to the measured value and
  DROP the exemption (adjusting the cap is not an option — the re-priced row
  fits the default 600000 ms cap, so the minimal-ledger rule forbids keeping
  any row at all).
- **Item B (pacing):** arm `-b` (~226 s median wall, 188.6 gated site seconds)
  is now the heaviest replay arm, and `row_scan_ops`'s mutation sites carry
  ~105 s of that. Reduce those sites' wall cost while preserving every
  guarded property — the suite's mutation discipline is that no relaxation may
  let a mutant gain ground, so every site must still end `killed`.

## Problem Statement / Motivation

Measured evidence (all verified at plan time):

- `knowledge-base/project/specs/archive/20261108-065407-feat-one-shot-12015-replay-a-pacer/measurements.md`
  — green merge_group runs 42447940669 / 42442159415 / 42439386564
  (2026-11-08, all `success`): arm medians **-a 160004 ms**, -b 225993 ms,
  -c 165824 ms. Guarded site-cost reading on tree `f0c3bb8656` (476-site file):
  gated site seconds a=98.8, b=188.6, c=136.5, unconditional ~74 s/arm.
- Per-site table (`/var/tmp/m12015/table.tsv`, same reading): the five
  `row_scan_ops` sites in arm -b over 5 s are 219=47.3 s, 217=16.8 s,
  218=15.4 s, 175=12.5 s, 216=7.3 s; `row_scan_ops` totals **105.0 s of arm
  -b's 188.6 gated seconds** (~56%). `row_sym` totals 35.4 s (site 225=30.2 s).
  Arm -c's `row_rt_big_baseline` site 350 costs 31.2 s.
- Local instrumented run of the pristine `row_scan_ops` body (extracted to
  `/tmp/row_scan_ops_i.py`, `python3 /tmp/row_scan_ops_i.py
  scripts/ci-pr-affected-replay.py`): **4.8 s total** — the traced phases cost
  ~0.4 s, the 400k-path PathIndex build ~2.9 s, the CPU legs ~1.4 s. The
  expensive sites are therefore **mutant-side runaway**, not pristine cost:
  the mutants execute the whole battery before being condemned, and the
  `give_up` bound in `cpu()` is only checked between rep-blocks, so a
  quadratic mutant pays entire legs (18 scans of the 64 KB leg, one full ~30 s
  scan of the 1 MB leg).

The two stale-price consequences compound: an over-priced -a fools the
shard-packing math AND holds an exemption row the ledger's own slack bound
declares inconsistent, while -b paces the battery ~66 s above -a on wall.

## Proposed Solution

### Item A — re-price `ci-pr-affected-replay-a` and drop its exemption row

1. Edit `scripts/suite-durations.tsv`: `plugins/soleur/test/ci-pr-affected-replay-a`
   `1033094` → `160004` (`measured` — median of the three cited green runs;
   keep the `measured` src tag because the value IS measured, with a
   provenance `#` comment naming the three run ids so the hand-seated value is
   auditable until the next generator pass).
2. Delete the `plugins/soleur/test/ci-pr-affected-replay-a    1343022 ...`
   row from `scripts/suite-weight-exemptions.tsv` (160004 < 600000 default
   cap — the minimal-ledger invariant forbids the row staying; the slack
   bound forbids adjusting it).
3. Provenance refresh: run
   `python3 scripts/regenerate-shard-manifest.py --incremental --durations scripts/suite-durations.tsv --write`
   so the generated-table headers (`generated-at`, `growth-acked`) reflect a
   real generator pass rather than a hand edit — the file header itself
   declares "generated ... NOT hand-edited" (see
   `scripts/test-all.sh`'s note at ~:5949). Verify the resulting diff is
   limited to the -a row plus header stamps and the pinned manifest; if the
   regen produces unrelated churn, fall back to the surgical two-line edit and
   record the deviation in the PR body.
4. Append a dated line to
   `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`'s
   re-price log recording the post-retirement re-price and exemption drop
   (mirrors the existing "Measured arm medians (seeded → measured)" entries).
5. Do NOT re-split `scripts/suite-shard-legs.tsv`: the manifest is a committed
   assignment, not a computation — a stale-but-present price only biases
   future regens, and re-packing is a separate, larger diff (`--runs 5`
   re-prices the 8 always-on drifters #11648 tracks and reds
   `test-all-fast-tier-budget`, the exact trap the prior re-price's runbook
   entry documents).
6. Do NOT re-price -b/-c in this PR: their rows are stale the same direction
   but violate no ledger invariant; that sweep belongs to the #11679 umbrella
   (recorded as deferred, tracked, no new issue needed).

### Item B — bound mutant-side runaway in `row_scan_ops` (and `row_sym`)

The kill evidence for every `row_scan_ops` site is produced inside ONE python
heredoc (`plugins/soleur/test/ci-pr-affected-replay.test.sh:987-1119`), run
once unconditionally (:1121) and once per gated mutant naming it (16 sites:
ordinals 85-89, 157, 175-178, 215-223 on the 476-site file — all shift +1 if
open PR #12412 lands first, plus the ungated `ctl-ops-traceback` control).
The reshape keeps the same pinned properties with a cheaper assertion shape:

1. **Per-scan `give_up` inside `cpu()`.** Today `give_up` is only consulted
   between rep-blocks (`for _ in range(reps)` completes fully first), so a
   quadratic mutant pays an entire block per leg. Check elapsed against
   `give_up` after every scan and abort the leg early, returning a value that
   is *over* the bound (never under) so the mutant still goes RED — a bound
   that can only fire `> bound`, never `<=`. On pristine nothing changes:
   pristine scans never approach `give_up` (3-30x above the asserted bound).
2. **Early-condemn ordering + checkpoints.** The CPU phase currently runs
   t2 → t400k → width → lengths → c64 → c1m with `if bad` exits only at two
   points. Insert `if bad: print; sys.exit(0)` after each measured leg and run
   the legs cheapest-first so a mutant condemned by a ~1 s leg never pays a
   ~30 s one. (The per-start quadratic class — sites 216-219 — is only
   condemned by the text axis, so that axis's cost dominates their bill.)
3. **Shrink the text axis's absolute sizes, keep its detection window.** The
   assertion is "per byte, the big text may cost at most 3x what the small
   text costs". It is currently 64 KB → 1 MB (16x window; catches per-byte
   growth exponent > ~0.4). Move it to ~16 KB → ~256 KB — the SAME ~16x
   window and detection band, ~1/16 the quadratic-mutant cost (a single
   256 KB quadratic scan is ~2-4 s vs ~30 s at 1 MB), and the big leg stays
   comfortably above the `FLOOR=1ms` timing floor (pristine ≈ tens of ms).
   Sizing the small leg above the floor is the constraint: anything under
   ~1 ms of pristine time lets `max(small, FLOOR)` mask a real 3x breach.
   Exact sizes are tuned at work time against a jitter check on the local
   host; the 16x window is the invariant to preserve.
4. **Tighten the line-event cap.** `cap = 40*len(text) + 20000` bounds a
   runaway mutant under `sys.settrace`; the asserted bound is `ev <= 8*len`,
   so ~5x headroom is slack the cap-burn class (site 175 = 12.5 s) spends.
   Tighten to ~`12*len(text) + 5000` — still ~1.5x above the asserted bound,
   ~3x less cap-burn per condemning fixture. Pristine events (~≤2*len) never
   approach it.
5. **`row_sym` per-invocation timeout.** Site 225's 30.2 s is the
   `read-opens-blocking` mutant hanging on the fixture FIFO until
   `run_sut`'s literal `timeout 30` (test.sh:249) kills it — the cost IS the
   bound. Parameterize it: `timeout "${REPLAY_SUT_TIMEOUT:-30}"`, and set
   `REPLAY_SUT_TIMEOUT=10` inside `row_sym`'s subshell (`row_sym() ( … )` —
   env scoping is free). The mutant still dies `rc 124` → RED → killed; the
   pristine audit over the dsym fixture is ~1 s, so 10 s leaves ~10x
   headroom. All other `run_sut` callers keep 30 s.
6. **Site 350 (`row_rt_big_baseline`, arm -c): leave unchanged.** Its 31.2 s
   is the quadratic mutant burning the same `timeout 30`; the 150k-line
   baseline is load-bearing (the in-code comment records that at 60000 lines
   the quadratic finished <25 s on a fast runner and SURVIVED — #10404-class
   evidence), and the external bound can only shrink to ~28 s before it
   eats the pristine 25 s budget. Not worth ~3 s of flake risk.
7. **Explicit rejections (do not implement):** shrinking the 400k-path corpus
   — the code comment records an O(paths)-per-scan survivor at 100k paths
   (#10404's merge-group survivor); shrinking the 20k corpus — the traced
   legs measured ~0.4 s total, immaterial; fewer rep rounds — pristine cost
   is already ~1.4 s across all CPU legs; a 4th `--rows` leg — adds a ~74 s
   duplicated unconditional head for ~40 s of parallelism (already ruled out
   by the sibling plan's measurement record).

### Mutation discipline (the acceptance bar)

Every `mutate` site naming `row_scan_ops`, `row_sym`, or `row_rt_big_baseline`
must still end `killed`, and `ctl-ops-traceback` must still score `crashed`.
Local verification runs the named sites directly:

```bash
bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 215-223   # the per-start/hidden-scan row_scan_ops mutants
bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 175-178   # the call-less class
bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 224-227   # row_sym sites
bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 85-89     # arm -a's row_scan_ops sites
bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 159-316   # full arm -b for the before/after wall
```

(Ordinals are pre-#12412; if that PR lands first, every range shifts +1 —
find the sites by mutant name, not number.)

## Technical Considerations

- **The battery's structure.** Gated sites are the top-level `mutate` calls;
  `mutant_outcome` copies `scripts/ci-pr-affected-replay.py` (the SUT), applies
  the edit, and runs the named `row_*` checker against the mutant, with a
  once-per-row pristine check cached in `PRISTINE_OK`. `row_scan_ops` is BOTH
  an unconditional assertion (:1121, ~5 s of every arm's ~74 s head) and the
  checker for 16 gated sites. Cost attribution is per gated site: arm -b's
  first `row_scan_ops` site pays the pristine run (~10-12 s on the
  measurement host), the rest pay their own mutant run — which is where the
  16-47 s figures come from.
- **What each mutant class costs and why.** Traced-phase kills (brute-force,
  materializing, `_p in index.paths` loops) die in ~1-12 s (cap-burn). The
  per-start hidden-C-call class (`text[m.start():].encode()`,
  `.count()`, `re.search` on a slice, `.replace()` — sites 216-219) is
  invisible to ops/line-events/materialization by design and dies only at the
  CPU text axis — the most expensive leg in the file, and `give_up` can't
  interrupt inside a rep-block. That is the whole 87 s at sites 216-219.
- **Why the reshape preserves kills.** Nothing about the pinned property
  changes: constant ops/line-events per byte, no materialized tracked-path
  collection, ≤2x ops/lines on the paths/width/lengths axes, ≤3x best-of-3 CPU
  per byte across the text axis, ≤3x on the 400k-vs-2k paths axis. The give_up
  abort returns over-bound (a kill signal, never a pass); the text axis keeps
  a 16x size window; the cap stays above the asserted bound.
- **Flake surface.** The ratio bounds are self-referential (corpus-vs-corpus),
  so they ride out host speed differences; the residual flake class is timing
  noise near `FLOOR`, which is why the small text leg must stay ≥ a few ms of
  pristine time and why `REPLAY_SUT_TIMEOUT` stays ≥ ~10x the pristine audit
  cost.
- **Merge-order adjacency.** Open PR #12412 (mid-ship) edits this test file at
  ~:74 (DECLARED_TOTAL 476→477), ~:443-530 (fixture runs/units), ~:647
  (folded-parity checks), ~:3425 and adds `mutate folded-jobs-unclassified`
  after `unclassified-job-reassuring` — a site ordinal BEFORE ours, so all
  row_scan_ops/row_sym ordinals shift +1 and `FLOOR_ASSERTIONS` goes
  1110→1115. Whichever lands second rebases on the other's DECLARED_TOTAL /
  FLOOR_ASSERTIONS lines and re-verifies mutate anchors (anchors are exact
  SUT-text matches; #12412 also adds ~15 lines to the SUT at ~:205 — our
  anchors live in scan_text/audit paths and should hold, but the work phase
  MUST re-run the targeted `--rows` ranges after any rebase). Draft PR #12410
  touches only `scripts/ci-oracle-lane.*` — disjoint.
- **NFR:** none of `nfr-register.md`'s registers move — no production code,
  no new surface; this is test-harness cost tuning on an existing gate.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — a
  weakened mutation pin could let a `scripts/ci-pr-affected-replay.py`
  regression merge undetected; the user-visible artifact is a slower or
  silently wrong affected-suite selection in a later release, not a defect in
  this diff itself.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  vector — synthetic fixtures only (`cq-test-fixtures-synthesized-only`), no
  credentials, no user data on any path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI/test-harness cost change
  with synthesized fixtures and no production path — the next tier up
  (single-user incident) has no plausible reach path.
- Scope-out: `threshold: none, reason: touches scripts/ and plugins test
  harness only — no user-facing surface, no production code path, fixtures
  are synthesized.`

## Observability

The deliverable is a required-check battery and a ledger — its own signal IS
the CI verdict. No new runtime surface is introduced.

```yaml
liveness_signal:
  what: the replay arms' green/red verdict in the required test-scripts matrix legs
  cadence: per CI run
  alert_target: required-check failure on the PR / merge_group run
  configured_in: scripts/test-all.sh registrations of plugins/soleur/test/ci-pr-affected-replay-{a,b,c}
error_reporting:
  destination: the suite's own [FAIL]/[FATAL] lines in the leg log
  fail_loud: a mutant surviving prints "mutant <name>: survived" and the arm exits non-zero
failure_modes:
  - mode: a reshaped pin lets a mutant survive
    detection: the arm reds on the named site (kills are fail-closed)
    alert_route: required-check failure
  - mode: a stale/over-priced durations row or ledger-inconsistent exemption
    detection: scripts/test-all-corpus-weight-budget.test.sh (ledger invariants) + advisory WEIGHT_DRIFT lines
    alert_route: required-check failure / warn-only line
logs:
  where: suite-timings artifacts on merge_group runs; the leg's stdout log
  retention: GitHub artifact retention for the workflow
discoverability_test:
  command: grep -c 'replay-a' scripts/suite-durations.tsv
  expected_output: 1
```

## Architecture Decision (ADR/C4)

None. This is a cost-tuning change to an existing test battery and two
committed data rows — no ownership/tenancy boundary, no new substrate or
trust boundary, no ADR's Decision is diverged from (ADR-240's
generated-manifest mechanism is used as designed). A competent engineer
reading the existing ADRs + C4 after this ships is not misled.

## Guard Contract

### Guard 1 — mutation-kill preservation across the row_scan_ops reshape

**Property.** Every gated site naming `row_scan_ops` ends `killed`, the
`ctl-ops-traceback` control still scores `crashed`, and the unconditional
`row_scan_ops` invocation still greens on the pristine SUT.

**Assembly.** All 16 `mutate` sites naming the row (ordinals 85-89, 157,
175-178, 215-223 pre-#12412), the unconditional invocation at test.sh:1121,
and the control at :4249 — every dispatch flows through the single
`mutate()`/`mutant_outcome()` chokepoint at test.sh:3393-3419, so a reshape
cannot bypass a site; `in_range` still sequences every site against
DECLARED_TOTAL at EOF.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-apply the site-219 class by hand (`text.replace("zz","y")` inserted per match start in a scratch copy) — the reshaped text axis must still go RED on it | RED (killed) |
| 2 | Make the `cpu()` give_up abort return `0`/`None`-as-pass instead of an over-bound value — a bound that can pass on abort is vacuous; the harness row asserting the abort path must red | RED |
| 3 | A SECOND distinct per-start C-call mutant alongside the first (e.g., both `.encode()` and `.count()` per start) — a checkpoint that stops after the first condemned leg must still catch the class in the second leg | RED (both killed) |
| 4 | Remove a named `mutate` call site — the EOF `_site_seq == DECLARED_TOTAL` census must FATAL (guard's own dispatch) | RED (FATAL) |
| 5 | must-PASS, non-canonical input: `ROW_OPS_VERBOSE=1 bash … --rows 219-219` on pristine — the contract explicitly permits verbose mode and must still green | PASS |

### Guard 2 — committed-weight ledger consistency after re-price

**Property.** `suite-durations.tsv`'s `-a` row equals the measured value and
no `suite-weight-exemptions.tsv` row violates the slack (~1.3x), minimal
(fits-default-cap), stale-key, or #NNN-ref invariants.

**Assembly.** The three committed durations tables +
`suite-weight-exemptions.tsv`, judged by `check_corpus` in
`scripts/test-all-corpus-weight-budget.test.sh` — the single chokepoint every
ledger row flows through (the real-files arm plus self-checking fixture arms).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Leave the `-a` exemption row in place after the re-price (cap 1343022 > 1.3x 160004) | RED (slack bound) |
| 2 | Set the exemption cap below the weight (e.g., 100000) — cap must cover weight | RED |
| 3 | Re-add the exemption row AND drop the `-a` durations row entirely — stale-key parity (second-member: a row keyed on a label no table carries) | RED (stale-key) |
| 4 | Rewrite an exemption `reason` without a `#NNN` token | RED |
| 5 | must-PASS, non-canonical input: the post-change real tables (different label set than any fixture arm) | PASS |

### Guard 3 — run_sut per-invocation timeout override

**Property.** A hang inside a `run_sut` call is killed at the override's
declared seconds; with no override the bound stays 30 s; an invalid override
falls back to the default, never disables the bound.

**Assembly.** The single `timeout` call at test.sh:249 plus every call path
that can set `REPLAY_SUT_TIMEOUT` (initially `row_sym` only — the var is set
inside its subshell and nowhere else; a sweep asserts `grep -n
REPLAY_SUT_TIMEOUT` returns only the run_sut default and the row_sym site).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `read-opens-blocking` mutant (site 225) under the 10 s override — the FIFO hang must still be killed | RED (rc 124 → killed) |
| 2 | `REPLAY_SUT_TIMEOUT=0` or non-numeric — must not disable or widen the bound | RED or fallback-to-30 (never unbounded) |
| 3 | A second row setting the override (guard's second-member) — a grep row asserting exactly the declared setter sites must red | RED |
| 4 | Harness row: `REPLAY_SUT_TIMEOUT` unset on a hanging call — the default 30 s bound must still fire (dispatch of the default arm) | RED (rc 124) |
| 5 | must-PASS, non-canonical input: pristine `row_sym` under the override (~1 s audit, far under 10 s) | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-price it to the measured value and drop its `scripts/suite-weight-exemptions.tsv` row" [brief, Item A] | Proposed Solution Item A; Files-to-Edit rows for both TSVs; Guard 2; AC1-AC3 | mapped |
| 2 | "Reduce the site's wall cost while preserving the guarded properties" [brief, Item B] | Proposed Solution Item B steps 1-4; Guard 1; AC4-AC7 | mapped |
| 3 | "Secondary sites if cheap wins exist: `row_sym` (30.2s, site 225, b), `row_rt_big_baseline` (31.2s, site 350, c)" [brief, Item B] | Item B step 5 (row_sym timeout override); step 6 (site 350 assessed and left — floor-bound) | mapped |
| 4 | "mutation survivors must NOT gain ground (the suite's mutation discipline: every relaxation needs a mutation row proving the pin still kills)" [brief] | Mutation discipline block; Guards 1-3; AC5 | mapped |
| 5 | "plan must note rebase-on-merge-order" [brief, adjacency] | Technical Considerations merge-order block; Dependencies & Risks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| durations.tsv -a row edit | "Re-price it to the measured value" | asked |
| exemptions.tsv row deletion | "drop its `scripts/suite-weight-exemptions.tsv` row" | asked |
| row_scan_ops give_up/checkpoint/text-axis/cap reshape | "Reduce the site's wall cost while preserving the guarded properties (options to weigh: … cheaper assertion shape …)" | asked |
| run_sut REPLAY_SUT_TIMEOUT + row_sym setter | "Secondary sites if cheap wins exist: `row_sym` (30.2s, site 225, b)" | asked |
| runbook re-price log line | — | inferred — the runbook is the repo's re-price ledger (two prior re-prices are logged there); skipping it strands provenance |
| -b/-c re-price exclusion | "Two coupled items, ONE plan, ONE PR" + Item A names only the -a row | asked (scope bound) |
| measurements.md in spec dir | — | inferred — the two sibling slices both recorded measurements; this plan's ACs cite before/after numbers that must live somewhere |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `plugins/soleur/test/` (knowledge-base docs don't count as subsystem roots)
- Planned files: 5 | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `scripts/suite-durations.tsv` carries `plugins/soleur/test/ci-pr-affected-replay-a<TAB>160004<TAB>measured` (or a fresher measured value re-derived the same way, with provenance recorded) and the row stays label-sorted.
- [ ] AC2: `scripts/suite-weight-exemptions.tsv` has no `ci-pr-affected-replay-a` row; `bash scripts/test-all-corpus-weight-budget.test.sh` greens against the real tables.
- [ ] AC3: `bash plugins/soleur/test/scripts-shard-manifest.test.sh` greens (manifest/durations parity, sorting, provenance keys).
- [ ] AC4: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 159-316` greens locally, with every `mutate` site naming `row_scan_ops`/`row_sym` reported `killed` (arm -b dispatch unchanged).
- [ ] AC5: Each of the 16 `row_scan_ops` sites plus the `row_sym` sites is re-verified killed by name after the reshape — no survivor gains ground; `ctl-ops-traceback` still `crashed`.
- [ ] AC6: Post-change local arm -b gated work is materially lower: the targeted `--rows 215-223` span's wall drops by >= 50% vs the pre-change reading (measured and recorded in `knowledge-base/project/specs/feat-one-shot-ci-replay-b-pacer/measurements.md`).
- [ ] AC7: DECLARED_TOTAL, the three registered `--rows` ranges, and FLOOR_ASSERTIONS remain internally consistent (no range gap; the EOF census + anti-vacuity floor pass) — including after any rebase onto PR #12412's bumped counts.
- [ ] AC8: `row_rt_big_baseline`'s 150k-line fixture and the 400k-path corpus are untouched (both carry recorded survivor evidence).

## Test Scenarios

- Given the post-change tables, when `test-all-corpus-weight-budget.test.sh` runs, then it prints green on the real-files arm and its own red/green fixture arms (`unit`-class — the suite is itself the test).
- Given each `row_scan_ops` mutant site by name, when run via `--rows <site>-<site>`, then the suite reports `mutant <name> is killed by row_scan_ops` (`integration`-class — mutation battery).
- Given a sleeping/hanging invocation, when `REPLAY_SUT_TIMEOUT` is unset vs set, then the bound fires at 30 s vs the override respectively — verified by a harness row driving a stub SUT (`unit`-class).
- Given a merge of PR #12412 first, when this branch rebases, then `grep -c '^mutate '` equals the new DECLARED_TOTAL, the registered ranges still tile 1..DECLARED_TOTAL (`scripts-shard-totality.test.sh`), and the targeted `--rows` re-run still kills the named sites.
- Regression scenario (the class this pins): an O(paths) C-call per scan at 100k paths once survived (#10404) — the 400k paths-axis leg MUST remain, and the plan's AC8 is its regression pin.

## Success Metrics

- Arm -b gated site seconds: 188.6 → target <= ~100 s (the row_scan_ops sites' 105 s → ~15-30 s; row_sym's 35.4 s → ~13 s).
- Arm -b merge_group wall: ~226 s → target <= ~165 s (at or below arm -c's ~166 s).
- suite-durations `-a` price: 1033094 → ~160004 ms; zero exemption rows for the -a label.
- Zero mutation-site coverage loss: 16/16 row_scan_ops kills, 6/6 row_sym kills, unchanged ctl verdicts.

## Dependencies & Risks

- **Merge order with open PR #12412** (feat-one-shot-12360-ci-lever-threads): it bumps DECLARED_TOTAL to 477, FLOOR_ASSERTIONS to 1115, inserts a gated site before ours (all our ordinals +1), and adds ~15 lines to the SUT — the second merger rebases, re-verifies `grep -c '^mutate '` == DECLARED_TOTAL, re-runs the targeted `--rows` spans by mutant name, and re-checks the exemption/weights lines. `scripts/ci-pr-affected-replay.py` is edited by #12412 — mutate anchors are exact-match strings; the work phase re-verifies all anchors still land after any rebase.
- **Stale-price adjacency:** -b/-c prices are stale the same direction; kept out of scope (tracked under #11679). If review disagrees, the fix is one more TSV row, not a design change.
- **Flake risk:** the reshaped text axis and the row_sym timeout both depend on headroom multipliers; the work phase measures the jitter band locally before committing sizes/timeouts.
- **No new issue filings needed:** all deferrals land under existing trackers (#11679 umbrella, #10404 survivor precedent recorded in code comments).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/test-infrastructure cost
tuning (assessed across all 8 domain questions; Engineering was the only
marginal candidate and this is bounded harness surgery, not an architectural
decision; no spawn tool was available in this planning environment, so the
assessment is recorded inline rather than via leader Tasks).

## References & Research

- `knowledge-base/project/specs/archive/20261108-065407-feat-one-shot-12015-replay-a-pacer/measurements.md` — post-retirement arm medians + site-cost reading
- `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (+ 2026-11-08 postscript)
- `knowledge-base/project/plans/archive/20261108-065407-2026-11-08-ci-replay-arm-a-pacer-bound-plan.md` — sibling slice; its Cut List named this plan's scope
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:987-1119` (row_scan_ops body), :247-251 (run_sut `timeout 30`), :3393-3419 (mutate/mutant_outcome), :3611-3801 (named sites), :4249 (ctl control), :1410 (row_sym), :2499 (row_rt_big_baseline + survivor comment)
- `scripts/test-all-corpus-weight-budget.test.sh:60-90` (ledger invariants: slack ~1.3x, minimal, stale-key, #NNN)
- `scripts/regenerate-shard-manifest.py` (`--incremental --durations` incumbent-pinning path)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md:395-415` (re-price precedent + the `--runs 5` drifter trap)
- `plugins/soleur/test/scripts-shard-manifest.test.sh` (generated-table guards)
- Related: #11556 (epic), #12296 (retirement), #12016 closed (stale-prices slice), #12376 (evidence), #11679 (umbrella), #10404 (survivor precedent), PR #12412 (adjacency), PR #12410 (disjoint)

## Research Insights

- **Premise Validation.** Cited issues/PRs verified via `gh`: #11556 OPEN
  (epic), #12296 MERGED (retirement landed), #12016 CLOSED (this plan carries
  its deferred residual), #12376 MERGED (evidence doc), #11679 OPEN
  (umbrella, cited by the exemption row), #12357 MERGED, #12393/#12418 OPEN
  (non-goals). PR #12412 OPEN mid-ship — diff inspected: bumps
  DECLARED_TOTAL→477 and FLOOR_ASSERTIONS→1115, inserts a gated site before
  the row_scan_ops ordinals (+1 shift), edits the SUT +15 lines. PR #12410
  OPEN draft — `scripts/ci-oracle-lane.*` only, disjoint. Cited files all
  exist at the cited anchors. The `-a` row is still 1033094 and the exemption
  still present — the stale premise holds. `collision-precheck.sh 11556`
  reported `prs=none` plus two foreign `test-all.sh` processes owned by the
  sibling worktree `feat-one-shot-12393-oracle-lane-bound` (live run, not a
  PR conflict — noted, not blocking).
- **Property List.** (1) committed `-a` weight ≈ measured (~160 s) so the
  shard/packing math reads true weights; (2) no ledger-inconsistent exemption
  row; (3) arm -b gated site seconds materially below 188.6; (4) zero
  mutation-coverage regression.
- **Cut List.** "Move part of the property to a cheaper arm" → property 3 →
  relocates cost, doesn't reduce it (kept only as fallback); 4th `--rows` leg
  → property 3 → already ruled out by the sibling measurement record (a 4th
  ~74 s head); 400k/20k corpus shrink → properties 3+4 → recorded survivor
  evidence forbids the 400k leg and the 20k leg costs ~0.4 s; rep-round cuts
  → property 3 → pristine CPU legs are already ~1.4 s.
- **Value-prop measurement.** Numbers are measured, not asserted:
  `/var/tmp/m12015/table.tsv` (site costs), the three named merge_group runs
  (arm medians), and `python3 /tmp/row_scan_ops_i.py
  scripts/ci-pr-affected-replay.py` = 4.8 s pristine locally — establishing
  that site cost is mutant-side, which is what selects the levers above.
- **Repo conventions.** Generated tables carry provenance headers the guards
  pin; the suite's mutation discipline (every relaxation needs a kill row)
  is the acceptance bar; `--rows N-N` is the sanctioned single-site loop.
- **Subagent note.** This planning environment exposes no Task/spawn tool:
  the repo-research/learnings fan-out, spec-flow analysis, domain-leader
  assessments, scoped advisor consult, and plan-review panel were all
  executed or approximated inline by the orchestrator; the residual risk is
  concentrated in the assertion-reshape sizes, which are carried as pending
  technical rulings in `decision-challenges.md`.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for
all four planned paths; zero hits.

## Files to Edit

- `scripts/suite-durations.tsv` — `-a` row 1033094 → ~160004 (+ provenance comment / regen-refreshed headers)
- `scripts/suite-weight-exemptions.tsv` — delete the `ci-pr-affected-replay-a` row
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — `cpu()` per-scan give_up; leg ordering + early exits; text-axis sizes; line-event cap; `run_sut` timeout parameterization; `row_sym` override; FLOOR_ASSERTIONS comment if an assertion row is added
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — dated re-price log line

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-ci-replay-b-pacer/measurements.md` — before/after per-span walls + the post-merge arm medians note
- `knowledge-base/project/specs/feat-one-shot-ci-replay-b-pacer/decision-challenges.md` — pending technical rulings (written at plan time)
