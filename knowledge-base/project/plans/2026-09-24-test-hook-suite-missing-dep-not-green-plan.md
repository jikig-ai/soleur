---
title: "test: hook suites that cannot run report UNRESOLVED (exit 3), not green"
type: fix
date: 2026-09-24
slug: test-hook-suite-missing-dep-not-green
branch: feat-one-shot-8616-hook-suite-missing-dep-unresolved
issue: 8616
closes: 8616
lane: procedural
brand_survival_threshold: none
---

# test: hook suites that cannot run report UNRESOLVED (exit 3), not green

## Enhancement Summary

**Deepened on:** 2026-09-24. The lead asked for a small fan-out, so it was kept to two agents.

- **Agents used:**
  - a read-only realism pass: verify-the-negative, plus a post-edit self-audit (sonnet);
  - `soleur:engineering:review:test-design-reviewer`.
- **Skipped on purpose:** the full-roster skill and agent sweep. The plan-review panel (DHH, Kieran,
  code-simplicity, CTO) plus the Step 4.5 advisor had already reviewed this plan, and the lead asked
  for small deepen fan-out.
- **Gates:**
  - 4.6 User-Brand Impact: pass (threshold `none`, no sensitive path).
  - 4.7 Observability: the section is **added** in this pass. The Files to Edit are `.sh`, so the plan
    is not pure-docs. `discoverability_test.command` passes `probe-verb-gate.sh` with rc 0.
  - 4.8 PAT: no match.
  - 4.9 UI: not applicable.
  - 4.10 Encryption: not applicable.
  - 4.11 Guard Contract: `lint-guard-contract.py` is green and the assembly is structural (derived
    roots and population).
  - 4.5 / 4.55: no trigger.

### Key improvements

1. **The realism pass confirmed every negative and absolute claim against the tree.** That includes
   the 40 pairs, 22 jq skip-exit-0 suites and 11 git suites; `counters_of`'s two spellings; and
   `--print-suite-globs` being free of side effects. It found no stale v1 references outside the
   Cut List and Alternatives.
2. **Pairs now run with `CI`/`GITHUB_ACTIONS` unset** (row M11). A guard that branches on CI would
   otherwise pass in the one place the suite runs.
3. **Whole-suite guards must exit exactly 3, read from the source; arm-level guards must exit
   non-zero** (rows M12/M13). This closes "print the line, drop the exit".
4. **Tighter fixtures and farm:**
   - fixtures R-c (one-line `which`) and R-d (bare `exit`);
   - every fixture must derive exactly one pair through the real toggle;
   - the sweep now also matches a bare `exit`;
   - the farm links only absolute, existing PATH directories;
   - mutation rows run against a scratch copy, after a pristine control run.

### New considerations

- No other suite or script parses hook-suite output for `SKIP: jq missing` or for parity's `skipped`
  count (realism pass). The message change is therefore safe.

## Overview

The hook test suites under `.claude/hooks/` open with a dependency guard that prints a skip line and
exits 0 when `jq` is absent. Several also guard `git`, `perl`, `realpath` or `python3` the same way.
Exit 0 is the runner's pass code, so a host without the dependency records every one of those suites
as passing while asserting nothing.

This plan does three things:

1. It settles the verdict for a suite that cannot run. A missing **tool** exits **3 (UNRESOLVED)**. A
   missing **file under test** exits **1 (FAIL)**. Both are measured below to be not-green in
   `scripts/test-all.sh` and in CI.
2. It applies that verdict to every dependency guard in `.claude/hooks/*.test.sh` and
   `.claude/hooks/lib/*.test.sh`. That covers 40 (suite, tool) pairs across 25 files, plus 2 guards
   that skip when the file under test is missing.
3. It adds one regression suite, `.claude/hooks/hook-suite-dep-unresolved.test.sh`. For each guarded
   (suite, tool) pair, it runs the suite on a PATH with that tool removed. It requires a non-zero exit
   and the canonical `UNRESOLVED:` line. A static sweep also rejects any remaining `SKIP … exit 0` form, so
   the old pattern cannot come back.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured 2026-09-24) | Plan response |
|---|---|---|
| "Most `.claude/hooks/*.test.sh` suites open with `…SKIP: jq missing; exit 0`" | 22 of 52 hook suites exit 0 at a jq guard. Measured by running every suite on a jq-less PATH: 30 exit 0, of which 22 print only `SKIP: jq missing`/`SKIP: jq not on PATH` (or a `0/0` results line). The other 8 are genuinely jq-free (e.g. `lib/freeze-lock.test.sh` 13/13, `ship-runbook-ssh-gate.test.sh` 24/24), with one partial case: `hookeventname-coverage.test.sh` skips its jq arms and exits 0 on the remaining ones. | Convert all 22 plus the partial case. Leave the jq-free suites alone. Their exit 0 is a real verdict. |
| "several also `command -v git … \|\| exit 0` with no results line" | 11 suites guard git. On a git-less PATH all 11 print `SKIP: git missing` (so there *is* a skip record) and exit 0 with no `=== Results` line. | Convert all 11. The issue's point stands: there is no verdict line and exit 0 reads as a pass. |
| "`test-all.sh` … prints `[UNRESOLVED]` rather than `[FAIL]` for [exit 3]" | Measured: `suite_exit_class 3` → `failed`. `run_suite` prints `[FAIL] <label>` and counts the suite into `failed`, so the top-level runner exits 1. `[KILLED] … UNRESOLVED` applies only to signal-shaped rc 129..192. The issue's reading describes the *top-level* exit contract (the runner's own exit 3), not how a suite's rc 3 is classified. | Adopt 3 anyway. It is still not-green end to end, which is the property the issue asks for. The suite's own `UNRESOLVED:` line appears in the log directly above `[FAIL]`. `test-all.sh` is **not** edited (see Alternatives). |
| Implicit: jq is the only tool | Guard population by tool: jq 25 files (22 skip-exit-0, `hookeventname-coverage` partial, and `grep-rewrite`/`settings-hook-exec-bit`, which already exit 1), git 11, python3 2 (`security_reminder_hook` whole-suite; `pre-merge-rebase-parity` two per-arm skips), perl 1, realpath 1. | Convert all 40 pairs with one canonical form, and have the regression suite derive the population rather than list it. |

## Problem Statement

The repo already has a name for "could not measure": `UNRESOLVED`, exit 3 (`scripts/test-all.sh`
§EXIT CONTRACT). The hook suites predate it and use exit 0. On a jq-less host the scripts shard would
report `[ok]` for 22 guard suites that asserted nothing. `.claude/hooks/*.sh` (the hooks themselves)
call `jq` directly, so on that host the guardrails are also disarmed. The suites that exist to show
the guards work would therefore read green on exactly the machine where the guards fail.

`hook-input-contract.test.sh` kept its skip on purpose (#7190 item 5), giving four reasons (see
its comment block). This plan reverses that decision, and the reasons are answered here:

- **(a) "CI has jq, so a hard-fail is unreachable there."** True, and CI behavior does not change.
  The change targets local and non-CI runs, where "not measured" currently reads as green.
- **(b) "If CI lost jq, this suite is struck along with everything else."** Not measured. The 15
  unguarded jq-using suites do already go red without jq (rc 1/127), so a jq-less run is not
  silently green today. But the 22 guarded suites read `[ok]` inside that red run. That misstates
  which suites measured anything.
