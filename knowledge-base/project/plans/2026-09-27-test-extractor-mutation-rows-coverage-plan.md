---
title: "test: committed extractor-mutation coverage for the run_suite --rows tiling arm"
date: 2026-09-27
type: test
slug: test-extractor-mutation-rows-coverage
branch: feat-one-shot-8990-extractor-mutation-rows
issue: 8990
closes: [8990]
lane: cross-domain
priority: low
domain: engineering
brand_survival_threshold: none
---

# test: committed extractor-mutation coverage for the run_suite --rows tiling arm

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** Observability (real 5-field schema replaces the skip note — deepen-plan
Phase 4.7's trigger fires on any non-doc Files-to-Edit, so the block is required even though
the deliverable is test machinery), Technical Considerations (precedent pin for multi-line
anchors), Research Insights (verify-the-negative sweep results)
**Research agents used:** sequential-fallback — no Task fan-out in this runtime; deepen-plan
halt gates (4.6 User-Brand, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe, 4.10 Encryption,
4.11 Guard Contract via `lint-guard-contract.py`), citation verification, and the
verify-the-negative sweep were discharged inline by the orchestrator

### Key Improvements

1. `## Observability` now carries the full 5-field schema — Phase 4.7's trigger inspects
   Files-to-Edit and fires on `plugins/soleur/test/*.sh` + `.github/workflows/ci.yml`
   (non-doc paths); a prose skip note would HALT at the `liveness_signal` field check.
2. Multi-line anchor for `ROWS-SWAP` verified against in-file precedent (ROW5C/ROW7/M5 use
   the same shape), and every quoted anchor string verified byte-exact against current HEAD
   (`scripts/test-all.sh:3494-3495` — present post-init-commit `e0927dbd24`).
3. All cited issue/PR numbers resolved live: #8990 OPEN, #8864 CLOSED, #8967 MERGED (the
   split PR), #8659/#7942 OPEN (code-review overlap, dispositions recorded), `d453170127` on
   `origin/main`.
4. Discoverability probe chosen to survive preflight Check 10's shell-metachar reject:
   `grep -c 'DECLARED_TOTAL=27' …` — no `|`/`&`/quotes-alternation; asserts the bumped pin.

### New Considerations Discovered

- The pipeline init commit `e0927dbd24` landed mid-session and brought the branch onto the
  `d453170127`-bearing main tip — the plan now records both the stale-start and current
  states so a stale checkout is diagnosed at Phase 0 rather than at `ANCHOR MISSING` rows.
- `fixture-relative-assert.baseline.txt` pins a flagged-operand count of 10 for the battery
  file; the new `row()` calls add no `cp`/`mv`/`rm` operands so no baseline regen is expected
  (AC6 keeps the check honest).

## Overview

