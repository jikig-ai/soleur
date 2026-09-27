---
title: "fix: infra mutation batteries score rows through one shared capture-then-match scorer (#8855)"
type: fix
date: 2026-09-27
slug: fix-mutation-battery-shared-scorer
branch: feat-one-shot-8855-mutation-scorer-pipe
issue: 8855
closes: [8855, 8871]
priority: p3
domain: engineering
brand_survival_threshold: none
pr: 9033
lane: cross-domain
---

# fix: infra mutation batteries score rows through one shared capture-then-match scorer

## Enhancement Summary

**Deepened on:** 2026-09-27.

**Sections enhanced:** Lib self-test, Guard Contract (Guard 1), Consumer conversions, AC7 and AC8.

**Agents used:**

- `soleur:engineering:review:test-design-reviewer`
- `soleur:engineering:review:pattern-recognition-specialist`
- a verify-the-negative pass (standard tier)
- a hands-on prototype of the lib in the session scratchpad, measured against every mutant below

### Key Improvements

1. **Self-test gaps closed.**
   - New row S1b puts the needles on different failure lines. It kills a `grep -m1` capture and a
     dropped `-E`, both measured surviving v1.
   - S11 (uncompilable ERE) is restored. The v1 trim let a `[[ -r ]]` precheck plus `rc <= 2`
     survive (measured: S10 = 2, S11 = 1).
   - The alternation ERE is now used in S1, as the real callers use it.
2. **Count pin hardened.**
   - Abort rows assert in the parent shell.
   - They also require the `HARNESS ABORT: mutation_scorer:` stderr text.
   - `EXPECTED` counts assertion calls, not table rows.
   - An `INSTRUMENT BROKEN` counter check runs first.
   - `ALL PASS` prints only after the pin passes.
3. **Repo conventions adopted.**
   - The repo-root `# shellcheck source=` form; `source-path=` has no precedent in the repo.
   - two-space-indented PASS/FAIL lines that the infra runner's `MARKER_ERE` surfaces.
   - Exit 2 for a set-up fault, never 3.
   - The `scratch-root.test.sh` temp-dir and trap pattern.
   - File modes 100644 for the lib and 100755 for the test.
   - Consumers that already define `die` use it for the source abort.
4. **AC7 executes distinct axes.**
   - Guard 1 rows 1, 3, 6 and 11; Guard 2 rows 3 and 7.
   - An instrument-control run comes first.
   - Only rc 1 counts as a kill.

### New Considerations Discovered

- `pipefail` in the self-test's `set` line is load-bearing. Without it, the old `| grep -qF` shape
  returns 0 on S1 and survives. It is now pinned by harness row (f).
- The verify-the-negative pass confirmed all eight negative claims:
  - the call sites run in the battery's own shell;
  - no RED row names `-`;
  - no kill row has an empty expectation;
  - the scorer-shape pattern hits exactly 7 lines;
  - no `.tf` file is edited;
  - the guard has 4 existing PASS lines;
  - the zot-pull abort rows still see rc 2 through the wrapper;
  - `--list` prints each path indented by two spaces.
- Prototype measurements: 5 scorer calls on the 1.26 MB fixture take 0.27 s in total. An
  errexit-caller miss returns cleanly. shellcheck is clean.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Several infra mutation batteries decide whether a mutant was killed on its named assertion by
filtering a guard's output for failure lines and then searching that filtered stream for the row's
expected string. This plan moves those row-verdict scorers onto the capture-once, match-in-bash shape
that the zot-pull battery's `failed_on` already uses, where an unreadable log and an empty needle are
harness aborts rather than silent verdicts, and pins each converted file in the grep-q pipe guard.

The work lands as one shared sourced library, `apps/web-platform/infra/lib/mutation-scorer.sh`, with
its own deterministic self-test. Seven scorer sites in five batteries route through it: the six the
issue names, plus the betterstack battery that the issue's follow-up comment added. The zot-pull
battery's `failed_on` becomes a one-line wrapper over the library, so there is one implementation.

**Scope correction from research (see Premise Validation):** #8763 already replaced the six named
sites' `| grep -qF` with `| grep -cF` two days ago. That removed the SIGPIPE flake at those six. What
they still lack is the other half of the remedy: grep rc ≥ 2 and an empty needle both fold into a
verdict instead of aborting. The one site that still has the live SIGPIPE flake is betterstack's
`attributed()`, which #8763's sweep did not reach.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8855 is OPEN**, no closing PR. **#8871 is OPEN** (decision-challenge record of PR #8848).
- **Blocker #8763 is MERGED** (2026-09-25T14:25Z) — confirmed; `apex-single-node-replace-mutation.test.sh` is uncontended.
- **Stale part of the premise — the SIGPIPE flake is already gone at all six named sites.** #8763
  (commit `50ae36eff7`), merged ~3.5 h after #8855 was filed, mechanically rewrote every
  `| grep -qF -- "$x"` in 18 infra test files to `| grep -cF -- >/dev/null "$x"`. `grep -c` reads
  to EOF, so the producer never writes into a closed pipe. Measured in this session on a 1,260,025-byte
  fixture with the needle on line 2: the old `| grep -qF --` shape returned non-zero **30/30** (rc 141);
  the current `| grep -cF --` shape returned zero **30/30**. The six sites today read:
  - `apex-single-node-replace-mutation.test.sh` `score()`: `grep -E '^  FAIL|^\[VACUITY\]|^\[FATAL\]' "$WORK/out.txt" | grep -cF -- >/dev/null "$expect"`
  - `ssl-full-mitigation-mutation.test.sh` `case_row()` and `www-apex-canonicalizer-mutation.test.sh` `case_row()`: `grep -E '^  FAIL|^\[FATAL\]' "$log" | grep -cF -- >/dev/null "$expect"`
  - `web-host-provisioner-parity-mutation.test.sh` `expect_red()`, `expect_probe_red()`, `_g2_json_row()`: `grep -F "[FAIL]" "$OUT" | grep -cF -- >/dev/null "$anchor"`