- **(c) "It turns a green `test-all.sh` red on a jq-less dev machine for an environment reason, not a
  defect."** The verdict chosen is **UNRESOLVED (3)**, not FAIL. The suite says in its own output
  that the cause is the environment. `run_suite` still counts it not-green, which is correct: the
  hooks cannot run on that machine either.
- **(d) "False comfort while 21 sibling suites still skip."** This plan converts all of them together,
  and the regression suite stops any from drifting back.

## Proposed Solution

### The taxonomy (decided, measured)

| Condition | Exit | Canonical line | Why |
|---|---|---|---|
| A **tool** the whole suite needs is not on PATH (`jq`, `git`, `perl`, `realpath`, `python3`) | **3** | `UNRESOLVED: <tool> missing — this suite asserted nothing; install <tool>` | This is the repo's term for "not measured and not green". The environment is at fault, not the diff. Under ADR-188 §"who owns the missing precondition", the runner is expected to supply these tools, so the result must never be green. The `install <tool>` suffix tells the developer what to do (CTO review). |
| The **file under test** is missing (`context-reviewed-gate.test.sh` `$HOOK`, `pre-merge-auto-close-scan.test.sh` `$SCANNER`) | **1** | `FAIL: <path> not found — …` | The repo owns this file, so its absence is a defect in the tree, not in the environment. Precedent: `session-rules-loader.test.sh` already exits 1 with `FAIL: $HOOK not executable or missing`. ADR-188: a missing precondition the repo itself owns fails, always. |
| Some arms ran, and **one arm** hit a missing tool | **non-zero** (1 in both current cases) | `UNRESOLVED: <tool> missing — <arm> not run` | The property is not-green. A partial-arm suite keeps its existing exit machinery: `hookeventname-coverage` sets `fail=1`, and `pre-merge-rebase-parity`'s case floor already exits 1 without python3 (measured). The per-arm line carries the cause. The regression suite asserts `rc != 0` plus that line, so it reddens if either one ever exits 0. |

**What exit 3 buys, stated precisely.** `run_suite` renders rc 1 and rc 3 identically (`[FAIL]`,
counted into `failed`), so upstream the code number carries a **name**, not a behavior. Its value is
at direct invocation, where `bash <suite>; echo $?` separates "could not run" from "an assertion
failed". The issue's case for 3 assumed `[UNRESOLVED]` rendering. That premise was measured false, and
3 is kept on the naming argument alone.

**How exit 3 is surfaced (measured, not assumed):**

- `suite_exit_class 3` → `failed`, found by extracting the function from `scripts/test-all.sh` and
  evaluating it. Full results: rc 0→ok, 1→failed, 3→failed, 97→failed, 130→killed, 143→killed.
- `run_suite` → `[FAIL] <label> (<ms>)` on stderr, `failed += 1`, timing row `FAIL`. The suite's own
  output, which includes the `UNRESOLVED:` line, streams after the `--- <label> ---` header, so the
  cause sits directly above the `[FAIL]`.
- Top-level `test-all.sh` → `failed > 0` → **exit 1** (the failure-dominates arm).
- `ci.yml`: the hook suites run in the `scripts` group (`bash scripts/test-all.sh scripts`, the
  `test-scripts` shard on ubuntu-latest, which ships jq, git, perl, realpath and python3). A shard exit
  of 1 fails the job, and the aggregate `test` job reads `needs.<shard>.result == failure`. The result
  is not-green end to end.
- The runner header's warning ("3 is a TOP-LEVEL contract only: a nested runner returning 3 into
  run_suite classifies as a plain FAIL") is about **nested runners**. There, rc 3 means "some of my
  children were killed", and collapsing it to FAIL would mislead. The hook suites are **leaf** suites.
  Their rc 3 collapsing to FAIL loses nothing that exists today, because today these runs report
  `[ok]`.

### The canonical guard forms

One-liner (18 files use this shape; `grep-rewrite` also moves to it):

```bash
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
```

Multi-line (`security_reminder_hook`, `session-rules-loader`, `settings-hook-exec-bit`,
`hook-input-contract`): keep each suite's structure, i.e. `if ! command -v …; then … fi`, and the
`summary`-before-exit call in `hook-input-contract`. Change only the message (to the `UNRESOLVED:`
form) and the exit code (to 3).

Partial-arm:

- **`hookeventname-coverage`**: the jq branch prints the per-arm `UNRESOLVED:` line and sets
  `fail=1`. That is one added assignment. No new variable and no epilogue change, so the `set -u`
  trap Kieran found in the v1 epilogue does not arise.
- **`pre-merge-rebase-parity`**: messages only. `skip()` prints `echo "  UNRESOLVED: $1"` instead of
  `echo "  SKIP: $1"`. The `SKIPPED` counter, the results line and the floor block all stay byte-identical.

### The regression suite — `.claude/hooks/hook-suite-dep-unresolved.test.sh`

The existing `.claude/hooks/*.test.sh` entry in `SUITE_GLOBS` picks this suite up, so no registration
edit is needed in `test-all.sh`. `scripts/lint-orphan-test-suites.sh` reports it as covered because it
asks the runner for its globs.

1. **Roots come from the runner, not a copy.** Take the scan roots from
   `bash scripts/test-all.sh --print-suite-globs`, keeping the entries under `.claude/hooks/`. That flag
   answers and exits before any lock or side effect (see `--print-suite-globs` in `test-all.sh`). A
   hook-suite directory added to `SUITE_GLOBS` later is then scanned automatically, which is row M10.
