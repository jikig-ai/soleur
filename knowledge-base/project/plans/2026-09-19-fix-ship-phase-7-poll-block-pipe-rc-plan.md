---
title: "fix(ship): phase-7 poll block's BEHIND auto-sync reports a failed git merge as pushed — capture rc before tail"
type: fix
date: 2026-09-19
slug: fix-ship-phase-7-poll-block-pipe-rc
branch: feat-one-shot-8339-poll-block-pipe-rc
issue: 8339
closes: 8339
priority: P2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(ship): phase-7 poll block's BEHIND auto-sync reports a failed `git merge` as pushed — capture rc before `tail`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `knowledge-base/project/specs/feat-one-shot-8339-poll-block-pipe-rc/spec.md` exists on this one-shot branch.)

## Overview

The Phase 7 poll block that `soleur:ship` (canonical, inside the `<!-- phase-7-poll-block:start -->` fence) and `soleur:merge-pr` §5.2 (derived mirror) prescribe for the merge boundary has a BEHIND auto-sync arm whose three guards — `git fetch`, `git merge origin/main`, `git push` — are each piped through `| tail -N` for display. The `if`/`elif` tests read the pipeline's exit status, which is `tail`'s (always 0), so none of the three failure branches can ever be taken in the Monitor shell (which runs with `pipefail` off — measured: `bash -c 'set -o | grep pipefail'` prints `pipefail off`). A conflicting merge is therefore reported as "auto-sync N pushed", the worktree is left mid-merge with `MERGE_HEAD` present, and the remaining sync attempts are burned re-running `git merge` on an already-conflicted tree until the loop prints a `behind_exhausted` diagnosis for a condition that does not exist. Measured on PR #8320 (2026-09-18 23:03).

This plan captures the exit status of each of the three commands explicitly (not via `set -o pipefail`, which would change the semantics of every other pipe in a block that two skills copy), displays the captured output through `tail` afterwards, lands the identical sync arm in both the canonical block and the mirror, and adds RED-first fixtures to `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` that stub `git merge`, `git push`, and `git fetch` to exit 1.

**Load-bearing finding from plan-time prototyping (not in the issue):** the fixture harness sets `set -uo pipefail` at file scope, and the scenario subshell in `run_scenario` inherits it. Under `pipefail`, the *buggy* block takes the correct branch — so a fixture written naively against the harness as it stands today is GREEN on the defect it exists to catch. Verified in the scratchpad: with pipefail ON, the current block passes the new scenarios; with pipefail OFF (Monitor semantics), the current block fails them and the fixed block passes them. The scenario subshell must therefore run `set +o pipefail`, and the suite needs a self-check row proving it does.

## Problem Statement / Motivation

From #8339 (measured on PR #8320):

```text
23:03:20 [2/60] BEHIND detected — auto-sync attempt 1/6
Auto-merging plugins/soleur/skills/review/SKILL.md
Automatic merge failed; fix conflicts and then commit the result.
Everything up-to-date
23:03:26 [2/60] auto-sync 1 pushed
```

Inspected immediately after: `MERGE_HEAD` present, two paths in `--diff-filter=U`, remote head unchanged. Cause, in `plugins/soleur/skills/ship/SKILL.md` (fence, BEHIND arm):

```bash
    if ! git fetch origin main 2>&1 | tail -2; then
      ...
    elif ! git merge origin/main --no-edit 2>&1 | tail -5; then
      ...   # conflict branch: --abort + break — UNREACHABLE
    elif ! git push 2>&1 | tail -2; then
      ...   # "git push failed after merge" — UNREACHABLE
    else
      echo "... auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate"
```

The mirror in `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 has the same three pipes collapsed into one `&&` chain (`if git fetch … | tail -2 && git merge … | tail -5 && git push … | tail -2; then`) — same dead guard, and its single `else` arm conflates a fetch failure (which the canonical block treats as "skip this attempt") with a merge conflict (abort + stop).

This is the `cmd | tail` shape `work/SKILL.md` already forbids from #7828 ("never pipe a command whose exit code IS the result"), now measured inside the block that `ship` and `merge-pr` prescribe for the merge boundary.

## Proposed Solution

**Explicit rc capture, then display** — the issue's proposed form, applied to all three commands, in both blocks. Not `set -o pipefail`: that changes every other pipe in the block (`echo "$s" | grep -qE … && break`, `printf … | grep '^CONFLICT '`) and anything a later edit adds, in a block two skills copy and an LLM pastes into a Monitor.

Replacement for the sync arm (canonical block; the mirror gets the same lines and keeps its own success echo `auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed`):

```bash
    # Capture each command's rc BEFORE displaying through `tail`: `cmd | tail`
    # returns tail's status (0), so `if ! cmd | tail` can never take its
    # failure branch (#8339). Explicit capture, not `set -o pipefail` — that
    # would change every other pipe in a block two skills copy. No `local`
    # prefix on the assignment: `local x=$(cmd)` would clobber $? with local's 0.
    sync_out="$(git fetch origin main 2>&1)"; sync_rc=$?
    printf '%s\n' "$sync_out" | tail -2   # display only — never test this pipe
    if (( sync_rc != 0 )); then
      echo "fetch origin main failed (rc=$sync_rc) — skipping this sync attempt"
    else
      sync_out="$(git merge origin/main --no-edit 2>&1)"; sync_rc=$?
      printf '%s\n' "$sync_out" | tail -5
      if (( sync_rc != 0 )); then
        echo "git merge origin/main failed (rc=$sync_rc) — merge conflict, aborting sync. Conflicted paths:"
        git diff --name-only --diff-filter=U
        git merge --abort 2>/dev/null
        echo "Manual conflict resolution required on $BRANCH. Stopping the poll."
        break
      fi
      sync_out="$(git push 2>&1)"; sync_rc=$?
      printf '%s\n' "$sync_out" | tail -2
      if (( sync_rc != 0 )); then
        echo "git push failed after merge (rc=$sync_rc) — auto-sync incomplete. Stopping the poll."
        break
      fi
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate"
      # (existing re-fetch of $s + MERGED/CLOSED break stays here, unchanged)
    fi
