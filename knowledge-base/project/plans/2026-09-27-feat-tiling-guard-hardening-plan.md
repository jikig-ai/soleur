---
title: "fix: harden the --rows tiling guard — ci.yml-arm committed drivers + widened censuses"
type: fix
date: 2026-09-27
slug: feat-tiling-guard-hardening
branch: feat-one-shot-9035-tiling-guard-hardening
issue: 9035
closes: 9035
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: harden the --rows tiling guard — ci.yml-arm committed drivers + widened censuses

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); no spec.md exists for this branch because no brainstorm ran.

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** Technical Considerations, Guard Contract, Dependencies & Risks
**Research agents used:** none — this plan ran inside a Devin subagent with no
Task-spawn capability, so every deepen-plan pass (halt gates 4.6-4.11,
precedent-diff 4.4, verify-the-negative, self-audit, quality checklist) was
performed inline by the planning orchestrator with mechanical verification —
`Reviewed-Coverage: sequential-fallback`, no independent review is claimed.

### Key Improvements (deepen pass)

1. Census precedent verified: `apps/web-platform/infra/web-host-provisioner-parity.test.sh`
   already enumerates `git -C <repo> ls-files -z --cached --others --exclude-standard`
   with fail-loud on nonzero rc — the Direction-2 widening adopts that exact
   form rather than a novel one.
2. Clean-tree property verified empirically: the recursive comment-stripped
   `scripts/lib/**` census contains zero `--rows` literals today, so the
   widened Direction-1 cannot false-positive the existing tree.
3. New runtime dependency surfaced: the guard gains its first `git` call;
   the battery's `GIT_STUB_DIR` delegates every non-`diff` verb to the real
   git, so `guard_rc` exercises the enumeration unchanged.

### New Considerations Discovered

- Ephemeral fixtures must be `.sh`-named to hit the extension arm of the
  census predicate, and `scripts/lib/zz/` needs `mkdir -p` + dir removal in
  the trap, not only file removal.
- The phantom-job injections must land between `shard-totality-mutations`
  and `grok-fidelity` so the job-block awk's `inj` flag closes on the next
  `^  [a-z0-9_-]+:$` boundary — keeping the census arm (not the extractor)
  the verdict's driver.

## Overview

Harden the `run_suite --rows` tiling guard extended by PR #9027. The three
committed mutation rows cover the runner-argv arm of the guard, but the
parallel ci.yml `rows:`-matrix arm has no committed red-driver, and several
census/extraction regexes accept only one spelling of the constructs they
census — so evasive spellings (`rows :`, `"rows":`, `export`-prefixed
declarations), foreign trees (`tests/`, `apps/`, `infra/`), non-recursive lib
paths, and malformed flag arguments (`--rows 9-16x`) all pass silently. The
plan adds the missing committed drivers and widens the censuses to match the
properties they name, keeping every new check wired to a committed mutation
row so the hardened arms cannot drift back to green-on-miss.

## Research Insights

**Relevant file paths** (all verified against this worktree, 2026-09-27):

- `plugins/soleur/test/scripts-shard-totality.test.sh` — the guard. Tiling
  machinery lives in the block beginning at the `_rows_tile_check` comparator
  through the positive-control row at file end:
  - `_rows_tile_check` (~line 700): the shared contiguous-tiling comparator;
    requires sorted, newline-terminated, well-formed `A-B` input.
  - ci.yml arm (~lines 730-783): `_decl_total` ground-read `sed`,
    `shard-totality-mutations` job-block awk extractor, `--rows`-with-
    `matrix.rows` wire check, and the singleton census
    `grep -cE '^[[:space:]]+rows:' "$CI_YML"`.
  - run_suite-argv arm (~lines 785-921): awk extractor anchored on
    `^[[:space:]]*run_suite[[:space:]]` + `match(line, /--rows[[:space:]]+
    [0123456789]{1,9}-[0123456789]{1,9}/)` (unanchored tail — the
    garbage-suffix hole), per-token loop reading `^DECLARED_TOTAL=` at three
    sites (grep -lE, sed reader, grep -cE counter), distinct-legs pin against
    both committed TSVs and realized `leg_*` files.
  - Direction-1 literal census (~line 929): `sed 's/#.*//'` over
    `$RUNNER` + `$REPO_ROOT/scripts/lib/*.sh` — non-recursive glob.
  - Direction-2 declaration census (~lines 941-957): `grep -rlE
    '^[[:space:]]*DECLARED_TOTAL=[0123456789]+'` scoped to
    `scripts/` + `plugins/soleur/test/`.
  - Assertion floor `MIN_ROWS=45` (~line 978).
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — the battery.
  `DECLARED_TOTAL=27` (line 76); `row()`/`frow()`/`hfrow()` mechanics;
  managed-target set `{RUNNER, GUARD, CI_YML}` with pristine copies + EXIT-trap
  restore + dirty-tree refusal; committed tiling rows are `ROWS-GAP`,
  `ROWS-DROP`, `ROWS-SWAP` at the tail (~lines 693-726); range accounting and
  verdict accounting floors at file end.
