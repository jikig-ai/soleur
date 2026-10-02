---
title: "feat: make the affected pre-pass cheap and close the PR 1 residuals (#9307)"
date: 2026-10-01
slug: cheap-affected-prepass-and-pr1-residuals
branch: feat-one-shot-9307-affected-prepass-cheap
issue: 9307
closes: none  # PR body says `Ref #9307`, never `Closes`; the umbrella stays open for PR 2 and PR 3
type: feat
lane: cross-domain
priority: p2
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: make the affected pre-pass cheap and close the PR 1 residuals (#9307)

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** Delivery shape, Research Reconciliation, Value-proposition measurement, PR-A phases (0, A1-A4), Guard Contract (1, 2), Acceptance Criteria, Quality Gates, References
**Agents used:** architecture-strategist, pattern-recognition-specialist, performance-oracle, test-design-reviewer, code-quality-analyst, spec-flow-analyzer, security-sentinel, framework-docs-researcher, git-history-analyzer (after the plan-review panel: DHH, Kieran, code-simplicity, CTO)

### Key Improvements

1. The byte-identity contract now accounts for the one registration PR-A adds (row-set comparison with a declared added-label list and summary arithmetic) instead of demanding a stream that cannot exist.
2. The bench times the base side too (interleaved), so the headline factor no longer compares a load-44 baseline with load-12 head runs; bench hardening added (rev resolution, `mktemp -d`, `GIT_*` scrub, `env -u` on the child).
3. A3 is stated honestly as a constant-factor gain (O(length) string test, 4-7x smaller constant) and now covers the two other linear scans profiling found (`_seen`, `_FE_FILES`), with the per-token `_affected_normpath` fork as an A4 candidate.
4. The shadow-set reset is one new function defined inside the range the t11/m9 helper evals; the `eval`-fed site rebuilds the set. Guard 2 gained boundary, placement, prefix-collision and per-assignment-site rows.
5. CI-visible proof of identity is stated plainly: the bench is operator-attested; CI keeps the derive suite and the ratchet; the reference sha256 goes in the ADR amendment for PR-B.

### New Considerations Discovered

- A cap trip can silently drop a real edge (fail-open selection). Failing safe changes selection, so it is a PR-B item.
- `BASH_COMPAT` does not disable `patsub_replacement`; the shopt is the only switch (bash manual).
- ubuntu-24.04 ships bash 5.2.21 (runner-images README), so CI has the option on; the suite asserts the version rather than assuming it.
- Locale changes post-A3 timing 3-4x; the bench records it.

## Overview

Spec lacks a valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (fail-closed).

Umbrella #9307 PR 1 (squash 9c5252e644, merged 2026-10-01) anchored the edge matcher, added
`--print-selection`, audited the always-on floor and added a dropped-consumer ratchet. It did not make the
local affected pre-pass cheap: every local `--affected` run still spends about 11 minutes of CPU deriving
source closures before any suite starts, and the dropped-consumer ratchet pays one full walk of the same cost
on a CI leg. This plan makes that derive cheap with a selection that is byte-identical before and after, and
carries the remaining PR 1 residual checklist (re-demotion, heavy batteries, ratchet breadth, edge-minting
fixes) as follow-on PRs. PR 2 (plugin-shipped gate) and PR 3 (opt-in shard launcher) of the umbrella are out of
scope and are not started here.

### Delivery shape (review result: split)

The operator's brief said "one PR unless review says split". The review panel (three of four seats) said split,
for one reason that is also the plan's strongest property: Phase A is the only phase whose acceptance is
"output byte-identical", and bundling selection-changing work (B-D) into the same diff destroys that review
contract and enlarges the blast radius of a diff that, because it touches `scripts/test-all.sh`, degrades the
local gate to a full run and leaves CI as the only gate.

| PR | Scope | Acceptance | State |
|---|---|---|---|
| PR-A (this branch, draft #9375) | Phase 0 (bench, derive suite), A1, A2, A3 (edge set, `_seen`, `_FE_FILES` index), profile-gated A4, ADR-242 decision 16 and corrected cost figures, the learning | selection byte-identical; factor reported | planned in full below; implemented by `soleur:work` |
| PR-B (own branch off main after PR-A) | B1 recorder, B2 re-demote `scripts/domain-model-drift`, B3 audit Round 2, D2 ratchet breadth, D3 subcommand forms, D4 deleted declared subject | selection changes by design; each re-baselined | planned below at design level; re-filed on #9307 at ship time |
| PR-C (own branch off main after PR-B) | A5 runner as a closure leaf, D1 `REPO_ROOT` idiom, Phase C heavy batteries | selection changes by design; A5 and D1 decided together | planned below at design level; re-filed on #9307 at ship time |
| Post-merge | D5 regenerate the shard manifest from CI timing artifacts | none (data refresh) | tracked issue |

Each follow-on is re-filed on #9307 with the measured reason it is separate: its selection delta, and for D3
that no registration mints the form today. This choice and the 10x tension below are recorded in
`knowledge-base/project/specs/feat-one-shot-9307-affected-prepass-cheap/decision-challenges.md` for the operator
to reverse.

### What the plan-time measurements changed

The dominant cost is not the comment-token and O(n) scan story the issue and ADR-242 tell. Three measured
mechanisms, in order of size:

1. On bash 5.2 and later, `patsub_replacement` makes an unquoted `&` in the replacement of
   `${var//pat/rep}` expand to the matched text. `_affected_resolve_vars` substitutes captured variable values
   (a greedy capture of `REPO_ROOT="$(cd "$(dirname ...)/.." && pwd)"` contains `&&`) into a token, so each of
   its up to 12 iterations multiplies the token. Tokens reach 165-307 KB and every later `${_p//..}` in
   `_affected_edge_token` then takes seconds. Self-referential values (`t7_repo="$(mktemp -d)"; mkdir -p
   "$t7_repo/src"`) double the token per iteration with no `&` at all.
2. Eighteen non-always-on registrations whose closure reaches `scripts/test-all.sh` (24 counting the always-on
   ones the real run skips) each replay about 450 cached edges across about 780 cached files through O(n)
   membership scans, about 2.5 s each.
3. Per-file scans of about 776 distinct files cost about 78 ms of CPU each, mostly per-token bash loops and a
   linear variable-name lookup, not forks.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #9307, ADR-242 amendment, always-on audit) | Reality (measured 2026-10-01 at HEAD c2564f1f6d, scratch worktrees, nothing committed) | Plan response |
|---|---|---|
| The pre-pass cost is the closure following comment tokens (a suite whose comment names `test-all.sh` pulls that file in) plus an O(n) `_affected_in_list` scan | `scripts/domain-model-drift`'s closure is ONE file and ONE edge; it never reaches `test-all.sh`. All 63 s of its CPU (82 s under load, the audit's figure: a real measurement whose attached cause was an inference) is inside `_affected_edge_token` on 250 KB tokens produced by variable resolution. Comment-following is not the cause for any of the eight suites profiled | Reorder the levers: bound variable resolution first (A1, A2), then the membership scan (A3). "Stop following comment tokens" is cut (Cut List); its principled cousin, the runner as a closure leaf, is A5 in PR-C |
| Eight of 533 registrations are 73% of the cost (534 are runnable today) | Confirmed: after bounding resolution the same eight suites drop from 18-72 s of CPU each to under 1 s, except `resolve-regenerable-conflicts` (3 s) | The eight are the first beneficiaries; PR-A's acceptance reports them |
| `REPO_ROOT=...` "loses its `/..` in `_affected_edge_token`" | True on bash 3.2 to 5.1. On bash 5.2 and later the value is corrupted one step earlier: `&&` in the captured value becomes `$REPO_ROOT$REPO_ROOT`. Selection therefore depends on the bash version today (CI and the operator host are bash 5.x with `patsub_replacement` on; stock macOS is 3.2) | A1 (PR-A) makes resolution literal on every bash; D1 (PR-C) fixes the `/..` loss and needs A1 first. The version dependence is recorded as a defect in the ADR amendment |
| Dropped-consumer ratchet costs about 11 minutes | Confirmed: baseline 938.7 s wall, 649.9 s user+sys for `--print-selection --paths=README.md` | The ratchet inherits the PR-A result |
| `scripts/suite-shard-legs.tsv` has a row for the ratchet to rebalance | The label `scripts/test-affected-kb-consumers` is in neither `suite-shard-legs.tsv` nor `suite-durations.tsv`; it falls back to default weight | D5 is a regeneration from fresh CI timing artifacts, which need post-PR-A runs: a post-merge follow-up, not a same-PR edit |
| 71 of 292 derived suites "lose edges" under the REPO_ROOT idiom | A scratch prototype of D1 on top of A1 (not on main) changes 108 rows, adds 10,120 edges, removes edges from 23 rows (wrong-path edges that happened to exist), flips one suite to `unclassified`, and makes a README-only diff select 146 suites instead of 122, because 23 more suites now carry an exact `^README.md` edge through the runner closure | D1 is selection-changing and widening and roughly doubles the walk (217 s against 105 s); it is PR-C, decided together with A5 |

## Premise Validation (Phase 0.6)

Checked and held: #9306 is MERGED (merge commit 9c5252e644, 2026-10-01T13:52:30Z); #9375 is the open draft PR for
this branch; #9307 is OPEN; every function the issue names exists at HEAD (`_affected_derive`,
`_affected_file_edges`, `_affected_file_edges_uncached`, `_affected_resolve_vars`, `_affected_edge_token`,
`_affected_add_edge`, `_affected_in_list`); `scripts/regenerate-shard-manifest.py`, `scripts/suite-shard-legs.tsv`
and the battery-tag scripts (`scripts/battery-tag-authorship.test.sh`,
`scripts/battery-tag-authorship-mutations.test.sh`) exist. ADR corpus: ADR-242 is the owner; its alternatives
tables reject "drop the always-on class" and "run the ratchet over declared arrays only"; neither is proposed
here. No ADR rejects bounded variable resolution or a runner-leaf closure. Stale: the attribution of the cost to
comment tokens (above).

