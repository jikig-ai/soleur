---
feature: ci-orphan-suite-rows-split
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [8864, 8893, 8927, 8923]
brainstorm: knowledge-base/project/brainstorms/2026-09-26-ci-orphan-suite-rows-split-brainstorm.md
status: active
created: 2026-09-26
---

# Spec — Split `lint-orphan-test-suites-mutations` across two shard legs via `--rows`

## Problem Statement

After the 2026-09-25 K=6→K=7 rebalance (#8854), the `test-scripts` light group's
worst leg is a single atomic suite: `lint-orphan-test-suites-mutations` — the
mutation battery for `scripts/lint-orphan-test-suites.sh` (#7402). It measured
588.8 s suite time (~10.2 min wall) on run 36125573947 and is sticky-LPT-pinned
to its own leg at K=7. No matrix leg count can split one suite, so the ~10-min
ceiling rests on this suite's own duration. The issue's ~9.5 min re-evaluation
trigger is already exceeded.

Secondary defect (same file, unblocked by #8763 merging): the comment at
`scripts/test-all.sh` ~4592 claims "the lighter scripts group fans out over six
legs" — false since K=7.

## Goals

- **G1** — Lower the worst `test-scripts` leg below the ~9.5 min trigger by
  splitting `lint-orphan-test-suites-mutations` into two half-suites that the
  duration-aware shard manifest distributes independently.
- **G2** — Zero coverage loss by construction: the executed-row floor and the
  tiling guard fail RED if any declared mutation row stops running.
- **G3** — The split pattern is the one already proven by
  `plugins/soleur/test/scripts-shard-totality-mutations.sh`'s `--rows A-B`
  (DECLARED_TOTAL bounds, range gate at dispatch) — no new mechanics invented.

## Non-Goals

- **NG1** — Moving the suite to `want_scripts_heavy` (rejected at brainstorm:
  relocates the ~9.8 min floor without lowering it; +1 heavy runner, TSV regen).
- **NG2** — Row-splitting `tests/scripts/registry-gate-mutation-battery`
  (14.3–27.9 min contention ceiling): larger DECLARED_TOTAL conversion on a
  ~860 s battery; separately tracked; sequence after this lands.
- **NG3** — Dispositions on #8893 / #8923 / #8927 (kept open as machinery
  ledger / tracker — operator decision D7).
- **NG4** — Duplicate-skip machinery changes (#8919 shipped; residuals in #8927).
- **NG5** — Merge-queue re-adoption (#5780 closed; dormant).

## Functional Requirements

### FR1: `--rows A-B` range gate on `scripts/lint-orphan-test-suites.test.sh`

Add a `--rows A-B` CLI option selecting which declared mutation rows execute.
Semantics copied from `plugins/soleur/test/scripts-shard-totality-mutations.sh`:
`1 <= A <= B <= DECLARED_TOTAL` bounds-check (exit 2 on violation), `0`-unset
means all rows, unknown args error with usage. The gate sits at row dispatch —
rows M1–M16 already run as independent sandboxed workers under a `wait` fan-out,
so a range gate is trivially safe.

### FR2: DECLARED_TOTAL semantics for floors

Introduce `DECLARED_TOTAL` (the count of declared rows). Replace `MIN_ROWS=18`'s
literal executed-floor with: row-sites-reaching-the-range-gate ==
DECLARED_TOTAL regardless of range (a deleted row sites → FATAL), and
range-scope `MIN_ASSERTIONS` to the executed subset. A half-run must never
FATAL the whole-suite floor nor certify a shrunken matrix.

### FR3: Two half-suite registrations in `scripts/test-all.sh`

Register the halves as distinct suites (e.g.
`scripts/lint-orphan-test-suites-mutations-a` `--rows 1-N`,
`-mutations-b` `--rows N+1-TOTAL`) under the existing `want_scripts` block.
`lint-orphan-test-suites.sh` extracts the `*.test.sh` command token — both
registrations union-dedupe into the same surface-1 covered set; the
double-coverage refusal only fires across the six surfaces.

### FR4: Tiling guard

A check (home decided at plan — extend the shard-totality gap-detector or a new
extractor) asserting the registered `--rows` ranges tile 1..DECLARED_TOTAL with
no gaps or overlaps, anchored on the flag argument, never the suite label
(#7103 lesson). Row added + DECLARED_TOTAL bumped + range not extended ⇒ RED.

### FR5: Stale-comment fix

`scripts/test-all.sh` ~4592: "six legs" → "seven legs" (K=7).

## Technical Requirements

### TR1: Extraction anchors preserved

No `*.test.sh` path literal may sit on a `run_suite` line in command position
beyond the real command; heavy-region column-0 `if want_scripts_heavy`/`fi`
shape untouched (Guard 1b derives the heavy reference set from it).

### TR2: Fail-closed invariants

Mutators still fail closed (exactly-once anchor), sandbox stays synthetic
git-repo + TMPDIR=/var/tmp default, `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE`
retained, `env -u TEST_GROUP`/`SCRIPTS_SHARD` guard rows unchanged.

### TR3: Shard-manifest regen

After registration, regenerate `scripts/suite-shard-legs.tsv` from a green run
(`python3 scripts/regenerate-shard-manifest.py --run <id> --write`) so sticky-LPT
distributes the halves; verify no leg exceeds ~9.5 min predicted.

### TR4: Mutation-proof the split itself

The battery's own battery discipline applies: verify a dropped range row goes
RED (tiling guard), a DECLARED_TOTAL/registered-range mismatch goes RED, and
`--rows` out-of-bounds exits 2.

## Observability

- **Primary signal:** per-leg suite times in the regenerated shard manifest +
  `suite-timings-scripts-*` CI artifacts.
- **Discoverability test:** `command` —
  `python3 scripts/regenerate-shard-manifest.py --run <green-run-id>` (dry-run)
  prints predicted per-leg totals; no SSH required.
- **Failure mode → layer:** dropped row range → tiling guard RED on every PR;
  leg re-drifts past ~9.5 min → the runbook trigger in
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  re-fires.