- `.github/workflows/ci.yml` — `shard-totality-mutations` job (~lines
  1333-1368): `rows: ["1-14", "15-27"]` matrix (unique literal, verified
  `grep -c` = 1), `run: bash … --rows "${{ matrix.rows }}"` step, comment
  block describing the two-leg split and the ~24 s/row sizing basis.
- `scripts/test-all.sh` — the two committed `--rows` literals at
  `run_suite "scripts/lint-orphan-test-suites-mutations-a"` /
  `…-b"` (lines 3494-3495) splitting
  `scripts/lint-orphan-test-suites.test.sh` (`DECLARED_TOTAL=16` at line 80).
- `scripts/suite-shard-legs.tsv` — `…-a` pinned to leg 3, `…-b` to leg 5
  (lines 351-352).
- `scripts/lib/` — the non-recursive glob misses
  `scripts/lib/frontmatter-strip/strip.sh` and everything under
  `scripts/lib/fixtures/`.

**Institutional learnings applied:**

- `2026-09-26-whitespace-rc-fields-and-guard-population-censuses.md` — the
  origin of this exact machinery; prescribes census arms in both directions
  and "extract what you can, then assert the remainder is empty". This plan
  is that doctrine applied to the three remaining one-spelling censuses.
- `2026-09-24-the-alarm-my-plan-relied-on-could-not-page-and-my-census-read-one-spelling.md`
  — "a census that names the construct it forbids is a census of one
  spelling"; enumerate the grammar before calling a residual-zero guard
  complete. Directly motivates AC2/AC5.
- `2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md` —
  anchors here are chosen on code lines, never comment text.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — RED rows must be paired with must-PASS non-canonical inputs; each new arm
  carries one (`ROWS-CI-ORDER`, `DECL-PREFIX-READER`).
- Mutation-battery mechanics in the file header (~lines 10-24): pristine-copy
  restore, land-then-verify, exact unique anchors, `want_sig` binding the
  verdict to the named arm.