## Property List and Cut List (Phase 0.6b)

Properties the work must buy, and the mechanism that buys each:

| Property | Mechanism (PR) |
|---|---|
| P1. A local `--affected` pre-pass costs a fraction of the current ~11 minutes of CPU | A1, A2, A3 (PR-A); A5 (PR-C) |
| P2. The pre-pass output (class, selected bit, edge set and its order, summary) is unchanged by the speedup | `scripts/affected-prepass-bench.sh` compare, Guard 1, Guard 2 (PR-A) |
| P3. A demoted suite does not cost the pre-pass more than it saves | B2 (PR-B), cheap by A1 and A2 |
| P4. A diff that cannot change a heavy battery's verdict does not pay that battery's wall time locally | Phase C (PR-C) |
| P5. The dropped-consumer ratchet sees the read forms the demoted suites actually use | D2, Guard 3 (PR-B) |
| P6. Edge minting follows the repo's own idioms (`REPO_ROOT`, runner subcommands, a deleted declared subject) | D1 (PR-C), D3 and D4 (PR-B) |
| P7. Audit evidence is reproducible, and its blind spots are detected rather than stated | B1, Guard 4 (PR-B) |

Cut List (mechanism, property it would buy, what covers it or why cut):

- Stop following tokens in comments -> P1 -> measured not to be the cause (domain-model-drift: one file, one
  edge) and it narrows selection, violating P2. Cut. The runner-leaf rule (A5) is the principled version.
- Persistent edge cache keyed by blob hash -> P1 -> state outside the repo, existence-filter invalidation and
  concurrent writers. Cut unless a later measurement shows it is the only path to a target.
- Sparse-view bwrap replay as the missing-file probe detector -> P7 -> proves one run only and needs a
  per-suite runtime closure in the bind list. Cut; a static probe scan covers the stated blind spot (B1).
- Level-batched scanning and a per-file token-stream oracle -> P1 -> the scan is bash-loop bound, not fork
  bound; a rewrite of the extraction passes for a measured 11 ms of 78. Cut.
- Self-reference rule in the resolver -> P1 -> the growth cap alone bounds the doubling; keep the rule only if a
  measurement shows the cap leaves cost (A2 below).
- A separate measurements document -> none; the numbers live in the PR body and the ADR amendment.
- A separate test suite for the bench -> none; its compare logic is driven from the derive suite.

## Value-proposition measurement (Phase 0.6c)

Every number is `time bash scripts/test-all.sh --print-selection --paths=README.md` run in a detached scratch
worktree of HEAD (or a patched copy of it) on the 16-core operator host, with `/proc/loadavg` read before and
after. The host was shared with other sessions, so CPU (user+sys) is the comparable figure and wall is not;
identical configurations varied by about 30% run to run.

| Configuration | wall | user+sys | load before -> after | selection vs baseline |
|---|---|---|---|---|
| Baseline HEAD | 938.7 s | 649.9 s | 44.3 -> 32.3 | reference (stdout sha256 e17071ce...) |
| A1 only (`shopt -u patsub_replacement`) | 201.0 s | 204.9 s | 4 -> 6 | IDENTICAL |
| A2 only, prototype (self-reference break plus absolute 4096-byte cap; the prescribed A2 is a growth cap, re-measured in PR-A) | 168.6 s | 169.7 s | 24.0 -> 15.8 | IDENTICAL |
| A1 + A2, run 1 | 185.5 s | 188.8 s | 13.7 -> 14.8 | IDENTICAL |
| A1 + A2, run 2 | 136.1 s | 139.0 s | 14.8 -> 15.0 | IDENTICAL |
| A2 + A3 (set-membership strings) | 97.6 s | 98.7 s | 16.9 -> 11.9 | IDENTICAL |
| A1 + A2 + A3, run 1 | 105.4 s | 109.7 s | 8.7 -> 14.4 | IDENTICAL |
| A1 + A2 + A3, run 2 | 150.3 s | 141.6 s | 14.4 -> 24.2 | IDENTICAL |
| A1 + A2 + A3 + A5 (runner as a leaf; selection-CHANGING, PR-C) | 58.5 s | 61.9 s | 11.2 -> 12.8 | 18 rows differ, all edge-only removals (8,102 edges, about 450 each); class and selected bit unchanged |
| A1 + A2 + A3 + D1 prototype (PR-C) | 217.5 s | 223.7 s | not recorded | 108 rows differ, +10,120 edges; README-only diff selects 146 instead of 122 |

Reading. All A rows are prototypes of the levers, not of the exact prescribed code; PR-A re-measures the series with
the committed code. The identity-preserving series (A1 + A2 + A3) measures 4.6x to 5.9x on CPU, not 10x; A3 is worth
about a third on top of A1 + A2 (the membership scan is real; the string test is O(length) with a 4-7x smaller
constant than the array loop, 0.36-1.4 ms per call against 2.6-6.6 ms for a 26 KB set depending on locale), and A1 alone is worth 3x and is the one change that also
makes selection bash-version independent. The only measured path to 10x or better is A5, which changes
selection. PR-A therefore does not claim an order of magnitude: it claims the measured factor, honestly, and
PR-C is where the order of magnitude is bought, with its selection delta stated. Of the identity-preserving
remainder, a profile at plan time attributes about 58% to per-file scanning (776 files x 78 ms) and about 40% to
closure replay (a throwaway harness, not a published procedure; PR-A's profile step re-derives it before any A4
lever is taken). Locale matters: the same code ran 3-4x slower in a UTF-8 locale than in `C`, so the bench records
`LANG`/`LC_ALL` and times both sides under the same locale.