```

Notes on the shape:

- `var="$(cmd)"; rc=$?` — the assignment's status is the command substitution's status, so `$?` is `cmd`'s rc. Same idiom the DIRTY arm already uses a few lines above (`mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"`), so the block stays internally consistent. Verified by Kieran plan-review under `set -u; set +o pipefail` with the scenario-6 mocks: conflict branch taken, sentinel printed, loop exits at `i=1`.
- The merge-failure message now contains the literal `merge conflict`, so the Grok `AwaitShell` wake pattern in `plugins/soleur/lib/pr-merge-poll.ts` (`BEHIND detected|auto-sync.*pushed|BEHIND resolved|BEHIND unchanged|merge conflict`) fires on it. The old message ("produced conflicts") did not match that pattern.
- The three message prefixes the issue names — `fetch origin main failed`, `Manual conflict resolution required`, `git push failed after merge` — are preserved verbatim so the fixture rows and the issue's own verification language agree.
- Success lines are unchanged in both blocks (ship: `auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate`; merge-pr: `auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed`). Both match `auto-sync.*pushed` (the wake pattern) and the fixture regex `auto-sync [0-9/]+ pushed`.
- Nesting replaces the `if/elif/elif/else` chain because each step's rc has to be captured *before* the next step runs; a helper function (`_tail_rc N cmd…`) would keep the chain flat but adds a name to the Monitor shell's namespace and one more thing for the mirror to drift on. Rejected on the minimalism ladder (rung 5: the inline form is the same line count).
- **Alternative considered — `git -q` on all three commands and drop `tail` entirely** (DHH plan-review P0, measured: `-q` silences success output, keeps `CONFLICT`/`error:` lines and the rc). Three lines per block instead of ~25. Not adopted here because the operator's stated mechanism for #8339 is "capture the rc explicitly, then display via tail", and `-q` also drops the `Auto-merging <path>` / `Merge made by the 'ort' strategy` lines the operator reads in the Monitor stream. Recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8339-poll-block-pipe-rc/decision-challenges.md`; if accepted at ship, the fixture rows below hold unchanged except the mock dispatch keys (`"merge -q"` instead of `"merge origin/main"`).

### Files to Edit