2. **Population (derived, never listed).** Scan every matched file except this suite for guard-shaped
   lines: `^[[:space:]]*(if[[:space:]]+![[:space:]]*)?(command -v|which) <tool>`, keeping only the
   lines that also contain `||` or open with `if !`. Collect the distinct `(file, tool)` pairs.
   - Measured on the current tree: **40 pairs** (jq 25, git 11, python3 2, perl 1, realpath 1).
   - `which` matches nothing today. It stays because `which jq || exit 0` is the likeliest rewrite of a
     guard that went red (the sharp-edges rule "a fail-closed change is not done until its most natural
     repair is also refused"). `type -P` and `hash` were cut at review.
3. **Anti-vacuity floor, in the exact shape `scripts/guard-vacuity-floor.test.sh` can mutate.**
   `.claude/hooks/` is a `DEFERRED_DIRS` member, so this new floor-bearing file needs a `PROMOTED_FILES`
   entry, as every sibling has. That guard's `counters_of` recognises only these literal spellings, so
   use them exactly:
   - a counter incremented at the **call site**, once per pair checked, spelled
     `pairs_checked=$((pairs_checked + 1))`;
   - `MIN_PAIRS=40` as a plain literal on its own line, with no `$(`, directly above the floor;
   - the floor as a multi-line `if [[ "$pairs_checked" -lt "$MIN_PAIRS" ]]; then … fi`, with a
     standalone `fi`;
   - reported by `printf '[FATAL] anti-vacuity floor: …' >&2; exit 1`, never through pass()/fail().

   The FATAL text tells the reader what to do (CTO review): *"found N pairs < MIN_PAIRS=40. If you
   deliberately removed a guard or a guarded suite, lower MIN_PAIRS to N here and say why in the PR;
   otherwise the population regex or root derivation broke."* A green run prints `N pairs (floor 40)`,
   so a stale floor is visible in review.
4. **One PATH farm, toggled per tool.**
   - Build it as `for d in <PATH entries, in order>; do ln -s "$d"/* "$farm"/ 2>/dev/null || true; done`,
     linking **only absolute, existing directories**. A missing entry would otherwise leave a literal `*`
     link, and a relative entry such as `.` produces dangling links that can shadow a later directory's
     real tool (test-design P2-6). Moving a tool's link aside is a no-op when the host lacks that tool,
     e.g. `realpath` on macOS before 13.
     Without `-f`, `ln` keeps the first link for a given name, which is the shell's own resolution order,
     and it uses one process per directory instead of about 3,400 forks. This matters on macOS (Kieran
     P2-11).
   - For each tool, move its link aside, run that tool's pairs, then restore it.
   - Run the suites under `"$BASH"` (the running interpreter), not a PATH lookup of `bash`, so macOS
     cannot silently switch to `/bin/bash` 3.2 (Kieran P2-9).
   - **No timeout wrapper.** Every guard is measured to exit in under 1 s, and a pair that fails to reach
     its guard runs to completion, which is finite and bounded by the CI job's `timeout-minutes`. Cutting
     the wrapper also removes the `timeout`/`gtimeout` portability problem. Each run gets `</dev/null`,
     so a stray stdin read cannot block.
5. **Behavioral check per pair.** Run
   `env -u CI -u GITHUB_ACTIONS PATH=$farm "$BASH" <suite> </dev/null >"$ROOT/out.$n" 2>&1`.
   Output goes to a file, not `$(...)`, so no descendant can hold a pipe open. `CI` and
   `GITHUB_ACTIONS` are unset because a guard that branches on `CI` would otherwise pass in CI, where
   this suite runs. That would bring back the ADR-188 local-skip shape that Alternatives rejects
   (test-design P1-1, row M11). Require **both**:
   - `rc != 0`: the property the issue names, not-green. The rc is stricter for a **whole-suite**
     guard, meaning one whose guard block (the `{ … }` on the guard line, or the `if ! … fi`) contains
     an `exit`. Those must return exactly **rc == 3**. Guards without an `exit` (the
     `hookeventname-coverage` `if … elif` branch and the parity `if ! command -v python3` arm) keep
     `rc != 0`. The
     class is read from the source, not from a list. Without the stricter rule, "print the line but
     drop the `exit 3`" (rc 1 from the failing assertions that follow) and "`exit 3` → `exit 1`" would
     both stay green (test-design P1-2, rows M12/M13).
   - A line matching `^[[:space:]]*UNRESOLVED: <tool> missing`. This proves the verdict came from the
     guard. A suite that uses the tool before its guard dies with rc 127 or 1 and never prints the line,
     so this check also enforces guard-before-first-use, which the advisor raised. Measured today: every
     one of the 40 guards is reached first.

   A RED pair prints the rc, the suite's last output line, and the canonical one-liner with the tool
   filled in, so the fix can be copied (CTO review).
6. **Static sweep (layer B).** Report any non-comment line whose **string literal** contains the
   case-sensitive token `SKIP` when that line, or the next non-blank line before `fi`/`}`/`else`, exits
   with status 0. The match is `exit([[:space:]]+0)?[[:space:]]*(;|}|$)`, so a bare `exit` also counts
   (test-design P2-4).
   - It covers the two file-under-test arms, which the behavioral check cannot reach without deleting
     tracked files.
   - It deliberately misses `memory-backstop.test.sh`'s `echo "$_skipnote"` + `exit 0`, because the
     token is inside a variable, not a literal. That arm is out of scope (see Non-Goals) and gets a
     must-PASS fixture.
   - The suite skips itself by path.
7. **Checker self-test.** It doubles as the instrument self-test the `PROMOTED_FILES` entry expects.
   Fixtures are built from string pieces (`s=SK; s="${s}IP"`), so this suite's own body never contains
   the patterns it hunts (Kieran P1-2). They are written to `$ROOT` and put through the **same**
   `derive_pairs` / `check_pair` / `scan_skip_exit0` functions:
   - **R-a** (must be RED, caught **only** by the rc check): prints `UNRESOLVED: jq missing`, then `exit 0`.
   - **R-b** (must be RED, caught **only** by the line check): prints `SKIP: jq missing`, then `exit 3`.
   - **R-c** (must be RED under both the pair check and the sweep): the one-liner
     `which jq >/dev/null || { echo "SKIP"; exit 0; }`.
   - **R-d** (must be RED under the sweep): `echo "SKIP: x"; exit` (a bare `exit`).
   - **P-a** (must PASS through derivation and check): a multi-line
     `if ! command -v jq  >/dev/null 2>&1; then` / `echo "UNRESOLVED: jq missing — x"` / `exit 3` / `fi`
     with irregular spacing.
   - **P-b** (the sweep must PASS): the `grep-rewrite` shape `echo "SKIP: could not read peak RSS"`
     with no exit.
   - **P-c** (the sweep must PASS): the `memory-backstop` shape `echo "$_skipnote"` followed by `exit 0`.

   Each fixture carries a real guard line and runs through the **same** farm toggle. It must derive
   exactly 1 pair before its verdict counts, which also proves the toggle really removes the tool
   (test-design P2-3). If the must-RED and must-PASS verdicts do not both appear, or if pass() and
   fail() did not each move, the suite exits 2 before any real pair runs.
8. **Hygiene.**
   - Bash 3.2 compatible: no `mapfile`, `declare -A` or `${var,,}`.
   - Self path via `cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`, never `realpath`, which is one
     of the tools under test and is missing before macOS 13 (Kieran P2-10).
   - One owning `trap 'rm -rf "$ROOT"' EXIT`, set before any `source`. This is ADR-129 rule (c),
     enforced by `scripts/lint-trap-tempfile-ownership.py`.
   - Nothing is written outside `$ROOT`, and the per-pair runs do not write to the repo. Measured:
     `git status --porcelain` was unchanged after running all 52 suites on jq-less and git-less PATHs.
   - No `| grep -q` inside pipelines (`grep-q-pipe-guard.test.sh`).
   - The header says: "editing this checker? run the Guard Contract rows M1–M13, H1, H1b, H2 and H3 in the plan"
     (CTO review).

Measured cost: every guarded suite exits at its guard in under 1 s on a PATH that lacks the tool. The
per-directory `ln` build is one process per PATH entry. The added time in the `test-scripts` shard is
estimated at ≤ 15 s.

## Files to Edit

Whole-suite tool guards, one-liner: `exit 0` becomes the canonical UNRESOLVED line and `exit 3`
(tools in parentheses):

- `.claude/hooks/background-poll-prefer-monitor.test.sh` (jq)
- `.claude/hooks/cla-signed-author-gate.test.sh` (jq, git)
- `.claude/hooks/context-reviewed-gate.test.sh` (jq, git, perl). Also the `$HOOK` not-present arm
  changes to `FAIL:`/`exit 1`.
- `.claude/hooks/doppler-secrets-delete-redirect.test.sh` (jq)
- `.claude/hooks/durable-reminder-prefer-inngest.test.sh` (jq)
- `.claude/hooks/follow-through-directive-gate.test.sh` (jq, realpath)
- `.claude/hooks/guardrails.test.sh` (jq)
- `.claude/hooks/iac-plan-write-guard.test.sh` (jq)
- `.claude/hooks/new-scheduled-cron-prefer-inngest.test.sh` (jq)
- `.claude/hooks/pencil-collapse-guard.test.sh` (jq, git)
- `.claude/hooks/post-dispatch-watch-gate.test.sh` (jq, git)
- `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (jq)
- `.claude/hooks/pre-merge-auto-close-scan.test.sh` (jq, git). Also the `$SCANNER` not-found arm
  changes to `FAIL:`/`exit 1`.
- `.claude/hooks/pre-merge-rebase-headless.test.sh` (jq, git)
- `.claude/hooks/pre-merge-rebase.test.sh` (jq, git)
- `.claude/hooks/prod-write-defer-gate.test.sh` (jq)
- `.claude/hooks/ship-soak-followthrough-gate.test.sh` (jq, git)
- `.claude/hooks/ship-unpushed-commits-gate.test.sh` (jq, git)
- `.claude/hooks/grep-rewrite.test.sh` (jq): currently `FAIL … exit 1`. Move it to the canonical line
  and `exit 3`. Its comment's point, "a precondition, not a skip", still holds.

Whole-suite tool guards, multi-line:

- `.claude/hooks/security_reminder_hook.test.sh` (python3, jq). Also correct the "Preflight: skip with
  exit 0" comment.
- `.claude/hooks/session-rules-loader.test.sh` (jq, git)
- `.claude/hooks/settings-hook-exec-bit.test.sh` (jq): `fail …; exit 1` becomes the UNRESOLVED line and
  `exit 3`. Keep the "Fail, do not skip" rationale, reworded to "not-green (3), never skip".
- `.claude/hooks/hook-input-contract.test.sh` (jq): `summary; exit 0` becomes `summary; exit 3`, and the
  SKIP line is reworded to UNRESOLVED. **Rewrite the #7190-item-5 rationale block** so it records the
  reversal under #8616 and answers reasons (a) to (d) as in Problem Statement. Keep the `summary`
  helper; it is still printed on every exit path.

Partial-arm tool guards:

- `.claude/hooks/hookeventname-coverage.test.sh` (jq): the jq branch prints
  `UNRESOLVED: jq missing — registration/exec-bit/single-rewriter gates not run; install jq` and sets
  `fail=1`. `fail=0` already exists near the top of the file, and `exit "$fail"` is unchanged.
- `.claude/hooks/pre-merge-rebase-parity.test.sh`:
  - The jq guard's `exit 0` becomes `exit 3`, and its line keeps the `=== Results …` echo.
  - The git guard moves to the canonical line and `exit 3`.
  - `skip()` prints `echo "  UNRESOLVED: $1"` instead of `echo "  SKIP: $1"`.
  - Arm messages:
    - The `[[ -z "$SURROGATE_PAYLOAD" ]]` arm becomes `surrogate payload not generated (python3 missing
      or failed) — unreadable-envelope case not run`. It is not a python3 guard, and it fires on a
      python3 *error* too (Kieran P2-6).
    - The `if ! command -v python3` arm becomes `python3 missing — SIGPIPE padding-bypass case not run`.
  - No counter rename, no results-line change, no epilogue change. The floor block stays
    byte-identical, which matters because `scripts/guard-vacuity-floor.test.sh` slices exactly that
    block.
  - Measured without python3: `10/10 passed, 2 skipped`, then `FATAL anti-vacuity … floor is 12`, rc 1.
    That is not-green, and the regression suite's `rc != 0` + line check pins it.

Meta-guard ledger:

- `scripts/guard-vacuity-floor.test.sh`: add `\.claude/hooks/hook-suite-dep-unresolved\.test\.sh` to
  `PROMOTED_FILES`, with a comment entry in the same form as the siblings. The entry covers:
  - the deferred directory;
  - the 47 → 48 growth that would redden ARM 5c;
  - "PROMOTED, not by raising MAX_DEFERRED";
  - why the floor qualifies: the literal `MIN_PAIRS=40` directly above the `if`, the
    `pairs_checked=$((pairs_checked + 1))` call-site counter, `printf` + `exit 1`, and the fixture
    self-test that moves pass() and fail().

  Run that suite before and after the change and record the ledger count it reports. Do not infer it.

## Files to Create

- `.claude/hooks/hook-suite-dep-unresolved.test.sh`: the regression suite described above. Mode
  100755, to match its siblings. Its header comment is the **single home** for the taxonomy table and
  the measured `run_suite` classification, and each converted guard's message is self-describing.

## Non-Goals / Scope Boundary

- **`scripts/test-all.sh` is not edited.** It already surfaces rc 3 as not-green (measured). See
  Alternatives.
- **`git-commit-secret-scan.test.sh` gitleaks arms are acknowledged, not changed.** ADR-188 and #8266
  deliberately made "gitleaks unrunnable" a local SKIP and a CI FAIL: an unpinned mise shim is a
  common local state, and the suite pins that contract with its own T19 truth table. That arm is not
  guard-shaped (`gl_probe`), so neither the population nor the static sweep matches it. Reopening it
  would be an ADR-188 amendment, not part of this taxonomy change.
- **The 15 unguarded jq-using hook suites** (e.g. `brand-hex-commit-gate`, `incidents`, `no-memory-write`)
  already exit 1 or 127 without jq (measured), so they are not-green today. Adding a guard to each would
  improve the message, not the verdict, so it is not done here.
- **The live arms of `memory-backstop.test.sh`** print `SKIP: no user systemd bus …` through a
  variable and exit 0. A user systemd bus is a precondition nobody owns (headless CI, containers),
  which is ADR-188's "counted skip" class, and the suite already counts the skip and prints it. It is
  not a tool guard. It stays out of scope, and fixture P-c pins that the static sweep does not
  false-flag it (Kieran P1-3).
- **`hook-tool-kind.test.sh`** handles a missing python3 with a positive `if command -v python3 … else
  fail` arm, which is already not-green (rc 1, measured). It is not guard-shaped and is left alone.
- **The same idiom outside `.claude/hooks/`** (scope report only). A one-line-shape grep finds about 13
  tracked `*.test.sh` files: `scripts/*.test.sh` (5), `scripts/lib/` (1), `plugins/soleur/test/` (2),
  `plugins/soleur/skills/*/test/` (2), `apps/web-platform/infra/` (2, which run under
  `infra-validation.yml` with ADR-188's own `_skip()` semantics), plus multi-line forms not counted.
  Tracked in #8773 (filed at plan time; see Deferral Tracking). It is not trivially the
  same fix: the infra suites carry ADR-188 CI/local semantics, and the others belong to different
  owners and shards.

## Alternative Approaches Considered

| Alternative | Verdict | Why |
|---|---|---|
| Exit **1** (FAIL) instead of 3 | Rejected | 1 claims an assertion failed, and none ran. That is the AP-021/ADR-166 mistake of naming an unmeasured cause. It also brings back hook-input-contract's objection (c), "red for an environment reason". 3 is the repo's term for "not measured, not green", and upstream it lands on the same not-green outcome. |
| ADR-188 shape: FAIL under `CI=true`, SKIP (exit 0) locally | Rejected | Local "could not measure" still reads green, which is exactly the defect #8616 names. ADR-188's local-skip carve-out is for a precondition **nobody** owns (a flaky apt archive) or a commonly-unrunnable pinned binary. jq, git, perl, realpath and python3 are expected on any runner that runs these suites, and the hooks themselves need them. |
| Teach `run_suite` to render rc 3 as `[UNRESOLVED]` (like the rc-97 `[TRIPWIRE]` arm) | Rejected, not deferred | The runner's header says 3 is a top-level contract. `suite_exit_class` has byte-identical parity with `.github/scripts/test/run-all.sh`, pinned by a dedicated suite. Monitors anchor on `^\[FAIL\]`. The suite's own `UNRESOLVED:` line, directly above `[FAIL]` in the log, already carries the attribution. The added value is cosmetic and the blast radius is the whole runner. |
| Carry the rule in `scripts/lint-orphan-test-suites.sh` (research suggestion) | Rejected | That lint's single concern is registration (is every `*.test.sh` run?). A dependency-guard rule there would widen to every `*.test.sh` repo-wide and force the out-of-scope directories into this PR. A static lint also cannot show the behavior the issue asks for ("a dependency-less environment produces a not-green verdict"). Only running the suite without the tool shows that. |
| A shared `require_tool` helper in `.claude/hooks/lib/` (the Step 4.5 advisor's first recommendation) | Rejected | The advisor gave three reasons, and each is already covered. **Drift in wording and exit code:** the behavioral check requires a non-zero rc and the anchored line for every pair, so a drifted guard is RED. **Guard-before-first-use ordering:** a suite that uses the tool before its guard dies without printing the line, which is RED (item 5). **Shapes the regex misses:** `which` is added to the population regex, and a helper would not remove the need for a regex anyway, because banning raw guards outside the helper is itself a regex over the same line shapes. Against that, a helper would make 25 suites source a new file, and it cannot serve the two partial-arm suites, whose verdict is decided by `fail=1` and a case floor. |
| Static lint only, no PATH-stripped runs (the DHH review's main cut) | Rejected, recorded in `decision-challenges.md` | The issue's third acceptance item is literally "a dependency-less environment produces a not-green verdict", and only running the suite without the tool shows that. The two partial-arm suites reach their verdict through `fail=1` and a case floor, which a line rule cannot see; row M4 exists because the parity verdict depends on its floor. Measured cost is seconds, because every guard exits in under 1 s. The review cuts that *were* taken shrink the suite a lot: no positive controls, no timeout wrapper, no separate instrument test, `type -P`/`hash` removed, and no partial-arm epilogue rewrites. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing a product user sees. For the operator, the
  worst case is a guard suite that reads green on a machine where its hook is disarmed. That is the
  current state, which this change removes. The opposite breakage is a guarded suite that now exits 3
  on a machine that *has* the tool. The regression suite and the CI scripts shard would show that
  immediately as `[FAIL]`.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The change
  is test-harness exit codes and one sandboxed suite (symlink farms under `mktemp -d`). It reads no
  credentials and writes nothing outside its tempdir.
- **Brand-survival threshold:** `none`
  - `threshold: none, reason:` the diff touches only `.claude/hooks/*.test.sh` test harnesses and adds
    one test. It touches no production, auth, data or infra path, and none of it matches the preflight
    sensitive-path regex.

## Observability

The change touches only test harnesses (`.claude/hooks/*.test.sh`, `scripts/guard-vacuity-floor.test.sh`). No
production process emits anything new. The observable surface is therefore CI and the suites' own
output. Sentry is not involved, because nothing here runs outside a test runner.

```yaml
liveness_signal:
  what: "test-scripts CI shard result (bash scripts/test-all.sh scripts), which runs the new suite and all 25 converted suites; the new suite prints 'N pairs (floor 40)' on every green run"
  cadence: "every push / pull_request (ci.yml) and every 6 hours on main (main-health-monitor.yml, dispatched by the Inngest cron cron-main-health-monitor)"
  alert_target: "the required aggregate CI check on the PR; on main, main-health-monitor.yml files a P1 tracking issue when the suite fails"
  configured_in: ".github/workflows/ci.yml (test-scripts shard), .github/workflows/main-health-monitor.yml, scripts/test-all.sh SUITE_GLOBS"
error_reporting:
  destination: "GitHub Actions job log for the test-scripts shard, plus the red required check; no Sentry (test harness, not a runtime)"
  fail_loud: "'[FAIL] .claude/hooks/hook-suite-dep-unresolved.test.sh' from run_suite, preceded by the pair's rc, last line and canonical one-liner, or by '[FATAL] anti-vacuity floor: found N pairs < MIN_PAIRS=40'"
failure_modes:
  - mode: "a hook suite's dependency guard regresses to exit 0 (the #8616 defect)"
    detection: "the new suite's per-pair check (rc != 0 plus an anchored UNRESOLVED line) goes RED in CI"
    alert_route: "red required CI check on the PR; P1 issue from main-health-monitor if it reaches main"
  - mode: "the population derivation silently shrinks (regex or root drift)"
    detection: "MIN_PAIRS=40 floor emits [FATAL] and exits 1"
    alert_route: "same as above"
  - mode: "the checker itself is neutered (always-pass)"
    detection: "fixture self-test (R-a/R-b must be RED, P-a..P-c must PASS) exits 2 before any real pair"
    alert_route: "same as above"
  - mode: "a developer machine lacks a guarded tool"
    detection: "the suite prints 'UNRESOLVED: <tool> missing ... install <tool>' directly above run_suite's [FAIL]"
    alert_route: "local test-all / lefthook pre-push output (intended not-green)"
logs:
  where: "GitHub Actions run logs for ci.yml and main-health-monitor.yml; local runs print to the terminal"
  retention: "GitHub Actions log retention for the repository (default 90 days)"
discoverability_test:
  command: "git grep -h -m1 -e 'UNRESOLVED: jq missing' -- .claude/hooks"
  expected_output: "UNRESOLVED: jq missing"
```

The probe reads the canonical guard line out of the tracked hook suites. It needs no credentials, uses no
suite-shaped path, and has no shell-active characters. Before this change it prints nothing (measured:
`git grep -h -m1 -e 'SKIP: jq missing' -- .claude/hooks` currently prints the old form). After this
change it prints the converted guard lines.

## Risks

- **A developer machine without jq now sees about 25 `[FAIL]` lines from `test-all.sh scripts`.**
  - The lefthook pre-push `test-all.sh --affected` will block a push whose diff selects hook suites.
  - This is intended. The same machine's hooks call `jq` and are disarmed.
  - Each `UNRESOLVED:` line ends `install <tool>`. The fix is installing the tool, not `--no-verify`.
    The new suite's header says so too (CTO review).
  - CI is unaffected: ubuntu-latest ships every guarded tool, and every converted suite passes there
    today.
- **A guard that is not the first statement to need its tool** would die before printing its
  `UNRESOLVED:` line and redden the new suite. Measured for all 40 pairs on 2026-09-24: every guard is
  reached first. If a later edit moves tool use above a guard, the new suite names the pair. That is a
  true positive.
- **The population regex can miss a guard.** The regex covers `command -v` and `which`. A guard in
  another spelling would escape the behavioral check, e.g. `[ -x "$(command -v jq)" ] || exit 0` or
  `jq --version || exit 0`. The static sweep still catches any spelling that pairs a literal `SKIP`
  with `exit 0`. What remains uncovered is an unlisted spelling that exits 0 with no SKIP literal. That
  gap is accepted and named here, not claimed as covered.
- **The regex is line-based, not a lexer, so it can also over-match.** Guard-shaped text inside a
  heredoc or a string in some *other* suite would enter the population as a false pair. That fails
  **closed**: the pair would lack the `UNRESOLVED:` line, go RED, and name the file:line. Today the
  census matches exactly the 40 real guards. The new suite's own fixtures are built from string pieces
  and it excludes itself.
- **`scripts/guard-vacuity-floor.test.sh` ledger.** The new floor-bearing file sits in a
  `DEFERRED_DIRS` member. Without the `PROMOTED_FILES` entry, ARM 5c goes red, the same trap #8570 hit
  with `pre-merge-rebase-parity.test.sh`. The entry is in Files to Edit. The floor's spellings follow
  `counters_of` exactly (Proposed Solution item 3), and running that suite is part of local
  verification.
- **`pre-merge-rebase-parity`'s python3 verdict depends on its case floor.** It is not-green without
  python3 only because 10 executed cases < `MIN_CASES=12`. If a later change adds enough non-python3
  cases to clear the floor, that suite would exit 0 without python3. The new suite would then redden
  the (parity, python3) pair, and the fix is a one-line `(( SKIPPED > 0 )) && exit 3` above the floor.
  That is the guard doing its job, not a defect in this plan.
- **Concurrent `test-all.sh` runs.** Each pair run reaches its guard and exits. Measured runs of all 52
  suites on stripped PATHs left `git status` unchanged. The farm lives under `mktemp -d` with one
  owning trap.

## Guard Contract

### Guard 1 — hook-suite dependency guards never report green

**Property.** No suite under the `.claude/hooks/` roots of `SUITE_GLOBS` that guards a tool exits 0
when that tool is absent from PATH, with or without `CI` set. Each such (suite, tool) pair exits
non-zero and prints a line matching `^\s*UNRESOLVED: <tool> missing`. When the guard block itself
contains an `exit`, the pair exits exactly 3. No hook suite pairs a literal `SKIP` message with `exit 0`.

**Assembly.** There are two chokepoints, and the guard covers both:

1. **Guard-shaped lines.** These are lines matching
   `^\s*(if\s+!\s*)?(command -v|which) <tool>` together with `||` or `if !`, in every file under the
   `.claude/hooks/` roots that `bash scripts/test-all.sh --print-suite-globs` returns.
   - A suite has no other way to declare a tool dependency that it checks.
   - The roots and the population are both **derived** on every run; neither is ever listed. The
     population size is floored at `MIN_PAIRS=40`, the measured value.
   - A pair's verdict comes from the suite's guard **and**, in the partial-arm suites, from its exit
     path. That is why the check runs each suite instead of reading it.
2. **Skip-message exit sites.** These are string literals containing `SKIP` whose line, or next line,
   is `exit 0`. This covers the arms that have no tool (the file-under-test arms) and any spelling
   outside chokepoint 1.

**Mutation matrix.** Each row is an edit that MUST turn the new suite RED. The implementer runs every
row once and records the RED line in the PR body.

| # | Edit | Expected RED |
|---|---|---|
| M1 | `guardrails.test.sh`: revert the jq guard to `…; exit 0; }` | pair (guardrails, jq): `rc=0` |
| M2 | `cla-signed-author-gate.test.sh`: keep the jq guard compliant and revert **only the second** guard (git) to `exit 0` | pair (cla-signed-author-gate, git) RED under the git toggle. A check that stops at the first compliant guard would miss this. |
| M3 | `hookeventname-coverage.test.sh`: drop the `fail=1` from the jq branch | pair (hookeventname-coverage, jq): `rc=0` |
| M4 | `pre-merge-rebase-parity.test.sh`: lower `MIN_CASES` to 10 (a python3-less run then clears the floor) | pair (pre-merge-rebase-parity, python3): `rc=0`. This pins the floor dependency named in Risks. |
| M5 | own dispatch: break the population regex so it matches nothing (e.g. `command -V`) | floor: `[FATAL] … found 0 pairs < MIN_PAIRS=40` |
| M6 | own dispatch: the per-tool toggle stops moving the tool's link aside | the tool resolves, so every suite runs in full and exits 0 without an `UNRESOLVED:` line. Every pair for that tool is RED. |
| M7 | reintroduce a file-under-test skip: `pre-merge-auto-close-scan.test.sh`'s `$SCANNER` arm back to `echo "SKIP: …"; exit 0` | static sweep names file:line |
| M8 | add `.claude/hooks/zz-probe.test.sh` containing `which jq >/dev/null \|\| { echo "SKIP"; exit 0; }`, sorting after the compliant existing members | pair (zz-probe, jq) RED **and** static sweep RED |
| M9 | a guard's message reworded to `SKIP: jq missing`, keeping `exit 3` | pair: `rc=3 but no UNRESOLVED: jq line` |
| M10 | add a scratch root under `.claude/hooks/` to `SUITE_GLOBS` in a throwaway copy, containing one non-compliant suite | the suite scans it and reports that pair RED. A hardcoded pair of globs would miss it (Kieran P1-5). |
| M11 | `guardrails.test.sh`: make the jq guard exit 3 only when `CI` is set, else `exit 0` | pair (guardrails, jq): `rc=0`, because the pair run unsets `CI` |
| M12 | `guardrails.test.sh`: keep the `UNRESOLVED:` echo, drop the `exit 3` | pair: `whole-suite guard rc=1, expected 3` |
| M13 | `guardrails.test.sh`: `exit 3` → `exit 1` | pair: `whole-suite guard rc=1, expected 3` |

**Harness rows.** These are edits to the new suite itself, or checker inputs that are not the
canonical form.

| # | Edit / input | Expected |
|---|---|---|
| H1 | neuter the rc half of `check_pair` (always treat rc as non-zero) | fixture R-a (`UNRESOLVED:` + `exit 0`) is reported PASS, so the self-test fails and exits 2 |
| H1b | neuter the line half of `check_pair` (always treat the line as found) | fixture R-b (`SKIP` + `exit 3`) is reported PASS, so the self-test fails and exits 2 |
| H2 | must-PASS: fixture P-a (multi-line `if ! command -v jq`, irregular spacing) through `derive_pairs` and `check_pair` | derived as one pair and reported PASS. A checker that rejects everything, or a regex that misses the multi-line form, fails here. |
| H3 | must-PASS: fixtures P-b (`SKIP: could not read peak RSS`, no exit) and P-c (`echo "$_skipnote"` + `exit 0`) through `scan_skip_exit0` | sweep reports clean. A sweep that flags every `SKIP` or every `exit 0` fails here. |

**Anchor.** `MIN_PAIRS` and the guards live in the same tree, so one diff can delete a guard and lower
the floor together. Review sees that as a floor decrease; no independent registry backs it. The
behavioral design is what gives the check teeth. It reads each suite's real exit code and output, not
a stored copy, so a weakened guard that stays in the population cannot pass.

## Test Scenarios

- **Normal host (all tools present).** `bash .claude/hooks/hook-suite-dep-unresolved.test.sh` exits 0.
  It prints `40 pairs (floor 40)`, the self-test verdicts (R-a and R-b RED, P-a to P-c PASS) and a
  clean static sweep.
- **Each converted suite on a normal host.** Behavior is unchanged. Running each of the 25 edited
  suites individually is green, which proves the edits did not touch the tool-present path.
- **Each tool toggled off, with `CI` unset.** Every jq-, git-, perl-, realpath- and python3-guarded
  suite prints `UNRESOLVED: <tool> missing`. The whole-suite guards exit 3, and the two arm-level
  pairs (`hookeventname-coverage`/jq and `pre-merge-rebase-parity`/python3) exit 1.
- **Suites that do not use jq** (e.g. `lib/freeze-lock.test.sh`) still exit 0 on the jq-less PATH. They
  are not in the population, so this is observed during work, not asserted.

## Deferral Tracking

- The same `SKIP … exit 0` idiom in `*.test.sh` files outside `.claude/hooks/` (about 13 files) is tracked in
  #8773, filed at plan time. It is re-evaluated when that directory's owner touches its
  suites.

## Open Code-Review Overlap

1 open scope-out touches these files: #7218 (cla-signed-author-gate only detects one hardcoded
unsigned identity). **Acknowledge.** It concerns the hook's detection logic, while this plan edits
only that suite's dependency guard line. The two changes are unrelated and #7218 stays open.

## Research Insights

**Premise validation.** #8616 is OPEN, with no closing PR. #7190 is CLOSED; its item 5 is the recorded
decision this plan reverses. #8570 is MERGED; it added the anti-vacuity floor to
`pre-merge-rebase-parity.test.sh` that this plan re-orders. Every cited path exists on this branch
(based at `285699d09f`). The mechanism the issue proposes (exit 3) was checked against the ADR
corpus. ADR-181 covers counted declines. ADR-188 covers "who owns the missing precondition": a tool the
runner is expected to supply leads to a hard fail under CI, and a precondition nobody owns leads to a
counted skip. No ADR rejects a leaf suite exiting 3. ADR-188's "the runner is contracted to supply
jq/git/perl/…" ownership axis supports never-green. The one local-skip exception it records
(gitleaks, #8266) is left out of scope and acknowledged.

**Property List (Phase 0.6b).**

- P1: On a host missing a tool that a hook suite guards, that suite's verdict is not green in
  `test-all.sh` and CI.
- P2: The verdict names its cause (a tool is missing, not an assertion failure) wherever the suite
  itself is read.
- P3: The conversion covers every guard in the hook suites (jq, git and the rest), not a sample.
- P4: A later edit cannot quietly reintroduce a green skip. One test shows it.

**Cut List.**

- `run_suite` `[UNRESOLVED]` rendering → P2 → already provided by the suite's own `UNRESOLVED:` line,
  which run_suite streams directly above `[FAIL]`. Cut.
- A shared `require_tool` helper → P3 → one-line canonical form plus behavioral verification covers it.
  Cut. The Step 4.5 advisor recommended it; the rebuttal is in Alternatives.
- A new `test-all.sh` registration → P4 → the existing `.claude/hooks/*.test.sh` `SUITE_GLOBS` entry
  auto-registers the new suite. Cut.
- An ADR → no property requires it. The taxonomy extends ADR-188's ownership axis to leaf suites
  without contradicting it, and lives in the new suite's header. Cut, per Phase 2.10: no reader of the
  existing ADRs is misled.
- Cut at plan review, each for one of two reasons: nothing required it, or a simpler mechanism in the
  plan already covered it.
  - Positive farm controls: the pair check fails closed on its own.
  - The timeout wrapper and its portability layer: every guard exits in under 1 s.
  - A separate instrument self-test: merged into the fixture self-test.
  - The "any tool yields 0 pairs" check: the exact-census floor already catches it.
  - `type -P`/`hash` in the regex.
  - The v1 exact-`rc == 3` assertion and the partial-arm epilogue rewrites: P1 needs non-zero, not 3.
  - H4/H5: they pinned nothing.

**Plan review (2026-09-24).** Four reviewers: DHH, Kieran, code-simplicity and CTO (devex lens). The
Step 4.5 advisor also ran.

- **Applied (Mechanical):**
  - All 12 Kieran findings. The sharpest: v1 H1 could not go RED; AC2 would have matched the new
    suite's own fixtures; the static sweep would have hit `memory-backstop.test.sh`; hook roots are
    now derived from `--print-suite-globs`; the exact `counters_of` spellings are now stated; output
    goes to a file, not `$(...)`; the farm is built with one `ln` per PATH directory.
  - The code-simplicity cuts listed above.
  - All three CTO mechanical DX items: an `install <tool>` suffix, an actionable FATAL text, and RED
    messages that print the canonical one-liner.
- **Declined, with reasons:**
  - DHH "static lint only": see Alternatives. Recorded in `decision-challenges.md`.
  - Code-simplicity "leave `grep-rewrite`/`settings-hook-exec-bit` at exit 1": the edit touches the
    same line anyway, and the issue's second acceptance item asks for uniform application.
  - Keeping `which` in the regex: this is the natural-repair sharp edge.

**Measurements behind this plan (2026-09-24, this worktree).**

- `suite_exit_class`, extracted and evaluated: `3 → failed`, `130/143 → killed`, `97 → failed`.
- All 52 hook suites were run on a PATH farm without jq (3,377 symlinks, `command -v jq` fails). 30 exit
  0; 22 of those printed only a SKIP line or a `0/0` results line; `hookeventname-coverage` ran partially;
  7 are genuinely jq-free. 15 exit 1, and 7 exit 127. Serial sum 30 s. `git status` was unchanged.
- The same on a PATH without git: the 11 git-guarded suites print `SKIP: git missing` and exit 0. The
  remaining suites run in full (serial sum 179 s). That is why the regression suite runs **only** the
  guarded population, not every suite.
- Without perl, realpath or python3: `context-reviewed-gate`, `follow-through-directive-gate` and
  `security_reminder_hook` each reach their guard and exit 0. `pre-merge-rebase-parity` gives
  `10/10 passed, 2 skipped` and then `FATAL anti-vacuity … floor is 12`, rc 1. `hook-tool-kind` gives
  `23 passed, 1 failed`, rc 1.
- Guard-population regex on the current tree: 40 lines, which is 40 distinct (file, tool) pairs.

**Relevant files.**

- `scripts/test-all.sh`: §EXIT CONTRACT (header), `SUITE_GLOBS`, `suite_exit_class()`, `run_suite()`
  (the FAIL/`[TRIPWIRE]` arms) and the glob registration loop (`for _suite_glob in "${SUITE_GLOBS[@]}"`).
- `.github/workflows/ci.yml`: the `test-scripts` shard (`bash scripts/test-all.sh scripts`) and the
  `lint-scripts` job (`lint-orphan-test-suites.sh`, `lint-trap-tempfile-ownership.py`).
- `.claude/hooks/git-commit-secret-scan.test.sh` `_mk_stub_path`: prior art for building a PATH that
  lacks one tool. It links a named tool list; the new suite links **all** PATH executables except one,
  because the tool set each guarded suite needs is not known up front.
- `.claude/hooks/hook-input-contract.test.sh`: the #7190-item-5 rationale this plan reverses.

**Institutional learnings applied.**

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: a mutation
  matrix derived from the design, including rows on the guard's own dispatch (M5, M6).
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: the core
  defect. The fix must show the check *can* fail, which the harness rows H1/H2 do.
- `2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md`:
  when a fix turns an undefined outcome into a defined one, check which way it was defined. #7190 made
  a jq-missing run pass; this plan defines it as UNRESOLVED.
- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`: floors report with
  `printf` plus `exit`, never through the helper they back up (MIN_PAIRS).
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`: derive cardinality from the
  filesystem, never from a hard-coded list (the population is derived).
- `2026-03-10-require-jq-startup-check-consistency.md`: one canonical startup-check form across a
  family of scripts.
- `2026-09-17-command-v-is-a-resolvability-probe-and-every-guard-i-wrote-to-pin-it-was-narrower-than-its-name.md`: `command -v` checks only that a tool
  resolves. The farm toggles exactly that property (resolvability), which is also what the suites'
  guards test. The claim is kept that narrow.

**CLAUDE.md / AGENTS.md conventions.** `cq-write-failing-tests-before`: the new suite is written and
seen RED against the unconverted tree first. Expected from the measurements: all 40 pairs RED. 37
exit 0. The other 3 (`grep-rewrite`/jq, `settings-hook-exec-bit`/jq, `pre-merge-rebase-parity`/python3)
exit 1 but lack the `UNRESOLVED:` line.
`hr-when-a-command-exits-non-zero-or-prints`, `cq-assert-anchor-not-bare-token`: the canonical line
is matched anchored (`^\s*UNRESOLVED: <tool> missing`), not as a bare `UNRESOLVED` token.

**Functional overlap.** Community registries have no dedicated bash dependency-guard taxonomy tool
(shellspec and similar are general frameworks). No overlap. Community stack discovery was not
applicable, since the change touches only bash test files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change to test-harness exit
codes, plus one regression suite.

## Implementation Phases

1. **RED first.**
   - Write `.claude/hooks/hook-suite-dep-unresolved.test.sh`, including its self-test fixtures.
   - Add its `PROMOTED_FILES` entry in the same phase, so `guard-vacuity-floor.test.sh` stays green
     from the first commit.
   - Run the new suite against the unconverted tree and confirm:
     - the RED pairs are the 37 at rc 0 today: 22 whole-suite jq skips, 11 git, perl, realpath,
       `security_reminder_hook` python3 and `hookeventname-coverage` jq;
     - `grep-rewrite`/jq, `settings-hook-exec-bit`/jq and `pre-merge-rebase-parity`/python3 already
       exit 1, but are RED on the missing `UNRESOLVED:` line;
     - the static sweep lists the 35 one-line AC2 matches and the multi-line `security_reminder_hook`
       and `context-reviewed-gate` `$HOOK` arms;
     - the self-test passes.
2. **Convert the guards.**
   - The one-liner files (18, plus `grep-rewrite`) and the 4 multi-line files move to the canonical
     forms.
   - The 2 file-under-test arms become `FAIL:`/`exit 1`.
3. **Partial arms.**
   - `hookeventname-coverage`: add `fail=1` and the UNRESOLVED line.
   - `pre-merge-rebase-parity`: change messages only.
4. **Rationale comments.** Update `hook-input-contract.test.sh`, `grep-rewrite.test.sh`,
   `settings-hook-exec-bit.test.sh` and `security_reminder_hook.test.sh`.
5. **GREEN and mutation.**
   - Run the new suite: 0 failures, 40 pairs.
   - Run the 25 edited suites individually on a normal PATH: all green.
   - Run mutation rows M1–M13 and harness rows H1, H1b, H2 and H3 once each, each against a scratch
     copy of the repo with a pristine control run first. Quote each output line in the PR body.
6. **CI-form lints, run locally.** Two of these went red on the #8727 plugin-root migration.
   - Gates:
     - `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` (no skill
       is touched; run it anyway)
     - `python3 scripts/lint-trap-tempfile-ownership.py`, plus `--check-highwater`
     - `bash scripts/lint-orphan-test-suites.sh`
     - `bash scripts/guard-vacuity-floor.test.sh`: the ledger count is unchanged from its pre-change
       run, and the new file is reported as covered.
     - `shellcheck` on the new suite
   - There is no `.ts` in the diff, so eslint has nothing to check. Say so in the PR.
   - Targeted neighbours that scan hook test files: `stub-argv-fidelity.test.sh`,
     `grep-q-pipe-guard.test.sh`, `settings-hook-exec-bit.test.sh`, `hookeventname-coverage.test.sh`,
     `memory-backstop.test.sh` and `plugins/soleur/test/fixture-relative-assert.test.sh`.
   - **Do not run `scripts/test-all.sh` unscoped.** CI runs the full battery.

## Acceptance Criteria

- [ ] **AC1:** The header of `.claude/hooks/hook-suite-dep-unresolved.test.sh` is the single home of
  the taxonomy. A missing tool exits 3 with `UNRESOLVED: … install <tool>`. A missing file under test
  exits 1 with `FAIL:`. A partial arm exits non-zero with a per-arm `UNRESOLVED:` line. The header cites
  the measured `run_suite` classification (rc 3 is printed as `[FAIL]` and counted not-green; the top
  level exits 1) and states that upstream, exit 3 names the verdict without changing it.
- [ ] **AC2:** `grep -nE '^[[:space:]]*[^#].*SKIP[^"]*"[^}]*exit 0' .claude/hooks/*.test.sh .claude/hooks/lib/*.test.sh`
  returns nothing, with no carve-out for the new suite, whose fixtures are built from pieces. The
  regression suite's static sweep also reports clean, including the multi-line forms this grep cannot
  see.
- [ ] **AC3:** `bash .claude/hooks/hook-suite-dep-unresolved.test.sh` exits 0 on a normal host and
  prints `40 pairs (floor 40)`. Every pair exits non-zero with `UNRESOLVED: <tool> missing` under its
  tool toggle.
- [ ] **AC4:** Each of the 25 edited suites exits 0 when run individually on a normal PATH.
- [ ] **AC5:** Mutation rows M1–M13 were each run once and each turned the new suite RED.
  - Every row ran against a **scratch copy** of the repo, never against tracked files in place.
  - A control run on the pristine copy exited 0.
  - Only rc 1 counts as a caught mutation. An rc of 2 or 127 means the instrument broke, and that is
    not evidence (test-design P2-5). Harness rows
  H1 and H1b were RED (self-test exit 2), and H2 and H3 passed. The output line from each row is quoted
  in the PR body.
- [ ] **AC6:** `scripts/test-all.sh` and `.github/workflows/ci.yml` are unchanged:
  `git diff --quiet origin/main -- scripts/test-all.sh .github/workflows/ci.yml`.
- [ ] **AC7:** Each of these passes locally, run with the gate's own invocation rather than a
  reconstruction of its inputs: `lint-trap-tempfile-ownership.py` (and `--check-highwater`),
  `lint-orphan-test-suites.sh`, `lint-skill-body-budget.py --base <merge-base>`,
  `scripts/guard-vacuity-floor.test.sh`, and `shellcheck` on the new suite.
- [ ] **AC8:** The rationale block in `hook-input-contract.test.sh` records the reversal under #8616
  and answers reasons (a) to (d).
- [ ] **AC9:** #8773 (the same pattern outside `.claude/hooks/`) exists and is linked in the PR body.
  The PR body uses `Closes #8616`.