**Premise Validation (Phase 0.6):** Issue #9035 verified OPEN via
`gh issue view 9035 --json state`. Source PR #9027 verified merged (squash
commit `2619b4f5f8` on this branch's base). Both named files exist. Every
claimed gap was re-verified against the code rather than trusted: the
`--rows A-B` literal count in `scripts/test-all.sh` + `scripts/lib/*.sh` is
exactly 2 (matches the issue's re-eval baseline); the singleton-census regex,
the non-recursive lib glob, the two-tree Direction-2 scope, the
`^DECLARED_TOTAL=` anchors, and the unanchored `match()` all exist as
described; repo-wide `git grep` confirms only two tracked
`DECLARED_TOTAL` declarers (the two known batteries) and zero
`export`/`readonly`/`local`-prefixed spellings today — so the widened census
lands on a clean tree. No stale premise found.

**Property List (Phase 0.6b):**

- P1: A gapped ci.yml `rows:` matrix range drives the guard RED through a
  committed battery row (Arm A parity with the run_suite arm).
- P2: A second `rows:` matrix key fails loudly no matter how the key is
  spelled (`rows:`, `rows :`, `"rows":`, column-0).
- P3: A `DECLARED_TOTAL`-declaring battery anywhere in the tracked tree that
  is unreachable by a tiling arm fails the census.
- P4: A malformed `--rows` flag argument fails the guard instead of
  normalizing to a clean prefix.
- P5: `export`/`readonly`/`local`/`declare`-prefixed `DECLARED_TOTAL`
  declarations are read and censused identically to bare ones.
- P6: The previously-undriven sibling sub-arms (`<unresolved>` token,
  all-unflagged, Direction-1 census, distinct-legs manifest pin, recursive
  lib coverage) each have a committed driver.

**Cut List (Phase 0.6b):**

- "Re-split the lint-orphan battery differently" — cut: buys no listed
  property; the existing `-a`/`-b` set is fully covered.
- "Promote `shard-totality-mutations` to a required check" — cut: explicitly
  tracked separately (ci.yml comment above the job, ~line 1331); outside the
  re-eval trigger for this issue.
- "Generalize the singleton census into a per-battery registry" — cut: the
  spelling-tolerant singleton census buys P2 today; a registry is a larger
  mechanism that buys the same property and the issue's own re-eval criterion
  names the condition under which to revisit.
- Every mechanism the issue proposed (Arm A row, census widening, anchored
  extractor, sub-arm rows) buys at least one listed property and none is
  covered by a mechanism already on `origin/main` — verified by reading the
  guard, not asserted.

**Functional overlap (Phase 1.5b, orchestrator-inline):** no community or
registry artifact covers repo-internal guard machinery; internally the guard
is the mechanism (lint-orphan-test-suites.sh is adjacent — registration vs.
assignment — not overlapping). No Task-spawn capability in this harness, so
the check was performed by direct repo inspection.

**Research decision:** external research skipped — strong local context, the
machinery is bespoke to this repo, and two directly-on-point learnings exist.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| Arm A has no committed mutation row | Confirmed — battery rows mutate `$RUNNER` only; `$CI_YML` rows are `ROW5`/`ROW5B`/`ROW5D`/`MUSTPASS`, none touching the `rows:` matrix | `ROWS-CI-*` row family |
| `rows:` singleton census is spelling-fragile | Confirmed — `^[[:space:]]+rows:` misses `rows :`, `"rows":`, column-0 | Spelling-tolerant key regex + three committed drivers |
| Direction-2 scope is two trees | Confirmed — census greps `scripts/` + `plugins/soleur/test/`; `tests/`, `apps/`, `infra/`, `test/`, `spike/`, `bin/`, `todos/` exist outside it | Tracked-file repo-wide census via `git ls-files` |
| `scripts/lib/*.sh` non-recursive | Confirmed — `frontmatter-strip/strip.sh` and `fixtures/` sit outside the glob | Recursive lib-tree enumeration with shell predicate |
| `DECLARED_TOTAL` spelling variants evade | Confirmed — `^DECLARED_TOTAL=`/`^[[:space:]]*DECLARED_TOTAL=` reject keyword prefixes at all four read sites | One shared prefix-tolerant regex constant applied at all sites |
| Garbage-suffix ranges normalize silently | Confirmed — `match()` at the extractor takes the `9-16` prefix of `9-16x`/`9-16-24` | Whole-token capture + malformed-spec fail arm |
| Sub-arms lack committed rows | Confirmed — no row exercises `<unresolved>`, all-unflagged, Direction-1, or the legs pin | Six new committed rows |

## Problem Statement / Motivation

The tiling guard exists to catch coverage drift between `--rows` contracts
and the batteries they split. A guard whose own extraction and census
machinery reads one spelling per construct is a subset guard: every unmatched
shape lands outside the checked population while the verdict stays green —
the exact failure class the machinery was built to eliminate (see the two
learnings cited above). PR #9027 closed the named `-a`/`-b` member set;
this issue is the residual map of what the structural seat found still
unguarded. None of it is user-facing, but a guard that cannot see a drift
shape reports confidence it has not earned.

## Proposed Solution

Two coordinated changes, landed in one PR because the drivers are meaningless
without the widened arms and the widened arms are unverifiable without the
drivers:

1. **Widen the guard** (`scripts-shard-totality.test.sh`): spelling-tolerant
   `rows:`-key census and job-block extraction; whole-token `--rows` capture
   with a dedicated malformed-spec fail; a shared prefix-tolerant
   `DECLARED_TOTAL` regex applied at all four read sites; recursive
   scripts/lib enumeration for Direction-1; tracked-file repo-wide Direction-2
   census with an empty-census fail.
2. **Drive every widened arm** (`scripts-shard-totality-mutations.sh` +
   `ci.yml`): fifteen new committed row sites (Arm A gap/order/second-key
   family, malformed-flag family, sub-arm family, census-scope/prefix family),
   `DECLARED_TOTAL` 27 → 42, the ci.yml matrix re-split three ways
   (`["1-14", "15-28", "29-42"]`), and the managed-target set extended to
   `suite-shard-legs.tsv` and `lint-orphan-test-suites.test.sh`.

## Technical Considerations

- **Assembly semantics for the widened census.** The Direction-2 file set is
  `git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard` —
  tracked plus untracked-non-ignored, which is the set that could reach CI
  (committed) or be exercised locally — intersected with a shell predicate
  (`*.sh`/`*.bash` basename, or extensionless file with a shell shebang) and
  minus `**/fixtures/**` data dirs. `git ls-files` is used rather than
  `grep -r`/`find` because it never descends into `.git`, `node_modules`,
  `.worktrees`, or ignored build output — a plain recursive grep would.
  **Precedent:** `apps/web-platform/infra/web-host-provisioner-parity.test.sh`
  enumerates its `*.tf` universe with the identical `git -C … ls-files -z
  --cached --others --exclude-standard` form and fails loudly on nonzero rc —
  adopt it verbatim (precedent-diff gate 4.4).
  The ephemeral-fixture rows depend on `--others` coverage: an unregistered
  fixture file is untracked, and an untracked file inside a registration tree
  is exactly the pre-commit drift the census exists to see. Enumeration
  failure must fail the guard loudly, never degrade to an empty census.
- **The guard gains its first `git` call.** It currently execs none; the
  census adds `git -C "$REPO_ROOT" ls-files`. The battery's `GIT_STUB_DIR`
  delegates every non-`diff` verb to the real git, so `guard_rc` exercises
  the enumeration unchanged — but a `git` absence/failure must fail the
  guard, not degrade to an empty census.
- **Clean-tree invariance verified (2026-09-27).** The recursive
  comment-stripped `scripts/lib/**` tree contains zero `--rows A-B` literals
  (only a stripped comment at `test-affected-paths.sh`), so widening
  Direction-1 cannot false-positive the existing tree — the CONTROL row
  stays green by measurement, not assumption.
- **One shared declaration regex.** Introduce
  `_DECL_RE`/`_DECL_PREFIX_RE` constants near the top of the guard and apply
  them at all four sites (battery ground-read `sed`, per-token `grep -lE`,
  per-token `sed` reader, `_decl_lines` counter) plus the Direction-2 census
  grep — five call sites on one pattern, so a future prefix cannot widen one
  reader while leaving its sibling blind (the one-spelling class recurring
  inside this fix is the risk this constant exists to foreclose).
- **Whole-token `--rows` capture.** The extractor emits the verbatim next
  token after `--rows`; the per-token loop routes any range field failing
  `^[0-9]+-[0-9]+$` to a dedicated `malformed --rows spec` fail before
  sorting/tiling. This keeps Direction-1's literal-vs-emitted equality intact:
  a `--rows 9-16x` line counts once on each side.
- **Ephemeral-fixture row mechanics.** Three rows need a file that must NOT
  be committed (a permanent fixture would red every run). Add an `erow()`
  helper beside `row()`: write the file inside the census tree → `guard_rc`
  → assert RED + `want_sig` → remove → assert removal; every created path is
  appended to an `EPHEMERAL_FILES` array consumed by the EXIT trap so an
  abort mid-row cannot leak a census-tree file into the next run. Fixture
  names use `.sh` basenames so they hit the extension arm of the census
  predicate without needing an exec bit or shebang; `scripts/lib/zz/` needs
  `mkdir -p` before the write and the trap removes the file AND the now-empty
  dir. Fixture content is inert by construction (a `DECLARED_TOTAL=` line or
  an uncalled function body) so nothing is sourced or executed.
- **Managed-target extension.** `LEGS-COLOCATE` mutates
  `scripts/suite-shard-legs.tsv` and `DECL-PREFIX-READER` mutates
  `scripts/lint-orphan-test-suites.test.sh`; both join the pristine-copy /
  `restore_all` / dirty-tree-refusal / `row()` `case` set. The battery file
  itself (`$0`) is never a target — bash reads scripts incrementally, the
  hazard the file header documents.
- **Split arithmetic.** 27 + 15 sites = `DECLARED_TOTAL=42`. At the measured
  ~24 s/row, two legs would put each leg near ~10 min — nearly double the
  current ~5.5 min on the workflow's longest job. Three legs
  (`["1-14", "15-28", "29-42"]`) holds leg time near ~6 min and matches the
  existing three-leg `test-scripts-heavy` precedent. The singleton census
  counts `rows:` KEYS, not legs, so a third leg inside the same key is
  in-contract. Update the job's comment block (`TWO-LEG` → three-leg, row
  counts) and the battery header (`twice` → three invocations,
  `DECLARED_TOTAL=27` → 42).