1. `plugins/soleur/skills/ship/SKILL.md` — inside the `<!-- phase-7-poll-block:start -->` … `:end` fence only (the BEHIND arm, currently the `if ! git fetch … | tail -2` / `elif ! git merge … | tail -5` / `elif ! git push … | tail -2` / `else` chain). Nothing else in the file: the fence comment header, the `MAX_POLL_MIN` derivation, the required-check scan, the DIRTY arm, the `behind_exhausted` arm, and the incident-PIR gate (§5.5, `OUTAGE_RE`, tracked separately by #8334) are all out of scope.
2. `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2, inside its `<!-- phase-7-poll-block:start --> mirror` fence: replace the `if git fetch … | tail -2 && git merge … | tail -5 && git push … | tail -2; then … else git merge --abort; echo "auto-sync failed …"; break; fi` arm with the captured-rc arm above (keeping merge-pr's own success echo and re-fetch). Also update the §5.2 prose sentence "this mirror is not directly tested" — after this plan scenarios 6/7/8 run against the mirror too.
3. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — see Guard Contract. The fence-anchored `extract_block()` awk and the three fingerprint tokens are NOT modified.

### Files to Create

None.

## Technical Considerations

- **The harness must reproduce the Monitor shell's option set.** `run_scenario` gains `set +o pipefail` as the first statement of its `( … )` subshell (the subshell scopes it; the file-level `set -uo pipefail` still governs the harness's own bookkeeping). All six existing scenarios were re-run with this change in the scratchpad: 18/18 still pass, so the existing rows do not depend on pipefail. `errexit` is not asserted: the harness never sets `-e`, and if it ever did, `sync_out="$(git merge …)"` would exit the subshell before the sentinel and the live rows 6/7 would redden on their own.
- **The self-check mocks file must be written with a QUOTED heredoc.** Every existing mocks file uses an unquoted `<<EOF`, which expands `$?` at file-creation time in the harness shell — a self-check body written that way literally contains `echo "harness-pipefail-status=0"` and passes regardless of the subshell's options (Kieran plan-review, verified). Use `<<'EOF'` (or escape `\$?`).
- **Both blocks get scenario coverage for the sync arm.** `run_scenario` currently sources the global `$BLOCK_FILE`; it takes the block file as a 5th argument (`local block="${5:-$BLOCK_FILE}"`) so scenarios 6/7/8 can run against `$MIRROR_FILE` too. The mirror extraction must gain the same `sed 's/<number>/4387/g'` the canonical extraction has — sourced verbatim, `gh pr view <number>` parses `<number>` as an input redirect from a file named `number`, and `$s` degrades to `fetch-error:` on the first tick (needed for execution, not for `bash -n`, which the mirror already passes).
- **`break` must be observed, not inferred.** With `gh pr view` stubbed to return `OPEN BEHIND` forever and `sleep` a no-op, a block that does not `break` runs to `behind_exhausted` and then `Merge poll timed out` inside a second. Scenarios 6 and 7 therefore forbid `ship.phase7.behind_exhausted|Merge poll timed out` — that is the observable for `break`. `--abort` is observed by the git stub printing a sentinel **on stdout** (`MOCK: git merge --abort observed`) — the arm runs `git merge --abort 2>/dev/null`, so a sentinel on stderr is swallowed and scenario 6 would go RED on a correct block.
- **Mock `git` dispatches on `"$1 ${2:-}"` with these exact case patterns** (the block calls each of these): `"rev-parse "*) echo "test-branch" ;;` (covers `--abbrev-ref HEAD`, which AC2's regex hard-codes, and `--is-inside-work-tree`), `"merge origin/main") …`, `"merge --abort") echo "MOCK: git merge --abort observed" ;;`, `"diff --name-only") echo "foo.md" ;;`, `"fetch origin") …`, `"push "|"push") …` (bare `git push` has no `$2`; `${2:-}` is required under `set -u`), `*) return 0 ;;`.
- **Command substitution and mock counters.** The fixed block runs `git` inside `$( … )`, so any counter a mock increments is lost in the subshell. Do not design assertions around call counts; use printed sentinels and the exit-observables above.
- **Grok harness.** The block is also the loop body `pollInstructions()` hands to AwaitShell/Shell; nothing in the fix uses a bashism beyond what the block already uses (`(( ))`, `mapfile`), so no `harness.ts` change.
- **Real exit codes, measured 2026-09-19 in a throwaway bare-origin repo (git 2.x):** `git merge origin/main --no-edit` on a content conflict → rc 1 with `MERGE_HEAD` present; `git merge --abort` → `MERGE_HEAD` gone; `git fetch origin <missing-ref>` → rc 128. The fix tests `!= 0`, so both 1 and 128 take the failure arm; the mocks use `return 1` and the retroactive run (AC11) uses real git.
- **`plugins/soleur/scripts/sync-pr-behind.sh` has the same three `| tail` pipes but runs under `set -euo pipefail` (line 10), so its guards DO see the git rc.** Verified by reading the file — the repo-research pass flagged it as the same defect; it is not. Out of scope; it is the third copy of this arm, and consolidating the three is #8383.

## User-Brand Impact

- **If this lands broken, the user experiences:** a `soleur:ship` / `soleur:merge-pr` Monitor stream that either still prints "auto-sync N pushed" over a conflicted worktree (regression of the bug), or a poll that stops on a non-failure (over-correction) — in both cases a false verdict line the founder acts on. No end-user surface of the web platform is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the change adds no output beyond the captured `git` stdout/stderr that was already displayed through `tail`, and adds no network call.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the diff touches only two SKILL.md bash blocks and their bash fixture; no auth, payment, migration, or customer-data path is read or written.`

## Observability

The defect *is* an observability defect (a verdict line that could not be believed), so the section is written even though the touched files are skill prose plus a test.

