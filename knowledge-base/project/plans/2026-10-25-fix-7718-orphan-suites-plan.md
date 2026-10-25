---
title: "fix: lint-orphan-test-suites.sh is blind to tests/scripts/ — an unregistered suite there is silently green"
type: fix
date: 2026-10-25
slug: fix-7718-orphan-suites
branch: feat-one-shot-7718-orphan-suites-testsdir
issue: 7718
closes: 7718
lane: engineering
---

# fix: lint-orphan-test-suites.sh is blind to tests/scripts/ — an unregistered suite there is silently green

## Overview

Issue #7718: `scripts/lint-orphan-test-suites.sh` exists to catch a test suite that no runner
executes. It cannot see `tests/scripts/`, for two independent reasons:

1. `scripts/test-all.sh --print-suite-globs` does not list `tests/scripts/**` — `SUITE_GLOBS`
   covers nine `*.test.sh` patterns and nothing else.
2. The naming convention there is `test-<name>.sh` (and `test_<name>.py` for the unittest
   suites), which a `*.test.sh` suffix glob cannot match even if the directory were added.

So a suite added to `tests/scripts/` runs only if someone hand-writes an explicit `run_suite`
line, and nothing detects the omission. The failure is silent and green — the same shape as
#3366, where a harness carrying a PR's entire "the gate cannot silently pass" claim ran in
zero runners.

## Design fork — resolved

The issue names three candidate shapes:

- **(a) Widen the linter's walk to include `tests/scripts/`.** Chosen — but as a *second
  producer keyed on the directory's own conventions*, not by extending the `*.test.sh`
  producer. This is the shape the linter's own header already prescribes ("closing it needs
  a second producer keyed on the `test-*.sh` convention") and the shape the file already
  ships for `tests/commands/*.sh` (#7442): a dedicated loop that walks the directory and
  asserts a `run_suite` registration for every suite-named file.
- **(b) Rename `test-*.sh` → `*.test.sh` and register the glob.** Rejected. ~88 renames plus
  every `run_suite` line, fixture reference, and `AFFECTED_*_PATHS` edge; the `test-*`
  convention is deliberate and shared with `tests/commands/` and `.github/scripts/test/`.
  Worse, adding `tests/scripts/test-*.sh` to `SUITE_GLOBS` would make the glob loop
  auto-execute every match unconditionally under one group — stripping the per-suite
  relevance gating, shard legs, and conditional registration the explicit lines carry — and
  would double-register all 88, which this same linter's disjointness check would red.
- **(c) Explicit per-file registration list the linter checks.** Rejected: a second
  hand-maintained list next to `test-all.sh` is exactly the declaration that falls behind.
  The `run_suite` lines are already the registration list; the correct check asserts the
  file set equals the registered set, not that two hand-lists agree.

**Decision: (a)** — keep explicit `run_suite` registration (it carries per-suite grouping,
shard, and relevance context the auto-glob cannot express), and give `tests/scripts/` the
same dedicated walk `tests/commands/` already has, extended to both suite conventions.

## Census (2026-10-25, `git ls-files 'tests/scripts/'`)

208 tracked files under `tests/scripts/`:

| Class | Count | Registration state |
|---|---|---|
| `test-*.sh` suites (top level) | 88 | ALL registered via `run_suite … bash tests/scripts/<file>` — verified mechanically against the command-anchored regex |
| `test_*.py` unittest suites | 4 (`test_lint_ratchet`, `test_lint_rule_bodies`, `test_lint_rule_ids`, `test_rule_id_regex_parity`) | ALL registered via `run_suite … python3 -m unittest tests.scripts.<module>` |
| Non-suite files | `_git_fixture_env.py`, `trio-baseline.tsv`, `lib/*.sh`/`*.jq` helpers (26), `fixtures/` data (85+) | not suites; outside both suite-naming shapes |

**Zero unregistered suites exist today.** The defect is that nothing guards the next one.

## Implementation

1. **`scripts/lint-orphan-test-suites.sh`** — new block after the `tests/commands/` loop:
   - Producer: `git -C "$REPO_ROOT" ls-files 'tests/scripts/'` (index-bound, like every other
     producer in the file; sees staged files), filtered on the *basename* matching
     `test-*.sh` or `test_*.py`. Basename-keyed rather than top-level-glob so a suite-shaped
     name placed under `lib/` or `fixtures/` is still checked — those subtrees hold helpers
     and data, and a `test-*` basename there is either a suite or a convention violation.
   - `.sh` arm: anchored on `run_suite … bash tests/scripts/<file>` (command position, never
     the label — same anchor shape as the `tests/commands/` check).
   - `.py` arm: anchored on `run_suite … python3 -m unittest tests.scripts.<module>` — the
     registration names the dotted module, not the file path.
   - Per-convention floors, hand-ratcheted like `MIN_TRACKED_SUITES`: `test-*.sh` floor 80
     against 88 measured (slack for real cleanup, not narrowing budget); `test_*.py` floor
     ≥1 (the `tests/commands/` non-empty precedent — empty is a finding, not silent green).
     Separate floors because a combined count cannot see one convention's arm going dark
     while the other keeps the total plausible.
   - Printed walk line (`tests/scripts/: walked N …`), same every-run evidence discipline
     as the main `walked …` line.
   - Header scope note updated: the recorded known-gap text becomes a description of the
     second producer this PR adds; the stale `.github/scripts/test/run-all.sh` MIN_SUITES
     claim in the `tests/commands/` comment is corrected at the same time.
2. **`scripts/lint-orphan-test-suites.test.sh`** — the mutation battery gains five rows
   (DECLARED_TOTAL 30 → 35), and `build_pristine` materialises `git ls-files
   'tests/scripts/'` so the sandbox walks the real 92-file set:
   - M31: a newly created `tests/scripts/test-m31-orphan.sh` with no registration → RED,
     named.
   - M32: delete the `run_suite` line for `tests/scripts/test-tmp-purge.sh` (label absent
     from `ALWAYS_ON_SUITES`/`AFFECTED_CONSUMED_EDGES`, so the kill is attributable to the
     new check alone) → RED, named.
   - M33: delete the `run_suite` `python3 -m unittest` line for
     `tests.scripts.test_lint_rule_ids` → RED, named (the `.py` arm).
   - M34 (two sandboxes): point the `ls-files 'tests/scripts/'` producer at a nonexistent
     dir → `test-*.sh` floor fires; neuter the `test_*.py` case arm → the per-convention
     floor fires.
   - M35: non-suite files (`helper.sh`, `lib/helper-gate.sh`, `fixtures/testdata.sh`,
     `_helper.py`, `notes.tsv`) → GREEN, none named.
   - C0 gains a fourth assertion on the new `tests/scripts/: walked` line.
3. **`scripts/test-all.sh`** — `DECLARED_TOTAL` bump re-splits the two registered ranges
   (`--rows 1-15`/`16-30` → `1-18`/`19-35`) at all four coupled sites (two `run_suite` +
   two `skip_suite` re-run strings); the shard-totality tiling check enforces this.

## Guard Contract

### Guard 1 — a suite-named file under `tests/scripts/` is registered in test-all.sh

**Property.** Every tracked file under `tests/scripts/` whose basename matches the suite
conventions (`test-*.sh`, `test_*.py`) has a `run_suite` registration in `scripts/test-all.sh`
— `bash tests/scripts/<file>` for `.sh`, `python3 -m unittest tests.scripts.<module>` for
`.py` — so a suite there can never run in zero runners while reading as coverage. Files
outside both conventions (`_*` helpers, `*.tsv`, `lib/`, `fixtures/` non-`test-*` members)
are never flagged.

**Assembly.** `tests/scripts/` is registered exclusively by explicit `run_suite` lines in
`scripts/test-all.sh` — verified: `SUITE_GLOBS` carries no `tests/**` entry, no workflow
`run:` line is the sole registration for any member, and all 92 suite-named files match the
two command-anchored regexes today. The guard's producer is `git ls-files 'tests/scripts/'`
filtered on basename, so registration and enumeration share the index as ground truth; a
staged-but-uncommitted suite is inside the domain.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `tests/scripts/test-orphan.sh` to the index with no `run_suite` line | RED — linter names `tests/scripts/test-orphan.sh is never run by test-all.sh` (battery M31) |
| 2 | Delete `run_suite "tests/scripts/tmp-purge" bash tests/scripts/test-tmp-purge.sh` from the runner | RED — names `tests/scripts/test-tmp-purge.sh` (battery M32) |
| 3 | Delete `run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids` | RED — names `tests/scripts/test_lint_rule_ids.py` (battery M33) |
| 4 | Add non-suite files (`helper.sh`, `lib/helper-gate.sh`, `fixtures/testdata.sh`, `_helper.py`, `notes.tsv`) | GREEN — none named as orphans (battery M35) |

**Anchor.** `scripts/lint-orphan-test-suites.sh` is itself in `REQUIRED_RUNNERS`, so its own
`run_suite` line cannot be deleted silently; the battery's single-surface discipline is
unneeded here because `test-*.sh` files are visible to exactly one surface — this check.

### Guard 2 — the tests/scripts/ producer cannot silently narrow

**Property.** The walk's per-convention counts are floored independently (`test-*.sh` ≥ 80,
`test_*.py` ≥ 1), and the walked count is printed on every run, so a producer or
basename-filter that stops enumerating a convention reds rather than passing over a subset
— the same anti-vacuity doctrine as `MIN_TRACKED_SUITES`/`EXPECTED_SUITE_ROOTS` one level up.