## Research Insights

- Premise Validation, Property List and Cut List: the sections above. Cut: stop following comment tokens (not
  the cause, narrows selection), a persistent blob-hash cache, sparse-view bwrap replay, level-batched scanning,
  a separate measurements document.
- Files: the pre-pass functions in `scripts/test-all.sh`; declarations in `scripts/lib/test-affected-paths.sh`;
  the extracted-block helper `_edge_run` (t11/m9) in `scripts/test-all-affected.test.sh`; the ratchet
  `scripts/test-affected-kb-consumers.test.sh` and its baseline; `scripts/regenerate-shard-manifest.py`;
  `plugins/soleur/test/scripts-shard-totality.test.sh` and `scripts-shard-runtime-coverage.test.sh` pin the
  manifests; `scripts/test-all-infra-coverage-notice.test.sh` censuses the runner's predicate-array names.
- Institutional learnings applied: anchoring flips a matcher's error direction and the ratchet never ran
  (2026-10-01); a self-pointing derived edge reads as coverage (2026-09-20); `--print-affected-set` prints
  classes, not selection (2026-09-30); an `elif` arm that ate the selection walk (2026-09-29); guards narrower
  than their names and chokepoint-only mutation batteries (2026-09-28).
- Repo precedent for the bash 5.2 hazard: `apps/web-platform/infra/ci-deploy.sh` (quoted replacement) and a
  comment naming `patsub_replacement` in `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`.
- Related: #9307 (umbrella), #9306 (PR 1, merged), #9375 (this draft PR), #8231 (PR 3 tracker), #8800, #8659,
  #7942 (open code-review overlap, all acknowledged).
- Plan-time scratch measurements: baseline stdout sha256 e17071ce19fb86e9439f15806a7cd8c13f4e05fba19540de8547700a2a92a49e
  (534 `AFFECTED_SELECTED` rows plus the summary line `selected=122 of=534 always_on=122 edge=0`), taken in
  detached scratch worktrees of HEAD c2564f1f6d that are not part of the deliverable.

## Problem Statement

The affected gate exists so a local diff pays only for the suites it can affect. Its selection pre-pass is
the fixed cost before the first suite starts, and today it is about 11 minutes of CPU for every diff, while the
always-on floor (122 suites) is the second, larger cost for a docs-only diff (39.3 minutes of summed suite
time, of which nine batteries are about 80%). Both costs make the "affected" gate slow enough that sessions
stop it and let CI gate, which is the behaviour #9307 was filed against.

## Proposed Solution

PR-A makes the derive cheap and proves the output did not change. PR-B and PR-C then change selection on
purpose, each with its own re-baseline.

### Architecture

The pre-pass lives in `scripts/test-all.sh` (`_affected_classify` -> `_affected_derive` ->
`_affected_file_edges` -> `_affected_file_edges_uncached` / `_affected_edge_token` /
`_affected_resolve_vars` / `_affected_add_edge`), reads declarations from `scripts/lib/test-affected-paths.sh`,
and is observable through `--print-selection`. All of PR-A is local to those functions. Bash 3.2 compatible: no
`declare -A`, no `declare -n`, no `${var^^}`, no `printf -v` with array targets; set membership uses
newline-joined strings.

Consumers of what the new suite and PR-B declare: `_affected_classify` resolves the declared array by NAME from
the label (`_arr="AFFECTED_${_u}_PATHS"`, with `_u` the label upper-cased and every non-alphanumeric run turned
into `_`), so the new label `scripts/test-affected-derive` reads
`AFFECTED_SCRIPTS_TEST_AFFECTED_DERIVE_PATHS`; the census linter `scripts/lint-orphan-test-suites.sh` reads the
same arrays by the same normalisation. A declared edge nothing consults is inert, so each new array is paired
with a `--print-selection --paths=<one declared path>` row that must select the suite.

External binaries of the new tool: `git` (worktree), `cmp`, `awk`, the bash `time` keyword and `/proc/loadavg`.
The bench is a Linux operator-host and CI tool and says so in its header; it prints `?` for the load average
where `/proc/loadavg` is absent (precedent: `scripts/lib/test-contention.sh`) rather than carrying a portability
layer. No `timeout`, `readlink -f`, `stat -c`, `date -d` or `sed -i`. (The PR-B recorder also needs
`inotifywait` and is Linux-only; its test replays a synthesized event stream so CI needs no inotify.)

## Implementation Phases

### PR-A — Phase 0: bench and derive suite

Commit discipline (test-first without red commits): each row is written and seen red locally before its change
and the red is recorded in the commit message; a commit contains a lever and the rows it flips, and the suite is
registered in the first commit with only rows that pass at that point (extraction floor, bench rows, must-PASS
rows), so every commit is bisectable and the pre-push suites pass on each. Rows that need A1, A2 or A3 arrive in
those commits.