- **Anchor discipline.** New mutation anchors: the matrix literal
  `rows: ["1-14", "15-28", "29-42"]` (unique), the `grok-fidelity` job
  boundary for the phantom-job injections, `DECLARED_TOTAL=16   # the gated
  mutation rows` (unique), the TSV line `…-b\t5`, and the existing `-a`/`-b`
  run_suite lines. Anchors sit on code lines only — never comment text (the
  2026-09-23 learning). The phantom-job blocks land between
  `shard-totality-mutations` and `grok-fidelity` so the job-block awk's `inj`
  flag closes on the next `^  [a-z0-9_-]+:$` boundary — the singleton census
  (which reads the whole file) is the verdict's driver, not the extractor.
- **`want_sig` coverage.** Every RED row carries the 7th-arg signature bound
  to its arm's fail text so a red raised by an unrelated arm cannot satisfy
  the row.
- **`MIN_ROWS` in the guard.** Re-derive at implementation: 45 + the number
  of new assertion sites the widening adds (est. 2-4: empty-census check,
  malformed-spec arm emits inside the existing loop).
- **Concurrency.** A third leg adds one parallel job; `test-scripts-heavy`
  already runs three legs, so pool shape is precedented.
- NFR assessment: no NFRs touched — CI-internal test machinery; no
  performance, security, or reliability surface outside the pipeline itself.

## Files to Edit