- **What is still live at those six sites** (the remedy's other two properties, which `grep -c` does not buy):
  1. **grep rc ≥ 2 folds into "not found".** Under `pipefail` an unreadable log makes the producer exit 2,
     the `!` reads it as a miss, and the row scores MISROUTED instead of aborting the harness.
  2. **An empty needle is a vacuous KILL.** `printf 'a\n' | grep -cF -- ''` prints `1` rc 0 (measured) —
     `-F ''` matches every line, so any red row whose expectation is empty scores KILLED on *any* failure.
     No red row passes `""` today (checked: ssl's `case_row` modes are `green` ×4 and `kill` ×16, and no
     `kill` row passes `""`; apex's `-` rows — M11, PF, M19, H2, H3 — are all GREEN), so this is a latent
     fail-open, not a live one.
- **Still-live SIGPIPE site the issue's follow-up comment added:**
  `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` `attributed()`:
  `for a in "$@"; do grep -F '[FAIL]' "$OUT" | grep -qF -- "$a" || return 1; done` — the exact #8664 shape,
  unconverted (it sits outside `apps/web-platform/infra/`, so #8763's sweep missed it). Also a latent
  fail-open: `attributed` with zero anchors returns 0.
- The comment's second extra site, `infra-config-repush-mutation.test.sh:812`
  (`printf … | grep -c '^STAY-GREEN|' >/dev/null`), is already `grep -c` — a harness floor, not a row
  verdict, and SIGPIPE-safe. Out of scope; acknowledged.
- **The issue comment's claim "the affected-path gate follows `source` edges" holds** —
  `scripts/test-all.sh` `_affected_*` closure: "Closure, bounded: follow source/import edges one level at a
  time." (depth ≤ 8). CI does not depend on it: `infra-validation.yml` triggers on `apps/*/infra/**` and
  `apps/web-platform/test/infra/**` and runs the full infra set.
- ADR corpus grep (`sigpipe|mutation batter|pipefail`) returned only incidental mentions; no ADR decides
  or rejects a shared test-scorer library.

### Property List (Phase 0.6b)

- **P1** A row's verdict is a function of its log's bytes, never of process scheduling (no early-exit reader on a pipe).
- **P2** An unreadable log or a regex that does not compile aborts the battery (exit 2), never scores a verdict.
- **P3** An empty needle, or no needle at all, aborts the battery, never scores KILLED.
- **P4** The matcher is scoped to the battery's failure-line prefix, so a string that appears only on a PASS line never scores KILLED.
- **P5** The four named batteries (plus the betterstack battery the issue's comment added) cannot silently regress to a piped scorer — each is named in `.claude/hooks/grep-q-pipe-guard.test.sh`.
- **P6** There is one implementation of P1–P4, with one deterministic self-test, not one copy per battery.

### Cut List (Phase 0.6b)

- *Per-file inline `failed_on` copies* → P6 → cut in favour of the shared lib the issue comment names as the default.
- *Widening the guard's pathspec to `apps/web-platform/**`* → P5 → cut: the guard header forbids widening a glob ("Growth happens by adding a named file, never by widening a glob"); the census below also shows ~30 unrelated `| grep -q` sites in `ci-deploy.sh` / `cron-egress-*.sh` that are #7005's scope.
- *Converting the 19 `| head -1` reads in the guard file* → no property here → cut; #8871 choice 2 stays accepted.
- *A new relevance-array entry in `scripts/lib/test-relevance-paths.sh`* → P6's reach → cut: infra suites are not relevance-gated, and test-all's source-edge closure already reaches consumers.

### Census (with the guard's own PATTERN, per the #8664 learning's session-error 4)

- `git grep -nE "$PATTERN|$PATTERN_AWK_EXIT" -- 'apps/web-platform/**/*mutation*.test.sh'`, code lines only:
  **one** hit — `betterstack-send-failed-alert-mutation.test.sh:102`. (Comment hits in
  `infra-config-repush`, `workspaces-luks-g4`, `supabase-advisor/scan-workflow-mutation` are prose;
  `scan-workflow-mutation.test.sh:93-94` are deliberate SIGPIPE demonstrations inside `( … )`.)
- A scorer-shape pattern `(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+--([[:space:]]|$)`
  ("a pipe into a grep whose flags end in `--`") hits **exactly the 7 scorer sites** (6 + betterstack) and
  nothing else across the six consumer files; validated in this session against 6 bad / 5 good probe lines
  (6/6, 0/5), including `printf … | grep -cF 'www.soleur.ai'` (ssl-full-mitigation's mutator text) and
  `| grep -v '/\.terraform/'` (parity's TF_FILES enumeration), which it must not match.

### Relevant files

- Reference implementation: `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh` `failed_on()` and its scorer self-test (`SELFTEST_LOG`, 20,000 × `  FAIL: filler` lines after the needle, the empty-needle and unreadable-log abort rows). <!-- markdownlint-disable-line MD038 -->
- Drift guard: `.claude/hooks/grep-q-pipe-guard.test.sh` — `PATTERN`, `PATTERN_AWK_EXIT`, `ALLOW_MARKER`, `FILES_7024`, `FILES_8664`, the tracked-file + member-count pin, the `failed_on "$SELFTEST_LOG" SELFTEST-TARGET` presence pin, the non-vacuity probe.
- Suite registration: `apps/web-platform/infra/run-registered-suites.sh` derives suites with `git ls-tree -r --name-only HEAD -- apps/web-platform/infra | grep -E '\.test\.sh$'` (ADR-252: "presence IS registration"; `-r` makes subdirectory suites visible). A committed `apps/web-platform/infra/lib/mutation-scorer.test.sh` is registered by existing.
- `.claude/hooks/*.test.sh` is in `scripts/test-all.sh` `SUITE_GLOBS`, so the guard edit runs in test-all.
- The betterstack battery runs as an explicit step in `.github/workflows/infra-validation.yml` ("Run Better Stack SEND_FAILED alert MUTATION battery").
- Consumers: all use `set -uo pipefail` (no `-e`). The five direct scorer sites (apex, ssl, www, parity ×3, betterstack) run in the battery's own shell, so a lib `exit 2` terminates the battery. zot-pull's `case_mutate` (which calls `failed_on`) runs inside `( … )`/`$( … )` at three harness rows; two end in `|| die` and the third checks rc 2 on purpose, so an abort still aborts. `ssl-full-mitigation`, `www-apex-canonicalizer` and zot-pull define `die()` (exit 2); `apex`, `parity`, `betterstack` do not — the lib must carry its own abort and must not define or depend on `die`.
- Row-count pins that must not move: apex `EXPECTED_ROWS=31`, www `EXPECTED_ROWS=28`, betterstack `EXPECTED_ROWS=36`.
- Pre-existing display bug in the same files: `ssl-full-mitigation-mutation.test.sh` and `www-apex-canonicalizer-mutation.test.sh` baseline-abort branches read `grep -E '^  FAIL|^\[FATAL\]' "$BASE_LOG" >&2 | head -20` — the redirect sends grep's stdout to stderr, so `head -20` receives nothing and the list is unbounded.

### Institutional learnings applied

- `knowledge-base/project/learnings/test-failures/2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md` — capture-then-glob; abort on rc ≥ 2; refuse empty needle; >1 MiB self-test; **every deterministic regression input gets a positive control that restores the defect**; end display branches of a status-read function with explicit `return 0`; census with the guard's PATTERN, never a variable-keyed search.
- `…/2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md` — pin the bytes the producer must still write **after** the needle, not the file size (a needle moved to the last line keeps the size and disarms the row).
- `knowledge-base/project/learnings/2026-03-18-shared-test-helpers-extraction.md` — duplicated helpers drift; `[[ "$h" == *"$n"* ]]` over `echo | grep -qF`.
- `knowledge-base/project/learnings/best-practices/2026-06-02-shared-helper-fix-must-grep-for-inline-copies-before-claiming-blast-radius.md` — grep for inline copies before claiming coverage (the scorer-shape census above is that grep).
- `knowledge-base/project/learnings/2026-05-11-drift-guard-scoping-extract-call-site-not-widen-walk.md` — name files, do not widen the walk.
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — `x="$(grep …)"; rc=$?` aborts under `set -e`; write `rc=0; x="$(grep …)" || rc=$?` in a sourced lib that cannot know its caller's options.

### Related issues / PRs

- #8664 / PR #8848 (merged 2026-09-27) — origin of `failed_on`; filed #8855 and #8871.
- #8763 (merged 2026-09-25) — the `grep -q` → `grep -c` sweep that already removed the SIGPIPE at the six sites.
- #8871 — choice 1 (defer sibling batteries) is fulfilled here; choice 2 (19 `| head -1` reads) stays accepted. PR body carries `Closes #8871`.
- #7005 — repo-wide pipefail + `grep -q` sweep in `scripts/` and `plugins/`; different area, not a duplicate.
- #7942 — open code-review issue that names `apex-single-node-replace-mutation.test.sh` only as an example of correct naming; no overlap in substance.

### Functional overlap

`soleur:engineering:discovery:functional-discovery`: no community skill/agent overlaps (general mutation-testing
skills mutate code; none scores bash battery rows or addresses pipefail/SIGPIPE). Nothing installed.

## Plan Review Revisions

The review panel had four seats: DHH, Kieran and code-simplicity, plus the CTO on devex. A scoped
advisor consult ran before it. Mechanical findings were applied:

- **Kieran P1 (conversion table):** in the v1 table the ERE alternation was escaped as `\|`, which
  `grep -E` reads as a literal pipe. Measured: 0 of 2 lines matched. The snippets now live in a code
  block.
- **Kieran P1 (AC3):** the runner's `--list` also prints untracked on-disk suites, so the v1 grep
  passed before the commit. It is now an exact-line match with no `NOT git-tracked` line.
- **Kieran P2 (subshell claim):** corrected. zot-pull's `case_mutate` does run in subshells, and
  already aborts on rc 2.
- **Kieran P2 (apex `-`):** a RED row naming `-` now fails the row instead of skipping attribution.
- **Kieran P2 (AC6, shellcheck, harness row):**
  - AC6 now says four existing PASS lines, not three.
  - AC8 requires `source=` directives.
  - Guard 2 harness row (a) was rewritten.
- **Both simplification seats fired on the same guard items; the fix was to delete them.** Cut:
  - Routing presence, the same-shell pin and the lib-test presence pin.
  - The lib test's standing positive control, and with it the `ALLOW_MARKER` carve-out.
  - Eight self-test rows (S3, S4, S11, S12, S13, S15, S16, S1-PC). Deepen later restored S11 and added S1b.
  - The empty-ERE check and the refuse-execution line.
  - Plan v1's no-pipe AC and census AC.
  - The v1 display-fix AC (the fix itself stays in the diff).
  - AC7 was cut down to five matrix rows.
- **CTO (applied):**
  - The lib header states its scope and that every consumer must be listed in `FILES_8855`.
  - A comment beside the array names the places that change together.
  - The consumer-contract checks were kept out of the pipe guard.
- **Not applied, recorded in `knowledge-base/project/specs/feat-one-shot-8855-mutation-scorer-pipe/decision-challenges.md`:**
  - CTO: add a pointer in the plan skill's references telling future battery authors to use the lib.
  - The scope addition of the betterstack battery, which the operator's brief did not name.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on `origin/main` (81827c46b5) | Plan response |
|---|---|---|
| Six sites read `grep … \| grep -qF -- "$expect"` and flake under load | Since #8763 they read `grep … \| grep -cF -- >/dev/null "$expect"`; `grep -c` reads to EOF (30/30 clean on a 1.26 MB fixture) | Convert anyway, for P2/P3/P6. The PR body must not say these six "flaked"; it says #8763 removed the SIGPIPE there and this PR adds the abort semantics and the single chokepoint |
| "Four files" are the scope | The issue's own follow-up comment adds `betterstack-send-failed-alert-mutation.test.sh` (a live `\| grep -qF --` scorer) and `infra-config-repush-mutation.test.sh:812` (already `grep -c`, a floor, not a verdict) | Fold betterstack in (it is the only live instance of the class); acknowledge infra-config-repush as already safe |
| "Add each file to the named-file zero pin" | Today's `PATTERN` does not match `grep -c`, so the pin passes on the *unconverted* files — it cannot tell this PR from its revert | Add the files **and** a scorer-shape pattern that matches exactly the 7 sites today (census above) |
| The lib is "the alternative if more than two files are converted" | Five batteries plus zot-pull's copy | Lib is the chosen shape (P6) |

## Problem Statement / Motivation

A mutation battery earns its keep only if a row's verdict means what it says. Each scorer site answers
"did the guard go red **on the assertion this row targets**?" Three ways that answer can be wrong
survive on `main`:

1. **Scheduling-dependent verdict (P1)** — betterstack's `attributed()` pipes into `grep -qF`. When the
   guard's `[FAIL]` stream exceeds a stdio chunk after the needle, the producer takes SIGPIPE and
   `pipefail` reports a killed row as mis-attributed at random. This is the #8664 defect, measured there
   at 64/3000 runs.
2. **Unreadable log scores a verdict (P2)** — at all seven sites a producer rc 2 is read as "needle
   absent". It fails the row (loud), but names the wrong cause: MISROUTED, not "harness broken".
3. **Empty needle scores KILLED (P3)** — `grep -F ''` matches every line. A red row added later with an
   empty expectation (a typo'd variable under `set -u` cannot produce this, but a `"${x:-}"` default can)
   would be KILLED by any failure at all. `attributed` with zero anchors returns 0 outright. Latent today,
   fail-open when it fires.

Five copies of the scorer (plus zot-pull's) is also how the defect class spread: #8664 fixed one copy,
and the review had to go hunting for the others (P6).

## Proposed Solution

### The library — `apps/web-platform/infra/lib/mutation-scorer.sh`

One function, sourced-only, no global side effects:

```bash
# shellcheck shell=bash
# Scope: web-platform infra mutation batteries only. Every consumer must also be listed in
# FILES_8855 in .claude/hooks/grep-q-pipe-guard.test.sh.
# mutation_scorer_failed_on <log> <fail-line-ERE> <needle> [<needle>...]
#   return 0  iff EVERY needle is a substring of some line of <log> matching <fail-line-ERE>
#   return 1  otherwise (including "the log has no failure lines at all": grep rc 1)
#   exit 2    harness abort: no needle, an empty needle, or grep rc >= 2
#             (unreadable log / ERE that does not compile)
# Call it in the battery's own shell. Inside $( … ), ( … ) or a pipeline stage, exit 2 leaves only
# that subshell; the caller must then treat rc 2 as an abort itself (zot-pull's `|| die` does).
```

Implementation contract (the implementer writes it; these are the load-bearing lines):

- Own abort helper, namespaced: `_mutation_scorer_abort() { printf 'HARNESS ABORT: mutation_scorer: %s\n' "$*" >&2; exit 2; }`.
  **Do not define or call `die`** — three consumers define their own and three define none.
- Validate before reading: `(( $# >= 3 ))` and every needle non-empty — all before grep runs.
- Capture with an `errexit`-safe form, because a sourced lib cannot know its caller's options:
  `local fails rc=0; fails="$(grep -E -- "$ere" "$log")" || rc=$?; (( rc <= 1 )) || _mutation_scorer_abort …`.
- Match in bash, quoted, so glob metacharacters in a needle are literal: `[[ "$fails" == *"$needle"* ]] || return 1`.
- End with an explicit `return 0`. No display output, no pipes anywhere in the file.
- Sets no shell options, defines no variables at file scope beyond the two functions.

Cut at plan review (both simplification seats): an empty-ERE check (every call site passes a literal
ERE) and a refuse-direct-execution line (running the file directly defines a function and exits 0,
which is harmless).

### Consumer conversions (7 sites + 1 wrapper)

Each consumer sources the lib once, near the top, after its root variable exists. It carries the
repo-root shellcheck directive so `shellcheck -x` can follow the source, and it aborts if the source
fails. The abort differs by file:

- ssl, www and zot-pull already define `die` (exit 2), so they use `|| die "could not source mutation-scorer.sh"`.
- zot-pull also checks the path first, following its lines 64–68 (`[ -f ] && [ -r ] || die`), and
  places the source line **before** `failed_on()` and its self-test calls.
- apex, parity and betterstack have no `die`, so they use the inline form:

```bash
# shellcheck source=apps/web-platform/infra/lib/mutation-scorer.sh
source "$SCRIPT_DIR/lib/mutation-scorer.sh" \
  || { echo "HARNESS ABORT: could not source mutation-scorer.sh" >&2; exit 2; }
```

Resolve the path from what each battery already computes: `SCRIPT_DIR` (`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`)
in apex, ssl, www and zot-pull; `REAL_INFRA` in parity; `$ROOT/apps/web-platform/infra/lib/…` in
betterstack (`ROOT` is `git rev-parse --show-toplevel`). Never a hard-coded checkout path, and never a
sandbox copy that a mutation could touch.

**Call-site shell.** The five direct call sites (apex, ssl, www, parity ×3, betterstack) are
`if`/`elif`/`&&` conditions in the battery's own shell, so the lib's `exit 2` ends the battery.
zot-pull is the exception and is correct as it stands: `case_mutate` (which calls `failed_on`) runs
inside `( … )` or `$( … )` at three harness rows. Two of them end in `|| die`, and the third checks
for rc 2 on purpose, so an abort still aborts.

The new site shapes (a bare `|` inside the quoted ERE means alternation; **do not** backslash it — in
`grep -E`, `\|` is a literal pipe, so `'^  FAIL\|^\[FATAL\]'` matches nothing):

```bash
# apex-single-node-replace-mutation.test.sh — score(), inside the want == RED branch.
# A RED row must name its expectation. Replace the `[[ "$expect" != "-" ]] &&` skip with a row failure:
if [[ "$expect" == "-" ]]; then
  verdict 1 "$id: a RED row must name the case it expects (got '-')"; return
fi
if ! mutation_scorer_failed_on "$WORK/out.txt" '^  FAIL|^\[VACUITY\]|^\[FATAL\]' "$expect"; then

# ssl-full-mitigation-mutation.test.sh and www-apex-canonicalizer-mutation.test.sh — case_row(), kill path
if ! mutation_scorer_failed_on "$log" '^  FAIL|^\[FATAL\]' "$expect"; then

# web-host-provisioner-parity-mutation.test.sh — expect_red() and expect_probe_red()
elif mutation_scorer_failed_on "$OUT" '\[FAIL\]' "$anchor"; then
# … and _g2_json_row(): keep the want==red short-circuit BEFORE the call (green rows pass anchor "")
elif [[ "$want" == red ]] && mutation_scorer_failed_on "$OUT" '\[FAIL\]' "$anchor"; then

# betterstack-send-failed-alert-mutation.test.sh — every anchor must match, as before;
# zero anchors now aborts instead of returning 0
attributed() { mutation_scorer_failed_on "$OUT" '\[FAIL\]' "$@"; }

# cloud-init-inngest-zot-pull-mutation.test.sh — keep the name, trim its comment to point at the lib,
# leave its scorer self-test block byte-unchanged (the guard pins `failed_on "$SELFTEST_LOG" SELFTEST-TARGET`)
failed_on() { mutation_scorer_failed_on "$1" '^  FAIL' "$2"; }
```

Notes per file:

- **apex:** the rows passing `-` today (M11, PF, M19, H2, H3) are all GREEN, and `score()` only
  reaches the scorer under `want == RED`, so no current row changes verdict. Keeping the old
  `!= "-"` skip would let a future RED row written with `-` score KILLED on any failure, which is the
  P3 hole. And the lib would not abort on `-`, because it is a non-empty needle that matches any FAIL
  line containing a hyphen.
- **www:** rewrite the comment above the site. It still says `grep -qF -- "$expect"` and explains
  `--`. Say instead that the lib passes the needle to a bash match, never to grep, so the
  `--branch` / `--project-name` needles are literal.
- **parity:** `'\[FAIL\]'` as an ERE selects exactly the lines `grep -F '[FAIL]'` does (unanchored,
  literal brackets).

### Fold-in: the baseline-abort display bug in ssl-full-mitigation and www-apex-canonicalizer

`grep -E '^  FAIL|^\[FATAL\]' "$BASE_LOG" >&2 | head -20` sends grep's stdout to stderr, so `head -20`
reads nothing and the list is unbounded. Rewrite to `grep -E '^  FAIL|^\[FATAL\]' "$BASE_LOG" | head -20 >&2`.
This is display in a branch that `exit 2`s on the next line, so the `| head` status is never read. It is
two lines in files this PR already edits (no separate AC; review reads the diff).

### Guard — `.claude/hooks/grep-q-pipe-guard.test.sh`

The guard gains one list and one pattern, nothing else. Plan review cut three consumer-contract
checks: routing presence, the same-shell pin, and a presence pin on a lib-test line. Each guarded a
regression that either fails closed already or is anchored elsewhere, and none of them concerned
piped `grep` (CTO: they would belong beside the scorer, not in this guard).

1. Header: add a `#8855` paragraph under the `#8664` one. It names the files and says why the
   scorer-shape pattern exists: `PATTERN` does not see the `grep -c` spelling that #8763 introduced.
2. `FILES_8855=( … )`: 6 members, named individually. They are `apps/web-platform/infra/lib/mutation-scorer.sh`,
   the four infra batteries, and `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`.
   zot-pull stays in `FILES_8664`. The lib test is not listed: nothing in it runs a piped shape, so it
   needs no `ALLOW_MARKER` carve-out. Put a one-line comment beside the array naming the places that
   must change together: the array, the member count below, and the lib header's consumer note.
3. Extend the tracked-file loop to `"${FILES_8855[@]}"`, and the member-count condition with `|| ${#FILES_8855[@]} != 6`.
4. New `PATTERN_PIPED_SCORER='(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+--([[:space:]]|$)'`,
   meaning "a pipe into a grep whose flags end in `--`". Every scorer spelling shares that signature
   (`| grep -qF --`, `| grep -cF --`). Add it to the ERE-compile loop.
5. `hits_8855` = `git grep -nE "$PATTERN|$PATTERN_AWK_EXIT|$PATTERN_PIPED_SCORER" -- "${FILES_8855[@]}"`,
   with comment lines stripped exactly like the #8664 pass. No opt-out marker.
6. Non-vacuity probe: add `bad-scorer.sh` with the 7 real pre-PR site spellings. Add `good-scorer.sh`
   with these lines:
   - `printf '%s' "$m" | grep -cF 'www.soleur.ai' >/dev/null`
   - `| grep -v '/\.terraform/' | sed …`
   - `a || grep -qF -- "$x" <<<"$y"`
   - `mutation_scorer_failed_on "$log" '^  FAIL' "$e"`
   - `grep -qF -- "$a" "$f"`

   Compare them as counts, exactly like the existing probe. This census already passes: 6/6 bad lines
   and 0/5 good lines matched in this session.
7. New PASS line: `PASS: grep-q-zero-8855-pass (scorer lib and five batteries)`.

### Lib self-test — `apps/web-platform/infra/lib/mutation-scorer.test.sh`

Registered by presence (ADR-252), committed as mode `100755`. It sources the lib from
`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mutation-scorer.sh`, with the repo-root directive form
`# shellcheck source=apps/web-platform/infra/lib/mutation-scorer.sh`. That is the form
`apex-origin-probe.sh` and `cutover-verify.sh` use; no infra file uses `source-path=`.

Set-up and conventions:

- `set -uo pipefail`. **`pipefail` is load-bearing:** without it, Guard 1 row 1 (the old
  `| grep -qF` shape) returns 0 on S1 and survives (measured during deepen).
- Temp dir, following the `scripts/lib/scratch-root.test.sh` pattern, in this order:
  - `T="$(mktemp -d …)" || exit 2`
  - `[[ "$T" == /* && -d "$T" && ! -L "$T" ]]`
  - `trap 'rm -rf -- "$T"' EXIT INT TERM`

  Do not source `test-helpers.sh`.
- Report lines: `pass(){ echo "  PASS: $1"; …; }` and `fail(){ echo "  FAIL: $1"; …; }`, with the row id
  in the label (for example a line reading "FAIL: S6 …" after the two-space indent). That shape matches `run-registered-suites.sh`'s
  `MARKER_ERE`, so a red run shows the failing row.
- Exit codes: 0 green, 1 any row failure or count-pin mismatch, 2 set-up fault (`HARNESS ABORT: …`,
  for example the S1 fixture lost its needle-on-line-2 shape or its ≥ 1 MiB tail). Never 3 — that is
  the runner's own "suite was killed" code.
- Instrument check first (as `trusted-verdict.test.sh` does): call `pass` and `fail` once each on
  throwaway labels, confirm both counters moved, reset them, and exit 2 with `INSTRUMENT BROKEN`
  otherwise.

Trimmed at plan review: the zot-pull self-test already exercises the needle-first / PASS-scope /
empty-needle / unreadable-log cases *through the lib*, and www's live `--branch` rows exercise
option-shaped needles. This file keeps the lib's own unit, plus what a single-needle caller cannot reach.

| Row | Input | Expected |
|---|---|---|
| S1 needle-first | the zot-pull fixture shape, where every PASS/FAIL line starts with two spaces: line 1 is a PASS line reading "PASS: SELFTEST-ONLY-ON-PASS would  FAIL if unscoped", line 2 is "FAIL: SELFTEST-TARGET", then 20,000 "FAIL: filler …" lines, then a last line that starts at column 0 with "[FATAL] SELFTEST-LAST-FATAL". Call it with the real ssl/www alternation ERE (`^  FAIL` or `^\[FATAL\]`, written in the file with a bare pipe exactly as in the Consumer conversions code block). Also assert the bytes **after** the needle line are ≥ 1,048,576 (pin the cause, not the file size) | rc 0 |
| S1b needles on different lines | S1 fixture, needles `SELFTEST-TARGET` and `SELFTEST-LAST-FATAL` (first FAIL line and the last, `[FATAL]`-prefixed line) with the alternation ERE | rc 0 — kills a `grep -m1` capture, a "same line" rewrite, and a dropped `-E` |
| S2 PASS-scope | needle `SELFTEST-ONLY-ON-PASS` on the S1 fixture | rc exactly 1 |
| S5 second needle missing | first needle present, second absent | rc exactly 1 |
| S6 no failure lines | log with only PASS lines (grep rc 1) | rc exactly **1**, not 2 |
| S7 empty needle | `""` | exit 2 |
| S8 empty second needle | `X ""` | exit 2 |
| S9 zero needles | 2 args | exit 2 |
| S10 unreadable log | nonexistent path | exit 2 |
| S11 uncompilable ERE | `'('` on the S1 fixture | exit 2 — restored at deepen: a `[[ -r $log ]]` precheck plus `rc <= 2` passes S10 yet returns 1 here |
| S14 glob-metachar needle | `[ab]*`: absent literally while `a` is present → rc exactly 1; present literally → rc 0 | as stated |

Every rc-1 row is paired with an rc-0 row on the same fixture (S2/S1, S5 with a first-needle-only
call, S14's two halves). Each asserts rc is exactly `1` and not `2`.

Abort rows (S7–S11) run the call as `rc=0; ( mutation_scorer_failed_on … ) 2>"$T/err" || rc=$?`.
They assert in the **parent** shell, so no `pass`/`fail` increment is lost inside the subshell, and
each requires both of these:

- `rc == 2`;
- `$T/err` contains `HARNESS ABORT: mutation_scorer:`. A bare rc 2 could be bash misuse.

`EXPECTED` counts **assertion calls**, not table rows: S1, S14 and the paired rc-0 calls each make
more than one. The suite ends with `(( pass == EXPECTED && fail == 0 ))`, else exit 1. Only after
that pin passes does it print exactly `mutation-scorer self-test: ALL PASS`. That literal is the
discoverability probe below.

No positive control line lives in this file. The old piped shape is exercised once, at
implementation time, by Guard 1 matrix row 1 (AC7). Measured in this session: `| grep -qF` on
the S1 fixture returned 141 in 30/30 runs. A standing positive control would test grep, not the lib,
and would require an opt-out in the pipe guard.

## Technical Considerations

- **Performance.** `[[ "$fails" == *"$needle"* ]]` over ~1.2 MB is what zot-pull already does per row;
  real guard logs are a few KB. No measurable change to battery wall time.
- **Behaviour change, fail-closed only.** Every semantic change turns a verdict into an abort (rc ≥ 2,
  empty needle, zero needles) or, at apex, a RED row naming `-` into a row failure. No row that is
  KILLED today on real input can become SURVIVED. This holds because every consumer negates or
  AND-s the scorer; a future `||` fallback at a call site would not hold it.
- **`set -u` in consumers.** The lib reads only its positional parameters and locals.
- **Blast radius of merge.** `apply-web-platform-infra.yml` fires on any push to `main` touching
  `apps/web-platform/infra/**` (target-scoped). This PR changes no `.tf`, so the plan is expected to be a
  no-op, exactly as for #8763 and #8848. The merge-message kill switch `[skip-web-platform-apply]` exists if
  ship prefers not to run it.
- **NFR impact:** none (test harness only).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. A broken scorer would make an infra
  guard's mutation battery report wrong verdicts, which could let a weakened production guard (DNS apex,
  SSL mode, web-host provisioning parity, Better Stack alerting) merge unnoticed later.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector; the change
  reads only local test logs and touches no credentials, network, or user data.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched apps/web-platform/infra/ paths are test harnesses and a sourced test library that run only in CI and locally; no deployed artifact, Terraform expression or host reads them.`

## Observability

```yaml
liveness_signal:
  what: the infra-validation workflow's deploy-script-tests jobs, which run every registered infra suite (the new lib self-test included by presence) and the betterstack battery step
  cadence: per pull request touching apps/*/infra/** or apps/web-platform/test/infra/**, and per push to main on the infra content globs
  alert_target: the GitHub check on the PR (RED check run)
  configured_in: .github/workflows/infra-validation.yml
error_reporting:
  destination: GitHub Actions job log for deploy-script-tests; stderr of each battery
  fail_loud: "HARNESS ABORT: mutation_scorer: <reason>" on stderr with exit 2 for rc>=2 or empty/absent needles; "MISROUTED" / "went red but NOT via" rows for real attribution misses; the runner prints "RED <path>"
failure_modes:
  - mode: a consumer's source line breaks (moved or renamed lib)
    detection: the source line aborts the battery with exit 2 before any row runs; the guard's tracked-file pin reds on a renamed lib
    alert_route: RED check on the PR
  - mode: someone reintroduces a piped scorer (grep -q or grep -c spelling) in a named file
    detection: .claude/hooks/grep-q-pipe-guard.test.sh FILES_8855 pass (PATTERN or PATTERN_PIPED_SCORER)
    alert_route: RED check on the PR
  - mode: the lib is edited back into an early-exit or rc-folding shape
    detection: mutation-scorer.test.sh rows S1, S1b, S6-S11 (deterministic), plus zot-pull's own scorer self-test, which runs through the lib
    alert_route: RED check on the PR
logs:
  where: GitHub Actions run logs for infra-validation.yml and the test-all run that executes .claude/hooks suites
  retention: GitHub Actions default log retention for this repository
discoverability_test:
  command: bash apps/web-platform/infra/lib/mutation-scorer.test.sh
  expected_output: "mutation-scorer self-test: ALL PASS"
```

## Guard Contract

### Guard 1 — mutation-scorer lib self-test

**Property.** `mutation_scorer_failed_on` returns 0 exactly when every needle is a substring of some failure-prefixed line of the log, 1 when one is not, and exits 2 on any input it cannot score (unreadable log or uncompilable ERE, empty or absent needle), independent of how the kernel schedules the processes involved.

**Assembly.** The single function `mutation_scorer_failed_on` in `apps/web-platform/infra/lib/mutation-scorer.sh` is the one chokepoint for every row verdict in the six consumer batteries. That covers five batteries' direct call sites plus zot-pull's `failed_on` wrapper. The self-test calls it through the same `source` a consumer uses. zot-pull's pre-existing scorer self-test is a second caller through the wrapper.

**Mutation matrix:**

| # | Mutation (to the lib) | Expected |
|---|---|---|
| 1 | Replace the capture with `grep -E -- "$ere" "$log" \| grep -qF -- "$needle"` (the #8664 shape) | RED (S1, deterministic 1 MiB tail) |
| 2 | Replace the capture with `grep -E -- "$ere" "$log" \| grep -cF -- "$needle" >/dev/null` (the #8763 shape) | RED (S10: rc 2 no longer aborts) |
| 3 | Delete the empty-needle loop | RED (S7, S8) |
| 4 | Keep the empty check but apply it only to the FIRST needle (second-member row) | RED (S8) |
| 5 | Loop `return 0` after the first matching needle | RED (S5) |
| 6 | Replace the ERE argument with `.` inside the lib (lose the failure-line scope) | RED (S2: line 1 is a PASS line carrying the needle) |
| 7 | Change `(( rc <= 1 ))` to `(( rc <= 2 ))` | RED (S10) |
| 8 | Unquote the needle in the glob (`*$needle*`) | RED (S14) |
| 9 | Replace the whole function body with `return 0` | RED (S2, S5, S6) |
| 10 | Replace the whole function body with `return 1` | RED (S1) |
| 11 | Capture with `grep -m1 -E` (stop after the first failure line) | RED (S1b) |
| 12 | Drop `-E` from the capture (in a basic regex a bare pipe is a literal character, so the alternation stops matching) | RED (S1, S1b) |
| 13 | Add a `[[ -r $log ]] \|\| _mutation_scorer_abort` precheck and relax to `(( rc <= 2 ))` | RED (S11) |

**Harness rows.**

- (a) Delete S1's filler loop so the fixture is 2 lines. The bytes-after-needle floor goes RED, so the suite pins the cause, not only the verdict.
- (b) Delete any one row. The exact `pass == EXPECTED` count pin fails.
- (c) Make the suite source a stub lib whose function is `return 0`. S2, S5 and S6 go RED.
- (e) Move an abort row's `pass`/`fail` call inside its `( … )`. Its increment is lost, and the exact `pass == EXPECTED` pin goes RED.
- (f) Delete `pipefail` from the suite's `set` line, then apply matrix row 1. The row now survives. This shows `pipefail` is doing the work, and that the suite's `set` line is part of the contract.
- (d) Must-PASS non-canonical input: S14's literal-present half is a needle with glob metacharacters. It differs from the canonical S1 needle in a way the contract permits, and must stay GREEN.

**Anchor.** The self-test's expectations are literal rows in the same file as the fixtures, so one diff could weaken both. The outside anchor is zot-pull's pre-existing scorer self-test. It runs through the lib after this PR, and it is pinned by the guard's `failed_on "$SELFTEST_LOG" SELFTEST-TARGET` presence check, which this PR does not edit.

### Guard 2 — grep-q-pipe-guard #8855 pass

**Property.** No named #8855 file contains, on a non-comment line, a pipe into a grep that can stop at its first match, a pipe into an `awk` that exits, or a pipe into a fixed-string scorer grep (`| grep … --`).

**Assembly.** `FILES_8855` (6 named files) in `.claude/hooks/grep-q-pipe-guard.test.sh`, scanned by one `git grep -nE "$PATTERN|$PATTERN_AWK_EXIT|$PATTERN_PIPED_SCORER"`. It also covers the shared tracked-file and member-count pin, the ERE-compile loop, and the non-vacuity probe. Growth is by naming a file, never by widening a glob.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert one converted site in `ssl-full-mitigation-mutation.test.sh` to the pre-PR `grep -E … "$log" \| grep -cF -- >/dev/null "$expect"` | RED (PATTERN_PIPED_SCORER) |
| 2 | Revert betterstack's `attributed()` to the pre-PR `\| grep -qF -- "$a"` | RED (PATTERN and PATTERN_PIPED_SCORER) |
| 3 | Leave parity's first site converted and revert only its **third** (`_g2_json_row`) | RED (the scan reports every hit, not the first) |
| 4 | Rename `apps/web-platform/infra/lib/mutation-scorer.sh` (git mv) without updating the list | RED (tracked-file pin) |
| 5 | Delete one entry from `FILES_8855` | RED (member count ≠ 6) |
| 6 | Break `PATTERN_PIPED_SCORER` into a non-compiling ERE (e.g. an unbalanced `(`) | RED (ERE-compile loop exits 3, UNRESOLVED) |
| 7 | Edit `PATTERN_PIPED_SCORER` so it no longer matches `\| grep -cF --` | RED (non-vacuity probe bad-count) |

**Harness rows.**

- (a) Empty `FILES_8855` (delete every entry). The member-count check (`!= 6`) goes red, so the pass cannot report "0 checked" and exit 0.
- (b) Must-PASS non-canonical inputs, which must stay GREEN:
  - A comment line in a consumer that spells `| grep -qF -- "$expect"` while explaining history (the comment filter drops it).
  - ssl-full-mitigation's python-string line `printf '%s' "$m_expr" | grep -cF 'www.soleur.ai'`, which is not a scorer.
- (c) The four existing PASS lines (hooks, #7024, #8664, and the pattern self-check) must still print unchanged.

**Anchor.** The pinned list and the files live in one diff, so a PR could delete a file from the list and revert it in the same change. The member-count literal `6` reds that unless it is edited too, and that edit is visible in the diff of this one guard file. Accepted residuals:

- A line search cannot see a scorer split across lines or wrapped in `command grep`. The guard header's "Not matched" note records this, and #7005 tracks widening.
- A battery that inlines a correct capture-then-match instead of calling the lib is not flagged. P1–P4 still hold for it; only P6 (a single implementation) is lost.

## Acceptance Criteria

- [x] AC1 `apps/web-platform/infra/lib/mutation-scorer.sh` exists and defines exactly `mutation_scorer_failed_on` and `_mutation_scorer_abort`. It defines no `die`, sets no shell options, and is listed in `FILES_8855`. Its no-pipe property is enforced by Guard 2.
- [x] AC2 `bash apps/web-platform/infra/lib/mutation-scorer.test.sh` exits 0 and prints `mutation-scorer self-test: ALL PASS`.
- [x] AC3 After commit, `bash apps/web-platform/infra/run-registered-suites.sh --list | grep -cxF '  apps/web-platform/infra/lib/mutation-scorer.test.sh'` prints `1`, and the same `--list` output contains no `NOT git-tracked` line. (A bare `grep -c 'lib/mutation-scorer.test.sh'` also matches the runner's untracked-file report, so it passes before the commit.)
- [x] AC4 Each of the six consumer files has ≥ 1 non-comment `mutation_scorer_failed_on` line. In zot-pull, `failed_on` is a one-line wrapper and the scorer self-test block is byte-unchanged: `git diff origin/main...HEAD -- apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh` touches only the `failed_on` definition, its comment, and the added `source` lines.
- [x] AC5 All six batteries exit 0 with row totals unchanged. The pinned totals are apex `EXPECTED_ROWS=31`, www `EXPECTED_ROWS=28` and betterstack `EXPECTED_ROWS=36`. ssl, parity and zot-pull must report the same totals as on `origin/main`. Record the before and after totals in the PR body.
- [x] AC6 `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0 and prints `PASS: grep-q-zero-8855-pass …`. The four pre-existing PASS lines still print.
- [x] AC7 These matrix rows are executed against a detached worktree at the branch HEAD. The pristine self-test and pristine guard must each exit 0 first (instrument control).
  - Guard 1 rows 1, 3, 6 and 11.
  - Guard 2 rows 3 and 7.

  Only rc 1 counts as a killed mutant; rc 2 or 127 is an instrument fault. Every row must be observed RED and then restored. The Guard 2 row 3 RED output must name the `_g2_json_row` line number, proving it was the third parity site that was reverted and not the first. Record each row's observed output line in the PR body. Guard 1 row 1 doubles as the positive control, showing the S1 fixture exposes the early-exit defect.
- [x] AC8 Run from the repo root: `shellcheck -x apps/web-platform/infra/lib/mutation-scorer.sh apps/web-platform/infra/lib/mutation-scorer.test.sh` exits 0. There must be no SC1091, because the repo-root `source=` directives resolve. This is a local check only; no workflow runs shellcheck over `infra/*.sh`. `python3 scripts/lint-trap-tempfile-ownership.py apps/web-platform/infra/lib/mutation-scorer.test.sh` also exits 0. `git ls-files -s` shows the lib at mode `100644` and the test at mode `100755`.
- [ ] AC9 The first line of the PR #9033 body answers "does merging this alone mutate production?". The answer is no. Merging fires the target-scoped `apply-web-platform-infra.yml`, because the diff is under `apps/web-platform/infra/**`, but it changes no `.tf`, so the apply is expected to plan zero changes. The body also:
  - carries `Closes #8855` and `Closes #8871`;
  - states that #8871 choice 1 is fulfilled by this PR, and that choice 2 (the 19 `| head -1` reads) stays accepted as-is;
  - states that #8763 already removed the SIGPIPE at the six named sites. This PR adds the abort semantics, the single scorer and the pins. The one live SIGPIPE site it fixes is betterstack's `attributed()`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (test harness scorer and its drift guard; no user-facing, legal, marketing, finance, sales, support or operations surface).

## Test Scenarios

- Given the S1 fixture (needle on line 2, ≥ 1 MiB of failure lines after it), when `mutation_scorer_failed_on "$FX" '^  FAIL' SELFTEST-TARGET` runs, then it returns 0 on every run, while the pre-fix piped shape returns 141.
- Given a log path that does not exist, when a battery's scorer runs, then the battery prints `HARNESS ABORT: mutation_scorer: …` and exits 2 instead of printing MISROUTED.
- Given `attributed` is called with no anchors, when betterstack's `expect_red` scores, then the battery aborts with exit 2 instead of reporting `ok`.
- Given `www-apex-canonicalizer`'s rows that expect `--branch` / `--project-name`, when they run, then they score KILLED (option-shaped needles are literal).
- Given an apex RED row written with expectation `-`, when it scores, then the row fails with "a RED row must name the case it expects" instead of skipping attribution.
- Given parity's `_g2_json_row` green rows (anchor `""`), when they run, then the lib is never called (the `[[ "$want" == red ]] &&` short-circuit holds) and they stay GREEN.
- Regression: `bash apps/web-platform/infra/{apex-single-node-replace,ssl-full-mitigation,www-apex-canonicalizer,web-host-provisioner-parity,cloud-init-inngest-zot-pull}-mutation.test.sh` and `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` each exit 0 with unchanged totals.
- Guard: `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0; with matrix row 1 applied it exits 1 naming the reverted line.

## Implementation Phases

1. **RED first** (`cq-write-failing-tests-before`): write `mutation-scorer.test.sh` (fails: lib absent) and the guard's #8855 pass (fails: 7 scorer-shape hits, lib untracked). Run both; record the failures.
2. **Lib**: write `mutation-scorer.sh` to the contract above; self-test GREEN; shellcheck clean.
3. **Consumers**: convert in this order, running each battery after its edit — betterstack (the live SIGPIPE site), ssl, www (+ comment rewrite + display fix in both), apex, parity (three sites), zot-pull wrapper.
4. **Guard GREEN**: run `grep-q-pipe-guard.test.sh`; then execute the AC7 matrix rows in a detached worktree (`git worktree add --detach <scratch> HEAD`), never in the live worktree while a battery is running (#8664 learning, session-error 8). Remove the scratch worktree after.
5. **Verify**: AC2–AC6 and AC8 commands; commit; `run-registered-suites.sh --list` for AC3 (needs the commit, since derivation reads `git ls-tree HEAD`).

## Files to Create

- `apps/web-platform/infra/lib/mutation-scorer.sh`
- `apps/web-platform/infra/lib/mutation-scorer.test.sh`

## Files to Edit

- `apps/web-platform/infra/apex-single-node-replace-mutation.test.sh`
- `apps/web-platform/infra/ssl-full-mitigation-mutation.test.sh`
- `apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh`
- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
- `.claude/hooks/grep-q-pipe-guard.test.sh`

## Open Code-Review Overlap

1 open code-review issue mentions a planned file:

- #7942 (two `*.mutation.sh` batteries in `plugins/soleur/test/` run in no gate) — **Acknowledge.** It names `apex-single-node-replace-mutation.test.sh` only as an example of the correct `*-mutation.test.sh` naming; its work is in `plugins/soleur/test/` and is untouched here.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Inline a `failed_on` copy in each battery (the issue's primary remedy) | Six copies of one contract is how this class spread; the issue's own follow-up comment makes the lib the default at ≥ 3 files |
| Leave the six `grep -c` sites alone (SIGPIPE already fixed) and only fix betterstack | Misses P2/P3 (abort semantics) and leaves the named-file pin non-discriminating; the issue asks for the capture-once shape explicitly |
| Put the scorer-shape pattern in the lib test instead of the grep-q guard | Two member lists that can drift; one list in the guard, next to the existing named-file pins, is the single place pipe-shape pins live |
| Widen the guard to `apps/web-platform/**/*mutation*.test.sh` | Forbidden by the guard's own scope note (comments and deliberate demonstrations match a text search) |
| Convert the 19 `\| head -1` reads in the guard file | #8871 choice 2 stays accepted: single short writes cannot SIGPIPE |
| Lib returns 2 and every caller branches three ways (0 / 1 / ≥2 → `die`) instead of the lib exiting | Seven call sites each re-implementing the abort is the duplication P6 removes; every direct site runs in the battery's shell and zot-pull's subshell callers already `\|\| die` |
| Guard-side consumer-contract pins: routing presence (≥ 1 lib call per battery), a same-shell pin, a presence pin on a lib-test line (plan v1) | Cut at plan review (DHH + simplicity, CTO concurring). An inline correct capture still satisfies P1–P4; a subshell-wrapped call still fails the row loudly under `pipefail` (wrong label only); the lib test is registered by presence and pinned by its own count. None is about piped `grep`, so none belongs in this guard |
| Pin each battery's lib-call count to its exact current number of sites (advisor suggestion) | A per-file snapshot reds on a legitimate refactor and still cannot see an inline scorer that bypasses the lib |
| A standing positive control (the old piped shape run on the S1 fixture) inside the lib test (plan v1 S1-PC) | Tests grep, not the lib, and needs an opt-out marker in the pipe guard; run once at implementation as Guard 1 matrix row 1 instead (AC7) |

No deferrals are created by this plan.

## Dependencies & Risks

- **Risk: a consumer is sourced from a sandbox copy.** Mitigation: source from `SCRIPT_DIR`/`REAL_INFRA`/`ROOT`, which all resolve to the checkout, before any sandbox is created.
- **Risk: exit 2 inside a subshell becomes a verdict.** The five direct sites run in the battery's shell; zot-pull's three subshell callers already treat rc 2 as an abort (`|| die`, or an explicit rc-2 check). The lib header states the rule. A future subshell-wrapped call would still fail its row loudly under `pipefail` (rc 2 is non-zero), only with the MISROUTED label instead of HARNESS ABORT. The lib self-test runs its abort rows inside `( … )` deliberately and checks rc 2.
- **Risk: parity battery runtime.** It is the longest (1,296 lines); run it in the background and poll, per `hr-never-run-commands-with-unbounded-output`, redirecting output to a file under `/var/tmp`, not the worktree.
- No external dependency; no new tool.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above (`none`, with the sensitive-path scope-out, since `apps/*/infra/` matches preflight's `SENSITIVE_PATH_RE`).
- `run-registered-suites.sh --list` derives from `git ls-tree HEAD` but also prints an untracked-file report that names on-disk suites, so a loose grep passes before the commit. Use AC3's exact-line form after the commit.
- Do not re-word `failed_on "$SELFTEST_LOG" SELFTEST-TARGET` in zot-pull — the #8664 guard pass pins that exact string.
- Every `rc 1` row in the self-test (S2, S5, S6, S14-absent) must sit on a fixture that also has an `rc 0` row, or assert rc is exactly `1` and not `2` — an "expect not-found" row otherwise passes on an unreadable file (sharp-edge from #8644).
- Any new guard check must be a count comparison with the ERE compile pre-check, never `! grep -q`: a negated grep folds rc 2 into a pass (#8807). Do not copy the existing #8664 presence line (`if ! grep -qF …`) as a template.
- Inside the `grep -E` ERE, alternation is a bare `|`. A markdown table forces `\|`, which in `grep -E` is a literal pipe and matches nothing; the conversion snippets are in a code block for that reason.
- `discoverability_test.command` must contain none of `| ; & < > $` or a backtick (preflight Check 10's shell-active reject); the chosen `bash apps/web-platform/infra/lib/mutation-scorer.test.sh` has none.
- No file in `FILES_8855` may contain the forbidden piped shape, including the lib test, which is why the positive control runs once at implementation (AC7) rather than living in a file.

## Review Addendum — 2026-09-27 (PR #9033 review panel)

Corrections to this plan, recorded here rather than edited in place:

- §Premise Validation says #8763 rewrote `| grep -qF --` in "18 infra test files". `git show 50ae36eff7` shows **13** files (27 lines).
- §Guard says the cut consumer-contract checks each guarded a regression that "fails closed already". Measured false: replacing a battery's call with `if false` left it `OK: 20/20` with a row pointing at a needle the guard never prints. The pin is reinstated as a behavioural wire suite, `apps/web-platform/infra/lib/mutation-scorer-consumers.test.sh`. It runs every battery that sources the lib with `MUTATION_SCORER_PROBE` set and requires each one to reach the scorer. The pipe guard also derives the sourcing files and fails on any it does not pin.
- §Guard item 6 says "7 real pre-PR site spellings". The seven sites use **6** distinct spellings.
- "The one site that still has the live SIGPIPE flake is betterstack" holds for web-platform. Two more piped `grep -q` scorers exist in `plugins/` and `scripts/` (#7005).
- zot-pull (a lib consumer) is pinned in FILES_8664. That pass now also runs `PATTERN_PIPED_SCORER`.
- The lib now refuses a needle containing a newline and reads logs with `grep -a`. The self-test gained S5b (first needle missing), S15 (option-shaped needle), S16a/b (the escaped `\[FAIL\]` ERE), S17 (newline needle) and S18 (NUL byte), and dropped S5a (a duplicate of S1). Its instrument check now drives `want_rc`/`want_abort` with inputs that must fail.