- 0.1 `scripts/affected-prepass-bench.sh`: `--base <rev>` (default: merge-base of HEAD and `origin/main`;
  after PR-A merges that equals HEAD and the run exits 3 with a message saying `--base` is required, and the
  certified identity commit for PR-B is `9c5252e644`), `--head <rev>` (default: the working tree),
  `--probe <paths>` (two defaults: `README.md`, and a multi-path probe that selects edge suites,
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh,knowledge-base/legal/article-30-register.md`),
  `--runs N` (timing repeats, interleaved base/head/base/head so both sides see the same load; head default 5,
  base default 2), `--base-runner <path>` / `--head-runner <path>` (run a given runner script instead of a
  worktree's, used by the suite with fake runners), `--compare-only <a> <b>` (pure compare of two saved
  streams), `--report-diff` (list differing rows, always print the first differing row), `--json` (one
  machine-readable result line for the row on #9307). The reference stream is produced once per probe and
  compared with `cmp`; the compare also covers `--print-affected-set` (the class-only stream, which takes the
  print-mode early-out in classify, so it is a cheap surface check for A1-A3, not a derive surface).
  Row-set contract: PR-A registers one new suite, so the head stream has one more `AFFECTED_SELECTED` row than
  the base; the bench compares byte for byte every row whose label exists in the base stream, requires the extra
  labels to equal the added-label list (default: the difference of the two `--enumerate-commands all` label
  sets), and requires the head summary to equal the base summary adjusted by the added rows (`of=` plus the
  added count; `selected=` and `always_on=`/`edge=` per the added rows' own class and bit). The report prints,
  per side, min and median CPU (user and sys separately) and wall, load average before and after, locale,
  `BASH_VERSION` and `patsub_replacement` state, and one plain line. Exit 0 identical, 1 differs, 2 usage,
  3 base and head are the same tree.
  Anti-vacuity: both sides must exit 0; the stream must end in an `AFFECTED_SUMMARY` whose `of=` equals the
  count of `SUITE_COMMAND` rows from `--enumerate-commands all` (a double crash at the same row cannot read as
  identical); the child runs under `env -u CI -u SOLEUR_TEST_FORCE_ALL` (`_diff_touches` returns 0 under either,
  which would make every selected bit 1; scoped to the child, not unset in the bench shell).
  Hardening (operator-only tool over trusted revisions; the header says so): resolve revs with
  `git rev-parse --verify --end-of-options "$rev^{commit}"`, create the worktree under `mktemp -d` and remove
  only that exact path in a trap, scrub `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` before any git call
  (lefthook exports them), and refuse a `--probe` containing whitespace other than commas.
- 0.2 `scripts/test-affected-derive.test.sh`: extracts the block from the column-0 `_AC_CLASS=""` declaration
  (the first occurrence; a second, indented one sits inside `_affected_classify`) through the closing brace of
  `_affected_derive` by content anchor (never by line number), asserts `declare -F _affected_derive` after the
  eval (a floor: a missed anchor must not pass vacuously), and drives it with synthesized files. One suite, one
  `run_suite` registration, appended after the `scripts/test-affected-kb-consumers` line as the last registration
  of the scripts block with that "LAST" comment updated (the registration ordinal shifts shard-leg parity;
  commit `abd29f4bcf` reverted a mid-block insert for exactly this), and one declared edge array
  `AFFECTED_SCRIPTS_TEST_AFFECTED_DERIVE_PATHS` listing the suite, the bench, `scripts/test-all.sh` and
  `scripts/lib/test-affected-paths.sh` (the census linter fails unless the array contains the lib). The suite
  reads no `knowledge-base/` path, so the ratchet baseline is unaffected; missing manifest rows in
  `suite-shard-legs.tsv` are tolerated (the ratchet has none either) and D5 regenerates them. Rows:
  R1 a captured variable value containing `&&` and `&` resolves literally, run twice (cold and warm) with a value
  that only works if the option was off before the first derive; R2 a self-referential value terminates with the
  head before the first quote preserved and the token far under a fixed absolute bound; R3 a mutually
  referential pair terminates under the same bound; R3b (must-PASS) a 5000-byte line with no self-reference
  whose edge still resolves to the exact expected value; R3c boundary rows at growth exactly 4096 (resolves) and
  4097 (stops); R4 the membership set agrees with the array at every assignment site (derive entry, classify
  entry, `_affected_resolve_edges`, an external reset), with a prefix-collision fixture (`a/b` against
  `a/bc`) and a newline-bearing name that must not mint; R5 no `&` appears in the replacement of a
  pattern-substitution inside the extracted block (a census, so a future site is caught); R7 the bench: a fake
  runner pair through the full dispatch path (pristine pair rc 0, a pair with one edge dropped rc 1, the same
  path twice rc 3, a pair differing by one added suite label rc 0), then `--compare-only` rows (identical,
  one-byte difference in the last of 534 rows, edges reordered inside a row, zero rows, one side crashing,
  summary `of=` mismatch, stderr-only difference rc 0, the same stream under `CI=1` rc 0). The conditional
  `&&` rows print a counted `SKIPPED rows=N (bash < 5.2)` line and exit 0 locally, and fail under `CI`.

### PR-A — Phase A: make the pre-pass cheap, selection byte-identical (one commit per lever)

Each lever: write the row and see it red, apply the change, run the bench, record the measured row in the commit
message.

- A1: `shopt -u patsub_replacement 2>/dev/null || true` as the first statement of the derive block, at column
  0 and exactly once (the Observability probe counts it), immediately after the column-0 `_AC_CLASS=""`
  declaration, so the derive suite's extraction includes it and Guard 2 mutation 1 can bite; it takes effect
  before the first derive call, and no earlier code in the runner or its index uses `&` in a replacement
  (checked; R5 keeps it that way inside the block). It is a no-op on bash before 5.2, so selection becomes the
  same on CI (bash 5.2.21 on ubuntu-24.04), the operator host (5.3) and stock macOS (3.2) by construction (the
  3.2 behaviour is by documentation; no 3.2 host is available to run it). The shopt is the only switch:
  `BASH_COMPAT` does not disable the option. Repo precedent quotes the replacement instead (`ci-deploy.sh`,
  valid on 5.2 and later per the manual); that form is not used because quote handling inside a double-quoted
  `${..//../"x"}` is unverified on old bash here and a future site would reintroduce the hazard. Measured
  alone: 938.7 s -> 201.0 s wall, selection identical. New idiom for this repo; the ADR amendment records it.
- A2: bound the growth in `_affected_resolve_vars`. Record the input length on entry; before each substitution
  stop (leave the token as it is) when `${#_RV}` exceeds the input length plus 4096. The first substitution
  therefore always happens, the head of an exploded token before its first quote is preserved, and a long line
  (pass 2 resolves a whole grep line, not a token) with no growth resolves exactly as before. The cap is on
  growth, not absolute length, because a legitimate line over 4096 bytes must still resolve. A single global
  substitution can overshoot the cap by occurrences times value length, so the property is "stops substituting
  once growth exceeds 4096", and the tests assert an absolute bound far below the 250 KB tokens, not 4096
  exactly. The unresolvable-variable behaviour (the loop stops on a name not in the map) is unchanged. Add a
  self-reference rule only if a measurement shows the cap alone leaves cost (then with a word-boundary check;
  the baseline's `${_RV//\$name/...}` also hits the prefix of `$name2`, and the bench covers that). Known
  limit, stated: a cap trip leaves a `$VAR` in the token, which then dies at the `-e` filter, so a real
  dependency behind a pathological value is not minted; the baseline has the same flaw with its 12-iteration
  cap. Failing safe on a trip (classify as `unclassified`) would change selection for the suites that explode
  today, so it is a PR-B item, not PR-A.
- A3a: membership for the edge set. Keep `_AC_EDGES` as the ordered store and add one shadow set `_AC_ESET`
  (newline-joined; membership as `[[ "$_AC_ESET" == *"${_nl}${_p}${_nl}"* ]]` with the newline a local `$'\n'`
  inside `_affected_add_edge`, matching the repo's inline-`$'\n'` idiom). This is O(length) with a 4-7x smaller
  constant than the array loop, not O(1). `_affected_reset_edges` is a NEW function, defined inside the range
  the `_edge_run` helper in `scripts/test-all-affected.test.sh` evals (from `_affected_in_list` through
  `_affected_add_edge`), and replaces the three inline resets of `_AC_EDGES` (derive entry, classify entry, the
  `eval` copy in `_affected_resolve_edges`); the `eval` site additionally rebuilds `_AC_ESET` from the loaded
  members, because it fills the array without going through `_affected_add_edge`. `_affected_add_edge` reads
  `${_AC_ESET-}` with a default, so `_edge_run` works unchanged in a fresh subshell, and the `-d` normalisation
  line stays verbatim (mutation m9 counts it once). `_affected_add_edge` skips a token containing a newline (it
  cannot arise from `read` lines, and a newline would forge two set entries), and `_affected_resolve_edges` returns
  early unless its argument is a valid identifier (`^[A-Za-z_][A-Za-z0-9_]*$`) before the `eval`. A
  count-comparison backstop is not used: it cannot see an equal-length reassignment. Measured: A2 alone 168.6 s ->
  A2 + A3 97.6 s.
- A3b: the two other linear scans the profile found, taken with A3a through one shared string-set idiom (their
  estimated share, about 25 s of the remaining 100 s, is above the 10% gate): the closure queue's `_seen` list
  (a per-call copy of up to about 780 words) and the `_FE_FILES` memo lookup in `_affected_file_edges`; plus the
  per-file buffer `_FE_BUF`. Each is taken only while the bench stays IDENTICAL.
- A4 (profile-gated; take a lever only if the committed profile step attributes more than 10% of the remaining
  CPU to it, and only while the bench stays IDENTICAL): (a) an O(1)-ish variable-name lookup in
  `_affected_resolve_vars` (a linear scan over the file's variable list, 0.6 ms per token at 60 variables, the
  top cost inside a scanned file); (b) cache the already-minted anchored form per file so a replay is a set test
  and an append with no `-e`/`-d` stats; (c) replace the subshell, `printf` and `sed` that `_affected_normpath`
  forks per `../` token (4.1 ms against 0.4 ms for the rest of `_affected_edge_token`; the "rare" comment is
  wrong for `$SCRIPT_DIR/../lib/x`) with pure-bash segment stripping, which the bench proves identical. There is no
  numeric stop target: stop when the next lever is below 10% or fails the bench, and report the factor reached.
  The profile output goes in the PR body, not a committed file.
- ADR-242 amendment (`## Amendment — 2026-10-01`, short): decision 16, the derive is bounded and bash-version
  independent (`patsub_replacement` off, growth-bounded resolution, the selection-identity bench as the
  acceptance contract for any pre-pass change), the baseline and reference sha256 (e17071ce...) and the baseline
  CPU, and corrected figures in decision 15 (the cost attribution is variable resolution and replay, not comment
  tokens; the pre-pass measures about 5x cheaper). Later decisions are numbered in landing order: PR-B is
  decision 17, PR-C decision 18. A one-paragraph correction to the "What the demotion costs" paragraph of
  `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`.
- The learning (topic: bash 5.2 `patsub_replacement` multiplying the affected pre-pass while the issue blamed
  comment tokens; selection that depends on the bash version; "profile before choosing the lever").

PR-A acceptance: `bash scripts/affected-prepass-bench.sh --base <merge-base>` exits 0 on both probes and the
class-only stream; the min and median CPU factor against the base side timed in the same run, the load averages,
the locale and the bash version are quoted in plain terms in the PR body ("an affected run waited about 11
minutes on selection and now waits about N").
Identity is operator-attested by the bench (about 35 CPU-minutes for the interleaved timing; run it once at the
end, not per commit; per commit run it with `--runs 1`). CI keeps the derive suite and the dropped-consumer
ratchet's full walk as its regression coverage; the plan does not claim CI proves identity against the
merge-base.

### PR-B (follow-on; design level) — re-price the demotions, ratchet breadth, minting fixes

- B1: a committed, reproducible recorder, `scripts/audit-suite-reads.sh`, from the method in
  `always-on-audit.md` (Reproducing the recorder): detached worktree, `inotifywait -m -r -e open` excluding
  `.git` and `node_modules`, each registered argv run serially with a quiet gap, events attributed by window.
  New failure detection, each fatal for the verdict: `Q_OVERFLOW` in the event stream and a startup check of
  watch headroom (`max_user_watches` against the directory count; any `Failed to watch` on stderr; the host's
  `max_queued_events` is 16384 while one audited suite opened 16,636 files, so overflow was plausible); a
  static probe scan of the suite and every script it executes for file tests (`-e -f -d -s -r -x -L -h`),
  `stat`, `ls`, `find` against repo-relative or root-variable paths, because open events never see a probe of a
  missing file. A probed path outside the proposed cover disqualifies. Test `scripts/audit-suite-reads.test.sh`
  replays synthesized event streams. Hardening: run suites under `env -i` with a scratch `HOME` and no credential tokens; a path in an event
  containing a newline is fatal (a suite-created file could forge event lines); refuse symlinked cover entries
  (`-r` does not follow symlinks) and statically flag reads under `.git`, which the exclusion hides. Built only
  because B2 and Phase C need its verdicts; if neither lands, it is not built.
- B2: re-demote `scripts/domain-model-drift` (remove from `ALWAYS_ON_SUITES`, declare
  `plugins/soleur/scripts/domain-model-drift.sh`, `plugins/soleur/scripts/lib/domain-model-lib.sh` and
  `scripts/domain-model-drift.test.sh`); its derive cost is 0.3 s after PR-A (it was 82 s). Re-run the recorder
  with the B1 disqualifiers on the 23 already-demoted suites; a new disqualification re-promotes that suite.
- B3: append "Round 2" to the always-on audit with the verdicts.
- D2: ratchet breadth in `scripts/test-affected-kb-consumers.test.sh`: add detection only for the forms that
  surface a real uncovered suite today (measured by running the widened oracle against the 534 registrations),
  from `find knowledge-base`, `${KB_DIR:-knowledge-base}`, split-literal joins, `$PWD/knowledge-base`, the
  relevance-gated registrations (outside the population today), suites with no code file in argv, and the
  non-KB edges of the demoted suites (`docs/legal/`, `AGENTS*.md`, migrations); list the forms still unseen,
  with the count, in the file header. Each added form gets a fixture row that reddens when planted without a
  covering edge (Guard 3).
- D3: the runner-subcommand skip extended to `deno test`, `make test`, `npm run test`, `bun run test` and
  applied inside the `-c` payload word loop, which mints `^test/` from `bun test` today. No registration mints
  these forms today (measured), so this is fixture rows plus a two-line change, filed as its own item with that
  reason.
- D4: a deleted declared subject must still select. Mint declared and consumed edges without the `-e` filter
  (keep it for derived tokens) and let the census linter keep reporting a declared path that no longer exists.
  Precondition found in review: about 22 declared directory entries have no trailing slash and mutation m9 pins
  the `-d` normalisation, so slash-less directory entries must first be migrated to trailing slashes, enforced
  by the census linter, or a deleted slash-less directory would mint an exact `^dir` that never matches
  `dir/x`. This amends ADR-242 decision 12 (decision 18 in the amendment).

### PR-C (follow-on; design level) — runner leaf, REPO_ROOT idiom, heavy batteries

- A5: treat the runner and its index (`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`,
  `scripts/lib/test-relevance-paths.sh`) as closure leaves for comment and token mentions only: keep the real
  `source`/`.` edges (pass 1 of the scan), drop what the runner text merely names. A diff touching any of the
  three already degrades the gate to the full run by design. The measured 18-row delta came from a README-only
  probe; before landing, run the multi-path probe and the recorder on the 18 suites, because dropping the whole
  closure also drops edges to helpers the runner really sources (for example
  `plugins/soleur/scripts/lib/proc.sh`). Measured with A1-A3: 61.9 s CPU, the only measured route to 10x.
- D1: fix the `REPO_ROOT` idiom in `_affected_edge_token`: resolve
  `$(cd "<dir>[/..]" && pwd[ -P])` to the cd target (through `_affected_normpath`) before the greedy
  `$(cd*pwd*)` replacements. Needs A1. Decide it together with A5 (the 23 `^README.md` edges arrive through
  the runner closure that A5 may remove). Re-baseline the ratchet; the row delta is classified by an independent
  resolver (a short script that resolves the idiom against the real files from the suite text and the file's
  own directory), never from the runner's own counts.
- Phase C: narrow heavy always-on batteries, only with evidence. Default per suite is keep. A suite narrows only
  when (1) the recorder run is clean (no overflow, rc 0 on a quiet host, no probe outside the proposed cover),
  (2) a perturbation test passes (edit a comment in ten unrelated tracked files, add and delete an unrelated
  file, rerun: exit code and output hash unchanged), and (3) a corpus check over the last 60 first-parent commits
  lists which commits the suite would no longer be selected for, each classified as unable to change the
  verdict. (CI still runs everything: the local gate declines nothing under `CI`, so narrowing costs local
  coverage only; that is a standing precondition, not an evidence step.) Candidates are the four whose subject is
  explicit: `scripts/test-all-affected` (442 s), `scripts/lint-orphan-test-suites-mutations-a` and `-b` (422,
  424 s; the live census `scripts/lint-orphan-test-suites` stays always-on) and
  `scripts/test-all-infra-coverage-notice` (83 s), together about 1,371 s of the 39.3 minutes. The other five
  (`scripts/test-contention`, `operator-ack-guard`, `hook-input-classification-mutation`,
  `sentry-alert-live-fidelity`, the live census) are recorded as keep with the reason, in one line each.

### Post-merge

- D5: `python3 scripts/regenerate-shard-manifest.py --runs 5 --write` from at least five CI runs of the
  post-PR-A code, so the ratchet lands on a balanced leg at its new cost. Tracked issue.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Stop following tokens in comments (issue candidate 1) | Not the measured cause; narrows selection (violates P2); see Cut List |
| Memoise by blob hash across runs (issue candidate) | Persistent state, existence-filter invalidation, concurrent writers; only if a later measurement requires it |
| Quote the replacement (`${x//p/"$v"}`) at each site instead of the shopt | Repo precedent exists, but quote handling inside a double-quoted expansion cannot be verified on bash 3.2 here, and a future site would reintroduce the hazard; the shopt covers every site and is inert on old bash |
| Rewrite the scan passes in awk, or batch the scan per BFS level | Semantics-equivalence risk on the sed chain for a gain the profile does not support (the scan is bash-loop bound, not fork bound) |
| Associative arrays for the sets | bash 3.2 is a stated target |
| One PR for A-D | Review result: bundling selection-changing work destroys the byte-identical review contract (see Delivery shape) |
| Count-comparison backstop for the shadow set | Cannot see an equal-length reassignment; one reset chokepoint is simpler and complete |
| Buy (Bazel, Nx, a git-diff selector) | Would mean re-modelling 534 registrations; nothing off the shelf derives a suite-to-file closure from bash |

## User-Brand Impact

- **If this lands broken, the user experiences:** the maintainer's local `--affected` gate selects fewer suites
  than a diff can affect and prints "affected-suite gate passed"; a regression then reaches CI, where the
  required `test` check (the authoritative gate, unchanged by this plan) catches it, or the gate refuses or
  slows. No Soleur end user sees any of this: the change is confined to the repo's own test runner and
  knowledge-base documents.
- **If this leaks, the user's data is exposed via:** no vector. The runner reads repository files and prints
  suite labels and paths; no credential, user data or network call is added.
- **Brand-survival threshold:** `none`. Scope note: PR 2 of the umbrella (the plugin-shipped gate for users'
  repositories) is the surface the umbrella's `single-user incident` threshold was declared for; this work does
  not touch it. The diff touches no path in the preflight sensitive-path regex (`scripts/`, `knowledge-base/`
  only).

## Observability

Scope note: the deliverable is a repo-root developer tool and test-runner internals (`scripts/`), not a server,
cron or customer-facing surface; the five-field block is declared anyway so the gate has something checkable.

```yaml
liveness_signal:
  what: every affected-mode run prints one `AFFECTED_SUMMARY selected=N of=M ...` line on stdout and, in a degraded run, `fallback=<reason>`; the bench prints one plain line with head CPU against the recorded baseline
  cadence: per local affected run and per CI battery run
  alert_target: the developer's terminal and the CI log of the required `test` check
  configured_in: scripts/test-all.sh (summary line, PR 1) and scripts/affected-prepass-bench.sh (PR-A)
error_reporting:
  destination: non-zero exit of the bench (1 differs, 2 usage, 3 same tree) and a red `scripts/test-affected-derive.test.sh` row in CI
  fail_loud: true
failure_modes:
  - mode: a lever changes a selection row
    detection: scripts/affected-prepass-bench.sh exits 1 with --report-diff rows; CI runs the derive suite
    alert_route: red required `test` check
  - mode: resolution grows a token without bound again (bash 5.2 patsub_replacement regression)
    detection: derive suite rows R1-R3 and the eight-suite derive timing in the PR report
    alert_route: red required `test` check
  - mode: the bench compares a vacuous pair (same tree, crashed side, empty stream)
    detection: rc 3 / rc 1 anti-vacuity arms of Guard 1
    alert_route: red required `test` check
logs:
  where: stdout and stderr of the run; the CI job log retains them
  retention: GitHub Actions log retention for the repository
discoverability_test:
  command: grep -c -e '^shopt -u patsub_replacement' scripts/test-all.sh
  expected_output: 1
```

## Guard Contract

### Guard 1 — selection-identity oracle (`scripts/affected-prepass-bench.sh`, PR-A)

**Property.** For the same registration set and the same named paths, the optimized pre-pass emits stdout
byte-identical to the reference revision's, row for row (class, selected bit, edge list in order) for every
registration the reference has, with the summary equal to the reference's adjusted only by the declared added
registrations (PR-A adds one suite), and the same `--print-affected-set` stream.

**Assembly.** The population is every `SUITE_COMMAND` row of `test-all.sh --enumerate-commands all` (534 at HEAD,
derived by the run, never listed), reached through ONE chokepoint: the pair of `--print-selection --paths=<probe>`
invocations the harness makes per probe (README.md, and a multi-path probe that selects edge suites), plus one
`--print-affected-set` pair. The reference is a detached worktree of the merge-base with `origin/main`, so no
single diff can edit both the candidate and the reference; that merge-base is the anchor. A tree where base
equals head (rc 3), a side that exits non-zero, a stream with no `AFFECTED_SUMMARY`, or a summary whose `of=`
differs from the enumerated count is refused, never reported identical; a head row whose label is not in the
base stream and not in the declared added-label list is a difference. Order is part of the contract. Under `CI`
the bench would see every selected bit as 1, so it scrubs `CI` and `SOLEUR_TEST_FORCE_ALL` for the child only.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `--compare-only` given two streams differing in a single edge of the LAST of 534 rows after 533 identical rows | RED (a compare that stops at the first row or samples is the defect) |
| 2 | Two edges swapped inside one row | RED (order is part of the contract) |
| 3 | The harness is pointed at the same tree for base and head (its own dispatch), or the stream is empty, or one side crashes at the same row on both sides | RED (rc 3 / rc 1; never "0 differences") |
| 4 | Summary `of=` differs from the enumerated registration count | RED |
| 5 | Must-PASS: the head stream carries extra stderr lines only, and separately one added suite label that is on the declared list | PASS (the contract compares stdout only and allows declared additions; a bench that rejects everything cannot pass it) |
| 6 | A head row for a label not on the declared added-label list (an undeclared extra registration) | RED |
| 7 | Dispatch path through fake runners: a pristine pair rc 0, a pair with one edge dropped rc 1 (the bench is exercised end to end, not only `--compare-only`) | rc 0 / RED |

### Guard 2 — bounded resolution and membership drift (`scripts/test-affected-derive.test.sh`, PR-A)

**Property.** Variable resolution never re-inserts matched text and stops substituting once a token has grown
more than 4096 bytes beyond its input, on any bash (one global substitution may overshoot by occurrences times
value length, so the tests assert a fixed absolute bound far below the 250 KB tokens); a long input with no
growth resolves exactly as before; the membership set never disagrees with the ordered edge array.

**Assembly.** The single function `_affected_resolve_vars` (both of its call sites, the pass-2 whole-line loop
and the pass-3 token loop in `_affected_file_edges_uncached`, flow through it); the entry of
`_affected_edge_token`; every assignment site of `_AC_EDGES` (derive entry, classify entry,
`_affected_resolve_edges`, all going through the new `_affected_reset_edges`, which sits inside the range the
t11/m9 helper evals) and the append site `_affected_add_edge`. The `shopt` line is the first statement of the
extracted block, so the suite evals it; the extraction is guarded by `declare -F _affected_derive`.

A conditional row can go dark: the `&&` fixture is only meaningful on bash 5.2 or later. On older bash it prints
a counted `SKIPPED rows=N (bash < 5.2)` line and exits 0; under `CI` the row fails (rc 1) with a message naming
`BASH_VERSION` if the host bash lacks the option, so the CI side asserts the row RAN and a runner-image change
turns CI red readably rather than silently skipping.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `shopt -u patsub_replacement` line from the block, or move it after the first derive call or into a subshell | RED on the cold-and-warm `&&` fixture (bash 5.2 or later) |
| 2 | Delete the growth cap in `_affected_resolve_vars` | RED on the self-referential and the mutually referential fixtures (token grows beyond input + 4096) |
| 3 | Apply the cap to absolute length instead of growth, skip substitution when the input is already long, or move the boundary by one (4097 against 4096) | RED on the 5000-byte no-growth must-PASS fixture (it must resolve to its exact value) and on the 4096/4097 boundary rows |
| 4 | `_affected_add_edge` appends without updating `_AC_ESET`; or one assignment site (derive entry, classify entry, the `eval` copy, an external reset) is left as a raw `_AC_EDGES=()`; or the set test is a bare substring | RED (a later member is skipped; the `a/b` against `a/bc` prefix-collision fixture reddens the substring form) |
| 5 | Dispatch: the extraction anchor matches nothing, so zero functions are driven | RED (`declare -F _affected_derive` floor, and rows counted) |
| 6 | Must-PASS: a value containing `&`, `\`, `$(`, a space and a trailing quote that is NOT self-referential | PASS and resolves literally |

### Guard 3 — ratchet breadth (`scripts/test-affected-kb-consumers.test.sh`, D2, PR-B)

**Property.** Every registered suite that reads a real `knowledge-base/` path, or a path the demoted suites
declared, through any form the oracle lists is always-on or carries a covering edge.

**Assembly.** The population stays derived (`--enumerate-commands --paths=README.md all` joined with
`--print-selection`) and is widened to include the relevance-gated registrations; the read forms are enumerated
in one table in the oracle so a new form is one row; the chokepoint is the oracle's reference extractor, which
every form must flow through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A fixture suite reads `find knowledge-base` with no covering edge | RED |
| 2 | Same for `${KB_DIR:-knowledge-base}`, a split-literal join and `$PWD/knowledge-base` (one row each, added after a compliant first) | RED each |
| 3 | A fixture suite with no code file in argv that reads a covered KB path | PASS (covered), and RED with the edge removed |
| 4 | The population floor: empty enumeration | RED (never "0 checked") |
| 5 | A non-KB read (`docs/legal/`, `AGENTS.md`) with no covering edge | RED |

### Guard 4 — recorder disqualifiers (`scripts/audit-suite-reads.sh`, B1, PR-B)

**Property.** A suite is never reported demotable from an incomplete recording or when it probes a path
outside its proposed cover.

**Assembly.** The event stream (open events, `Q_OVERFLOW`, watch-setup errors) and the static probe scan over
the suite file and every script it executes; both flow through the single verdict function.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A replayed stream containing `Q_OVERFLOW` | verdict "unreliable", not demotable |
| 2 | A fixture suite that tests `[[ -e some/missing/path ]]` outside the cover | disqualified |
| 3 | A second fixture suite that probes after a compliant first | disqualified (the scan covers every member) |
| 4 | Zero suites enumerated | RED (floor) |
| 5 | Must-PASS: a suite whose only file tests are on its own cover | demotable |

## Architecture Decision (ADR/C4)

### ADR

PR-A amends ADR-242
(`knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`)
with a short `## Amendment — 2026-10-01`: decision 16 (the derive is bounded and bash-version independent;
the selection-identity bench is the acceptance contract for any pre-pass change) and the corrected cost
attribution and measured factor in decision 15. This is a PR-A task through `soleur:architecture`, not a
follow-up. PR-B adds decision 18 (declared edges are minted without the existence filter, reversing the clause
of decision 12 that drops an edge to a deleted path) and PR-C adds decision 17 (the runner and its index are
closure leaves) only if they land; each states its own selection delta.

### C4 views

None change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`; `soleur:work` reads
them in full before concluding): the actors and systems enumerated are the repo's own test runner, a local
developer shell and the CI test jobs. External human actors: none added (the maintainer and CI are already
modeled). External systems or vendors: none added (no network call). Containers or data stores: none.
Actor-to-surface access relationships: none change. A search of the three files for the runner, the affected
gate, lefthook and the local gate found only CI edges to vendors, no element for the runner. Derived
cardinalities in edge prose are untouched: run `bash plugins/soleur/test/c4-count-parity.test.sh` and cite the
green run.

### Sequencing

Nothing is soak-gated; the amendment describes the landed state.

## Acceptance Criteria

### Functional Requirements (PR-A)

- [ ] AC1: `bash scripts/affected-prepass-bench.sh` exits 0 for both probes and the `--print-affected-set`
  stream, and prints, for the head side, median wall and user+sys, load average before and after, and
  `BASH_VERSION`/`patsub_replacement`. Stdout of `--print-selection` is byte-identical to the merge-base's.
- [ ] AC2: the report states the CPU factor reached (median of three head runs against the recorded baseline
  649.9 s user+sys, with the load averages) in plain terms in the PR body and the final message. No numeric
  pass threshold: the identity-preserving series is measured at 4.6x to 5.9x, and the PR does not claim an order
  of magnitude (decision-challenges.md records the tension with the brief's "order of magnitude").
- [ ] AC3: the eight profiled suites each derive in under 3 s (reported from the profile step).
- [ ] AC4: `scripts/test-affected-derive.test.sh` is registered and green, and every Guard 2 and Guard 1 row
  reddens under its mutation (the mutation rows are in the suite, not only in the plan).
- [ ] AC5: ADR-242 amended (decision 16, corrected decision-15 figures) and the audit correction made.
- [ ] AC6: PR body: `Ref #9307` (never `Closes`), the net-issue-flow one-line justification PR 1 used
  (`<!-- gate-override: net-issue-flow -->` plus the sentence that #9307 is the pre-existing umbrella and stays
  open), "affected-suite gate passed" wording only, the statement that the local full battery was not run
  because the runner is touched and CI is the authoritative gate, and the trailer
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] AC7 (pre-merge): PR-B, PR-C and D5 are re-filed on #9307 as tracked issues, each with its measured
  reason and a milestone from `knowledge-base/product/roadmap.md`; the labels used are checked with
  `gh label list --limit 200` first.

### Post-merge (tracked, not blocking the PR)

- [ ] D5: after at least five CI runs of the post-PR-A code on main, regenerate
  `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` with the command in Phase "Post-merge".
- [ ] Re-run the bench against main once merged and record the row on #9307.

### Non-Functional Requirements

- [ ] Bash 3.2 compatible (`bash -n` plus a grep for `declare -A`, `declare -n`, `${..^^}`, `mapfile` in the diff).
- [ ] No test or commit edits a file while a background suite that reads it is running.
- [ ] NFR register assessment: `soleur:architecture assess` against
  `knowledge-base/engineering/architecture/nfr-register.md` run and noted.

### Quality Gates (pre-push targeted suites; CI went red on three of them on PR 1)

- [ ] `bash scripts/lint-orphan-test-suites.sh`
- [ ] `bash scripts/test-affected-kb-consumers.test.sh` (about 2 minutes after PR-A; about 11 before)
- [ ] `bash plugins/soleur/test/fixture-relative-assert.test.sh`
- [ ] `bash scripts/battery-tag-authorship.test.sh` and `bash scripts/battery-tag-authorship-mutations.test.sh`
- [ ] `bash scripts/guard-vacuity-floor.test.sh`
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main`
- [ ] `cd apps/web-platform && npx vitest run --project repo-wide test/plugin-root-anc*`
- [ ] `bash scripts/test-all-infra-coverage-notice.test.sh` (its runner-array census reads variable names
  from `test-all.sh`; the new shadow-set global must not appear as a predicate array)
- [ ] `scripts/test-all-affected.test.sh`: do not run the whole file (about 25 minutes); run a focused copy
  holding the t11/m9 rows (they eval the extracted `_affected_in_list` to `_affected_add_edge` block) and let CI
  run the rest
- [ ] `python3 scripts/lint-guard-contract.py` (no arguments, CI's own invocation) and
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
- [ ] CI required `test` check green; the local full run is not performed (a diff touching
  `scripts/test-all.sh` degrades `--affected` to the full run by design)

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a captured variable value containing `&&`, when the token is resolved on bash 5.2 or later, then the
  value is inserted literally (R1).
- Given a value that references its own name, when resolved, then growth is bounded and the head before the
  first quote survives (R2); given a 5000-byte line with no self-reference, its edge still resolves (R3b).
- Given the merge-base and the candidate, when the bench runs both probes, then stdout is byte-identical and
  the report names loadavg and bash version.

### Regression Tests

- Given the eight profiled suites, when their derive is timed, then none exceeds 3 s.
- Given an external reset of `_AC_EDGES` through `_affected_reset_edges`, when `_affected_add_edge` is called,
  then no edge is silently skipped (R4).

### Edge Cases

- A value containing `&`, a trailing backslash or `$(` resolves literally and terminates.
- A pass-2 line over 4096 bytes with no growth resolves exactly as before.
- Bash 3.2: `shopt -u patsub_replacement` fails harmlessly; no associative arrays.
- A double crash at the same row on both sides is not identical (rc 1).

### Integration Verification (for `soleur:qa`)

- **Selection identity:** `bash scripts/affected-prepass-bench.sh --probe README.md` expects `identical`.
- **Ratchet:** `bash scripts/test-affected-kb-consumers.test.sh` expects the final ledger line to report 0 failures.

## Dependencies & Risks

- R-1 (high): a lever that is "obviously equivalent" changes a row. Mitigation: the bench compares every row
  and the order on two probes and the class-only stream; levers land one per commit so a red bisects to one
  change. The oracle certifies only the registration set that exists today; a future suite with an unusual idiom
  is not covered, which is why A2 bounds growth rather than capping length.
- R-2: `shopt -u patsub_replacement` changes `${x//p/&}` anywhere in the runner. Checked: no replacement in
  the runner or the index contains `&` today.
- R-3: the host is shared; wall time is noisy (identical configurations differed by about 30%). Mitigation: CPU
  is the headline, load average is always quoted, the head side is timed three times and the median reported.
- R-4: the shadow set is a second source of truth. Mitigation: one reset chokepoint, and a Guard 2 row that
  breaks it on purpose.
- R-5: the bench is pinned to a merge-base by default; later selection-changing PRs will differ by design.
  Mitigation: `--head`, `--report-diff`, and naming the PR-A tip as the certified identity commit.
- R-6: scratch worktrees used for measurement must be removed (`git worktree remove`) before the PR.

## Open Code-Review Overlap

Three open `code-review` issues name files this plan edits. Dispositions:

- #8800 (`build_census_sandbox` shares inodes with the live repo, in `scripts/test-all-affected.test.sh` and
  `scripts/lib/test-affected-paths.sh`): Acknowledge. PR-A does not edit the file; the derive suite builds no
  census sandbox. The write-through hazard is a separate small fix.
- #8659 (suites replace `test-helpers`' composed EXIT trap; names `scripts/test-all.sh`): Acknowledge. Different
  concern; the new suite installs a plain `trap cleanup EXIT` and sources no helper.
- #7942 (`*.mutation.sh` batteries run in no gate; names `scripts/test-all.sh`): Acknowledge. Different
  concern; the new suite is named `*.test.sh` and registered with `run_suite`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: internal test-runner tooling, documentation under `knowledge-base/`, no
user-facing surface, no legal, financial, marketing or operations surface. The engineering review is the
plan-review panel and the ADR-242 amendment.

## Files to Edit

PR-A:

- `scripts/test-all.sh` (A1-A3, profile-gated A4)
- `scripts/lib/test-affected-paths.sh` (the edge array for the new suite)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` (correction paragraph)

Follow-on (design level, edited in their own PRs): `scripts/lib/test-affected-paths.sh` (B2, D4),
`scripts/test-affected-kb-consumers.test.sh` and its baseline (D2, D1 re-baseline), `scripts/test-all.sh` (A5,
D1, D3, D4), `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (D5).

## Files to Create

PR-A:

- `scripts/affected-prepass-bench.sh`
- `scripts/test-affected-derive.test.sh` (registered with one `run_suite` line in `scripts/test-all.sh`;
  `scripts/*.test.sh` is NOT auto-globbed)
- A learning under `knowledge-base/project/learnings/` (topic above); the author picks the filename and date at
  write time.

Follow-on: `scripts/audit-suite-reads.sh` and `scripts/audit-suite-reads.test.sh` (B1).

Glob check: `scripts/lib/test-relevance-paths.sh`, `scripts/regenerate-shard-manifest.py`,
`scripts/suite-shard-legs.tsv`, `scripts/battery-tag-authorship.test.sh` all exist on this branch.

## Success Metrics

- CPU for the README.md probe: 649.9 s baseline -> the reported median after PR-A (measured 4.6x to 5.9x for
  A1 + A2 + A3), with selection identical.
- The ratchet leg: about 11 minutes -> about 2 minutes of CPU after PR-A; further after PR-C.

## References & Research

### Internal References

- Issue #9307 (PR 1 residuals checklist); PR #9306 (merged); draft PR #9375.
- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` (method, "Where the time
  actually is", "What the demotion costs").
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  (Amendment — 2026-09-30, decisions 12-15).
- Learnings: `2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md`,
  `test-failures/2026-09-20-a-classified-edge-that-pointed-at-itself-read-as-coverage.md`,
  `2026-09-30-print-affected-set-prints-classes-not-selection-and-the-ask-was-half-shipped.md`,
  `test-failures/2026-09-29-my-elif-arm-ate-the-selection-walk-and-two-review-seats-caught-what-my-unrun-arm-would-have.md`,
  `2026-09-28-every-guard-was-narrower-than-its-name-and-my-battery-mutated-only-whole-chokepoints.md`.
- Repo precedent for the bash 5.2 hazard: `apps/web-platform/infra/ci-deploy.sh` (quoted replacement) and
  `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (a comment naming `patsub_replacement`).

### Related Work

- PR 2 and PR 3 of #9307 are separate later PRs and are not started here. #8231 tracks PR 3.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or filler text fails `deepen-plan` Phase 4.6; this
  one declares `none` with a reason because no sensitive path is touched.
- Quote the CPU figure, not the wall figure: the baseline ran at load average 44 and later runs at 4-24.
- A diff that touches `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` makes the local gate a full
  run. Never start it. Run the named targeted suites and let CI gate.
- Never edit a file a background suite is reading (the boundary check voids the verdict). Use
  `source plugins/soleur/scripts/lib/proc.sh; list_runs <basename>` and never `pgrep -f`; never bare `git stash`.
- `printf '%s' ... | grep -q` under `pipefail` is a fail-open; capture and test on separate lines.
- The plan-time scratch worktrees are not part of the deliverable; remove them with `git worktree remove`.

## Execution outcome — 2026-10-01 (appended; the sections above are the pre-implementation plan)

- PR-A shipped A1 (patsub), A2 (growth cap, counted in bytes; a review showed it is not identity-preserving in
  general, removing it measured 220-260 s against ~90 s, so it stayed with its limit stated), A3a (shadow set, `+=`)
  and the closure visited-set lever. The memo-index lever was not taken (a review prototype is unmeasured on the
  full walk). Measured figures: 4.0x (README probe) and 4.4x (multi-path probe) median CPU, selection identical;
  they replace the 4.6x to 5.9x forecast in DC2 and AC2, and the AC3 "eight suites each under 3 s" check is
  withdrawn (the eight were first-touch attribution, not expensive suites). See ADR-242, Amendment — 2026-10-01.
- The class-only (`--print-affected-set`) comparison, `--json` and `--report-diff` were dropped from the bench on
  review (the class-only stream cannot see the derive and false-reds on diff-state; the others had no user).
- AC1 changed as the class-only comparison was dropped; AC3 is withdrawn (see above); AC7 was met as a comment on
  #9307 carrying the measured reasons and the PR-B/PR-C/D5 scope, not as three new issues (net issue flow 0). The NFR
  register assessment was not run: the change is operator tooling and a derive-speed change with no new runtime
  surface, and ADR-242 amendment decision 16 records the design.