```yaml
liveness_signal:
  what: "ship-phase-7-poll-fixtures.test.sh scenarios 6/7/8 (both blocks) + pipefail self-check row, executed on every PR in the `scripts` group of scripts/test-all.sh (plugins/soleur/test/*.test.sh glob, line 78)"
  cadence: "per PR / per push to main"
  alert_target: "red `test-scripts` required check on the PR"
  configured_in: "scripts/test-all.sh (SUITE_GLOBS) + .github/workflows/ci.yml matrix job"

error_reporting:
  destination: "the Monitor stream itself (observability layer 7 — customer-hosted CLI, no Sentry hop); `hr-observability-layer-citation`: the poll block's stdout/stderr is the only channel and the fix makes its failure lines reachable"
  fail_loud: "`git merge origin/main failed (rc=N) — merge conflict …` / `git push failed after merge (rc=N) …` followed by `Stopping the poll.`; the loop exits instead of printing `auto-sync N pushed`"

failure_modes:
  - mode: "merge conflict during BEHIND auto-sync"
    detection: "captured `sync_rc != 0` after `git merge`; conflicted paths printed from `git diff --name-only --diff-filter=U`, then `git merge --abort` and `break`"
    alert_route: "Monitor notification line + loop exit (operator session)"
  - mode: "push rejected after a clean merge (non-fast-forward, protected ref, auth)"
    detection: "captured `sync_rc != 0` after `git push`; `git push failed after merge (rc=N)` + `break`"
    alert_route: "Monitor notification line + loop exit"
  - mode: "fetch failure (network / auth)"
    detection: "captured `sync_rc != 0` after `git fetch`; `fetch origin main failed (rc=N) — skipping this sync attempt`; the attempt is counted and the loop continues"
    alert_route: "Monitor notification line; `behind_exhausted` after 6 such attempts (a fetch-outage reads as 'main moving faster than CI' — accepted here, tracked as an optional refinement in #8383)"
  - mode: "the fix regresses in either block (a future edit re-introduces `git X | tail` inside a conditional)"
    detection: "scenarios 6/7/8 run against both extracted blocks under `set +o pipefail`; any dead guard prints `pushed` and reddens `test-scripts`"
    alert_route: "red required check on the PR"

logs:
  where: "Monitor tool notification stream of the ship/merge-pr session (Claude Code) or AwaitShell output (Grok Build); not persisted beyond the session transcript"
  retention: "session transcript lifetime"

discoverability_test:
  command: "bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh"
  expected_output: "ship-phase-7 fixture: N pass, 0 fail (N ≥ 18 + the rows this plan adds), including `pass: [6-merge-conflict-in-sync]`, `pass: [7-push-fails-after-merge]`, `pass: [8-fetch-fails-skips-attempt]` for both `ship` and `merge-pr`, and `pass: harness runs the block with pipefail off`"
```

## Guard Contract

### Guard 1 — BEHIND sync-arm failure branches are reachable (scenarios 6, 7, 8 on both blocks)

**Property.** In the Phase 7 poll block as sourced by a shell with `pipefail` off, a non-zero exit from `git merge origin/main` produces `git merge --abort` and terminates the loop, a non-zero exit from `git push` produces the line `git push failed after merge` and terminates the loop, and a non-zero exit from `git fetch` skips the attempt without terminating — and the line `auto-sync … pushed` is never printed in any of the three cases.