- `plugins/soleur/test/scripts-shard-totality.test.sh` — the five
  widenings + shared decl-regex constant + `MIN_ROWS` re-derivation.
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` —
  `DECLARED_TOTAL` 27→42, `erow()` helper + `EPHEMERAL_FILES` trap wiring,
  managed-target set +2, fifteen new row sites, header comment updates.
- `.github/workflows/ci.yml` — matrix re-split to three ranges + job comment
  block update.

## Files to Create

None committed. (`erow()` writes runtime fixtures under `apps/` and
`scripts/` that are created and deleted inside single battery rows.)

## Open Code-Review Overlap

None — the only open `code-review` issue naming the planned files is #9035,
this plan's own issue. Checked 2026-09-27 against all five planned paths via
`gh issue list --label code-review --state open` + `jq --arg` substring match.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is internal: a widened census with a false positive would red
  the `test-scripts` suite on unrelated PRs (CI friction, visible and
  revertible); a widened arm with a false negative reproduces today's silent
  gap.
- **If this leaks, the user's workflow is exposed via:** nothing — no data,
  credential, or user-workflow surface is touched; the diff is confined to
  test files and one workflow matrix literal.
- **Brand-survival threshold:** `none`

*Sensitive-path check:* the planned file list was evaluated against the
preflight `SENSITIVE_PATH_RE` (Check 6 Step 6.1) — `ci.yml` matches none of
the workflow-token patterns and the test files match nothing — so the
`threshold: none` scope-out bullet is not required.

## Observability

```yaml
liveness_signal:
  what:            # shard-totality-mutations job result on every PR; the guard
                   # suite itself runs inside the required test-scripts legs
  cadence:         # per-PR
  alert_target:    # PR check status (shard-totality-mutations context, and the
                   # required test check for guard regressions)
  configured_in:   # .github/workflows/ci.yml — shard-totality-mutations job

error_reporting:
  destination:     # GitHub Actions job log for the failing leg
  fail_loud:       # nonzero battery exit → red shard-totality-mutations context
                   # on the PR; guard regression → red required test check

failure_modes:
  - mode:          # a mutation row SURVIVOR (guard stays green under a mutation)
    detection:     # the row's own fail verdict in the battery log
    alert_route:   # red shard-totality-mutations leg on the PR
  - mode:          # a widened census false-positives on a clean tree
    detection:     # the battery CONTROL row goes RED → battery exits 2 VOID
    alert_route:   # red shard-totality-mutations leg on the PR
  - mode:          # an ephemeral fixture leaks into the census tree after an abort
    detection:     # next run's census reports it as unregistered (NEITHER fail)
    alert_route:   # red guard inside the required test-scripts leg

logs:
  where:           # GitHub Actions job log per matrix leg
  retention:       # GitHub default (~90 days)

discoverability_test:
  command:         # grep -c 'scripts-shard-totality-mutations.sh --rows' .github/workflows/ci.yml
  expected_output: # 1