**Assembly.** The producer is one `git ls-files 'tests/scripts/'` call feeding a single
`case` filter; the only narrowing points are the pathspec argument and the two case
patterns. Both floors are hand-ratcheted absolutes — there is no second producer to derive
them from, and deriving a floor from the walked set would be deriving it from its own
subject.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Point `ls-files 'tests/scripts/'` at `tests/scripts-nonexistent-dir/` | RED — `test-*.sh` arm enumerates 0, below floor 80 (battery M34a) |
| 2 | Neuter the `test_*.py` case arm so python suites fall to `*)` | RED — `test_*.py` arm enumerates 0 (battery M34b) |
| 3 | Lower/remove the `test-*.sh` floor while narrowing the producer | RED via the printed-count evidence + floor coupling; a floor removal is caught by the battery row that mutates the producer (the floor is the check) |

**Anchor.** `scripts/lint-orphan-test-suites.test.sh` rows M31–M35 are dispatched in
`ROW_IDS`, tiled `1..DECLARED_TOTAL` across the two `--rows` registrations, and the tiling
is asserted by `plugins/soleur/test/scripts-shard-totality.test.sh`.

## Acceptance Criteria

- `bash scripts/lint-orphan-test-suites.sh` exits 0 on the live tree and prints the
  `tests/scripts/: walked 92` line.
- `bash scripts/lint-orphan-test-suites.test.sh` is green end-to-end (C0 + M1–M35).
- A `tests/scripts/test-foo.sh` with no `run_suite` line reds by name; a registered one
  passes; a non-suite file is never flagged.
- `bash scripts/test-all.sh --print-suite-globs` output is unchanged (the decision adds no
  glob — the registration mechanism stays explicit `run_suite` lines).
- `python3 scripts/lint-guard-contract.py` exits 0.