`plugins/soleur/test/scripts-shard-totality.test.sh` gained a `run_suite`-argv tiling arm on
`origin/main` (commit `d453170127`, PR for #8864): an awk extractor that lifts every
`run_suite "…" bash <file>.sh --rows A-B` registration out of `scripts/test-all.sh`, per-token
contract checks (DECLARED_TOTAL presence, no mixed flagged/unflagged registrations, contiguous
tiling via `_rows_tile_check`, distinct-leg pinning), a literal census, a DECLARED_TOTAL census,
and a positive control proving the comparator detects a gap.

What is missing is a **committed** mutation row that drives that extraction chain red
end-to-end. During the predecessor PR every extractor arm was driven red only *locally*
(dropped registration, overlap, order-inversion, DECLARED_TOTAL bump, comment contamination,
skip_suite exclusion, unsplit-contract token, non-.test.sh token, comment-backslash swallow);
none of those mutations is committed anywhere. Issue #8990 asks for one (or more) committed
mutation rows in the battery that owns guard-mutation coverage for this guard —
`plugins/soleur/test/scripts-shard-totality-mutations.sh` — so the proof survives the PR that
created the machinery.

## Research Insights

*Reviewed-Coverage: sequential-fallback — this runtime has no Task/subagent spawn, so the
Phase 1 research fan-out (repo-research-analyst, learnings-researcher), Phase 1.5b
functional-discovery, Phase 3 spec-flow, and the Step 4.5 advisor consult were discharged by
the orchestrator reading the files directly, inline. No independent review ran.*

### Premise Validation (Phase 0.6)

| Cited reference | Check | Result |
|---|---|---|
| Issue #8990 | `gh issue view 8990 --json state` | OPEN — premise holds |
| Commit `d453170127` ("ci: split lint-orphan-test-suites-mutations via --rows over two shard legs (#8967)") | `git merge-base --is-ancestor` | Exists and **is** on `origin/main`. At session start this worktree's HEAD (`dfee49ef53`) predated it; the pipeline's init commit (`e0927dbd24`, atop `6ee3acf0d8` = origin/main tip) subsequently brought the branch current — see Research Reconciliation |
| Issue #8864 (predecessor) | `gh issue view 8864 --json state` | CLOSED — the split shipped |
| `plugins/soleur/test/scripts-shard-totality.test.sh` tiling arm | `git grep _rows_tile_check` | Present at HEAD (4 sites) post-init-commit |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` | `ls` + site enumeration | Present; DECLARED_TOTAL=24; 24 `in_range` row sites enumerated — **none** mutates a `--rows` registration |
| `scripts/test-all.sh` `--rows` registrations | `git show`/`grep -n` | Present at HEAD post-init-commit (lines 3494-3495) |

### Property List (Phase 0.6b)

1. A committed, CI-executed proof that mutating a `run_suite … --rows` registration in
   `scripts/test-all.sh` drives `scripts-shard-totality.test.sh` RED — end-to-end through the
   awk extractor, not just the comparator's positive control.
2. A committed must-PASS input proving the arm does not reject a permitted non-canonical
   ordering (registration order is explicitly not tiling order).
3. The proof must live where the rest of this guard's mutation coverage lives, so the
   battery's own DECLARED_TOTAL/range-accounting machinery keeps it honest.

### Cut List (Phase 0.6b)

- **A separate fixture-runner script** (the issue's alternative shape) → buys property 1 but
  duplicates the pristine-copy/restore machinery; `scripts-shard-totality-mutations.sh` already
  owns every mutation row for this guard and its `row()` helper does exactly this job. Cut:
  add `row()` entries to the existing battery instead.
- **Committing all nine locally-driven extractor arms** → buys property 1 many times over at
  ~24 s of guard runtime per row; the issue asks for committed coverage of the *arm*, not an
  exhaustive port. Cut: three rows (gap-RED, drop-RED, order-swap-GREEN) cover the tile check,
  the MIXED-contract arm, and the must-PASS direction — the rest remain locally-reproducible.

### Relevant files (all verified at plan-write time against `origin/main`)

- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — the mutation battery;
  `DECLARED_TOTAL=24` (line 76), `in_range`/`row`/`frow`/`hfrow` helpers, `mutate()` exact-anchor
  substitution (refuses missing/ambiguous anchors), dirty-tree refusal on the three mutation
  targets, EXIT-trap restore from pristine copies, range-accounting + assertion floor at the tail.
- `plugins/soleur/test/scripts-shard-totality.test.sh` — the guard (SUT); tiling arm at
  ~lines 690-990 on `origin/main`; `_rows_tile_check` comparator; `MIN_ROWS=45` floor.
- `scripts/test-all.sh` — carries the two registrations under test (origin/main lines
  3494-3495): `…-mutations-a … --rows 1-8` and `…-mutations-b … --rows 9-16`.
- `scripts/lint-orphan-test-suites.test.sh` — the battery those registrations split;
  `DECLARED_TOTAL=16` (origin/main). Not edited — only mutated *in fixtures* at test time.
- `.github/workflows/ci.yml` — `shard-totality-mutations` job (origin/main lines 1333-1368):
  `rows: ["1-12", "13-24"]` matrix, `--rows "${{ matrix.rows }}"` wire, "declares 24 numbered
  row sites" comment.
- `scripts/suite-shard-legs.tsv` — `-a`→leg 3, `-b`→leg 5 (distinct-leg pin; unchanged).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — pins a count of `10` flagged
  `mv-cp` operands for the battery file (line 312/313 region); new `row()` calls add no
  `cp`/`mv`/`rm` operands, so the count should not move — verify, regenerate only if it does.

### Applicable learnings

- `knowledge-base/project/learnings/2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`
  — an anchor's uniqueness is a property of the file's *entire* byte content, comments
  included. Anchors here are full lines including the unique `-mutations-b` label (verified:
  exactly 1 occurrence in `origin/main` `scripts/test-all.sh`), and the mutation targets
  `$RUNNER`, not the battery file, so the new rows' own comments cannot self-match.
- `knowledge-base/project/learnings/2026-09-25-matrix-k-cannot-split-an-atomic-suite.md` —
  the `--rows` split exists because the atomic battery was the worst leg; each added row costs
  ~24 s of serial guard runtime (9.5 min / 24 rows measured on the predecessor), so the row
  count is deliberately kept at three and re-split in the same commit.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — the must-PASS row exists because a RED-only matrix cannot detect a guard that rejects
  everything.
- `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md`
  — an order/lifetime property needs a reorder row, not only delete rows: ROWS-SWAP observes
  the extractor's lo-bound sort directly.

### Related issues / PRs

- #8990 (this issue, OPEN), #8864 (predecessor, CLOSED), `d453170127` (the split commit),
  #8967 (the split PR), #7902 (Guard 1 / AC12 lineage — battery header), #8006 (two-leg row
  split lineage), #7103 (flag-argument anchoring precedent).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "the predecessor --rows split PR merged 2026-09-27 (commit d453170127)" | True. **Observed two ways during planning:** at session start HEAD (`dfee49ef53`) predated `d453170127`; mid-session the pipeline's init commit `e0927dbd24` landed atop `6ee3acf0d8` (origin/main tip), so the branch now contains the split. If the work phase ever sees a checkout without it, every mutation anchor below is `ANCHOR MISSING` | Phase 0 keeps a cheap verify (grep the anchors, confirm `_rows_tile_check` exists) — merge `origin/main` only if that verify fails |
| "`scripts-shard-totality.test.sh` gained a run_suite-argv tiling block" | True at current HEAD (extractor + `_rows_tile_check` + censuses + positive control) | Phase 0 verify covers it |
| "no committed mutation row drives the extractor itself red" | Verified: all 24 `in_range` sites in the battery enumerated; none touches a `--rows` registration | Plan adds three |
| Fix shape: "a mutation row in a battery covering scripts-shard-totality.test.sh … whichever suite owns guard-mutation coverage for this file" | Owner is `plugins/soleur/test/scripts-shard-totality-mutations.sh` (its header declares it the Guard-1 mutation battery; it already mutates `$RUNNER` = `scripts/test-all.sh`) | Rows land there |

## Problem Statement / Motivation

A tiling guard whose extraction chain has no committed red-driver is one refactor away from
silently dead coverage: the positive control proves `_rows_tile_check` can detect a gap *when
fed one*, but nothing committed proves the awk extractor actually surfaces a broken
registration to it. The issue deferred this as belt-and-suspenders; this plan is the cheap,
mechanical commit that closes it.

## Proposed Solution

Add three mutation rows to `plugins/soleur/test/scripts-shard-totality-mutations.sh`, appended
after the `MUSTPASS` row (so existing row-site positions 1-24 are untouched and the new sites
become 25-27), plus the two same-commit knock-ons the battery's own contract demands
(`DECLARED_TOTAL` bump and the ci.yml `rows:` re-split).

```bash
# --- run_suite --rows tiling arm: committed extractor mutations (#8990) ------------------
#
# The guard's run_suite-argv tiling arm (awk extractor + _rows_tile_check over the
# `--rows A-B` flags on the lint-orphan-test-suites-mutations -a/-b registrations) shipped
# with a committed POSITIVE control but no committed row mutating a --rows registration
# end-to-end. These rows drive the extraction chain red through scripts/test-all.sh.

# ROWS-GAP: shrink the -b range so battery row 9 executes in no leg. The tile check
# reports "range '10-16' starts at 10, expected 9 (gap or overlap)".
in_range && row "ROWS-GAP" "$RUNNER" \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh --rows 9-16' \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh --rows 10-16' \
  RED "a gapped --rows range leaves battery row 9 unexecuted in every leg" \
  'scripts/lint-orphan-test-suites.test.sh: --rows ranges do not tile'

# ROWS-DROP: remove the flag so -b registers UNFLAGGED beside flagged -a — the
# MIXED-contract arm must fire (a dropped flag double-executes rather than loses coverage).
in_range && row "ROWS-DROP" "$RUNNER" \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh --rows 9-16' \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh' \
  RED "a dropped --rows flag yields a MIXED flagged/unflagged contract" \
  'MIXED --rows contract'

# ROWS-SWAP (must-PASS): registration order is not tiling order — the extractor sorts
# ranges by lo-bound, so swapping the -a/-b lines is a permitted non-canonical input.
# A guard that reds on this is over-tight; a RED-only matrix cannot see that.
in_range && row "ROWS-SWAP" "$RUNNER" \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-a" bash scripts/lint-orphan-test-suites.test.sh --rows 1-8
  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh --rows 9-16' \
  '  run_suite "scripts/lint-orphan-test-suites-mutations-b" bash scripts/lint-orphan-test-suites.test.sh --rows 9-16
  run_suite "scripts/lint-orphan-test-suites-mutations-a" bash scripts/lint-orphan-test-suites.test.sh --rows 1-8' \
  GREEN "swapped registration order tiles identically (ranges sort before the tile check)"
```

### Same-commit knock-ons (the battery's own contract requires them)

1. `DECLARED_TOTAL=24` → `DECLARED_TOTAL=27` in the battery, and its header comment
   "breaks the partition twenty-four ways" → "twenty-seven ways".
2. `.github/workflows/ci.yml` `shard-totality-mutations` job: `rows: ["1-12", "13-24"]` →
   `rows: ["1-14", "15-27"]`, and its comments "declares 24 numbered row sites" → "27" and
   "the serial 24-row battery" → "27-row". The DECLARED_TOTAL census + ci.yml tiling arm in
   the guard red both legs if these drift apart in either direction.

## Technical Considerations

- **Anchor uniqueness** (learning `2026-09-23-…-mutation-anchor-can-match-inside-your-own-comment`):
  every anchor above carries the unique `-mutations-b` (or paired `-a`) label; verified exactly
  one occurrence each at current HEAD (`scripts/test-all.sh:3494-3495`). `mutate()` fails
  closed (`ANCHOR MISSING`/`ANCHOR AMBIGUOUS`) on drift, so a stale anchor reports
  measured-NOTHING, never a silent green.
- **Precedent-diff (Phase 4.4):** the `in_range && row "ID" "$RUNNER" 'old' 'new' VERDICT "desc"`
  shape has 13 in-file precedents (ROW1..ROW10, ROW5C, ROW7, ROW8, HARNESS, MUSTPASS); the
  ROWS-SWAP multi-line anchor copies the ROW5C/M5 two-line-anchor form verbatim (ROW7 extends
  the same technique to four lines) — no new mechanics, no novel pattern.
- **Verify-the-negative sweep (Phase 4.45):** the plan's negative claims were probed — the
  battery does not `source test-helpers.sh` (grep empty; #8659 does not reach this file), the
  battery file is not
  in its own dirty-tree refusal set (only `test-all.sh`, `ci.yml`, the guard are), no existing
  `in_range` site mutates a `--rows` registration (24 sites enumerated), `MIN_ROWS=45` is
  untouched (guard file not edited), and no `cp`/`mv`/`rm`/`redirect` operands appear in the
  new rows (baseline count expected unchanged).
- **Dirty-tree refusal:** the battery refuses to run when `scripts/test-all.sh`, `ci.yml`, or
  the guard have uncommitted changes — commit (or the pipeline's commit cadence) before running
  it locally. The battery's own file is not one of the three checked paths, so editing it
  first is fine.
- **Leg cost:** +3 rows ≈ +72 s serial (24-row battery measured ~9.5 min ⇒ ~24 s/row); per
  leg the net is leg-1 +2 rows (absorbs 13-14) and leg-2 +1 (sheds two, gains three), and
  `1-14` remains the larger leg by count (14 vs 13) — still far under the
  `timeout-minutes: 30` budget either way.
- **No new registration:** the battery is invoked from its own ci.yml job, not via `run_suite`
  in `test-all.sh`, so no shard-manifest pin changes are needed.
- **`fixture-relative-assert` baseline:** the new rows contain no `cp`/`mv`/`rm`/redirect
  operands, so the battery's pinned count of 10 flagged `mv-cp` operands should be unchanged;
  the verify step re-runs the suite and regenerates the baseline only if the count moved.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is a
  red `shard-totality-mutations` CI leg on unrelated PRs (internal CI noise).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the change adds test fixtures/assertions over repo-internal scripts only.
- **Brand-survival threshold:** `none`

## Observability

Required by deepen-plan Phase 4.7: the Files-to-Edit list contains non-doc paths
(`plugins/soleur/test/*.sh`, `.github/workflows/ci.yml`), so the gate applies even though the
deliverable is test machinery rather than a production surface. The signals below are the CI
job's own verdict machinery — the thing this plan exists to prove works.

```yaml
liveness_signal:
  what: "shard-totality-mutations CI job verdict — two legs, rows 1-14 and 15-27"
  cadence: "per-PR and per-main-push via .github/workflows/ci.yml"
  alert_target: "required-check red on the PR / red main run (no external paging)"
  configured_in: ".github/workflows/ci.yml — shard-totality-mutations job block"

error_reporting:
  destination: "GitHub Actions job log of the failing leg"
  fail_loud: "battery prints 'FAIL: <id> — SURVIVOR: …' or 'VERDICT: N of M rows FAILED' and exits nonzero"

failure_modes:
  - mode: "mutation anchor drift — the run_suite -a/-b lines are renamed or reshaped"
    detection: "the row's mutate() fails 'ANCHOR MISSING' and the row reports measured-NOTHING (a FAIL, never a silent pass)"
    alert_route: "red shard-totality-mutations leg on whichever PR drifted the anchor"
  - mode: "DECLARED_TOTAL / ci.yml rows-matrix desplit (bump without re-split, or vice versa)"
    detection: "battery's declared-row-drift check reds every leg; the guard's ci.yml tiling arm reds independently"
    alert_route: "red leg + red scripts-shard-totality suite"
  - mode: "guard regression that keeps the tiling arm green over broken registrations"
    detection: "ROWS-GAP / ROWS-DROP report SURVIVOR (guard stayed GREEN under a broken fixture)"
    alert_route: "red leg on the PR that regressed the extractor"

logs:
  where: "GitHub Actions job log — every row prints a '  PASS:' / '  FAIL:' line"
  retention: "GitHub default workflow-log retention"

discoverability_test:
  command: grep -c 'DECLARED_TOTAL=27' plugins/soleur/test/scripts-shard-totality-mutations.sh
  expected_output: "1"
```

## Guard Contract

The deliverable is anti-vacuity coverage for the `run_suite`-argv tiling arm — the new battery
rows are themselves the control, so they get the contract.

### Guard 1 — run_suite --rows extractor mutation coverage

**Property.** A `run_suite "…" bash <file>.sh --rows A-B` registration in
`scripts/test-all.sh` whose ranges fail to tile 1..DECLARED_TOTAL (gap, dropped flag) drives
`plugins/soleur/test/scripts-shard-totality.test.sh` RED end-to-end through the awk extractor,
and a permitted non-canonical ordering keeps it GREEN.

**Assembly.** The single chokepoint is the `row()` helper in
`plugins/soleur/test/scripts-shard-totality-mutations.sh` (mutate → `guard_rc` → verdict →
pristine restore), applied to `$RUNNER`; the member set is every `--rows`-flagged `run_suite`
registration in `scripts/test-all.sh` — currently exactly the `-a`/`-b` pair at origin/main
lines 3494-3495, which the guard's own singleton literal census independently floors.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `…-mutations-b … --rows 9-16` → `--rows 10-16` (gap: battery row 9 in no leg) | RED via `_rows_tile_check` |
| 2 | `…-mutations-b … --rows 9-16` → flag dropped (MIXED contract) | RED via the mixed-contract arm |
| 3 | Swap the `-a`/`-b` registration lines (order-inversion, explicitly permitted) | GREEN — must-PASS on a non-canonical input |
| 4 | Battery's own dispatch: a new row site added without a `DECLARED_TOTAL` bump | battery reds via the declared-row-drift check |

**Anchor.** Every `mutate()` anchor names the unique `-mutations-a`/`-b` label; if a future
edit renames or reshapes the registrations the anchor fails loudly (`ANCHOR MISSING`) rather
than scoring the baseline — the failure message is the drift alarm.

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/test/scripts-shard-totality-mutations.sh` contains three new
  `in_range && row` sites named `ROWS-GAP`, `ROWS-DROP`, `ROWS-SWAP`, appended after the
  `MUSTPASS` row site, with the exact anchors shown in Proposed Solution.
- [ ] AC2: `DECLARED_TOTAL=27` in the battery, and `git grep -n '24' plugins/soleur/test/scripts-shard-totality-mutations.sh .github/workflows/ci.yml` shows no stale "24" count prose for this battery (header comment, ci.yml job comment, matrix ranges all read 27 / `["1-14", "15-27"]`).
- [ ] AC3: `bash plugins/soleur/test/scripts-shard-totality-mutations.sh --rows 25-27` exits 0
  and prints `3 executed` (the three new rows run and pass on the unmutated tree: two RED
  verdicts + one GREEN verdict — all *expected* verdicts).
- [ ] AC4: `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` (full range) exits 0
  with `27 of 27` declared-row accounting (`_row_seq == DECLARED_TOTAL`, `EXECUTED == 27`).
- [ ] AC5: after the DECLARED_TOTAL bump but *before* the ci.yml re-split, running
  `bash plugins/soleur/test/scripts-shard-totality.test.sh` locally goes RED on the ci.yml
  tiling arm — evidence the knock-on is load-bearing, not ceremony (then the re-split makes
  it green; commit only the green state).
- [ ] AC6: `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0; if the
  battery's baseline count moved, regenerate via `--write-baseline` in the same commit.
- [ ] AC7: `git diff origin/main...HEAD --stat` touches exactly:
  `plugins/soleur/test/scripts-shard-totality-mutations.sh`, `.github/workflows/ci.yml`,
  plan/spec artifacts under `knowledge-base/project/`, and (only if AC6 required it)
  `plugins/soleur/test/fixture-relative-assert.baseline.txt`.

## Test Scenarios

- Given the unmutated tree, when the battery runs `--rows 25-27`, then all three new rows
  report PASS (RED-verdict rows red the guard as required; the swap row stays GREEN).
- Given a tree where the `DECLARED_TOTAL` bump lands but the `rows:` matrix still reads
  `["1-12", "13-24"]`, when the guard runs, then the ci.yml tiling arm reports the gap —
  proving the re-split is enforced, not just conventional.
- Given a tree where an anchor drifts (label renamed), when the row runs, then `mutate()`
  fails `ANCHOR MISSING` and the row reports measured-NOTHING rather than PASS.
- Given the shard-totality-mutations CI job, when a PR lands the change, then both legs
  (`1-14`, `15-27`) go green — the row space re-tiles and each half's `EXECUTED` floor holds.

## Implementation Phases

### Phase 0 — Base check (cheap; load-bearing if it fails)

- [ ] Verify: `grep -n 'lint-orphan-test-suites-mutations-b.*--rows 9-16' scripts/test-all.sh`
  returns exactly one line, and `git grep -n _rows_tile_check plugins/soleur/test/` is
  non-empty. (At plan time both hold — the pipeline init commit `e0927dbd24` sits atop the
  `d453170127`-bearing main tip. This step exists because the worktree began the session
  stale; if a future checkout predates the split, run `git merge origin/main` first —
  expected fast-forward — or every mutation anchor below is `ANCHOR MISSING`.)

### Phase 1 — Add the three mutation rows

- [ ] Append the `ROWS-GAP` / `ROWS-DROP` / `ROWS-SWAP` block after the `MUSTPASS` row site in
  `plugins/soleur/test/scripts-shard-totality-mutations.sh` (before the RANGE ACCOUNTING block).

### Phase 2 — Same-commit contract updates

- [ ] `DECLARED_TOTAL=24` → `27`; header "twenty-four ways" → "twenty-seven ways".
- [ ] ci.yml: `rows: ["1-12", "13-24"]` → `["1-14", "15-27"]`; comments "24 numbered row
  sites" → "27", "24-row battery" → "27-row".
- [ ] (Optional but cheap) land Phases 1+2 as one commit — the battery's declared-row-drift
  check reds on every range if they split.

### Phase 3 — Verify

- [ ] `bash plugins/soleur/test/scripts-shard-totality-mutations.sh --rows 25-27` → green (AC3).
- [ ] `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` full range → green (AC4).
- [ ] `bash plugins/soleur/test/scripts-shard-totality.test.sh` → green on the synced tree (AC5
  evidence already collected: red before the ci.yml re-split, green after).
- [ ] `bash plugins/soleur/test/fixture-relative-assert.test.sh` → green (AC6).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal test-machinery change (CI/test battery only,
no user-facing surface, no data, no infra). The mechanical UI-surface override was checked
against the Files lists below: no `components/**`, `app/**/page.tsx`, `pages/**`, `*.njk`,
`*.html`, `*.vue`, `*.svelte`, or `*.astro` paths — exempt. Engineering was assessed against
its question ("significant architectural decisions … beyond normal implementation?") — adding
rows to an existing battery is normal implementation.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (200 cap) for each file below:

- `scripts/test-all.sh` is named in open issues **#8659** (test-helpers EXIT-trap composition —
  this battery does not source `test-helpers.sh`; different surface) and **#7942**
  (`*.mutation.sh` batteries that run in no gate — different files; our battery is
  `*-mutations.sh` and runs from its own ci.yml job). **Disposition: acknowledge** — neither
  is fixed or worsened by this plan.
- No open code-review issue names `plugins/soleur/test/scripts-shard-totality-mutations.sh`,
  `plugins/soleur/test/scripts-shard-totality.test.sh`, or `.github/workflows/ci.yml`.

## Dependencies & Risks

- **Worktree base drift:** the session began on a HEAD predating the split; the pipeline's
  init commit brought it current mid-session. Phase 0's verify greps confirm the anchors'
  presence before any edit — the safe direction is that `mutate()` fails loudly
  (`ANCHOR MISSING`) on a stale tree, never a silent green.
- **Concurrent sibling edits to the registration block:** if another in-flight PR touches the
  `-a`/`-b` lines or `suite-shard-legs.tsv`, the anchors may need re-pointing — `mutate()` will
  fail loudly rather than silently pass (safe failure direction).
- **Leg-time growth:** +3 guard invocations (~72 s serial) on the heaviest job; acceptable,
  but noted as the reason the row count stays at three rather than porting all nine
  locally-driven arms.
- **Sharp-edge notes applied:** multi-line anchor uniqueness verified before commit
  (learning `2026-09-23`); order/lifetime property gets a reorder row, not only delete rows
  (learning `2026-08-20`); the must-PASS row exists because RED-only matrices cannot see a
  reject-everything guard (learning `2026-08-13`); AC scopes derived from the gates' own
  invocations, not hand-enumerated reconstructions (`2026-07-28` sharp edge).

## Files to Edit

- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — three new `in_range && row`
  sites + `DECLARED_TOTAL` bump + header comment.
- `.github/workflows/ci.yml` — `shard-totality-mutations` matrix `rows:` re-split + two
  count-bearing comments.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — **conditional:** only if AC6's
  run shows the battery's flagged-operand count moved (expected not to).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-8990-extractor-mutation-rows/tasks.md`
  (pipeline artifact).

## Success Metrics

- `shard-totality-mutations` CI job green on both re-split legs.
- The next `--rows` registration drift (gap, drop, reorder) is caught by a committed row
  rather than rediscovered in review.

## References & Research

- Issue: #8990 (OPEN), #8864 (CLOSED predecessor), #8967 (split PR), commit `d453170127`.
- Internal: `plugins/soleur/test/scripts-shard-totality-mutations.sh` (row/`mutate`/`guard_rc`
  contract), `plugins/soleur/test/scripts-shard-totality.test.sh` (tiling arm, `_rows_tile_check`,
  origin/main ~L690-990), `scripts/test-all.sh` (origin/main L3494-3495).
- Learnings: `knowledge-base/project/learnings/2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`,
  `knowledge-base/project/learnings/2026-09-25-matrix-k-cannot-split-an-atomic-suite.md`,
  `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`,
  `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md`.