```

## Guard Contract

### Guard 1 — ci.yml `rows:`-matrix tiling arm (Arm A)

**Property.** Every `rows:` matrix key in ci.yml is spelled detectably, exactly
one exists, and the shard-totality-mutations matrix ranges tile
1..DECLARED_TOTAL contiguously and reach the run step as the
`${{ matrix.rows }}` interpolation.

**Assembly.** The chokepoints are the ci.yml file itself (every `rows:`-shaped
key anywhere in the workflow, spelling-tolerant) and the
`shard-totality-mutations` job block (matrix literal + run step). There is one
census over the whole file — a key in ANY job block counts, because a split
contract is not scoped to the job the guard knows about.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `ROWS-CI-GAP`: last leg's lo-bound +1 (`29-42` → `30-42`) | RED — "mutation row ranges do not tile" |
| 2 | `ROWS-CI-KEY2`: inject a phantom job block with a canonical `rows:` key | RED — "rows: matrix keys" |
| 3 | `ROWS-CI-KEY2-SPACE`: phantom job with `rows :` spelling | RED — spelling-tolerant census counts it |
| 4 | `ROWS-CI-KEY2-QUOTE`: phantom job with `"rows":` spelling | RED — spelling-tolerant census counts it |
| 5 | `ROWS-CI-ORDER`: reorder the three range literals | GREEN — sort-before-tile must-PASS |
| 6 | Dispatch: delete the `rows:` key entirely | RED — "declares no rows: ranges" (existing arm) |
| 7 | Harness: neuter `_rows_tile_check` to `return 0` | RED — existing positive control catches it |

**Anchor.** The census reads the committed ci.yml — the same blob the merge
carries — so integrity comes from the singleton-count property itself: any
second key, however spelled, moves the count off one. The battery's
`DECLARED_TOTAL` pin is independently asserted by the `_row_seq` floor, so a
weakening cannot pass by shrinking the declared space.

### Guard 2 — run_suite-argv tiling arm + extraction boundary

**Property.** Every `--rows` flag argument on a registration is a well-formed
`A-B` range, and the ranges for each DECLARED_TOTAL-declaring token tile
1..DECLARED_TOTAL contiguously on distinct legs.

**Assembly.** The chokepoints are the `run_suite`/`skip_suite` call sites in
`scripts/test-all.sh` (the only registration path — line-start shape is the
anchor, and Direction-1's literal census is the remainder-is-empty check over
the runner plus every sourced lib file, recursively), the per-token battery
files the registrations name, and the two committed shard-leg TSVs for the
distinct-legs pin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `ROWS-MALFORMED-SUFFIX`: `--rows 9-16` → `--rows 9-16x` | RED — "malformed --rows spec" |
| 2 | `ROWS-MALFORMED-TRISEG`: `--rows 9-16` → `--rows 9-16-24` | RED — "malformed --rows spec" |
| 3 | `ROWS-UNRESOLVED`: `bash` → `sh` on the -a registration | RED — `<unresolved>` token fails the decl arm |
| 4 | `ROWS-ALL-UNFLAGGED`: drop both `--rows` flags (two-line anchor) | RED — "carry no --rows" |
| 5 | `DIR1-MIDLINE`: `run_suite …` → `true && run_suite …` (mid-line call shape) | RED — "literal census" (emit < lit) |
| 6 | `DIR1-LIBSUBDIR`: ephemeral `scripts/lib/zz/x.sh` holding an uncalled function with a `--rows` literal | RED — "literal census" proves recursive reach |
| 7 | `LEGS-COLOCATE`: TSV `-b` leg 5 → 3 | RED — "pin to legs" |
| 8 | `DECL-PREFIX-READER` (must-PASS): `DECLARED_TOTAL=16` → `export DECLARED_TOTAL=16` | GREEN — prefix tolerance end-to-end |
| 9 | Second member after a compliant first: any row above adds a second `--rows` contract beside the working `-a`/`-b` pair | covered by rows 1-7 mutating one member of a working set |

**Anchor.** The extractor's own blindness is bounded by Direction-1's
count-equality: a registration shape the anchor cannot see still inflates the
literal side. The distinct-legs pin reads the committed TSVs — the same data
the merge ships — and the realized `leg_*` files, so both the declared and the
realized assignment must agree.

### Guard 3 — DECLARED_TOTAL declaration census (Direction 2)

**Property.** Every file-scope `DECLARED_TOTAL` declaration in the tracked +
untracked-non-ignored shell-bearing tree — any spelling of the declaration
keyword — is reachable by a tiling arm (run_suite argv or the ci.yml
`rows:` run step).

**Assembly.** The chokepoint is "a file declares the contract": the census
enumerates `git ls-files --cached --others --exclude-standard` ∩ (`.sh`/
`.bash` basename or extensionless-with-shell-shebang) minus `**/fixtures/**`,
repo-wide — not a tree allowlist, so a battery under `tests/`, `apps/`,
`infra/`, `test/`, `spike/` or any future tree is inside the property by
construction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `DECL-SCOPE-FOREIGN`: ephemeral `apps/zz-decl-scope-battery.sh` with `DECLARED_TOTAL=3`, unregistered | RED — "registered in NEITHER run_suite argv nor a ci.yml" |
| 2 | `DECL-PREFIX-CENSUS`: ephemeral `scripts/zz-decl-prefix-fixture.sh` with `export DECLARED_TOTAL=2`, unregistered | RED — prefixed declaration enters the census |
| 3 | `DECL-PREFIX-READER` (must-PASS): `DECLARED_TOTAL=16` → `export DECLARED_TOTAL=16` on the registered lint-orphan battery | GREEN — the reader tolerates the prefix (shared row with Guard 2) |
| 4 | Dispatch: census enumerates zero files | RED — new `[[ -s decl_census ]]` fail-closed check |
| 5 | Second member: either ephemeral row adds a second declarer beside the two compliant batteries | covered by rows 1-2 |

**Anchor.** The census cannot certify itself because its input set is derived
from git's own enumeration — a weakening must survive both `git ls-files` and
the shell predicate, and row 4 keeps "the census saw nothing" a failure rather
than a green zero.

## Implementation Phases

### Phase 1 — Widen the guard (`plugins/soleur/test/scripts-shard-totality.test.sh`)

- 1.1 Add `_DECL_PREFIX_RE`/`_DECL_RE` constants near the top
  (`(export|readonly|local|typeset|declare)` keyword whitelist, optional flag
  argument for `declare -x` shapes) and apply at all five read sites:
  battery ground-read `sed`, per-token `grep -lE`, per-token `sed` reader,
  `_decl_lines` counter, Direction-2 census grep.
- 1.2 Spelling-tolerant `rows:` census regex
  (`^[[:space:]]*["']?rows["']?[[:space:]]*:`) and the same tolerance in the
  job-block awk (`inj &&` match + the `gsub` extraction).
- 1.3 Whole-token `--rows` capture in the awk extractor; per-token loop gains
  a `malformed --rows spec '<tok>'` fail for range fields failing
  `^[0-9]+-[0-9]+$`, evaluated before sorting.
- 1.4 Direction-1: replace `scripts/lib/*.sh` with the recursive
  `git ls-files`-based lib-tree enumeration (same shell predicate).
- 1.5 Direction-2: replace the two-tree grep with the repo-wide
  `git ls-files --cached --others --exclude-standard` enumeration ∩ shell
  predicate minus `**/fixtures/**`; enumeration failure fails loudly; add the
  `[[ -s decl_census ]]` fail-closed check.
- 1.6 Re-derive `MIN_ROWS` for the new assertion sites.
- **Success criterion:** the guard exits 0 on the unmutated tree (CONTROL
  stays green — the widenings are verified non-destructive before drivers
  land).

### Phase 2 — Battery drivers + managed set (`plugins/soleur/test/scripts-shard-totality-mutations.sh`)

- 2.1 Extend the managed-target set: `scripts/suite-shard-legs.tsv` and
  `scripts/lint-orphan-test-suites.test.sh` get pristine copies,
  `restore_all` entries, `row()` `case` arms, and dirty-tree-refusal list
  entries.
- 2.2 Add `erow()` + `EPHEMERAL_FILES` trap wiring.
- 2.3 Land the fifteen row sites: `ROWS-CI-GAP`, `ROWS-CI-ORDER`,
  `ROWS-CI-KEY2`, `ROWS-CI-KEY2-SPACE`, `ROWS-CI-KEY2-QUOTE`,
  `ROWS-MALFORMED-SUFFIX`, `ROWS-MALFORMED-TRISEG`, `ROWS-UNRESOLVED`,
  `ROWS-ALL-UNFLAGGED`, `DIR1-MIDLINE`, `DIR1-LIBSUBDIR`, `LEGS-COLOCATE`,
  `DECL-SCOPE-FOREIGN`, `DECL-PREFIX-CENSUS`, `DECL-PREFIX-READER` —
  grouped by arm after `ROWS-SWAP`, each `in_range`-gated, every RED row
  carrying its `want_sig`.
- 2.4 `DECLARED_TOTAL` 27 → 42; header comment updates (three invocations,
  new total).
- **Success criterion:** `bash … --rows 1-42` locally reports every new row
  landing and scoring as designed.

### Phase 3 — Re-split the matrix (`.github/workflows/ci.yml`)

- 3.1 `rows: ["1-14", "15-27"]` → `rows: ["1-14", "15-28", "29-42"]`; update
  the job's split comment (two-leg → three-leg, row counts, sizing basis).
- **Success criterion:** `git diff` on ci.yml touches only the matrix literal
  and its comment; the singleton `rows:` key count stays 1.

### Phase 4 — Verify

- 4.1 `bash plugins/soleur/test/scripts-shard-totality-mutations.sh
  --rows 1-14`, `15-28`, `29-42` each report all-in-range rows green.
- 4.2 `bash plugins/soleur/test/scripts-shard-totality.test.sh` exits 0 on
  the clean tree.
- 4.3 `python3 scripts/lint-guard-contract.py
  knowledge-base/project/plans/2026-09-27-feat-tiling-guard-hardening-plan.md`
  exits 0.
- 4.4 Full `scripts/test-all.sh scripts` shard containing the guard suite.

## Domain Review

**Domains relevant:** Engineering (infrastructure/tooling change)

### Engineering

**Status:** reviewed (orchestrator-inline — no Task-spawn capability in this
Devin subagent harness; the assessment was performed by the planning
orchestrator against the domain question, not by an independent leader agent —
sequential-fallback disclosure, no independent review is claimed)
**Assessment:** Architectural decision: none — the change hardens an existing
guard inside its existing contract (no boundary move, no new substrate, no
new trust boundary; Phase 2.10's "would a competent engineer reading only the
ADRs + C4 be misled" test answers no). Complexity is concentrated in the
census-scope widening, addressed by the `git ls-files` enumeration semantics
and the ephemeral-fixture mechanics in Technical Considerations.

No cross-domain implications detected — meta/machinery change confined to CI
test infrastructure (`domain/engineering`, `meta/machinery` per the issue's
labels).

## Acceptance Criteria

- [ ] AC1: `ROWS-CI-GAP` — a committed battery row mutating the ci.yml
  `rows:` matrix ranges drives the guard RED via the "mutation row ranges do
  not tile" arm (Arm A committed driver).
- [ ] AC2: A second `rows:`-shaped matrix key fails the singleton census
  under each spelling — `rows :` and `"rows":` — via `ROWS-CI-KEY2-SPACE` and
  `ROWS-CI-KEY2-QUOTE`; canonical `rows:` duplication stays caught via
  `ROWS-CI-KEY2`.
- [ ] AC3: A `DECLARED_TOTAL`-declaring battery under `apps/` (or `tests/`)
  that no tiling arm reaches fails the Direction-2 census via
  `DECL-SCOPE-FOREIGN`; a registration through a non-`bash` command token
  fails via `ROWS-UNRESOLVED`.
- [ ] AC4: `--rows 9-16x` and `--rows 9-16-24` fail the guard via the
  malformed-spec arm rather than extracting as `9-16` — `ROWS-MALFORMED-*`.
- [ ] AC5: `export`/`readonly`/`local`-prefixed `DECLARED_TOTAL` declarations
  enter the census and the per-token readers — `DECL-PREFIX-CENSUS` (RED) and
  `DECL-PREFIX-READER` (GREEN on the registered battery).
- [ ] AC6: `DECLARED_TOTAL` reads 42; the ci.yml matrix tiles
  `["1-14", "15-28", "29-42"]`; each leg's battery run reports all-in-range
  rows scored.
- [ ] AC7: The unmutated CONTROL row stays green on the clean tree — no
  widened census false-positives the existing tree.
- [ ] AC8: `lint-guard-contract.py` exits 0 against this plan; the guard's
  own suite passes inside `scripts/test-all.sh scripts`.

## Test Scenarios

- Given the committed tree, when the battery runs any declared range, then
  the CONTROL row reports GREEN before any mutation row executes.
- Given `rows: ["1-14", "15-28", "30-42"]` in ci.yml, when the guard runs,
  then the tiling arm reports a gap at 29 and the battery scores ROWS-CI-GAP
  RED.
- Given a phantom job block carrying `rows :` or `"rows":`, when the guard
  runs, then the singleton census reports >1 keys regardless of spelling.
- Given an unregistered `apps/zz-decl-scope-battery.sh` declaring
  `DECLARED_TOTAL=3`, when the guard runs, then Direction-2 reports it
  reachable by NEITHER arm.
- Given `--rows 9-16x` on a registration, when the guard runs, then the
  malformed-spec arm fails before the range reaches the comparator.
- Given `export DECLARED_TOTAL=16` on the lint-orphan battery, when the
  guard runs, then the per-token reader, declaration-line counter, and
  census all resolve 16 — GREEN.
- Given `true && run_suite "…-a" …` on the -a registration line, when the
  guard runs, then Direction-1 reports 2 literals vs 1 extracted.
- Given the TSV pin moved `-b` onto leg 3, when the guard runs, then the
  distinct-legs arm reports `3,3`.
- Given an abort mid-`erow`, when the battery exits, then the EXIT trap has
  removed every path in `EPHEMERAL_FILES` and the next run's census is clean.

## Success Metrics

- All five issue acceptance criteria driven by committed rows that re-run on
  every PR (not one-time evidence).
- Battery: 42 declared sites, zero SURVIVORs, both census directions at
  equality on the clean tree.
- Leg wall time stays ≤ ~7 min (three-leg re-split at the measured ~24 s/row).

## Dependencies & Risks

- **Battery runtime growth:** 27→42 rows nearly doubles serial time —
  mitigated by the three-leg re-split; residual risk is the job stays the
  workflow's longest leg either way.
- **Ephemeral-fixture leakage:** an abort between create and delete could
  leave a census-tree file — mitigated by `EPHEMERAL_FILES` + EXIT trap;
  a leaked fixture is loud (next run's census flags it), never silent.
- **False-positive census hits:** an untracked scratch `.sh` containing a
  file-scope `DECLARED_TOTAL=` under a developer's tree reds the guard
  locally — intended behavior (the declaration is the contract), documented
  in the guard comment; ignored files (`.worktrees`, `node_modules`) are
  outside the enumeration by `--exclude-standard`.
- **Regex over-tolerance:** the keyword whitelist could admit
  `somevarDECLARED_TOTAL`-style false hits — mitigated by anchoring the
  keyword run to line-start with whitespace separators and pinning behavior
  with the GREEN/RED prefix rows.
- **Anchor drift:** mutation anchors on `rows: ["1-14", "15-28", "29-42"]`
  are written against the post-change literals; the battery's own
  anchor-missing/ambiguous refusals surface drift as row failures, not
  survivors.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled at authoring time.
- Mutation anchors must never be written against comment text — comments are
  stripped per-line before extraction and can neither fabricate nor hide a
  range, but an anchor that matches a comment line mutates nothing.
- The battery file must never appear in its own managed-target set — bash
  reads scripts incrementally by byte offset.
- Ephemeral fixtures must use `.sh` basenames (extension arm of the census
  predicate) and must never be `source`d shapes — content stays inert
  (declaration line or uncalled function body).
- `want_sig` strings must be copied from the actual fail-message literals in
  the guard, not paraphrased — the signature binds the verdict to the arm.

## References & Research

- Issue: #9035 (open) — review-residual from PR #9027
- Source PR: #9027 (merged, squash `2619b4f5f8`)
- Origin brainstorm: `knowledge-base/project/brainstorms/2026-09-26-ci-orphan-suite-rows-split-brainstorm.md` (D2–D5 created this machinery)
- Predecessor spec dir: `knowledge-base/project/specs/feat-one-shot-8990-extractor-mutation-rows/`
- Guard: `plugins/soleur/test/scripts-shard-totality.test.sh`
- Battery: `plugins/soleur/test/scripts-shard-totality-mutations.sh`
- Matrix: `.github/workflows/ci.yml` `shard-totality-mutations` job
- Learnings:
  - `knowledge-base/project/learnings/2026-09-26-whitespace-rc-fields-and-guard-population-censuses.md`
  - `knowledge-base/project/learnings/2026-09-24-the-alarm-my-plan-relied-on-could-not-page-and-my-census-read-one-spelling.md`
  - `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