**Assembly.** The BEHIND auto-sync arm of BOTH fenced blocks: `plugins/soleur/skills/ship/SKILL.md` between `<!-- phase-7-poll-block:start -->` and `:end`, and `plugins/soleur/skills/merge-pr/SKILL.md` between its own copies of the same markers. The chokepoint is `extract_block()` in `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — every scenario sources what that awk extracts, so a sync arm outside the fence (or a third copy of the block elsewhere — `plugins/soleur/scripts/sync-pr-behind.sh` is one, tracked by #8383) is NOT covered. There are exactly two members today (canonical + mirror); `run_scenario` is parameterized on the block file so scenarios 6/7/8 run once per member, and the mirror-parity token check asserts the member shape did not silently change.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the `git merge` capture in ship's block to `elif ! git merge origin/main --no-edit 2>&1 \| tail -5; then` | RED — scenario 6 (ship): `MOCK: git merge --abort observed` missing, `auto-sync 1 pushed` present (verified in scratchpad against the current block) |
| 2 | Revert the `git push` capture in ship's block to `elif ! git push 2>&1 \| tail -2; then` | RED — scenario 7 (ship): `git push failed after merge` missing |
| 3 | Delete the `git merge --abort 2>/dev/null` line from the fixed arm | RED — scenario 6: abort sentinel missing while `Manual conflict resolution required` present |
| 4 | Delete the `break` after `Manual conflict resolution required …` | RED — scenario 6: `ship.phase7.behind_exhausted` / `Merge poll timed out` present (the loop ran on) |
| 5 | Apply the fix to ship's block only; leave merge-pr's `&&` chain | RED — scenarios 6/7/8 (merge-pr) fail exactly as rows 1/2, and the parity token `sync_rc=$?` is missing from the mirror |
| 6 | Change the fetch-failure arm to `break` instead of falling through | RED — scenario 8: `behind_exhausted` missing (a fetch failure must be counted, not fatal) |
| 7 | Move `sync_rc=$?` one line down (after the `printf … \| tail`) | RED — scenarios 6 and 7: `$?` is now `tail`'s 0 again; this is the ORDER row — the property is about where the rc is read, not whether the line exists |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Remove `set +o pipefail` from the `run_scenario` subshell | RED — the pipefail self-check row (`false \| true; echo "harness-pipefail-status=$?"`, written with a quoted heredoc) prints `=1`; without this row, rows 1/2/7 would go GREEN on the buggy block (measured: current block passes scenarios 6 and 7 under pipefail ON) |
| H2 | Drop the `sed 's/<number>/4387/g'` from the mirror extraction | RED — scenario 6 (merge-pr) sees `fetch-error:` on tick 1 and breaks before the BEHIND arm; the must-match sentinel is missing |
| H3 | Point the mirror scenarios at `$BLOCK_FILE` instead of `$MIRROR_FILE` (parameter drift) | RED — row 5 can no longer redden; AC6 requires `grep -c '"\$MIRROR_FILE"$'` ≥ 3 in the suite (the terminating-line form, because every `run_scenario` call is multi-line) |
| H4 | Write the self-check mocks with an unquoted `<<EOF` heredoc | RED — AC4 requires the row to have been driven RED once by removing `set +o pipefail` before commit (recorded in the PR body); with an unquoted heredoc that RED cannot be produced, which is the tell |
| P1 | Must-PASS, non-canonical: existing scenario 3 (all-success git, BEHIND saturation) and 4b (DIRTY-but-clean → auto-sync prints `pushed`) under the new `set +o pipefail` subshell | GREEN — 18/18 existing assertions unchanged (measured in scratchpad) |

## Acceptance Criteria

- [ ] AC1 — RED first, checkable by commit order: in `git log --oneline origin/main..HEAD`, the commit that adds scenarios 6/7/8 + `set +o pipefail` + the self-check row precedes the first commit that edits either SKILL.md, and that first commit's `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` run ends with `fail` > 0 (the pass/fail line is quoted in the PR body) (`cq-write-failing-tests-before`).
- [ ] AC2 — scenario 6 asserts, per block: must-match `MOCK: git merge --abort observed` AND `Manual conflict resolution required on test-branch\. Stopping the poll\.` AND `merge conflict`; must-not-match `auto-sync [0-9/]+ pushed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call`.
- [ ] AC3 — scenario 7 asserts, per block: must-match `git push failed after merge`; must-not-match `auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call`. Scenario 8 asserts, per block: must-match `fetch origin main failed` AND `ship\.phase7\.behind_exhausted`; must-not-match `auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|git push failed after merge`. (Scenario 8 is RED on the current block too — the dead fetch guard falls through to merge/push and prints `pushed`.)
- [ ] AC4 — a harness self-check row sources a mocks file written with a QUOTED heredoc whose body is `false | true; echo "harness-pipefail-status=$?"` (plus a `gh` returning `MERGED CLEAN` on tick 1) and asserts `harness-pipefail-status=0`; the PR body quotes the one run where removing `set +o pipefail` made this row print `=1` (Guard 1 rows H1/H4).
- [ ] AC5 — the mirror-parity token loop (existing `for token in …` over `$MIRROR_FILE`) gains `'sync_rc=$?'`, `'git merge --abort'`, `'git push failed after merge'` and `'fetch origin main failed'`; the existing tokens are untouched.
- [ ] AC6 — `run_scenario` accepts the block file as its 5th argument; `grep -c '"\$MIRROR_FILE"$' plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` ≥ 3 (scenarios 6/7/8 against the mirror), and the mirror extraction line carries `sed 's/<number>/4387/g'`.
- [ ] AC7 — `bash -n` is asserted for the mirror file as it already is for the canonical (one added `pass`/`fail` line).
- [ ] AC8 — diff scope, one check: `git diff -U0 origin/main -- plugins/soleur/skills/ship/SKILL.md | grep '^@@'` shows hunks only inside the `<!-- phase-7-poll-block:start -->` … `:end` line range (2228–2363 on `origin/main`; recompute after the edit), `git diff origin/main -- plugins/soleur/skills/ship/SKILL.md | grep -c OUTAGE_RE` = 0 (the §5.5 incident-PIR gate is untouched, #8334), merge-pr's hunks fall inside its fence (377–465 on `origin/main`) plus the one prose sentence at line 374, and `git diff origin/main -- plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh | grep -E '^[-+].*(in_block|for token in '"'"'MAX_BEHIND_SYNCS)'` prints nothing (extractor and fingerprint untouched).
- [ ] AC9 — full suite green after the fix: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` ends `0 fail`, and `TEST_GROUP=scripts bash scripts/test-all.sh` is green (the fixture is picked up by the existing `plugins/soleur/test/*.test.sh` glob — no runner registration change; `scripts/lint-orphan-test-suites.sh` derives its globs from `test-all.sh`).
- [ ] AC10 — `scripts/lint-guard-contract.py` passes on this plan file.
- [ ] AC11 — Retroactive application (requested in #8339 under `wg-when-fixing-a-workflow-gates-detection`): the fixed canonical arm is run once against a throwaway local repo placed one conflicting commit behind its `main` (synthesized bare `origin` + two clones, no network, real `git` — see Test Scenarios "Retroactive"); the captured stream shows `merge conflict`, the conflicted path, `Manual conflict resolution required on feat`, and NO `auto-sync … pushed`; afterwards `git rev-parse -q --verify MERGE_HEAD` → rc 1, `git status --porcelain` in the feature clone is empty, and `git rev-parse origin/main` / `git rev-parse origin/feat` are unchanged (the three observables the mocks structurally cannot see). The ~10 verdict lines go in the PR body next to the AC1 RED run — no `specs/` transcript file.

## Test Scenarios

Existing scenarios 1, 2, 3, 4, 4b, 5 are unchanged in content and must still pass under `set +o pipefail`.

- **Scenario 6 — merge conflict in sync (RED on current block).** Given `gh pr view` always returns `OPEN BEHIND`, and `git merge origin/main` prints `CONFLICT (content): Merge conflict in foo.md` / `Automatic merge failed; …` and exits 1, and `git diff --name-only --diff-filter=U` prints `foo.md`, and `git merge --abort` prints `MOCK: git merge --abort observed` on stdout, when the block is sourced with pipefail off, then the output contains the abort sentinel and `Manual conflict resolution required on test-branch. Stopping the poll.`, and contains neither `auto-sync … pushed` nor `behind_exhausted` nor `Merge poll timed out`. Run against `$BLOCK_FILE` and `$MIRROR_FILE`.
- **Scenario 7 — push fails after clean merge (RED on current block).** Given the same `gh`, `git merge` prints `Merge made by the 'ort' strategy.` and exits 0, `git push` prints `error: failed to push some refs to 'origin'` and exits 1, then the output contains `git push failed after merge`, and contains neither `auto-sync … pushed` nor the abort sentinel nor `behind_exhausted`. Both blocks.
- **Scenario 8 — fetch fails, attempt is skipped (RED on current block).** Given `git fetch` prints `fatal: unable to access 'origin'` and exits 1 while merge/push would succeed, then `fetch origin main failed (rc=1) — skipping this sync attempt` is printed, no abort sentinel, no `git push failed`, no `pushed`, and after six attempts `[ship.phase7.behind_exhausted]` appears and the loop times out. Both blocks.
- **Harness self-check.** Given a mocks file (quoted heredoc) whose body is `false | true; echo "harness-pipefail-status=$?"` plus a `gh` that returns `MERGED CLEAN` on tick 1, then the output contains `harness-pipefail-status=0`.
- **Regression (issue transcript).** The #8320 transcript shape (`Automatic merge failed` followed by `auto-sync 1 pushed`) is exactly scenario 6's forbidden pairing.
- **Retroactive (AC11), synthesized only, no network.** Run from a subshell with the worktree's git-location variables scrubbed (this repo is a linked worktree, so `GIT_DIR`/`GIT_INDEX_FILE` are exported to hooks and a child `git` honours them over `cwd` — see `plugins/soleur/AGENTS.md` §Test Fixture Conventions) and a pinned identity: `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bash -c '…'` where `…` is: `tmp=$(mktemp -d); git init -q --bare $tmp/origin; git clone -q $tmp/origin $tmp/a; (cd $tmp/a && echo base > f && git add f && git commit -qm base && git push -q origin HEAD:main && git checkout -qb feat && echo feat > f && git commit -qam feat && git push -q origin feat); git clone -q $tmp/origin $tmp/b; (cd $tmp/b && git checkout -q main && echo main > f && git commit -qam main && git push -q origin main)`; then in `$tmp/a` source the extracted fixed block with `gh` stubbed to `OPEN BEHIND` then `MERGED`, `sleep` a no-op, real `git`, and capture the stream. Expect `merge conflict`, `f`, `Manual conflict resolution required on feat`, no `pushed`; afterwards `git rev-parse -q --verify MERGE_HEAD` → rc 1, `git status --porcelain` empty, remote SHAs unchanged (measured: the recipe reproduces a real rc-1 conflict with `MERGE_HEAD` present and `--abort` clears it). Keep `$tmp` under the scratchpad, not the worktree, and never commit it.

## Success Metrics

- The next `soleur:ship` / `soleur:merge-pr` run that hits a real conflict during BEHIND auto-sync stops with the conflicted path named instead of printing `pushed` (re-eval trigger named in #8339).
- `test-scripts` stays green with the new rows; suite runtime stays ≈ 1 s (measured 1.04 s today; the new rows are all no-sleep).

## Dependencies & Risks

- **Risk: harness pipefail masking (the vacuity trap).** Mitigated by the self-check row (AC4, quoted heredoc) and by AC1 requiring the RED run before the fix. If the RED run comes back green, the subshell is still running under pipefail — stop and fix the harness, do not "fix" the block.
- **Risk: mirror drift.** The mirror is edited by hand; scenarios 6/7/8 execute against it and AC5's tokens make a half-applied fix red.
- **Risk: `printf '%s\n' "$sync_out" | tail -N` prints one empty line when `$sync_out` is empty** (`git push` with nothing to say). Cosmetic; accepted — a `[[ -n … ]]` guard is one more line for the mirror to drift on.
- **Risk: `set -u` in the fixture.** `sync_out`/`sync_rc` are always assigned before use; the mock `git` must use `${2:-}` (bare `git push`).
- **Out of scope, explicitly:** #8334 (`OUTAGE_RE` negation in the incident-PIR gate), #7472 (Phase 7 silent on non-required check failures — same block, different arm; acknowledged, not folded), #8383 (consolidating the three copies of the sync arm — ship fence, merge-pr mirror, `sync-pr-behind.sh` — into one executable, plus an optional separate fetch-failure counter; filed from the CTO plan-review).
- Depends on nothing; blocks nothing. Draft PR #8378 exists for this branch.

## Research Insights

### Premise Validation (Phase 0.6)

- #8339: OPEN, labels `type/chore`, `deferred-automation`, `meta/machinery`, `closedByPullRequestsReferences: []` — premise holds.
- #8320: MERGED 2026-09-18T23:08Z; it is the PR that measured the bug and resolved its own conflict by hand; it does not touch the fence — confirmed by the three `| tail` lines still present at `plugins/soleur/skills/ship/SKILL.md` (`if ! git fetch origin main 2>&1 | tail -2; then` … `elif ! git merge origin/main --no-edit 2>&1 | tail -5; then` … `elif ! git push 2>&1 | tail -2; then`) and `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 (`if git fetch origin main 2>&1 | tail -2 \ && git merge … | tail -5 \ && git push 2>&1 | tail -2; then`).
- Draft PR #8378 (`WIP: feat-one-shot-8339-poll-block-pipe-rc`) OPEN, isDraft, on this branch.
- Fence + extractor present: `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` `extract_block()` anchors on `<!-- phase-7-poll-block:start -->` / `:end`; suite currently 18 pass / 0 fail in 1.04 s.
- Mechanism vs ADR corpus: no ADR concerns pipe exit-status capture; `work/SKILL.md` (#7828 block) already prescribes "never pipe a command whose exit code IS the result — redirect and read `$?`", so the proposed mechanism is the repo's stated convention, not a new one.
- Monitor shell semantics measured: `bash -c 'set -o | grep pipefail'` → `pipefail off`.

### Property List / Cut List (Phase 0.6b)

Properties:

1. A failed `git merge` in the BEHIND arm is reported, aborted, and stops the poll — never "pushed".
2. A failed `git push` after a clean merge is reported as `git push failed after merge` and stops the poll.
3. A failed `git fetch` skips the attempt (counted) without stopping the poll.
4. The fixture observes the block under the Monitor shell's semantics (pipefail off), so it is RED on the current block.
5. Canonical and mirror carry the same sync arm (no drift).

Mechanisms kept: explicit rc capture (buys 1–3; nothing on `origin/main` buys them — grepped both fences, both blocks pipe to `tail`); `set +o pipefail` in the scenario subshell + a quoted-heredoc self-check row (buys 4; the harness today sets pipefail ON and nothing turns it off — grepped `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`); scenarios 6/7/8 executed against both blocks + four added parity tokens (buys 5 behaviourally; the existing parity check is token-only and the mirror is not executed — its own comment says so).

Cut list: block-level `set -o pipefail` → properties 1–3 → cut, changes every other pipe in a block two skills copy (issue agrees). Helper function `_tail_rc` → properties 1–3 → cut, same line count as inline and one more name to drift. Call-count assertions on the mock → property 1 → cut, counters are lost inside `$( … )`. **Cut at plan-review (v2):** a checked-in negative-control copy of the buggy block → property 4 → cut, same property as the self-check row at ~30× the cost, and every other vacuity cause also reddens the live rows (DHH P1, simplicity #5); a comment-stripped `diff` of the two sync arms → property 5 → cut into four parity tokens, the executed scenarios are the behavioural parity check (DHH P1, simplicity #6, Kieran #2/#3); a negative-shape grep guard (`git (fetch|merge|push)… | tail`) → no listed property → cut, quantified over exactly the three commands the scenarios exercise (DHH P2, simplicity #7); an `errexit` half of the self-check → property 4 → cut, under `-e` the live rows redden on their own (simplicity #3); aligning the mirror's echo lines with the canonical → no listed property → cut (simplicity #9).

### Prototype measurements (scratchpad, 2026-09-19)

| Block | pipefail | scenario 6 | scenario 7 |
|---|---|---|---|
| current ship | off | RED | RED |
| current ship | on | GREEN (vacuity trap) | GREEN |
| fixed ship | off | GREEN | GREEN |
| fixed ship | on | GREEN | GREEN |
| current merge-pr | off | RED | RED |
| fixed merge-pr | off | GREEN | GREEN |

Existing 18 assertions under `set +o pipefail`: 18 pass.

### Repo research

- CI wiring: `scripts/test-all.sh:78` glob `'plugins/soleur/test/*.test.sh'`, group `scripts`; `scripts/lint-orphan-test-suites.sh` derives globs from `test-all.sh` — editing an existing suite needs no registration.
- Local idiom for capture-then-display: `mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"` in the same block (both files); `out=$(cmd 2>&1) && rc=0 || rc=$?` in `apps/cla-evidence/scripts/inspect.test.sh`.
- No doc outside the two SKILL.md files quotes the sync-arm lines verbatim.
- `plugins/soleur/lib/pr-merge-poll.ts` line 71: AwaitShell wake pattern `BEHIND detected|auto-sync.*pushed|BEHIND resolved|BEHIND unchanged|merge conflict` — the new merge-failure message includes `merge conflict` so Grok wakes on it.
- `plugins/soleur/scripts/sync-pr-behind.sh` lines 54/70/77 have the same pipe shape but under `set -euo pipefail` (line 10) — not a defect; research claim corrected by reading the file. Third copy of the arm → #8383.
- Retroactive-application rule body: `plugins/soleur/skills/ship/SKILL.md` §5.5 (`wg-when-fixing-a-workflow-gates-detection`) — "gate fixed AND missed case remediated"; the issue itself asks for the re-run.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` (#7828) — `cmd | tail` takes the pipe's status and destroys the evidence; read `$?` immediately after the command whose status matters.
- `knowledge-base/project/learnings/2026-05-15-red-tests-for-extractors-must-use-covered-code-path.md` — a RED fixture must inject the failure on the path the implementation actually reads; here that path is "pipefail off", which the harness did not provide.
- `knowledge-base/project/learnings/2026-03-14-bare-repo-helper-extraction-patterns.md` — subshells inherit the parent's `set` state; scope the override inside `( … )`.
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — toggling pipefail block-wide changes `grep`-in-pipeline semantics; the reason block-level pipefail was cut.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — harness rows and the ORDER row (matrix row 7) come from these; Kieran's heredoc-expansion finding is a fresh instance of the same class.
- `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` — `git merge --abort` is the safe recovery; never stash mid-merge (the arm keeps `--abort`).

### Scoped advisor consult (Phase 4.5, ADR-083) and plan-review (v1 → v2)

Advisor (curated payload): explicit capture is the right architecture; four suggestions (negative-control fixture, arm-diff parity, retroactive observables, errexit self-check). Plan-review then cut three of the four as redundant with the executed scenarios (see Cut list); the retroactive observables (`MERGE_HEAD` absent, porcelain empty, remote SHAs unchanged) stayed in AC11. Kieran plan-review found the self-check's unquoted-heredoc vacuity (fixed: quoted heredoc, row H4), the multi-line `run_scenario` grep form (fixed: AC6), the stdout-vs-stderr sentinel trap, and the exact mock dispatch patterns (folded into Technical Considerations). DHH's `-q` rewrite and the CTO's message-tag/next-step additions are User-Challenge / Taste and are recorded in `knowledge-base/project/specs/feat-one-shot-8339-poll-block-pipe-rc/decision-challenges.md`, not applied.

### Functional overlap (Phase 1.5b)

Registries queried (2/3 reachable): `ship` (composio-community) and `github-triage` (trailofbits) overlap architecturally (PR lifecycle automation), not functionally with this bug fix. Nothing installed. Community discovery (1.5): no uncovered stack (bash + TypeScript repo).

## Open Code-Review Overlap

None — 65 open `code-review` issues scanned; none cite `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/merge-pr/SKILL.md`, or `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`. Adjacent open issues on the same block, acknowledged and not folded: #7472 (non-required check failures are silent — different arm), #8334 (`OUTAGE_RE` negation — explicitly out of scope per the run mandate), #8383 (filed by this plan — consolidation of the three sync-arm copies).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a bash block inside two engineering skills plus its fixture; no user-facing surface, no data, no vendor).

## References & Research

- Issue #8339; found on PR #8320 (merged 2026-09-18). Follow-up: #8383.
- Canonical block: `plugins/soleur/skills/ship/SKILL.md` (`<!-- phase-7-poll-block:start -->` fence, BEHIND arm).
- Mirror: `plugins/soleur/skills/merge-pr/SKILL.md` §5.2.
- Fixture: `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (`extract_block()`, `run_scenario()`, mirror-parity token list).
- Convention: `plugins/soleur/skills/work/SKILL.md` #7828 block ("never pipe a command whose exit code IS the result").
- Grok wake pattern: `plugins/soleur/lib/pr-merge-poll.ts` (`pollInstructions()`).
- Retroactive rule: `plugins/soleur/skills/ship/SKILL.md` §5.5 `wg-when-fixing-a-workflow-gates-detection`.
